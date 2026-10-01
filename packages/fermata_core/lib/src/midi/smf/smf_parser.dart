/// A parsed Standard MIDI File: its header plus the raw events of each track.
///
/// This is the faithful, lossless layer. It does not interpret the music, pair
/// note-ons with note-offs, or decide what a tempo map means. It records what the
/// file actually says, in the order it says it. Interpretation happens one level
/// up in `MidiScore`, which keeps the format's quirks (running status, zero
/// note-offs, SMPTE division) in one place instead of spread through the app.
library;

import 'byte_cursor.dart';

/// The file's declared structure.
enum SmfFormat {
  /// One multi-channel track.
  format0(0),

  /// A tempo map track followed by one track per part.
  format1(1),

  /// Independent, unsynchronised tracks, played as one.
  format2(2);

  const SmfFormat(this.value);

  final int value;

  static SmfFormat? fromValue(int value) {
    for (final format in SmfFormat.values) {
      if (format.value == value) return format;
    }
    return null;
  }
}

/// How the file expresses time.
class SmfDivision {
  const SmfDivision.ticksPerQuarterNote(this.ticksPerQuarterNote)
    : framesPerSecond = null,
      ticksPerFrame = null;

  /// SMPTE timing: frames per second and ticks per frame.
  const SmfDivision.smpte({
    required this.framesPerSecond,
    required this.ticksPerFrame,
  }) : ticksPerQuarterNote = null;

  /// Ticks per quarter note, or null for SMPTE-divided files.
  final int? ticksPerQuarterNote;

  /// Frames per second, or null for metric division.
  final int? framesPerSecond;

  final int? ticksPerFrame;

  bool get isSmpte => ticksPerQuarterNote == null;

  /// Ticks per quarter note, resolving SMPTE division against a tempo.
  ///
  /// A few files record their division in SMPTE frames, which leaves "a quarter
  /// note" undefined until a tempo is known. Assuming the spec default of 120bpm
  /// lets measure maths still work: at 120bpm a quarter note is half a second, so
  /// one tick is `ticksPerFrame * framesPerSecond / 2` of one.
  int resolveTicksPerQuarterNote() {
    final metric = ticksPerQuarterNote;
    if (metric != null) return metric > 0 ? metric : 480;
    final fps = framesPerSecond ?? 25;
    final perFrame = ticksPerFrame ?? 80;
    final resolved = perFrame * fps ~/ 2;
    return resolved > 0 ? resolved : 480;
  }
}

/// A single decoded event, positioned by absolute tick.
///
/// Events keep the order they appeared in, including events that mean nothing to
/// playback, because dropping them here would make the parser lossy in a way that
/// is hard to debug later.
sealed class SmfEvent {
  const SmfEvent({required this.tick});

  /// Absolute tick within the track, after adding this event's delta time.
  final int tick;
}

/// A channel voice message: something that sounds.
sealed class SmfChannelEvent extends SmfEvent {
  const SmfChannelEvent({required super.tick, required this.channel});

  /// MIDI channel 0-15.
  final int channel;
}

class SmfNoteOn extends SmfChannelEvent {
  const SmfNoteOn({
    required super.tick,
    required super.channel,
    required this.note,
    required this.velocity,
  });

  final int note;
  final int velocity;

  /// A note-on with zero velocity is a note-off spelled with 0x90.
  ///
  /// Files use this because running status makes it one byte shorter than a real
  /// note-off, and a great many of them rely on it. Treating it as a note-on
  /// leaves notes hanging until the end of the track.
  bool get isNoteOff => velocity == 0;
}

class SmfNoteOff extends SmfChannelEvent {
  const SmfNoteOff({
    required super.tick,
    required super.channel,
    required this.note,
    required this.velocity,
  });

  final int note;
  final int velocity;
}

class SmfProgramChange extends SmfChannelEvent {
  const SmfProgramChange({
    required super.tick,
    required super.channel,
    required this.program,
  });

  final int program;
}

class SmfControlChange extends SmfChannelEvent {
  const SmfControlChange({
    required super.tick,
    required super.channel,
    required this.controller,
    required this.value,
  });

