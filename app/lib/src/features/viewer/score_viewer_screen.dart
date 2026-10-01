import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';
import '../library/library_screen.dart';
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

class _ScoreViewerScreenState extends ConsumerState<ScoreViewerScreen> {
  late final TransformationController _transformController;
  late final PageController _pageController;
  int _currentPage = 0;
  bool _drawingMode = false;

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
              onTapZone: _onTapZone,
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
                onStep: _step,
                onJump: _jumpTo,
              ),
        orElse: () => null,
      ),
    );
  }

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
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Tapping the outer thirds of the page turns it.
  ///
  /// Bluetooth pedal support arrives in a later milestone as key events, and
  /// not every musician will have one, so a tap target is always available.
  void _onTapZone(TapZone zone) {
    switch (zone) {
      case TapZone.previous:
        _step(-1);
      case TapZone.next:
        _step(1);
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

class _ViewerFooter extends ConsumerWidget {
  const _ViewerFooter({
    required this.currentPage,
    required this.pageCount,
    required this.drawingMode,
    required this.onStep,
    required this.onJump,
  });

  final int currentPage;
  final int pageCount;
  final bool drawingMode;
  final ValueChanged<int> onStep;
  final ValueChanged<int> onJump;

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
          : _PageBar(
              currentPage: currentPage,
              pageCount: pageCount,
              onStep: onStep,
              onJump: onJump,
            ),
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.currentPage,
    required this.pageCount,
    required this.onStep,
    required this.onJump,
  });

  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onStep;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: currentPage > 0 ? () => onStep(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          TextButton(
            onPressed: () => _showPagePicker(context),
            child: Text('${currentPage + 1} / $pageCount'),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: currentPage < pageCount - 1 ? () => onStep(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  void _showPagePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: pageCount,
          itemBuilder: (_, index) => ListTile(
            title: Text('Page ${index + 1}'),
            selected: index == currentPage,
            onTap: () {
              onJump(index);
              Navigator.of(sheetContext).pop();
            },
          ),
        ),
      ),
    );
  }
}
