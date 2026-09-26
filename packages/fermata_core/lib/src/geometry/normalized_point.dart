import 'dart:math' as math;

/// A point expressed as a fraction of the page box, in the range `[0, 1]`.
///
/// Fermata stores every annotation coordinate this way rather than in pixels or
/// PDF points. That single decision is what keeps annotations aligned with the
/// score at any zoom level, on any device density, and in either orientation:
/// the page image and the overlay both resolve normalized coordinates through
/// whatever render box they currently occupy.
class NormalizedPoint {
  const NormalizedPoint(this.x, this.y);

  /// Horizontal position, `0` = left edge of the page, `1` = right edge.
  final double x;

  /// Vertical position, `0` = top edge of the page, `1` = bottom edge.
  final double y;

  static const NormalizedPoint zero = NormalizedPoint(0, 0);
  static const NormalizedPoint one = NormalizedPoint(1, 1);

  /// Clamps both components into `[0, 1]`.
  ///
  /// Callers that convert a drag gesture into a point should clamp, because
  /// `PointerMoveEvent` can report coordinates slightly outside the target.
  NormalizedPoint clamp() => NormalizedPoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

  /// Converts to pixels within a render box of [renderWidth] x [renderHeight].
  ({double x, double y}) toPixels({
    required double renderWidth,
    required double renderHeight,
  }) {
    return (x: x * renderWidth, y: y * renderHeight);
  }

  /// Converts from pixels within a render box of the given size.
  ///
  /// A zero-sized box (which can happen mid-layout) yields [zero] rather than
  /// dividing by zero.
  factory NormalizedPoint.fromPixels({
    required double x,
    required double y,
    required double renderWidth,
    required double renderHeight,
  }) {
    if (renderWidth <= 0 || renderHeight <= 0) return zero;
    return NormalizedPoint(
      (x / renderWidth).clamp(0.0, 1.0),
      (y / renderHeight).clamp(0.0, 1.0),
    );
  }

  double distanceTo(NormalizedPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  NormalizedPoint lerp(NormalizedPoint other, double t) => NormalizedPoint(
    x + (other.x - x) * t,
    y + (other.y - y) * t,
  );

  Map<String, double> toJson() => {'x': x, 'y': y};

  factory NormalizedPoint.fromJson(Map<String, dynamic> json) {
    return NormalizedPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NormalizedPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'NormalizedPoint($x, $y)';
}