  final int controller;
  final int value;
}

class SmfPitchBend extends SmfChannelEvent {
  const SmfPitchBend({
    required super.tick,
    required super.channel,
    required this.value,
  });

  /// 14-bit value, 8192 being centre.
  final int value;
}

class SmfChannelPressure extends SmfChannelEvent {
  const SmfChannelPressure({
    required super.tick,
    required super.channel,
    required this.value,
  });

  final int value;
}

class SmfNotePressure extends SmfChannelEvent {
  const SmfNotePressure({
    required super.tick,
    required super.channel,
    required this.note,
    required this.value,
  });

  final int note;
  final int value;
}

/// A meta event: information about the music rather than notes.
sealed class SmfMetaEvent extends SmfEvent {
  const SmfMetaEvent({required super.tick, required this.metaType});

  /// The meta event type byte from the file, 0x51 for tempo and so on.
  final int metaType;
}

/// Tempo, stored as microseconds per quarter note.
class SmfSetTempo extends SmfMetaEvent {
  const SmfSetTempo({
    required super.tick,
    required this.microsecondsPerBeat,
  }) : super(metaType: 0x51);

  final int microsecondsPerBeat;
}

class SmfTimeSignature extends SmfMetaEvent {
  const SmfTimeSignature({
    required super.tick,
    required this.numerator,
    required this.denominatorExponent,
    required this.clocksPerClick,
    required this.notated32ndsPerQuarter,
  }) : super(metaType: 0x58);

  final int numerator;

  /// The file stores the denominator as a power of two, so 2 means 4/4.
  ///
  /// Kept as the raw exponent because that is what the file contains; converting
  /// early loses the ability to tell "4" from an author who wrote 2^4 by mistake.
  final int denominatorExponent;

  final int clocksPerClick;
  final int notated32ndsPerQuarter;

  /// The denominator as a number: 2 -> 4, 3 -> 8.
  int get denominator => 1 << denominatorExponent;
}

class SmfKeySignature extends SmfMetaEvent {
  const SmfKeySignature({
    required super.tick,
    required this.sharps,
    required this.isMinor,
  }) : super(metaType: 0x59);

  /// Signed: negative is a flat key.
  final int sharps;
  final bool isMinor;
}

/// A named point in the piece, which is how most files mark rehearsal letters
/// and section starts.
class SmfMarker extends SmfMetaEvent {
  const SmfMarker({required super.tick, required this.text}) : super(metaType: 0x06);

  final String text;
}

/// A cue point, the other of the two "here is a landmark" events.
class SmfCuePoint extends SmfMetaEvent {
  const SmfCuePoint({required super.tick, required this.text})
    : super(metaType: 0x07);

  final String text;
}

class SmfTrackName extends SmfMetaEvent {
  const SmfTrackName({required super.tick, required this.text})
    : super(metaType: 0x03);

  final String text;
}

class SmfInstrumentName extends SmfMetaEvent {
  const SmfInstrumentName({required super.tick, required this.text})
    : super(metaType: 0x04);

  final String text;
}

class SmfLyrics extends SmfMetaEvent {
  const SmfLyrics({required super.tick, required this.text})
    : super(metaType: 0x05);

  final String text;
}

class SmfCopyrightNotice extends SmfMetaEvent {
  const SmfCopyrightNotice({required super.tick, required this.text})
    : super(metaType: 0x02);

  final String text;
}

class SmfEndOfTrack extends SmfMetaEvent {
  const SmfEndOfTrack({required super.tick}) : super(metaType: 0x2F);
}

/// A meta event Fermata has no specific meaning for, kept rather than discarded.
class SmfUnknownMeta extends SmfMetaEvent {
  const SmfUnknownMeta({
    required super.tick,
    required int metaTypeValue,
    required this.data,
  }) : super(metaType: metaTypeValue);

  final Uint8ListBytes data;
}

/// A system-exclusive event.
class SmfSysEx extends SmfEvent {
  const SmfSysEx({required super.tick, required this.data});

