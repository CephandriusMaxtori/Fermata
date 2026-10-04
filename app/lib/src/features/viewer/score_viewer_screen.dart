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

  /// Whether detection has run, and what it found.
  ///
  /// Null until the first detection finishes, which is also how the footer knows
  /// to show a spinner rather than claiming a bar count it does not have.
  ///
  /// This is deliberately *not* the same field as whether bar mode is on. They
  /// were one flag, which meant switching bar mode off wrote `false` here and the
  /// footer read that as "detection found no staff": one round trip through the
  /// toggle threw away what detection had learned. That was issue #5.
  bool? _detection;

  /// Whether the footer steps by bar instead of by page.
  ///
  /// Only ever true when detection found bars, so the viewer cannot offer bar
  /// stepping on a score where there is nothing to step to.
  bool _barMode = false;

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

    // `firstNavigable`, not `BarCursor.start`: the first page of a score is
    // often a title page with no staff on it, and parking the cursor on a bar
    // that does not exist is what made the very next frame throw. See #5.
    final navigable = BarNavigator.isNavigable(_orderedLayouts(pages));
    final cursor = BarNavigator.firstNavigable(_orderedLayouts(pages));

    setState(() {
      _detection = navigable;
      _barMode = navigable;
      _cursor = cursor;
    });
  }

  /// Runs detection, treating any failure as "nothing found".
  ///
  /// The footer reads `null` as "still looking", so an escaping exception would
  /// strand it on "Looking for bars..." for good. Landing on `false` instead
  /// means the viewer falls back to page turning, which is what it would have
  /// done anyway had the scan simply yielded no text.
  Future<void> _runDetection(List<ScorePage> pages) async {
    try {
      await _detectBars(pages);
    } on Object {
      if (!mounted) return;
      setState(() {
        _detection = false;
        _barMode = false;
      });
    }
  }

  /// [_barLayouts] in page order, for [BarNavigator].
  ///
  /// Indexed by position rather than looked up by [ScorePage.indexOf]: the pages
  /// list is already in order, and `indexOf` compares by value, so two identical
  /// pages would resolve to the first one every time.
  List<BarLayout> _orderedLayouts(List<ScorePage> pages) => [
    for (var i = 0; i < pages.length; i++)
      _barLayouts[i] ?? BarLayout.empty,
  ];

  /// Scrolls so [cursor]'s bar is the music in view.
  ///
  /// Both axes matter and they are coupled. Horizontally the bar's *left* edge
  /// is aligned to the left of the screen, so every step lands the music you are
  /// about to read in the same place. Vertically the *system* the bar is in is
  /// brought near the top, because a step that crosses into the next system of
  /// the same page has to move the view at all — the bar itself may already be
  /// on screen.
  ///
  /// The transform is rebuilt from identity rather than composed onto the
  /// current one: bar positions are page fractions, so a leftover pinch would
  /// scale the offset into the wrong place, and a leftover drag would compound.
  void _scrollToCursor() {
    // The layout comes from the *cursor's* page, not the page currently on
    // screen. They are not always the same: switching bar mode on resets the
    // cursor to the first bar of the score while `PageView` stays wherever the
    // user was, so reading the current page's layout here indexed it with
    // another page's system and bar and tripped `barRange`'s assert. That was
    // the second half of #5, and the half that needed an actual mode switch to
    // reach.
    final layout = _barLayouts[_cursor.pageIndex] ?? BarLayout.empty;
    if (_cursor.systemIndex >= layout.systems.length) return;
    final system = layout.systems[_cursor.systemIndex];
    if (_cursor.barIndex >= system.barCount) return;
    final range = system.barRange(_cursor.barIndex);

    final size = context.size;
    if (size == null || size.isEmpty) return;

    // The page is letterboxed into the viewport, so a fraction of the *page* is
    // not a fraction of the *screen*. Clamping to the viewport is what stops a
    // bar in the right-hand margin from scrolling the page off screen.
    final dx = (range.start * size.width).clamp(0.0, size.width);
    final dy = (system.bounds.top * size.height).clamp(0.0, size.height);
    _transformController.value =
        Matrix4.identity()..translateByDouble(dx, dy, 0, 1);
  }

  /// Switches between page stepping and bar stepping.
  ///
  /// Turning bar mode *on* resets the cursor to the start of the score: the
  /// layouts may have just been discovered, and carrying a cursor from a previous
  /// session's guess would put the first bar step somewhere arbitrary. Turning
  /// it off keeps the cursor, so switching back resumes where the user was.
  void _toggleBarMode(List<ScorePage> pages) {
    final enabling = !_barMode;
    if (enabling && !BarNavigator.isNavigable(_orderedLayouts(pages))) return;

    // `firstNavigable`, not `BarCursor.start`. Detection finding nothing used to
    // leave the footer still offering "By bar", and enabling bar mode there
    // parked a cursor on a score with no bars in it at all, which threw on the
    // next frame. Refusing the switch keeps that state unreachable rather than
    // merely unlikely.
    final cursor = enabling
        ? BarNavigator.firstNavigable(_orderedLayouts(pages))
        : _cursor;

    setState(() {
      _barMode = enabling;
      _cursor = cursor;
    });
    if (enabling) _transformController.value = Matrix4.identity();
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
    _scrollToCursor();
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
                barMode: _detection,
                barStepping: _barMode,
                cursor: _cursor,
                layouts: _orderedLayouts(pages),
                onStep: _step,
                onStepBar: (delta) => _stepBar(delta, pages),
                onJump: _jumpTo,
                onDetect: () => _runDetection(pages),
                onToggleMode: () => _toggleBarMode(pages),
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
        if (_barMode) {
          _stepBar(-1, pages);
        } else {
          _step(-1);
        }
      case TapZone.next:
        if (_barMode) {
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
    required this.barStepping,
    required this.cursor,
    required this.layouts,
    required this.onStep,
    required this.onStepBar,
    required this.onJump,
    required this.onDetect,
    required this.onToggleMode,
  });

  final int currentPage;
  final int pageCount;
  final bool drawingMode;

  /// Null while detection has not run yet.
  final bool? barMode;

  /// Whether the footer is stepping by bar right now. Distinct from [barMode],
  /// which reports whether bars were *found*.
  final bool barStepping;
  final BarCursor cursor;
  final List<BarLayout> layouts;
  final ValueChanged<int> onStep;
  final ValueChanged<int> onStepBar;
  final ValueChanged<int> onJump;
  final VoidCallback onDetect;
  final VoidCallback onToggleMode;

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
              barStepping: barStepping,
              cursor: cursor,
              layouts: layouts,
              onStepPage: onStep,
              onStepBar: onStepBar,
              onJumpToPage: onJump,
              onDetect: onDetect,
              onToggleMode: onToggleMode,
            ),
    );
  }
}



