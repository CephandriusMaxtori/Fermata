/// An axis-aligned rectangle expressed as fractions of the page box.
///
/// Same reasoning as [NormalizedPoint]: a rect is stored relative to the page,
/// never in pixels or PDF points, so anything derived from it stays correct at
/// any zoom level, density or orientation. The web UI will read these same
/// values, which is the reason they live here rather than next to the PDF
/// plugin that produced them.
///
/// Note the vertical axis runs *downward* ([top] < [bottom]), matching
/// [NormalizedPoint] and Flutter's coordinate space. PDF text extraction uses a
/// bottom-left origin with [PdfRect.top] > [PdfRect.bottom], so every conversion
/// has to flip. Doing that flip in exactly one place is the whole reason this
/// type exists.
class NormalizedRect {
  /// [left]/[right] and [top]/[bottom] are asserted ordered because every
  /// downstream measurement (`height`, `overlapArea`, `_findBars`) assumes it.
  /// Use [NormalizedRect.fromPdfEdges] when the source may report them the other
  /// way round.
  const NormalizedRect(this.left, this.top, this.right, this.bottom)
    : assert(left <= right, 'left must not exceed right'),
      assert(top <= bottom, 'top must not exceed bottom');

  /// Bypasses the ordering asserts. Only [NormalizedRect.empty] uses this.
  const NormalizedRect._unchecked(this.left, this.top, this.right, this.bottom);

  /// A zero-area rect at the origin, usable in a const expression.
  ///
  /// [empty] below is a plain `final` because it is deliberately inverted
  /// (`left > right`) to make `isEmpty` true, which the constructor's asserts
  /// forbid.
  static const NormalizedRect zero = NormalizedRect(0, 0, 0, 0);

  /// Builds a rect from PDF page coordinates **as fractions of the page**.
  ///
  /// Not merely "the same rect with its edges ordered". Two things happen here,
  /// and doing only the first is a bug that still looks plausible:
  ///
  ///  1. The vertical axis is flipped. PDF's origin is bottom-left with y
  ///     increasing upward, so a box at y 0.90..0.95 is at the *top* of the page,
  ///     not 90% of the way down.
  ///  2. The vertical edges are ordered defensively. `PdfRect` asserts
  ///     `top >= bottom`, so through pdfrx this half is a no-op; it is here so
  ///     that a second source, or a patched engine, cannot produce a negative
  ///     height that would silently corrupt every measurement downstream.
  ///
  /// Flipping is why this is the only place in the app that touches a `PdfRect`.
  /// A box that is reordered but not flipped puts every bar on the wrong system
  /// of the page, and that reads as bad detection rather than a coordinate bug.
  ///
  /// Callers must divide points by the page size first — this type is fractions
  /// throughout, and scaling belongs to the one caller that knows the geometry.
  factory NormalizedRect.fromPdfEdges({
    required double left,
    required double right,
    required double top,
    required double bottom,
  }) {
    // In PDF space the smaller y is nearer the bottom of the page, so it becomes
    // the *larger* page fraction once flipped.
    final nearBottom = top < bottom ? top : bottom;
    final nearTop = top < bottom ? bottom : top;
    return NormalizedRect(left, 1 - nearTop, right, 1 - nearBottom);
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// An empty rect, used as the identity when folding boxes together.
  ///
  /// Inverted (`left > right`, `top < bottom`) so [isEmpty] holds. That is
  /// precisely what the public constructor's asserts forbid, so it goes through
  /// a private constructor that skips them. The inversion is not a loophole for
  /// callers: it is the one value whose [isEmpty] is load-bearing, and
  /// [expandedToInclude] is the only thing meant to consume it.
  static final NormalizedRect empty =
      NormalizedRect._unchecked(1, 1, 0, 0);

  double get width => right - left;
  double get height => bottom - top;

  bool get isEmpty => width <= 0 || height <= 0;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  /// Clamps all four edges into `[0, 1]`.
  NormalizedRect clamp() => NormalizedRect(
    left.clamp(0.0, 1.0),
    top.clamp(0.0, 1.0),
    right.clamp(0.0, 1.0),
    bottom.clamp(0.0, 1.0),
  );

  /// The smallest rect containing both [other] and this one.
  NormalizedRect expandedToInclude(NormalizedRect other) => NormalizedRect(
    left < other.left ? left : other.left,
    top < other.top ? top : other.top,
    right > other.right ? right : other.right,
    bottom > other.bottom ? bottom : other.bottom,
  );

  /// Fraction of this rect's area that [other] covers, in `[0, 1]`.
  double overlapArea(NormalizedRect other) {
    final x = (right < other.right ? right : other.right) -
        (left > other.left ? left : other.left);
    final y = (bottom < other.bottom ? bottom : other.bottom) -
        (top > other.top ? top : other.top);
    if (x <= 0 || y <= 0) return 0;
    return (x * y) / (width * height);
  }

  /// True when [y] falls inside this rect's vertical span.
  ///
  /// [NormalizedPoint.y] is the number to test.
  bool containsY(double y) => y >= top && y <= bottom;

  @override
  bool operator ==(Object other) =>
      other is NormalizedRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'NormalizedRect($left, $top, $right, $bottom)';
}