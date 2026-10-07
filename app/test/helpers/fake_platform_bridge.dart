import 'package:fermata/src/providers/platform_bridge.dart';

/// Records every URI it is asked to open and answers with [handles].
///
/// `handles: false` stands in for a device with no Obtainium, which is the
/// branch that has to produce a dialog rather than a dead button.
class FakeUriLauncher implements UriLauncher {
  FakeUriLauncher({this.handles = true});

  final List<Uri> opened = [];
  final bool handles;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return handles;
  }
}

class FakeInstalledPackageSource implements InstalledPackageSource {
  const FakeInstalledPackageSource({
    this.versionName = '1.0.0',
    this.versionCode = 1,
  });

  final String versionName;
  final int versionCode;

  @override
  Future<InstalledPackage> read() async => InstalledPackage(
    versionName: versionName,
    versionCode: versionCode,
  );
}