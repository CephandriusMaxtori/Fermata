import 'dart:math' as math;

import '../geometry/normalized_rect.dart';
import 'bar_layout.dart';

/// Finds staff systems and bar positions from the text layer of a score page.
///
/// ## What this can and cannot see
///
/// Barlines are *strokes*, not characters. `PdfPage.loadText` returns glyph
/// bounding boxes, so a barline is visible here only as the absence of glyphs
/// where one is expected. Everything below is therefore gap analysis on glyph
/// positions, which is genuinely a heuristic and has real failure modes:
///
///  * A score exported as **vector art or a scan has no text layer at all.**.
///    [BarDetector.detect] returns [BarLayout.empty] and the caller is expected
///    to fall back to page turning. That is the common case for printed music,
///    so this path is a bonus, not the foundation.
///  * **Lyrics and chord symbols** are text on the page but are not staff. They
///    are excluded by requiring a system to be tall enough to hold several
///    stacked staff lines, which a line of lyrics never is.
///  * **Dense runs of semiquavers** can close up a measure's interior so its
///    trailing gap is no longer the widest on the system. The threshold is
///    relative to the system's own gap distribution, which keeps it working on
///    clean engraving, but a hand-typeset score can defeat it.
///
/// The alternative — reading the page's vector drawing operators to find the
/// actual barline strokes — is exact, and pdfrx does not expose it. If that ever
/// becomes available it should replace this file wholesale rather than being
/// merged in; see `Todo.md`.
abstract final class BarDetector {
  /// Groups [runs] into staff systems and splits each into bars.
  ///
  /// Returns [BarLayout.empty] when the runs do not look like staff, so callers
  /// can treat "no bars" as a normal outcome rather than a failure.
  static BarLayout detect(List<TextRun> runs) {
    if (runs.isEmpty) return BarLayout.empty;

    final usable = runs
        .where((r) => !r.isBlank && !r.bounds.isEmpty)
        .toList(growable: false);
    if (usable.isEmpty) return BarLayout.empty;

    // Blanks are dropped because a space glyph has a real bounding box and would
    // otherwise show up as a barline-sized hole in the middle of a measure.
    final systems = _groupIntoSystems(usable);
    if (systems.isEmpty) return BarLayout.empty;

    return BarLayout(systems: systems, hasStaff: true);
  }

  /// Groups runs into horizontal bands, then discards bands that cannot be
  /// staff.
  ///
  /// Sorting by vertical centre first is what makes this a single sweep: bands
  /// are contiguous runs of the sorted list, so a run can only join the band
  /// immediately above it and no backtracking is needed.
  static List<StaffSystem> _groupIntoSystems(List<TextRun> runs) {
    final sorted = [...runs]..sort((a, b) => a.centerY.compareTo(b.centerY));

    // Step 1: Group into individual staves (tight vertical clustering)
    final staves = <List<TextRun>>[];
    for (final run in sorted) {
      if (staves.isEmpty || !_staffJoins(staves.last, run)) {
        staves.add([run]);
      } else {
        staves.last.add(run);
      }
    }

    // Step 2: Group adjacent staves belonging to the same multi-staff system (e.g. grand staff)
    final systemBands = <List<List<TextRun>>>[];
    for (final staff in staves) {
      if (systemBands.isEmpty || !_systemJoins(systemBands.last, staff)) {
        systemBands.add([staff]);
      } else {
        systemBands.last.add(staff);
      }
    }

    final systems = <StaffSystem>[];
    for (final systemBand in systemBands) {
      final system = _buildSystem(systemBand);
      if (system != null) systems.add(system);
    }
    return systems;
  }

  static bool _staffJoins(List<TextRun> staff, TextRun run) {
    final staffBounds = _boundsOf(staff);
    final shorter = math.min(run.bounds.height, staffBounds.height);
    if (shorter <= 0) return false;
    final overlap = math.min(run.bounds.bottom, staffBounds.bottom) -
        math.max(run.bounds.top, staffBounds.top);
    if (overlap <= 0) {
      final gap = run.bounds.top > staffBounds.bottom
          ? run.bounds.top - staffBounds.bottom
          : staffBounds.top - run.bounds.bottom;
      return gap < 0.005;
    }
    return overlap / shorter >= _kVerticalOverlap;
  }

  static bool _systemJoins(List<List<TextRun>> systemBand, List<TextRun> staff) {
    final systemBounds = _boundsOf(systemBand.expand((s) => s).toList());
    final staffBounds = _boundsOf(staff);
    final verticalGap = staffBounds.top - systemBounds.bottom;
    if (verticalGap < 0.002 || verticalGap > 0.08) return false;

    final horizOverlap = math.min(staffBounds.right, systemBounds.right) -
        math.max(staffBounds.left, systemBounds.left);
    return horizOverlap > 0.1;
  }

