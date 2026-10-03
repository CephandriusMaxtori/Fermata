/// Pure Dart domain layer for Fermata.
///
/// This library intentionally has no dependency on Flutter, `dart:io` or any
/// database. Everything here is safe to compile for the web, which is what lets
/// the future companion web UI share the same models, geometry and duplicate
/// rules as the Android app rather than reimplementing them.
library;

export 'src/geometry/normalized_point.dart';
export 'src/geometry/normalized_rect.dart';
export 'src/geometry/page_geometry.dart';
export 'src/geometry/stroke.dart';
export 'src/geometry/stroke_conditioner.dart';
export 'src/import/duplicate_detection.dart';
export 'src/measure/bar_cursor.dart';
export 'src/measure/bar_detector.dart';
export 'src/measure/bar_layout.dart';
export 'src/midi/midi_pitch.dart';
export 'src/midi/midi_score.dart';
export 'src/midi/smf/byte_cursor.dart';
export 'src/midi/smf/smf_midi_score.dart';
export 'src/midi/smf/smf_parser.dart';
export 'src/models/annotation_layer.dart';
export 'src/models/midi_file.dart';
export 'src/models/pedal_mapping.dart';
export 'src/models/recording.dart';
export 'src/models/score.dart';
export 'src/models/score_page.dart';
export 'src/models/setlist.dart';
export 'src/models/tag.dart';
export 'src/repositories/organization_repositories.dart';
export 'src/repositories/repositories.dart';
