/// A loose label for grouping scores, e.g. "Warm-ups".
///
/// Distinct from a [Setlist]: tags are unordered and a score can have many.
class Tag {
  const Tag({required this.id, required this.name, this.colorValue});

  final String id;
  final String name;
  final int? colorValue;

  Tag copyWith({String? name, int? colorValue}) =>
      Tag(id: id, name: name ?? this.name, colorValue: colorValue ?? this.colorValue);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
  };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: (json['colorValue'] as num?)?.toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is Tag && other.id == id && other.name == name && other.colorValue == colorValue;

  @override
  int get hashCode => Object.hash(id, name, colorValue);
}
