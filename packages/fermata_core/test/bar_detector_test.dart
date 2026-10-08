import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

/// A glyph box in normalized coordinates.
TextRun run(double left, double top, double right, double bottom,
        {String text = 'n'}) =>
    TextRun(
      text: text,
      bounds: NormalizedRect(left, top, right, bottom),
    );

/// A row of evenly spaced glyphs, as one staff system would look after
/// extraction: [count] glyphs across [width], each [glyphWidth] wide.
List<TextRun> glyphRow({
  required double top,
  required double height,
  required double count,
  double start = 0.15,
  double end = 0.85,
  double glyphWidth = 0.004,
}) {
  final step = (end - start) / count;
  return [
    for (var i = 0; i < count; i++)
      run(
        start + i * step,
        top,
        start + i * step + glyphWidth,
        top + height,
      ),
  ];
}

void main() {
  group('BarDetector', () {
    test('returns empty for a page with no text at all', () {
      final layout = BarDetector.detect(const []);

      expect(layout.systems, isEmpty);
      expect(layout.hasStaff, isFalse);
      expect(layout.barCount, 0);
    });

    test('returns empty for a scan, which has a text layer with nothing on it',
        () {
      // Whitespace glyphs carry real bounding boxes but are not staff. Treating
      // these as systems would put phantom barlines on every page of every scan.
      final layout = BarDetector.detect([
        run(0.1, 0.1, 0.12, 0.12, text: ' '),
        run(0.2, 0.1, 0.22, 0.12, text: '  '),
      ]);

      expect(layout.hasStaff, isFalse);
    });

    test('finds a single system of evenly spaced notes', () {
      final layout = BarDetector.detect(glyphRow(top: 0.2, height: 0.08, count: 40));

      expect(layout.hasStaff, isTrue);
      expect(layout.systems, hasLength(1));
    });

    test('uniform spacing yields one bar, because no gap stands out', () {
      // This is the detector's honest limit, pinned deliberately: with every gap
      // identical there is nothing to distinguish a barline from note spacing,
      // and inventing barlines by dividing the row evenly would be worse than
      // admitting there is one bar. Real engraving varies its spacing, which is
      // why the wide-gap case below works.
      final layout = BarDetector.detect(glyphRow(top: 0.2, height: 0.08, count: 40));

      expect(layout.systems.single.barCount, 1);
    });

    test('a system starts on its left edge and runs its last bar to the right edge',
        () {
      final layout = BarDetector.detect(glyphRow(top: 0.2, height: 0.08, count: 40));
      final system = layout.systems.single;

      // Otherwise a navigation step has no left edge to scroll the first bar to,
      // and the final bar would have no extent.
      expect(system.barStarts.first, system.bounds.left);
      expect(system.barRange(system.barCount - 1).end, system.bounds.right);
    });

    test('barStarts are strictly increasing', () {
      final layout = BarDetector.detect(glyphRow(top: 0.2, height: 0.08, count: 60));
      final starts = layout.systems.single.barStarts;

      for (var i = 1; i < starts.length; i++) {
        expect(starts[i], greaterThan(starts[i - 1]),
            reason: 'bar $i is not to the right of bar ${i - 1}');
      }
    });

    test('barRange covers the system without gaps or overlaps', () {
      final layout = BarDetector.detect(glyphRow(top: 0.2, height: 0.08, count: 50));
      final system = layout.systems.single;

      for (var i = 0; i < system.barCount; i++) {
        final range = system.barRange(i);
        expect(range.start, lessThan(range.end));
        if (i + 1 < system.barCount) {
          expect(system.barRange(i + 1).start, closeTo(range.end, 1e-9));
        }
      }
      expect(system.barRange(0).start, system.bounds.left);
      expect(system.barRange(system.barCount - 1).end, system.bounds.right);
    });

    test('separates systems stacked down the page', () {
      final layout = BarDetector.detect([
        ...glyphRow(top: 0.15, height: 0.08, count: 40),
        ...glyphRow(top: 0.45, height: 0.08, count: 40),
        ...glyphRow(top: 0.75, height: 0.08, count: 40),
      ]);

      expect(layout.systems, hasLength(3));
      // Reading order, top to bottom.
      for (var i = 1; i < layout.systems.length; i++) {
        expect(
          layout.systems[i].bounds.top,
          greaterThan(layout.systems[i - 1].bounds.top),
        );
      }
    });

    test('systemsAt picks the system containing a y position', () {
      final layout = BarDetector.detect([
        ...glyphRow(top: 0.15, height: 0.08, count: 40),
        ...glyphRow(top: 0.75, height: 0.08, count: 40),
      ]);

      expect(layout.systemsAt(0.19), hasLength(1));
      expect(layout.systemsAt(0.79), hasLength(1));
      expect(layout.systemsAt(0.45), isEmpty);
    });

    test('ignores lyrics, which are text but not staff', () {
      // One line of text: wide enough to pass the horizontal check, too short to
      // be a staff. Folding it in would drag the barline threshold around with
      // whatever spacing the lyricist happened to use.
      final layout = BarDetector.detect([
        ...glyphRow(top: 0.2, height: 0.08, count: 40),
        ...glyphRow(top: 0.36, height: 0.012, count: 30),
      ]);

      expect(layout.systems, hasLength(1));
      expect(layout.systems.single.bounds.height, greaterThan(0.05));
    });

    test('splits a wide gap into two bars', () {
      // Two measures separated by a clearly wider gap than the intra-measure
      // spacing: this is the case the feature exists for.
      final layout = BarDetector.detect([
        ...glyphRow(
            top: 0.2, height: 0.08, count: 12, start: 0.15, end: 0.45),
        ...glyphRow(
            top: 0.2, height: 0.08, count: 12, start: 0.55, end: 0.85),
      ]);

      final system = layout.systems.single;
      // One bar per measure: the seam barline splits the system in two.
      expect(system.barCount, 2);
      expect(system.barRange(1).start, closeTo(system.barRange(0).end, 1e-9));
      // The first bar ends at the seam, the second runs to the system edge.
      expect(system.barRange(0).end, closeTo(0.429, 0.001));
      expect(system.barRange(1).end, system.bounds.right);
    });

    test('handles multi-staff systems (e.g. grand staff) without double counting bars', () {
      final layout = BarDetector.detect([
        ...glyphRow(top: 0.15, height: 0.03, count: 12, start: 0.15, end: 0.45),
        ...glyphRow(top: 0.15, height: 0.03, count: 12, start: 0.55, end: 0.85),
        ...glyphRow(top: 0.22, height: 0.03, count: 12, start: 0.15, end: 0.45),
        ...glyphRow(top: 0.22, height: 0.03, count: 12, start: 0.55, end: 0.85),
      ]);

      expect(layout.systems, hasLength(1));
      expect(layout.systems.single.barCount, 2);
    });

    test('a bar lands in the gap between the two measures', () {
      final layout = BarDetector.detect([
        ...glyphRow(top: 0.2, height: 0.08, count: 12, start: 0.15, end: 0.45),
        ...glyphRow(top: 0.2, height: 0.08, count: 12, start: 0.55, end: 0.85),
      ]);

      // The barline is recorded at the end of the ink before the gap, which is where
      // a barline is engraved: immediately after the last notehead of the measure
      // it closes. The first measure's last glyph ends at 0.429.
      final seam = layout.systems.single.barRange(1).start;
      expect(seam, closeTo(0.429, 0.001));
      expect(seam, lessThan(0.55), reason: 'the barline must fall in the gap');
    });

    test('barCount across systems is the sum of the systems', () {
      final layout = BarDetector.detect([
        ...glyphRow(top: 0.15, height: 0.08, count: 30),
        ...glyphRow(top: 0.75, height: 0.08, count: 30),
      ]);

      final sum = layout.systems.fold(0, (n, s) => n + s.barCount);
      expect(layout.barCount, sum);
    });

    test('a page too sparse to be music is not claimed to be staff', () {
      // Three isolated glyphs. Fewer than _kMinRunsPerSystem, so no phantom
      // navigation for a page that merely has a page number on it.
      final layout = BarDetector.detect([
        run(0.2, 0.9, 0.21, 0.92),
        run(0.5, 0.9, 0.51, 0.92),
        run(0.8, 0.9, 0.81, 0.92),
      ]);

      expect(layout.hasStaff, isFalse);
    });
  });

  group('NormalizedRect', () {
    test('normalises PDF edges whichever way round they arrive', () {
      // pdfrx asserts top >= bottom, so this ordering never actually reaches us
      // today. It is pinned anyway because the guarantee is the engine's, not
      // ours: a negative height would corrupt every measurement downstream, and
      // the failure would look like bad detection rather than a coordinate bug.
      final a = NormalizedRect.fromPdfEdges(
          left: 0.1, right: 0.2, top: 0.3, bottom: 0.2);
      final b = NormalizedRect.fromPdfEdges(
          left: 0.1, right: 0.2, top: 0.2, bottom: 0.3);

      expect(a, b);
      expect(a.top, closeTo(0.70, 1e-9));
      expect(a.bottom, closeTo(0.80, 1e-9));
      expect(a.height, closeTo(0.10, 1e-9));
    });

    test('flips PDF\'s bottom-left origin, not just the edge order', () {
      // y 900..950 on a 1000pt page is the top 5%, so it must come out as
      // 0.05..0.10. Reordering without flipping yields 0.90..0.95, which is
      // wrong in a way that looks like bad detection rather than a coordinate
      // bug — every bar lands on the wrong system of the page.
      final rect = NormalizedRect.fromPdfEdges(
        left: 0.1,
        right: 0.2,
        top: 0.95,
        bottom: 0.90,
      );

      expect(rect.top, closeTo(0.05, 1e-9));
      expect(rect.bottom, closeTo(0.10, 1e-9));
    });

    test('preserves horizontal position, which is not flipped', () {
      final rect = NormalizedRect.fromPdfEdges(
        left: 0.25,
        right: 0.75,
        top: 0.95,
        bottom: 0.90,
      );

      expect(rect.left, 0.25);
      expect(rect.right, 0.75);
    });

    test('clamp keeps edges inside the page', () {
      final clamped = const NormalizedRect(-0.5, -1, 1.5, 2).clamp();

      expect(clamped.left, 0);
      expect(clamped.top, 0);
      expect(clamped.right, 1);
      expect(clamped.bottom, 1);
    });

    test('containsY uses the y axis running downward', () {
      const rect = NormalizedRect(0, 0.2, 1, 0.4);

      expect(rect.containsY(0.3), isTrue);
      expect(rect.containsY(0.2), isTrue);
      expect(rect.containsY(0.1), isFalse);
      expect(rect.containsY(0.5), isFalse);
    });

    test('overlapArea is zero for disjoint rects and symmetric', () {
      const a = NormalizedRect(0, 0, 0.5, 0.5);
      const b = NormalizedRect(0.25, 0, 0.75, 0.5);
      const far = NormalizedRect(0.9, 0.9, 1, 1);

      expect(a.overlapArea(b), closeTo(0.5, 1e-9));
      expect(b.overlapArea(a), closeTo(a.overlapArea(b), 1e-9));
      expect(a.overlapArea(far), 0);
    });

    test('expandedToInclude is the bounding box of both', () {
      const a = NormalizedRect(0.2, 0.2, 0.4, 0.4);
      const b = NormalizedRect(0.1, 0.5, 0.3, 0.6);

      expect(a.expandedToInclude(b), const NormalizedRect(0.1, 0.2, 0.4, 0.6));
      expect(b.expandedToInclude(a), const NormalizedRect(0.1, 0.2, 0.4, 0.6));
    });

    test('isEmpty for zero-area boxes but not for real ones', () {
      expect(const NormalizedRect(0.5, 0.5, 0.5, 0.5).isEmpty, isTrue);
      expect(const NormalizedRect(0.5, 0.5, 0.5, 0.6).isEmpty, isTrue);
      expect(const NormalizedRect(0.4, 0.5, 0.5, 0.6).isEmpty, isFalse);
    });

    test('inverted edges are rejected rather than silently tolerated', () {
      // Every downstream measurement assumes ordered edges, so letting one
      // through would produce a negative height and a nonsense overlap ratio.
      expect(() => NormalizedRect(0.5, 0.5, 0.4, 0.6), throwsA(isA<AssertionError>()));
      expect(() => NormalizedRect(0.1, 0.6, 0.9, 0.5), throwsA(isA<AssertionError>()));
    });

    test('the inverted [empty] is the one exception, and reports empty', () {
      // Built as a `final` precisely so the constructor's asserts do not reject
      // it: `expandedToInclude` needs an identity to fold into.
      expect(NormalizedRect.empty.isEmpty, isTrue);
    });
  });

  group('TextRun', () {
    test('isBlank ignores whitespace-only text', () {
      expect(const TextRun(text: '  \n', bounds: NormalizedRect.zero).isBlank,
          isTrue);
      expect(
          const TextRun(text: 'a', bounds: NormalizedRect.zero).isBlank, isFalse);
    });

    test('exposes centres for the sweep in BarDetector', () {
      const r = TextRun(text: 'n', bounds: NormalizedRect(0.2, 0.4, 0.3, 0.6));

      expect(r.centerX, closeTo(0.25, 1e-9));
      expect(r.centerY, closeTo(0.5, 1e-9));
    });
  });

  group('BarLayout.empty', () {
    test('is a safe default for callers that did not detect anything', () {
      expect(BarLayout.empty.hasStaff, isFalse);
      expect(BarLayout.empty.systemsAt(0.5), isEmpty);
      expect(BarLayout.empty.barCount, 0);
    });
  });

  group('StaffSystem.barRange', () {
    test('rejects an out-of-range bar rather than returning nonsense', () {
      final system = StaffSystem(
        bounds: const NormalizedRect(0.1, 0.2, 0.9, 0.3),
        barStarts: const [0.1, 0.5],
      );

      expect(() => system.barRange(2), throwsA(isA<AssertionError>()));
      expect(() => system.barRange(-1), throwsA(isA<AssertionError>()));
    });

    test('the last bar runs to the system right edge', () {
      final system = StaffSystem(
        bounds: const NormalizedRect(0.1, 0.2, 0.9, 0.3),
        barStarts: const [0.1, 0.5],
      );

      expect(system.barRange(1), (start: 0.5, end: 0.9));
    });
  });
}
