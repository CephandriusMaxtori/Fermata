import 'dart:math' as math;

import 'normalized_point.dart';
import 'stroke.dart';

/// Pure-Dart stroke conditioning: thinning, smoothing and simplification.
///
/// The Flutter layer turns the resulting point list into a `Path`, but all the
/// geometry lives here so it can be unit tested without a widget tree. Keeping
/// smoothing in the model layer also means a stroke looks identical whether it
/// is replayed by the app, exported to a backup, or redrawn by the web UI.
abstract final class StrokeConditioner {
  /// Drops points closer than [minDistance] to the previous kept point.
  ///
  /// Finger input emits events far faster than a stroke needs samples, so this
  /// is what keeps a long annotation session from producing a database full of
  /// redundant coordinates. The first and last points are always kept so the
  /// stroke's extent is preserved.
  static List<StrokePoint> thin(
    List<StrokePoint> points, {
    required double minDistance,
  }) {
    if (points.length < 3 || minDistance <= 0) {
      return List<StrokePoint>.unmodifiable(points);
    }
    final kept = <StrokePoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final candidate = points[i];
      if (candidate.position.distanceTo(kept.last.position) >= minDistance) {
        kept.add(candidate);
      }
    }
    kept.add(points.last);
    return List<StrokePoint>.unmodifiable(kept);
  }

  /// Smooths a point list with a Catmull-Rom spline.
  ///
  /// Sampling the spline into a denser point list (rather than emitting curve
  /// segments) keeps the result representable as a plain polyline, which is
  /// what gets persisted.
  static List<StrokePoint> smooth(
    List<StrokePoint> points, {
    int samplesPerSegment = 12,
  }) {
    if (points.length < 3 || samplesPerSegment < 1) {
      return List<StrokePoint>.unmodifiable(points);
    }

    final extended = <StrokePoint>[
      _reflect(points[0], points[1]),
      ...points,
      _reflect(points.last, points[points.length - 2]),
    ];

    final output = <StrokePoint>[];
    for (var i = 1; i < extended.length - 2; i++) {
      final isEdgeSegment = i == 1 || i == extended.length - 3;

      for (var step = 0; step <= samplesPerSegment; step++) {
        if (step == 0 && !isEdgeSegment) continue;
        final t = step / samplesPerSegment;
        output.add(
          StrokePoint(
            position: _interpolate(
              extended[i - 1].position,
              extended[i].position,
              extended[i + 1].position,
              extended[i + 2].position,
              t,
            ),
            pressure: _lerp(
              extended[i].pressure,
              extended[i + 1].pressure,
              t,
            ),
          ),
        );
      }
    }

    return List<StrokePoint>.unmodifiable(output);
  }

  /// Ramer-Douglas-Peucker simplification, with [tolerance] in normalized
  /// units (so roughly a fraction of page width).
  static List<StrokePoint> simplify(
    List<StrokePoint> points, {
    required double tolerance,
  }) {
    if (points.length < 3 || tolerance <= 0) {
      return List<StrokePoint>.unmodifiable(points);
    }

    final keep = List<bool>.filled(points.length, false);
    keep.first = true;
    keep.last = true;

    final pending = <_Span>[_Span(0, points.length - 1)];
    while (pending.isNotEmpty) {
      final span = pending.removeLast();
      if (span.end <= span.start + 1) continue;

      final start = points[span.start].position;
      final end = points[span.end].position;
      var furthestDistance = 0.0;
      var furthestIndex = -1;

      for (var i = span.start + 1; i < span.end; i++) {
        final distance = _perpendicularDistance(points[i].position, start, end);
        if (distance > furthestDistance) {
          furthestDistance = distance;
          furthestIndex = i;
        }
      }

      if (furthestIndex != -1 && furthestDistance > tolerance) {
        keep[furthestIndex] = true;
        pending
          ..add(_Span(span.start, furthestIndex))
          ..add(_Span(furthestIndex, span.end));
      }
    }

    return List<StrokePoint>.unmodifiable([
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ]);
  }

  /// Thin, then simplify, then smooth.
  ///
  /// This is the standard entry point when a stroke is finalized. Thinning
  /// first keeps the RDP pass cheap, and smoothing last means the rendered
  /// curve passes through the simplified polyline's vertices.
  static List<StrokePoint> finalize(
    List<StrokePoint> points, {
    required double minDistance,
    required double simplifyTolerance,
    int samplesPerSegment = 12,
  }) {
    return smooth(
      simplify(
        thin(points, minDistance: minDistance),
        tolerance: simplifyTolerance,
      ),
      samplesPerSegment: samplesPerSegment,
    );
  }

  static StrokePoint _reflect(StrokePoint edge, StrokePoint inward) {
    return StrokePoint(
      position: NormalizedPoint(
        2 * edge.position.x - inward.position.x,
        2 * edge.position.y - inward.position.y,
      ),
      pressure: edge.pressure,
    );
  }

  static NormalizedPoint _interpolate(
    NormalizedPoint p0,
    NormalizedPoint p1,
    NormalizedPoint p2,
    NormalizedPoint p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;
    return NormalizedPoint(
      0.5 *
          ((2 * p1.x) +
              (-p0.x + p2.x) * t +
              (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
              (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
      0.5 *
          ((2 * p1.y) +
              (-p0.y + p2.y) * t +
              (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
              (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _perpendicularDistance(
    NormalizedPoint point,
    NormalizedPoint lineStart,
    NormalizedPoint lineEnd,
  ) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    if (dx == 0 && dy == 0) {
      return point.distanceTo(lineStart);
    }
    final numerator =
        ((point.y - lineStart.y) * dx - (point.x - lineStart.x) * dy).abs();
    return numerator / math.sqrt(dx * dx + dy * dy);
  }
}

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}
