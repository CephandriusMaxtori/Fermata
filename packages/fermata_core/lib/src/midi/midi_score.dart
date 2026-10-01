/// A parsed MIDI file, expressed in Fermata's own vocabulary.
///
/// This is the seam the rest of the app builds on. The piano visualizer, the
/// falling-notes lane, auto-scroll and A-B looping all need the same three
/// things: which notes sound at a given moment, where the measures are, and how
/// fast the music is going. None of that should depend on which library parsed
/// the bytes, so this interface is what they see and the SMF reader is an
/// implementation detail behind it.
///
/// Keeping it pure Dart also keeps it unit testable with no plugin and no audio
/// engine, which is the only reason the timeline can be validated before the
/// playback layer exists.
library;

import 'package:collection/collection.dart';

import 'midi_pitch.dart';

export 'midi_pitch.dart';

/// One sounding note, addressed by its position in the piece rather than in
/// wall-clock time.
///
/// Tempo is deliberately absent. A note's duration in ticks is fixed by the
/// file; how long that turns out to be depends on the tempo in force, which the
/// user can change while playing. Keeping that out of the model means slowing a
/// piece down never invalidates its notes.
class ScoreNote {
  const ScoreNote({
    required this.startTick,
    required this.durationTicks,
    required this.noteNumber,
    required this.velocity,
    required this.channel,
  });

  /// When the note begins, in ticks.
  final int startTick;

  /// How long it sounds, in ticks.
  final int durationTicks;

  /// Raw MIDI note number, 0-127.
  final int noteNumber;

  /// 0-127. Zero-velocity note-ons are running-status note-offs, so a note with
  /// velocity 0 should not be treated as audible.
  final int velocity;

  /// MIDI channel, 0-15.
  final int channel;

  int get endTick => startTick + durationTicks;

  bool get isSilent => velocity == 0;

  /// Whether this note is sounding at [tick].
  ///
  /// Half-open, so a note that ends exactly where the next begins does not
  /// report as two notes at the same instant. This is the same convention
  /// `LoopRange.contains` uses.
  bool contains(int tick) => tick >= startTick && tick < endTick;

  @override
  String toString() =>
      'ScoreNote($noteNumber, tick $startTick..$endTick, vel $velocity, ch $channel)';
}

/// A tempo change at a given tick.
class TempoChange {
  const TempoChange({required this.tick, required this.microsecondsPerBeat});

  final int tick;
  final int microsecondsPerBeat;

  /// Beats per minute derived from the tempo event.
  double get bpm => 60000000.0 / microsecondsPerBeat;

  @override
  String toString() => 'TempoChange(tick $tick, ${bpm.toStringAsFixed(1)} bpm)';
}

/// A time signature in force from [tick].
class TimeSignature {
  const TimeSignature({
    required this.tick,
    required this.numerator,
    required this.denominator,
  });

  final int tick;
  final int numerator;
  final int denominator;

  /// Ticks per bar, using the file's ticks-per-quarter-note.
  ///
  /// Handles compound and asymmetric signatures like 6/8 and 7/8 by counting
  /// in quarter notes: a 6/8 bar is three eighths, which is 3/4 of a quarter
  /// note, so its length in ticks depends on the denominator's power of two.
  int ticksPerBar(int ticksPerQuarterNote) =>
      numerator * ticksPerQuarterNote * 4 ~/ denominator;

  @override
  String toString() =>
      'TimeSignature(tick $tick, $numerator/$denominator)';
}

/// The musical content of a MIDI file, ready for practice.
abstract interface class MidiScore {
  /// The ticks the file uses per quarter note, as declared in its header.
  int get ticksPerQuarterNote;

  /// Every audible note, ordered by start tick then note number.
  ///
  /// Silent note-ons (velocity 0, which is how many files spell a note-off) are
  /// excluded. Callers that need the raw events should read the file directly.
  List<ScoreNote> get notes;

  /// The piece's tempo map, always starting at tick 0.
  ///
  /// A file with no tempo event gets the spec default of 120bpm at tick 0, so
  /// this is never empty.
  List<TempoChange> get tempoMap;

  /// The time signatures in force, always starting at tick 0.
  List<TimeSignature> get timeSignatureMap;

  /// The last tick that carries any event, which is the piece's length.
  int get endTick;

  /// Wall-clock duration at the file's own tempo.
  Duration get duration;

  /// Whether [tick] falls inside the piece.
  bool containsTick(int tick);

  /// The notes sounding at [tick].
  List<ScoreNote> notesAt(int tick);

  /// The note numbers sounding at [tick], ascending and deduplicated.
  ///
  /// This is what the visualizer highlights. Deduplicated because the same pitch
  /// on two channels is one key to light up.
  Set<int> noteNumbersAt(int tick);

