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

    // The last point is always kept so the stroke's extent is preserved, but not
    // unconditionally: `kept.add` here used to leave a final segment of any
    // length, however short. A finger decelerates before lifting, so that tail
    // segment is routinely orders of magnitude shorter than the leg before it,
    // and the spline then draws a hook on it (see `_respace`).
    //
    // Absorbing it into the previous kept point keeps the stroke's true end
    // position -- which is why the last point is not simply dropped -- while
    // restoring the spacing guarantee `minDistance` promises everywhere.
    if (kept.length > 1 &&
        kept.last.position.distanceTo(points.last.position) < minDistance) {
      kept[kept.length - 1] = points.last;
    } else {
      kept.add(points.last);
    }

    return List<StrokePoint>.unmodifiable(kept);
  }

  /// Smooths a point list with a Catmull-Rom spline, preserving corners.
  ///
  /// Sampling the spline into a denser point list (rather than emitting curve
  /// segments) keeps the result representable as a plain polyline, which is
  /// what gets persisted.
  ///
  /// A plain Catmull-Rom spline has a continuous tangent at every control point,
  /// so it cannot represent a corner: the direction change is smeared across the
  /// samples on either side of the vertex and a 90-degree turn arrives as a
  /// shallow arc. Curved handwriting wants that, but the corners in a stem, an
  /// "L", or the hook of a "5" are exactly what makes writing legible, and
  /// rounding them is what makes ink read as rope.
  ///
  /// So vertices where the direction changes by more than [cornerThresholdRadians]
  /// are treated as run boundaries: each run between corners is splined on its
  /// own and the corner vertex is emitted exactly once, unblurred. The threshold
  /// trades the two off - set it high and handwriting keeps hard angles inside
  /// what should have been curves, set it low and true curves get faceted.
  ///
  /// ## On the threshold's real headroom
  ///
  /// An earlier version of this comment claimed handwriting turns 0.008-0.2 rad,
  /// "an order of magnitude" below the 0.7 default. That was measured on clean
  /// synthetic arcs, not on finger input, and it is roughly an order of
  /// magnitude optimistic. Sampling at `minDistance` (0.002 is about two device
  /// pixels) with a pixel of capacitive jitter gives per-vertex turns of
  /// 0.16-0.46 rad, and past about 0.006 of jitter the worst vertices cross 0.7
  /// and the corner splitter starts firing on noise.
  ///
  /// When it does, `_cornerRuns` returns only two-point runs, so the stroke is
  /// emitted as a raw polyline with no spline at all. That is a silent fallback,
  /// not a crash, which is why it went unnoticed. The default is still right for
  /// clean input; it is just not the comfortable margin it was documented as.
  ///
  /// Note also that this threshold is measured on *normalized* coordinates, where
  /// x is a fraction of page width and y of page height. On A4 the same physical
  /// 45-degree corner measures 0.615 rad travelling horizontally and 0.956 rad
  /// travelling vertically, so at a given threshold the same corner is preserved
  /// or smoothed depending on which way the pen happened to be going. Fixing that
  /// means measuring the angle in a space where the page is square, which is a
  /// separate change from this one and is not made here.
  static List<StrokePoint> smooth(
    List<StrokePoint> points, {
    int samplesPerSegment = 12,
    double cornerThresholdRadians = 0.7,
    double maxSegmentLength = 0.004,
  }) {
    if (points.length < 3 || samplesPerSegment < 1) {
      return List<StrokePoint>.unmodifiable(points);
    }

    final output = <StrokePoint>[];
    for (final run in _cornerRuns(points, cornerThresholdRadians)) {
      if (output.isNotEmpty) output.removeLast();
      output.addAll(
        run.length < 3
            ? run
            : _splineRun(
                _respace(run, maxSegmentLength),
                samplesPerSegment: samplesPerSegment,
              ),
      );
    }

    return List<StrokePoint>.unmodifiable(output);
  }

  /// Re-spaces a run so no segment dwarfs its neighbours, keeping every vertex.
  ///
  /// Uniform Catmull-Rom takes its tangent at a control point from the chord
  /// *across* that point's neighbours, `(p[i+1] - p[i-1]) / 2`, which is
  /// proportional to the long segment even when the segment it is about to draw
  /// is tiny. A long leg followed by a short one therefore leaves the run
  /// heading off along the long leg's direction and forces it back onto the next
  /// point: a hook several times the length of the short segment. That is the
  /// "lasso" of issue #4, and it is invisible on evenly-spaced input, which is
  /// why every fixture from issue #1 missed it.
  ///
  /// Measured on the control polygon `(0.5,0.5) -> (0.5,0.4) -> (0.5002,0.3995)`:
  /// the `p1 -> p2` segment is 0.00054 long and the spline passes 0.0070 below
  /// it, roughly 13x the segment. Fingers decelerate before lifting, so this
  /// shape is the *common* end of a stroke rather than a corner case.
  ///
  /// Walking the polyline at a fixed arc length and emitting the original
  /// vertices *alongside* the new samples bounds the excursion at roughly
  /// `maxSegmentLength / 2`. Emitting the originals is what keeps this
  /// re-spacing and not decimation: a corner vertex is a run boundary, and
  /// dropping it because it fell between two samples would reintroduce exactly
  /// the faceting that corner splitting exists to avoid.
  static List<StrokePoint> _respace(
    List<StrokePoint> points,
    double maxSegmentLength,
  ) {
    if (points.length < 3 || maxSegmentLength <= 0) return points;

    final output = <StrokePoint>[points.first];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1].position;
      final b = points[i].position;
      final length = a.distanceTo(b);

      // Short enough already, and adding samples here could only duplicate
      // vertices that `simplify` would remove again later.
      if (length <= maxSegmentLength) {
        output.add(points[i]);
        continue;
      }

      final steps = (length / maxSegmentLength).ceil();
      for (var step = 1; step < steps; step++) {
        final t = step / steps;
        output.add(
          StrokePoint(
            position: NormalizedPoint(
              a.x + (b.x - a.x) * t,
              a.y + (b.y - a.y) * t,
            ),
            pressure: _lerp(points[i - 1].pressure, points[i].pressure, t),
          ),
        );
      }
      // The original vertex, not a resampled approximation of it.
      output.add(points[i]);
    }

    return List<StrokePoint>.unmodifiable(output);
  }

  /// Splits [points] into runs that each end on a corner, sharing that corner
  /// vertex between the run before and the run after it.
  static List<List<StrokePoint>> _cornerRuns(
    List<StrokePoint> points,
    double threshold,
  ) {
    if (threshold <= 0) return [points];

    final corners = <int>[];
    for (var i = 1; i < points.length - 1; i++) {
      final before = points[i].position - points[i - 1].position;
      final after = points[i + 1].position - points[i].position;
      if (before.isZero || after.isZero) continue;
      final cosine = (before.dot(after)) / (before.magnitude * after.magnitude);
      if (math.acos(cosine.clamp(-1.0, 1.0)) >= threshold) corners.add(i);
    }

    if (corners.isEmpty) return [points];

    final runs = <List<StrokePoint>>[];
    var start = 0;
    for (final corner in corners) {
      runs.add(points.sublist(start, corner + 1));
      start = corner;
    }
    runs.add(points.sublist(start));
    return runs;
  }

  /// Catmull-Rom through one run, with reflected end control points so the
  /// first and last segments do not droop.
  static List<StrokePoint> _splineRun(
    List<StrokePoint> points, {
    required int samplesPerSegment,
  }) {
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
    return output;
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

  /// Thin, then smooth, then simplify.
  ///
  /// The order is load-bearing and was originally the reverse, which turned
  /// every sharp direction change into a loop (issue #1).
  ///
  /// Reordering was necessary but not sufficient (issue #4): uniform Catmull-Rom
  /// still hooks on unevenly-spaced input, because its tangent at a control point
  /// comes from the chord across that point's neighbours. `thin` guarantees a
  /// *minimum* spacing and nothing more, so a stroke drawn fast and then settled
  /// reaches the spline with one segment orders of magnitude shorter than the one
  /// before it. `smooth` re-spaces each run to `[maxSegmentLength]`, which bounds
  /// the excursion at about half that. Measured on the fixture that used to stray
  /// 0.0086 from the finger's path: now 0.0001.
  ///
  /// Simplifying *before* smoothing is destructive. Ramer-Douglas-Peucker
  /// collapses a straight run to its two endpoints, so a mark that turns one
  /// corner reaches the spline as just three points: start, corner, end. No
  /// spline through three widely spaced points can turn sharply without bulging
  /// outward, so a clean 90-degree corner came out as a 151-degree reversal
  /// straying ~3% of page width away from the path the finger actually took -
  /// the "rope" look. Reducing the tolerance does not help: a straight run
  /// collapses at any tolerance, so there is no setting that preserves it.
  ///
  /// Smoothing first keeps every thinned vertex as a spline control point, so a
  /// corner is a shape the spline reproduces rather than one it has to invent.
  /// The simplify pass then runs on the spline *output*, which really is smooth,
  /// so its tolerance discards only the redundant dense samples that smoothing
  /// just added and leaves genuine curvature alone. It also keeps storage down:
  /// the `samplesPerSegment` densification is undone again before anything is
  /// persisted.
  static List<StrokePoint> finalize(
    List<StrokePoint> points, {
    required double minDistance,
    required double simplifyTolerance,
    int samplesPerSegment = 12,
    double? maxSegmentLength,
  }) {
    return simplify(
      smooth(
        thin(points, minDistance: minDistance),
        samplesPerSegment: samplesPerSegment,
        // Tied to the caller's own spacing knob rather than exposed separately:
        // the caller already states how finely it wants this stroke sampled, and
        // one number to reason about beats two that can disagree.
        maxSegmentLength: maxSegmentLength ?? minDistance * 2,
      ),
      tolerance: simplifyTolerance,
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
