/// A piece of sheet music in the library.
class Score {
  const Score({
    required this.id,
    required this.title,
    required this.composer,
    required this.dateAdded,
    required this.pageCount,
    this.lastOpened,
    this.contentHash,
    this.thumbnailPath,
    this.linkedMidiId,
    this.notes,
  });

  final String id;
  final String title;
  final String composer;
  final DateTime dateAdded;

  /// Updated every time the score is opened, for the "recently opened" sort.
  final DateTime? lastOpened;

  /// Denormalized count so the library list can render without loading pages.
  final int pageCount;

  /// SHA-256 of the primary source file. Exact-duplicate detection.
  final String? contentHash;

  /// Relative path to the cached page-1 thumbnail, if generated.
  final String? thumbnailPath;

  final String? linkedMidiId;
  final String? notes;

  bool get wasNeverOpened => lastOpened == null;

  Score copyWith({
    String? title,
    String? composer,
    DateTime? lastOpened,
    int? pageCount,
    String? contentHash,
    String? thumbnailPath,
    String? linkedMidiId,
    String? notes,
  }) => Score(
    id: id,
    title: title ?? this.title,
    composer: composer ?? this.composer,
    dateAdded: dateAdded,
    lastOpened: lastOpened ?? this.lastOpened,
    pageCount: pageCount ?? this.pageCount,
    contentHash: contentHash ?? this.contentHash,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    linkedMidiId: linkedMidiId ?? this.linkedMidiId,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'composer': composer,
    'dateAdded': dateAdded.toIso8601String(),
    'lastOpened': lastOpened?.toIso8601String(),
    'pageCount': pageCount,
    'contentHash': contentHash,
    'thumbnailPath': thumbnailPath,
    'linkedMidiId': linkedMidiId,
    'notes': notes,
  };

  factory Score.fromJson(Map<String, dynamic> json) => Score(
    id: json['id'] as String,
    title: json['title'] as String,
    composer: json['composer'] as String,
    dateAdded: DateTime.parse(json['dateAdded'] as String),
    lastOpened: json['lastOpened'] == null
        ? null
        : DateTime.parse(json['lastOpened'] as String),
    pageCount: (json['pageCount'] as num).toInt(),
    contentHash: json['contentHash'] as String?,
    thumbnailPath: json['thumbnailPath'] as String?,
    linkedMidiId: json['linkedMidiId'] as String?,
    notes: json['notes'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Score &&
      other.id == id &&
      other.title == title &&
      other.composer == composer &&
      other.dateAdded == dateAdded &&
      other.lastOpened == lastOpened &&
      other.pageCount == pageCount &&
      other.contentHash == contentHash &&
      other.thumbnailPath == thumbnailPath &&
      other.linkedMidiId == linkedMidiId &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    composer,
    dateAdded,
    lastOpened,
    pageCount,
    contentHash,
    thumbnailPath,
    linkedMidiId,
    notes,
  );
}

/// The fields the library list needs in order to sort and filter.
enum ScoreSort {
  recentlyOpened,
  titleAscending,
  composerAscending,
  dateAddedDescending;

  static ScoreSort fromName(String name) => ScoreSort.values.firstWhere(
    (sort) => sort.name == name,
    orElse: () => ScoreSort.recentlyOpened,
  );
}

/// How the library screen is currently filtering.
class ScoreQuery {
  const ScoreQuery({
    this.searchText = '',
    this.tagIds = const {},
    this.setlistId,
    this.sort = ScoreSort.recentlyOpened,
  });

  final String searchText;
  final Set<String> tagIds;

  /// When set, restricts results to one setlist in its stored order.
  final String? setlistId;

  final ScoreSort sort;

  bool get hasFilters =>
      searchText.trim().isNotEmpty ||
      tagIds.isNotEmpty ||
      setlistId != null;

  ScoreQuery copyWith({
    String? searchText,
    Set<String>? tagIds,
    String? setlistId,
    bool clearSetlist = false,
    ScoreSort? sort,
  }) => ScoreQuery(
    searchText: searchText ?? this.searchText,
    tagIds: tagIds ?? this.tagIds,
    setlistId: clearSetlist ? null : (setlistId ?? this.setlistId),
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is ScoreQuery &&
      other.searchText == searchText &&
      other.setlistId == setlistId &&
      other.sort == sort &&
      other.tagIds.length == tagIds.length &&
      other.tagIds.containsAll(tagIds);

  @override
  int get hashCode => Object.hash(
    searchText,
    Object.hashAllUnordered(tagIds),
    setlistId,
    sort,
  );
}
