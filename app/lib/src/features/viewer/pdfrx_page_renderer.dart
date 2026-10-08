import 'dart:ui' as ui;

import 'package:fermata_core/fermata_core.dart';
import 'package:fermata_data/fermata_data.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'page_renderer.dart';

/// Rasterises pages with pdfrx's PDFium engine.
///
/// Fermata drives pdfrx purely as a document loader and page rasteriser. Its
/// bundled viewer widgets are built on the separate `material_ui` package,
/// which would be a second component library alongside this app's Material 3
/// theme, and Fermata needs a custom viewer anyway: the annotation overlay must
/// share a box with the page, and draw-versus-pan gestures need routing that a
/// general-purpose viewer does not offer.
///
/// Two details worth knowing:
///
///  * The document is cached per source path, because a multi-page score made
///    of one PDF re-opens the same file for every page otherwise.
///  * [PdfPage.render] hands back a [PdfImage] that owns native memory and
///    must be disposed, and it accepts a cancellation token so a fast scroll can
///    abandon a render it no longer needs.
class PdfrxPageRenderer implements PageRenderer {
  PdfrxPageRenderer(this._fileStore);

  final FileStore _fileStore;

  final Map<String, Future<PdfDocument>> _documents = {};
  final Map<String, _Raster> _rasters = {};

  /// Bar layouts by page id. Small and cheap, so it is never evicted per page —
  /// the whole point is that a navigation step does not re-run extraction.
  final Map<String, BarLayout> _barLayouts = {};

  /// Horizontal gap, as a fraction of page width, that ends a text run.
  ///
  /// Sized above inter-character spacing inside a word and below the gap a
  /// barline leaves, which is the only range in which the two are separable at
  /// all. It is a compromise, and `BarDetector` documents what happens when it
  /// is wrong.
  static const kRunGap = 0.0015;

  /// A4-ish fallback for pages whose geometry cannot be measured.
  static const PageGeometry _fallback = PageGeometry(
    widthPt: 595,
    heightPt: 842,
  );

  @override
  Future<PageGeometry?> geometry(ScorePage page) async {
    if (page.geometry != null) return page.geometry;
    if (page.kind != PageSourceKind.pdf) return _fallback;

    final document = await _documentFor(_absolutePath(page));
    final pdfPage = document.pages[(page.pdfPageNumber ?? 1) - 1];
    return PageGeometry(widthPt: pdfPage.width, heightPt: pdfPage.height);
  }

  @override
  Future<ui.Image?> render(
    ScorePage page, {
    required Size maxSize,
    required double pixelRatio,
  }) async {
    final pageGeometry = await geometry(page);
    if (pageGeometry == null) return null;

    final fitted = pageGeometry.fitWithin(
      availableWidth: maxSize.width,
      availableHeight: maxSize.height,
    );
    if (fitted.width <= 0 || fitted.height <= 0) return null;

    // Cache key includes target size and pixel ratio so rotate, resize or
    // high-DPI changes do not silently reuse a raster at the wrong resolution.
    final renderWidth = (fitted.width * pixelRatio).round();
    final renderHeight = (fitted.height * pixelRatio).round();
    final key = '${page.id}@${renderWidth}x$renderHeight';
    final cached = _rasters[page.id];
    if (cached != null && cached.key == key) return cached.image;

    final image = await _rasterise(page, fitted, pixelRatio);
    if (image == null) return null;

    _rasters[page.id] = _Raster(key, image);
    return image;
  }

  Future<ui.Image?> _rasterise(
    ScorePage page,
    ({double width, double height}) fitted,
    double pixelRatio,
  ) async {
    if (page.kind == PageSourceKind.bitmap) {
      return _rasteriseBitmap(page, fitted, pixelRatio);
    }

    final document = await _documentFor(_absolutePath(page));
    final pdfPage = document.pages[(page.pdfPageNumber ?? 1) - 1];
    final cancellation = pdfPage.createCancellationToken();

    final rendered = await pdfPage.render(
      fullWidth: fitted.width * pixelRatio,
      fullHeight: fitted.height * pixelRatio,
      cancellationToken: cancellation,
    );
    if (rendered == null) return null;

    final image = rendered.createImage();
    rendered.dispose();
    return image;
  }

