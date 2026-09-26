import '../models/score.dart';

/// How confident we are that an import is already in the library.
enum DuplicateVerdict {
  /// Nothing similar found.
  none,

  /// Byte-identical content (matching SHA-256). Import should be blocked.
  exactContent,

  /// Same title and composer, different bytes. Import may continue.
  metadata,
}

/// The outcome of checking a candidate file against the existing library.
class DuplicateAssessment {
  const DuplicateAssessment({
    required this.verdict,
    this.contentHash,
    this.exactMatches = const [],
    this.metadataMatches = const [],
  });

  const DuplicateAssessment.none()
    : verdict = DuplicateVerdict.none,
      contentHash = null,
      exactMatches = const [],
      metadataMatches = const [];

  final DuplicateVerdict verdict;
  final String? contentHash;

  /// Scores whose stored content hash matches. Non-empty means block.
  final List<Score> exactMatches;

  /// Scores whose normalized title and composer match. Advisory only.
  final List<Score> metadataMatches;

  bool get isExactDuplicate => exactMatches.isNotEmpty;

  bool get hasMetadataSuggestion => metadataMatches.isNotEmpty;

  /// The score the import dialog should offer to open instead.
  Score? get blockingScore => exactMatches.isEmpty ? null : exactMatches.first;
}

/// Folds case, strips diacritics, and collapses punctuation and whitespace.
///
/// Used to make title and composer comparison tolerant of re-scans and
/// re-exports without attempting real fuzzy matching.
///
/// Latin letters are folded through [_latinFolding] *before* any case handling,
/// which is deliberate: `toLowerCase()` would remap codes such as U+0179 to
/// U+017A, so a table written against the original code points would silently
/// fold the wrong letter. Everything the table emits is already lowercase, so
/// no separate case pass is needed.
String normalizeForComparison(String input) {
  final buffer = StringBuffer();
  var pendingSpace = false;

  void emit(String text) {
    if (pendingSpace && buffer.isNotEmpty) buffer.write(' ');
    pendingSpace = false;
    buffer.write(text);
  }

  for (final rune in input.runes) {
    if (_isCombiningMark(rune)) continue;

    final folded = _latinFolding[rune];
    if (folded != null) {
      emit(folded);
      continue;
    }

    final char = String.fromCharCode(rune);
    if (_isWordCharacter(char)) {
      emit(char.toLowerCase());
    } else {
      pendingSpace = true;
    }
  }

  return buffer.toString();
}

final RegExp _bracketedSegment = RegExp(r'[\(\[\{][^\(\)\[\]\{\}]*[\)\]\}]');

/// A looser title form with bracketed segments removed.
///
/// "Clair de Lune (R. 75)" and "Clair de Lune" collapse to the same core
/// title, which is what catches a re-export under a different catalogue
/// number. This is only ever used to *suggest*, never to block.
String coreTitle(String title) {
  final withoutBrackets = title.replaceAll(_bracketedSegment, ' ');
  return normalizeForComparison(withoutBrackets);
}

/// Compares a candidate's hash and metadata against the existing library.
///
/// Two rules, deliberately asymmetric:
///
///  * A matching content hash is a hard block. Identical bytes cannot be a
///    different piece, so the user is offered the existing score instead.
///  * A matching title and composer is only a suggestion. Re-scans and
///    re-exports differ byte-for-byte, so blocking on metadata would reject
///    legitimate imports of the same piece from two editions.
DuplicateAssessment assessDuplicates({
  required String contentHash,
  required String title,
  required String composer,
  required List<Score> existingScores,
}) {
  final exact = existingScores
      .where((score) => score.contentHash != null && score.contentHash == contentHash)
      .toList(growable: false);

  if (exact.isNotEmpty) {
    return DuplicateAssessment(
      verdict: DuplicateVerdict.exactContent,
      contentHash: contentHash,
      exactMatches: exact,
    );
  }

  final normalizedTitle = normalizeForComparison(title);
  final normalizedCore = coreTitle(title);
  final normalizedComposer = normalizeForComparison(composer);

  final matches = existingScores.where((score) {
    if (normalizeForComparison(score.title) == normalizedTitle &&
        normalizeForComparison(score.composer) == normalizedComposer) {
      return true;
    }
    if (normalizedCore.isEmpty) return false;
    return coreTitle(score.title) == normalizedCore &&
        normalizeForComparison(score.composer) == normalizedComposer;
  }).toList(growable: false);

  return DuplicateAssessment(
    verdict: matches.isEmpty
        ? DuplicateVerdict.none
        : DuplicateVerdict.metadata,
    contentHash: contentHash,
    metadataMatches: matches,
  );
}

bool _isWordCharacter(String char) => _wordCharacter.hasMatch(char);

/// Letters and numbers in any script.
///
/// A naive ASCII-only check would reduce a Cyrillic or CJK title to an empty
/// string, which would make every such score look like a metadata duplicate of
/// every other one.
final RegExp _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Latin letters folded to a lowercase base form, keyed by code point.
///
/// Dart has no NFD normalizer in the core libraries, so a title typed on a
/// phone keyboard usually arrives already composed (a single U+00E9 for "é")
/// and merely dropping combining marks would not catch it. This covers the
/// Latin-1 Supplement block and the Latin Extended-A block, which is where
/// re-export spelling drift in repertoire titles comes from ("Dvorak" vs
/// "Dvořák", "Sibelius" vs "Sibelius").
///
/// Every value is lowercase. Folding happens before any case handling, so
/// there is no need to distinguish upper from lower code points here.
final Map<int, String> _latinFolding = _buildLatinFolding();

