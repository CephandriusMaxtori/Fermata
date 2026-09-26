import '../geometry/stroke.dart';
import '../models/annotation_layer.dart';
import '../models/score.dart';
import '../models/score_page.dart';

/// Read/write access to the score library.
///
/// Declared in the model layer and implemented in the data layer so the UI
/// never depends on drift, and so the on-device web server can expose the same
/// operations over HTTP later.
abstract interface class ScoreRepository {
  /// Emits the full library, re-emitting whenever any score or page changes.
  Stream<List<Score>> watchScores(ScoreQuery query);

  /// Scores only, ordered as the library screen displays them.
  Future<List<Score>> getScores(ScoreQuery query);

  Future<Score?> getScore(String scoreId);

  /// Pages of [scoreId] in display order.
  Future<List<ScorePage>> getPages(String scoreId);

  Stream<List<ScorePage>> watchPages(String scoreId);

  /// Inserts a score and its pages in one transaction.
  Future<Score> createScore({
    required Score score,
    required List<ScorePage> pages,
    List<AnnotationLayer> layers,
  });

  Future<void> updateScore(Score score);

  /// Removes the score, its pages, its layers, its annotations and its files.
  Future<void> deleteScore(String scoreId);

  /// Records that the score was opened, for the "recently opened" sort.
  Future<void> markOpened(String scoreId, DateTime when);

  /// Scores whose content hash matches, used by import.
  Future<List<Score>> findByContentHash(String contentHash);
}

/// Read/write access to annotation layers and ink.
abstract interface class AnnotationRepository {
  Stream<List<AnnotationLayer>> watchLayers(String scoreId);

  Future<List<AnnotationLayer>> getLayers(String scoreId);

  Future<AnnotationLayer> createLayer({
    required String scoreId,
    required String name,
  });

  Future<void> renameLayer(AnnotationLayer layer, String name);

  Future<void> setLayerVisible(AnnotationLayer layer, {required bool visible});

  /// Deletes a layer and every annotation on it.
  Future<void> deleteLayer(String layerId);

  /// All ink on one page, optionally filtered to specific layers.
  Future<List<Stroke>> getStrokes({
    required String scoreId,
    required int pageIndex,
    Set<String> layerIds,
  });

  Stream<List<Stroke>> watchStrokes({
    required String scoreId,
    required int pageIndex,
    Set<String> layerIds,
  });

  Future<void> upsertStroke(Stroke stroke);

  Future<void> deleteStroke(String strokeId);

  /// Bulk insert, used when replaying an imported or restored set of marks.
  Future<void> upsertStrokes(List<Stroke> strokes);
}
