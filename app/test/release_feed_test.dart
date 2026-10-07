import 'dart:convert';

import 'package:fermata/src/providers/platform_bridge.dart';
import 'package:fermata/src/update/update_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_platform_bridge.dart';
import 'helpers/fake_release_feed.dart';

/// Wires the three providers the check depends on, so each test states only the
/// two facts it cares about: what is installed, and what GitHub says.
ProviderContainer _container({
  required String installedVersion,
  required ReleaseFeed feed,
}) {
  final container = ProviderContainer(
    overrides: [
      installedPackageSourceProvider.overrideWithValue(
        FakeInstalledPackageSource(versionName: installedVersion),
      ),
      releaseFeedProvider.overrideWithValue(feed),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ReleaseInfo', () {
    test('reads the tag as a version, dropping the v', () {
      final release = ReleaseInfo.fromJson(
        jsonDecode(releaseJson(tagName: 'v1.4.0')) as Map<String, Object?>,
      );

      expect(release.version.toString(), '1.4.0');
    });

    test('prefers the release title for display and falls back to the tag', () {
      final named = ReleaseInfo.fromJson(
        jsonDecode(
          releaseJson(tagName: 'v1.4.0', name: 'Barlines'),
        ) as Map<String, Object?>,
      );
      final unnamed = ReleaseInfo.fromJson(
        jsonDecode(releaseJson(tagName: 'v1.4.0')) as Map<String, Object?>,
      );

      expect(named.displayName, 'Barlines');
      expect(unnamed.displayName, 'v1.4.0');
    });

    test('rejects a release with no tag', () {
      // Without a tag there is no version, and a release with no version cannot
      // be compared against the installed one.
      expect(
        () => ReleaseInfo.fromJson(const {'name': 'Untagged'}),
        throwsFormatException,
      );
    });

    test('tolerates a release with no notes or date', () {
      final release = ReleaseInfo.fromJson(const {'tag_name': 'v1.0.0'});

      expect(release.body, isEmpty);
      expect(release.htmlUrl.host, 'github.com');
    });
  });

  group('updateCheckProvider', () {
    test('reports an available update for a newer tag', () async {
      final container = _container(
        installedVersion: '1.0.0',
        feed: FakeReleaseFeed(releaseJson(tagName: 'v1.1.0')),
      );

      final check = await container.read(updateCheckProvider.future);

      expect(
        check,
        isA<UpdateAvailable>().having((u) => u.latest.version.toString(), 'version', '1.1.0'),
      );
    });

    test('reports up to date for the same version with and without the v', () async {
      final container = _container(
        installedVersion: '1.1.0',
        feed: FakeReleaseFeed(releaseJson(tagName: 'v1.1.0')),
      );

      expect(await container.read(updateCheckProvider.future), isA<UpToDate>());
    });

    test('does not think 1.10 is older than the installed 1.9', () async {
      // The lexical-comparison bug in its real shape: as strings '1.10.0' sorts
      // before '1.9.0'.
      final container = _container(
        installedVersion: '1.9.0',
        feed: FakeReleaseFeed(releaseJson(tagName: 'v1.10.0')),
      );

      expect(await container.read(updateCheckProvider.future), isA<UpdateAvailable>());
    });

    test('reports up to date when the release is older', () async {
      final container = _container(
        installedVersion: '2.0.0',
        feed: FakeReleaseFeed(releaseJson(tagName: 'v1.9.0')),
      );

      expect(await container.read(updateCheckProvider.future), isA<UpToDate>());
    });

    test('treats a repository with no releases as up to date, not as an error',
        () async {
      // 404 from GitHub means "no releases yet", and answering with a failure
      // would show a red message on a perfectly healthy install.
      final container = _container(
        installedVersion: '1.0.0',
        feed: const FakeReleaseFeed(null),
      );

      expect(await container.read(updateCheckProvider.future), isA<UpToDate>());
    });

    test('surfaces a network failure as its own state, not as up to date', () async {
      // The distinction that matters: "up to date" is a promise, and a check that
      // never reached GitHub cannot make one.
      final container = _container(
        installedVersion: '1.0.0',
        feed: const FailingReleaseFeed(),
      );

      final check = await container.read(updateCheckProvider.future);

      expect(check, isA<UpdateCheckFailed>().having((f) => f.message, 'message', contains('offline')));
    });

    test('includes the installed package in an available update', () async {
      final container = _container(
        installedVersion: '1.0.0',
        feed: FakeReleaseFeed(releaseJson(tagName: 'v1.1.0')),
      );

      final check = await container.read(updateCheckProvider.future);

      expect(
        (check as UpdateAvailable).installed,
        isA<InstalledPackage>().having((p) => p.versionName, 'versionName', '1.0.0'),
      );
    });
  });
}