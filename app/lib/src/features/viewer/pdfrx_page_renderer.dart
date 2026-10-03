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

    // Cache key includes the target size so a rotate or a window change does
    // not silently reuse a raster at the wrong resolution.
    final key = '${page.id}@${fitted.width.round()}x${fitted.height.round()}';
    final cached = _rasters[page.id];
    if (cached != null && cached.key == key) return cached.image;

    final image = await _rasterise(page, fitted);
    if (image == null) return null;

    _rasters[page.id] = _Raster(key, image);
    return image;
  }

  Future<ui.Image?> _rasterise(ScorePage page, ({double width, double height}) fitted) async {
    if (page.kind == PageSourceKind.bitmap) {
      return _rasteriseBitmap(page, fitted);
    }

    final document = await _documentFor(_absolutePath(page));
    final pdfPage = document.pages[(page.pdfPageNumber ?? 1) - 1];
    final cancellation = pdfPage.createCancellationToken();

    final rendered = await pdfPage.render(
      fullWidth: fitted.width,
      fullHeight: fitted.height,
      cancellationToken: cancellation,
    );
    if (rendered == null) return null;

    final image = rendered.createImage();
    rendered.dispose();
    return image;
  }

  /// Finds bar positions by reading the page's text layer.
  ///
  /// Three things this deliberately does not do:
  ///
  ///  * **No scan handling.** A scanned score has no text layer, so this returns
  ///    [BarLayout.empty] and the viewer keeps page turning. Trying to read bar
  ///    positions off a scan means image processing, which is a different feature.
  ///  * **No caching of failures as successes.** An empty result is cached just
  ///    like a non-empty one, because "this page has no staff" is a stable fact
  ///    about the file and re-running extraction on every step would stutter.
  ///  * **No fallback that guesses.** See `BarDetector` for why a heuristic is
  ///    already the most this can honestly do.
  @override
  Future<BarLayout> barLayout(ScorePage page) async {
    if (page.kind != PageSourceKind.pdf) return BarLayout.empty;

    final cached = _barLayouts[page.id];
    if (cached != null) return cached;

    final BarLayout layout;
    try {
      final document = await _documentFor(_absolutePath(page));
      final pdfPage = document.pages[(page.pdfPageNumber ?? 1) - 1];
      final geometry = await this.geometry(page);
      if (geometry == null || geometry.widthPt <= 0 || geometry.heightPt <= 0) {
        return _barLayouts[page.id] = BarLayout.empty;
      }
      final text = await pdfPage.loadText();
      layout = text == null
          ? BarLayout.empty
          : BarDetector.detect(_textRuns(text, geometry));
    } on Object {
      // A page that cannot be parsed for text is simply a page without bars.
      // Letting this throw would take the whole viewer down over a navigation
      // convenience, so the failure is absorbed here and reported as "no staff".
      return _barLayouts[page.id] = BarLayout.empty;
    }

    return _barLayouts[page.id] = layout;
  }

  /// Converts pdfrx character boxes into normalized [TextRun]s.
  ///
  /// This is the only place in the app that knows PDF's bottom-left origin and
  /// its inverted vertical edges; [NormalizedRect.fromPdfEdges] absorbs the
  /// flip so no other file has to think about it.
  ///
  /// Characters are grouped into runs on whitespace and on large horizontal
  /// jumps. Grouping matters because a barline gap is measured between *runs* of
  /// ink: passing single characters through would let the gap inside a word
  /// register as a barline. Run bounds are accumulated as the run grows rather
  /// than rescanning, so this stays linear in the character count.
  static List<TextRun> _textRuns(PdfPageRawText text, PageGeometry geometry) {
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
      if (rect.isEmpty) continue;

      final charBounds = NormalizedRect.fromPdfEdges(
        left: rect.left / geometry.widthPt,
        right: rect.right / geometry.widthPt,
        top: rect.top / geometry.heightPt,
        bottom: rect.bottom / geometry.heightPt,
      ).clamp();
      if (charBounds.isEmpty) continue;

      final char = text.fullText[i];
      final jumped = previousRight.isFinite &&
          charBounds.left - previousRight > kRunGap;

      if (char.trim().isEmpty || jumped) {
        flush();
        if (char.trim().isEmpty) continue;
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
  ) async {
    // Bitmap sources are stored score-relative so a restored backup still
    // renders; the store resolves them against the current library root.
    final file = _fileStore.resolveScoreSource(page.scoreId, page.sourcePath);
    if (!file.existsSync()) return null;

    final codec = await ui.instantiateImageCodec(
      await file.readAsBytes(),
      targetWidth: fitted.width.round(),
    );
    final frame = await codec.getNextFrame();
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
