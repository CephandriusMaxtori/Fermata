import 'package:fermata/src/update/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion.parse', () {
    test('drops the leading v a release tag carries', () {
      expect(AppVersion.parse('v1.2.3').toString(), '1.2.3');
    });

    test('accepts a bare pubspec version', () {
      expect(AppVersion.parse('1.2.3').parts, [1, 2, 3]);
    });

    test('keeps only the numeric prefix of a pre-release', () {
      // Deliberately lossy. Obtainium's own version detection compares only
      // recognised standard formats and gives up on a mismatch, so `1.2.3-beta`
      // has to read as 1.2.3 for the two to agree.
      expect(AppVersion.parse('v1.2.3-beta').parts, [1, 2, 3]);
    });

    test('throws rather than inventing a version', () {
      // A release tagged `nightly` must surface as a visible failure, not as
      // "some version I could not read" that silently compares as 0.
      expect(() => AppVersion.parse('nightly'), throwsFormatException);
      expect(() => AppVersion.parse(''), throwsFormatException);
    });
  });

  group('AppVersion comparison', () {
    test('compares numerically, not lexically', () {
      // The regression this whole class exists for: as strings '1.10.0' sorts
      // before '1.9.0', so 1.10 would read as older and the app would claim to
      // be current while Obtainium installed the update underneath it.
      expect(
        AppVersion.parse('v1.10.0').isNewerThan(AppVersion.parse('v1.9.0')),
        isTrue,
      );
      expect(
        AppVersion.parse('v1.9.0').isNewerThan(AppVersion.parse('v1.10.0')),
        isFalse,
      );
    });

    test('pads so 1.2 and 1.2.0 are the same version', () {
      expect(AppVersion.parse('1.2'), AppVersion.parse('1.2.0'));
      expect(
        AppVersion.parse('v1.2').isNewerThan(AppVersion.parse('v1.2.0')),
        isFalse,
      );
    });

    test('the same version is not newer than itself', () {
      expect(
        AppVersion.parse('v1.0.0').isNewerThan(AppVersion.parse('1.0.0')),
        isFalse,
      );
    });

    test('a downgrade reads as older', () {
      expect(
        AppVersion.parse('v1.0.0').isNewerThan(AppVersion.parse('v2.0.0')),
        isFalse,
      );
    });
  });
}