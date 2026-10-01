import 'dart:io';

import 'package:drift/native.dart';
import 'package:fermata_data/fermata_data.dart';

/// Creates an in-memory database configured the way the app configures it.
///
/// Foreign keys are the whole point of this helper. `NativeDatabase.memory()` leaves
/// `PRAGMA foreign_keys` off, which is sqlite's default, so every `ON DELETE CASCADE`
/// in the schema silently does nothing and orphaned pages, layers and strokes
/// accumulate. The app switches the pragma on per connection through
/// `DriftNativeOptions.setup` (see `app/lib/src/providers/library_providers.dart`), so a
/// test that constructs the database any other way is not testing what ships.
///
/// Use this everywhere instead of `AppDatabase(NativeDatabase.memory())`.
AppDatabase openTestDatabase() {
  return AppDatabase(
    NativeDatabase.memory(
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
}

/// A temporary on-disk root plus the collaborators built over it.
///
/// Mirrors `makeLibrary()` in `storage_test.dart`; used by the repository and
/// import suites that need real files rather than only database rows.
typedef TestHarness = ({
  AppDatabase database,
  FermataLayout layout,
  FileStore fileStore,
  Directory root,
});

TestHarness createHarness() {
  final root = Directory.systemTemp.createTempSync('fermata_test_');
  final layout = FermataLayout(root);
  layout.ensureDirectories();
  return (
    database: openTestDatabase(),
    layout: layout,
    fileStore: FileStore(layout),
    root: root,
  );
}