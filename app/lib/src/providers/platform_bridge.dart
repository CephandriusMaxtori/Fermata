import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hands a URI to whichever app on the device claims it.
///
/// An interface rather than a direct `MethodChannel` call so the settings
/// screen's Obtainium hand-off can be tested without an Android runtime, and so
/// "nothing can handle this" is a value the caller has to think about instead
/// of a `PlatformException` escaping from the middle of a button handler.
abstract interface class UriLauncher {
  /// Resolves to `false` when no installed app can handle [uri].
  Future<bool> open(Uri uri);
}

/// Fermata as the OS installed it.
///
/// [versionName] is the part before the `+` in `pubspec.yaml`'s `version:`, and
/// it is what a release tag has to match for Obtainium to notice an update —
/// see `docs/obtainium.md`. [versionCode] is the part after it, and Android
/// requires it to increase for an install to count as an upgrade.
class InstalledPackage {
  const InstalledPackage({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;

  @override
  String toString() => '$versionName ($versionCode)';
}

/// Reads the installed package's own version.
abstract interface class InstalledPackageSource {
  Future<InstalledPackage> read();
}

final uriLauncherProvider = Provider<UriLauncher>(
  (ref) => const MethodChannelUriLauncher(),
);

final installedPackageSourceProvider = Provider<InstalledPackageSource>(
  (ref) => const MethodChannelInstalledPackageSource(),
);

/// Not auto-disposed: the settings screen shows the version whether or not an
/// update has ever been checked, and re-reading it from `PackageManager` on
/// every rebuild of that screen would be pointless work.
final installedPackageProvider = FutureProvider<InstalledPackage>(
  (ref) => ref.watch(installedPackageSourceProvider).read(),
);

/// The channel name shared with `MainActivity.kt`.
///
/// One channel for both calls, because a second one would mean a second
/// `MethodCallHandler` registration in the same activity and no gain.
const kPlatformChannel = MethodChannel('fermata/platform');

class MethodChannelUriLauncher implements UriLauncher {
  const MethodChannelUriLauncher();

  @override
  Future<bool> open(Uri uri) async {
    final handled = await kPlatformChannel.invokeMethod<bool>(
      'openUri',
      {'uri': uri.toString()},
    );
    // A null reply means the platform side is older than this Dart code, which
    // is not worth an exception: the user simply gets the "could not open"
    // fallback.
    return handled ?? false;
  }
}

class MethodChannelInstalledPackageSource implements InstalledPackageSource {
  const MethodChannelInstalledPackageSource();

  @override
  Future<InstalledPackage> read() async {
    final reply = await kPlatformChannel.invokeMapMethod<String, Object?>(
      'installedPackage',
    );
    if (reply == null) {
      throw PlatformException(
        code: 'empty',
        message: 'installedPackage returned nothing',
      );
    }
    final name = reply['versionName'];
    final code = reply['versionCode'];
    if (name is! String || code is! int) {
      throw PlatformException(
        code: 'shape',
        message: 'installedPackage returned $reply',
      );
    }
    return InstalledPackage(versionName: name, versionCode: code);
  }
}