  final Uint8ListBytes data;
}

/// Parses Standard MIDI File bytes.
///
/// Every quirk of the format is handled here so that nothing above this layer
/// needs to know about running status, variable-length quantities, or the several
/// ways a file can spell "stop playing this note".
class SmfParser {
  const SmfParser();

  /// Reads [bytes] as a Standard MIDI File.
  ///
  /// Throws [MidiFormatException] for anything that is not a well-formed file,
  /// including a truncated one. Partial credit is not offered: a score that
  /// silently omits half its notes would be worse than one that refuses to open.
  SmfFile parse(List<int> bytes) {
    final cursor = ByteCursor(bytes);
    return parseWith(cursor);
  }

  /// Reads a file from an existing cursor, used to parse a sub-buffer.
  SmfFile parseWith(ByteCursor cursor) {
    final magic = _readChunkId(cursor);
    if (magic != 'MThd') {
      throw MidiFormatException(
        'Not a MIDI file: expected a "MThd" header but found "$magic".',
        0,
      );
    }

    final headerLength = cursor.readUint32();
    if (headerLength < 6) {
      throw MidiFormatException(
        'The MIDI header is too short to describe a file.',
        cursor.absolutePosition - 4,
      );
    }
    // A few files pad the header beyond the six defined bytes.
    final headerEnd = cursor.position + headerLength;

    final formatValue = cursor.readUint16();
    final format = SmfFormat.fromValue(formatValue);
    if (format == null) {
      throw MidiFormatException(
        'Unknown MIDI format $formatValue; expected 0, 1 or 2.',
        cursor.absolutePosition - 2,
      );
    }

    final declaredTracks = cursor.readUint16();
    final divisionWord = cursor.readUint16();
    final division = divisionWord & 0x8000 != 0
        ? SmfDivision.smpte(
            // The high byte holds the frame rate as a negative SMPTE code.
            framesPerSecond: 256 - (divisionWord >> 8),
            ticksPerFrame: divisionWord & 0xFF,
          )
        : SmfDivision.ticksPerQuarterNote(divisionWord);

    // Skip anything between the defined header fields and the declared end.
    final padding = headerEnd - cursor.position;
    if (padding > 0) cursor.skip(padding);

    final tracks = <SmfTrack>[];
    for (var i = 0; i < declaredTracks; i++) {
      // A header promising tracks the file does not contain means a truncated or
      // damaged file. Stopping early would quietly return a score missing music,
      // which is worse than refusing to open it.
      if (cursor.isAtEnd) {
        throw MidiFormatException(
          'The header declares $declaredTracks track'
          '${declaredTracks == 1 ? '' : 's'} but only ${tracks.length} could be read.',
          cursor.absolutePosition,
        );
      }
      tracks.add(_parseTrack(cursor));
    }

    return SmfFile(
      format: format,
      division: division,
      tracks: List<SmfTrack>.unmodifiable(tracks),
    );
  }

  SmfTrack _parseTrack(ByteCursor cursor) {
    final magic = _readChunkId(cursor);
    if (magic != 'MTrk') {
      throw MidiFormatException(
        'Expected a "MTrk" track chunk but found "$magic".',
        cursor.absolutePosition - 4,
      );
    }

    final length = cursor.readUint32();
    if (length < 0 || length > cursor.remaining) {
      throw MidiFormatException(
        'A track claims to be $length bytes but only ${cursor.remaining} remain.',
        cursor.absolutePosition - 4,
      );
    }

    final trackBytes = cursor.readBytes(length);
    return SmfTrack(
      events: _parseTrackEvents(ByteCursor.sublist(
        trackBytes.toList(),
        0,
        length,
      )),
    );
  }

