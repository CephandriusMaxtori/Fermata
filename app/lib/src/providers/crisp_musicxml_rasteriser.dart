import 'dart:io';
import 'dart:math' as math;

import 'package:crisp_notation/crisp_notation.dart';
import 'package:fermata_data/fermata_data.dart';
// `PageMetrics` only, from the material library: this file needs `Color` and
// `WidgetsFlutterBinding` and nothing else, and a bare widgets import would
// collide with crisp_notation's own `PageMetrics` (Flutter has one too, for
// scroll physics).
import 'package:flutter/material.dart' show Color, WidgetsFlutterBinding;

/// Renders a MusicXML document to PNG pages with `crisp_notation`.
///
/// Accepts both plain `.musicxml` and the zipped `.mxl` container, which is what
/// every major notation editor actually writes. See [_readScoreXml] for why the
/// extension is not trusted to decide.
///
/// Lives in `app/` rather than `fermata_data` because rasterising needs Flutter:
/// `renderLayoutToPng` uses `dart:ui`, and the SMuFL glyph metrics that position
/// every glyph come from the Bravura asset that `crisp_notation_core` — being
/// pure Dart — cannot load. `fermata_data` declares the interface instead, which
/// is what keeps the import rules testable under `dart test`.
///
/// Pages are laid out on real ISO A4 rather than a fixed staff-space box, so the
/// engraved result is the size it would print, and a score that is one page on
/// paper is one page here.
class CrispMusicXmlRasteriser implements MusicXmlPageRasteriser {
  const CrispMusicXmlRasteriser({this.dpi = 200});

  /// Output resolution. 200 DPI is the point where staff lines and hairlines
  /// stop getting chunky; the stored PNG is what the viewer scales, so this is
  /// also the ceiling on how sharp a zoom can ever be.
  ///
  /// A consequence worth knowing: a rendered score is **raster**. Deep zoom
  /// softens, and unlike a PDF it cannot be re-rasterised from a vector source
  /// later. The `.musicxml` is kept on disk precisely so that raising this and
  /// re-rendering is possible without asking the user to find the file again.
  final double dpi;

  /// Pixels per staff space.
  ///
  /// 1.75mm is the standard engraving staff height from `Spatium`, so the page
  /// works out at true physical size: 210mm across is 120 staff spaces, and at
  /// 200 DPI that is about 945 pixels wide.
  static const double _staffSpaceMm = 1.75;

  static const double _kPixelsPerInch = 200;
  static const PaperSize _paper = PaperSize.a4;

  @override
  Future<MusicXmlRender> render(String absolutePath) async {
    WidgetsFlutterBinding.ensureInitialized();

    final xml = await _readScoreXml(absolutePath);
    final score = scoreFromMusicXml(xml);

    // Loading before layout rather than letting a view trigger it: the glyph
    // metrics decide where everything sits, so laying out against unloaded
    // metrics would produce pages that are subtly wrong rather than obviously
    // empty. This is cached after the first call.
    final metadata = await MusicFonts.load(MusicFont.bravura);

    final settings = LayoutSettings(
      metadata: metadata,
      fingeringPlacement: CrispNotationTheme.standard.fingeringPlacement,
    );

    final pxPerSpace = _staffSpaceMm == 0
        ? 8.0
        : (_kPixelsPerInch / 25.4) * _staffSpaceMm;
    final metrics = PageMetrics(
      width: _paper.width / _staffSpaceMm,
      height: _paper.height / _staffSpaceMm,
    );

    final paged = layoutPages(score, settings, metrics: metrics);

    if (paged.pages.isEmpty) {
      throw MusicXmlRenderException('the document laid out to no pages');
    }

    final widthPx = (metrics.width * pxPerSpace).round();
    final heightPx = (metrics.height * pxPerSpace).round();

    final pages = <RenderedPage>[];
    for (final page in paged.pages) {
      final flat = _flattenPage(page, metrics);
      final bytes = await renderLayoutToPng(
        flat,
        // staffSpace converts the layout's staff-space units to pixels. Passing
        // it explicitly is what makes the output resolution independent of
        // device density.
        staffSpace: pxPerSpace,
        // Opaque white: the annotation layer above assumes ink on paper, and a
        // transparent page would let the app background show through the score.
        background: const Color(0xFFFFFFFF),
      );
      pages.add(
        RenderedPage(
          pngBytes: bytes,
          widthPx: widthPx.toDouble(),
          heightPx: heightPx.toDouble(),
        ),
      );
    }

    return MusicXmlRender(
      pages: pages,
      title: score.metadata.title,
      composer: score.metadata.composer,
    );
  }
}

