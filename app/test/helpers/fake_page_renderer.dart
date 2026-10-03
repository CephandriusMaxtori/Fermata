import 'dart:async';
import 'dart:ui' as ui;

import 'package:fermata/src/features/viewer/page_renderer.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';

/// A renderer that produces flat-coloured pages of a known size.
///
/// Lets the whole viewer be widget-tested without pdfrx's native engine, which
/// cannot load in the test runner. Because pages have a fixed size, tests can
/// assert on the exact geometry the ink layer is given.
class FakePageRenderer implements PageRenderer {
  FakePageRenderer({
    this.pageGeometry = const PageGeometry(widthPt: 612, heightPt: 792),
    this.renderDelay = Duration.zero,
    this.bars = BarLayout.empty,
  });

  final PageGeometry pageGeometry;
  final Duration renderDelay;

  /// Bars the fake reports for every page.
  ///
  /// Defaults to [BarLayout.empty] — the no-staff case — because that is what a
  /// scan returns and the viewer must fall back to page turning. Tests that care
  /// about bar stepping pass a real layout.
  final BarLayout bars;

  final List<String> renderedPages = [];
  final List<String> evictedPages = [];
  int clearCount = 0;

  @override
  Future<BarLayout> barLayout(ScorePage page) async => bars;

  @override
  Future<PageGeometry?> geometry(ScorePage page) async => pageGeometry;

  @override
  Future<ui.Image?> render(
    ScorePage page, {
    required Size maxSize,
    required double pixelRatio,
  }) async {
    if (renderDelay > Duration.zero) {
      await Future<void>.delayed(renderDelay);
    }
    renderedPages.add(page.id);

    final fitted = pageGeometry.fitWithin(
      availableWidth: maxSize.width,
      availableHeight: maxSize.height,
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, fitted.width, fitted.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    return recorder.endRecording().toImage(
      (fitted.width * pixelRatio).round().clamp(1, 4096),
      (fitted.height * pixelRatio).round().clamp(1, 4096),
    );
  }

  @override
  void evict(ScorePage page) => evictedPages.add(page.id);

  @override
  void clear() {
    clearCount++;
    renderedPages.clear();
  }
}

/// A renderer that never resolves, for testing loading states.
class HangingPageRenderer implements PageRenderer {
  @override
  Future<PageGeometry?> geometry(ScorePage page) =>
      Completer<PageGeometry?>().future;

  @override
  Future<BarLayout> barLayout(ScorePage page) =>
      Completer<BarLayout>().future;

  @override
  Future<ui.Image?> render(
    ScorePage page, {
    required Size maxSize,
    required double pixelRatio,
  }) => Completer<ui.Image?>().future;

  @override
  void evict(ScorePage page) {}

  @override
  void clear() {}
}
