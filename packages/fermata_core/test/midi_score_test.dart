import 'dart:typed_data';

import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

import 'helpers/midi_bytes.dart';

/// Parses with Fermata's own Standard MIDI File reader.
MidiScore parseMidiBytes(List<int> bytes) => parseSmfBytes(bytes);

/// Parsing and querying real Standard MIDI File bytes.
///
/// These pin how Fermata's own reader interprets the format, since the whole
/// point of
/// hiding it behind `MidiScore` is that the rest of the app never sees it.
void main() {
  group('MidiPitch', () {
    test('labels note numbers in scientific pitch notation', () {
      expect(MidiPitch(60).label, 'C4');
      expect(MidiPitch(69).label, 'A4');
      expect(MidiPitch(61).label, 'C#4');
      expect(MidiPitch(0).label, 'C-1');
      expect(MidiPitch(127).label, 'G9');
    });

    test('identifies middle C and the concert A', () {
      expect(MidiPitch(60).isMiddleC, isTrue);
      expect(MidiPitch(61).isMiddleC, isFalse);
      expect(MidiPitch.concertA, 69);
      expect(MidiPitch(69).frequency, closeTo(440, 0.001));
    });

    test('computes equal-tempered frequencies', () {
      expect(MidiPitch(69).frequency, closeTo(440.0, 0.01));
      expect(MidiPitch(81).frequency, closeTo(880.0, 0.01));
      expect(MidiPitch(57).frequency, closeTo(220.0, 0.01));
      expect(MidiPitch(60).frequency, closeTo(261.63, 0.01));
    });

    test('knows which keys are black', () {
      // C, D, E, F, G, A, B are white; the rest are black.
      expect(MidiPitch(60).isBlackKey, isFalse); // C
      expect(MidiPitch(61).isBlackKey, isTrue); // C#
      expect(MidiPitch(62).isBlackKey, isFalse); // D
      expect(MidiPitch(64).isBlackKey, isFalse); // E
      expect(MidiPitch(66).isBlackKey, isTrue); // F#
      expect(MidiPitch(69).isBlackKey, isFalse); // A
      expect(MidiPitch(70).isBlackKey, isTrue); // A#
      expect(MidiPitch(71).isBlackKey, isFalse); // B
    });

    test('transposes by octave within the MIDI range', () {
      expect(MidiPitch(60).octaveUp?.number, 72);
      expect(MidiPitch(72).octaveDown?.number, 60);
      // C0 is note 12, and note 0 (C-1) is the bottom of the MIDI range, so
      // 12 is the lowest note that still has an octave below it.
      expect(MidiPitch(12).octaveDown?.number, 0);
      expect(MidiPitch(11).octaveDown, isNull);
      expect(MidiPitch(127).octaveUp, isNull);
    });

    test('rejects note numbers outside the MIDI range', () {
      expect(() => MidiPitch(128), throwsRangeError);
      expect(() => MidiPitch(-1), throwsRangeError);
    });

    test('offers the natural alternative for a black key', () {
      expect(Semitone.ofNote(61).naturalAlternative.name, 'C');
      expect(Semitone.ofNote(66).naturalAlternative.name, 'F');
      expect(Semitone.ofNote(70).naturalAlternative.name, 'A');
      // A white key is its own alternative.
      expect(Semitone.ofNote(60).naturalAlternative.name, 'C');
    });

    test('reports the pitch range of a set of notes', () {
      expect(MidiPitch.rangeOf(<int>[60, 72, 48]), (lowest: 48, highest: 72));
      expect(MidiPitch.rangeOf(<int>[60]), (lowest: 60, highest: 60));
      expect(MidiPitch.rangeOf(<int>[]), isNull);
    });

    test('snaps a range to whole keys so a keyboard is not clipped', () {
      // 61 is C#, 70 is A#, so both edges snap outward to a natural key.
      expect(MidiPitch.snapToOctaves(<int>[61, 70]), (lowest: 60, highest: 71));
      expect(MidiPitch.snapToOctaves(<int>[62, 69]), (lowest: 62, highest: 69));
    });
  });

  group('ScoreNote', () {
    test('treats its range as half-open', () {
      const note = ScoreNote(
        startTick: 100,
        durationTicks: 100,
        noteNumber: 60,
        velocity: 100,
        channel: 0,
      );
      expect(note.contains(100), isTrue); // start inclusive
      expect(note.contains(199), isTrue);
      expect(note.contains(200), isFalse); // end exclusive
      expect(note.contains(99), isFalse);
      expect(note.endTick, 200);
    });
  });

  group('SimpleMidiScore', () {
    // 480 ticks per quarter note, 120bpm => 500ms per quarter note.
    MidiScore build({
      List<ScoreNote> notes = const <ScoreNote>[],
      List<TempoChange> tempoMap = const <TempoChange>[],
      List<TimeSignature> timeSignatureMap = const <TimeSignature>[],
    }) => SimpleMidiScore(
      ticksPerQuarterNote: 480,
      notes: notes,
      tempoMap: tempoMap,
      timeSignatureMap: timeSignatureMap,
    );

    test('defaults to 120bpm and 4/4 when the file says nothing', () {
      final score = build();
      expect(score.tempoMap.single.bpm, closeTo(120, 0.001));
      expect(score.timeSignatureMap.single.numerator, 4);
      expect(score.timeSignatureMap.single.denominator, 4);
    });

    test('sorts notes by start tick then pitch', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 480,
            durationTicks: 480,
            noteNumber: 64,
            velocity: 100,
            channel: 0,
          ),
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 64,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      expect(
        score.notes.map((n) => n.noteNumber),
        <int>[60, 64, 64],
      );
    });

    test('reports notes sounding at a tick', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
          ScoreNote(
            startTick: 0,
            durationTicks: 960,
            noteNumber: 67,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      // At tick 0 both sound.
      expect(score.notesAt(0).map((n) => n.noteNumber), <int>[60, 67]);
      // By tick 700 only the longer note remains.
      expect(score.notesAt(700).map((n) => n.noteNumber), <int>[67]);
      expect(score.noteNumbersAt(0), <int>{60, 67});
    });

    test('deduplicates a pitch sounding on two channels', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 60,
            velocity: 100,
            channel: 1,
          ),
        ],
      );
      // One key to highlight, not two.
      expect(score.noteNumbersAt(0), <int>{60});
    });

    test('converts ticks to duration at a single tempo', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 480,
            durationTicks: 480,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      // 480 ticks = one quarter note = 500ms at 120bpm.
      expect(score.tickToDuration(480).inMilliseconds, 500);
      expect(score.tickToDuration(960).inMilliseconds, 1000);
      expect(score.tickToDuration(0), Duration.zero);
    });

    test('applies every tempo change when converting ticks', () {
      // First 480 ticks at 120bpm (500ms), then 480 ticks at 60bpm (1000ms).
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 960,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
        ],
        tempoMap: const <TempoChange>[
          TempoChange(tick: 0, microsecondsPerBeat: 500000),
          TempoChange(tick: 480, microsecondsPerBeat: 1000000),
        ],
      );
      expect(score.bpmAt(0), closeTo(120, 0.001));
      expect(score.bpmAt(479), closeTo(120, 0.001));
      expect(score.bpmAt(480), closeTo(60, 0.001));
      // 500ms + 1000ms, not a flat 1000ms.
      expect(score.tickToDuration(960).inMilliseconds, 1500);
    });

    test('converts duration back to ticks', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 960,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      expect(score.durationToTick(const Duration(milliseconds: 500)), 480);
      expect(score.durationToTick(Duration.zero), 0);
    });

    test('round-trips a tick through duration', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 1920,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      for (final tick in <int>[0, 240, 480, 960, 1440, 1920]) {
        final round = score.durationToTick(score.tickToDuration(tick));
        expect(
          (round - tick).abs(),
          lessThanOrEqualTo(2),
          reason: 'tick $tick round-tripped to $round',
        );
      }
    });

    test('derives measure boundaries from the time signature', () {
      // 4/4 at 480 ticks per quarter note = 1920 ticks per bar.
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 5760,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      // 5760 ticks is exactly three 4/4 bars.
      expect(score.measureCount, 3);
      expect(score.tickAtMeasure(1), 0);
      expect(score.tickAtMeasure(2), 1920);
      expect(score.tickAtMeasure(3), 3840);
      expect(score.measureAt(0), 1);
      expect(score.measureAt(1919), 1);
      expect(score.measureAt(1920), 2);
    });

    test('measures count from 1 for an unknown measure', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      expect(score.measureAt(-100), 1);
      expect(score.tickAtMeasure(0), 0);
      // Past the end clamps to the piece's length.
      expect(score.tickAtMeasure(9999), score.endTick);
    });

    test('handles 3/4 for waltzes', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 2880,
            noteNumber: 60,
            velocity: 100,
            channel: 0,
          ),
        ],
        timeSignatureMap: const <TimeSignature>[
          TimeSignature(tick: 0, numerator: 3, denominator: 4),
        ],
      );
      // 3/4 = 1440 ticks per bar.
      expect(score.tickAtMeasure(2), 1440);
      expect(score.measureCount, 2);
    });

    test('reports the pitch range of the piece', () {
      final score = build(
        notes: const <ScoreNote>[
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 48,
            velocity: 100,
            channel: 0,
          ),
          ScoreNote(
            startTick: 0,
            durationTicks: 480,
            noteNumber: 72,
            velocity: 100,
            channel: 0,
          ),
        ],
      );
      expect(score.pitchRange, (lowest: 48, highest: 72));
      expect(build().pitchRange, isNull);
    });
  });

  group('parseMidiBytes', () {
    test('reads a single note with its duration', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 480, bytes: MidiBytes.noteOff(0, 60)),
        ],
      );

      final score = parseMidiBytes(bytes);
      expect(score.ticksPerQuarterNote, 480);
      expect(score.notes, hasLength(1));
      expect(score.notes.single.noteNumber, 60);
      expect(score.notes.single.startTick, 0);
      expect(score.notes.single.durationTicks, 480);
    });

    test('treats a zero-velocity note-on as a note-off', () {
      // This is how running-status files usually spell a note-off.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 240, bytes: MidiBytes.noteOffAsZeroVelocity(0, 60)),
        ],
      );

      final score = parseMidiBytes(bytes);
      // One note, not a stuck note plus a phantom.
      expect(score.notes, hasLength(1));
      expect(score.notes.single.durationTicks, 240);
      expect(score.notes.single.isSilent, isFalse);
    });

    test('pairs note-ons and note-offs across channels', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 0, bytes: MidiBytes.noteOn(1, 60)),
          (deltaTime: 480, bytes: MidiBytes.noteOff(0, 60)),
        ],
      );

      final score = parseMidiBytes(bytes);
      // The channel-1 note never closes, so it runs to the end of the track
      // rather than being silently dropped.
      expect(score.notes, hasLength(2));
      expect(score.noteNumbersAt(0), <int>{60});
    });

    test('reads the tempo map', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.setTempo(500000)),
          (deltaTime: 960, bytes: MidiBytes.setTempo(1000000)),
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 480, bytes: MidiBytes.noteOff(0, 60)),
        ],
      );

      final score = parseMidiBytes(bytes);
      expect(score.tempoMap, hasLength(2));
      expect(score.bpmAt(0), closeTo(120, 0.001));
      expect(score.bpmAt(960), closeTo(60, 0.001));
    });

    test('reads a time signature whose denominator is a stored exponent', () {
      // 3/4 is stored with exponent 2, not the value 4.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.timeSignature(3, 2)),
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 1440, bytes: MidiBytes.noteOff(0, 60)),
        ],
      );

      final score = parseMidiBytes(bytes);
      // The parser converts the exponent, so this must read as 4 and not 16.
      expect(score.timeSignatureMap.single.numerator, 3);
      expect(score.timeSignatureMap.single.denominator, 4);
      expect(score.tickAtMeasure(2), 1440);
    });

    test('defaults to 4/4 when a file declares no time signature', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 480, bytes: MidiBytes.noteOff(0, 60)),
        ],
      );

      final score = parseMidiBytes(bytes);
      expect(score.timeSignatureMap.single.numerator, 4);
      expect(score.timeSignatureMap.single.denominator, 4);
    });

    test('answers which notes sound at a tick', () {
      // A broken chord: C and E together, then G alone.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 64)),
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 67)),
          (deltaTime: 480, bytes: MidiBytes.noteOff(0, 60)),
          (deltaTime: 0, bytes: MidiBytes.noteOff(0, 64)),
          (deltaTime: 0, bytes: MidiBytes.noteOff(0, 67)),
        ],
      );

      final score = parseMidiBytes(bytes);
      expect(score.noteNumbersAt(0), <int>{60, 64, 67});
      expect(score.notesAt(240), hasLength(3));
      expect(score.noteNumbersAt(480), isEmpty);
    });

    test('computes a duration for a parsed piece', () {
      // One quarter note of C at 120bpm is half a second.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.setTempo(500000)),
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 480, bytes: MidiBytes.noteOff(0, 60)),
        ],
      );

      final score = parseMidiBytes(bytes);
      expect(score.duration.inMilliseconds, 500);
    });

    test('throws a typed exception for bytes that are not a MIDI file', () {
      expect(
        () => parseMidiBytes(<int>[0x00, 0x01, 0x02, 0x03]),
        throwsA(isA<MidiFormatException>()),
      );
    });
  });
}