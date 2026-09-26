import 'package:fermata_core/fermata_core.dart';
import 'package:test/test.dart';

void main() {
  group('NormalizedPoint', () {
    test('maps the unit square onto a render box', () {
      final topLeft = const NormalizedPoint(0, 0).toPixels(
        renderWidth: 400,
        renderHeight: 800,
      );
      final bottomRight = const NormalizedPoint(1, 1).toPixels(
        renderWidth: 400,
        renderHeight: 800,
      );

      expect(topLeft.x, 0);
      expect(topLeft.y, 0);
      expect(bottomRight.x, 400);
      expect(bottomRight.y, 800);
    });

    test('scales with the render box so overlays cannot drift', () {
      const point = NormalizedPoint(0.25, 0.75);

      final small = point.toPixels(renderWidth: 100, renderHeight: 100);
      final large = point.toPixels(renderWidth: 1000, renderHeight: 1000);

      expect(small.x, closeTo(25, 1e-9));
      expect(small.y, closeTo(75, 1e-9));
      expect(large.x, closeTo(250, 1e-9));
      expect(large.y, closeTo(750, 1e-9));
    });

    test('round-trips through pixels at any render size', () {
      const original = NormalizedPoint(0.3, 0.6);

      for (final size in <double>[1, 17.5, 320, 1440.25]) {
        final pixels = original.toPixels(
          renderWidth: size,
          renderHeight: size,
        );
        final restored = NormalizedPoint.fromPixels(
          x: pixels.x,
          y: pixels.y,
          renderWidth: size,
          renderHeight: size,
        );

        expect(restored.x, closeTo(original.x, 1e-9));
        expect(restored.y, closeTo(original.y, 1e-9));
      }
    });

    test('clamp constrains drag coordinates that overshoot the page', () {
      const overshoot = NormalizedPoint(-0.2, 1.4);
      final clamped = overshoot.clamp();

      expect(clamped.x, 0);
      expect(clamped.y, 1);
    });

    test('fromPixels guards against a zero-sized render box', () {
      final point = NormalizedPoint.fromPixels(
        x: 10,
        y: 20,
        renderWidth: 0,
        renderHeight: 0,
      );

      expect(point, NormalizedPoint.zero);
    });

    test('fromPixels clamps pixels that land outside the box', () {
      final point = NormalizedPoint.fromPixels(
        x: -50,
        y: 500,
        renderWidth: 100,
        renderHeight: 200,
      );

      expect(point.x, 0);
      expect(point.y, 1);
    });

    test('distanceTo and lerp behave as expected', () {
      const a = NormalizedPoint(0, 0);
      const b = NormalizedPoint(3, 4);

      expect(a.distanceTo(b), 5);
      expect(a.lerp(b, 0.5), const NormalizedPoint(1.5, 2));
    });
  });

  group('PageGeometry', () {
    test('fits inside the available box preserving aspect ratio', () {
      // A4 portrait is taller than it is wide, so the height axis constrains.
      const page = PageGeometry(widthPt: 612, heightPt: 792);

      final fitted = page.fitWithin(
        availableWidth: 400,
        availableHeight: 400,
      );

      expect(fitted.height, closeTo(400, 1e-9));
      expect(fitted.width, closeTo(400 * (612 / 792), 1e-9));
      expect(fitted.width / fitted.height, closeTo(page.aspectRatio, 1e-9));
    });

    test('is constrained by the tighter axis', () {
      const page = PageGeometry(widthPt: 1000, heightPt: 500);

      final fitted = page.fitWithin(
        availableWidth: 250,
        availableHeight: 1000,
      );

      expect(fitted.width, closeTo(250, 1e-9));
      expect(fitted.height, closeTo(125, 1e-9));
    });

    test('returns a zero box for unknown geometry', () {
      const page = PageGeometry(widthPt: 0, heightPt: 0);

      expect(page.isValid, isFalse);
      expect(
        page.fitWithin(availableWidth: 400, availableHeight: 400),
        (width: 0.0, height: 0.0),
      );
    });
  });
}
