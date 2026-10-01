import 'dart:typed_data';

import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

import 'helpers/midi_bytes.dart';

/// Tests for Fermata's own Standard MIDI File reader.
///
/// These cover the parts of the format that are easy to get subtly wrong and
/// impossible to notice until a real piece fails to play: running status,
/// multi-track files, SMPTE division, and malformed input. The interpretation
/// layer is covered separately in `midi_score_test.dart`.
void main() {
  const parser = SmfParser();

  group('SmfParser header', () {
    test('reads format, track count and division', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 480,
        events: <({int deltaTime, Uint8List bytes})>[],
      );

      final file = parser.parse(bytes);
      expect(file.format, SmfFormat.format0);
      expect(file.tracks, hasLength(1));
      expect(file.division.ticksPerQuarterNote, 480);
      expect(file.division.isSmpte, isFalse);
    });

    test('rejects a file whose magic is not MThd', () {
      expect(
        () => parser.parse(<int>[
          0x4E, 0x54, 0x48, 0x64, // 'NTDd' instead of 'MThd'
          0, 0, 0, 6,
          0, 0, 0, 1, 0, 96,
        ]),
        throwsA(
          isA<MidiFormatException>().having(
            (e) => e.message,
            'message',
            contains('MThd'),
          ),
        ),
      );
    });

    test('rejects an unknown format number', () {
      expect(
        () => parser.parse(<int>[
          0x4D, 0x54, 0x68, 0x64, // MThd
          0, 0, 0, 6,
          0, 9, // format 9, which does not exist
          0, 1,
          0, 96,
        ]),
        throwsA(
          isA<MidiFormatException>().having(
            (e) => e.message,
            'message',
            contains('Unknown MIDI format'),
          ),
        ),
      );
    });

    test('rejects a truncated file rather than reading past the end', () {
      // A header claiming six bytes but supplying two.
      expect(
        () => parser.parse(<int>[
          0x4D, 0x54, 0x68, 0x64,
          0, 0, 0, 6,
          0, 0,
        ]),
        throwsA(isA<MidiFormatException>()),
      );
    });

    test('rejects a file whose track chunk is missing', () {
      // One declared track, no MTrk chunk following it.
      expect(
        () => parser.parse(<int>[
          0x4D, 0x54, 0x68, 0x64,
          0, 0, 0, 6,
          0, 0, // format 0
          0, 1, // one track
          0, 96, // 96 ticks per quarter note
        ]),
        throwsA(isA<MidiFormatException>()),
      );
    });

    test('tolerates a header longer than the six defined bytes', () {
      // Some writers pad the header; the extra bytes should be skipped, not
      // mistaken for a track chunk.
      final file = parser.parse(<int>[
        0x4D, 0x54, 0x68, 0x64,
        0, 0, 0, 10, // header is ten bytes
        0, 0, // format 0
        0, 1, // one track
        0, 96, // division
        0, 0, 0, 0, // four bytes of padding
        0x4D, 0x54, 0x72, 0x6B, // MTrk
        0, 0, 0, 4,
        0x00, 0xFF, 0x2F, 0x00, // delta 0, end of track
      ]);

      expect(file.format, SmfFormat.format0);
      expect(file.tracks, hasLength(1));
    });
  });

  group('SmfParser events', () {
    test('accumulates delta times into absolute ticks', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 96, bytes: MidiBytes.noteOn(0, 64)),
          (deltaTime: 192, bytes: MidiBytes.noteOn(0, 67)),
          (deltaTime: 96, bytes: MidiBytes.noteOff(0, 60)),
          (deltaTime: 0, bytes: MidiBytes.noteOff(0, 64)),
          (deltaTime: 0, bytes: MidiBytes.noteOff(0, 67)),
        ],
      );

      final score = parseSmfBytes(bytes);
      expect(score.notes.map((n) => n.startTick), <int>[0, 96, 288]);
    });

    test('drops a note-on with no note-off that would have no duration', () {
      // A note starting exactly at the end of the track is zero-length, and a
      // zero-length note cannot be heard or highlighted, so it is not kept.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 96, bytes: MidiBytes.noteOff(0, 60)),
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 67)),
        ],
      );

      final score = parseSmfBytes(bytes);
      expect(score.notes.map((n) => n.noteNumber), <int>[60]);
    });

    test('handles running status, where data bytes repeat a status', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          // Each of these is only two bytes: the status is implied.
          (deltaTime: 96, bytes: Uint8List.fromList(<int>[62, 100])),
          (deltaTime: 96, bytes: Uint8List.fromList(<int>[64, 100])),
          // A note-off under running status still carries note and velocity.
          (deltaTime: 96, bytes: Uint8List.fromList(<int>[60, 0])),
        ],
      );

      final score = parseSmfBytes(bytes);
      // 60 sounds from 0 to 288, and 62 and 64 run to the end of the track.
      expect(score.notes.map((n) => n.noteNumber).toSet(), <int>{60, 62, 64});
      // 64 has not started until tick 192, so it is absent at 96.
      expect(score.noteNumbersAt(96), <int>{60, 62});
      expect(score.noteNumbersAt(192), <int>{60, 62, 64});
      // 60 was closed at tick 288, so it is no longer sounding.
      expect(score.noteNumbersAt(288), isNot(contains(60)));
    });

    test('clears running status after a meta event', () {
      // Per the spec a meta event resets running status, so a data byte after one
      // is not a continuation of the earlier note and must be rejected rather
      // than silently reinterpreted.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 0, bytes: MidiBytes.setTempo(500000)),
          (deltaTime: 96, bytes: Uint8List.fromList(<int>[60, 100])),
        ],
      );

      expect(
        () => parser.parse(bytes),
        throwsA(
          isA<MidiFormatException>().having(
            (e) => e.message,
            'message',
            contains('running status'),
          ),
        ),
      );
    });

    test('starts a fresh running status after a status byte', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 0, bytes: MidiBytes.setTempo(500000)),
          // A real status byte establishes a new running status.
          (deltaTime: 96, bytes: MidiBytes.noteOn(0, 64)),
          (deltaTime: 96, bytes: Uint8List.fromList(<int>[67, 100])),
          (deltaTime: 96, bytes: Uint8List.fromList(<int>[60, 0])),
        ],
      );

      final score = parseSmfBytes(bytes);
      expect(score.tempoMap, hasLength(1));
      // 60 was closed by the running-status note-off at tick 288, but it still
      // sounds for the whole span before that.
      expect(score.notes.map((n) => n.noteNumber).toSet(), <int>{60, 64, 67});
      expect(score.noteNumbersAt(0), <int>{60});
    });

    test('rejects a data byte that has no running status', () {
      expect(
        () => parser.parse(<int>[
          0x4D, 0x54, 0x68, 0x64,
          0, 0, 0, 6,
          0, 0, 0, 1, 0, 96,
          0x4D, 0x54, 0x72, 0x6B,
          0, 0, 0, 4,
          0x00, // delta 0
          0x3C, 0x40, // a data byte with no status before it
          0x00,
        ]),
        throwsA(
          isA<MidiFormatException>().having(
            (e) => e.message,
            'message',
            contains('running status'),
          ),
        ),
      );
    });

    test('reads program change and control change, which carry one or two bytes', () {
      // Program change has a single data byte, so the next event must start
      // cleanly rather than eating it.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: Uint8List.fromList(<int>[0xC0, 42])),
          (deltaTime: 0, bytes: Uint8List.fromList(<int>[0xB0, 7, 100])),
        ],
      );

      final file = parser.parse(bytes);
      final events = file.tracks.single.events;
      final program = events.whereType<SmfProgramChange>().single;
      expect(program.program, 42);
      final control = events.whereType<SmfControlChange>().single;
      expect(control.controller, 7);
      expect(control.value, 100);
    });

    test('reads a pitch bend as a centred 14-bit value', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          // LSB 0x00, MSB 0x40 => 8192, which is centre.
          (deltaTime: 0, bytes: Uint8List.fromList(<int>[0xE0, 0x00, 0x40])),
        ],
      );

      final file = parser.parse(bytes);
      expect(file.tracks.single.events.whereType<SmfPitchBend>().single.value, 8192);
    });

    test('reads track, instrument, marker and cue point text', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: _text(0x03, 'Piano')),
          (deltaTime: 0, bytes: _text(0x04, 'Grand Piano')),
          (deltaTime: 0, bytes: _text(0x06, 'A')),
          (deltaTime: 0, bytes: _text(0x07, 'Chorus')),
        ],
      );

      final file = parser.parse(bytes);
      final events = file.tracks.single.events;
      expect(events.whereType<SmfTrackName>().single.text, 'Piano');
      expect(events.whereType<SmfInstrumentName>().single.text, 'Grand Piano');
      expect(events.whereType<SmfMarker>().single.text, 'A');
      expect(events.whereType<SmfCuePoint>().single.text, 'Chorus');
      expect(file.tracks.single.name, 'Piano');
    });

    test('keeps an unrecognised meta event instead of discarding it', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: _text(0x60, 'custom')),
        ],
      );

      final file = parser.parse(bytes);
      final unknown = file.tracks.single.events.whereType<SmfUnknownMeta>().single;
      expect(unknown.metaType, 0x60);
      expect(unknown.data.toLatin1String(), 'custom');
    });

    test('reads a multi-byte variable-length delta time', () {
      // 0x81 0x00 is a two-byte VLQ meaning 128.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 128, bytes: MidiBytes.noteOn(0, 60)),
          (deltaTime: 96, bytes: MidiBytes.noteOff(0, 60)),
        ],
      );

      final score = parseSmfBytes(bytes);
      expect(score.notes.single.startTick, 128);
    });

    test('reads a tempo whose three bytes need all of them', () {
      // 0x0F 0x42 0x40 = 1000000 us per beat = 60bpm, which needs the full
      // three bytes rather than fitting in one.
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          (deltaTime: 0, bytes: MidiBytes.setTempo(1000000)),
        ],
      );

      final score = parseSmfBytes(bytes);
      expect(score.bpmAt(0), closeTo(60, 0.001));
    });

    test('reads a signed key signature with flats', () {
      final bytes = MidiBytes.format0(
        ticksPerQuarterNote: 96,
        events: <({int deltaTime, Uint8List bytes})>[
          // Two flats, major: 0xFE is -2 in two's complement.
          (deltaTime: 0, bytes: Uint8List.fromList(<int>[0xFF, 0x59, 0x02, 0xFE, 0x00])),
        ],
      );

      final file = parser.parse(bytes);
      final key = file.tracks.single.events.whereType<SmfKeySignature>().single;
      expect(key.sharps, -2);
      expect(key.isMinor, isFalse);
    });
  });

  group('SmfDivision', () {
    test('recognises SMPTE division and resolves it against a tempo', () {
      // 0xE728: high bit set, 0xE7 => 25fps, 0x28 = 40 ticks per frame.
      final file = parser.parse(<int>[
        0x4D, 0x54, 0x68, 0x64,
        0, 0, 0, 6,
        0, 0, 0, 1,
        0xE7, 0x28,
        0x4D, 0x54, 0x72, 0x6B,
        0, 0, 0, 4,
        0x00, 0xFF, 0x2F, 0x00,
      ]);

      expect(file.division.isSmpte, isTrue);
      expect(file.division.framesPerSecond, 25);
      expect(file.division.ticksPerFrame, 40);
      // 40 ticks/frame * 25fps / 2 = 500 ticks per quarter note at 120bpm.
      expect(file.division.resolveTicksPerQuarterNote(), 500);
    });

    test('falls back to 480 for a nonsensical metric division', () {
      expect(const SmfDivision.ticksPerQuarterNote(0).resolveTicksPerQuarterNote(), 480);
    });

    test('flags approximate timing on a score parsed from SMPTE', () {
      final file = parser.parse(<int>[
        0x4D, 0x54, 0x68, 0x64,
        0, 0, 0, 6,
        0, 0, 0, 1,
        0xE7, 0x28,
        0x4D, 0x54, 0x72, 0x6B,
        0, 0, 0, 4,
        0x00, 0xFF, 0x2F, 0x00,
      ]);
      expect(SmfMidiScore.fromFile(file).hasApproximateTiming, isTrue);
    });
  });

  group('ByteCursor', () {
    test('reads multi-byte integers big-endian', () {
      final cursor = ByteCursor(<int>[0x12, 0x34, 0x56, 0x78]);
      expect(cursor.readUint16(), 0x1234);
      expect(cursor.readUint16(), 0x5678);
      expect(cursor.isAtEnd, isTrue);
    });

    test('reads a 24-bit value', () {
      final cursor = ByteCursor(<int>[0x0F, 0x42, 0x40]);
      expect(cursor.readUint24(), 1000000);
    });

    test('decodes two\'s-complement signed bytes', () {
      final cursor = ByteCursor(<int>[0x7F, 0x80, 0xFF]);
      expect(cursor.readInt8(), 127);
      expect(cursor.readInt8(), -128);
      expect(cursor.readInt8(), -1);
    });

    test('decodes variable-length quantities', () {
      expect(ByteCursor(<int>[0x00]).readVariableLength(), 0);
      expect(ByteCursor(<int>[0x40]).readVariableLength(), 64);
      expect(ByteCursor(<int>[0x81, 0x00]).readVariableLength(), 128);
      expect(ByteCursor(<int>[0xC0, 0x00]).readVariableLength(), 8192);
      // The largest legal value, 0x0FFFFFFF, encoded as four continuation bytes.
      expect(
        ByteCursor(<int>[0xFF, 0xFF, 0xFF, 0x7F]).readVariableLength(),
        268435455,
      );
    });

    test('rejects an over-long variable-length quantity', () {
      expect(
        () => ByteCursor(<int>[0x80, 0x80, 0x80, 0x80, 0x00]).readVariableLength(),
        throwsA(isA<MidiFormatException>()),
      );
    });

    test('rejects a data byte above 0x7F where a 7-bit value is required', () {
      expect(
        () => ByteCursor(<int>[0x80]).readInt7(),
        throwsA(isA<MidiFormatException>()),
      );
    });

    test('reports a helpful message when the buffer ends early', () {
      final cursor = ByteCursor(<int>[0x01]);
      expect(
        cursor.readUint32,
        throwsA(
          isA<MidiFormatException>().having(
            (e) => e.message,
            'message',
            contains('Unexpected end of file'),
          ),
        ),
      );
    });

    test('decodes payload text as Latin-1 rather than UTF-8', () {
      // 0xE9 is 'e' with an acute in Latin-1 but invalid alone in UTF-8.
      final cursor = ByteCursor(<int>[0x4D, 0x54, 0x68, 0x64, 0xE9]);
      expect(cursor.readBytes(5).toLatin1String(), 'MThd\xE9');
    });
  });
}

/// Builds a text meta event.
Uint8List _text(int type, String value) {
  final bytes = <int>[value.codeUnitAt(0)];
  for (final unit in value.substring(1).codeUnits) {
    bytes.add(unit);
  }
  return Uint8List.fromList(<int>[
    0xFF,
    type,
    bytes.length,
    ...bytes,
  ]);
}