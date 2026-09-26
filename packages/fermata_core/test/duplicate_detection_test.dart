import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

Score scoreWith({
  required String id,
  String title = 'Untitled',
  String composer = 'Unknown',
  String? contentHash,
}) {
  return Score(
    id: id,
    title: title,
    composer: composer,
    dateAdded: DateTime.utc(2026),
    pageCount: 1,
    contentHash: contentHash,
  );
}

void main() {
  group('normalizeForComparison', () {
    test('lowercases and collapses punctuation and whitespace', () {
      expect(
        normalizeForComparison('  Clarin---  de   LUNE!  '),
        'clarin de lune',
      );
    });

    test('strips diacritics so accented titles compare equal', () {
      expect(
        normalizeForComparison('Café au lait'),
        normalizeForComparison('Cafe au lait'),
      );
    });

    test('folds precomposed and decomposed forms identically', () {
      // U+00E9 versus "e" plus U+0301 must land on the same string.
      expect(
        normalizeForComparison('Café'),
        normalizeForComparison('Cafe\u0301'),
      );
    });

    test('folds the Latin letters common in repertoire titles', () {
      expect(normalizeForComparison('Dvořák'), 'dvorak');
      expect(normalizeForComparison('Čajkovskij'), 'cajkovskij');
      expect(normalizeForComparison('Łódź'), 'lodz');
      expect(normalizeForComparison('Straße'), 'strasse');
      expect(normalizeForComparison('Ærøskøbing'), 'aeroskobing');
      expect(normalizeForComparison('Cœur'), 'coeur');
      expect(normalizeForComparison('Sibelius'), 'sibelius');
    });

    test('expands ligatures and stroked letters', () {
      expect(normalizeForComparison('Æther'), 'aether');
      expect(normalizeForComparison('Ørsted'), 'orsted');
      expect(normalizeForComparison('Œuvre'), 'oeuvre');
    });

    test('folds case before expanding, so capitals fold correctly', () {
      expect(normalizeForComparison('DVOŘÁK'), 'dvorak');
      expect(normalizeForComparison('ÉCLAIR'), 'eclair');
    });

    test('keeps non-Latin scripts intact', () {
      expect(normalizeForComparison('Лунный свет'), 'лунный свет');
      expect(normalizeForComparison('月光'), '月光');
      expect(normalizeForComparison('Clair de Lune 月光'), 'clair de lune 月光');
    });

    test('returns an empty string for input with no letters or numbers', () {
      expect(normalizeForComparison('--- ... !!!'), isEmpty);
    });
  });

  group('coreTitle', () {
    test('drops bracketed catalogue numbers', () {
      expect(coreTitle('Clair de Lune (R. 75)'), 'clair de lune');
      expect(coreTitle('Nocturne [Op. 9 No. 2]'), 'nocturne');
    });

    test('leaves an unbracketed title alone', () {
      expect(coreTitle('Nocturne in E flat'), 'nocturne in e flat');
    });
  });

  group('assessDuplicates', () {
    test('reports nothing for an empty library', () {
      final result = assessDuplicates(
        contentHash: 'abc',
        title: 'Sonata',
        composer: 'Mozart',
        existingScores: const [],
      );

      expect(result.verdict, DuplicateVerdict.none);
      expect(result.isExactDuplicate, isFalse);
      expect(result.hasMetadataSuggestion, isFalse);
    });

    test('blocks an exact content hash match', () {
      final existing = scoreWith(
        id: 'score-1',
        title: 'Totally Different Title',
        composer: 'Someone Else',
        contentHash: 'abc',
      );

      final result = assessDuplicates(
        contentHash: 'abc',
        title: 'Sonata',
        composer: 'Mozart',
        existingScores: [existing],
      );

      expect(result.verdict, DuplicateVerdict.exactContent);
      expect(result.isExactDuplicate, isTrue);
      expect(result.blockingScore?.id, 'score-1');
    });

    test('an exact hash match wins even when metadata disagrees', () {
      final existing = scoreWith(
        id: 'score-1',
        title: 'Sonata in C',
        composer: 'Haydn',
        contentHash: 'abc',
      );

      final result = assessDuplicates(
        contentHash: 'abc',
        title: 'Sonata in C',
        composer: 'Mozart',
        existingScores: [existing],
      );

      expect(result.verdict, DuplicateVerdict.exactContent);
    });

    test('only suggests, and never blocks, on a metadata match', () {
      final existing = scoreWith(
        id: 'score-1',
        title: 'Nocturne in E-flat',
        composer: 'Chopin',
        contentHash: 'hash-a',
      );

      final result = assessDuplicates(
        contentHash: 'hash-b',
        title: 'nocturne in e flat',
        composer: 'CHOPIN',
        existingScores: [existing],
      );

      expect(result.verdict, DuplicateVerdict.metadata);
      expect(result.isExactDuplicate, isFalse);
      expect(result.hasMetadataSuggestion, isTrue);
      expect(result.metadataMatches.single.id, 'score-1');
      expect(result.blockingScore, isNull);
    });

    test('suggests across differing bracketed suffixes', () {
      final existing = scoreWith(
        id: 'score-1',
        title: 'Clair de Lune (R. 75)',
        composer: 'Debussy',
        contentHash: 'hash-a',
      );

      final result = assessDuplicates(
        contentHash: 'hash-b',
        title: 'Clair de Lune',
        composer: 'Debussy',
        existingScores: [existing],
      );

      expect(result.hasMetadataSuggestion, isTrue);
    });

    test('requires the composer to match too', () {
      final existing = scoreWith(
        id: 'score-1',
        title: 'Nocturne',
        composer: 'Chopin',
        contentHash: 'hash-a',
      );

      final result = assessDuplicates(
        contentHash: 'hash-b',
        title: 'Nocturne',
        composer: 'Liszt',
        existingScores: [existing],
      );

      expect(result.verdict, DuplicateVerdict.none);
    });

    test('does not treat two unrelated works as duplicates', () {
      final existing = [
        scoreWith(id: 'a', title: 'Nocturne', composer: 'Chopin'),
        scoreWith(id: 'b', title: 'Etude', composer: 'Chopin'),
      ];

      final result = assessDuplicates(
        contentHash: 'hash-c',
        title: 'Mazurka',
        composer: 'Chopin',
        existingScores: existing,
      );

      expect(result.verdict, DuplicateVerdict.none);
    });

    test('ignores scores with no recorded hash', () {
      final existing = scoreWith(id: 'a', title: 'Etude', composer: 'Chopin');

      final result = assessDuplicates(
        contentHash: 'abc',
        title: 'Etude',
        composer: 'Chopin',
        existingScores: [existing],
      );

      expect(result.isExactDuplicate, isFalse);
    });

    test('matches non-Latin metadata', () {
      final existing = scoreWith(
        id: 'a',
        title: 'Лунный свет',
        composer: 'Римский-Корсаков',
        contentHash: 'hash-a',
      );

      final result = assessDuplicates(
        contentHash: 'hash-b',
        title: 'Лунный Свет',
        composer: 'Римский-Корсаков',
        existingScores: [existing],
      );

      expect(result.hasMetadataSuggestion, isTrue);
    });
  });

  group('ScoreQuery', () {
    test('is unfiltered by default', () {
      expect(const ScoreQuery().hasFilters, isFalse);
    });

    test('reports filters for search text, tags and setlists', () {
      expect(const ScoreQuery(searchText: 'x').hasFilters, isTrue);
      expect(const ScoreQuery(tagIds: {'t'}).hasFilters, isTrue);
      expect(const ScoreQuery(setlistId: 's').hasFilters, isTrue);
      expect(const ScoreQuery(searchText: '  ').hasFilters, isFalse);
    });

    test('copyWith can clear a setlist filter', () {
      const query = ScoreQuery(setlistId: 's');

      expect(query.copyWith(clearSetlist: true).setlistId, isNull);
      expect(query.copyWith().setlistId, 's');
    });

    test('compares tag sets irrespective of order', () {
      const a = ScoreQuery(tagIds: {'x', 'y'});
      const b = ScoreQuery(tagIds: {'y', 'x'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
