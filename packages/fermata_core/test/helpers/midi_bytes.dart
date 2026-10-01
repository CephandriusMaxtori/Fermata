import 'dart:typed_data';

/// Builds real Standard MIDI File bytes in memory.
///
/// The parser tests need actual `.mid` files rather than hand-built
/// [ScoreNote] lists, because the whole point of the parser tests is to pin how
/// Fermata's own reader interprets the format: variable-length delta times, running
/// status, zero-velocity note-ons, and the time signature's power-of-two
/// denominator. A hand-built list would only test our own code twice.
///
/// Bytes are assembled here rather than checked in as a binary fixture so the
/// intent of each byte is visible next to the assertion that depends on it.
abstract final class MidiBytes {
  /// A format 0 file with one track, at [ticksPerQuarterNote] resolution.
  ///
  /// [events] is a list of `(deltaTime, eventBytes)` in the order they should be
  /// written. The caller controls the raw bytes so tests can exercise running
  /// status and the meta events individually.
  static Uint8List format0({
    required int ticksPerQuarterNote,
    required List<({int deltaTime, Uint8List bytes})> events,
  }) {
    final track = BytesBuilder();

    for (final event in events) {
      track.add(_varInt(event.deltaTime));
      track.add(event.bytes);
    }
    // End of track: delta 0, FF 2F 00
    track.add(<int>[0x00, 0xFF, 0x2F, 0x00]);

    final trackBytes = track.toBytes();

    final header = BytesBuilder()
      ..add('MThd'.codeUnits)
      ..add(_uint32(6))
      ..add(_uint16(0)) // format 0
      ..add(_uint16(1)) // one track
      ..add(_uint16(ticksPerQuarterNote));

    final trackChunk = BytesBuilder()
      ..add('MTrk'.codeUnits)
      ..add(_uint32(trackBytes.length))
      ..add(trackBytes);

    return Uint8List.fromList(
      <int>[...header.toBytes(), ...trackChunk.toBytes()],
    );
  }

  /// A note-on event with an explicit status byte, so a test can force a
  /// zero-velocity note-on the way running-status files spell a note-off.
  static Uint8List noteOn(
    int channel,
    int note, [
    int velocity = 100,
  ]) => Uint8List.fromList(<int>[0x90 | channel, note, velocity]);

  /// A note-on event with velocity 0, which means "note off".
  static Uint8List noteOffAsZeroVelocity(int channel, int note) =>
      Uint8List.fromList(<int>[0x90 | channel, note, 0]);

  static Uint8List noteOff(int channel, int note, [int velocity = 0]) =>
      Uint8List.fromList(<int>[0x80 | channel, note, velocity]);

  /// A tempo event. [microsecondsPerBeat] of 500000 is 120bpm.
  static Uint8List setTempo(int microsecondsPerBeat) => Uint8List.fromList(
    <int>[
      0xFF,
      0x51,
      0x03,
      (microsecondsPerBeat >> 16) & 0xFF,
      (microsecondsPerBeat >> 8) & 0xFF,
      microsecondsPerBeat & 0xFF,
    ],
  );

  /// A time signature event.
  ///
  /// [denominatorExponent] is the raw exponent the format stores, so 2 means 4/4
  /// and 3 means 4/8. Passing the exponent rather than the denominator keeps the
  /// test honest about what actually sits in the file.
  static Uint8List timeSignature(int numerator, int denominatorExponent) =>
      Uint8List.fromList(<int>[
        0xFF,
        0x58,
        0x04,
        numerator,
        denominatorExponent,
        24,
        8,
      ]);

  /// The MIDI variable-length quantity used for delta times.
  static Uint8List _varInt(int value) {
    final out = <int>[];
    var buffer = value & 0x7F;
    while ((value >>= 7) > 0) {
      buffer <<= 8;
      buffer |= (value & 0x7F) | 0x80;
    }
    while (true) {
      out.add(buffer & 0xFF);
      if ((buffer & 0x80) != 0) {
        buffer >>= 8;
      } else {
        break;
      }
    }
    return Uint8List.fromList(out);
  }

  static Uint8List _uint16(int value) => Uint8List.fromList(<int>[
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);

  static Uint8List _uint32(int value) => Uint8List.fromList(<int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}