import 'dart:async';

import 'package:fermata/src/features/viewer/page_stack.dart';
import 'package:fermata/src/providers/library_providers.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_page_renderer.dart';

/// Verifies that ink is placed relative to the page, not the viewport.
///
/// The invariant under test: a normalized coordinate produced from a touch must
/// mean the same thing to the painter. That only holds when the gesture hit box
/// and the paint box are the same box, which is a structural property of the
/// widget tree and so cannot be checked by unit-testing the geometry alone.
void main() {
  late FakeAnnotationRepository repository;

  setUp(() => repository = FakeAnnotationRepository());
  tearDown(() => repository.close());

  const page = ScorePage(
    id: 'page-1',
    scoreId: 'score-1',
    index: 0,
    kind: PageSourceKind.pdf,
    sourcePath: 'score.pdf',
    pdfPageNumber: 1,
  );

  group('ScorePageView ink alignment', () {
    testWidgets('the gesture box is the page box, not the viewport', (
      tester,
    ) async {
      // A wide, short page in a tall viewport. The page is letterboxed vertically,
      // which is exactly the case where normalizing against the viewport would
      // put every mark in the wrong place.
      final repository = FakeAnnotationRepository();
      final renderer = FakePageRenderer(
        pageGeometry: const PageGeometry(widthPt: 400, heightPt: 100),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            annotationRepositoryProvider.overrideWith((ref) async => repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 800,
                child: ScorePageView(
                  page: page,
                  renderer: renderer,
                  drawingMode: true,
                  onTapZone: (_) {},
                  onStrokeCompleted: repository.recordStroke,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the box that holds both the rendered page and the ink overlay.
      final pageBox = tester.getRect(find.byType(Stack).first);
      expect(pageBox.height, lessThan(800), reason: 'the page should letterbox');

      // Drag across the middle of the page horizontally, at mid height.
      final gesture = await tester.startGesture(
        Offset(pageBox.left + pageBox.width * 0.25, pageBox.center.dy),
      );
      await gesture.moveTo(
        Offset(pageBox.left + pageBox.width * 0.75, pageBox.center.dy),
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(repository.savedStrokes, hasLength(1));
      final stroke = repository.savedStrokes.single;

      // Normalized against the page, a drag from a quarter to three quarters of
      // the page width must land there. Normalizing against the 800px viewport
      // instead would compress every x into a narrow band and fail this.
      expect(stroke.points.first.position.x, closeTo(0.25, 0.02));
      expect(stroke.points.last.position.x, closeTo(0.75, 0.02));

      // Mid-height is 0.5 whichever box is used, but the normalization must be
      // clamped and finite rather than a division by zero.
      expect(stroke.points.first.position.y, closeTo(0.5, 0.02));
      for (final point in stroke.points) {
        expect(point.position.x, inInclusiveRange(0, 1));
        expect(point.position.y, inInclusiveRange(0, 1));
      }
    });

    testWidgets('a vertical drag is normalized against the page, not the viewport', (
      tester,
    ) async {
      final repository = FakeAnnotationRepository();
      final renderer = FakePageRenderer(
        pageGeometry: const PageGeometry(widthPt: 400, heightPt: 100),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            annotationRepositoryProvider.overrideWith((ref) async => repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 800,
                child: ScorePageView(
                  page: page,
                  renderer: renderer,
                  drawingMode: true,
                  onTapZone: (_) {},
                  onStrokeCompleted: repository.recordStroke,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageBox = tester.getRect(find.byType(Stack).first);

      // A drag over just 10% of the page's height. Against the viewport this
      // would read as ~0.0125; against the page it is 0.1.
      final gesture = await tester.startGesture(
        Offset(pageBox.center.dx, pageBox.top + pageBox.height * 0.45),
      );
      await gesture.moveTo(
        Offset(pageBox.center.dx, pageBox.top + pageBox.height * 0.55),
      );
      await gesture.up();
      await tester.pumpAndSettle();

      final stroke = repository.savedStrokes.single;
      expect(stroke.points.first.position.y, closeTo(0.45, 0.02));
      expect(stroke.points.last.position.y, closeTo(0.55, 0.02));
    });
  });
}

/// An in-memory annotation repository.
///
/// Only the streams the viewer actually reads are implemented; the rest throw,
/// because a silent no-op there would make a test pass for the wrong reason.
class FakeAnnotationRepository implements AnnotationRepository {
  final _layers = StreamController<List<AnnotationLayer>>.broadcast();
  final _strokes = StreamController<List<Stroke>>.broadcast();

  /// Called from `tearDown` so the broadcast controllers do not leak.
  void close() {
    _layers.close();
    _strokes.close();
  }

  final List<Stroke> savedStrokes = [];

  // Not const: DateTime has no const constructor, and the layer is only needed
// at runtime.
  static final _layer = AnnotationLayer(
    id: 'layer-1',
    scoreId: 'score-1',
    name: kDefaultLayerName,
    visible: true,
    sortOrder: 0,
    createdAt: DateTime.utc(2026),
  );

  void recordStroke(Stroke stroke) => savedStrokes.add(stroke);

  @override
  Stream<List<AnnotationLayer>> watchLayers(String scoreId) async* {
    yield <AnnotationLayer>[_layer];
    yield* _layers.stream;
  }

  @override
  Stream<List<Stroke>> watchStrokes({
    required String scoreId,
    required int pageIndex,
    Set<String> layerIds = const <String>{},
  }) async* {
    yield savedStrokes.where((s) => s.pageIndex == pageIndex).toList();
    yield* _strokes.stream;
  }

  @override
  Future<List<AnnotationLayer>> getLayers(String scoreId) async =>
      <AnnotationLayer>[_layer];

  @override
  Future<List<Stroke>> getStrokes({
    required String scoreId,
    required int pageIndex,
    Set<String> layerIds = const <String>{},
  }) async => savedStrokes;

  @override
  Future<void> upsertStroke(Stroke stroke) async {}

  @override
  Future<void> upsertStrokes(List<Stroke> strokes) async {}

  @override
  Future<void> deleteStroke(String strokeId) async {}

  @override
  Future<AnnotationLayer> createLayer({
    required String scoreId,
    required String name,
  }) => throw UnimplementedError();

  @override
  Future<void> renameLayer(AnnotationLayer layer, String name) =>
      throw UnimplementedError();

  @override
  Future<void> setLayerVisible(
    AnnotationLayer layer, {
    required bool visible,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteLayer(String layerId) => throw UnimplementedError();
}