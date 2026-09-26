import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fermata_core/fermata_core.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import '../db/app_database.dart';
import 'annotation_repository.dart';

/// drift-backed [OrganizationRepository] for tags and setlists.
class DriftOrganizationRepository implements OrganizationRepository {
  DriftOrganizationRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<Tag>> watchTags() {
    final query = _database.select(_database.tags)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch().map(
      (rows) => rows
          .map((row) => Tag(id: row.id, name: row.name, colorValue: null))
          .toList(growable: false),
    );
  }

  @override
  Future<List<Tag>> getTags() async {
    final query = _database.select(_database.tags)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    final rows = await query.get();
    return rows
        .map((row) => Tag(id: row.id, name: row.name, colorValue: null))
        .toList(growable: false);
  }

  @override
  Future<Tag> ensureTag(String name) async {
    final existing = await (_database.select(
      _database.tags,
    )..where((t) => t.name.equals(name))).getSingleOrNull();
    if (existing != null) {
      return Tag(id: existing.id, name: existing.name);
    }

    final tag = Tag(id: newId(), name: name);
    try {
      await _database.into(_database.tags).insert(
        TagsCompanion.insert(id: tag.id, name: tag.name),
      );
    } on SqliteException {
      // The unique index is case-insensitive, so "Jazz" and "jazz" collide
      // here even though the equality lookup above missed. Re-read rather than
      // surfacing a constraint error to the caller.
      final raced = await (_database.select(
        _database.tags,
      )..where((t) => t.name.equals(name))).getSingleOrNull();
      if (raced != null) {
        return Tag(id: raced.id, name: raced.name);
      }
      rethrow;
    }
    return tag;
  }

  @override
  Future<void> renameTag(Tag tag, String name) async {
    await (_database.update(_database.tags)..where((t) => t.id.equals(tag.id)))
        .write(TagsCompanion(name: Value(name)));
  }

  @override
  Future<void> deleteTag(String tagId) async {
    await (_database.delete(_database.tags)..where((t) => t.id.equals(tagId)))
        .go();
  }

