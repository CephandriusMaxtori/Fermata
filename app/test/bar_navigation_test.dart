import 'package:fermata/src/features/viewer/page_stack.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_page_renderer.dart';

/// A staff system spanning the page width with [barCount] bars.
StaffSystem system(int barCount) => StaffSystem(
  bounds: const NormalizedRect(0.1, 0.2, 0.9, 0.3),
  barStarts: [
    for (var i = 0; i < barCount; i++) 0.1 + i * (0.8 / barCount),
  ],
);

BarLayout pageWith(List<int> systems) =>
    BarLayout(systems: [for (final n in systems) system(n)], hasStaff: true);

ScorePage page(int index) => ScorePage(
  id: 'page-$index',
  scoreId: 'score-1',
  pageIndex: index,
  pdfPageNumber: index + 1,
  kind: PageSourceKind.pdf,
  sourcePath: 'scores/score-1/page-$index.pdf',
  geometry: const PageGeometry(widthPt: 612, heightPt: 792),
);

void main() {
  group('Bar detection gating', () {
    testWidgets('is offered even when the score has no bars', (tester) async {
      // A scan: no text layer, so no bars. The control must still exist, or the
      // user has no way to ask again after adding a better source.
      await tester.pumpWidget(
        _app(renderer: FakePageRenderer(), pages: [page(0), page(1)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Find bars'), findsOneWidget);
    });

    testWidgets('offers bar mode once detection finds staff', (tester) async {
      await tester.pumpWidget(
        _app(
          renderer: FakePageRenderer(bars: pageWith([2])),
          pages: [page(0)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();

      expect(find.text('By page'), findsOneWidget);
      expect(find.text('Bar 1 / 2'), findsOneWidget);
    });

    testWidgets('falls back to page numbers when nothing is detected',
        (tester) async {
      await tester.pumpWidget(
        _app(
          renderer: FakePageRenderer(bars: BarLayout.empty),
          pages: [page(0), page(1)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();

      // No phantom bar count: the viewer stays page-based.
      expect(find.textContaining('Bar '), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });

  group('Bar stepping', () {
    testWidgets('next bar advances the bar number without leaving the page',
        (tester) async {
      await tester.pumpWidget(
        _app(renderer: FakePageRenderer(bars: pageWith([4])), pages: [page(0)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();

      expect(find.text('Bar 1 / 4'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Bar 2 / 4'), findsOneWidget);
      // Still page 1 of 1: a bar step is not a page step.
      expect(find.text('Page 1 of 1'), findsOneWidget);
    });

    testWidgets('previous bar is disabled on the first bar', (tester) async {
      await tester.pumpWidget(
        _app(renderer: FakePageRenderer(bars: pageWith([4])), pages: [page(0)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();

      final previous = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_left_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(previous.onPressed, isNull);
    });

    testWidgets('next bar is disabled on the last bar', (tester) async {
      await tester.pumpWidget(
        _app(renderer: FakePageRenderer(bars: pageWith([2])), pages: [page(0)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Bar 2 / 2'), findsOneWidget);

      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('a bar step across a page boundary turns the page',
        (tester) async {
      await tester.pumpWidget(
        _app(
          renderer: FakePageRenderer(bars: pageWith([2])),
          pages: [page(0), page(1)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Bar 2 / 4'), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);

      // One more bar is past the end of page 1, so it turns to page 2.
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Bar 3 / 4'), findsOneWidget);
      expect(find.text('Page 2 of 2'), findsOneWidget);
    });

    testWidgets('switching back to page mode restores page stepping',
        (tester) async {
      await tester.pumpWidget(
        _app(
          renderer: FakePageRenderer(bars: pageWith([4])),
          pages: [page(0), page(1)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bar '), findsOneWidget);

      await tester.tap(find.text('By page'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Bar '), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });

  group('Page picker', () {
    testWidgets('reports bar counts per page when in bar mode', (tester) async {
      await tester.pumpWidget(
        _app(
          renderer: FakePageRenderer(bars: pageWith([3])),
          pages: [page(0), page(1)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find bars'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bar 1 / 6'));
      await tester.pumpAndSettle();

      expect(find.text('3 bars'), findsNWidgets(2));
    });

    testWidgets('says so when a page has no detectable bars', (tester) async {
      await tester.pumpWidget(
        _app(
          renderer: FakePageRenderer(bars: BarLayout.empty),
          pages: [page(0), page(1)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 / 2'));
      await tester.pumpAndSettle();

      expect(find.text('No bars detected'), findsNWidgets(2));
    });
  });

  group('Annotation mode', () {
    testWidgets('shows the brush toolbar instead of navigation', (tester) async {
      await tester.pumpWidget(
        _app(renderer: FakePageRenderer(), pages: [page(0)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Find bars'), findsNothing);
    });
  });
}

Widget _app({
  required PageRenderer renderer,
  required List<ScorePage> pages,
}) {
  return ProviderScope(
    overrides: [
      pageRendererProvider.overrideWith((ref) async => renderer),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: PageStack(
          pages: pages,
          pageController: PageController(),
          transformationController: TransformationController(),
          drawingMode: false,
          onPageChanged: (_) {},
          onTapZone: (_) {},
          onStrokeCompleted: (_) {},
        ),
      ),
    ),
  );
}