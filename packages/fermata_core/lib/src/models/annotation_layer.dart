/// A named, independently toggleable set of annotations on one score.
///
/// Layers exist so a "Teacher's edits" layer and a "My fingering" layer can
/// live on the same page without being flattened into one undifferentiated set
/// of marks.
class AnnotationLayer {
  const AnnotationLayer({
    required this.id,
    required this.scoreId,
    required this.name,
    required this.visible,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String scoreId;
  final String name;
  final bool visible;
  final int sortOrder;
  final DateTime createdAt;

  AnnotationLayer copyWith({String? name, bool? visible, int? sortOrder}) =>
      AnnotationLayer(
        id: id,
        scoreId: scoreId,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'scoreId': scoreId,
    'name': name,
    'visible': visible,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AnnotationLayer.fromJson(Map<String, dynamic> json) => AnnotationLayer(
    id: json['id'] as String,
    scoreId: json['scoreId'] as String,
    name: json['name'] as String,
    visible: (json['visible'] as bool?) ?? true,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is AnnotationLayer &&
      other.id == id &&
      other.scoreId == scoreId &&
      other.name == name &&
      other.visible == visible &&
      other.sortOrder == sortOrder &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, scoreId, name, visible, sortOrder, createdAt);
}

/// Name given to the layer every score gets on import.
const String kDefaultLayerName = 'My markings';
