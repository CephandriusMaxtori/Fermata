import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

/// A system with [barCount] bars spanning the page.
StaffSystem system(int barCount) => StaffSystem(
  bounds: const NormalizedRect(0.1, 0.2, 0.9, 0.3),
  barStarts: [
    for (var i = 0; i < barCount; i++) 0.1 + i * (0.8 / barCount),
  ],
);

/// A page with [systemBars] systems, each with [barsPerSystem] bars.
BarLayout page(List<int> systemBars) => BarLayout(
  systems: [for (final n in systemBars) system(n)],
  hasStaff: true,
);

void main() {
  group('BarNavigator.forward', () {
    test('advances within a system', () {
      final layouts = [page([4])];

      expect(
        BarNavigator.forward(const BarCursor(
            pageIndex: 0, systemIndex: 0, barIndex: 1),
            layouts),
        const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 2),
      );
    });

    test('crosses into the next system at a system boundary', () {
      final layouts = [page([3, 3])];

      // Bar 3 of system 1 (the last) -> bar 1 of system 2.
      expect(
        BarNavigator.forward(const BarCursor(
            pageIndex: 0, systemIndex: 0, barIndex: 2),
            layouts),
        const BarCursor(pageIndex: 0, systemIndex: 1, barIndex: 0),
      );
    });

    test('crosses into the next page at a page boundary', () {
      final layouts = [page([2]), page([2])];

      // Last bar of the last system of page 1 -> first bar of page 2.
      expect(
        BarNavigator.forward(const BarCursor(
            pageIndex: 0, systemIndex: 0, barIndex: 1),
            layouts),
        const BarCursor(pageIndex: 1, systemIndex: 0, barIndex: 0),
      );
    });

    test('stops at the end of the score rather than wrapping', () {
      final layouts = [page([2])];

      expect(
        BarNavigator.forward(const BarCursor(
            pageIndex: 0, systemIndex: 0, barIndex: 1),
            layouts),
        const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 1),
      );
    });

    test('walks the whole score one bar at a time, visiting each bar once', () {
      final layouts = [page([2, 3]), page([2])];
      final visited = <BarCursor>[];

      var cursor = BarCursor.start;
      visited.add(cursor);
      var guard = 0;
      while (guard++ < 50) {
        final next = BarNavigator.forward(cursor, layouts);
        if (next == cursor) break;
        cursor = next;
        visited.add(cursor);
      }

      // 2 + 3 + 2 bars, and no bar is stepped over or landed on twice.
      expect(visited, hasLength(7));
      expect(visited.toSet(), hasLength(7));
      expect(visited.last,
          const BarCursor(pageIndex: 1, systemIndex: 0, barIndex: 1));
    });
  });

  group('BarNavigator.back', () {
    test('steps back within a system', () {
      final layouts = [page([4])];

      expect(
        BarNavigator.back(const BarCursor(
            pageIndex: 0, systemIndex: 0, barIndex: 2),
            layouts),
        const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 1),
      );
    });

    test('lands on the last bar of the previous system, not its first', () {
      final layouts = [page([3, 3])];

      // First bar of system 2 -> last bar of system 1. Anything else and a
      // second back-step would skip bar 2, so hands-free reversing would drift.
      expect(
        BarNavigator.back(const BarCursor(
            pageIndex: 0, systemIndex: 1, barIndex: 0),
            layouts),
        const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 2),
      );
    });

    test('lands on the last bar of the previous page', () {
      final layouts = [page([2]), page([3])];

      expect(
        BarNavigator.back(const BarCursor(
            pageIndex: 1, systemIndex: 0, barIndex: 0),
            layouts),
        const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 1),
      );
    });

    test('stops at the start of the score rather than wrapping', () {
      final layouts = [page([2])];

      expect(BarNavigator.back(BarCursor.start, layouts), BarCursor.start);
    });

    test('round-trips with forward over every bar in the score', () {
      final layouts = [page([3, 2]), page([4])];

      for (final start in <BarCursor>[
        const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 0),
        const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 2),
        const BarCursor(pageIndex: 0, systemIndex: 1, barIndex: 0),
        const BarCursor(pageIndex: 0, systemIndex: 1, barIndex: 1),
        const BarCursor(pageIndex: 1, systemIndex: 0, barIndex: 0),
      ]) {
        expect(
          BarNavigator.back(BarNavigator.forward(start, layouts), layouts),
          start,
          reason: 'round trip failed from $start',
        );
      }
    });
  });

  group('BarNavigator.position', () {
    test('reports a 1-based number and the total', () {
      final layouts = [page([2]), page([3])];

      expect(
        BarNavigator.positionIn(
            const BarCursor(pageIndex: 1, systemIndex: 0, barIndex: 1),
            layouts),
        (current: 4, total: 5),
      );
    });

    test('counts across systems on the same page', () {
      final layouts = [page([2, 3])];

      // First bar of system 2 is bar 3 of the score.
      expect(
        BarNavigator.positionIn(
            const BarCursor(pageIndex: 0, systemIndex: 1, barIndex: 0),
            layouts),
        (current: 3, total: 5),
      );
    });

    test('reports nothing when an earlier page has no staff', () {
      // A "bar 4 of 12" label that quietly skipped a page with no detectable
      // staff would be a lie, so the caller shows no number instead.
      final layouts = [
        BarLayout.empty,
        page([3]),
      ];

      expect(
        BarNavigator.positionIn(
            const BarCursor(pageIndex: 1, systemIndex: 0, barIndex: 0),
            layouts),
        isNull,
      );
    });

    test('reports nothing for a cursor off the end of its own page', () {
      final layouts = [page([2])];

      expect(
        BarNavigator.positionIn(
            const BarCursor(pageIndex: 0, systemIndex: 3, barIndex: 0),
            layouts),
        isNull,
      );
    });
  });

  group('BarNavigator.isFirst / isLast', () {
    test('identify the ends of the score', () {
      final layouts = [page([2]), page([2])];

      expect(BarNavigator.isFirst(BarCursor.start, layouts), isTrue);
      expect(BarNavigator.isLast(BarCursor.start, layouts), isFalse);

      final end = const BarCursor(
          pageIndex: 1, systemIndex: 0, barIndex: 1);
      expect(BarNavigator.isLast(end, layouts), isTrue);
      expect(BarNavigator.isFirst(end, layouts), isFalse);
    });
  });

  group('BarNavigator.isNavigable', () {
    test('is false for a score with no detectable staff anywhere', () {
      // The scan case: offering a bar control that cannot move would be worse
      // than not offering it, so the viewer keeps page turning instead.
      expect(
        BarNavigator.isNavigable([
          BarLayout.empty,
          BarLayout.empty,
        ]),
        isFalse,
      );
    });

    test('is false for an empty score', () {
      expect(BarNavigator.isNavigable(const []), isFalse);
    });

    test('is true when any page has bars', () {
      expect(
        BarNavigator.isNavigable([
          BarLayout.empty,
          page([2]),
        ]),
        isTrue,
      );
    });
  });

  group('BarCursor', () {
    test('copyWith replaces only what it is given', () {
      const cursor = BarCursor(
          pageIndex: 1, systemIndex: 2, barIndex: 3);

      expect(cursor.copyWith(barIndex: 9).barIndex, 9);
      expect(cursor.copyWith(barIndex: 9).pageIndex, 1);
      expect(cursor.copyWith(barIndex: 9).systemIndex, 2);
      expect(cursor.copyWith(), cursor);
    });

    test('compares by value', () {
      expect(
        const BarCursor(pageIndex: 1, systemIndex: 2, barIndex: 3),
        const BarCursor(pageIndex: 1, systemIndex: 2, barIndex: 3),
      );
      expect(
        const BarCursor(pageIndex: 1, systemIndex: 2, barIndex: 3).hashCode,
        const BarCursor(pageIndex: 1, systemIndex: 2, barIndex: 3).hashCode,
      );
    });
  });
}