Map<int, String> _buildLatinFolding() {
  // Indexed by (rune - 0xC0) for U+00C0..U+00DF, and reused for the matching
  // lowercase block U+00E0..U+00FF, since the two halves pair up exactly.
  // A null entry is a pure symbol (the multiplication and division signs) and
  // is deliberately left out of the table so it acts as a word separator.
  const latin1Bases = <String?>[
    'a', 'a', 'a', 'a', 'a', 'a', // À Á Â Ã Ä Å
    'ae', // Æ
    'c', // Ç
    'e', 'e', 'e', 'e', // È É Ê Ë
    'i', 'i', 'i', 'i', // Ì Í Î Ï
    'd', // Ð
    'n', // Ñ
    'o', 'o', 'o', 'o', 'o', // Ò Ó Ô Õ Ö
    null, // ×
    'o', // Ø
    'u', 'u', 'u', 'u', // Ù Ú Û Ü
    'y', // Ý
    'th', // Þ
    'ss', // ß
  ];

  const latinExtended = <int, String>{
    0x0100: 'a', 0x0101: 'a', 0x0102: 'a', 0x0103: 'a', // Ā ā Ă ă
    0x0104: 'a', 0x0105: 'a', // Ą ą
    0x0106: 'c', 0x0107: 'c', 0x0108: 'c', 0x0109: 'c', // Ć ć Ĉ ĉ
    0x010A: 'c', 0x010B: 'c', 0x010C: 'c', 0x010D: 'c', // Ċ ċ Č č
    0x010E: 'd', 0x010F: 'd', 0x0110: 'd', 0x0111: 'd', // Ď ď Đ đ
    0x0112: 'e', 0x0113: 'e', 0x0114: 'e', 0x0115: 'e', // Ē ē Ĕ ĕ
    0x0116: 'e', 0x0117: 'e', 0x0118: 'e', 0x0119: 'e', // Ė ė Ę ę
    0x011A: 'e', 0x011B: 'e', // Ě ě
    0x011C: 'g', 0x011D: 'g', 0x011E: 'g', 0x011F: 'g', // Ĝ ĝ Ğ ğ
    0x0120: 'g', 0x0121: 'g', 0x0122: 'g', 0x0123: 'g', // Ġ ġ Ģ ģ
    0x0124: 'h', 0x0125: 'h', 0x0126: 'h', 0x0127: 'h', // Ĥ ĥ Ħ ħ
    0x0128: 'i', 0x0129: 'i', 0x012A: 'i', 0x012B: 'i', // Ĩ ĩ Ī ī
    0x012C: 'i', 0x012D: 'i', 0x012E: 'i', 0x012F: 'i', // Ĭ ĭ Į į
    0x0130: 'i', 0x0131: 'i', // İ ı
    0x0132: 'ij', 0x0133: 'ij', // Ĳ ĳ
    0x0134: 'j', 0x0135: 'j', // Ĵ ĵ
    0x0136: 'k', 0x0137: 'k', 0x0138: 'k', // Ķ ķ ĸ
    0x0139: 'l', 0x013A: 'l', 0x013B: 'l', 0x013C: 'l', // Ĺ ĺ Ļ ļ
    0x013D: 'l', 0x013E: 'l', 0x013F: 'l', 0x0140: 'l', // Ľ ľ Ŀ ŀ
    0x0141: 'l', 0x0142: 'l', // Ł ł
    0x0143: 'n', 0x0144: 'n', 0x0145: 'n', 0x0146: 'n', // Ń ń Ņ ņ
    0x0147: 'n', 0x0148: 'n', 0x0149: 'n', // Ň ň ŉ
    0x014A: 'n', 0x014B: 'n', // Ŋ ŋ
    0x014C: 'o', 0x014D: 'o', 0x014E: 'o', 0x014F: 'o', // Ō ō Ŏ ŏ
    0x0150: 'o', 0x0151: 'o', // Ő ő
    0x0152: 'oe', 0x0153: 'oe', // Œ œ
    0x0154: 'r', 0x0155: 'r', 0x0156: 'r', 0x0157: 'r', // Ŕ ŕ Ŗ ŗ
    0x0158: 'r', 0x0159: 'r', // Ř ř
    0x015A: 's', 0x015B: 's', 0x015C: 's', 0x015D: 's', // Ś ś Ŝ ŝ
    0x015E: 's', 0x015F: 's', 0x0160: 's', 0x0161: 's', // Ş ş Š š
    0x0162: 't', 0x0163: 't', 0x0164: 't', 0x0165: 't', // Ţ ţ Ť ť
    0x0166: 't', 0x0167: 't', // Ŧ ŧ
    0x0168: 'u', 0x0169: 'u', 0x016A: 'u', 0x016B: 'u', // Ũ ũ Ū ū
    0x016C: 'u', 0x016D: 'u', 0x016E: 'u', 0x016F: 'u', // Ŭ ŭ Ů ů
    0x0170: 'u', 0x0171: 'u', 0x0172: 'u', 0x0173: 'u', // Ű ű Ų ų
    0x0174: 'w', 0x0175: 'w', // Ŵ ŵ
    0x0176: 'y', 0x0177: 'y', 0x0178: 'y', // Ŷ ŷ Ÿ
    0x0179: 'z', 0x017A: 'z', 0x017B: 'z', // Ź Ź Ż ż
    0x017C: 'z', 0x017D: 'z', 0x017E: 'z', // Ž ž Ž
    0x017F: 's', // ſ
  };

  final table = <int, String>{};
  for (var i = 0; i < latin1Bases.length; i++) {
    final base = latin1Bases[i];
    if (base == null) continue;
    table[0xC0 + i] = base;
    table[0xE0 + i] = base;
  }
  table.addAll(latinExtended);
  return table;
}

bool _isCombiningMark(int rune) => rune >= 0x0300 && rune <= 0x036F;
