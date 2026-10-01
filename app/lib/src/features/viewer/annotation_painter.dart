import 'dart:math' as math;

import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';

import 'brush_selection.dart';

/// Draws a score's ink for one page.
///
/// Every coordinate arrives normalized to the page box and is resolved through
/// [size], the same box the page image occupies. That is the whole alignment
/// guarantee: the painter and the image are laid out identically, so ink lands
/// on the staff at any zoom, density or orientation.
class AnnotationPainter extends CustomPainter {
  AnnotationPainter({
    required this.strokes,
    required this.size,
    this.liveStroke,
    this.liveBrush,
  });

  final List<Stroke> strokes;

  /// The render box, in logical pixels, that the page image also occupies.
  final Size size;

  /// The stroke currently under the user's finger, drawn before it is committed
  /// so the pen feels responsive without a database write per pointer event.
  final List<StrokePoint>? liveStroke;

  /// The brush the live stroke will be committed with.
  ///
  /// The preview has to match the committed mark. An earlier version hard-coded a
  /// red 3px stroke, so a user with the highlighter selected saw a thin red line
  /// that turned into a thick yellow band on lift.
  final BrushSelection? liveBrush;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (size.isEmpty) return;

    final byLayer = <AnnotationKind, List<Stroke>>{
      for (final kind in AnnotationKind.values) kind: <Stroke>[],
    };
    for (final stroke in strokes) {
      byLayer[stroke.kind]?.add(stroke);
    }

    // Highlighter first, so pen ink sits on top of it rather than under.
    for (final stroke
        in byLayer[AnnotationKind.highlighter] ?? const <Stroke>[]) {
      _paintStroke(
        canvas,
        stroke,
        paint: Paint()
          ..color = Color(stroke.colorValue).withValues(alpha: 0.42)
          ..strokeWidth = math.max(1, stroke.widthFraction * size.width)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          // Multiply is what makes a highlighter read as ink under the print
          // rather than paint on top of it.
          ..blendMode = BlendMode.multiply,
      );
    }

    for (final stroke in byLayer[AnnotationKind.pen] ?? const <Stroke>[]) {
      _paintStroke(
        canvas,
        stroke,
        paint: Paint()
          ..color = Color(stroke.colorValue)
          ..strokeWidth = math.max(1, stroke.widthFraction * size.width)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final live = liveStroke;
    if (live != null && live.length > 1) {
      final brush = liveBrush;
      final isHighlighter = brush?.kind == AnnotationKind.highlighter;
      _paintPoints(
        canvas,
        live,
        Paint()
          // Same colour and width rules as a committed stroke, so the preview is
          // an honest preview. Falls back to opaque black rather than a hard-coded
          // red if no brush was supplied.
          ..color = Color(brush?.color ?? 0xFF000000).withValues(
            alpha: isHighlighter ? 0.42 : 1.0,
          )
          ..strokeWidth = math.max(
            1,
            (brush?.width ?? 0.006) * size.width,
          )
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = isHighlighter ? BlendMode.multiply : BlendMode.srcOver,
      );
    }
  }

  void _paintStroke(Canvas canvas, Stroke stroke, {required Paint paint}) {
    if (stroke.points.length < 2) {
      // A tap rather than a drag: render it as a dot so it is not invisible.
      if (stroke.points.length == 1) {
        final offset = _toOffset(stroke.points.first.position, size);
        canvas.drawCircle(offset, paint.strokeWidth / 2, paint);
      }
      return;
    }
    _paintPoints(canvas, stroke.points, paint);
  }

  void _paintPoints(Canvas canvas, List<StrokePoint> points, Paint paint) {
    final path = Path()..moveTo(_x(points[0]), _y(points[0]));

    // Quadratic segments through stroke midpoints: the point list is already
    // Catmull-Rom sampled by StrokeConditioner, so a plain polyline is smooth
    // and this only removes any residual faceting.
    for (var i = 1; i < points.length - 1; i++) {
      final current = _toOffset(points[i].position, size);
      final next = _toOffset(points[i + 1].position, size);
      path.quadraticBezierTo(
        current.dx,
        current.dy,
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
    }

    final last = _toOffset(points.last.position, size);
    path.lineTo(last.dx, last.dy);
    canvas.drawPath(path, paint);
  }

  double _x(StrokePoint point) => point.position.x * size.width;

  double _y(StrokePoint point) => point.position.y * size.height;

  Offset _toOffset(NormalizedPoint point, Size box) =>
      Offset(point.x * box.width, point.y * box.height);

  @override
  bool shouldRepaint(AnnotationPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.liveStroke != liveStroke ||
        oldDelegate.size != size;
  }
}
