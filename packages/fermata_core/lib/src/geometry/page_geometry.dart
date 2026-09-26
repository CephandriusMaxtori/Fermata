import 'dart:math' as math;

/// The intrinsic size of one page of a score, in PDF points (72 dpi).
///
/// Fermata treats this as metadata only: it is used to preserve a page's
/// aspect ratio and to convert between the PDF point space that stamps and
/// text notes are authored in and the normalized space that ink is stored in.
/// Rendering never depends on it.
class PageGeometry {
  const PageGeometry({required this.widthPt, required this.heightPt});

  final double widthPt;
  final double heightPt;

  bool get isValid => widthPt > 0 && heightPt > 0;

  double get aspectRatio => isValid ? widthPt / heightPt : 1.0;

  /// The render box for this page fitted inside [available] while preserving
  /// the page's aspect ratio.
  ///
  /// Returns a zero-sized box when the page geometry is unknown, which callers
  /// should treat as "not ready to lay out" rather than "render at zero".
  ({double width, double height}) fitWithin({
    required double availableWidth,
    required double availableHeight,
  }) {
    if (!isValid || availableWidth <= 0 || availableHeight <= 0) {
      return (width: 0, height: 0);
    }
    final scale = math.min(
      availableWidth / widthPt,
      availableHeight / heightPt,
    );
    return (width: widthPt * scale, height: heightPt * scale);
  }

  @override
  bool operator ==(Object other) =>
      other is PageGeometry &&
      other.widthPt == widthPt &&
      other.heightPt == heightPt;

  @override
  int get hashCode => Object.hash(widthPt, heightPt);

  @override
  String toString() => 'PageGeometry(${widthPt}pt x ${heightPt}pt)';
}
