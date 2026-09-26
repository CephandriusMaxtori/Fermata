import 'package:drift/drift.dart';
import 'package:fermata_core/fermata_core.dart';

import '../db/app_database.dart';

/// drift-backed [ScoreRepository].
class DriftScoreRepository implements ScoreRepository {
  DriftScoreRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<Score>> watchScores(ScoreQuery query) {
    // Filtering and sorting are done in Dart rather than SQL. The library is a
    // personal collection measured in hundreds of scores, not thousands, and
    // keeping the sort rules in one place means the tag, setlist and
    // alphabetical orders cannot drift apart.
    return _database
        .select(_database.scores)
        .watch()
        .map((rows) => applyScoreQuery(rows.map(_toScore).toList(), query));
  }

  @override
  Future<List<Score>> getScores(ScoreQuery query) async {
    final rows = await _database.select(_database.scores).get();
    return applyScoreQuery(rows.map(_toScore).toList(), query);
  }

  @override
  Future<Score?> getScore(String scoreId) async {
    final row = await (_database.select(
      _database.scores,
    )..where((t) => t.id.equals(scoreId))).getSingleOrNull();
    return row == null ? null : _toScore(row);
  }

  @override
  Future<List<ScorePage>> getPages(String scoreId) async {
    final query = _database.select(_database.scorePages)
      ..where((t) => t.scoreId.equals(scoreId))
      ..orderBy([(t) => OrderingTerm.asc(t.pageIndex)]);
    final rows = await query.get();
    return rows.map(_toPage).toList(growable: false);
  }

  @override
  Stream<List<ScorePage>> watchPages(String scoreId) {
    final query = _database.select(_database.scorePages)
      ..where((t) => t.scoreId.equals(scoreId))
      ..orderBy([(t) => OrderingTerm.asc(t.pageIndex)]);
    return query.watch().map(
      (rows) => rows.map(_toPage).toList(growable: false),
    );
  }

  @override
  Future<Score> createScore({
    required Score score,
    required List<ScorePage> pages,
    List<AnnotationLayer> layers = const [],
  }) async {
    await _database.transaction(() async {
      await _database.into(_database.scores).insert(_scoreCompanion(score));
      await _database.batch((batch) {
        batch.insertAll(
          _database.scorePages,
          pages.map(_pageCompanion).toList(growable: false),
        );
        if (layers.isNotEmpty) {
          batch.insertAll(
            _database.annotationLayers,
            layers.map(_layerCompanion).toList(growable: false),
          );
        }
      });
    });
    return score;
  }

  @override
  Future<void> updateScore(Score score) async {
    await (_database.update(
      _database.scores,
    )..where((t) => t.id.equals(score.id))).write(_scoreCompanion(score));
  }

  @override
  Future<void> deleteScore(String scoreId) async {
    await (_database.delete(
      _database.scores,
    )..where((t) => t.id.equals(scoreId))).go();
  }

  @override
  Future<void> markOpened(String scoreId, DateTime when) async {
    await (_database.update(_database.scores)
          ..where((t) => t.id.equals(scoreId)))
        .write(ScoresCompanion(lastOpened: Value(when)));
  }

  @override
  Future<List<Score>> findByContentHash(String contentHash) async {
    final rows = await (_database.select(_database.scores)
          ..where((t) => t.contentHash.equals(contentHash)))
        .get();
    return rows.map(_toScore).toList(growable: false);
  }

  /// Sets the stored page geometry once a document has been measured.
  Future<void> updatePageGeometry(ScorePage page) async {
    await (_database.update(
      _database.scorePages,
    )..where((t) => t.id.equals(page.id))).write(
      ScorePagesCompanion(
        widthPt: Value(page.geometry?.widthPt),
        heightPt: Value(page.geometry?.heightPt),
      ),
    );
  }

  Score _toScore(ScoreRow row) => Score(
    id: row.id,
    title: row.title,
    composer: row.composer,
    dateAdded: row.dateAdded,
    lastOpened: row.lastOpened,
    pageCount: row.pageCount,
    contentHash: row.contentHash,
    thumbnailPath: row.thumbnailPath,
    linkedMidiId: row.linkedMidiId,
    notes: row.notes,
  );

  ScorePage _toPage(ScorePageRow row) => ScorePage(
    id: row.id,
    scoreId: row.scoreId,
    index: row.pageIndex,
    kind: PageSourceKind.fromName(row.kind),
    sourcePath: row.sourcePath,
    pdfPageNumber: row.pdfPageNumber,
    geometry: (row.widthPt != null && row.heightPt != null)
        ? PageGeometry(widthPt: row.widthPt!, heightPt: row.heightPt!)
        : null,
  );

  ScoresCompanion _scoreCompanion(Score score) => ScoresCompanion(
    id: Value(score.id),
    title: Value(score.title),
    composer: Value(score.composer),
    dateAdded: Value(score.dateAdded),
    lastOpened: Value(score.lastOpened),
    pageCount: Value(score.pageCount),
    contentHash: Value(score.contentHash),
    thumbnailPath: Value(score.thumbnailPath),
    linkedMidiId: Value(score.linkedMidiId),
    notes: Value(score.notes),
  );

  ScorePagesCompanion _pageCompanion(ScorePage page) => ScorePagesCompanion(
    id: Value(page.id),
    scoreId: Value(page.scoreId),
    pageIndex: Value(page.index),
    kind: Value(page.kind.name),
    sourcePath: Value(page.sourcePath),
    pdfPageNumber: Value(page.pdfPageNumber),
    widthPt: Value(page.geometry?.widthPt),
    heightPt: Value(page.geometry?.heightPt),
  );

  AnnotationLayersCompanion _layerCompanion(AnnotationLayer layer) =>
      AnnotationLayersCompanion(
        id: Value(layer.id),
        scoreId: Value(layer.scoreId),
        name: Value(layer.name),
        visible: Value(layer.visible),
        sortOrder: Value(layer.sortOrder),
        createdAt: Value(layer.createdAt),
      );
}

/// Applies filtering, setlist restriction and sorting to [scores].
///
/// Split out from the repository so the ordering rules are unit testable
/// without a database, and so the web UI can reproduce the same ordering.
List<Score> applyScoreQuery(List<Score> scores, ScoreQuery query) {
  Iterable<Score> result = scores;

  final search = query.searchText.trim().toLowerCase();
  if (search.isNotEmpty) {
    result = result.where(
      (score) =>
          score.title.toLowerCase().contains(search) ||
          score.composer.toLowerCase().contains(search),
    );
  }

  final filtered = result.toList(growable: false);

  return switch (query.sort) {
    ScoreSort.recentlyOpened => _sorted(filtered, (a, b) {
      // Never-opened scores sort last rather than first, since
      // DateTime.compare puts them at the epoch.
      final aTime = a.lastOpened ?? a.dateAdded;
      final bTime = b.lastOpened ?? b.dateAdded;
      return bTime.compareTo(aTime);
    }),
    ScoreSort.titleAscending =>
      _sorted(filtered, (a, b) => _compareTitles(a, b)),
    ScoreSort.composerAscending => _sorted(
      filtered,
      (a, b) => a.composer.toLowerCase().compareTo(
        b.composer.toLowerCase(),
      ),
    ),
    ScoreSort.dateAddedDescending =>
        _sorted(filtered, (a, b) => b.dateAdded.compareTo(a.dateAdded)),
  };
}

List<Score> _sorted(List<Score> scores, int Function(Score, Score) compare) {
  final copy = List<Score>.of(scores)..sort(compare);
  return copy;
}

int _compareTitles(Score a, Score b) {
  final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
}
