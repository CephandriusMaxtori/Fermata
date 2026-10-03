import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';
import '../library/library_screen.dart';
import 'bar_navigation_bar.dart';
import 'brush_toolbar.dart';
import 'page_stack.dart';

/// The score viewer.
///
/// The page raster and the annotation overlay are siblings inside one [Stack],
/// and that [Stack] is what the zoom transforms. Because both layers resolve
/// their geometry through the same box, ink cannot drift out of alignment with
/// the music at any zoom, density or orientation.
class ScoreViewerScreen extends ConsumerStatefulWidget {
  const ScoreViewerScreen({
    super.key,
    required this.scoreId,
    required this.title,
  });

  final String scoreId;
  final String title;

  @override
  ConsumerState<ScoreViewerScreen> createState() => _ScoreViewerScreenState();
}

/// Bar navigation is opt-in via a control rather than automatic on open.
///
/// Two reasons. Bar detection reads the text layer of every page up front, which
/// is real work on a long score, and it has to happen before the first step can
/// be trusted. And on a score with no text layer it finds nothing, so running it
/// by default would mean every scan gets a "Looking for bars…" wait for no
/// benefit. The viewer is page-based until asked otherwise.
class _ScoreViewerScreenState extends ConsumerState<ScoreViewerScreen> {
  late final TransformationController _transformController;
  late final PageController _pageController;
  int _currentPage = 0;
  bool _drawingMode = false;

  /// Whether the footer steps by bar instead of by page.
  ///
  /// Null until the first detection finishes, which is also how the footer knows
  /// to show a spinner rather than claiming a bar count it does not have.
  bool? _barMode;
  BarCursor _cursor = BarCursor.start;

  /// Bar layouts per page index, filled in as detection completes.
  ///
  /// Kept as a map rather than a list because pages arrive out of order and a
  /// hole has to be distinguishable from "no staff on this page".
  final Map<int, BarLayout> _barLayouts = {};

  

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _transformController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Asks the renderer for each page's bars, filling [barMode] in when they all
  /// answer.
  ///
  /// Deliberately all pages up front rather than the visible one on demand:
  /// stepping backwards off the front of a page has to know the last bar of the
  /// page before it, and discovering that only when the user steps back is how a
  /// control ends up enabled but dead.
  Future<void> _detectBars(List<ScorePage> pages) async {
    final renderer = await ref.read(pageRendererProvider.future);
    if (!mounted) return;

    final layouts = <int, BarLayout>{};
    for (final (index, page) in pages.indexed) {
      layouts[index] = await renderer.barLayout(page);
      if (!mounted) return;
    }

    _barLayouts
      ..clear()
      ..addAll(layouts);

    setState(() {
      _barMode = BarNavigator.isNavigable(_orderedLayouts(pages));
      _cursor = BarCursor.start;
    });
  }

  /// [_barLayouts] in page order, for [BarNavigator].
  ///
  /// Missing entries are treated as staff-less rather than skipped, so the
  /// indices in a cursor line up with the page indices.
  List<BarLayout> _orderedLayouts(List<ScorePage> pages) => [
    for (final page in pages)
      _barLayouts[pages.indexOf(page)] ?? BarLayout.empty,
  ];

  /// The current page's bars.
  BarLayout _currentLayout(List<ScorePage> pages) =>
      _barLayouts[_currentPage] ?? BarLayout.empty;

  /// Scrolls the page so [cursor]'s bar is in view.
  ///
  /// The bar's left edge is what gets aligned, so a step always puts the music
  /// you are about to read at the same place on the screen. Resetting the zoom
  /// first matters: bar positions are page fractions, so an inherited pinch would
  /// scroll to the wrong offset.
  void _scrollToCursor(List<ScorePage> pages) {
    final layout = _currentLayout(pages);
    if (_cursor.systemIndex >= layout.systems.length) return;
    final system = layout.systems[_cursor.systemIndex];
    final range = system.barRange(_cursor.barIndex);

    final size = context.size;
    if (size == null || size.isEmpty) return;

    // Fraction of the page the bar starts at, mapped into the viewport. The
    // page fills the viewport at rest, so the fraction *is* the offset — but
    // clamped so a bar in the right-hand margin cannot scroll the page away.
    final dx = (range.start * size.width).clamp(0.0, size.width);
    _transformController.value =
        Matrix4.identity()..translateByDouble(dx, 0, 0, 1);
  }

