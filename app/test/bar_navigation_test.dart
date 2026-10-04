import 'package:fermata/src/features/viewer/bar_navigation_bar.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A staff system spanning the page width with [barCount] bars.
StaffSystem system(int barCount) => StaffSystem(
  bounds: const NormalizedRect(0.1, 0.2, 0.9, 0.3),
  barStarts: [for (var i = 0; i < barCount; i++) 0.1 + i * (0.8 / barCount)],
);

/// A page with [systems] systems, each holding the given bar count.
BarLayout pageWith(List<int> systems) =>
    BarLayout(systems: [for (final n in systems) system(n)], hasStaff: true);

/// Pumps the bar under test and records what the user asked for.
///
/// Every counter is a list, not an `int`: the record is built before the test
/// taps anything, so a captured int would freeze at zero and every assertion
/// after an interaction would fail for reasons that have nothing to do with the
/// bar.
///
/// [barStepping] defaults to whatever `barMode == true` implies, which is what
/// every test written before the two were split wanted: "bars were found" and
/// "stepping by bar" together. Pass it explicitly to exercise the case they now
/// have to answer for separately, namely bar mode turned back off after
/// detection succeeded.
Future<({List<int> pageSteps, List<int> barSteps, List<int> jumps, List<int> detects, List<int> toggles})>
pumpBar(
  WidgetTester tester, {
  required bool? barMode,
  required BarCursor cursor,
  required List<BarLayout> layouts,
  bool? barStepping,
  int currentPage = 0,
  int pageCount = 1,
}) async {
  final pageSteps = <int>[];
  final barSteps = <int>[];
  final jumps = <int>[];
  final detects = <int>[];
  final toggles = <int>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: BarNavigationBar(
          currentPage: currentPage,
          pageCount: pageCount,
          barMode: barMode,
          barStepping: barStepping ?? barMode == true,
          cursor: cursor,
          layouts: layouts,
          onStepPage: pageSteps.add,
          onStepBar: barSteps.add,
          onJumpToPage: jumps.add,
          onDetect: () => detects.add(1),
          onToggleMode: () => toggles.add(1),
        ),
      ),
    ),
  );

  return (
    pageSteps: pageSteps,
    barSteps: barSteps,
    jumps: jumps,
    detects: detects,
    toggles: toggles,
  );
}

