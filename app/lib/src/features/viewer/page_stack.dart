import 'dart:ui' as ui;

import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';
import 'annotation_painter.dart';
import 'brush_toolbar.dart';
import 'page_renderer.dart';
import 'pdfrx_page_renderer.dart';

/// The pen or highlighter currently selected.
final brushProvider = NotifierProvider<BrushNotifier, BrushSelection>(
  BrushNotifier.new,
);

class BrushNotifier extends Notifier<BrushSelection> {
  @override
  BrushSelection build() =>
      const BrushSelection(color: 0xFFD32F2F, width: 0.006);

  void select(BrushSelection selection) => state = selection;
}

/// The stroke currently under the user's finger.
///
/// Held outside the database so drawing stays responsive: the painter shows
/// this immediately and a single row is written when the finger lifts.
final liveStrokeProvider =
    NotifierProvider<LiveStrokeNotifier, List<StrokePoint>>(
      LiveStrokeNotifier.new,
    );

class LiveStrokeNotifier extends Notifier<List<StrokePoint>> {
  @override
  List<StrokePoint> build() => const [];

  void begin(NormalizedPoint point) =>
      state = [StrokePoint(position: point)];

  void extend(NormalizedPoint point) =>
      state = [...state, StrokePoint(position: point)];

  void clear() => state = const [];
}

/// The layer new ink lands on.
///
/// v1 has no layer picker yet, so this is the score's first visible layer.
/// Resolving it here rather than in the widget means multi-layer support drops
/// in without restructuring the page.
final activeLayerProvider = FutureProvider.autoDispose
    .family<AnnotationLayer?, String>((ref, scoreId) async {
      final repository = await ref.watch(annotationRepositoryProvider.future);
      final layers = await repository.getLayers(scoreId);
      if (layers.isEmpty) return null;
      return layers.firstWhere((l) => l.visible, orElse: () => layers.first);
    });

/// Identifies one page of one score.
typedef PageRef = ({String scoreId, int pageIndex});

/// Committed ink on a page, limited to the visible layers.
///
/// A stream, not a future: a stroke is persisted after the finger lifts, so a
/// one-shot read leaves the overlay showing the state from before the last mark
/// and nothing appears until the widget is rebuilt. `watchStrokes` re-emits
/// whenever the annotations table changes.
final strokesForPageProvider = StreamProvider.autoDispose
    .family<List<Stroke>, PageRef>((ref, key) async* {
      final repository = await ref.watch(annotationRepositoryProvider.future);
      // Layer visibility is streamed too, so hiding a layer redraws without
      // needing the page to be rebuilt.
      await for (final layers in repository.watchLayers(key.scoreId)) {
        final visible = layers.where((l) => l.visible).map((l) => l.id).toSet();
        yield* repository.watchStrokes(
          scoreId: key.scoreId,
          pageIndex: key.pageIndex,
          layerIds: visible,
        );
      }
    });

/// Rasterises pages with pdfrx.
///
/// Async because it needs the file store, and the library root is only known
/// once path_provider has answered.
final pageRendererProvider = FutureProvider.autoDispose<PageRenderer>((
  ref,
) async {
  final store = await ref.watch(fileStoreProvider.future);
  final renderer = PdfrxPageRenderer(store);
  ref.onDispose(renderer.clear);
  return renderer;
});

/// Paged view of a score, with pan and zoom wrapping the whole thing.
class PageStack extends ConsumerWidget {
  const PageStack({
    super.key,
    required this.pages,
    required this.pageController,
    required this.transformationController,
    required this.drawingMode,
    required this.onPageChanged,
    required this.onTapZone,
    required this.onStrokeCompleted,
  });

  final List<ScorePage> pages;
  final PageController pageController;
  final TransformationController transformationController;
  final bool drawingMode;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<TapZone> onTapZone;
  final ValueChanged<Stroke> onStrokeCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(pageRendererProvider)
        .when(
          data: (renderer) => _buildStack(context, renderer),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
        );
  }

  Widget _buildStack(BuildContext context, PageRenderer renderer) {
    return InteractiveViewer(
      transformationController: transformationController,
      // Panning belongs to the page while reading and to the pen while
      // annotating. Pinch zoom stays live in both, because inspecting a
      // fingering still needs zooming without leaving the pen.
      panEnabled: !drawingMode,
      scaleEnabled: true,
      minScale: 1,
      maxScale: 6,
      child: PageView.builder(
        controller: pageController,
        onPageChanged: onPageChanged,
        itemCount: pages.length,
        itemBuilder: (context, index) => ScorePageView(
          page: pages[index],
          renderer: renderer,
          drawingMode: drawingMode,
          onTapZone: onTapZone,
          onStrokeCompleted: onStrokeCompleted,
        ),
      ),
    );
  }
}

/// One page: the raster and its ink, sharing a single box.
class ScorePageView extends ConsumerStatefulWidget {
  const ScorePageView({
    super.key,
    required this.page,
    required this.renderer,
    required this.drawingMode,
    required this.onTapZone,
    required this.onStrokeCompleted,
  });

