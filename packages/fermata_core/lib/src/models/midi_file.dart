/// A named point in a MIDI timeline, e.g. "slow spot" or "rehearsal mark B".
class CuePoint {
  const CuePoint({required this.tick, required this.label});

  /// Absolute tick from the start of the file.
  final int tick;
  final String label;

  Map<String, dynamic> toJson() => {'tick': tick, 'label': label};

  factory CuePoint.fromJson(Map<String, dynamic> json) => CuePoint(
    tick: (json['tick'] as num).toInt(),
    label: json['label'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is CuePoint && other.tick == tick && other.label == label;

  @override
  int get hashCode => Object.hash(tick, label);
}

/// An A-B practice loop, expressed in ticks so it survives tempo changes.
class LoopRange {
  const LoopRange({required this.startTick, required this.endTick});

  final int startTick;
  final int endTick;

  int get lengthTicks => endTick - startTick;

  bool get isValid => startTick >= 0 && endTick > startTick;

  bool contains(int tick) => tick >= startTick && tick < endTick;

  Map<String, dynamic> toJson() => {
    'startTick': startTick,
    'endTick': endTick,
  };

  factory LoopRange.fromJson(Map<String, dynamic> json) => LoopRange(
    startTick: (json['startTick'] as num).toInt(),
    endTick: (json['endTick'] as num).toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is LoopRange &&
      other.startTick == startTick &&
      other.endTick == endTick;

  @override
  int get hashCode => Object.hash(startTick, endTick);
}

/// The playback edits for one MIDI file.
///
/// These are the values the companion web UI writes and the app reads. Keeping
/// them as a single value object (rather than loose columns) is what lets both
/// surfaces agree on what an "edit" is.
class PlaybackEdits {
  const PlaybackEdits({
    this.tempoScale = 1.0,
    this.loop,
    this.mutedChannels = const {},
    this.countInBars,
    this.cuePoints = const [],
  });

  /// Playback rate multiplier. 1.0 is the file's written tempo.
  ///
  /// Tempo changes are applied at synthesis time rather than by resampling, so
  /// pitch is unaffected.
  final double tempoScale;

  final LoopRange? loop;

  /// Zero-based MIDI channel numbers to silence.
  final Set<int> mutedChannels;

  /// Length of the metronome count-in in bars; null or 0 disables it.
  final int? countInBars;

  final List<CuePoint> cuePoints;

  bool get hasLoop => loop?.isValid ?? false;

  PlaybackEdits copyWith({
    double? tempoScale,
    LoopRange? loop,
    bool clearLoop = false,
    Set<int>? mutedChannels,
    int? countInBars,
    bool clearCountIn = false,
    List<CuePoint>? cuePoints,
  }) => PlaybackEdits(
    tempoScale: tempoScale ?? this.tempoScale,
    loop: clearLoop ? null : (loop ?? this.loop),
    mutedChannels: mutedChannels ?? this.mutedChannels,
    countInBars: clearCountIn ? null : (countInBars ?? this.countInBars),
    cuePoints: cuePoints ?? this.cuePoints,
  );

  Map<String, dynamic> toJson() => {
    'tempoScale': tempoScale,
    'loop': loop?.toJson(),
    'mutedChannels': mutedChannels.toList()..sort(),
    'countInBars': countInBars,
    'cuePoints': cuePoints.map((c) => c.toJson()).toList(growable: false),
  };

  factory PlaybackEdits.fromJson(Map<String, dynamic> json) => PlaybackEdits(
    tempoScale: (json['tempoScale'] as num?)?.toDouble() ?? 1.0,
    loop: json['loop'] == null
        ? null
        : LoopRange.fromJson(json['loop'] as Map<String, dynamic>),
    mutedChannels:
        ((json['mutedChannels'] as List<dynamic>?) ?? const [])
            .map((c) => (c as num).toInt())
            .toSet(),
    countInBars: (json['countInBars'] as num?)?.toInt(),
    cuePoints:
        ((json['cuePoints'] as List<dynamic>?) ?? const [])
            .map((c) => CuePoint.fromJson(c as Map<String, dynamic>))
            .toList(growable: false),
  );

  @override
  bool operator ==(Object other) =>
      other is PlaybackEdits &&
      other.tempoScale == tempoScale &&
      other.loop == loop &&
      other.countInBars == countInBars &&
      other.mutedChannels.length == mutedChannels.length &&
      other.mutedChannels.containsAll(mutedChannels) &&
      other.cuePoints.length == cuePoints.length;

  @override
  int get hashCode => Object.hash(
    tempoScale,
    loop,
    Object.hashAllUnordered(mutedChannels),
    countInBars,
    Object.hashAll(cuePoints),
  );
}

/// A MIDI file in the library, either standalone or linked to a score.
class MidiFile {
  const MidiFile({
    required this.id,
    required this.title,
    required this.filePath,
    required this.addedAt,
    this.linkedScoreId,
    this.edits = const PlaybackEdits(),
  });

  final String id;
  final String title;

  /// Path relative to the library's midi directory.
  final String filePath;

  final DateTime addedAt;

  /// The score this acts as a reference for, or null if standalone.
  final String? linkedScoreId;

  final PlaybackEdits edits;

  MidiFile copyWith({String? title, String? linkedScoreId, PlaybackEdits? edits}) =>
      MidiFile(
        id: id,
        title: title ?? this.title,
        filePath: filePath,
        addedAt: addedAt,
        linkedScoreId: linkedScoreId ?? this.linkedScoreId,
        edits: edits ?? this.edits,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'addedAt': addedAt.toIso8601String(),
    'linkedScoreId': linkedScoreId,
    'edits': edits.toJson(),
  };

  factory MidiFile.fromJson(Map<String, dynamic> json) => MidiFile(
    id: json['id'] as String,
    title: json['title'] as String,
    filePath: json['filePath'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
    linkedScoreId: json['linkedScoreId'] as String?,
    edits: json['edits'] == null
        ? const PlaybackEdits()
        : PlaybackEdits.fromJson(json['edits'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      other is MidiFile &&
      other.id == id &&
      other.title == title &&
      other.filePath == filePath &&
      other.addedAt == addedAt &&
      other.linkedScoreId == linkedScoreId &&
      other.edits == edits;

  @override
  int get hashCode =>
      Object.hash(id, title, filePath, addedAt, linkedScoreId, edits);
}
