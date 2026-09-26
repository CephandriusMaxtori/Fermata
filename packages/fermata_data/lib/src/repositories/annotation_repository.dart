import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fermata_core/fermata_core.dart';

import '../db/annotation_points_codec.dart';
import '../db/app_database.dart';

/// drift-backed [AnnotationRepository].
class DriftAnnotationRepository implements AnnotationRepository {
  DriftAnnotationRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<AnnotationLayer>> getLayers(String scoreId) async {
    final query = _database.select(_database.annotationLayers)
      ..where((t) => t.scoreId.equals(scoreId))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    final rows = await query.get();
    return rows.map(_toLayer).toList(growable: false);
  }

  @override
  Stream<List<AnnotationLayer>> watchLayers(String scoreId) {
    final query = _database.select(_database.annotationLayers)
      ..where((t) => t.scoreId.equals(scoreId))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return query.watch().map(
      (rows) => rows.map(_toLayer).toList(growable: false),
    );
  }

  @override
  Future<AnnotationLayer> createLayer({
    required String scoreId,
    required String name,
  }) async {
    final existing = await getLayers(scoreId);
    final layer = AnnotationLayer(
      id: newId(),
      scoreId: scoreId,
      name: name,
      visible: true,
      sortOrder: existing.length,
      createdAt: DateTime.now().toUtc(),
    );
    await _database.into(_database.annotationLayers).insert(
      AnnotationLayersCompanion.insert(
        id: layer.id,
        scoreId: layer.scoreId,
        name: layer.name,
        visible: Value(layer.visible),
        sortOrder: Value(layer.sortOrder),
        createdAt: layer.createdAt,
      ),
    );
    return layer;
  }

  @override
  Future<void> renameLayer(AnnotationLayer layer, String name) async {
    await (_database.update(
      _database.annotationLayers,
    )..where((t) => t.id.equals(layer.id))).write(
      AnnotationLayersCompanion(name: Value(name)),
    );
  }

  @override
  Future<void> setLayerVisible(AnnotationLayer layer, {required bool visible}) async {
    await (_database.update(
      _database.annotationLayers,
    )..where((t) => t.id.equals(layer.id))).write(
      AnnotationLayersCompanion(visible: Value(visible)),
    );
  }

  @override
  Future<void> deleteLayer(String layerId) async {
    await (_database.delete(
      _database.annotationLayers,
    )..where((t) => t.id.equals(layerId))).go();
  }

  @override
  Future<List<Stroke>> getStrokes({
    required String scoreId,
    required int pageIndex,
    Set<String> layerIds = const {},
  }) async {
    final rows = await _strokesQuery(
      scoreId: scoreId,
      pageIndex: pageIndex,
      layerIds: layerIds,
    ).get();
    return rows.map(_toStroke).toList(growable: false);
  }

  @override
  Stream<List<Stroke>> watchStrokes({
    required String scoreId,
    required int pageIndex,
    Set<String> layerIds = const {},
  }) {
    return _strokesQuery(
      scoreId: scoreId,
      pageIndex: pageIndex,
      layerIds: layerIds,
    ).watch().map((rows) => rows.map(_toStroke).toList(growable: false));
  }

  @override
  Future<void> upsertStroke(Stroke stroke) async {
    await _database.into(_database.annotations).insertOnConflictUpdate(
      _strokeCompanion(stroke),
    );
  }

  @override
  Future<void> upsertStrokes(List<Stroke> strokes) async {
    if (strokes.isEmpty) return;
    await _database.batch(
      (batch) => batch.insertAllOnConflictUpdate(
        _database.annotations,
        strokes.map(_strokeCompanion).toList(growable: false),
      ),
    );
  }

  @override
  Future<void> deleteStroke(String strokeId) async {
    await (_database.delete(
      _database.annotations,
    )..where((t) => t.id.equals(strokeId))).go();
  }

  /// Deletes many strokes at once, used by the eraser and by undo.
  Future<void> deleteStrokes(Set<String> strokeIds) async {
    if (strokeIds.isEmpty) return;
    await (_database.delete(_database.annotations)
          ..where((t) => t.id.isIn(strokeIds)))
        .go();
  }
  Selectable<AnnotationRow> _strokesQuery({
    required String scoreId,
    required int pageIndex,
    required Set<String> layerIds,
  }) {
    final query = _database.select(_database.annotations)
      ..where(
        (t) => t.scoreId.equals(scoreId) & t.pageIndex.equals(pageIndex),
      )
      // drift stores DateTime as whole unix seconds, so two strokes drawn in the
      // same second tie on createdAt. Ids are time-prefixed to microsecond
      // precision, so they break the tie in the order the strokes were made,
      // which is what the draw order and the undo stack depend on.
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    if (layerIds.isNotEmpty) {
      query.where((t) => t.layerId.isIn(layerIds));
    }
    return query;
  }

  AnnotationLayer _toLayer(AnnotationLayerRow row) => AnnotationLayer(
    id: row.id,
    scoreId: row.scoreId,
    name: row.name,
    visible: row.visible,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
  );

  Stroke _toStroke(AnnotationRow row) => Stroke(
    id: row.id,
    scoreId: row.scoreId,
    pageIndex: row.pageIndex,
    layerId: row.layerId,
    kind: AnnotationKind.fromName(row.kind),
    colorValue: row.colorValue,
    widthFraction: row.widthFraction,
    points: AnnotationPointsCodec.decode(row.pointsJson),
    createdAt: row.createdAt,
  );

  AnnotationsCompanion _strokeCompanion(Stroke stroke) =>
      AnnotationsCompanion.insert(
        id: stroke.id,
        scoreId: stroke.scoreId,
        pageIndex: stroke.pageIndex,
        layerId: stroke.layerId,
        kind: stroke.kind.name,
        colorValue: stroke.colorValue,
        widthFraction: stroke.widthFraction,
        pointsJson: AnnotationPointsCodec.encode(stroke.points),
        createdAt: stroke.createdAt,
      );
}

/// Generates a collision-resistant identifier for a new row.
///
/// Time-prefixed so ids sort roughly by creation order, which makes a data
/// directory far easier to read while debugging than fully random ids.
String newId() {
  final timestamp = DateTime.now()
      .toUtc()
      .microsecondsSinceEpoch
      .toRadixString(36);
  final suffix = List<int>.generate(8, (_) => _random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$timestamp-$suffix';
}

final Random _random = Random.secure();
