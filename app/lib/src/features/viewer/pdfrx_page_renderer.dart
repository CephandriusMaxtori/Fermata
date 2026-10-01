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
      pdfrxFlutterInitialize();
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
