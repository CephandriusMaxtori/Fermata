import 'normalized_point.dart';

/// The annotation tools Fermata can represent.
///
/// Only [pen] and [highlighter] are creatable in the first annotation pass;
/// [text] and [stamp] are declared up front so persisted data and the future
/// web UI agree on the vocabulary from the start.
enum AnnotationKind {
  pen,
  highlighter,
  text,
  stamp;

  static AnnotationKind fromName(String name) => AnnotationKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => AnnotationKind.pen,
  );

  /// Whether this kind carries a freehand point list.
  bool get isInk => this == AnnotationKind.pen || this == AnnotationKind.highlighter;
}

/// One sampled point along an ink stroke.
class StrokePoint {
  const StrokePoint({
    required this.position,
    this.pressure = 1.0,
  });

  final NormalizedPoint position;

  /// Stylus pressure in `[0, 1]`. Defaults to a neutral 1.0 for finger input.
  final double pressure;

  StrokePoint copyWith({NormalizedPoint? position, double? pressure}) =>
      StrokePoint(
        position: position ?? this.position,
        pressure: pressure ?? this.pressure,
      );

  List<dynamic> toJson() => pressure == 1.0
      ? <dynamic>[position.x, position.y]
      : <dynamic>[position.x, position.y, pressure];

  factory StrokePoint.fromJson(List<dynamic> json) {
    return StrokePoint(
      position: NormalizedPoint(
        (json[0] as num).toDouble(),
        (json[1] as num).toDouble(),
      ),
      pressure: json.length > 2 ? (json[2] as num).toDouble() : 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StrokePoint &&
      other.position == position &&
      other.pressure == pressure;

  @override
  int get hashCode => Object.hash(position, pressure);
}

/// A single freehand mark: pen ink or highlighter.
class Stroke {
  const Stroke({
    required this.id,
    required this.scoreId,
    required this.pageIndex,
    required this.layerId,
    required this.kind,
    required this.colorValue,
    required this.widthFraction,
    required this.points,
    required this.createdAt,
  });

  final String id;
  final String scoreId;

  /// Zero-based position of the page this stroke lives on.
  final int pageIndex;

  final String layerId;
  final AnnotationKind kind;

  /// Packed ARGB. Stored as an int so the model layer stays free of Flutter's
  /// `Color`.
  final int colorValue;

  /// Stroke width as a fraction of page width, so a mark keeps its visual
  /// weight relative to the staff no matter how the page is rendered.
  final double widthFraction;

  final List<StrokePoint> points;
  final DateTime createdAt;

  Stroke copyWith({
    String? id,
    int? pageIndex,
    String? layerId,
    AnnotationKind? kind,
    int? colorValue,
    double? widthFraction,
    List<StrokePoint>? points,
  }) {
    return Stroke(
      id: id ?? this.id,
      scoreId: scoreId,
      pageIndex: pageIndex ?? this.pageIndex,
      layerId: layerId ?? this.layerId,
      kind: kind ?? this.kind,
      colorValue: colorValue ?? this.colorValue,
      widthFraction: widthFraction ?? this.widthFraction,
      points: points ?? this.points,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'scoreId': scoreId,
    'pageIndex': pageIndex,
    'layerId': layerId,
    'kind': kind.name,
    'colorValue': colorValue,
    'widthFraction': widthFraction,
    'createdAt': createdAt.toIso8601String(),
    'points': points.map((p) => p.toJson()).toList(growable: false),
  };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      id: json['id'] as String,
      scoreId: json['scoreId'] as String,
      pageIndex: (json['pageIndex'] as num).toInt(),
      layerId: json['layerId'] as String,
      kind: AnnotationKind.fromName(json['kind'] as String),
      colorValue: (json['colorValue'] as num).toInt(),
      widthFraction: (json['widthFraction'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      points: (json['points'] as List<dynamic>)
          .map((p) => StrokePoint.fromJson(p as List<dynamic>))
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Stroke &&
      other.id == id &&
      other.scoreId == scoreId &&
      other.pageIndex == pageIndex &&
      other.layerId == layerId &&
      other.kind == kind &&
      other.colorValue == colorValue &&
      other.widthFraction == widthFraction &&
      other.createdAt == createdAt &&
      _pointsEqual(other.points, points);

  static bool _pointsEqual(List<StrokePoint> a, List<StrokePoint> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    scoreId,
    pageIndex,
    layerId,
    kind,
    colorValue,
    widthFraction,
    createdAt,
    Object.hashAll(points),
  );
}
