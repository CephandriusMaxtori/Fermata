import '../models/midi_file.dart';
import '../models/pedal_mapping.dart';
import '../models/recording.dart';
import '../models/setlist.dart';
import '../models/tag.dart';

/// Tags and setlists.
///
/// Kept separate from [ScoreRepository] because setlist ordering and tag
/// membership have their own invariants and are edited from different screens.
abstract interface class OrganizationRepository {
  Stream<List<Tag>> watchTags();

  Future<List<Tag>> getTags();

  /// Creates the tag if it does not exist, otherwise returns the existing one.
  Future<Tag> ensureTag(String name);

  Future<void> renameTag(Tag tag, String name);

  Future<void> deleteTag(String tagId);

  Future<void> setScoreTags(String scoreId, Set<String> tagIds);

  Future<Set<String>> getScoreTagIds(String scoreId);

  Stream<List<Setlist>> watchSetlists();

  Future<Setlist> createSetlist(String name);

  Future<void> renameSetlist(Setlist setlist, String name);

  Future<void> deleteSetlist(String setlistId);

  /// Entries in stored order.
  Future<List<SetlistEntry>> getEntries(String setlistId);

  Stream<List<SetlistEntry>> watchEntries(String setlistId);

  /// Appends a score to the end of the setlist.
  Future<void> addScoreToSetlist(String setlistId, String scoreId);

  /// Moves a score to [newPosition], shifting the rest.
  Future<void> moveSetlistEntry(String setlistId, String scoreId, int newPosition);

  Future<void> removeScoreFromSetlist(String setlistId, String scoreId);
}

/// MIDI files and their playback edits.
abstract interface class PlaybackRepository {
  Stream<List<MidiFile>> watchMidiFiles();

  Future<List<MidiFile>> getMidiFiles();

  Future<MidiFile?> getMidiFile(String id);

  Future<MidiFile> createMidiFile({
    required String title,
    required String relativePath,
    String? linkedScoreId,
  });

  Future<void> linkToScore(String midiFileId, String? scoreId);

  /// Persists edits made by either the app or the companion web UI.
  Future<void> saveEdits(String midiFileId, PlaybackEdits edits);
}

/// Practice recordings for a score.
abstract interface class RecordingRepository {
  Stream<List<Recording>> watchRecordings(String scoreId);

  Future<List<Recording>> getRecordings(String scoreId);

  Future<Recording> createRecording({
    required String scoreId,
    required String relativePath,
    required Duration duration,
    required RecordingSource source,
    String? label,
  });

  Future<void> deleteRecording(String recordingId);
}

/// Configurable page-turn pedal bindings.
abstract interface class PedalMappingRepository {
  Future<List<PedalMapping>> getMappings();

  Stream<List<PedalMapping>> watchMappings();

  Future<void> saveMapping(PedalMapping mapping);

  /// Restores the shipped arrow-key and media-key defaults.
  Future<void> resetToDefaults();
}
