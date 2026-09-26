import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

List<StrokePoint> pointsFrom(List<(double, double)> coords) => [
  for (final (x, y) in coords)
    StrokePoint(position: NormalizedPoint(x, y), pressure: 0.5),
];

List<double> xsOf(List<StrokePoint> points) =>
    points.map((p) => p.position.x).toList();

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
      final input = pointsFrom(const [
        (0, 0),
        (0.5, 0.5),
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
    test('runs thin, simplify and smooth in that order', () {
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
      final input = pointsFrom(const [
        (0, 0.5),
        (0.25, 0.1),
        (0.5, 0.5),
        (0.75, 0.9),
        (1, 0.5),
      ]);

      final result = StrokeConditioner.finalize(
        input,
        minDistance: 0.01,
        simplifyTolerance: 0.01,
        samplesPerSegment: 8,
      );

      expect(result.length, greaterThan(input.length));
      expect(result.first.position.x, closeTo(0, 1e-9));
      expect(result.last.position.x, closeTo(1, 1e-9));
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