  /// Decodes one track's events.
  ///
  /// [ByteCursor.sublist] is given a fresh copy here because the sub-cursor needs
  /// to be independently bounded; the track's own length has already been
  /// validated, so the copy cannot fail.
  List<SmfEvent> _parseTrackEvents(ByteCursor cursor) {
    final events = <SmfEvent>[];
    var tick = 0;

    // Running status: when a data byte appears where a status byte should, the
    // previous status is reused. Reset by any real status byte, including meta
    // and sysex, per the spec.
    var runningStatus = -1;

    while (!cursor.isAtEnd) {
      final delta = cursor.readVariableLength();
      tick += delta;

      final byte = cursor.readByte();

      if (byte < 0x80) {
        // A data byte means the previous status applies, and this byte is its
        // first data byte. The rest of that event's data still has to be read,
        // or the next byte would be mistaken for a status byte and the stream
        // would desynchronise from here on.
        if (runningStatus < 0) {
          throw MidiFormatException(
            'A data byte appeared with no running status to apply it to.',
            cursor.absolutePosition - 1,
          );
        }
        final status = runningStatus;
        final high = status & 0xF0;
        final count = high == 0xC0 || high == 0xD0 ? 1 : 2;
        final data = <int>[byte];
        for (var i = 1; i < count; i++) {
          data.add(cursor.readInt7());
        }
        events.add(_decodeChannelEvent(cursor, tick, status, data));
        continue;
      }

      if (byte < 0xF0) {
        runningStatus = byte;
        events.add(
          _decodeChannelEvent(cursor, tick, byte, _readData(cursor, byte)),
        );
        continue;
      }

      if (byte == 0xFF) {
        // A meta event always clears running status.
        runningStatus = -1;
        events.add(_decodeMetaEvent(cursor, tick));
        continue;
      }

      if (byte == 0xF0 || byte == 0xF7) {
        runningStatus = -1;
        final length = cursor.readVariableLength();
        events.add(SmfSysEx(tick: tick, data: cursor.readBytes(length)));
        continue;
      }

      // 0xF1 to 0xF6 are system common messages, which a Standard MIDI File does
      // not use. Skipping them keeps a real-time-interleaved file readable rather
      // than throwing it away.
      runningStatus = -1;
      events.add(
        SmfSysEx(tick: tick, data: Uint8ListBytes(const <int>[], 0, 0)),
      );
    }

    return List<SmfEvent>.unmodifiable(events);
  }

  /// Reads the data bytes for a channel status byte, whose count depends on it.
  List<int> _readData(ByteCursor cursor, int status) {
    final high = status & 0xF0;
    // Program change and channel pressure carry a single data byte; everything
    // else carries two.
    final count = high == 0xC0 || high == 0xD0 ? 1 : 2;
    final out = <int>[];
    for (var i = 0; i < count; i++) {
      out.add(cursor.readInt7());
    }
    return out;
  }

  SmfChannelEvent _decodeChannelEvent(
    ByteCursor cursor,
    int tick,
    int status,
    List<int> data,
  ) {
    final channel = status & 0x0F;
    switch (status & 0xF0) {
      case 0x80:
        return SmfNoteOff(
          tick: tick,
          channel: channel,
          note: data[0],
          velocity: data.length > 1 ? data[1] : 0,
        );
      case 0x90:
        return SmfNoteOn(
          tick: tick,
          channel: channel,
          note: data[0],
          velocity: data.length > 1 ? data[1] : 0,
        );
      case 0xA0:
        return SmfNotePressure(
          tick: tick,
          channel: channel,
          note: data[0],
          value: data.length > 1 ? data[1] : 0,
        );
      case 0xB0:
        return SmfControlChange(
          tick: tick,
          channel: channel,
          controller: data[0],
          value: data.length > 1 ? data[1] : 0,
        );
      case 0xC0:
        return SmfProgramChange(
          tick: tick,
          channel: channel,
          program: data[0],
        );
      case 0xD0:
        return SmfChannelPressure(tick: tick, channel: channel, value: data[0]);
      case 0xE0:
        final lsb = data.isNotEmpty ? data[0] : 0;
        final msb = data.length > 1 ? data[1] : 0;
        return SmfPitchBend(
          tick: tick,
          channel: channel,
          // 14-bit, centre 8192, matching the spec's convention.
          value: (msb << 7) | lsb,
        );
      default:
        throw MidiFormatException(
          'Unknown channel status byte 0x${status.toRadixString(16)}.',
          cursor.absolutePosition,
        );
    }
  }

