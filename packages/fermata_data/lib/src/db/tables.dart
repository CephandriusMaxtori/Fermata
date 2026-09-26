import 'package:drift/drift.dart';

/// Page count sentinel used before a document has actually been opened.
const int kUnknownPageCount = 0;

@DataClassName('ScoreRow')
class Scores extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 512)();
  TextColumn get composer => text().withLength(max: 512).withDefault(const Constant(''))();
  DateTimeColumn get dateAdded => dateTime()();
  DateTimeColumn get lastOpened => dateTime().nullable()();
  IntColumn get pageCount => integer().withDefault(const Constant(kUnknownPageCount))();

  /// SHA-256 of the primary source file, for exact duplicate detection.
  ///
  /// Kept on the row rather than in a side table so the import path can check a
  /// candidate with a single indexed lookup.
  TextColumn get contentHash => text().nullable()();

  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get linkedMidiId => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One page of a score, backed by a PDF page or an image file.
@DataClassName('ScorePageRow')
class ScorePages extends Table {
  TextColumn get id => text()();
  TextColumn get scoreId => text().references(Scores, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageIndex => integer()();

  /// One of the [PageSourceKind] names.
  TextColumn get kind => text()();

  /// Path relative to the owning score's source directory.
  TextColumn get sourcePath => text()();

  /// One-based page number within the source PDF; null for bitmaps.
  IntColumn get pdfPageNumber => integer().nullable()();

  RealColumn get widthPt => real().nullable()();
  RealColumn get heightPt => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE (score_id, page_index)',
  ];
}

/// A named, independently toggleable set of annotations.
@DataClassName('AnnotationLayerRow')
class AnnotationLayers extends Table {
  TextColumn get id => text()();
  TextColumn get scoreId => text().references(Scores, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 256)();
  BoolColumn get visible => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A single annotation mark.
///
/// Ink geometry is stored as a compact JSON array of coordinates rather than as
/// a row per point: a stroke is only meaningful as a whole, and one row per
/// point would make deleting or reordering a stroke a multi-row operation.
@DataClassName('AnnotationRow')
class Annotations extends Table {
  TextColumn get id => text()();
  TextColumn get scoreId => text().references(Scores, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageIndex => integer()();
  TextColumn get layerId =>
      text().references(AnnotationLayers, #id, onDelete: KeyAction.cascade)();

  /// One of the [AnnotationKind] names.
  TextColumn get kind => text()();

  IntColumn get colorValue => integer()();
  RealColumn get widthFraction => real()();

  /// Flat coordinate list; see [AnnotationPointsCodec] for the shape.
  TextColumn get pointsJson => text()();

  /// Present only for non-ink annotations (text, stamp).
  TextColumn get textContent => text().nullable()();

  RealColumn get anchorX => real().nullable()();
  RealColumn get anchorY => real().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE (score_id, page_index, layer_id, id)',
  ];
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 128)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE (name COLLATE NOCASE)'];
}

@DataClassName('ScoreTagRow')
class ScoreTags extends Table {
  TextColumn get scoreId => text().references(Scores, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {scoreId, tagId};
}

@DataClassName('SetlistRow')
class Setlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 256)();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Join table carrying the setlist's performance order.
@DataClassName('SetlistEntryRow')
class SetlistEntries extends Table {
  TextColumn get setlistId =>
      text().references(Setlists, #id, onDelete: KeyAction.cascade)();
  TextColumn get scoreId => text().references(Scores, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {setlistId, scoreId};

  @override
  List<String> get customConstraints => [
    'UNIQUE (setlist_id, position)',
  ];
}

@DataClassName('MidiFileRow')
class MidiFiles extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 512)();
  TextColumn get filePath => text()();
  DateTimeColumn get addedAt => dateTime()();
  TextColumn get linkedScoreId =>
      text().nullable().references(Scores, #id, onDelete: KeyAction.setNull)();

  /// Serialized [PlaybackEdits], so the app and the web UI share one definition
  /// of what an edit is.
  TextColumn get editsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RecordingRow')
class Recordings extends Table {
  TextColumn get id => text()();
  TextColumn get scoreId => text().references(Scores, #id, onDelete: KeyAction.cascade)();

  /// Path relative to the score's recordings directory.
  TextColumn get filePath => text()();
  DateTimeColumn get recordedAt => dateTime()();
  IntColumn get durationMs => integer()();

  /// One of the [RecordingSource] names.
  TextColumn get source => text()();
  TextColumn get label => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PedalMappingRow')
class PedalMappings extends Table {
  TextColumn get id => text()();
  TextColumn get keyLabel => text()();
  IntColumn get platformKeyCode => integer().nullable()();

  /// One of the [PedalAction] names.
  TextColumn get action => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
