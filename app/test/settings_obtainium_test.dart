import 'package:fermata/src/features/settings/settings_screen.dart';
import 'package:fermata/src/providers/platform_bridge.dart';
import 'package:fermata/src/update/obtainium_app.dart';
import 'package:fermata/src/update/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_platform_bridge.dart';
import 'helpers/fake_release_feed.dart';

/// Overrides the two providers the settings screen reaches for outside the
/// update check: the launcher, and the Obtainium config asset.
///
/// The config is overridden rather than loaded from the bundle so the test does
/// not depend on the asset actually being registered in `pubspec.yaml` — that
/// wiring is `obtainium_app_test.dart`'s job, via [kObtainiumConfigAsset].
ProviderContainer _container({
  required String installedVersion,
  required ReleaseFeed feed,
  FakeUriLauncher? launcher,
}) {
  final container = ProviderContainer(
    overrides: [
      installedPackageSourceProvider.overrideWithValue(
        FakeInstalledPackageSource(versionName: installedVersion),
      ),
      releaseFeedProvider.overrideWithValue(feed),
      uriLauncherProvider.overrideWithValue(launcher ?? FakeUriLauncher()),
      obtainiumAppProvider.overrideWith(
        (ref) async => const ObtainiumApp(
          id: 'com.hoid.fermata',
          url: 'https://github.com/CephandriusMaxtori/Fermata',
          author: 'CephandriusMaxtori',
          name: 'Fermata',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adds Fermata to Obtainium when no update is pending', (tester) async {
    final launcher = FakeUriLauncher();
    final container = _container(
      installedVersion: '1.0.0',
      // No releases: the common case for a user hearing about Fermata through
      // Obtainium with nothing installed to update from.
      feed: const FakeReleaseFeed(null),
      launcher: launcher,
    );
    await _pump(tester, container);

    await tester.tap(find.text('Install and update with Obtainium'));
    await tester.pumpAndSettle();

    expect(launcher.opened, hasLength(1));
    expect(launcher.opened.single.scheme, 'obtainium');
    expect(launcher.opened.single.host, 'app');
  });

  testWidgets('refreshes instead of adding when an update is waiting', (tester) async {
    final launcher = FakeUriLauncher();
    final container = _container(
      installedVersion: '1.0.0',
      feed: FakeReleaseFeed(releaseJson(tagName: 'v1.1.0')),
      launcher: launcher,
    );
    await _pump(tester, container);

    await tester.tap(find.text('Install and update with Obtainium'));
    await tester.pumpAndSettle();

    // The `app` deep link opens Obtainium's Add screen, which is the wrong
    // screen for someone who already tracks Fermata and wants the new build.
    expect(launcher.opened.single.host, 'refresh');
    expect(
      launcher.opened.single.queryParameters['id'],
      'com.hoid.fermata',
    );
  });

  testWidgets('explains itself when Obtainium is not installed', (tester) async {
    final launcher = FakeUriLauncher(handles: false);
    final container = _container(
      installedVersion: '1.0.0',
      feed: const FakeReleaseFeed(null),
      launcher: launcher,
    );
    await _pump(tester, container);

    await tester.tap(find.text('Install and update with Obtainium'));
    await tester.pumpAndSettle();

    // Nothing may be swallowed here: a hand-off that fails silently reads as a
    // broken app, and the fix is to install Obtainium.
    expect(find.text('Obtainium is not installed'), findsOneWidget);
    expect(find.textContaining('obtainium://app/'), findsOneWidget);
  });

  testWidgets('shows the installed version and the update', (tester) async {
    final container = _container(
      installedVersion: '1.0.0',
      feed: FakeReleaseFeed(releaseJson(tagName: 'v1.1.0')),
    );
    await _pump(tester, container);

    expect(find.textContaining('Installed version: 1.0.0'), findsOneWidget);
    expect(find.text('Fermata 1.1.0 is available.'), findsOneWidget);
  });

  testWidgets('says so plainly when there is no update', (tester) async {
    final container = _container(
      installedVersion: '1.0.0',
      feed: FakeReleaseFeed(releaseJson(tagName: 'v1.0.0')),
    );
    await _pump(tester, container);

    expect(find.text('Up to date.'), findsOneWidget);
  });

  testWidgets('reports a failed check instead of claiming up to date',
      (tester) async {
    final container = _container(
      installedVersion: '1.0.0',
      feed: const FailingReleaseFeed('rate limited'),
    );
    await _pump(tester, container);

    // The distinction that matters: "up to date" is a promise, and a check that
    // never reached GitHub cannot make one.
    expect(find.textContaining('Could not check'), findsOneWidget);
    expect(find.text('Up to date.'), findsNothing);
  });

  testWidgets('lists the settings that are still pending', (tester) async {
    final container = _container(
      installedVersion: '1.0.0',
      feed: const FakeReleaseFeed(null),
    );
    await _pump(tester, container);

    expect(find.text('Page-turn pedal'), findsOneWidget);
    expect(find.text('Backup and restore'), findsOneWidget);
  });
}