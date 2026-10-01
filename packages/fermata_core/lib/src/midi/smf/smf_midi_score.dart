import '../midi_score.dart';
import 'smf_parser.dart';

/// A [MidiScore] read by Fermata's own Standard MIDI File parser.
///
/// The interpretation lives here, on top of the lossless [SmfFile] layer: note
/// pairing, tempo assembly, measure maths. Keeping it separate from the byte
/// parsing means the format's quirks stay in `SmfParser` and the musical rules
/// stay here.
class SmfMidiScore extends BaseMidiScore {
  SmfMidiScore._({
    required this.ticksPerQuarterNote,
    required List<ScoreNote> notes,
    required List<TempoChange> tempoMap,
    required List<TimeSignature> timeSignatureMap,
    required this.endTick,
    required Map<String, int> markerTicks,
    required Map<String, int> cuePointTicks,
    required this.trackNames,
    required this.format,
    required this.division,
  }) : notes = List<ScoreNote>.unmodifiable(notes),
       tempoMap = List<TempoChange>.unmodifiable(tempoMap),
       timeSignatureMap = List<TimeSignature>.unmodifiable(timeSignatureMap),
       markers = Map<String, int>.unmodifiable(markerTicks),
       cuePoints = Map<String, int>.unmodifiable(cuePointTicks);

  /// Reads [bytes] as a Standard MIDI File and interprets it.
  ///
  /// Throws [MidiFormatException] when the file cannot be read.
  factory SmfMidiScore.fromBytes(List<int> bytes) =>
      SmfMidiScore.fromFile(const SmfParser().parse(bytes));

  /// Interprets an already-parsed file.
  factory SmfMidiScore.fromFile(SmfFile file) {
    final ticksPerQuarterNote = file.division.resolveTicksPerQuarterNote();

    final notes = <ScoreNote>[];
    final tempoMap = <TempoChange>[];
    final timeSignatures = <TimeSignature>[];
    final markers = <String, int>{};
    final cuePoints = <String, int>{};
    final trackNames = <String>[];

    for (final track in file.tracks) {
      final trackName = track.name;
      if (trackName != null && trackName.isNotEmpty) {
        trackNames.add(trackName);
      }

      var tick = 0;

      // Sounding notes, keyed by channel and pitch. A piece may hold the same
      // pitch on two channels at once, so both parts matter.
      final sounding = <({int channel, int note}), Sounding>{};

      for (final event in track.events) {
        tick = event.tick;

        switch (event) {
          case SmfNoteOn(isNoteOff: true):
            _close(notes, sounding, _key(event), tick);
          case SmfNoteOn():
            // A repeated note-on for a sounding pitch restarts it. Treating the
            // earlier one as closed here keeps a truncated file from leaving
            // notes running to the end of the track.
            _close(notes, sounding, _key(event), tick);
            sounding[_key(event)] = Sounding(startTick: tick, velocity: event.velocity);
          case SmfNoteOff():
            _close(notes, sounding, _keyOff(event), tick);
          case SmfSetTempo():
            tempoMap.add(
              TempoChange(
                tick: tick,
                microsecondsPerBeat: event.microsecondsPerBeat,
              ),
            );
          case SmfTimeSignature():
            timeSignatures.add(
              TimeSignature(
                tick: tick,
                numerator: event.numerator,
                // Converted here, from the exponent the file stores.
                denominator: event.denominator,
              ),
            );
          case SmfMarker():
            markers[event.text] = tick;
          case SmfCuePoint():
            cuePoints[event.text] = tick;
          default:
            break;
        }
      }

      // Anything still sounding when the track ends runs to its last tick.
      for (final entry in sounding.entries) {
        final began = entry.value;
        final duration = tick - began.startTick;
        if (duration <= 0) continue;
        notes.add(
          ScoreNote(
            startTick: began.startTick,
            durationTicks: duration,
            noteNumber: entry.key.note,
            velocity: began.velocity,
            channel: entry.key.channel,
          ),
        );
      }
    }

    final audible = notes
        .where((note) => !note.isSilent && note.durationTicks > 0)
        .toList()
      ..sort((a, b) {
        final byStart = a.startTick.compareTo(b.startTick);
        if (byStart != 0) return byStart;
        final byPitch = a.noteNumber.compareTo(b.noteNumber);
        if (byPitch != 0) return byPitch;
        return a.channel.compareTo(b.channel);
      });

    final endTick = file.endTick > 0 ? file.endTick : _furthest(notes, tempoMap);

    return SmfMidiScore._(
      ticksPerQuarterNote: ticksPerQuarterNote,
      notes: audible,
      tempoMap: _tempoMapOrDefault(tempoMap),
      timeSignatureMap: _signatureMapOrDefault(timeSignatures),
      endTick: endTick,
      markerTicks: markers,
      cuePointTicks: cuePoints,
      trackNames: trackNames,
      format: file.format,
      division: file.division,
    );
  }

