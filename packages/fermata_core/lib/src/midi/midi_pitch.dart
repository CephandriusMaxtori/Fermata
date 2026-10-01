/// Pitch helpers shared by the piano visualizer and the practice tools.
///
/// Fermata receives raw MIDI note numbers (0-127) from a parsed file and needs
/// to answer practical questions about them: which octave is this, is it a
/// black key, what should the user-facing label say. Those are spelled out
/// here rather than at each call site so the visualizer, the falling-notes
/// lane and any future metronome calibration agree.
///
/// The arithmetic is deliberately hand-rolled. A MIDI note number is defined as
/// 12 per octave from C, and that definition is part of the file format rather
/// than something to look up in a table of names.
library;

import 'dart:math' as math;

/// One semitone of the chromatic scale.
class Semitone {
  const Semitone._(this.index, this.name, this.isBlackKey);

  /// 0 is C, 1 is C#, 11 is B.
  final int index;

  /// Scientific pitch notation without an octave, e.g. `F#`.
  final String name;

  /// Black keys sit higher and narrower, which is why the visualizer needs this
  /// to lay out a keyboard correctly.
  final bool isBlackKey;

  static const int _count = 12;

  static const List<Semitone> _all = <Semitone>[
    Semitone._(0, 'C', false),
    Semitone._(1, 'C#', true),
    Semitone._(2, 'D', false),
    Semitone._(3, 'D#', true),
    Semitone._(4, 'E', false),
    Semitone._(5, 'F', false),
    Semitone._(6, 'F#', true),
    Semitone._(7, 'G', false),
    Semitone._(8, 'G#', true),
    Semitone._(9, 'A', false),
    Semitone._(10, 'A#', true),
    Semitone._(11, 'B', false),
  ];

  /// The semitone [index] steps above C. Indices wrap, as they must musically.
  static Semitone at(int index) => _all[index % _count];

  /// Whether a raw MIDI note number falls on a black key.
  static bool isBlackKeyAt(int noteNumber) =>
      _all[noteNumber % _count].isBlackKey;

  /// The semitone for a MIDI note number.
  static Semitone ofNote(int noteNumber) => at(noteNumber);

  /// All twelve semitones, C first.
  static List<Semitone> get values => List<Semitone>.unmodifiable(_all);

  /// Enharmonic alternatives, e.g. G# is also Ab.
  ///
  /// A black key always has exactly one natural partner. Flat and sharp
  /// spellings are both conventional, and which one a musician expects depends
  /// on the key signature rather than on the file, so this returns the natural
  /// name and lets the caller decide how to spell it.
  Semitone get naturalAlternative => switch (index) {
    1 => _all[0], // C#
    3 => _all[2], // D#
    6 => _all[5], // F#
    8 => _all[7], // G#
    10 => _all[9], // A#
    _ => this,
  };
}

/// Facts about a MIDI note number, 0-127.
class MidiPitch {
  const MidiPitch._(this.noteNumber);

  final int noteNumber;

  /// Middle C in scientific pitch notation.
  static const int middleC = 60;

  /// A4 = 440 Hz, the reference the MIDI spec uses for tuning.
  static const int concertA = 69;

  factory MidiPitch(int noteNumber) {
    if (noteNumber < 0 || noteNumber > 127) {
      throw RangeError.range(noteNumber, 0, 127, 'noteNumber');
    }
    return MidiPitch._(noteNumber);
  }

  /// The raw note number, 0-127.
  int get number => noteNumber;

  Semitone get semitone => Semitone.ofNote(noteNumber);

  /// The octave number. MIDI octave 4 starts at note 60.
  int get octave => (noteNumber ~/ 12) - 1;

  /// Scientific pitch notation, e.g. `A4`, `F#3`.
  String get label => '${semitone.name}$octave';

  bool get isBlackKey => semitone.isBlackKey;

  bool get isMiddleC => noteNumber == middleC;

  /// Equal-tempered frequency in Hz, assuming A4 = 440.
  ///
  /// This is a display and tuning aid, not a measurement: real instruments
  /// drift, and a stretched or just-intoned keyboard will not match it. The
  /// visualizer uses it to place a falling note at a height that looks right.
  double get frequency => 440.0 * math.pow(2.0, (noteNumber - concertA) / 12.0);

  /// The note one octave below, or null at the bottom of the MIDI range.
  MidiPitch? get octaveDown =>
      noteNumber < 12 ? null : MidiPitch(noteNumber - 12);

  /// The note one octave above, or null at the top of the MIDI range.
  MidiPitch? get octaveUp =>
      noteNumber > 115 ? null : MidiPitch(noteNumber + 12);

  /// Whether this note lies within the inclusive range, used to window the
  /// on-screen keyboard to the part of the instrument a piece actually uses.
  bool isInRange(int lowest, int highest) =>
      noteNumber >= lowest && noteNumber <= highest;

  /// The lowest and highest note that sounds in [notes].
  ///
  /// Returns null for an empty collection, which is different from a range of
  /// zero: a piece with no notes has no range, it does not have a silent one.
  static ({int lowest, int highest})? rangeOf(Iterable<int> notes) {
    var lowest = 128;
    var highest = -1;
    var any = false;
    for (final note in notes) {
      if (!any) {
        lowest = note;
        highest = note;
        any = true;
        continue;
      }
      if (note < lowest) lowest = note;
      if (note > highest) highest = note;
    }
    return any ? (lowest: lowest, highest: highest) : null;
  }

  /// Widens a range to whole octaves so the keyboard is not clipped mid-key.
  ///
  /// A range that starts on D looks wrong on a keyboard whose leftmost key is a
  /// partial C. Snapping outward to C keeps the layout honest at both edges.
  static ({int lowest, int highest})? snapToOctaves(
    Iterable<int> notes,
  ) {
    final range = rangeOf(notes);
    if (range == null) return null;
    return (lowest: _snapDown(range.lowest), highest: _snapUp(range.highest));
  }

  /// Moves a note number down to the nearest natural key.
  static int _snapDown(int noteNumber) =>
      Semitone.isBlackKeyAt(noteNumber) ? noteNumber - 1 : noteNumber;

  /// Moves a note number up to the nearest natural key.
  static int _snapUp(int noteNumber) =>
      Semitone.isBlackKeyAt(noteNumber) ? noteNumber + 1 : noteNumber;

  }