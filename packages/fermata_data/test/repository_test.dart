import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:fermata_data/fermata_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory root;
late AppDatabase database;
late FileStore store;
late DriftScoreRepository scores;
late DriftAnnotationRepository annotations;

final _epoch = DateTime.utc(2026);

Score makeScore({
  String id = 'score-1',
  String title = 'Nocturne',
  String composer = 'Chopin',
  String? contentHash,
  DateTime? lastOpened,
  DateTime? dateAdded,
  int pageCount = 1,
}) => Score(
  id: id,
  title: title,
  composer: composer,
  dateAdded: dateAdded ?? DateTime.utc(2026, 1, 1),
  lastOpened: lastOpened,
  pageCount: pageCount,
  contentHash: contentHash,
);

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fermata_repo_test_');
    final layout = FermataLayout(root);
    await layout.ensureDirectories();
    store = FileStore(layout);
    database = AppDatabase(NativeDatabase.memory());
    scores = DriftScoreRepository(database);
    annotations = DriftAnnotationRepository(database);
  });

  tearDown(() async {
    await database.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('DriftScoreRepository', () {
    test('round-trips a score and its pages', () async {
      await scores.createScore(
        score: makeScore(contentHash: 'hash-1'),
        pages: const [
          ScorePage(
            id: 'page-1',
            scoreId: 'score-1',
            index: 0,
            kind: PageSourceKind.pdf,
            sourcePath: 'a.pdf',
            pdfPageNumber: 1,
          ),
          ScorePage(
            id: 'page-2',
            scoreId: 'score-1',
            index: 1,
            kind: PageSourceKind.bitmap,
            sourcePath: 'b.jpg',
          ),
        ],
      );

      final loaded = await scores.getScore('score-1');
      expect(loaded?.title, 'Nocturne');
      expect(loaded?.contentHash, 'hash-1');

      final pages = await scores.getPages('score-1');
      expect(pages.map((p) => p.index), [0, 1]);
      expect(pages.first.kind, PageSourceKind.pdf);
      expect(pages.first.pdfPageNumber, 1);
      expect(pages.last.kind, PageSourceKind.bitmap);
      expect(pages.last.pdfPageNumber, isNull);
    });

    test('pages come back in index order', () async {
      await scores.createScore(
        score: makeScore(),
        pages: [
          for (var i = 2; i >= 0; i--)
            ScorePage(
              id: 'page-$i',
              scoreId: 'score-1',
              index: i,
              kind: PageSourceKind.pdf,
              sourcePath: '$i.pdf',
              pdfPageNumber: i + 1,
            ),
        ],
      );

      expect(
        (await scores.getPages('score-1')).map((p) => p.index),
        [0, 1, 2],
      );
    });

    test('stores and reads back page geometry', () async {
      await scores.createScore(
        score: makeScore(),
        pages: const [
          ScorePage(
            id: 'page-1',
            scoreId: 'score-1',
            index: 0,
            kind: PageSourceKind.pdf,
            sourcePath: 'a.pdf',
            pdfPageNumber: 1,
            geometry: PageGeometry(widthPt: 612, heightPt: 792),
          ),
        ],
      );

      final page = (await scores.getPages('score-1')).single;
      expect(page.geometry?.widthPt, 612);
      expect(page.geometry?.heightPt, 792);
      expect(page.geometry?.aspectRatio, closeTo(612 / 792, 1e-9));
    });

    test('findByContentHash returns only exact matches', () async {
      await scores.createScore(
        score: makeScore(contentHash: 'hash-1'),
        pages: const [],
      );
      await scores.createScore(
        score: makeScore(id: 'score-2', contentHash: 'hash-2'),
        pages: const [],
      );

      expect((await scores.findByContentHash('hash-1')).single.id, 'score-1');
      expect(await scores.findByContentHash('missing'), isEmpty);
    });

    test('markOpened updates the sort key', () async {
      await scores.createScore(
        score: makeScore(),
        pages: const [],
      );

      final opened = DateTime.utc(2026, 6, 1);
      await scores.markOpened('score-1', opened);

      expect((await scores.getScore('score-1'))?.lastOpened?.toUtc(), opened);
    });

    test('watchScores emits on create and delete', () async {
      final emissions = <int>[];
      final sub = scores
          .watchScores(const ScoreQuery())
          .listen((list) => emissions.add(list.length));

      // Let the stream deliver its opening snapshot before mutating anything,
      // otherwise the first insert can land before the initial empty emission
      // and the sequence is not deterministic.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(emissions, [0]);

      await scores.createScore(score: makeScore(), pages: const []);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await scores.deleteScore('score-1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(emissions, [0, 1, 0]);
    });

    test('deleting a score cascades to its pages and layers', () async {
      await scores.createScore(
        score: makeScore(),
        pages: const [
          ScorePage(
            id: 'page-1',
            scoreId: 'score-1',
            index: 0,
            kind: PageSourceKind.pdf,
            sourcePath: 'a.pdf',
            pdfPageNumber: 1,
          ),
        ],
        layers: [
          AnnotationLayer(
            id: 'layer-1',
            scoreId: 'score-1',
            name: kDefaultLayerName,
            visible: true,
            sortOrder: 0,
            createdAt: DateTime.utc(2026),
          ),
        ],
      );

      await scores.deleteScore('score-1');

      expect(await scores.getPages('score-1'), isEmpty);
      expect(await annotations.getLayers('score-1'), isEmpty);
    });
  });

  group('applyScoreQuery', () {
    final library = [
      makeScore(
        id: 'a',
        title: 'Clair de Lune',
        composer: 'Debussy',
        lastOpened: DateTime.utc(2026, 3, 1),
      ),
      makeScore(
        id: 'b',
        title: 'avril',
        composer: 'Chopin',
        lastOpened: DateTime.utc(2026, 5, 1),
      ),
      makeScore(
        id: 'c',
        title: 'Étude',
        composer: 'Chopin',
        dateAdded: DateTime.utc(2026, 2, 1),
      ),
    ];

    test('filters by title, case-insensitively', () {
      final result = applyScoreQuery(library, const ScoreQuery(searchText: 'lune'));
      expect(result.map((s) => s.id), ['a']);
    });

    test('filters by composer', () {
      final result = applyScoreQuery(
        library,
        const ScoreQuery(searchText: 'chopin'),
      );
      expect(result.map((s) => s.id).toSet(), {'b', 'c'});
    });

    test('recently opened sorts the newest first', () {
      final result = applyScoreQuery(
        library,
        const ScoreQuery(sort: ScoreSort.recentlyOpened),
      );
      expect(result.first.id, 'b');
    });

    test('never-opened scores sort last, not first', () {
      final result = applyScoreQuery(
        library,
        const ScoreQuery(sort: ScoreSort.recentlyOpened),
      );
      expect(result.last.id, 'c');
    });

    test('title sort is case-insensitive', () {
      final result = applyScoreQuery(
        library,
        const ScoreQuery(sort: ScoreSort.titleAscending),
      );
      expect(result.map((s) => s.title), ['avril', 'Clair de Lune', 'Étude']);
    });

    test('composer sort groups by composer', () {
      final result = applyScoreQuery(
        library,
        const ScoreQuery(sort: ScoreSort.composerAscending),
      );
      expect(result.first.composer, 'Chopin');
      expect(result.last.composer, 'Debussy');
    });

    test('combines search and sort', () {
      final result = applyScoreQuery(
        library,
        const ScoreQuery(
          searchText: 'chopin',
          sort: ScoreSort.titleAscending,
        ),
      );
      expect(result.map((s) => s.title), ['avril', 'Étude']);
    });
  });

  group('DriftAnnotationRepository', () {
    Future<void> seedScore() => scores.createScore(
      score: makeScore(),
      pages: const [],
      layers: [
        AnnotationLayer(
          id: 'layer-1',
          scoreId: 'score-1',
          name: kDefaultLayerName,
          visible: true,
          sortOrder: 0,
          createdAt: _epoch,
        ),
      ],
    );

    test('stores and reloads a stroke with its points', () async {
      await seedScore();
      final stroke = Stroke(
        id: 'stroke-1',
        scoreId: 'score-1',
        pageIndex: 0,
        layerId: 'layer-1',
        kind: AnnotationKind.highlighter,
        colorValue: 0xFFFFEB3B,
        widthFraction: 0.03,
        createdAt: DateTime.utc(2026, 5, 5),
        points: [
          const StrokePoint(position: NormalizedPoint(0.1, 0.2)),
          const StrokePoint(position: NormalizedPoint(0.3, 0.4)),
        ],
      );

      await annotations.upsertStroke(stroke);
      final loaded = await annotations.getStrokes(
        scoreId: 'score-1',
        pageIndex: 0,
      );

      expect(loaded.single.kind, AnnotationKind.highlighter);
      expect(loaded.single.colorValue, 0xFFFFEB3B);
      expect(loaded.single.widthFraction, closeTo(0.03, 1e-4));
      expect(loaded.single.points, hasLength(2));
    });

    test('keeps strokes on different pages apart', () async {
      await seedScore();
      for (final page in [0, 1]) {
        await annotations.upsertStroke(
          Stroke(
            id: 'stroke-$page',
            scoreId: 'score-1',
            pageIndex: page,
            layerId: 'layer-1',
            kind: AnnotationKind.pen,
            colorValue: 1,
            widthFraction: 0.01,
            createdAt: DateTime.utc(2026),
            points: const [],
          ),
        );
      }

      expect(
        (await annotations.getStrokes(scoreId: 'score-1', pageIndex: 0)).length,
        1,
      );
      expect(
        (await annotations.getStrokes(scoreId: 'score-1', pageIndex: 1)).length,
        1,
      );
    });

    test('filters by layer', () async {
      await scores.createScore(score: makeScore(), pages: const []);
      await annotations.createLayer(scoreId: 'score-1', name: 'Teacher');
      final layers = await annotations.getLayers('score-1');

      for (final layer in layers) {
        await annotations.upsertStroke(
          Stroke(
            id: 'stroke-${layer.id}',
            scoreId: 'score-1',
            pageIndex: 0,
            layerId: layer.id,
            kind: AnnotationKind.pen,
            colorValue: 1,
            widthFraction: 0.01,
            createdAt: DateTime.utc(2026),
            points: const [],
          ),
        );
      }

      final filtered = await annotations.getStrokes(
        scoreId: 'score-1',
        pageIndex: 0,
        layerIds: {layers.first.id},
      );
      expect(filtered, hasLength(1));
    });

    test('upserting the same id replaces rather than duplicates', () async {
      await seedScore();
      Stroke strokeAt(double x) => Stroke(
        id: 'stroke-1',
        scoreId: 'score-1',
        pageIndex: 0,
        layerId: 'layer-1',
        kind: AnnotationKind.pen,
        colorValue: 1,
        widthFraction: 0.01,
        createdAt: DateTime.utc(2026),
        points: [StrokePoint(position: NormalizedPoint(x, x))],
      );

      await annotations.upsertStroke(strokeAt(0.1));
      await annotations.upsertStroke(strokeAt(0.9));

      final loaded = await annotations.getStrokes(
        scoreId: 'score-1',
        pageIndex: 0,
      );
      expect(loaded, hasLength(1));
      expect(loaded.single.points.single.position.x, closeTo(0.9, 1e-3));
    });

    test('deleting a layer removes its strokes', () async {
      await seedScore();
      await annotations.upsertStroke(
        Stroke(
          id: 'stroke-1',
          scoreId: 'score-1',
          pageIndex: 0,
          layerId: 'layer-1',
          kind: AnnotationKind.pen,
          colorValue: 1,
          widthFraction: 0.01,
          createdAt: DateTime.utc(2026),
          points: const [],
        ),
      );

      await annotations.deleteLayer('layer-1');

      expect(
        await annotations.getStrokes(scoreId: 'score-1', pageIndex: 0),
        isEmpty,
      );
    });

    test('layer visibility toggles independently', () async {
      await seedScore();
      final layer = (await annotations.getLayers('score-1')).single;

      await annotations.setLayerVisible(layer, visible: false);
      expect(
        (await annotations.getLayers('score-1')).single.visible,
        isFalse,
      );

      await annotations.setLayerVisible(layer, visible: true);
      expect((await annotations.getLayers('score-1')).single.visible, isTrue);
    });
  });

  group('DriftOrganizationRepository', () {
    late DriftOrganizationRepository organization;

    setUp(() {
      organization = DriftOrganizationRepository(database);
    });

    test('ensureTag is idempotent', () async {
      final first = await organization.ensureTag('Warm-ups');
      final second = await organization.ensureTag('Warm-ups');

      expect(first.id, second.id);
      expect(await organization.getTags(), hasLength(1));
    });

    test('assigns and reads score tags', () async {
      await scores.createScore(score: makeScore(), pages: const []);
      final tag = await organization.ensureTag('Jazz');

      await organization.setScoreTags('score-1', {tag.id});

      expect(await organization.getScoreTagIds('score-1'), {tag.id});
    });

    test('setScoreTags replaces the previous set', () async {
      await scores.createScore(score: makeScore(), pages: const []);
      final first = await organization.ensureTag('A');
      final second = await organization.ensureTag('B');

      await organization.setScoreTags('score-1', {first.id});
      await organization.setScoreTags('score-1', {second.id});

      expect(await organization.getScoreTagIds('score-1'), {second.id});
    });

    test('setlist preserves insertion order', () async {
      final setlist = await organization.createSetlist('Concert');
      for (final id in ['a', 'b', 'c']) {
        await scores.createScore(
          score: makeScore(id: id),
          pages: const [],
        );
        await organization.addScoreToSetlist(setlist.id, id);
      }

      final entries = await organization.getEntries(setlist.id);
      expect(entries.map((e) => e.scoreId), ['a', 'b', 'c']);
      expect(entries.map((e) => e.position), [0, 1, 2]);
    });

    test('reordering keeps positions contiguous', () async {
      final setlist = await organization.createSetlist('Concert');
      for (final id in ['a', 'b', 'c']) {
        await scores.createScore(score: makeScore(id: id), pages: const []);
        await organization.addScoreToSetlist(setlist.id, id);
      }

      await organization.moveSetlistEntry(setlist.id, 'c', 0);

      final entries = await organization.getEntries(setlist.id);
      expect(entries.map((e) => e.scoreId), ['c', 'a', 'b']);
      expect(entries.map((e) => e.position), [0, 1, 2]);
    });

    test('adding the same score twice is a no-op', () async {
      final setlist = await organization.createSetlist('Concert');
      await scores.createScore(score: makeScore(), pages: const []);

      await organization.addScoreToSetlist(setlist.id, 'score-1');
      await organization.addScoreToSetlist(setlist.id, 'score-1');

      expect(await organization.getEntries(setlist.id), hasLength(1));
    });

    test('removing from the middle closes the gap', () async {
      final setlist = await organization.createSetlist('Concert');
      for (final id in ['a', 'b', 'c']) {
        await scores.createScore(score: makeScore(id: id), pages: const []);
        await organization.addScoreToSetlist(setlist.id, id);
      }

      await organization.removeScoreFromSetlist(setlist.id, 'b');

      final entries = await organization.getEntries(setlist.id);
      expect(entries.map((e) => e.scoreId), ['a', 'c']);
      expect(entries.map((e) => e.position), [0, 1]);
    });
  });

  group('DriftPlaybackRepository', () {
    test('stores and reloads playback edits', () async {
      final playback = DriftPlaybackRepository(database);
      final midi = await playback.createMidiFile(
        title: 'Arabesque',
        relativePath: 'abc.mid',
      );

      const edits = PlaybackEdits(
        tempoScale: 0.6,
        loop: LoopRange(startTick: 480, endTick: 960),
        mutedChannels: {1, 2},
        countInBars: 1,
        cuePoints: [CuePoint(tick: 0, label: 'A')],
      );
      await playback.saveEdits(midi.id, edits);

      final loaded = await playback.getMidiFile(midi.id);
      expect(loaded?.edits.tempoScale, 0.6);
      expect(loaded?.edits.loop?.startTick, 480);
      expect(loaded?.edits.mutedChannels, {1, 2});
      expect(loaded?.edits.countInBars, 1);
      expect(loaded?.edits.cuePoints.single.label, 'A');
    });

    test('malformed edit JSON falls back to defaults', () async {
      final playback = DriftPlaybackRepository(database);
      final midi = await playback.createMidiFile(
        title: 'Broken',
        relativePath: 'broken.mid',
      );

      await database.update(
        database.midiFiles,
      ).write(MidiFilesCompanion(editsJson: const Value('{not json')));

      final loaded = await playback.getMidiFile(midi.id);
      expect(loaded?.edits.tempoScale, 1.0);
    });
  });

  group('DriftPedalMappingRepository', () {
    test('resetToDefaults installs the shipped mappings', () async {
      final pedals = DriftPedalMappingRepository(database);

      await pedals.resetToDefaults();

      final mappings = await pedals.getMappings();
      expect(mappings, hasLength(kDefaultPedalMappings.length));
      expect(
        mappings.map((m) => m.action),
        contains(PedalAction.nextPage),
      );
    });

    test('saveMapping upserts by id', () async {
      final pedals = DriftPedalMappingRepository(database);

      await pedals.saveMapping(
        const PedalMapping(
          id: 'custom',
          keyLabel: 'Key F',
          action: PedalAction.nextPage,
        ),
      );
      await pedals.saveMapping(
        const PedalMapping(
          id: 'custom',
          keyLabel: 'Key G',
          action: PedalAction.previousPage,
        ),
      );

      final mappings = await pedals.getMappings();
      expect(mappings, hasLength(1));
      expect(mappings.single.keyLabel, 'Key G');
    });
  });

  group('layout paths are relative-friendly', () {
    test('source paths recorded by import are relative', () async {
      final source = File(p.join(root.path, 'incoming.pdf'));
      await source.writeAsBytes([1, 2, 3]);

      final stored = await store.importScoreSource(
        scoreId: 'score-1',
        source: source,
      );

      expect(p.isRelative(stored), isTrue);
    });
  });
}