/// Collapses one page's systems into a single [ScoreLayout] spanning the page box.
///
/// `layoutPages` returns a [PageLayout] holding positioned systems, but
/// `renderLayoutToPng` — the only public rasteriser — takes a single
/// [ScoreLayout]. The package paints a page itself, inside `ScorePageView`'s
/// render object, and does not export that composition, so it is reproduced here.
///
/// **Why this and not mounting `ScorePageView` off-screen and capturing it.**
/// [LayoutPrimitive] is a *sealed* hierarchy, so the switch below is
/// exhaustiveness-checked: if `crisp_notation` adds a primitive kind, this stops
/// compiling and CI says so. The alternative's failure modes are silent — Bravura
/// not yet resolved at capture time yields pages of blank boxes, and a page count
/// taken before first layout is quietly wrong. A build break is the safer outcome
/// for a dependency that was published 44 hours ago.
ScoreLayout _flattenPage(PageLayout page, PageMetrics metrics) {
  final primitives = <LayoutPrimitive>[];

  for (final placed in page.systems) {
    final layout = placed.system.layout;
    // `placed.top` is the system's offset from the top of the content box and
    // `layout.top` the y of that system's own bounding-box top (negative, since
    // ink overshoots above the top staff line). Their difference is the offset
    // from the page box's top edge to the layout's origin, which is what
    // `renderLayoutToPng` would otherwise have applied itself.
    final dy = metrics.marginTop + placed.top - layout.top;
    final dx = metrics.marginLeft;

    for (final primitive in layout.primitives) {
      primitives.add(_translate(primitive, dx, dy));
    }
  }

  return ScoreLayout(
    width: metrics.width,
    height: metrics.height,
    // The page box *is* the origin here, so there is no overshoot above it to
    // account for. Reporting 0 stops the rasteriser shifting the image up by the
    // bounding-box top it would otherwise apply.
    top: 0,
    primitives: primitives,
    // No regions and no measure extents: nothing hit-tests or scrolls against a
    // flattened page. The viewer annotates with normalised coordinates and never
    // asks this layout anything.
    regions: const [],
    measureRegions: const [],
    crossStaffStubs: const {},
  );
}

/// Reads the MusicXML document out of [absolutePath], unarchiving `.mxl`.
///
/// The extension picks the path, but the *bytes* decide the actual handling:
/// `readMusicXmlFromMxl` detects the ZIP magic itself and falls back to reading
/// the file as plain XML when there is no archive. That is deliberate on their
/// part — publishers do ship uncompressed MusicXML under a `.mxl` extension, so
/// trusting the extension here would reject a perfectly good score. Routing both
/// through the same call keeps that tolerance, and means a mislabelled file
/// still imports instead of failing.
///
/// `FormatException` is left to propagate: `ImportService` catches it and names
/// the file, which is what the user needs when a handful of scores did not
/// import.
Future<String> _readScoreXml(String absolutePath) async {
  final bytes = await File(absolutePath).readAsBytes();
  return readMusicXmlFromMxl(bytes);
}

LayoutPrimitive _translate(LayoutPrimitive primitive, double dx, double dy) {
  math.Point<double> move(math.Point<double> p) =>
      math.Point<double>(p.x + dx, p.y + dy);

  return switch (primitive) {
    GlyphPrimitive(:final smuflName, :final position, :final scale, :final elementId) =>
      GlyphPrimitive(
        smuflName,
        move(position),
        scale: scale,
        elementId: elementId,
      ),
    LinePrimitive(
      :final from,
      :final to,
      :final thickness,
      :final round,
      :final elementId,
    ) => LinePrimitive(
      move(from),
      move(to),
      thickness: thickness,
      round: round,
      elementId: elementId,
    ),
    TextPrimitive(:final text, :final position, :final size, :final elementId) =>
      TextPrimitive(text, move(position), size: size, elementId: elementId),
    BeamPrimitive(:final start, :final end, :final thickness, :final elementId) =>
      BeamPrimitive(
        move(start),
        move(end),
        thickness: thickness,
        elementId: elementId,
      ),
    CurvePrimitive(
      :final start,
      :final control1,
      :final control2,
      :final end,
      :final thickness,
    ) => CurvePrimitive(
      move(start),
      move(control1),
      move(control2),
      move(end),
      thickness: thickness,
    ),
  };
}