  @override
  Future<void> setScoreTags(String scoreId, Set<String> tagIds) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.scoreTags,
      )..where((t) => t.scoreId.equals(scoreId))).go();
      if (tagIds.isEmpty) return;
      await _database.batch(
        (batch) => batch.insertAll(
          _database.scoreTags,
          [
            for (final tagId in tagIds)
              ScoreTagsCompanion.insert(scoreId: scoreId, tagId: tagId),
          ],
        ),
      );
    });
  }

  @override
  Future<Set<String>> getScoreTagIds(String scoreId) async {
    final rows = await (_database.select(
      _database.scoreTags,
    )..where((t) => t.scoreId.equals(scoreId))).get();
    return rows.map((row) => row.tagId).toSet();
  }

  @override
  Stream<List<Setlist>> watchSetlists() {
    final query = _database.select(_database.setlists)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => Setlist(
              id: row.id,
              name: row.name,
              createdAt: row.createdAt,
              notes: row.notes,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<Setlist> createSetlist(String name) async {
    final setlist = Setlist(
      id: newId(),
      name: name,
      createdAt: DateTime.now().toUtc(),
    );
    await _database.into(_database.setlists).insert(
      SetlistsCompanion.insert(
        id: setlist.id,
        name: setlist.name,
        createdAt: setlist.createdAt,
      ),
    );
    return setlist;
  }

  @override
  Future<void> renameSetlist(Setlist setlist, String name) async {
    await (_database.update(
      _database.setlists,
    )..where((t) => t.id.equals(setlist.id))).write(
      SetlistsCompanion(name: Value(name)),
    );
  }

  @override
  Future<void> deleteSetlist(String setlistId) async {
    await (_database.delete(
      _database.setlists,
    )..where((t) => t.id.equals(setlistId))).go();
  }

  @override
  Future<List<SetlistEntry>> getEntries(String setlistId) => _entries(setlistId);

  @override
  Stream<List<SetlistEntry>> watchEntries(String setlistId) {
    final query = _database.select(_database.setlistEntries)
      ..where((t) => t.setlistId.equals(setlistId))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => SetlistEntry(
              setlistId: row.setlistId,
              scoreId: row.scoreId,
              position: row.position,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> addScoreToSetlist(String setlistId, String scoreId) async {
    await _database.transaction(() async {
      final already = await (_database.select(_database.setlistEntries)
            ..where(
              (t) =>
                  t.setlistId.equals(setlistId) & t.scoreId.equals(scoreId),
            ))
          .getSingleOrNull();
      if (already != null) return;

      final count = await _positionCount(setlistId);
      await _database.into(_database.setlistEntries).insert(
        SetlistEntriesCompanion.insert(
          setlistId: setlistId,
          scoreId: scoreId,
          position: count,
        ),
      );
    });
  }

  @override
  Future<void> moveSetlistEntry(
    String setlistId,
    String scoreId,
    int newPosition,
  ) async {
    await _database.transaction(() async {
      final entries = await _entries(setlistId);
      final from = entries.indexWhere((e) => e.scoreId == scoreId);
      if (from < 0) return;

      final reordered = reorderSetlistEntries(
        entries,
        from: from,
        to: newPosition,
      );

      // Positions are unique per setlist, so they cannot be written directly:
      // moving the last entry to the front would need it to take position 0
      // while the current occupant of 0 still holds it. Parking every affected
      // row in a disjoint negative range first makes the second pass
      // collision-free.
      const stagingBase = -1000000;
      for (var i = 0; i < reordered.length; i++) {
        await (_database.update(_database.setlistEntries)..where(
              (t) =>
                  t.setlistId.equals(setlistId) &
                  t.scoreId.equals(reordered[i].scoreId),
            ))
            .write(
              SetlistEntriesCompanion(
                position: Value(stagingBase - i),
              ),
            );
      }

      for (var i = 0; i < reordered.length; i++) {
        await (_database.update(_database.setlistEntries)..where(
              (t) =>
                  t.setlistId.equals(setlistId) &
                  t.scoreId.equals(reordered[i].scoreId),
            ))
            .write(
              SetlistEntriesCompanion(position: Value(reordered[i].position)),
            );
      }
    });
  }

  @override
  Future<void> removeScoreFromSetlist(String setlistId, String scoreId) async {
    await _database.transaction(() async {
      await (_database.delete(_database.setlistEntries)..where(
            (t) =>
                t.setlistId.equals(setlistId) & t.scoreId.equals(scoreId),
          ))
          .go();

      final entries = await _entries(setlistId);
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].position == i) continue;
        await (_database.update(_database.setlistEntries)..where(
              (t) =>
                  t.setlistId.equals(setlistId) &
                  t.scoreId.equals(entries[i].scoreId),
            ))
            .write(
              SetlistEntriesCompanion(
                position: Value(-1000000 - i),
              ),
            );
      }
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].position == i) continue;
        await (_database.update(_database.setlistEntries)..where(
              (t) =>
                  t.setlistId.equals(setlistId) &
                  t.scoreId.equals(entries[i].scoreId),
            ))
            .write(SetlistEntriesCompanion(position: Value(i)));
      }
    });
  }

  Future<List<SetlistEntry>> _entries(String setlistId) async {
    final query = _database.select(_database.setlistEntries)
      ..where((t) => t.setlistId.equals(setlistId))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => SetlistEntry(
            setlistId: row.setlistId,
            scoreId: row.scoreId,
            position: row.position,
          ),
        )
        .toList(growable: false);
  }

  Future<int> _positionCount(String setlistId) async {
    final expression = _database.setlistEntries.setlistId.count();
    final query = _database.selectOnly(_database.setlistEntries)
      ..addColumns([expression])
      ..where(_database.setlistEntries.setlistId.equals(setlistId));
    final row = await query.getSingle();
    return row.read(expression) ?? 0;
  }
}

/// drift-backed [PlaybackRepository] for MIDI files and their edits.
class DriftPlaybackRepository implements PlaybackRepository {
  DriftPlaybackRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<MidiFile>> watchMidiFiles() {
    final query = _database.select(_database.midiFiles)
      ..orderBy([(t) => OrderingTerm.asc(t.title)]);
    return query.watch().map(
      (rows) => rows.map(_toMidi).toList(growable: false),
    );
  }

  @override
  Future<List<MidiFile>> getMidiFiles() async {
    final query = _database.select(_database.midiFiles)
      ..orderBy([(t) => OrderingTerm.asc(t.title)]);
    final rows = await query.get();
    return rows.map(_toMidi).toList(growable: false);
  }