  /// Always [BarLayout.empty]: there is no positional source wired up.
  ///
  /// This used to run `BarDetector` over the page's text layer. That was removed
  /// on 2026-10-08, and the reason is worth keeping, because it is not a bug in
  /// the heuristic — the heuristic never received an input it could work on.
  /// Every score PDF checked on this machine (three of them) is a scan with an
  /// embedded JPEG and zero `/Font` entries, so `loadText()` returned nothing
  /// and every page answered "no staff". The thresholds had never been
  /// validated against real engraving. See `bar-scribe-design.md`.
  ///
  /// The interface method stays, deliberately. A source that *does* know where
  /// the barlines are on the page — an OMR run that emits coordinates, or a
  /// sidecar — is a one-implementation change here, and the viewer, the
  /// navigation bar and `BarNavigator` all sit downstream of this seam already.
  ///
  /// Note that MusicXML is not such a source: it is a logical format with
  /// `<measure>` elements and no page coordinates, and `StaffSystem.barRange`
  /// returns fractions of page width because the viewer scrolls the original
  /// raster. Measures have to be mapped back onto the page before they can drive
  /// navigation.
  @override
  Future<BarLayout> barLayout(ScorePage page) async {
    return _barLayouts[page.id] = BarLayout.empty;
  }

  /// Characters are grouped into runs on whitespace and on large horizontal
  /// jumps.
  ///
  /// Kept even though nothing calls it yet. This is the only conversion in the
  /// codebase from PDF-space (bottom-left origin, points) to `fermata_core`'s
  /// page-relative normalized space, it is the piece any future positional
  /// source needs, and it is pinned by nine tests in
  /// `pdfrx_text_conversion_test.dart`. Deleting it would throw away tested
  /// geometry to avoid keeping an adapter.
  ///
  /// Run bounds are accumulated as the run grows rather than rescanning, so
  /// this stays linear in the character count.
  @visibleForTesting
  static List<TextRun> textRunsFrom(PdfPageRawText text, PageGeometry geometry) {
    final runs = <TextRun>[];
    var characters = StringBuffer();
    var bounds = NormalizedRect.empty;
    var previousRight = double.negativeInfinity;

    void flush() {
      if (characters.isNotEmpty) {
        runs.add(TextRun(text: characters.toString(), bounds: bounds));
      }
      characters = StringBuffer();
      bounds = NormalizedRect.empty;
    }

    for (var i = 0; i < text.charRects.length && i < text.fullText.length; i++) {
      final rect = text.charRects[i];

      final charBounds = rect.isEmpty
          ? null
          : NormalizedRect.fromPdfEdges(
        left: rect.left / geometry.widthPt,
        right: rect.right / geometry.widthPt,
        top: rect.top / geometry.heightPt,
        bottom: rect.bottom / geometry.heightPt,
      ).clamp();

      final char = text.fullText[i];

      // A character with no usable box ends the current run rather than being
      // silently skipped. Skipping it would shift every later character against
      // the wrong rect, and the run would end up straddling two unrelated parts
      // of the page.
      if (charBounds == null) {
        flush();
        previousRight = double.negativeInfinity;
        continue;
      }

      final jumped = previousRight.isFinite &&
          charBounds.left - previousRight > kRunGap;

      if (char.trim().isEmpty || jumped) {
        flush();
        // Whitespace ends the run but is never itself ink. A big horizontal jump
        // does end it, and the character that caused it does belong to the new
        // run, so it falls through to be written below.
        if (char.trim().isEmpty) {
          previousRight = double.negativeInfinity;
          continue;
        }
      }

      characters.write(char);
      bounds = bounds.isEmpty ? charBounds : bounds.expandedToInclude(charBounds);
      previousRight = charBounds.right;
    }

    flush();
    return runs;
  }

  Future<ui.Image?> _rasteriseBitmap(
    ScorePage page,
    ({double width, double height}) fitted,
    double pixelRatio,
  ) async {
    // Bitmap sources are stored score-relative so a restored backup still
    // renders; the store resolves them against the current library root.
    final file = _fileStore.resolveScoreSource(page.scoreId, page.sourcePath);
    if (!file.existsSync()) return null;

    final codec = await ui.instantiateImageCodec(
      await file.readAsBytes(),
      targetWidth: (fitted.width * pixelRatio).round(),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  String _absolutePath(ScorePage page) =>
      _fileStore.resolveScoreSource(page.scoreId, page.sourcePath).path;

  Future<PdfDocument> _documentFor(String absolutePath) {
    return _documents.putIfAbsent(absolutePath, () async {
      // Must be awaited, not just called. pdfrx's native library has to be
      // initialised before the first document is opened, and letting the future
      // float means opening a score can race the initialisation.
      await pdfrxFlutterInitialize();
      return PdfDocument.openFile(absolutePath);
    });
  }

  @override
  void evict(ScorePage page) {
    _rasters.remove(page.id)?.image.dispose();
  }

  @override
  void clear() {
    for (final raster in _rasters.values) {
      raster.image.dispose();
    }
    _rasters.clear();
    _barLayouts.clear();
    for (final pending in _documents.values) {
      pending.then((document) => document.dispose()).ignore();
    }
    _documents.clear();
  }
}

class _Raster {
  const _Raster(this.key, this.image);

  final String key;
  final ui.Image image;
}
