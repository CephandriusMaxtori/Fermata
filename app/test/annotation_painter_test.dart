import 'dart:ui' show Offset, Size;

import 'package:fermata/src/features/viewer/annotation_painter.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:flutter_test/flutter_test.dart';

List<StrokePoint> _points(List<(double, double)> coords) => [
  for (final (x, y) in coords)
    StrokePoint(position: NormalizedPoint(x, y)),
];

/// A right-angle drag through the centre of the page, conditioned the way the
/// viewer conditions a real stroke.
final List<StrokePoint> _elbow = StrokeConditioner.finalize(
  _points(const [(0.2, 0.2), (0.35, 0.2), (0.5, 0.2), (0.5, 0.4), (0.5, 0.6)]),
  minDistance: 0.002,
  simplifyTolerance: 0.0015,
);

void main() {
  group('AnnotationPainter.pathFor', () {
    test('never draws outside the box the finger drew in', () {
      // Issue #1, "Pen tool is a lasso." The painter used to smooth a third
      // time with quadratics through the midpoints of consecutive points. On a
      // conditioned stroke that pushed ink to x=522 and y=170 for a mark that
      // only spans x 200..500, y 200..600 - about 3% of page width of bulge,
      // which is what read as rope.
      final path = AnnotationPainter.pathFor(_elbow, const Size(1000, 1000));
      final bounds = path.getBounds();

      expect(bounds.left, closeTo(200, 0.001));
      expect(bounds.top, closeTo(200, 0.001));
      expect(bounds.right, closeTo(500, 0.001));
      expect(bounds.bottom, closeTo(600, 0.001));
    });

    test('keeps a right angle as a right angle', () {
      // The same marks, measured on the path rather than its bounding box: the
      // quadratic version reported no turn at all across the corner, i.e. it
      // quietly rounded 90 degrees away.
      final path = AnnotationPainter.pathFor(_elbow, const Size(1000, 1000));

      final offsets = <Offset>[];
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d <= metric.length; d += 0.5) {
          final tangent = metric.getTangentForOffset(d);
          if (tangent != null) offsets.add(tangent.position);
        }
      }
      expect(offsets.length, greaterThan(2));

      var worstTurn = 0.0;
      for (var i = 1; i < offsets.length - 1; i++) {
        final a = offsets[i] - offsets[i - 1];
        final b = offsets[i + 1] - offsets[i];
        final aLen = a.distance, bLen = b.distance;
        if (aLen == 0 || bLen == 0) continue;
        final cosine = (a.dx * b.dx + a.dy * b.dy) / (aLen * bLen);
        final degrees = (1 - cosine.clamp(-1.0, 1.0)) * 90;
        if (degrees > worstTurn) worstTurn = degrees;
      }

      expect(worstTurn, closeTo(90, 1));
    });

    test('scales with the page box so ink stays aligned when zoomed', () {
      final points = _points(const [(0.25, 0.5), (0.75, 0.5)]);

      final small = AnnotationPainter.pathFor(points, const Size(400, 400));
      final large = AnnotationPainter.pathFor(points, const Size(1200, 1200));

      // Same normalized geometry, so the fractions must agree exactly.
      expect(small.getBounds().left / 400, closeTo(large.getBounds().left / 1200, 1e-9));
      expect(small.getBounds().right / 400, closeTo(large.getBounds().right / 1200, 1e-9));
      expect(small.getBounds().top / 400, closeTo(large.getBounds().top / 1200, 1e-9));
    });

    test('returns an empty path for no points instead of throwing', () {
      final path = AnnotationPainter.pathFor(const [], const Size(100, 100));
      expect(path.getBounds().isEmpty, isTrue);
    });

    test('handles a single point, which paints as a dot', () {
      final path = AnnotationPainter.pathFor(
        _points(const [(0.4, 0.6)]),
        const Size(1000, 1000),
      );
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(400, 0.001));
      expect(bounds.top, closeTo(600, 0.001));
      // A single-point path has no extent; _paintStroke draws it as a circle.
      expect(bounds.width, 0);
      expect(bounds.height, 0);
    });
  });
}