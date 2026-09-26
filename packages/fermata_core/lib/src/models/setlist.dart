/// An ordered list of scores for a specific performance.
///
/// Order is the point of a setlist and is preserved exactly, unlike tags.
class Setlist {
  const Setlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final String? notes;

  Setlist copyWith({String? name, String? notes}) => Setlist(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
  };

  factory Setlist.fromJson(Map<String, dynamic> json) => Setlist(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    notes: json['notes'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Setlist &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(id, name, createdAt, notes);
}

/// One score's position in a setlist.
class SetlistEntry {
  const SetlistEntry({
    required this.setlistId,
    required this.scoreId,
    required this.position,
  });

  final String setlistId;
  final String scoreId;

  /// Zero-based rank within the setlist.
  final int position;

  SetlistEntry copyWith({int? position}) =>
      SetlistEntry(setlistId: setlistId, scoreId: scoreId, position: position ?? this.position);

  Map<String, dynamic> toJson() => {
    'setlistId': setlistId,
    'scoreId': scoreId,
    'position': position,
  };

  factory SetlistEntry.fromJson(Map<String, dynamic> json) => SetlistEntry(
    setlistId: json['setlistId'] as String,
    scoreId: json['scoreId'] as String,
    position: (json['position'] as num).toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is SetlistEntry &&
      other.setlistId == setlistId &&
      other.scoreId == scoreId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(setlistId, scoreId, position);
}

/// Reorders [entries] so that [from] and [to] swap ranks, returning a new
/// list. Out-of-range indices are returned untouched.
///
/// Lives in the model layer so the reorder rule is unit testable and so the
/// web UI can reuse the exact same ordering semantics later.
List<SetlistEntry> reorderSetlistEntries(
  List<SetlistEntry> entries, {
  required int from,
  required int to,
}) {
  if (from < 0 || from >= entries.length) return entries;
  if (to < 0 || to >= entries.length) return entries;
  if (from == to) return entries;

  final sorted = List<SetlistEntry>.of(entries)
    ..sort((a, b) => a.position.compareTo(b.position));
  final moved = sorted.removeAt(from);
  sorted.insert(to, moved);

  return [
    for (var i = 0; i < sorted.length; i++)
      sorted[i].copyWith(position: i),
  ];
}