  @override
  final int ticksPerQuarterNote;

  @override
  final List<ScoreNote> notes;

  @override
  final List<TempoChange> tempoMap;

  @override
  final List<TimeSignature> timeSignatureMap;

  @override
  final int endTick;

  /// Rehearsal marks and other landmarks, by name.
  ///
  /// Fermata already models a `CuePoint` in `PlaybackEdits`; these are the same
  /// idea read straight from the file, and reconciling the two is what M7 needs
  /// to do.
  final Map<String, int> markers;

  /// Cue points declared by the file.
  final Map<String, int> cuePoints;

  /// Names of the tracks that declared one, in file order.
  final List<String> trackNames;

  final SmfFormat format;
  final SmfDivision division;

  @override
  Duration get duration => tickToDuration(endTick);

  /// Whether the file used SMPTE frames rather than ticks per quarter note.
  ///
  /// Rare, and it means the measure maths is approximate, so the UI may want to
  /// say so rather than quietly presenting wrong bar numbers.
  bool get hasApproximateTiming => division.isSmpte;

  static int _furthest(List<ScoreNote> notes, List<TempoChange> tempoMap) {
    var furthest = 0;
    for (final note in notes) {
      if (note.endTick > furthest) furthest = note.endTick;
    }
    for (final change in tempoMap) {
      if (change.tick > furthest) furthest = change.tick;
    }
    return furthest;
  }

  static List<TempoChange> _tempoMapOrDefault(List<TempoChange> source) {
    if (source.isEmpty) {
      return const <TempoChange>[
        TempoChange(tick: 0, microsecondsPerBeat: 500000),
      ];
    }
    final sorted = source.toList()
      ..sort((a, b) => a.tick.compareTo(b.tick));
    // A tempo map that does not start at zero leaves the lookup with nothing to
    // fall back on, so the spec default is prepended.
    if (sorted.first.tick != 0) {
      return <TempoChange>[
        const TempoChange(tick: 0, microsecondsPerBeat: 500000),
        ...sorted,
      ];
    }
    return sorted;
  }

  static List<TimeSignature> _signatureMapOrDefault(
    List<TimeSignature> source,
  ) {
    if (source.isEmpty) {
      return const <TimeSignature>[
        TimeSignature(tick: 0, numerator: 4, denominator: 4),
      ];
    }
    final sorted = source.toList()
      ..sort((a, b) => a.tick.compareTo(b.tick));
    if (sorted.first.tick != 0) {
      return <TimeSignature>[
        const TimeSignature(tick: 0, numerator: 4, denominator: 4),
        ...sorted,
      ];
    }
    return sorted;
  }

  static ({int channel, int note}) _key(SmfNoteOn event) =>
      (channel: event.channel, note: event.note);

  static ({int channel, int note}) _keyOff(SmfNoteOff event) =>
      (channel: event.channel, note: event.note);

  /// Records a completed note, dropping empty ones.
  static void _close(
    List<ScoreNote> notes,
    Map<({int channel, int note}), Sounding> sounding,
    ({int channel, int note}) key,
    int endTick,
  ) {
    final began = sounding.remove(key);
    if (began == null) return;
    final duration = endTick - began.startTick;
    if (duration <= 0) return;
    notes.add(
      ScoreNote(
        startTick: began.startTick,
        durationTicks: duration,
        noteNumber: key.note,
        velocity: began.velocity,
        channel: key.channel,
      ),
    );
  }
}

/// A note that has started but not yet stopped.
class Sounding {
  const Sounding({required this.startTick, required this.velocity});

  final int startTick;
  final int velocity;
}

/// Reads [bytes] as a Standard MIDI File using Fermata's own parser.
MidiScore parseSmfBytes(List<int> bytes) => SmfMidiScore.fromBytes(bytes);