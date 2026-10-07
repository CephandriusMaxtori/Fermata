import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/platform_bridge.dart';
import 'app_version.dart';

/// One release as this app cares about it: a tag and some prose.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
  });

  /// `v1.2.3` — the tag. Obtainium derives the version from this, so it has to
  /// track `version:` in `pubspec.yaml` exactly.
  final String tagName;

  /// The release title, which may be empty where the tag is descriptive enough.
  final String name;

  /// Markdown release notes, or empty for a tag with no body.
  final String body;

  final Uri htmlUrl;

  final DateTime publishedAt;

  /// [tagName] without a leading `v`, compared numerically.
  AppVersion get version => AppVersion.parse(tagName);

  /// What the UI shows as the release's version: the title if the publisher wrote
  /// one, otherwise the tag.
  String get displayName => name.trim().isEmpty ? tagName : name.trim();

  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    final tagName = json['tag_name'];
    if (tagName is! String || tagName.isEmpty) {
      throw const FormatException('release has no tag_name');
    }
    return ReleaseInfo(
      tagName: tagName,
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: Uri.parse(
        (json['html_url'] as String?) ??
            'https://github.com/CephandriusMaxtori/Fermata/releases/tag/$tagName',
      ),
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// The outcome of a check, in the three states the UI distinguishes.
///
/// Sealed rather than nullable fields, because "there is no release at all" and
/// "the newest release is the one you are running" are different answers and
/// collapsing them produces the classic bug where a repository with zero
/// releases reports an update to version 0.0.0.
sealed class UpdateCheck {
  const UpdateCheck();
}

/// Check did not complete — no network, rate limited, malformed JSON.
///
/// Kept distinct from [UpToDate] so the screen can offer a retry instead of
/// claiming everything is fine.
class UpdateCheckFailed extends UpdateCheck {
  const UpdateCheckFailed(this.message);

  final String message;
}

class UpToDate extends UpdateCheck {
  const UpToDate(this.installed);

  final InstalledPackage installed;
}

class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable({required this.installed, required this.latest});

  final InstalledPackage installed;
  final ReleaseInfo latest;
}

/// Reads the newest published release.
///
/// An interface because the only implementation is [GitHubReleaseFeed], which
/// performs real I/O that a widget test cannot do, and because the alternative —
/// a test that asserts against the live GitHub API — fails whenever the
/// network does.
abstract interface class ReleaseFeed {
  /// The newest release that is neither a draft nor a prerelease.
  ///
  /// Returns null for a repository with no such release, which is a real state
  /// here: Fermata had no GitHub releases until it started shipping them.
  Future<ReleaseInfo?> latestRelease();
}

const kRepositoryOwner = 'CephandriusMaxtori';
const kRepositoryName = 'Fermata';

/// The `api.github.com` source Obtainium reads too.
///
/// Same endpoint deliberately: the in-app check and Obtainium's background
/// update then agree about which release is newest. A separate feed would make
/// the app claim there is an update Obtainium has already installed.
class GitHubReleaseFeed implements ReleaseFeed {
  const GitHubReleaseFeed({this.client, this.timeout = kReleaseFetchTimeout});

  /// Injectable so tests can serve a canned response. `null` builds a client
  /// per call and closes it, because a [HttpClient] left open pins a socket and
  /// an [HttpClient] closed too early aborts the read.
  final HttpClient? client;

  final Duration timeout;

  static const kReleaseFetchTimeout = Duration(seconds: 10);

  @override
  Future<ReleaseInfo?> latestRelease() async {
    final uri = Uri.https('api.github.com', '/repos/$kRepositoryOwner/'
        '$kRepositoryName/releases/latest');

    final owned = client == null;
    final http = client ?? HttpClient();
    try {
      final request = await http.getUrl(uri).timeout(timeout);
      // GitHub requires a User-Agent and rejects anonymous requests without
      // one; the API version header is what keeps the JSON shape stable.
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Fermata/$kRepositoryName')
        ..set('X-GitHub-Api-Version', '2022-11-28');

      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.notFound) {
        // 404 is "no releases yet", not a failure. Treating it as an error is
        // how a fresh install shows a scary message instead of a quiet one.
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        // 403 here is nearly always the 60/hour anonymous rate limit, which is
        // worth naming because retrying in a second will not help.
        throw HttpException(
          'GitHub returned ${response.statusCode}'
          '${response.statusCode == HttpStatus.forbidden ? ' (rate limited?)' : ''}',
          uri: uri,
        );
      }

      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('release response was not a JSON object');
      }
      return ReleaseInfo.fromJson(decoded);
    } finally {
      if (owned) http.close(force: true);
    }
  }
}

final releaseFeedProvider = Provider<ReleaseFeed>((ref) {
  return const GitHubReleaseFeed();
});

final updateCheckProvider = FutureProvider.autoDispose<UpdateCheck>((ref) async {
  final installed = await ref.watch(installedPackageProvider.future);
  final feed = ref.watch(releaseFeedProvider);
  try {
    final latest = await feed.latestRelease();
    if (latest == null) return UpToDate(installed);
    // Obtainium compares version *names*, so this does too. Comparing build
    // numbers here would let the app disagree with the thing that actually
    // installs the update.
    return latest.version.isNewerThan(AppVersion.parse(installed.versionName))
        ? UpdateAvailable(installed: installed, latest: latest)
        : UpToDate(installed);
  } on Object catch (error) {
    return UpdateCheckFailed('$error');
  }
});