void main() {
  group('BarNavigationBar: detection gate', () {
    testWidgets('offers "Find bars" before detection has run', (tester) async {
      await pumpBar(
        tester,
        barMode: null,
        cursor: BarCursor.start,
        layouts: const [],
      );

      expect(find.text('Find bars'), findsOneWidget);
      expect(find.text('Looking for bars...'), findsOneWidget);
      // No bar count is claimed before anything has been detected.
      expect(find.textContaining('Bar '), findsNothing);
      expect(find.text('1 / 1'), findsOneWidget);
    });

    testWidgets('invoking "Find bars" asks for detection', (tester) async {
      final calls = await pumpBar(
        tester,
        barMode: null,
        cursor: BarCursor.start,
        layouts: const [],
      );

      await tester.tap(find.text('Find bars'));

      expect(calls.detects, [1]);
    });

    testWidgets('stays page-based when detection finds nothing', (tester) async {
      // The scan case. Offering a bar mode that cannot move would be worse than
      // not offering one, so the label falls back to page numbers.
      final calls = await pumpBar(
        tester,
        barMode: false,
        cursor: BarCursor.start,
        layouts: const [BarLayout.empty, BarLayout.empty],
        pageCount: 2,
      );

      expect(find.textContaining('Bar '), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('By bar'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      expect(calls.barSteps, isEmpty);
      expect(calls.pageSteps, [1]);
    });
  });

  group('BarNavigationBar: bar mode', () {
    testWidgets('shows bar numbers and page position together', (tester) async {
      await pumpBar(
        tester,
        barMode: true,
        cursor: BarCursor.start,
        layouts: [pageWith([4])],
      );

      expect(find.text('Bar 1 / 4'), findsOneWidget);
      expect(find.text('Page 1 of 1'), findsOneWidget);
      expect(find.text('By page'), findsOneWidget);
    });

    testWidgets('next advances one bar, not one page', (tester) async {
      final calls = await pumpBar(
        tester,
        barMode: true,
        cursor: const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 1),
        layouts: [pageWith([4])],
      );

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));

      expect(calls.barSteps, [1]);
      // The whole point: a bar step must not also turn the page.
      expect(calls.pageSteps, isEmpty);
    });

    testWidgets('previous goes back one bar', (tester) async {
      final calls = await pumpBar(
        tester,
        barMode: true,
        cursor: const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 2),
        layouts: [pageWith([4])],
      );

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));

      expect(calls.barSteps, [-1]);
    });

    testWidgets('previous is disabled on the first bar', (tester) async {
      final calls = await pumpBar(
        tester,
        barMode: true,
        cursor: BarCursor.start,
        layouts: [pageWith([4])],
      );

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_left_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(calls.barSteps, isEmpty);
    });

    testWidgets('next is disabled on the last bar', (tester) async {
      final calls = await pumpBar(
        tester,
        barMode: true,
        cursor: const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 3),
        layouts: [pageWith([4])],
      );

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(calls.barSteps, isEmpty);
    });

    testWidgets('a bar step is requested even when it will cross a page',
        (tester) async {
      // The bar count says bar 2 of 4, so "next" is enabled and means "step to
      // bar 3", which the navigator resolves to page 2. The bar decides the
      // gesture is available; BarNavigator decides where it lands.
      final calls = await pumpBar(
        tester,
        barMode: true,
        cursor: const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 1),
        layouts: [pageWith([2]), pageWith([2])],
        pageCount: 2,
      );

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));

      expect(calls.barSteps, [1]);
    });

    testWidgets('omits the bar number when the position cannot be trusted',
        (tester) async {
      // A preceding page with no staff means "bar 3 of 5" would have silently
      // skipped a page's worth of bars, so the page number is shown instead.
      await pumpBar(
        tester,
        barMode: true,
        cursor: const BarCursor(pageIndex: 1, systemIndex: 0, barIndex: 0),
        layouts: [BarLayout.empty, pageWith([3])],
        currentPage: 1,
        pageCount: 2,
      );

      expect(find.textContaining('Bar '), findsNothing);
      expect(find.text('2 / 2'), findsOneWidget);
    });

    testWidgets('counts across systems on the same page', (tester) async {
      await pumpBar(
        tester,
        barMode: true,
        cursor: const BarCursor(pageIndex: 0, systemIndex: 1, barIndex: 0),
        layouts: [pageWith([2, 3])],
      );

      expect(find.text('Bar 3 / 5'), findsOneWidget);
    });
  testWidgets('the mode toggle is a distinct action from stepping',
        (tester) async {
      // The toggle used to call onStepPage(0), i.e. "step nowhere and switch
      // mode". Keeping them separate means neither callback can be triggered by
      // accident, and a step can never double as a mode change.
      final calls = await pumpBar(
        tester,
        barMode: true,
        cursor: BarCursor.start,
        layouts: [pageWith([4])],
      );

      await tester.tap(find.text('By page'));

      expect(calls.toggles, [1]);
      expect(calls.pageSteps, isEmpty);
      expect(calls.barSteps, isEmpty);
    });
  });

  group('BarNavigationBar: page picker', () {
    testWidgets('reports how many bars each page has', (tester) async {
      await pumpBar(
        tester,
        barMode: true,
        cursor: BarCursor.start,
        layouts: [pageWith([3]), pageWith([3])],
        pageCount: 2,
      );

      await tester.tap(find.text('Bar 1 / 6'));
      await tester.pumpAndSettle();

      expect(find.text('3 bars'), findsNWidgets(2));
    });

    testWidgets('says when a page has no detectable bars', (tester) async {
      await pumpBar(
        tester,
        barMode: false,
        cursor: BarCursor.start,
        layouts: const [BarLayout.empty, BarLayout.empty],
        pageCount: 2,
      );

      await tester.tap(find.text('1 / 2'));
      await tester.pumpAndSettle();

      // Omitting this line would make the fallback look arbitrary.
      expect(find.text('No bars detected'), findsNWidgets(2));
    });

    testWidgets('jumping closes the sheet and reports the page', (tester) async {
      final calls = await pumpBar(
        tester,
        barMode: true,
        cursor: BarCursor.start,
        layouts: [pageWith([3]), pageWith([3])],
        pageCount: 2,
      );

      await tester.tap(find.text('Bar 1 / 6'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page 2'));
      await tester.pumpAndSettle();

      expect(calls.jumps, [1]);
    });
  });

  group('BarNavigationBar: issue #5', () {
    // Switching to bar mode and back threw. The crash was reached through the
    // scan case: detection finds nothing, the footer still offered an enabled
    // "By bar", tapping it set bar mode on for a score with zero bars, and the
    // next frame indexed an empty systems list. These pin the reachable
    // configurations, none of which had a test before.

    testWidgets('survives bar mode on a score with no bars at all',
        (tester) async {
      // The exact state the toggle used to be able to produce.
      await pumpBar(
        tester,
        barMode: true,
        barStepping: true,
        cursor: BarCursor.start,
        layouts: const [BarLayout.empty, BarLayout.empty],
        pageCount: 2,
      );

      // Nothing to step, so the number is not printed and the chevrons are
      // disabled rather than throwing on the way to finding that out.
      expect(find.textContaining('Bar '), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);

      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('survives a cursor on a staffless first page', (tester) async {
      // A title page is page 0, so `BarCursor.start` points at no bar while
      // `isNavigable` is true because a later page has staff. This is the
      // configuration the navigator's new guards protect.
      await pumpBar(
        tester,
        barMode: true,
        barStepping: true,
        cursor: BarCursor.start,
        layouts: [BarLayout.empty, pageWith([4])],
        pageCount: 2,
      );

      expect(find.text('1 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not offer bar stepping when nothing was detected',
        (tester) async {
      final calls = await pumpBar(
        tester,
        barMode: false,
        cursor: BarCursor.start,
        layouts: const [BarLayout.empty, BarLayout.empty],
        pageCount: 2,
      );

      // The button is still shown, so the footer admits it looked, but it is
      // disabled: a control that leads nowhere is worse than a dead one.
      expect(find.text('By bar'), findsOneWidget);
      final toggle = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('By bar'),
          matching: find.byType(TextButton),
        ),
      );
      expect(toggle.onPressed, isNull);

      await tester.tap(find.text('By bar'));
      expect(calls.toggles, isEmpty);
    });

    testWidgets('switching bar mode off does not look like a failed scan',
        (tester) async {
      // The round trip that erased what detection had learned. Bars were found,
      // the user turned bar mode off, and the footer used to read that as
      // "detection found no staff", so the mode could never be switched back on.
      final calls = await pumpBar(
        tester,
        barMode: true,
        barStepping: false,
        cursor: const BarCursor(pageIndex: 0, systemIndex: 0, barIndex: 2),
        layouts: [pageWith([4])],
      );

      // Page-based again...
      expect(find.textContaining('Bar '), findsNothing);
      expect(find.text('1 / 1'), findsOneWidget);
      // ...but bars are still known to exist, so the way back on is offered and
      // enabled. This is the whole reason barStepping is a separate flag.
      expect(find.text('By bar'), findsOneWidget);
      final toggle = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('By bar'),
          matching: find.byType(TextButton),
        ),
      );
      expect(toggle.onPressed, isNotNull);

      await tester.tap(find.text('By bar'));
      expect(calls.toggles, [1]);
    });
  });
}