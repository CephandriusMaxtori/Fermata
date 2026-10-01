import 'package:fermata/src/features/viewer/brush_selection.dart';
import 'package:fermata/src/features/viewer/brush_toolbar.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrushSelection.copyWith', () {
    test('keeps the pen when changing colour', () {
      const pen = BrushSelection(color: 0xFF1A1A1A, width: 0.006);
      final updated = pen.copyWith(color: 0xFFD32F2F);

      expect(updated.kind, AnnotationKind.pen);
      expect(updated.color, 0xFFD32F2F);
      expect(updated.width, 0.006);
    });

    test('keeps the highlighter when changing colour', () {
      // This is the regression: copyWith used to call the pen constructor, so
      // picking a colour silently switched the tool back to the pen.
      const highlighter = BrushSelection.highlighter(
        color: 0xFFFFEB3B,
        width: 0.01,
      );
      final updated = highlighter.copyWith(color: 0xFF80CBC4);

      expect(updated.kind, AnnotationKind.highlighter);
      expect(updated.color, 0xFF80CBC4);
    });

    test('keeps the highlighter when changing width', () {
      const highlighter = BrushSelection.highlighter(
        color: 0xFFFFEB3B,
        width: 0.01,
      );
      final updated = highlighter.copyWith(width: 0.02);

      expect(updated.kind, AnnotationKind.highlighter);
      expect(updated.width, 0.02);
    });

    test('leaves the tool untouched when changing nothing', () {
      const highlighter = BrushSelection.highlighter(
        color: 0xFFFFEB3B,
        width: 0.01,
      );
      expect(highlighter.copyWith().kind, AnnotationKind.highlighter);
      expect(highlighter.copyWith().color, 0xFFFFEB3B);
      expect(highlighter.copyWith().width, 0.01);
    });
  });

  group('BrushSelection.withKind', () {
    test('switches from pen to highlighter', () {
      const pen = BrushSelection(color: 0xFF1A1A1A, width: 0.006);
      final highlighter = pen.withKind(AnnotationKind.highlighter);

      expect(highlighter.kind, AnnotationKind.highlighter);
      // The palettes are disjoint, so the colour falls back to a valid one
      // rather than leaving the user with an unpickable colour.
      expect(highlighterColors, contains(highlighter.color));
      expect(highlighter.width, 0.006);
    });

    test('switches from highlighter to pen', () {
      const highlighter = BrushSelection.highlighter(
        color: 0xFFFFEB3B,
        width: 0.01,
      );
      final pen = highlighter.withKind(AnnotationKind.pen);

      expect(pen.kind, AnnotationKind.pen);
      expect(penColors, contains(pen.color));
      expect(pen.width, 0.01);
    });

    test('is a no-op when the tool is already selected', () {
      const pen = BrushSelection(color: 0xFF1976D2, width: 0.008);
      expect(pen.withKind(AnnotationKind.pen), pen);
    });

    test('always lands on a colour the new palette offers', () {
      for (final color in penColors) {
        final switched = BrushSelection(
          color: color,
          width: 0.005,
        ).withKind(AnnotationKind.highlighter);
        expect(
          highlighterColors,
          contains(switched.color),
          reason: 'highlighter fallback for pen colour $color',
        );
      }
      for (final color in highlighterColors) {
        final switched = BrushSelection.highlighter(
          color: color,
          width: 0.005,
        ).withKind(AnnotationKind.pen);
        expect(
          penColors,
          contains(switched.color),
          reason: 'pen fallback for highlighter colour $color',
        );
      }
    });
  });

  group('BrushSelection.palette', () {
    test('reports the palette matching the tool', () {
      expect(
        const BrushSelection(color: 0xFF1A1A1A, width: 0.006).palette,
        penColors,
      );
      expect(
        const BrushSelection.highlighter(color: 0xFFFFEB3B, width: 0.006)
            .palette,
        highlighterColors,
      );
    });

    test('the two palettes do not overlap', () {
      expect(penColors.toSet().intersection(highlighterColors.toSet()), isEmpty);
    });
  });

  group('BrushToolbar', () {
    testWidgets('choosing a colour keeps the highlighter selected', (
      tester,
    ) async {
      var selection = const BrushSelection.highlighter(
        color: 0xFFFFEB3B,
        width: 0.01,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  BrushToolbar(
                    selection: selection,
                    onChanged: (next) => setState(() => selection = next),
                  ),
                  Text('kind=${selection.kind.name}'),
                ],
              ),
            ),
          ),
        ),
      );

      // Tap the second colour dot. Scoped to the scrollable row because
      // byType(InkWell) would also match the ChoiceChips' internal ink wells.
      final dots = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(InkWell),
      );
      await tester.tap(dots.at(1));
      await tester.pumpAndSettle();

      expect(selection.kind, AnnotationKind.highlighter);
      expect(selection.color, highlighterColors[1]);
      expect(find.text('kind=highlighter'), findsOneWidget);
    });

    testWidgets('dragging the width slider keeps the highlighter selected', (
      tester,
    ) async {
      var selection = const BrushSelection.highlighter(
        color: 0xFFFFEB3B,
        width: 0.001,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  BrushToolbar(
                    selection: selection,
                    onChanged: (next) => setState(() => selection = next),
                  ),
                  Text('kind=${selection.kind.name}'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(Slider), const Offset(80, 0));
      await tester.pumpAndSettle();

      expect(selection.kind, AnnotationKind.highlighter);
      expect(selection.width, greaterThan(0.001));
      expect(find.text('kind=highlighter'), findsOneWidget);
    });

    testWidgets('switching tools lands on a colour the new palette offers', (
      tester,
    ) async {
      var selection = const BrushSelection(color: 0xFF1A1A1A, width: 0.006);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  BrushToolbar(
                    selection: selection,
                    onChanged: (next) => setState(() => selection = next),
                  ),
                  Text('color=0x${selection.color.toRadixString(16)}'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Highlight'));
      await tester.pumpAndSettle();

      expect(selection.kind, AnnotationKind.highlighter);
      expect(highlighterColors, contains(selection.color));
      // The toolbar must not be showing an unselected dot after a tool switch.
      expect(
        find.text('color=0x${selection.color.toRadixString(16)}'),
        findsOneWidget,
      );
    });
  });
}