  @override
  Future<MidiFile?> getMidiFile(String id) async {
    final row = await (_database.select(
      _database.midiFiles,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toMidi(row);
  }

  @override
  Future<MidiFile> createMidiFile({
    required String title,
    required String relativePath,
    String? linkedScoreId,
  }) async {
    final midi = MidiFile(
      id: newId(),
      title: title,
      filePath: relativePath,
      addedAt: DateTime.now().toUtc(),
      linkedScoreId: linkedScoreId,
    );
    await _database.into(_database.midiFiles).insert(
      MidiFilesCompanion.insert(
        id: midi.id,
        title: midi.title,
        filePath: midi.filePath,
        addedAt: midi.addedAt,
        linkedScoreId: Value(midi.linkedScoreId),
        editsJson: Value(jsonEncode(midi.edits.toJson())),
      ),
    );
    return midi;
  }

  @override
  Future<void> linkToScore(String midiFileId, String? scoreId) async {
    await (_database.update(
      _database.midiFiles,
    )..where((t) => t.id.equals(midiFileId))).write(
      MidiFilesCompanion(linkedScoreId: Value(scoreId)),
    );
  }

  @override
  Future<void> saveEdits(String midiFileId, PlaybackEdits edits) async {
    await (_database.update(
      _database.midiFiles,
    )..where((t) => t.id.equals(midiFileId))).write(
      MidiFilesCompanion(editsJson: Value(jsonEncode(edits.toJson()))),
    );
  }

  MidiFile _toMidi(MidiFileRow row) => MidiFile(
    id: row.id,
    title: row.title,
    filePath: row.filePath,
    addedAt: row.addedAt,
    linkedScoreId: row.linkedScoreId,
    edits: _decodeEdits(row.editsJson),
  );

  static PlaybackEdits _decodeEdits(String source) {
    if (source.isEmpty) return const PlaybackEdits();
    try {
      return PlaybackEdits.fromJson(jsonDecode(source) as Map<String, dynamic>);
    } on FormatException {
      // A malformed blob should not make the file unplayable; fall back to the
      // file's own defaults.
      return const PlaybackEdits();
    }
  }
}

/// drift-backed [RecordingRepository].
class DriftRecordingRepository implements RecordingRepository {
  DriftRecordingRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<Recording>> watchRecordings(String scoreId) {
    final query = _database.select(_database.recordings)
      ..where((t) => t.scoreId.equals(scoreId))
      ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toRecording).toList(growable: false),
    );
  }

  @override
  Future<List<Recording>> getRecordings(String scoreId) async {
    final query = _database.select(_database.recordings)
      ..where((t) => t.scoreId.equals(scoreId))
      ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)]);
    final rows = await query.get();
    return rows.map(_toRecording).toList(growable: false);
  }

  @override
  Future<Recording> createRecording({
    required String scoreId,
    required String relativePath,
    required Duration duration,
    required RecordingSource source,
    String? label,
  }) async {
    final recording = Recording(
      id: newId(),
      scoreId: scoreId,
      filePath: relativePath,
      recordedAt: DateTime.now().toUtc(),
      duration: duration,
      source: source,
      label: label,
    );
    await _database.into(_database.recordings).insert(
      RecordingsCompanion.insert(
        id: recording.id,
        scoreId: recording.scoreId,
        filePath: recording.filePath,
        recordedAt: recording.recordedAt,
        durationMs: recording.duration.inMilliseconds,
        source: recording.source.name,
        label: Value(recording.label),
      ),
    );
    return recording;
  }

  @override
  Future<void> deleteRecording(String recordingId) async {
    await (_database.delete(
      _database.recordings,
    )..where((t) => t.id.equals(recordingId))).go();
  }

  Recording _toRecording(RecordingRow row) => Recording(
    id: row.id,
    scoreId: row.scoreId,
    filePath: row.filePath,
    recordedAt: row.recordedAt,
    duration: Duration(milliseconds: row.durationMs),
    source: RecordingSource.fromName(row.source),
    label: row.label,
  );
}

/// drift-backed [PedalMappingRepository].
class DriftPedalMappingRepository implements PedalMappingRepository {
  DriftPedalMappingRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<PedalMapping>> getMappings() async {
    final rows = await _database.select(_database.pedalMappings).get();
    return rows
        .map(
          (row) => PedalMapping(
            id: row.id,
            keyLabel: row.keyLabel,
            platformKeyCode: row.platformKeyCode,
            action: PedalAction.fromName(row.action),
            enabled: row.enabled,
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<PedalMapping>> watchMappings() {
    return _database
        .select(_database.pedalMappings)
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => PedalMapping(
                  id: row.id,
                  keyLabel: row.keyLabel,
                  platformKeyCode: row.platformKeyCode,
                  action: PedalAction.fromName(row.action),
                  enabled: row.enabled,
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveMapping(PedalMapping mapping) async {
    await _database.into(_database.pedalMappings).insertOnConflictUpdate(
      PedalMappingsCompanion.insert(
        id: mapping.id,
        keyLabel: mapping.keyLabel,
        platformKeyCode: Value(mapping.platformKeyCode),
        action: mapping.action.name,
        enabled: Value(mapping.enabled),
      ),
    );
  }

  @override
  Future<void> resetToDefaults() async {
    await _database.transaction(() async {
      await _database.delete(_database.pedalMappings).go();
      await _database.batch(
        (batch) => batch.insertAll(
          _database.pedalMappings,
          [
            for (final mapping in kDefaultPedalMappings)
              PedalMappingsCompanion.insert(
                id: mapping.id,
                keyLabel: mapping.keyLabel,
                action: mapping.action.name,
              ),
          ],
        ),
      );
    });
  }
}
