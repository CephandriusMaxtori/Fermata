import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:fermata_data/fermata_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'pdfrx_page_counter.dart';

/// The library root, created on first launch.
///
/// Everything Fermata owns lives under one directory, so backup and restore
/// have a single thing to copy.
final libraryRootProvider = FutureProvider<Directory>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(documents.path, 'fermata'));
  await root.create(recursive: true);
  return root;
});

final fermataLayoutProvider = FutureProvider<FermataLayout>((ref) async {
  final root = await ref.watch(libraryRootProvider.future);
  final layout = FermataLayout(root);
  await layout.ensureDirectories();
  return layout;
});

/// The library database.
///
/// Foreign keys are switched on per connection via [DriftNativeOptions.setup]
/// rather than in the migration, because a pragma set on one connection does
/// not carry over to the next one the pool opens, and the cascade deletes that
/// keep orphaned pages and annotations from accumulating depend on it.
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final root = await ref.watch(libraryRootProvider.future);

  final database = AppDatabase(
    driftDatabase(
      name: 'fermata',
      native: DriftNativeOptions(
        databaseDirectory: () async => p.join(root.path, 'db'),
        setup: _enableForeignKeys,
      ),
    ),
  );

  ref.onDispose(database.close);
  return database;
});

void _enableForeignKeys(CommonDatabase db) {
  db.execute('PRAGMA foreign_keys = ON');
}

final fileStoreProvider = FutureProvider<FileStore>((ref) async {
  final layout = await ref.watch(fermataLayoutProvider.future);
  return FileStore(layout);
});

final scoreRepositoryProvider = FutureProvider<ScoreRepository>((ref) async {
  return DriftScoreRepository(
    await ref.watch(databaseProvider.future),
    fileStore: await ref.watch(fileStoreProvider.future),
  );
});

final annotationRepositoryProvider = FutureProvider<AnnotationRepository>((
  ref,
) async {
  return DriftAnnotationRepository(await ref.watch(databaseProvider.future));
});

final organizationRepositoryProvider = FutureProvider<OrganizationRepository>((
  ref,
) async {
  return DriftOrganizationRepository(await ref.watch(databaseProvider.future));
});

final tagsProvider = StreamProvider.autoDispose<List<Tag>>((ref) async* {
  final repo = await ref.watch(organizationRepositoryProvider.future);
  yield* repo.watchTags();
});

final setlistsProvider = StreamProvider.autoDispose<List<Setlist>>((ref) async* {
  final repo = await ref.watch(organizationRepositoryProvider.future);
  yield* repo.watchSetlists();
});

final setlistEntriesProvider = StreamProvider.autoDispose.family<List<SetlistEntry>, String>((ref, setlistId) async* {
  final repo = await ref.watch(organizationRepositoryProvider.future);
  yield* repo.watchEntries(setlistId);
});

final playbackRepositoryProvider = FutureProvider<PlaybackRepository>((ref) async {
  return DriftPlaybackRepository(await ref.watch(databaseProvider.future));
});

final recordingRepositoryProvider = FutureProvider<RecordingRepository>((
  ref,
) async {
  return DriftRecordingRepository(await ref.watch(databaseProvider.future));
});

final pedalMappingRepositoryProvider = FutureProvider<PedalMappingRepository>((
  ref,
) async {
  return DriftPedalMappingRepository(await ref.watch(databaseProvider.future));
});

final importServiceProvider = FutureProvider<ImportService>((ref) async {
  final service = ImportService(
    scoreRepository: await ref.watch(scoreRepositoryProvider.future),
    fileStore: await ref.watch(fileStoreProvider.future),
    pdfPageCounter: PdfrxPdfPageCounter(),
  );
  ref.onDispose(service.dispose);
  return service;
});
