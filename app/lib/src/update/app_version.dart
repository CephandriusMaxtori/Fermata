/// A dotted numeric version, compared numerically rather than lexically.
///
/// Lexical comparison is the trap here: `"1.10.0" < "1.9.0"` as strings, so a
/// release of 1.10 would be reported as older than 1.9 and the app would tell
/// the user it is up to date while Obtainium installs the update underneath it.
///
/// This is not a full SemVer implementation and does not try to be. A leading
/// `v` is dropped because tags are written `v1.2.3`, and a trailing
/// pre-release or build suffix (`-beta`, `+12`) is ignored rather than ordered,
/// which means `1.2.3-beta` reads as equal to `1.2.3`. That is deliberate:
/// Obtainium's version detection has exactly the same blind spot, so matching
/// it keeps the app's answer and the installer's answer in agreement.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.parts, this.raw);

  /// Parses [raw], throwing [FormatException] if it holds no leading number.
  ///
  /// Throwing rather than returning null because every caller here has a tag or
  /// an installed version that is *supposed* to be well-formed, and a release
  /// tagged `nightly` should surface as a visible failure rather than as
  /// "some version I could not read".
  factory AppVersion.parse(String raw) {
    final trimmed = raw.trim();
    final withoutV = trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
    final numbers = withoutV.split('.');
    final parts = <int>[];
    for (final number in numbers) {
      final match = RegExp(r'^\d+').firstMatch(number);
      if (match == null) {
        // `1.2.3-beta` stops here; `beta` alone would have thrown at 0.
        break;
      }
      parts.add(int.parse(match.group(0)!));
    }
    if (parts.isEmpty) {
      throw FormatException('"$raw" contains no version number');
    }
    return AppVersion._(parts, trimmed);
  }

  /// Compares numerically, padding the shorter side with zeroes.
  ///
  /// Padding is what makes `1.2` and `1.2.0` the same version, which is how
  /// pubspec versions and release tags actually differ in practice.
  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a < b ? -1 : 1;
    }
    return 0;
  }

  final List<int> parts;

  /// The string this was parsed from, tag prefix and all.
  final String raw;

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  /// Strips the leading `v` for display, so a tag and a version name can be
  /// shown with the same punctuation.
  String get normalized => raw.startsWith('v') ? raw.substring(1) : raw;

  @override
  String toString() => normalized;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(parts);
}