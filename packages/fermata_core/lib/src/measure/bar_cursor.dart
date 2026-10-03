import 'bar_layout.dart';

/// Where bar-by-bar navigation currently is.
///
/// One place per bar in a score: page, system within that page, and bar within
/// that system. Modelled as a value type with [copyWith] so the viewer can hold
/// it in state without worrying about identity.
class BarCursor {
  const BarCursor({
    required this.pageIndex,
    required this.systemIndex,
    required this.barIndex,
  });

  /// The first bar of the first system of the first page.
  static const BarCursor start = BarCursor(
    pageIndex: 0,
    systemIndex: 0,
    barIndex: 0,
  );

  final int pageIndex;
  final int systemIndex;
  final int barIndex;

  BarCursor copyWith({int? pageIndex, int? systemIndex, int? barIndex}) =>
      BarCursor(
        pageIndex: pageIndex ?? this.pageIndex,
        systemIndex: systemIndex ?? this.systemIndex,
        barIndex: barIndex ?? this.barIndex,
      );

  @override
  bool operator ==(Object other) =>
      other is BarCursor &&
      other.pageIndex == pageIndex &&
      other.systemIndex == systemIndex &&
      other.barIndex == barIndex;

  @override
  int get hashCode => Object.hash(pageIndex, systemIndex, barIndex);

  @override
  String toString() =>
      'BarCursor(page $pageIndex, system $systemIndex, bar $barIndex)';
}

/// Steps a [BarCursor] through the bars of a score.
///
/// Pure logic over per-page [BarLayout]s, with no Flutter and no PDF, so the
/// stepping rules can be tested directly. That matters here because the rules are
/// where this feature actually lives: crossing a bar, a system and a page are
/// three different transitions, and a one-off in any of them is an off-by-one
/// that only shows up on a real score.
///
/// ## Why this is not an index into a flat list
///
/// An earlier version of this idea counted bars across the whole score and
/// stepped that number. It is simpler, and wrong in a way that is hard to see:
/// the layouts are discovered per page and asynchronously, so a flat count has to
/// be rebuilt whenever any page finishes loading, and the cursor has to be
/// re-based onto it. Carrying `(page, system, bar)` instead means a step is
/// always "what is the next sibling of where I already am", which needs no
/// global index and no re-basing.
abstract final class BarNavigator {
  /// The cursor one bar forward, clamped at the end of the score.
  ///
  /// Returns [cursor] unchanged at the end rather than wrapping, so a held pedal
  /// at the last bar does not silently restart the piece.
  static BarCursor forward(
    BarCursor cursor,
    List<BarLayout> layouts,
  ) {
    final page = layouts[cursor.pageIndex];
    final system = page.systems[cursor.systemIndex];

    if (cursor.barIndex + 1 < system.barCount) {
      return cursor.copyWith(barIndex: cursor.barIndex + 1);
    }
    if (cursor.systemIndex + 1 < page.systems.length) {
      return cursor.copyWith(systemIndex: cursor.systemIndex + 1, barIndex: 0);
    }

    // Pages with no staff are skipped rather than stepped into, because there is
    // no bar to land on there. `copyWith` cannot do this: the system and bar
    // indices must be *reset*, and null means "leave alone".
    for (var next = cursor.pageIndex + 1; next < layouts.length; next++) {
      final layout = layouts[next];
      if (layout.systems.isEmpty) continue;
      return BarCursor(pageIndex: next, systemIndex: 0, barIndex: 0);
    }
    return cursor;
  }

  /// The cursor one bar back, clamped at the start of the score.
  ///
  /// Note that crossing *into* a new system lands on its last bar, not its
  /// first. Going forward from bar 2 of system 1 reaches bar 1 of system 2, so
  /// coming back has to arrive at bar 2 of system 1 — otherwise a second reverse
  /// step would skip a bar, which is the kind of asymmetry that makes hands-free
  /// page turning feel broken.
  static BarCursor back(BarCursor cursor, List<BarLayout> layouts) {
    if (cursor.pageIndex < 0 || cursor.pageIndex >= layouts.length) {
      return cursor;
    }

    final page = layouts[cursor.pageIndex];
    if (cursor.systemIndex >= page.systems.length) return cursor;

    if (cursor.barIndex > 0) {
      return cursor.copyWith(barIndex: cursor.barIndex - 1);
    }
    if (cursor.systemIndex > 0) {
      final previous = page.systems[cursor.systemIndex - 1];
      return cursor.copyWith(
        systemIndex: cursor.systemIndex - 1,
        barIndex: previous.barCount - 1,
      );
    }
    // Mirrors `forward`'s skipping of pages with no staff, so the two stay
    // symmetrical: forward past them, back past them.
    for (var previous = cursor.pageIndex - 1; previous >= 0; previous--) {
      final layout = layouts[previous];
      if (layout.systems.isEmpty) continue;
      final lastSystem = layout.systems.last;
      if (lastSystem.barCount == 0) continue;
      return BarCursor(
        pageIndex: previous,
        systemIndex: layout.systems.length - 1,
        barIndex: lastSystem.barCount - 1,
      );
    }
    return cursor;
  }

  /// Where [cursor] sits in the score as a 1-based display number, and the total.
  ///
  /// Counts every bar before the cursor, across pages. Null when any preceding
  /// page has no staff: a "bar 4 of 12" label that skipped an undetectable page
  /// would be a lie, and the viewer shows no number in that case.
  ///
  /// Named `positionIn` rather than `position` because the record type it
  /// returns is declared in the widget layer, and a bare `position` here reads
  /// ambiguously against `NormalizedPoint.position`.
  static ({int current, int total})? positionIn(
    BarCursor cursor,
    List<BarLayout> layouts,
  ) {
    if (cursor.pageIndex < 0 || cursor.pageIndex >= layouts.length) return null;

    var seen = 0;
    for (var i = 0; i < cursor.pageIndex; i++) {
      final page = layouts[i];
      if (!page.hasStaff) return null;
      seen += page.barCount;
    }

    final page = layouts[cursor.pageIndex];
    if (!page.hasStaff || page.systems.isEmpty) return null;
    if (cursor.systemIndex >= page.systems.length) return null;

    for (var i = 0; i < cursor.systemIndex; i++) {
      seen += page.systems[i].barCount;
    }

    final system = page.systems[cursor.systemIndex];
    if (cursor.barIndex < 0 || cursor.barIndex >= system.barCount) return null;

    final total = layouts.fold(0, (sum, p) => sum + p.barCount);
    return (current: seen + cursor.barIndex + 1, total: total);
  }

  /// Whether [cursor] is the first bar of the score, so a "previous" control can
  /// be disabled.
  static bool isFirst(BarCursor cursor, List<BarLayout> layouts) =>
      back(cursor, layouts) == cursor;

  /// Whether [cursor] is the last bar, so a "next" control can be disabled.
  static bool isLast(BarCursor cursor, List<BarLayout> layouts) =>
      forward(cursor, layouts) == cursor;

  /// Whether any page in [layouts] has staff worth navigating.
  ///
  /// The gate on offering bar stepping at all. Without it the viewer would show
  /// a control that does nothing, which is worse than not offering it.
  static bool isNavigable(List<BarLayout> layouts) =>
      layouts.any((layout) => layout.hasStaff && layout.barCount > 0);
}