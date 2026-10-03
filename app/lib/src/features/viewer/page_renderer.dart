import 'dart:ui' as ui;

import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/widgets.dart';

/// Rasterises one page of a score.
///
/// Declared as an interface so the entire viewer can be widget-tested without
/// pdfrx's native PDFium engine. The real implementation is one small class; a
/// test double just draws a coloured rectangle with `PictureRecorder`. This is
/// also the seam where page caching and render cancellation live, so neither
/// leaks into the widget tree.
abstract interface class PageRenderer {
  /// Returns the intrinsic size of [page] in points, or null if it cannot be
  /// measured.
  Future<PageGeometry?> geometry(ScorePage page);

  /// Rasterises [page] so it fits inside [maxSize] logical pixels, preserving
  /// the page's aspect ratio.
  ///
  /// [pixelRatio] scales the raster for the device's display density.
  Future<ui.Image?> render(
    ScorePage page, {
    required Size maxSize,
    required double pixelRatio,
  });

  /// Bar positions found in [page]'s text layer, or [BarLayout.empty].
  ///
  /// Deliberately on this interface rather than reaching for pdfrx directly in
  /// the viewer: bar navigation has to be widget-testable, and [BarLayout.empty]
  /// is the answer for every page without a usable text layer (a scan, a
  /// vector-only export), which is a normal outcome rather than a failure.
  Future<BarLayout> barLayout(ScorePage page);

  /// Drops any cached raster for [page].
  void evict(ScorePage page);

  /// Drops every cached raster.
  void clear();
}
