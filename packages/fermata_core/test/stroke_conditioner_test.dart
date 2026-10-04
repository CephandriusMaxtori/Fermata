import 'dart:math' show atan2, max, min, pi;

import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

List<StrokePoint> pointsFrom(List<(double, double)> coords) => [
  for (final (x, y) in coords)
    StrokePoint(position: NormalizedPoint(x, y), pressure: 0.5),
];

List<double> xsOf(List<StrokePoint> points) =>
    points.map((p) => p.position.x).toList();

/// Turn in degrees between the leg arriving at [at] and the leg leaving it.
double _angleBetween(NormalizedPoint before, NormalizedPoint at, NormalizedPoint after) {
  final incoming = atan2(at.y - before.y, at.x - before.x);
  final outgoing = atan2(after.y - at.y, after.x - at.x);
  var degrees = (outgoing - incoming).abs() * 180 / pi;
  if (degrees > 180) degrees = 360 - degrees;
  return degrees;
}

/// Shortest distance from [point] to the polyline through [points].
double _distanceToPolyline(NormalizedPoint point, List<StrokePoint> points) {
  var nearest = double.infinity;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1].position;
    final b = points[i].position;
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      nearest = min(nearest, point.distanceTo(a));
      continue;
    }
    var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);
    nearest = min(nearest, point.distanceTo(NormalizedPoint(a.x + t * dx, a.y + t * dy)));
  }
  return nearest;
}