  SmfMetaEvent _decodeMetaEvent(ByteCursor cursor, int tick) {
    final type = cursor.readByte();
    final length = cursor.readVariableLength();
    final payload = cursor.readBytes(length);

    switch (type) {
      case 0x51:
        if (length != 3) {
          throw MidiFormatException(
            'A tempo event must be 3 bytes, not $length.',
            cursor.absolutePosition,
          );
        }
        return SmfSetTempo(
          tick: tick,
          microsecondsPerBeat: (payload[0] << 16) | (payload[1] << 8) | payload[2],
        );
      case 0x58:
        if (length != 4) {
          throw MidiFormatException(
            'A time signature event must be 4 bytes, not $length.',
            cursor.absolutePosition,
          );
        }
        return SmfTimeSignature(
          tick: tick,
          numerator: payload[0],
          denominatorExponent: payload[1],
          clocksPerClick: payload[2],
          notated32ndsPerQuarter: payload[3],
        );
      case 0x59:
        return SmfKeySignature(
          tick: tick,
          sharps: payload.isEmpty ? 0 : _signed(payload[0]),
          isMinor: payload.length > 1 && payload[1] == 1,
        );
      case 0x01:
        return SmfText(tick: tick, text: payload.toLatin1String());
      case 0x02:
        return SmfCopyrightNotice(
          tick: tick,
          text: payload.toLatin1String(),
        );
      case 0x03:
        return SmfTrackName(tick: tick, text: payload.toLatin1String());
      case 0x04:
        return SmfInstrumentName(
          tick: tick,
          text: payload.toLatin1String(),
        );
      case 0x05:
        return SmfLyrics(tick: tick, text: payload.toLatin1String());
      case 0x06:
        return SmfMarker(tick: tick, text: payload.toLatin1String());
      case 0x07:
        return SmfCuePoint(tick: tick, text: payload.toLatin1String());
      case 0x2F:
        return SmfEndOfTrack(tick: tick);
      default:
        return SmfUnknownMeta(
          tick: tick,
          metaTypeValue: type,
          data: payload,
        );
    }
  }

  static int _signed(int byte) => byte > 0x7F ? byte - 0x100 : byte;

  /// Reads a four-character chunk identifier.
  static String _readChunkId(ByteCursor cursor) {
    if (cursor.remaining < 4) {
      throw MidiFormatException(
        'The file ends before a chunk identifier could be read.',
        cursor.absolutePosition,
      );
    }
    return String.fromCharCodes(<int>[
      cursor.readByte(),
      cursor.readByte(),
      cursor.readByte(),
      cursor.readByte(),
    ]);
  }
}

/// Free-form text, used for event 0x01 which Fermata does not interpret.
class SmfText extends SmfMetaEvent {
  const SmfText({required super.tick, required this.text}) : super(metaType: 0x01);

  final String text;
}

/// One parsed track.
class SmfTrack {
  const SmfTrack({required this.events});

  final List<SmfEvent> events;

  /// The track's name, if it declares one.
  String? get name {
    for (final event in events) {
      if (event is SmfTrackName) return event.text;
    }
    return null;
  }
}

/// A parsed file.
class SmfFile {
  const SmfFile({
    required this.format,
    required this.division,
    required this.tracks,
  });

  final SmfFormat format;
  final SmfDivision division;
  final List<SmfTrack> tracks;

  /// The last tick carrying any event, across all tracks.
  int get endTick {
    var furthest = 0;
    for (final track in tracks) {
      for (final event in track.events) {
        if (event.tick > furthest) furthest = event.tick;
      }
    }
    return furthest;
  }

  /// Every event across every track, in track order.
  ///
  /// Track order rather than tick order: a MIDI file's tracks are independent
  /// streams, and interleaving them by tick would invent an ordering the file
  /// does not have.
  List<SmfEvent> get allEvents => <SmfEvent>[
    for (final track in tracks) ...track.events,
  ];
}