  /// Builds a system from [systemBand], or null if the band is not staff-shaped.
  static StaffSystem? _buildSystem(List<List<TextRun>> systemBand) {
    final allRuns = systemBand.expand((s) => s).toList();
    if (allRuns.length < _kMinRunsPerSystem) return null;

    final bounds = _boundsOf(allRuns);
    // A staff is at least a few staff-spaces tall. Lyrics sit on a single line
    // and are well under this, which is what keeps sung text out of the layout.
    if (bounds.height < _kMinSystemHeight) return null;

    // A title spans the page but is one line; a system spans the page *and* is
    // tall. Requiring real horizontal density rejects both headings and page
    // numbers without needing to recognise the characters.
    final runsPerUnitWidth = allRuns.length / math.max(bounds.width, 1e-6);
    if (runsPerUnitWidth < _kMinRunsPerWidth) return null;

    // Pick the primary staff (the sub-band with the most runs) to find bars
    final primaryStaff = systemBand.reduce((a, b) => a.length >= b.length ? a : b);

    return StaffSystem(bounds: bounds, barStarts: _findBars(primaryStaff, bounds));
  }

  static List<List<TextRun>> _subdivideIntoStaves(List<TextRun> band) {
    if (band.isEmpty) return [];
    final sorted = [...band]..sort((a, b) => a.centerY.compareTo(b.centerY));

    final staves = <List<TextRun>>[];
    var currentStaff = <TextRun>[sorted.first];

    for (var i = 1; i < sorted.length; i++) {
      final run = sorted[i];
      final prev = sorted[i - 1];
      final verticalGap = run.bounds.top - prev.bounds.bottom;
      if (verticalGap > 0.015) {
        staves.add(currentStaff);
        currentStaff = [run];
      } else {
        currentStaff.add(run);
      }
    }
    staves.add(currentStaff);
    return staves;
  }

  /// Left edge of every bar in [band].
  ///
  /// Works by merging glyphs into x-intervals and treating the gaps between them
  /// as barlines. A gap only counts as a barline when it is wide relative to the
  /// *other* gaps on the same system, which is what lets a dense measure and a
  /// sparse one coexist on one line.
  static List<double> _findBars(List<TextRun> band, NormalizedRect bounds) {
    final intervals = band
        .map((r) => (r.bounds.left, r.bounds.right))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    final merged = <({double start, double end})>[];
    for (final (start, end) in intervals) {
      if (end <= start) continue;
      if (merged.isNotEmpty && start <= merged.last.end + _kGlyphOverlap) {
        // Overlapping or touching glyph: extend the current run of ink.
        if (end > merged.last.end) {
          merged[merged.length - 1] = (start: merged.last.start, end: end);
        }
        continue;
      }
      merged.add((start: start, end: end));
    }

    if (merged.length < 2) return [bounds.left];

    final gaps = <double>[];
    for (var i = 1; i < merged.length; i++) {
      gaps.add(merged[i].start - merged[i - 1].end);
    }

    final positive = gaps.where((g) => g > 0).toList()..sort();
    if (positive.isEmpty) return [bounds.left];

    // Median rather than mean: one wide gap (a double bar, a key change) must
    // not drag the threshold up and hide the ordinary barlines.
    final median = positive[positive.length ~/ 2];
    final threshold = math.max(
      _kMinBarGap * bounds.width,
      median * _kBarGapFactor,
    );

    // A bar starts at the ink that precedes it, so a barline lands just after the
    // last notehead of the measure it closes. That is where a barline is
    // engraved, and it keeps the bar spanning the gap rather than starting
    // halfway across it.
    //
    // [bounds.right] is deliberately *not* appended: `StaffSystem.barRange`
    // already runs the final bar out to the system edge, so adding it here would
    // manufacture a zero-width trailing bar.
    final bars = <double>[bounds.left];
    for (var i = 1; i < merged.length; i++) {
      final gap = merged[i].start - merged[i - 1].end;
      if (gap >= threshold) bars.add(merged[i - 1].end);
    }

    return bars;
  }

  static NormalizedRect _boundsOf(List<TextRun> runs) {
    var result = runs.first.bounds;
    for (final run in runs.skip(1)) {
      result = result.expandedToInclude(run.bounds);
    }
    return result;
  }

  /// Fraction of the shorter box that must overlap vertically for a run to join a
  /// band. Low, because one system can span several staves.
  static const _kVerticalOverlap = 0.5;

  /// Glyphs this close are treated as one run of ink.
  static const _kGlyphOverlap = 0.0005;

  /// A system narrower than this (page-width fraction) has no barlines in it.
  static const _kMinBarGap = 0.004;

  /// Barline threshold, as a multiple of the system's median glyph gap.
  static const _kBarGapFactor = 2.5;

  static const _kMinRunsPerSystem = 6;

  /// A staff this tall (page-height fraction) is at least a few staff spaces.
  static const _kMinSystemHeight = 0.02;

  static const _kMinRunsPerWidth = 12;
}