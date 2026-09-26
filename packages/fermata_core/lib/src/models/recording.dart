/// Where a practice recording came from.
enum RecordingSource {
  audio,
  midiIn;

  static RecordingSource fromName(String name) => RecordingSource.values.firstWhere(
    (source) => source.name == name,
    orElse: () => RecordingSource.audio,
  );
}

/// A take of the user playing a piece, stored per score.
class Recording {
  const Recording({
    required this.id,
    required this.scoreId,
    required this.filePath,
    required this.recordedAt,
    required this.duration,
    required this.source,
    this.label,
  });

  final String id;
  final String scoreId;

  /// Path relative to the score's recordings directory.
  final String filePath;

  final DateTime recordedAt;
  final Duration duration;
  final RecordingSource source;
  final String? label;

  Recording copyWith({String? label}) => Recording(
    id: id,
    scoreId: scoreId,
    filePath: filePath,
    recordedAt: recordedAt,
    duration: duration,
    source: source,
    label: label ?? this.label,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'scoreId': scoreId,
    'filePath': filePath,
    'recordedAt': recordedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'source': source.name,
    'label': label,
  };

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
    id: json['id'] as String,
    scoreId: json['scoreId'] as String,
    filePath: json['filePath'] as String,
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    duration: Duration(milliseconds: (json['durationMs'] as num).toInt()),
    source: RecordingSource.fromName(json['source'] as String),
    label: json['label'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Recording &&
      other.id == id &&
      other.scoreId == scoreId &&
      other.filePath == filePath &&
      other.recordedAt == recordedAt &&
      other.duration == duration &&
      other.source == source &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(id, scoreId, filePath, recordedAt, duration, source, label);
}
