import 'dart:io';


import 'package:fermata_core/fermata_core.dart';
import 'package:fermata_data/fermata_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_database.dart';

/// Builds a throwaway library rooted at a fresh temp directory.
Future<({AppDatabase database, FermataLayout layout, FileStore store, Directory root})>
makeLibrary() async {
  final root = await Directory.systemTemp.createTemp('fermata_test_');
  final layout = FermataLayout(root);
  await layout.ensureDirectories();
  return (
    database: openTestDatabase(),
    layout: layout,
    store: FileStore(layout),
    root: root,
  );
}

Future<DriftScoreRepository> makeScores(AppDatabase database) async =>
    DriftScoreRepository(database);

Future<File> writeTempFile(
  Directory directory,
  String name,
  List<int> bytes,
) async {
  final file = File(p.join(directory.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  return file;
}

/// A PDF page counter that returns a fixed count, standing in for pdfrx.
class FakePdfPageCounter implements PdfPageCounter {
  FakePdfPageCounter(this.pagesPerFile);

  final Map<String, int> pagesPerFile;
  int fallback = 1;

  @override
  Future<int> pageCount(String absolutePath) async =>
      pagesPerFile[absolutePath] ?? fallback;
}

void main() {
  late Directory root;
  late AppDatabase database;
  late FermataLayout layout;
  late FileStore store;

  setUp(() async {
    final library = await makeLibrary();
    root = library.root;
    database = library.database;
    layout = library.layout;
    store = library.store;
  });

  tearDown(() async {
    await database.close();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  group('AppDatabase', () {
    test('creates the full v1 schema', () async {
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          )
          .get();

      final names = tables.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        containsAll([
          'scores',
          'score_pages',
          'annotation_layers',
          'annotations',
          'tags',
          'score_tags',
          'setlists',
          'setlist_entries',
          'midi_files',
          'recordings',
          'pedal_mappings',
          'app_settings',
        ]),
      );
    });

    test('enables foreign keys so cascades fire', () async {
      final result = await database.customSelect('PRAGMA foreign_keys').get();
      expect(result.single.read<int>('foreign_keys'), 1);
    });
  });

  group('FermataLayout', () {
    test('builds the documented directory layout', () {
      expect(layout.databasePath, endsWith('fermata.sqlite'));
      expect(
        layout.scoreSourceDirectory('abc'),
        endsWith('scores${Platform.pathSeparator}abc${Platform.pathSeparator}source'),
      );
      expect(layout.thumbnailFile('abc'), endsWith('abc.png'));
    });

    test('ensureDirectories is idempotent', () async {
      await layout.ensureDirectories();
      await layout.ensureDirectories();

      expect(Directory(layout.scoresPath).existsSync(), isTrue);
      expect(Directory(layout.midiPath).existsSync(), isTrue);
    });
  });

  group('FileHasher', () {
    test('matches the known SHA-256 of an empty input', () async {
      final file = await writeTempFile(root, 'empty.bin', const []);

      expect(
        await FileHasher.sha256(file),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('matches the known SHA-256 of "abc"', () async {
      final file = await writeTempFile(root, 'abc.txt', 'abc'.codeUnits);

      expect(
        await FileHasher.sha256(file),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('hashes content larger than one chunk', () async {
      final bytes = List<int>.filled(200 * 1024, 0x41);
      final file = await writeTempFile(root, 'big.bin', bytes);

      final streamed = await FileHasher.sha256(file);
      final inMemory = FileHasher.sha256Bytes(bytes);

      expect(streamed, inMemory);
    });

    test('different content yields different hashes', () async {
      final a = await writeTempFile(root, 'a.txt', 'one'.codeUnits);
      final b = await writeTempFile(root, 'b.txt', 'two'.codeUnits);

      expect(await FileHasher.sha256(a), isNot(await FileHasher.sha256(b)));
    });
  });

  group('FileStore', () {
    test('imports a source and returns a relative path', () async {
      final source = await writeTempFile(root, 'score.pdf', [1, 2, 3]);

      final stored = await store.importScoreSource(
        scoreId: 'score-1',
        source: source,
      );

      expect(stored, 'score.pdf');
      expect(
        store.resolveScoreSource('score-1', stored).existsSync(),
        isTrue,
      );
    });

    test('keeps the copy after the original is deleted', () async {
      final source = await writeTempFile(root, 'keep.pdf', [1, 2, 3]);
      final stored = await store.importScoreSource(
        scoreId: 'score-1',
        source: source,
      );
      await source.delete();

      expect(
        store.resolveScoreSource('score-1', stored).readAsBytesSync(),
        [1, 2, 3],
      );
    });

    test('renames rather than overwriting a colliding filename', () async {
      final first = await writeTempFile(root, 'a/score.pdf', [1]);
      final second = await writeTempFile(root, 'b/score.pdf', [2]);

      final a = await store.importScoreSource(
        scoreId: 'score-1',
        source: first,
      );
      final b = await store.importScoreSource(
        scoreId: 'score-1',
        source: second,
      );

      expect(a, 'score.pdf');
      expect(b, 'score-2.pdf');
      expect(
        store.resolveScoreSource('score-1', 'score.pdf').readAsBytesSync(),
        [1],
      );
      expect(
        store.resolveScoreSource('score-1', 'score-2.pdf').readAsBytesSync(),
        [2],
      );
    });

    test('writeAtomic leaves no temp file behind', () async {
      final target = p.join(root.path, 'out.png');

      await store.writeAtomic(target, [1, 2, 3]);

      expect(File(target).existsSync(), isTrue);
      expect(File('$target.tmp').existsSync(), isFalse);
    });

    test('deletes a score directory and its thumbnail', () async {
      final source = await writeTempFile(root, 'score.pdf', [1]);
      await store.importScoreSource(scoreId: 'score-1', source: source);
      await store.writeAtomic(layout.thumbnailFile('score-1'), [1]);

      await store.deleteScoreAssets('score-1');

      expect(Directory(layout.scoreDirectory('score-1')).existsSync(), isFalse);
      expect(File(layout.thumbnailFile('score-1')).existsSync(), isFalse);
    });
  });

  group('AnnotationPointsCodec', () {
    test('round-trips points', () {
      final points = [
        const StrokePoint(position: NormalizedPoint(0.1, 0.2)),
        const StrokePoint(
          position: NormalizedPoint(0.3, 0.4),
          pressure: 0.65,
        ),
      ];

      final restored = AnnotationPointsCodec.decode(
        AnnotationPointsCodec.encode(points),
      );

      expect(restored.length, 2);
      expect(restored.first.position.x, closeTo(0.1, 1e-4));
      expect(restored.first.position.y, closeTo(0.2, 1e-4));
      expect(restored.first.pressure, 1.0);
      expect(restored.last.pressure, closeTo(0.65, 1e-4));
    });

    test('omits pressure when neutral', () {
      final encoded = AnnotationPointsCodec.encode([
        const StrokePoint(position: NormalizedPoint(0.5, 0.5)),
      ]);

      // Coordinates are stored as integers scaled by 1/10000 of a page.
      expect(encoded, '[[5000,5000]]');
    });

    test('survives a storage round trip through the database', () async {
      final annotations = DriftAnnotationRepository(database);
      await makeScores(database);
      final scores = DriftScoreRepository(database);
      await scores.createScore(
        score: _score('score-1'),
        pages: const [],
        layers: [_layer('score-1', 'layer-1')],
      );

      final stroke = Stroke(
        id: 'stroke-1',
        scoreId: 'score-1',
        pageIndex: 0,
        layerId: 'layer-1',
        kind: AnnotationKind.pen,
        colorValue: 0xFF000000,
        widthFraction: 0.01,
        createdAt: DateTime.utc(2026),
        points: [
          const StrokePoint(
            position: NormalizedPoint(0.123456, 0.654321),
            pressure: 0.42,
          ),
        ],
      );
      await annotations.upsertStroke(stroke);

      final loaded = await annotations.getStrokes(
        scoreId: 'score-1',
        pageIndex: 0,
      );

      expect(loaded.single.points.single.position.x, closeTo(0.123456, 1e-4));
      expect(loaded.single.points.single.pressure, closeTo(0.42, 1e-4));
    });
  });
}

Score _score(String id) => Score(
  id: id,
  title: 'Test Score',
  composer: 'Tester',
  dateAdded: DateTime.utc(2026),
  pageCount: 1,
);

AnnotationLayer _layer(String scoreId, String id) => AnnotationLayer(
  id: id,
  scoreId: scoreId,
  name: kDefaultLayerName,
  visible: true,
  sortOrder: 0,
  createdAt: DateTime.utc(2026),
);
