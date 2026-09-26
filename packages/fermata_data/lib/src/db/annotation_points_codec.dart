import 'dart:convert';

import 'package:fermata_core/fermata_core.dart';

/// Compact JSON encoding for a stroke's point list.
///
/// Points are written as a flat array of numbers rather than an array of
/// objects, because a busy annotation session produces a lot of these and the
/// per-point key names dominate the payload:
///
/// ```json
/// [[0.12,0.34],[0.13,0.35,0.7]]
/// ```
///
/// Each entry is `[x, y]`, or `[x, y, pressure]` when pressure is not the
/// neutral default of 1.0. Coordinates are rounded on write: at 1/10000 of a
/// page, that is a ten-thousandth of a page width, far below what a fingertip
/// or stylus can resolve, and it keeps the stored text short.
abstract final class AnnotationPointsCodec {
  static const int _coordinateScale = 10000;

  static String encode(List<StrokePoint> points) {
    final encoded = <List<dynamic>>[
      for (final point in points)
        point.pressure == 1.0
            ? <dynamic>[
                _round(point.position.x),
                _round(point.position.y),
              ]
            : <dynamic>[
                _round(point.position.x),
                _round(point.position.y),
                _round(point.pressure),
              ],
    ];
    return jsonEncode(encoded);
  }

  static List<StrokePoint> decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];

    return [
      for (final entry in decoded)
        if (entry is List && entry.length >= 2)
          StrokePoint(
            position: NormalizedPoint(
              _toDouble(entry[0]),
              _toDouble(entry[1]),
            ),
            pressure: entry.length > 2 ? _toDouble(entry[2]) : 1.0,
          ),
    ];
  }

  static int _round(double value) =>
      (value * _coordinateScale).round();

  static double _toDouble(Object? value) => value is num
      ? value / _coordinateScale
      : (double.tryParse(value?.toString() ?? '') ?? 0) / _coordinateScale;
}
