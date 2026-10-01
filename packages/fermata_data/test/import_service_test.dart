import 'dart:io';


import 'package:fermata_core/fermata_core.dart';
import 'package:fermata_data/fermata_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_database.dart';

late Directory root;
late AppDatabase database;
late DriftScoreRepository scores;
late FileStore store;
late Map<String, int> pdfPageCounts;

class StubPdfPageCounter implements PdfPageCounter {
  @override
  Future<int> pageCount(String absolutePath) async {
    final count = pdfPageCounts[absolutePath];
    if (count == null) {
      throw ImportException('Unknown PDF in test: $absolutePath');
    }
    return count;
  }
}

ImportService makeService() => ImportService(
  scoreRepository: scores,
  fileStore: store,
  pdfPageCounter: StubPdfPageCounter(),
);

Future<File> makeFile(String name, List<int> bytes) async {
  final file = File(p.join(root.path, 'picked', name));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  return file;
}

Future<File> makePdf(String name, List<int> bytes, int pages) async {
  final file = await makeFile(name, bytes);
  pdfPageCounts[file.path] = pages;
  return file;
}

ImportCandidate candidateFor(File file, {String? title, String? composer}) =>
    ImportCandidate(
      sourcePath: file.path,
      title: title,
      composer: composer,
    );

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fermata_import_test_');
    pdfPageCounts = {};
    final layout = FermataLayout(root);
    await layout.ensureDirectories();
    store = FileStore(layout);
    database = openTestDatabase();
    scores = DriftScoreRepository(database);
  });

  tearDown(() async {
    await database.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('importScore', () {
    test('imports a single-page PDF as one page', () async {
      final pdf = await makePdf('nocturne.pdf', [1, 2, 3], 1);

      final result = await makeService().importScore([candidateFor(pdf)]);

      expect(result.pageCount, 1);
      expect(result.pages.single.kind, PageSourceKind.pdf);
      expect(result.pages.single.pdfPageNumber, 1);
      expect(result.score.title, 'nocturne');
      expect(result.score.pageCount, 1);
    });

    test('expands a multi-page PDF into one page row per page', () async {
      final pdf = await makePdf('sonata.pdf', [1, 2, 3], 5);

      final result = await makeService().importScore([candidateFor(pdf)]);

      expect(result.pageCount, 5);
      expect(result.pages.map((p) => p.index), [0, 1, 2, 3, 4]);
      expect(result.pages.map((p) => p.pdfPageNumber), [1, 2, 3, 4, 5]);
    });

    test('imports an image as a single bitmap page', () async {
      final image = await makeFile('scan.jpg', [9, 9, 9]);

      final result = await makeService().importScore([candidateFor(image)]);

      expect(result.pageCount, 1);
      expect(result.pages.single.kind, PageSourceKind.bitmap);
      expect(result.pages.single.pdfPageNumber, isNull);
    });

    test('combines several files in picker order', () async {
      final first = await makePdf('one.pdf', [1], 2);
      final second = await makeFile('two.jpg', [2]);
      final third = await makePdf('three.pdf', [3], 1);

      final result = await makeService().importScore([
        candidateFor(first),
        candidateFor(second),
        candidateFor(third),
      ]);

      expect(result.pageCount, 4);
      expect(
        result.pages.map((p) => p.kind),
        [
          PageSourceKind.pdf,
          PageSourceKind.pdf,
          PageSourceKind.bitmap,
          PageSourceKind.pdf,
        ],
      );
      expect(result.pages.map((p) => p.index), [0, 1, 2, 3]);
    });

    test('copies sources into the score directory', () async {
      final pdf = await makePdf('nocturne.pdf', [1, 2, 3], 1);

      final result = await makeService().importScore([candidateFor(pdf)]);

      final stored = File(
        p.join(
          store.layout.scoreSourceDirectory(result.score.id),
          result.pages.single.sourcePath,
        ),
      );
      expect(stored.existsSync(), isTrue);
      expect(stored.readAsBytesSync(), [1, 2, 3]);
    });

    test('records a content hash matching the source bytes', () async {
      final pdf = await makePdf('a.pdf', [1, 2, 3], 1);

      final result = await makeService().importScore([candidateFor(pdf)]);

      expect(
        result.score.contentHash,
        FileHasher.sha256Bytes([1, 2, 3]),
      );
    });

    test('creates a default annotation layer', () async {
      final pdf = await makePdf('a.pdf', [1], 1);

      final result = await makeService().importScore([candidateFor(pdf)]);

      final layers = await DriftAnnotationRepository(
        database,
      ).getLayers(result.score.id);
      expect(layers.single.name, kDefaultLayerName);
      expect(layers.single.visible, isTrue);
    });

    test('title and composer overrides win', () async {
      final pdf = await makePdf('scan001.pdf', [1], 1);

      final result = await makeService().importScore(
        [candidateFor(pdf)],
        title: 'Nocturne in E-flat',
        composer: 'Chopin',
      );

      expect(result.score.title, 'Nocturne in E-flat');
      expect(result.score.composer, 'Chopin');
    });

    test('falls back to PDF metadata for the title', () async {
      final pdf = await makePdf('scan001.pdf', [1], 1);

      final result = await makeService().importScore([
        candidateFor(pdf, title: 'From Metadata', composer: 'Anon'),
      ]);

      expect(result.score.title, 'From Metadata');
      expect(result.score.composer, 'Anon');
    });

    test('reports progress through every file', () async {
      final first = await makePdf('a.pdf', [1], 1);
      final second = await makeFile('b.jpg', [2]);
      final service = makeService();

      final phases = <ImportPhase>[];
      final sub = service.progress.listen((p) => phases.add(p.phase));

      await service.importScore([candidateFor(first), candidateFor(second)]);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(phases, contains(ImportPhase.hashing));
      expect(phases, contains(ImportPhase.copying));
      expect(phases.last, ImportPhase.done);
    });

    test('rejects a selection with nothing importable', () async {
      final text = await makeFile('notes.txt', [1]);

      expect(
        () => makeService().importScore([candidateFor(text)]),
        throwsA(isA<ImportException>()),
      );
    });

    test('rejects an empty selection', () async {
      expect(
        () => makeService().importScore(const []),
        throwsA(isA<ImportException>()),
      );
    });

    test('skips unsupported files but keeps the importable ones', () async {
      final pdf = await makePdf('a.pdf', [1], 1);
      final text = await makeFile('notes.txt', [1]);

      final result = await makeService().importScore([
        candidateFor(pdf),
        candidateFor(text),
      ]);

      expect(result.pageCount, 1);
    });
  });

  group('duplicate handling on import', () {
    test('refuses a byte-identical re-import', () async {
      final pdf = await makePdf('nocturne.pdf', [1, 2, 3], 1);
      final service = makeService();
      await service.importScore([candidateFor(pdf)]);

      final again = await makePdf('copy-of-nocturne.pdf', [1, 2, 3], 1);

      expect(
        () => service.importScore([candidateFor(again)]),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('already in your library'),
          ),
        ),
      );
    });

    test('imports a re-scan of the same piece with a warning', () async {
      final first = await makePdf(
        'edition1.pdf',
        [1, 1, 1],
        1,
      );
      final second = await makePdf(
        'edition2.pdf',
        [2, 2, 2],
        1,
      );
      final service = makeService();

      await service.importScore([
        candidateFor(first, title: 'Nocturne', composer: 'Chopin'),
      ]);
      final result = await service.importScore([
        candidateFor(second, title: 'nocturne', composer: 'CHOPIN'),
      ]);

      expect(result.duplicateWarning, hasLength(1));
      expect(result.score.pageCount, 1);
      expect(await scores.getScores(const ScoreQuery()), hasLength(2));
    });

    test('different pieces are not flagged', () async {
      final first = await makePdf('a.pdf', [1], 1);
      final second = await makePdf('b.pdf', [2], 1);
      final service = makeService();

      await service.importScore([
        candidateFor(first, title: 'Nocturne', composer: 'Chopin'),
      ]);
      final result = await service.importScore([
        candidateFor(second, title: 'Etude', composer: 'Chopin'),
      ]);

      expect(result.duplicateWarning, isEmpty);
    });
  });

  group('preview', () {
    test('reports an exact duplicate before anything is written', () async {
      final pdf = await makePdf('a.pdf', [1, 2, 3], 1);
      final service = makeService();
      await service.importScore([candidateFor(pdf)]);

      final again = await makePdf('a-copy.pdf', [1, 2, 3], 1);
      final preview = await service.preview([candidateFor(again)]);

      expect(preview.hasExactDuplicate, isTrue);
      expect(preview.canImport, isFalse);
      expect(preview.exactDuplicate!.blockingScore!.title, 'a');
    });

    test('reports a metadata suggestion without blocking', () async {
      final first = await makePdf('a.pdf', [1], 1);
      final second = await makePdf('b.pdf', [2], 1);
      final service = makeService();
      await service.importScore([
        candidateFor(first, title: 'Nocturne', composer: 'Chopin'),
      ]);

      final preview = await service.preview([
        candidateFor(second, title: 'Nocturne', composer: 'Chopin'),
      ]);

      expect(preview.hasExactDuplicate, isFalse);
      expect(preview.hasMetadataSuggestion, isTrue);
      expect(preview.canImport, isTrue);
    });

    test('lists unsupported files', () async {
      final text = await makeFile('notes.txt', [1]);

      final preview = await makeService().preview([candidateFor(text)]);

      expect(preview.unsupportedFiles, ['notes.txt']);
      expect(preview.canImport, isFalse);
    });
  });
}
