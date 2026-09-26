import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// The library database.
///
/// The [QueryExecutor] is supplied by the host so this package stays free of
/// Flutter and can be tested against an in-memory database.
///
/// The whole v1 schema lands in version 1, including the tables the later
/// milestones need (MIDI, recordings, setlists, pedal mappings). Adding those
/// as they are built would mean a migration per feature; declaring them now
/// means later work is feature code rather than schema churn.
@DriftDatabase(
  tables: [
    Scores,
    ScorePages,
    AnnotationLayers,
    Annotations,
    Tags,
    ScoreTags,
    Setlists,
    SetlistEntries,
    MidiFiles,
    Recordings,
    PedalMappings,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Foreign keys are off by default in SQLite, and the cascade deletes that
      // keep orphaned pages, layers and annotations from accumulating depend
      // on them.
      await customStatement('PRAGMA foreign_keys = ON');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