void main() {
  group('StrokeConditioner.thin', () {
    test('drops points closer than the minimum distance', () {
      final input = pointsFrom(const [
        (0, 0),
        (0.001, 0),
        (0.002, 0),
        (0.2, 0),
        (0.4, 0),
      ]);

      final thinned = StrokeConditioner.thin(input, minDistance: 0.05);

      expect(xsOf(thinned), [0.0, 0.2, 0.4]);
    });

    test('always keeps the first and last points', () {
      final input = pointsFrom(const [
        (0.1, 0.1),
        (0.1001, 0.1),
        (0.1002, 0.1),
      ]);

      final thinned = StrokeConditioner.thin(input, minDistance: 1.0);

      expect(thinned.first.position.x, 0.1);
      expect(thinned.last.position.x, 0.1002);
    });

    test('returns the input untouched when it is too short to thin', () {
      final input = pointsFrom(const [(0, 0), (1, 1)]);

      final thinned = StrokeConditioner.thin(input, minDistance: 0.5);

      expect(thinned.length, 2);
    });

    test('a tail shorter than minDistance is absorbed, not kept', () {
      // Issue #4. `kept.add(points.last)` was unconditional, so the final
      // segment could be any length however short. A finger decelerates before
      // lifting, so that is the *normal* end of a stroke, and it hands the
      // spline a segment orders of magnitude shorter than the one before it.
      final input = pointsFrom(const [
        (0.1, 0.5),
        (0.3, 0.5),
        (0.5, 0.5),
        (0.5001, 0.5),
      ]);

      final thinned = StrokeConditioner.thin(input, minDistance: 0.002);

      // 4 points in, 3 out: the last is absorbed into the third, which moves to
      // the true end position. Dropping it instead would lose 0.0001 of stroke.
      expect(thinned.length, 3);
      expect(thinned.last.position.x, closeTo(0.5001, 1e-9));
      for (var i = 1; i < thinned.length; i++) {
        expect(
          thinned[i].position.distanceTo(thinned[i - 1].position),
          greaterThanOrEqualTo(0.002),
          reason: 'thin promised a minimum spacing and broke it at the end',
        );
      }
    });

    test('still keeps a last point that is genuinely far away', () {
      // The case the absorption above must not break: a real final segment
      // stays a separate vertex rather than being merged backwards.
      final input = pointsFrom(const [
        (0.1, 0.5),
        (0.3, 0.5),
        (0.5, 0.5),
        (0.7, 0.5),
      ]);

      final thinned = StrokeConditioner.thin(input, minDistance: 0.002);

      expect(thinned.length, 4);
      expect(thinned.last.position.x, closeTo(0.7, 1e-9));
    });
  });

  group('StrokeConditioner.smooth', () {
    test('leaves fewer than three points alone', () {
      final input = pointsFrom(const [(0, 0), (1, 1)]);

      expect(
        StrokeConditioner.smooth(input),
        hasLength(2),
      );
    });

    test('passes through the original vertices', () {
      final input = pointsFrom(const [
        (0.2, 0.2),
        (0.5, 0.5),
        (0.8, 0.2),
      ]);

      final smoothed = StrokeConditioner.smooth(input, samplesPerSegment: 16);
      final xs = xsOf(smoothed);

      // The midpoints of the three control points must all be present, since
      // Catmull-Rom interpolates them exactly.
      for (final vertex in const [0.2, 0.5, 0.8]) {
        expect(xs.any((x) => (x - vertex).abs() < 1e-9), isTrue,
            reason: 'expected smoothed output to pass through $vertex');
      }
    });

    test('interpolates pressure across a segment', () {
      final input = [
        const StrokePoint(position: NormalizedPoint(0, 0), pressure: 0.0),
        const StrokePoint(position: NormalizedPoint(0.5, 0), pressure: 0.5),
        const StrokePoint(position: NormalizedPoint(1, 0), pressure: 1.0),
      ];

      final smoothed = StrokeConditioner.smooth(input, samplesPerSegment: 10);
      final pressures = smoothed.map((p) => p.pressure).toList();

      expect(pressures.first, closeTo(0.0, 1e-9));
      expect(pressures.last, closeTo(1.0, 1e-9));
      expect(
        pressures.every((p) => p >= -1e-9 && p <= 1 + 1e-9),
        isTrue,
        reason: 'pressure must stay within the input range',
      );
    });

    test('produces a denser point list than it was given', () {
      // A curve, not an angle. A peak like (0,0) -> (0.5,0.5) -> (1,0) turns
      // 90 degrees and is deliberately treated as two straight runs joined at a
      // corner, so it is covered by the corner tests instead.
      final input = pointsFrom(const [
        (0, 0),
        (0.25, 0.217),
        (0.5, 0.309),
        (0.75, 0.217),
        (1, 0),
      ]);

      expect(
        StrokeConditioner.smooth(input, samplesPerSegment: 8).length,
        greaterThan(input.length),
      );
    });
  });

  group('StrokeConditioner.simplify', () {
    test('collapses a straight line to its endpoints', () {
      final input = pointsFrom(const [
        (0, 0.5),
        (0.25, 0.5),
        (0.5, 0.5),
        (0.75, 0.5),
        (1, 0.5),
      ]);

      final simplified = StrokeConditioner.simplify(
        input,
        tolerance: 0.01,
      );

      expect(simplified, hasLength(2));
      expect(simplified.first.position.x, 0);
      expect(simplified.last.position.x, 1);
    });

    test('keeps a point that deviates beyond the tolerance', () {
      final input = pointsFrom(const [
        (0, 0.5),
        (0.5, 0.1),
        (1, 0.5),
      ]);

      final simplified = StrokeConditioner.simplify(
        input,
        tolerance: 0.01,
      );

      expect(simplified, hasLength(3));
    });

    test('a zero tolerance disables simplification', () {
      final input = pointsFrom(const [(0, 0), (0.5, 0.5), (1, 0)]);

      expect(
        StrokeConditioner.simplify(input, tolerance: 0).length,
        input.length,
      );
    });
  });

  group('StrokeConditioner.finalize', () {
    test('reduces a dead-straight drag to its two endpoints', () {
      final input = pointsFrom(const [
        (0, 0.5),
        (0.0001, 0.5),
        (0.0002, 0.5),
        (0.5, 0.5),
        (0.9999, 0.5),
        (1, 0.5),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.01,
        simplifyTolerance: 0.01,
        samplesPerSegment: 8,
      );

      // A dead-straight drag reduces to its two endpoints: there is no curve
      // to sample, and padding a straight line with collinear points would
      // only bloat the stored geometry.
      expect(result, hasLength(2));
      expect(result.first.position.x, closeTo(0, 1e-9));
      expect(result.last.position.x, closeTo(1, 1e-9));
      expect(
        result.every((p) => (p.position.y - 0.5).abs() < 1e-9),
        isTrue,
      );
    });

    test('keeps a curved drag as a smooth dense run', () {
      // A shallow arc. The V shapes used here previously turned ~90 degrees per
      // vertex, which is a corner by any reading and is now left sharp on
      // purpose, so the "stays dense" claim is made with an actual curve.
      //
      // The claim is about *fidelity*, not point count. This used to assert
      // `result.length > input.length`, which was true for the wrong reason:
      // the spline bulged away from the chord polyline, so simplify had to keep
      // extra points to stay inside tolerance. Once the bulge is fixed (issue #4)
      // the density correctly goes away, because five evenly-spaced points
      // already describe this arc to 0.067 - far inside any useful tolerance.
      // Asserting density would have pinned the bug, so what is asserted now is
      // that the stored polyline still follows the curve and keeps its extent.
      final input = pointsFrom(const [
        (0, 0.5),
        (0.25, 0.376),
        (0.5, 0.309),
        (0.75, 0.376),
        (1, 0.5),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.01,
        simplifyTolerance: 0.01,
        samplesPerSegment: 8,
      );

      expect(result.length, greaterThanOrEqualTo(3));
      expect(result.first.position.x, closeTo(0, 1e-9));
      expect(result.last.position.x, closeTo(1, 1e-9));
      // The middle of the arc is genuinely bowed away from the straight line
      // between the endpoints, and that bow survives.
      expect(
        result.any(
          (p) => p.position.y < 0.4,
        ),
        isTrue,
        reason: 'the arc came out flat, so the curve was lost',
      );
    });

    test('keeps a right-angle corner instead of looping past it', () {
      // Issue #1, "Pen tool is a lasso.": simplifying before smoothing collapsed
      // a two-leg mark to three points, and the spline through them inverted
      // the corner into a 151-degree reversal. Smoothing before simplifying
      // keeps the corner as a control point.
      final input = pointsFrom(const [
        (0.2, 0.2),
        (0.35, 0.2),
        (0.5, 0.2),
        (0.5, 0.4),
        (0.5, 0.6),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.002,
        simplifyTolerance: 0.0015,
      );

      // Turn between the incoming and outgoing directions at the corner. The
      // two legs are perpendicular, so this should stay near 90.
      final cornerIndex = result.indexWhere(
        (p) =>
            p.position.x >= 0.499 && p.position.x <= 0.501 && p.position.y <= 0.4,
      );
      expect(cornerIndex, greaterThan(0));
      expect(cornerIndex, lessThan(result.length - 1));

      final before = result[cornerIndex - 1].position;
      final at = result[cornerIndex].position;
      final after = result[cornerIndex + 1].position;
      final turn = _angleBetween(before, at, after);

      expect(turn, greaterThan(75));
      expect(turn, lessThan(105));
    });

    test('leaves a smooth curve smooth rather than faceting it', () {
      // The cost of corner preservation: a threshold low enough to keep a stem
      // sharp must not chop a genuine curve into straight chords. A tight but
      // continuous arc has per-vertex turns an order of magnitude below the
      // default threshold, so it has to survive intact.
      final input = pointsFrom(const [
        (0, 0.5),
        (0.25, 0.376),
        (0.5, 0.309),
        (0.75, 0.376),
        (1, 0.5),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.002,
        simplifyTolerance: 0.0015,
      );

      // Faithful to the finger's path in both directions: every input vertex is
      // reproduced, and every stored point lies back on the curve. This is what
      // the old `result.length > input.length` was a proxy for, and it fails if
      // a curve is ever faceted into straight chords.
      for (final point in input) {
        expect(
          _distanceToPolyline(point.position, result),
          lessThan(0.01),
          reason: 'a smooth curve was faceted into straight chords',
        );
      }
      for (final point in result) {
        expect(
          _distanceToPolyline(point.position, input),
          lessThan(0.01),
          reason: 'smoothing pushed ink off the curve it was drawn along',
        );
      }
    });

    test('keeps a corner sharp without a stray bulge on either side', () {
      // A corner that survives by simply inserting a loop is not a corner. The
      // runs either side of it must stay straight, which for these two legs
      // means every point on the horizontal leg has the same y.
      final result = StrokeConditioner.finalize(
        pointsFrom(const [
          (0.2, 0.2),
          (0.35, 0.2),
          (0.5, 0.2),
          (0.5, 0.4),
          (0.5, 0.6),
        ]),
        minDistance: 0.002,
        simplifyTolerance: 0.0015,
      );

      final onHorizontalLeg = result.where((p) => p.position.x < 0.49);
      expect(onHorizontalLeg, isNotEmpty);
      for (final point in onHorizontalLeg) {
        expect(
          point.position.y,
          closeTo(0.2, 0.005),
          reason: 'the leg before the corner bulged away from straight',
        );
      }

      final onVerticalLeg = result.where((p) => p.position.y > 0.25);
      expect(onVerticalLeg, isNotEmpty);
      for (final point in onVerticalLeg) {
        expect(
          point.position.x,
          closeTo(0.5, 0.005),
          reason: 'the leg after the corner bulged away from straight',
        );
      }
    });

    test('a fast leg into a slow finish does not hook past the end', () {
      // Issue #4, "Pen tool acting like a lasso": the #1 fix was real but
      // incomplete. Uniform Catmull-Rom takes its tangent at a control point
      // from the chord across that point's neighbours, so a long leg followed by
      // a short one sends the curve off along the long leg's direction and
      // forces it back. Every fixture from #1 is evenly spaced, so this was
      // never in the tested input distribution.
      //
      // Fingers decelerate before lifting, so a stroke that draws fast and
      // settles is ordinary rather than exotic. The spacing ratio here is the
      // invariant that matters; the individual points are incidental.
      final input = pointsFrom(const [
        (0.2, 0.2),
        (0.45, 0.25),
        (0.62, 0.35),
        (0.70, 0.46),
        (0.715, 0.52),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.002,
        simplifyTolerance: 0.0015,
      );

      // Half a logical pixel on a 510px page. Before this fix the same input
      // strayed 0.0086, which is ~4.4 logical px and the visible hook.
      for (final point in result) {
        expect(
          _distanceToPolyline(point.position, input),
          lessThan(0.001),
          reason: 'the spline hooked away from the finger path near the end',
        );
      }
    });

    test('no segment dwarfs the one after it', () {
      // The general form of the above, and the property that actually fixes it:
      // once every run entering the spline is evenly spaced, the overshoot has
      // nothing to amplify. A hand-picked fixture would only prove one case.
      final input = pointsFrom(const [
        (0.2, 0.2), (0.35, 0.2), (0.5, 0.2),
        (0.5, 0.30), (0.5, 0.32), (0.5001, 0.3205),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.002,
        simplifyTolerance: 0.0015,
      );

      final lengths = [
        for (var i = 1; i < result.length; i++)
          result[i].position.distanceTo(result[i - 1].position),
      ];
      expect(lengths, isNotEmpty);
      final ratio = lengths.reduce(max) / lengths.reduce(min);
      expect(
        ratio,
        lessThan(20),
        reason: 'a segment ${lengths.reduce(max)} long sits beside one '
            '${lengths.reduce(min)} long, which is what makes Catmull-Rom hook',
      );
    });

    test('never strays far from the path the finger took', () {
      // The "rope" symptom in numbers: the rendered mark sat up to 3% of page
      // width off the input on a straight-leged mark, which on A4 is ~17pt of
      // bulge. Ink should stay on the finger's path.
      final input = pointsFrom(const [
        (0.2, 0.2),
        (0.3, 0.2),
        (0.4, 0.2),
        (0.5, 0.2),
        (0.5, 0.35),
        (0.5, 0.5),
        (0.5, 0.6),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.002,
        simplifyTolerance: 0.0015,
      );

      for (final point in input) {
        expect(
          _distanceToPolyline(point.position, result),
          lessThan(0.01),
          reason: 'finalize pushed ink away from where it was drawn',
        );
      }
    });
  });

  group('Stroke serialization', () {
    test('round-trips through JSON', () {
      final stroke = Stroke(
        id: 'stroke-1',
        scoreId: 'score-1',
        pageIndex: 2,
        layerId: 'layer-1',
        kind: AnnotationKind.highlighter,
        colorValue: 0xFFFFEB3B,
        widthFraction: 0.02,
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        points: [
          const StrokePoint(position: NormalizedPoint(0.1, 0.2)),
          const StrokePoint(
            position: NormalizedPoint(0.3, 0.4),
            pressure: 0.7,
          ),
        ],
      );

      final restored = Stroke.fromJson(stroke.toJson());

      expect(restored, stroke);
    });

    test('omits pressure when it is neutral', () {
      const point = StrokePoint(position: NormalizedPoint(0.5, 0.5));

      expect(point.toJson(), hasLength(2));
      expect(StrokePoint.fromJson(point.toJson()), point);
    });

    test('copyWith replaces only the given fields', () {
      final stroke = Stroke(
        id: 'stroke-1',
        scoreId: 'score-1',
        pageIndex: 0,
        layerId: 'layer-1',
        kind: AnnotationKind.pen,
        colorValue: 0xFF000000,
        widthFraction: 0.01,
        createdAt: DateTime.utc(2026),
        points: const [],
      );

      final moved = stroke.copyWith(pageIndex: 4);

      expect(moved.pageIndex, 4);
      expect(moved.id, stroke.id);
      expect(moved.colorValue, stroke.colorValue);
      expect(moved.createdAt, stroke.createdAt);
    });
  });

  group('AnnotationKind', () {
    test('classifies ink and non-ink kinds', () {
      expect(AnnotationKind.pen.isInk, isTrue);
      expect(AnnotationKind.highlighter.isInk, isTrue);
      expect(AnnotationKind.text.isInk, isFalse);
      expect(AnnotationKind.stamp.isInk, isFalse);
    });

    test('fromName falls back to pen for unknown input', () {
      expect(AnnotationKind.fromName('nonsense'), AnnotationKind.pen);
    });
  });
}