  /// The lowest and highest note numbers that sound anywhere in the piece.
  ///
  /// Null when the piece is silent, which the visualizer treats differently from
  /// a zero-width range. Used to window the on-screen keyboard to the part of
  /// the instrument a piece actually needs.
  ({int lowest, int highest})? get pitchRange;

  /// Converts a tick to elapsed time at the file's own tempo.
  Duration tickToDuration(int tick);

  /// Converts elapsed time back to a tick at the file's own tempo.
  int durationToTick(Duration elapsed);

  /// The measure number containing [tick], counting from 1.
  ///
  /// This walks the tempo-independent structure: the file's bar lines as
  /// declared by its time signatures. For a file with no time signature event it
  /// assumes 4/4, which is what most music is written in.
  int measureAt(int tick);

  /// The tick at which measure [measure] begins, counting from 1.
  ///
  /// Returns [endTick] for a measure past the end, so a caller looping a range
  /// can clamp without special-casing the tail.
  int tickAtMeasure(int measure);

  /// Total measure count, rounded up so a trailing partial bar still counts.
  int get measureCount;

  /// The tempo in force at [tick], in beats per minute.
  double bpmAt(int tick);
}

/// Base for [MidiScore] implementations, providing every query in terms of the
/// five fields a subclass must supply.
///
/// The lookups are the same regardless of how a file was parsed, and they must
/// not drift between implementations, so they live here once. An extension
/// would not do: extension members are not inherited, so a class that
/// `implements MidiScore` would still be obliged to write out all of them.
abstract class BaseMidiScore implements MidiScore {
  const BaseMidiScore();

  /// Whether [tick] falls inside the piece.
  @override
  bool containsTick(int tick) => tick >= 0 && tick <= endTick;

  /// The tempo in force at [tick].
  TempoChange tempoChangeAt(int tick) {
    var result = tempoMap.first;
    for (final change in tempoMap) {
      if (change.tick > tick) break;
      result = change;
    }
    return result;
  }

  /// The time signature in force at [tick].
  TimeSignature timeSignatureAt(int tick) {
    var result = timeSignatureMap.first;
    for (final signature in timeSignatureMap) {
      if (signature.tick > tick) break;
      result = signature;
    }
    return result;
  }

  /// The notes sounding at [tick].
  @override
  List<ScoreNote> notesAt(int tick) =>
      notes.where((note) => note.contains(tick)).toList(growable: false);

  /// The note numbers sounding at [tick], ascending and deduplicated.
  @override
  Set<int> noteNumbersAt(int tick) {
    final sounding = <int>{};
    for (final note in notes) {
      if (note.contains(tick)) sounding.add(note.noteNumber);
    }
    return sounding;
  }

  /// Ticks elapsed at [tick] once every tempo change up to it is applied.
  ///
  /// Walks the tempo map rather than assuming one tempo, because a piece that
  /// slows down for a ritardando would otherwise be timed wrongly for its whole
  /// second half.
  @override
  Duration tickToDuration(int tick) {
    if (tick <= 0) return Duration.zero;
    final target = tick.clamp(0, endTick);

    var elapsedMicros = 0;
    var consumedTicks = 0;

    for (var i = 0; i < tempoMap.length; i++) {
      final change = tempoMap[i];
      final nextTick = i + 1 < tempoMap.length ? tempoMap[i + 1].tick : null;

      // This tempo is in force from `change.tick` until the next change.
      final segmentEnd = nextTick == null
          ? target
          : (target < nextTick ? target : nextTick);
      if (segmentEnd <= change.tick) break;

      final ticksInSegment = segmentEnd - change.tick;
      final beats = ticksInSegment / ticksPerQuarterNote;
      elapsedMicros += (beats * change.microsecondsPerBeat).round();
      consumedTicks = segmentEnd;
    }

    if (consumedTicks < target) {
      final beats = (target - consumedTicks) / ticksPerQuarterNote;
      elapsedMicros += (beats * tempoMap.last.microsecondsPerBeat).round();
    }

    return Duration(microseconds: elapsedMicros);
  }

  /// The tick reached after [elapsed] at the file's own tempo.
  @override
  int durationToTick(Duration elapsed) {
    if (elapsed <= Duration.zero) return 0;
    final targetMicros = elapsed.inMicroseconds;

    var microsAtTick = 0;

    for (var i = 0; i < tempoMap.length; i++) {
      final change = tempoMap[i];
      final nextTick = i + 1 < tempoMap.length ? tempoMap[i + 1].tick : null;
      final segmentEnd = nextTick ?? endTick;
      if (segmentEnd <= change.tick) continue;

      final ticksInSegment = segmentEnd - change.tick;
      final segmentMicros =
          (ticksInSegment / ticksPerQuarterNote * change.microsecondsPerBeat)
              .round();

      if (microsAtTick + segmentMicros >= targetMicros) {
        final intoSegment = targetMicros - microsAtTick;
        final fraction = change.microsecondsPerBeat == 0
            ? 0.0
            : intoSegment / change.microsecondsPerBeat;
        final beats = fraction * ticksPerQuarterNote;
        return (change.tick + beats).round().clamp(0, endTick);
      }

      microsAtTick += segmentMicros;
    }

    return endTick;
  }

