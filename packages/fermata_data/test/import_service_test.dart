import 'dart:convert';
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

/// A rasteriser that never touches crisp_notation.
///
/// The real one needs Flutter to load Bravura and rasterise, so the import
/// rules around a rendered source — page rows, stored paths, error mapping —
/// are pinned against this instead.
class StubMusicXmlRasteriser implements MusicXmlPageRasteriser {
  StubMusicXmlRasteriser({this.pages = 2, this.failWith, this.title, this.composer});

  final int pages;

  /// Thrown instead of rendering, to pin the error path.
  final Object? failWith;

  final String? title;
  final String? composer;

  /// Paths passed to [render], in call order.
  final List<String> requested = [];

  @override
  Future<MusicXmlRender> render(String absolutePath) async {
    requested.add(absolutePath);
    final failure = failWith;
    if (failure != null) throw failure;
    return MusicXmlRender(
      title: title,
      composer: composer,
      pages: [
        for (var i = 0; i < pages; i++)
          RenderedPage(
            // Distinct bytes per page, so a test can prove page N points at
            // image N rather than every row sharing the first one.
            pngBytes: utf8.encode('png-page-${i + 1}'),
            widthPx: 1240,
            heightPx: 1754,
          ),
      ],
    );
  }
}

ImportService makeServiceWithMusicXml(StubMusicXmlRasteriser rasteriser) =>
    ImportService(
      scoreRepository: scores,
      fileStore: store,
      pdfPageCounter: StubPdfPageCounter(),
      musicXmlRasteriser: rasteriser,
    );

Future<File> makeMusicXml(String name, {List<int>? bytes}) async =>
    makeFile(name, bytes ?? utf8.encode('<score-partwise/>'));

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

  group('MusicXML import', () {
    test('a .musicxml candidate is recognised as supported', () {
      expect(
        ImportCandidate(sourcePath: p.join('a', 'b.musicxml')).isMusicXml,
        isTrue,
      );
      expect(
        ImportCandidate(sourcePath: p.join('a', 'b.musicxml')).isSupported,
        isTrue,
      );
    });

    test('the zipped .mxl container is not yet accepted', () {
      // Deliberate: plain XML is what homr emits, and a clear rejection is
      // better than a half-supported container.
      final candidate = ImportCandidate(sourcePath: p.join('a', 'b.mxl'));
      expect(candidate.isMusicXml, isFalse);
      expect(candidate.isSupported, isFalse);
    });

    test('renders each page to its own PNG and points every row at it', () async {
      final file = await makeMusicXml('etude.musicxml');
      final rasteriser = StubMusicXmlRasteriser(pages: 3);

      final result = await makeServiceWithMusicXml(
        rasteriser,
      ).importScore([candidateFor(file)]);

      expect(rasteriser.requested, [file.path]);
      expect(result.pageCount, 3);
      expect(result.pages.map((p) => p.kind), everyElement(PageSourceKind.bitmap));
      expect(result.pages.map((p) => p.pdfPageNumber), everyElement(isNull));

      // Each row must name a *different* generated file, in page order.
      expect(
        result.pages.map((p) => p.sourcePath),
        [
          'etude-page-1.png',
          'etude-page-2.png',
          'etude-page-3.png',
        ],
      );

      // And the bytes on disk must be the ones the rasteriser produced, in the
      // right file. Every row sharing one image would still pass the checks above.
      for (final (i, page) in result.pages.indexed) {
        final written = store.resolveScoreSource(result.score.id, page.sourcePath);
        expect(written.existsSync(), isTrue, reason: 'page ${i + 1} missing');
        expect(await written.readAsBytes(), utf8.encode('png-page-${i + 1}'));
      }
    });

    test('keeps the .musicxml itself for provenance', () async {
      final file = await makeMusicXml('nocturne.musicxml');

      final result = await makeServiceWithMusicXml(
        StubMusicXmlRasteriser(pages: 1),
      ).importScore([candidateFor(file)]);

      // The document is what a future higher-resolution re-render would read,
      // so it must survive even though no page row points at it.
      final source = result.sources.single;
      expect(source.storedPath, 'nocturne.musicxml');
      expect(
        store.resolveScoreSource(result.score.id, source.storedPath).existsSync(),
        isTrue,
      );
    });

    test('stored page paths stay relative, as every stored path must', () async {
      final file = await makeMusicXml('relative.musicxml');

      final result = await makeServiceWithMusicXml(
        StubMusicXmlRasteriser(pages: 2),
      ).importScore([candidateFor(file)]);

      for (final page in result.pages) {
        expect(p.isRelative(page.sourcePath), isTrue, reason: page.sourcePath);
      }
    });

    test('a document that renders no pages is an error, not an empty score', () async {
      final file = await makeMusicXml('empty.musicxml');

      await expectLater(
        makeServiceWithMusicXml(
          StubMusicXmlRasteriser(pages: 0),
        ).importScore([candidateFor(file)]),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('rendered no pages'),
          ),
        ),
      );
    });

    test('an unrenderable document names the file that failed', () async {
      // The user picked several files and has to be told which to replace, so the
      // file name is load-bearing here rather than decoration.
      final file = await makeMusicXml('broken.musicxml');

      await expectLater(
        makeServiceWithMusicXml(
          StubMusicXmlRasteriser(failWith: const FormatException('bad xml')),
        ).importScore([candidateFor(file)]),
        throwsA(
          isA<ImportException>()
              .having((e) => e.message, 'message', contains('broken.musicxml'))
              .having((e) => e.message, 'message', contains('bad xml')),
        ),
      );
    });

    test('a missing rasteriser fails loudly rather than importing nothing', () async {
      final file = await makeMusicXml('nomlx.musicxml');

      await expectLater(
        makeService().importScore([candidateFor(file)]),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('No MusicXML rasteriser configured'),
          ),
        ),
      );
    });

    test('combines a rendered score with a scanned PDF in one import', () async {
      // Mixed picks are the normal case when a user has a PDF and a MusicXML of
      // the same piece, so the two page kinds must coexist in page order.
      final pdf = await makePdf('scan.pdf', [1, 2, 3], 2);
      final xml = await makeMusicXml('clean.musicxml');

      final result = await makeServiceWithMusicXml(
        StubMusicXmlRasteriser(pages: 2),
      ).importScore([candidateFor(pdf), candidateFor(xml)]);

      expect(
        result.pages.map((p) => p.kind),
        [
          PageSourceKind.pdf,
          PageSourceKind.pdf,
          PageSourceKind.bitmap,
          PageSourceKind.bitmap,
        ],
      );
      expect(result.pages.map((p) => p.index), [0, 1, 2, 3]);
      expect(
        result.pages.map((p) => p.pdfPageNumber),
        [1, 2, null, null],
      );
    });

    test('duplicates are still detected against the MusicXML bytes', () async {
      final first = await makeMusicXml('twin.musicxml', bytes: [1, 2, 3]);
      final service = makeServiceWithMusicXml(StubMusicXmlRasteriser());
      await service.importScore([candidateFor(first)]);

      final second = await makeMusicXml('other-name.musicxml', bytes: [1, 2, 3]);
      await expectLater(
        service.importScore([candidateFor(second)]),
        throwsA(isA<ImportException>()),
      );
    });
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