  final ScorePage page;
  final PageRenderer renderer;
  final bool drawingMode;
  final ValueChanged<TapZone> onTapZone;
  final ValueChanged<Stroke> onStrokeCompleted;

  @override
  ConsumerState<ScorePageView> createState() => _ScorePageViewState();
}

class _ScorePageViewState extends ConsumerState<ScorePageView> {
  ui.Image? _image;
  Size _logicalSize = Size.zero;
  bool _pending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  @override
  void didUpdateWidget(ScorePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) {
      widget.renderer.evict(oldWidget.page);
      _image = null;
      _logicalSize = Size.zero;
      _pending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _render());
    }
  }

  @override
  void dispose() {
    widget.renderer.evict(widget.page);
    super.dispose();
  }

  Future<void> _render() async {
    if (!mounted || !_pending) return;

    // context.size is null until the first layout pass. The render is kicked
    // off from a post-frame callback precisely so a size is available by then,
    // but bail out rather than risk a zero-sized render box.
    final available = context.size;
    if (available == null || available.isEmpty) return;

    // Read the pixel ratio before the first await; touching context after an
    // async gap is unsafe even when the State is still mounted.
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    final geometry = await widget.renderer.geometry(widget.page);
    final image = await widget.renderer.render(
      widget.page,
      maxSize: available,
      pixelRatio: pixelRatio,
    );
    if (!mounted) return;

    final fitted = geometry?.fitWithin(
          availableWidth: available.width,
          availableHeight: available.height,
        ) ??
        (width: available.width, height: available.height);

    setState(() {
      _image = image;
      _logicalSize = Size(fitted.width, fitted.height);
      _pending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageRef = (
      scoreId: widget.page.scoreId,
      pageIndex: widget.page.index,
    );
    final strokes =
        ref.watch(strokesForPageProvider(pageRef)).value ?? const <Stroke>[];
    final live = ref.watch(liveStrokeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.drawingMode
              ? null
              : (details) => _reportTap(details.localPosition, box),
          onPanStart: widget.drawingMode
              ? (details) => _beginStroke(details.localPosition, box)
              : null,
          onPanUpdate: widget.drawingMode
              ? (details) => _extendStroke(details.localPosition, box)
              : null,
          onPanEnd: widget.drawingMode ? (_) => _commitStroke() : null,
          child: Center(
            child: SizedBox(
              width: _logicalSize.width,
              height: _logicalSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_image != null)
                    RawImage(image: _image, fit: BoxFit.fill)
                  else
                    const ColoredBox(color: Colors.white),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: AnnotationPainter(
                        strokes: strokes,
                        size: _logicalSize,
                        liveStroke: live.isEmpty ? null : live,
                      ),
                      size: _logicalSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tapping the outer thirds of the page turns it.
  ///
  /// This is the fallback the design calls for alongside Bluetooth pedal
  /// support: pedals arrive as key events and are not always present, so there
  /// is always a way to turn the page with a thumb.
  void _reportTap(Offset local, Size box) {
    if (box.isEmpty) return;
    final third = box.width / 3;
    if (local.dx < third) {
      widget.onTapZone(TapZone.previous);
    } else if (local.dx > box.width - third) {
      widget.onTapZone(TapZone.next);
    } else {
      widget.onTapZone(TapZone.none);
    }
  }

  void _beginStroke(Offset local, Size box) {
    if (box.isEmpty) return;
    ref
        .read(liveStrokeProvider.notifier)
        .begin(_normalized(local, box));
  }

  void _extendStroke(Offset local, Size box) {
    if (box.isEmpty) return;
    ref.read(liveStrokeProvider.notifier).extend(_normalized(local, box));
  }

  NormalizedPoint _normalized(Offset local, Size box) =>
      NormalizedPoint.fromPixels(
        x: local.dx,
        y: local.dy,
        renderWidth: box.width,
        renderHeight: box.height,
      );

  Future<void> _commitStroke() async {
    final live = ref.read(liveStrokeProvider);
    if (live.length < 2) {
      ref.read(liveStrokeProvider.notifier).clear();
      return;
    }

    final brush = ref.read(brushProvider);
    final layer = await ref.read(
      activeLayerProvider(widget.page.scoreId).future,
    );
    if (layer == null) {
      // No layer to attach ink to. Drop the stroke rather than write a row that
      // would violate the foreign key on annotations.layer_id.
      ref.read(liveStrokeProvider.notifier).clear();
      return;
    }

    widget.onStrokeCompleted(
      Stroke(
        id: _newStrokeId(),
        scoreId: widget.page.scoreId,
        pageIndex: widget.page.index,
        layerId: layer.id,
        kind: brush.kind,
        colorValue: brush.color,
        widthFraction: brush.width,
        points: StrokeConditioner.finalize(
          live,
          minDistance: 0.002,
          simplifyTolerance: 0.0015,
        ),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    ref.read(liveStrokeProvider.notifier).clear();
  }
}

int _strokeCounter = 0;

String _newStrokeId() {
  _strokeCounter++;
  final micros = DateTime.now()
      .toUtc()
      .microsecondsSinceEpoch
      .toRadixString(36);
  return '$micros-${_strokeCounter.toRadixString(36)}';
}
