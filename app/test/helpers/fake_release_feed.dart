import 'dart:convert';

import 'package:fermata/src/update/update_service.dart';

/// Serves canned GitHub release JSON without touching a socket.
///
/// Hand-written because the repo has no mocking library, and because the
/// alternative — a test against api.github.com — fails on a train and would
/// make CI's green depend on GitHub's uptime.
class FakeReleaseFeed implements ReleaseFeed {
  const FakeReleaseFeed(this.body);

  /// A raw response body. Null means "the repository has no releases", which is
  /// a real state, not an error.
  final String? body;

  @override
  Future<ReleaseInfo?> latestRelease() async {
    final source = body;
    if (source == null) return null;
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('expected a JSON object');
    }
    return ReleaseInfo.fromJson(decoded);
  }
}

/// A feed that always throws, for the "could not check" path.
class FailingReleaseFeed implements ReleaseFeed {
  const FailingReleaseFeed([this.error = 'offline']);

  final Object error;

  @override
  Future<ReleaseInfo?> latestRelease() async => throw error;
}

/// The shape GitHub returns for `/releases/latest`, trimmed to the fields
/// `ReleaseInfo` reads.
String releaseJson({
  required String tagName,
  String name = '',
  String body = '',
  String publishedAt = '2026-10-01T09:00:00Z',
}) => jsonEncode({
  'tag_name': tagName,
  'name': name,
  'body': body,
  'html_url': 'https://github.com/CephandriusMaxtori/Fermata/releases/tag/$tagName',
  'published_at': publishedAt,
});