  void _stepBar(int delta, List<ScorePage> pages) {
    final layouts = _orderedLayouts(pages);
    final next = delta > 0
        ? BarNavigator.forward(_cursor, layouts)
        : BarNavigator.back(_cursor, layouts);
    if (next == _cursor) return;

    final pageChanged = next.pageIndex != _cursor.pageIndex;
    setState(() => _cursor = next);

    if (pageChanged) {
      _transformController.value = Matrix4.identity();
      _pageController.animateToPage(
        next.pageIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _scrollToCursor(pages);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pagesValue = ref.watch(scorePagesProvider(widget.scoreId));

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _drawingMode ? 'Done annotating' : 'Annotate',
            isSelected: _drawingMode,
            onPressed: pagesValue.maybeWhen(
              data: (pages) => pages.isEmpty
                  ? null
                  : () => setState(() => _drawingMode = !_drawingMode),
              orElse: () => null,
            ),
            icon: Icon(
              _drawingMode ? Icons.draw_rounded : Icons.edit_outlined,
            ),
          ),
        ],
      ),
      body: switch (pagesValue) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('This score has no pages.'),
        ),
        AsyncData(:final value) => Stack(
          children: [
            PageStack(
              pages: value,
              pageController: _pageController,
              transformationController: _transformController,
              drawingMode: _drawingMode,
              onPageChanged: (index) => setState(() => _currentPage = index),
              onTapZone: (zone) => _onTapZone(zone, value),
              onStrokeCompleted: _persistStroke,
            ),
            if (_drawingMode) const _DrawingHint(),
          ],
        ),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: pagesValue.maybeWhen(
        data: (pages) => pages.isEmpty
            ? null
            : _ViewerFooter(
                currentPage: _currentPage,
                pageCount: pages.length,
                drawingMode: _drawingMode,
                barMode: _barMode,
                cursor: _cursor,
                layouts: _orderedLayouts(pages),
                onStep: _step,
                onStepBar: (delta) => _stepBar(delta, pages),
                onJump: _jumpTo,
                onDetect: () => _detectBars(pages),
              ),
        orElse: () => null,
      ),
    );
  }

  /// Steps the page when bar mode is off.
  void _step(int delta) {
    final pages = ref.read(scorePagesProvider(widget.scoreId)).value;
    if (pages == null || !_pageController.hasClients) return;
    final target = (_currentPage + delta).clamp(0, pages.length - 1);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpTo(int index) {
    if (!_pageController.hasClients) return;
    _transformController.value = Matrix4.identity();
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Tapping the outer thirds of the page steps forward.
  ///
  /// Bluetooth pedal support arrives in a later milestone as key events, and not
  /// every musician will have one, so a tap target is always available.
  ///
  /// In bar mode a tap steps one bar; otherwise one page. Same gesture, so
  /// nothing about reaching for the page changes when the mode does.
  void _onTapZone(TapZone zone, List<ScorePage> pages) {
    switch (zone) {
      case TapZone.previous:
        if (_barMode ?? false) {
          _stepBar(-1, pages);
        } else {
          _step(-1);
        }
      case TapZone.next:
        if (_barMode ?? false) {
          _stepBar(1, pages);
        } else {
          _step(1);
        }
      case TapZone.none:
        break;
    }
  }

  Future<void> _persistStroke(Stroke stroke) async {
    final repository = await ref.read(annotationRepositoryProvider.future);
    await repository.upsertStroke(stroke);
  }
}

class _DrawingHint extends StatelessWidget {
  const _DrawingHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.inverseSurface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'Drag to annotate',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the page sits on screen, needed to turn a bar fraction into pixels.
class _ViewerFooter extends ConsumerWidget {
  const _ViewerFooter({
    required this.currentPage,
    required this.pageCount,
    required this.drawingMode,
    required this.barMode,
    required this.cursor,
    required this.layouts,
    required this.onStep,
    required this.onStepBar,
    required this.onJump,
    required this.onDetect,
  });

  final int currentPage;
  final int pageCount;
  final bool drawingMode;

  /// Null while detection has not run yet.
  final bool? barMode;
  final BarCursor cursor;
  final List<BarLayout> layouts;
  final ValueChanged<int> onStep;
  final ValueChanged<int> onStepBar;
  final ValueChanged<int> onJump;
  final VoidCallback onDetect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: drawingMode
          ? BrushToolbar(
              selection: ref.watch(brushProvider),
              onChanged: (value) =>
                  ref.read(brushProvider.notifier).select(value),
            )
          : BarNavigationBar(
              currentPage: currentPage,
              pageCount: pageCount,
              barMode: barMode,
              cursor: cursor,
              layouts: layouts,
              onStepPage: onStep,
              onStepBar: onStepBar,
              onJumpToPage: onJump,
              onDetect: onDetect,
            ),
    );
  }
}