  /// Beats per minute at [tick].
  @override
  double bpmAt(int tick) => tempoChangeAt(tick).bpm;

  /// The tick where each measure begins.
  ///
  /// Derived from the time signature map rather than from any bar-line event,
  /// because many files omit bar lines entirely and rely on the time signature.
  /// A file that declares no signature is treated as 4/4, which is the spec
  /// default and what most written music uses.
  List<int> get measureStarts {
    final starts = <int>[0];
    var tick = 0;
    while (tick < endTick) {
      final signature = timeSignatureAt(tick);
      final ticksPerBar = signature.ticksPerBar(ticksPerQuarterNote);
      if (ticksPerBar <= 0) break;
      tick += ticksPerBar;
      if (tick < endTick) starts.add(tick);
    }
    return List<int>.unmodifiable(starts);
  }

  /// The measure number containing [tick], counting from 1.
  @override
  int measureAt(int tick) {
    final starts = measureStarts;
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (starts[mid] <= tick) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low + 1;
  }

  /// The tick at which measure [measure] begins, counting from 1.
  @override
  int tickAtMeasure(int measure) {
    final starts = measureStarts;
    final index = measure - 1;
    if (index < 0) return 0;
    if (index >= starts.length) return endTick;
    return starts[index];
  }

  /// Total measure count.
  @override
  int get measureCount => measureStarts.length;

  /// The lowest and highest note numbers that sound, or null when silent.
  @override
  ({int lowest, int highest})? get pitchRange =>
      MidiPitch.rangeOf(notes.map((note) => note.noteNumber));
}

/// Builds a [MidiScore] from already-extracted parts.
///
/// Exists so tests, and the companion web UI's importer, can construct a score
/// without going through a parser.
class SimpleMidiScore extends BaseMidiScore {
  SimpleMidiScore({
    required this.ticksPerQuarterNote,
    required List<ScoreNote> notes,
    List<TempoChange>? tempoMap,
    List<TimeSignature>? timeSignatureMap,
    int? endTick,
  }) : notes = _sortedNotes(notes),
       tempoMap = _tempoMapOrDefault(tempoMap),
       timeSignatureMap = _signatureMapOrDefault(timeSignatureMap),
       endTick = endTick ?? _furthestTick(notes, tempoMap);

  /// Both maps must start at tick 0 or the lookups have nothing to fall back
  /// on. The spec defaults are 120bpm and 4/4, which is what a file with no
  /// such event means.
  static List<TempoChange> _tempoMapOrDefault(List<TempoChange>? source) {
    final tempos = source ?? const <TempoChange>[];
    if (tempos.isEmpty) {
      return const <TempoChange>[
        TempoChange(tick: 0, microsecondsPerBeat: 500000),
      ];
    }
    return List<TempoChange>.unmodifiable(
      tempos.sorted((a, b) => a.tick.compareTo(b.tick)),
    );
  }

  static List<TimeSignature> _signatureMapOrDefault(
    List<TimeSignature>? source,
  ) {
    final signatures = source ?? const <TimeSignature>[];
    if (signatures.isEmpty) {
      return const <TimeSignature>[
        TimeSignature(tick: 0, numerator: 4, denominator: 4),
      ];
    }
    return List<TimeSignature>.unmodifiable(
      signatures.sorted((a, b) => a.tick.compareTo(b.tick)),
    );
  }

  static List<ScoreNote> _sortedNotes(List<ScoreNote> notes) =>
      List<ScoreNote>.unmodifiable(
        notes.sorted((a, b) {
          final byStart = a.startTick.compareTo(b.startTick);
          return byStart != 0
              ? byStart
              : a.noteNumber.compareTo(b.noteNumber);
        }),
      );

  /// The piece's length: the last note's end, or the last event in a tempo map
  /// that outlives the notes.
  static int _furthestTick(List<ScoreNote> notes, List<TempoChange>? tempoMap) {
    var furthest = 0;
    for (final note in notes) {
      if (note.endTick > furthest) furthest = note.endTick;
    }
    for (final change in tempoMap ?? const <TempoChange>[]) {
      if (change.tick > furthest) furthest = change.tick;
    }
    return furthest;
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

  /// Wall-clock duration at the file's own tempo.
  @override
  Duration get duration => tickToDuration(endTick);
}