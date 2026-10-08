import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fermata's Obtainium app configuration.
///
/// The same JSON object is the unit Obtainium imports through
/// `obtainium://app/<url-encoded json>`, the unit its crowdsourced config
/// directory stores, and the unit its import/export page round-trips. There is
/// therefore exactly one of it, [`kObtainiumConfigAsset`], and both this class
/// and `docs/obtainium.md` are downstream of that file. A second copy — a
/// constant in Dart, say — would drift, and the drift would be invisible until
/// a user installed the wrong thing.
class ObtainiumApp {
  const ObtainiumApp({
    required this.id,
    required this.url,
    required this.author,
    required this.name,
    this.appSource,
    this.additionalSettings,
  });

  /// The package name Obtainium files the app under.
  ///
  /// Not free-form: Obtainium uses it to work out whether the app it is
  /// tracking is the same app Android has installed, so a typo here means the
  /// update never registers.
  final String id;

  /// The source Obtainium polls for releases. GitHub, so the app source
  /// resolves without an access token for anyone who has not configured one.
  final String url;

  final String author;
  final String name;

  /// Explicit app source (e.g. "GitHub").
  final String? appSource;

  /// Additional settings for Obtainium (e.g. apkFilterRegEx).
  final Map<String, Object?>? additionalSettings;

  factory ObtainiumApp.fromJson(Map<String, Object?> json) {
    return ObtainiumApp(
      id: _requiredString(json, 'id'),
      url: _requiredString(json, 'url'),
      author: _requiredString(json, 'author'),
      name: _requiredString(json, 'name'),
      appSource: json['appSource'] as String?,
      additionalSettings: (json['additionalSettings'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// The exact bytes Obtainium imports.
  ///
  /// Key order is fixed rather than taken from the decoded map so that the
  /// asset round-trips byte-identically. Obtainium shows the raw JSON on its
  /// confirmation dialog, and a payload that reorders itself between the asset
  /// file and the hand-off would make that dialog unreviewable.
  String toJson() {
    final map = <String, Object?>{
      'id': id,
      'url': url,
      'author': author,
      'name': name,
    };
    if (appSource != null) {
      map['appSource'] = appSource;
    }
    if (additionalSettings != null && additionalSettings!.isNotEmpty) {
      map['additionalSettings'] = additionalSettings;
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// `obtainium://app/<config>` — opens Obtainium's Add App screen.
  ///
  /// If Obtainium already tracks this exact URL it opens that app's page instead,
  /// which is what makes this safe to wire to a button that is always visible:
  /// the first tap adds Fermata, every later tap is a shortcut to it. No
  /// "already added" state to keep track of on our side.
  Uri get addLink => Uri.parse('obtainium://app/${Uri.encodeComponent(toJson())}');

  /// The add link, for showing or copying when Obtainium is not installed.
  String get addLinkText => addLink.toString();

  /// `obtainium://refresh?id=<package>` — re-checks just Fermata.
  ///
  /// Only useful once [addLink] has been used at least once; Obtainium has no
  /// app to refresh otherwise.
  Uri get refreshLink => Uri.parse(
    'obtainium://refresh?id=${Uri.encodeQueryComponent(id)}',
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('obtainium config field "$key" must be a non-empty '
        'string, got ${value.runtimeType}');
  }
  return value;
}

/// Where the config lives. Matched by `pubspec.yaml`'s asset entry.
const kObtainiumConfigAsset = 'assets/distribution/obtainium_config.json';

final obtainiumAppProvider = FutureProvider<ObtainiumApp>((ref) async {
  return ObtainiumApp.fromJson(
    await _decodeObtainiumConfig(await rootBundle.loadString(kObtainiumConfigAsset)),
  );
});

/// Shared by the provider and by tests, so both parse the same way.
Future<Map<String, Object?>> _decodeObtainiumConfig(String source) async {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'obtainium config must be a JSON object',
    );
  }
  return decoded;
}

/// Exposed for tests; the provider above is the production path.
Future<ObtainiumApp> loadObtainiumApp([String asset = kObtainiumConfigAsset]) async {
  final source = await rootBundle.loadString(asset);
  return ObtainiumApp.fromJson(await _decodeObtainiumConfig(source));
}