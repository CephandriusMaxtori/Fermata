import '../geometry/normalized_rect.dart';

/// A run of text extracted from a PDF page, with its box in page-relative
/// coordinates.
///
/// Deliberately not a `PdfRect` or a `Rect`: the extractor is the only thing
/// that should know about PDF's bottom-left origin, and it converts once on the
/// way in. Everything downstream — grouping runs into staff systems, finding
/// bars, scrolling the viewer — is then plain geometry.
class TextRun {
  const TextRun({required this.text, required this.bounds});

  final String text;
  final NormalizedRect bounds;

  double get centerY => bounds.centerY;
  double get centerX => bounds.centerX;

  bool get isBlank => text.trim().isEmpty;

  @override
  String toString() => 'TextRun(${text.length} chars, $bounds)';
}

/// One staff system: a horizontal band of the page holding a run of measures.
///
/// A "system" is engraving's word for one unbroken line of music. Every system
/// is bracketed by a barline, so the systems on a page are what give bar-by-bar
/// navigation its vertical structure.
class StaffSystem {
  const StaffSystem({
    required this.bounds,
    required this.barStarts,
  });

  /// Vertical extent of the system, including all of its runs.
  final NormalizedRect bounds;

  /// Left edge of each bar in the system, as a fraction of page width.
  ///
  /// Always starts with [bounds.left] and ends with [bounds.right]: the two
  /// barlines that close the system are real bar positions and a navigation step
  /// has to be able to land on the final one.
  final List<double> barStarts;

  int get barCount => barStarts.length;

  /// The `[start, end)` range of bar [index] in page-width fractions.
  ({double start, double end}) barRange(int index) {
    assert(index >= 0 && index < barCount, 'bar index $index out of range');
    return (
      start: barStarts[index],
      end: index + 1 < barCount ? barStarts[index + 1] : bounds.right,
    );
  }

  @override
  String toString() => 'StaffSystem($bounds, $barCount bars)';
}

/// Every bar on one page, in reading order.
///
/// This is the unit bar-by-bar navigation steps through. [bars] is flattened
/// across [systems] so a caller can say "next bar" without caring that page
/// breaks happen at system boundaries.
class BarLayout {
  const BarLayout({required this.systems, required this.hasStaff});

  /// Systems found on the page, top to bottom.
  final List<StaffSystem> systems;

  /// Whether anything staff-shaped was detected at all.
  ///
  /// A scanned score has no text layer, so extraction returns nothing. That is
  /// not an error — it means bar stepping should stay switched off and the
  /// viewer should fall back to page turning rather than pretend it knows where
  /// the bars are.
  final bool hasStaff;

  /// Total bars across all systems.
  int get barCount =>
      systems.fold(0, (total, system) => total + system.barCount);

  /// The bars of the system containing [y], or an empty list if none does.
  List<StaffSystem> systemsAt(double y) =>
      systems.where((s) => s.bounds.containsY(y)).toList();

  /// `const` so it can be a default parameter value in the app's test doubles.
  static const BarLayout empty =
      BarLayout(systems: <StaffSystem>[], hasStaff: false);
}