/// A bounds-checked reader over MIDI file bytes.
///
/// Every read is checked, because the input is a file the user picked from
/// their device and may well be truncated, hand-edited, or not a MIDI file at
/// all. A parser that reads past the end of the buffer on bad input crashes with
/// an opaque `RangeError`; this throws [MidiFormatException] with the byte offset
/// so the failure can be reported usefully.
library;

/// Raised when bytes cannot be read as a Standard MIDI File.
class MidiFormatException implements Exception {
  const MidiFormatException(this.message, [this.offset]);

  final String message;

  /// Byte offset the failure was detected at, when known.
  final int? offset;

  @override
  String toString() {
    final where = offset == null ? '' : ' at byte $offset';
    return 'MidiFormatException: $message$where';
  }
}

/// Sequential big-endian reader over a byte buffer.
class ByteCursor {
  ByteCursor(this._bytes) : _start = 0, _end = _bytes.length;

  /// Reads from a slice of a larger buffer, used for track data.
  ByteCursor.sublist(this._bytes, int start, int end)
    : _start = start,
      _end = end;

  final List<int> _bytes;
  final int _start;
  final int _end;

  int _position = 0;

  /// Current offset within this cursor's own range.
  int get position => _position;

  /// Offset within the original buffer, for error messages.
  int get absolutePosition => _start + _position;

  int get remaining => _end - _start - _position;

  bool get isAtEnd => _position >= _end - _start;

  void _require(int count) {
    if (count < 0) {
      throw MidiFormatException(
        'Cannot read a negative number of bytes ($count).',
        absolutePosition,
      );
    }
    if (remaining < count) {
      throw MidiFormatException(
        'Unexpected end of file: needed $count more byte'
        '${count == 1 ? '' : 's'} but only $remaining remained.',
        absolutePosition,
      );
    }
  }

  int readByte() {
    _require(1);
    return _bytes[_start + _position++];
  }

  /// Reads an unsigned 7-bit value.
  int readInt7() {
    final byte = readByte();
    if (byte > 0x7F) {
      throw MidiFormatException(
        'Expected a 7-bit value but found 0x${byte.toRadixString(16)}.',
        absolutePosition - 1,
      );
    }
    return byte;
  }

  int readUint16() => (readByte() << 8) | readByte();

  int readUint24() => (readByte() << 16) | (readByte() << 8) | readByte();

  int readUint32() =>
      (readByte() << 24) | (readByte() << 16) | (readByte() << 8) | readByte();

  /// Reads a signed 8-bit two's-complement value.
  int readInt8() {
    final byte = readByte();
    return byte > 0x7F ? byte - 0x100 : byte;
  }

  /// Reads a MIDI variable-length quantity.
  ///
  /// Up to four bytes, seven bits of value each, with the high bit set on every
  /// byte except the last. This is how delta times and text lengths are encoded,
  /// and getting it wrong desynchronises the rest of the stream, so it is
  /// validated rather than trusted.
  int readVariableLength() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final byte = readByte();
      value = (value << 7) | (byte & 0x7F);
      if (byte & 0x80 == 0) return value;
    }
    throw MidiFormatException(
      'A variable-length value may be at most four bytes.',
      absolutePosition - 4,
    );
  }

  /// Reads [count] raw bytes.
  Uint8ListBytes readBytes(int count) {
    _require(count);
    final start = _start + _position;
    _position += count;
    return Uint8ListBytes(_bytes, start, count);
  }

  /// Skips [count] bytes.
  void skip(int count) {
    _require(count);
    _position += count;
  }
}

/// An immutable view over a slice of bytes, avoiding a copy.
///
/// Event payloads are held only until they are decoded, so copying them would be
/// wasted work on a file that is megabytes long.
class Uint8ListBytes {
  const Uint8ListBytes(this._bytes, this._start, this._length);

  final List<int> _bytes;
  final int _start;
  final int _length;

  int get length => _length;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  int operator [](int index) => _bytes[_start + index];

  /// A copy, safe to retain after the source buffer is gone.
  List<int> toList() => _bytes.sublist(_start, _start + _length);

  /// Decodes as Latin-1, which the spec uses for text meta events.
  ///
  /// Not UTF-8: the Standard MIDI File spec defines these strings as ASCII, and
  /// decoding as UTF-8 would mangle any byte above 0x7F rather than preserving
  /// it. Track names from older software routinely contain such bytes.
  String toLatin1String() => String.fromCharCodes(toList());
}