import 'package:fermata/src/features/viewer/pdfrx_page_renderer.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// A rect in the engine's bottom-left space, where `top > bottom`.
///
/// Arguments are in the engine's own order so the call sites read like the
/// docs, and the conversion to fractions stays in one place below.
PdfRect rect(double left, double bottom, double right, double top) =>
    PdfRect(left, top, right, bottom);

/// A degenerate rect, as a malformed page might report for a glyph.
const PdfRect degenerate = PdfRect(0, 0, 0, 0);

/// A page 1000pt square, so points and fractions are numerically interchangeable.
const PageGeometry page = PageGeometry(widthPt: 1000, heightPt: 1000);

/// Builds the raw text a page would report for glyphs at the given boxes.
///
/// Goes through the engine's own `PdfPageRawText`, so the tests exercise the
/// real pair of structures rather than a stand-in that could drift from them.
PdfPageRawText raw(List<PdfRect> rects) =>
    PdfPageRawText('a' * rects.length, rects);

void main() {
  group('PdfrxPageRenderer.textRunsFrom', () {
    test('flips PDF\'s bottom-left origin into page-relative top-left', () {
      // y=900..950 in PDF space is the top 5% of a 1000pt page, and must come
      // out as top 0.05..0.10. Getting this backwards silently puts every bar on
      // the wrong system of the page.
      //
      // The two glyphs are adjacent (200 -> 201), so this is one run: a 10pt gap
      // on a 1000pt page is far past kRunGap and would split, which the next
      // test covers separately.
      final runs = PdfrxPageRenderer.textRunsFrom(
        PdfPageRawText('ab', [rect(100, 900, 200, 950), rect(201, 900, 260, 950)]),
        page,
      );

      expect(runs, hasLength(1));
      expect(runs.single.bounds.top, closeTo(0.05, 1e-9));
      expect(runs.single.bounds.bottom, closeTo(0.10, 1e-9));
      expect(runs.single.bounds.left, closeTo(0.10, 1e-9));
      expect(runs.single.bounds.right, closeTo(0.26, 1e-9));
      expect(runs.single.text, 'ab');
    });

    test('a single glyph still converts, not just a run of them', () {
      // A page whose staff is one glyph per measure is degenerate but legal, and
      // the conversion must not assume there is ever a second character.
      final runs = PdfrxPageRenderer.textRunsFrom(
        raw([rect(100, 900, 200, 950)]),
        page,
      );

      expect(runs, hasLength(1));
      expect(runs.single.bounds.top, closeTo(0.05, 1e-9));
      expect(runs.single.bounds.left, closeTo(0.10, 1e-9));
    });

    test('groups adjacent characters into one run', () {
      final runs = PdfrxPageRenderer.textRunsFrom(
        PdfPageRawText(
          'note',
          [
            rect(100, 900, 130, 950),
            rect(131, 900, 160, 950),
            rect(161, 900, 190, 950),
            rect(191, 900, 220, 950),
          ],
        ),
        page,
      );

      expect(runs, hasLength(1));
      expect(runs.single.text, 'note');
    });

    test('splits runs on a wide gap, which is where a barline sits', () {
      final runs = PdfrxPageRenderer.textRunsFrom(
        PdfPageRawText(
          'abcd',
          [
            rect(100, 900, 120, 950),
            rect(121, 900, 141, 950),
            // A 0.1-page jump: far more than letter spacing.
            rect(500, 900, 520, 950),
            rect(521, 900, 541, 950),
          ],
        ),
        page,
      );

      expect(runs, hasLength(2));
      expect(runs[0].text, 'ab');
      expect(runs[1].text, 'cd');
      expect(runs[0].bounds.right, lessThan(runs[1].bounds.left));
    });

    test('drops whitespace characters instead of splitting on them twice', () {
      // A space has a real bounding box, so treating it as ink would register
      // the gap inside a word as a barline.
      final runs = PdfrxPageRenderer.textRunsFrom(
        PdfPageRawText(
          'a b',
          [
            rect(100, 900, 120, 950),
            rect(121, 900, 141, 950),
            rect(142, 900, 162, 950),
          ],
        ),
        page,
      );

      expect(runs, hasLength(2));
      expect(runs[0].text, 'a');
      expect(runs[1].text, 'b');
    });

    test('a degenerate box ends a run rather than being skipped in place', () {
      // The bug this pins: skipping the box silently would shift every later
      // character against the wrong rect, and 'ab' + boxless + 'c' would come out
      // as 'ab' + 'c' straddling two parts of the page.
      final runs = PdfrxPageRenderer.textRunsFrom(
        raw([
          rect(100, 900, 120, 950),
          rect(121, 900, 141, 950),
          degenerate,
          rect(500, 900, 520, 950),
          rect(521, 900, 541, 950),
        ]),
        page,
      );

      expect(runs, hasLength(2));
      expect(runs[0].text, 'aa');
      expect(runs[1].text, 'aa');
      expect(runs[0].bounds.right, lessThan(runs[1].bounds.left));
    });

    test('clamps boxes that fall outside the page', () {
      // Glyph boxes that overhang a trim edge must not produce negative or
      // greater-than-one coordinates, which every downstream measurement
      // assumes.
      final runs = PdfrxPageRenderer.textRunsFrom(
        PdfPageRawText('n', [rect(-50, -50, 1050, 1050)]),
        page,
      );

      expect(runs.single.bounds.left, 0);
      expect(runs.single.bounds.right, 1);
      expect(runs.single.bounds.top, 0);
      expect(runs.single.bounds.bottom, 1);
    });

    test('handles rects longer than the text without throwing', () {
      // A malformed file can hand back more boxes than characters; reading past
      // the end of the string would throw and take the viewer down.
      final runs = PdfrxPageRenderer.textRunsFrom(
        PdfPageRawText('a', [
          rect(100, 900, 120, 950),
          rect(121, 900, 141, 950),
        ]),
        page,
      );

      expect(runs.single.text, 'a');
    });

    test('returns nothing for a page with no glyphs', () {
      expect(
        PdfrxPageRenderer.textRunsFrom(PdfPageRawText('', const []), page),
        isEmpty,
      );
    });
  });

  group('bar detection on converted runs', () {
    test('a run of notes becomes bars a navigator can step through', () {
      // End-to-end over the conversion: two measures separated by a gap.
      final rects = <PdfRect>[
        for (var i = 0; i < 12; i++)
          rect(100 + i * 10, 900, 108 + i * 10, 950),
        for (var i = 0; i < 12; i++)
          rect(700 + i * 10, 900, 708 + i * 10, 950),
      ];

      final layout = BarDetector.detect(
        PdfrxPageRenderer.textRunsFrom(
          PdfPageRawText('x' * rects.length, rects),
          page,
        ),
      );

      expect(layout.hasStaff, isTrue);
      expect(layout.barCount, greaterThanOrEqualTo(2));
    });
  });
}