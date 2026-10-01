# AGENTS.md

Fermata — an offline-first sheet music keeping app for **Android**. Store, organize, annotate and
practice from your scores. Full design in [`DESIGN.md`](DESIGN.md); live checklist in
[`Todo.md`](Todo.md).

**Android-only.** No `ios/`, `web/`, `linux/`, `macos/` or `windows/` directory exists. iOS is a
later phase (`DESIGN.md` §4, §11.14) — don't generate platform dirs unless asked.

## The MIDI layer (ours, in `fermata_core/lib/src/midi/`)

Three files, one direction:

```
smf/byte_cursor.dart   bounds-checked reads, variable-length quantities
smf/smf_parser.dart   lossless: header, chunks, every event, in file order
smf/smf_midi_score.dart  interpretation: note pairing, tempo/signature maps
midi_score.dart       MidiScore + BaseMidiScore: every query, shared by all impls
midi_pitch.dart       note number -> name, octave, frequency, black key
```

**We wrote the parser deliberately.** No maintained third-party SMF reader exists
in Dart: `flutter_sequencer` and `flutter_midi` declare pre-null-safety SDK
constraints and cannot resolve on Dart 3.13, and `dart_midi_pro` had ~23
downloads/month. Every future MIDI feature — measure mapping, cue points, OMR
output, MIDI writing — lands in this layer.

Rules:

- **Format quirks go in `SmfParser`, never at a call site.** Running status, VLQ,
  zero-velocity note-offs, SMPTE division. All four are handled there and pinned by
  `test/smf_parser_test.dart`.
- **Keep the two layers separate.** `SmfParser` is lossless — it records what the
  file says without interpreting it. `SmfMidiScore` interprets. Mixing them means
  every quirk has to be understood twice.
- **Put queries in `BaseMidiScore`, not an extension.** Extension members are not
  inherited, so a class that `implements MidiScore` would have to re-declare them.
- **We own the parser, not the synth.** The audio engine is FluidSynth either way;
  owning a wrapper around it would buy nothing. The engine sits behind an
  `AudioEngine` interface so it stays swappable.
- **Never hand-roll maths.** `midi_pitch.dart` originally had a hand-written `pow`
  that was wrong for fractional exponents — middle C came out as 220Hz. Use
  `dart:math`; it is core Dart and importing it costs nothing.
- Malformed input throws `MidiFormatException` with a byte offset. Never return a
  partial score: a score silently missing music is worse than one that refuses to
  open.

## Commands

The repo is a single **Dart pub workspace** (`pubspec.yaml:10-13`), so one resolution covers all
three members.

```bash
# 1. FIRST-TIME SETUP — MANDATORY on a fresh clone
dart pub get                     # resolves all 3 members
cd packages/fermata_data
dart run build_runner build --delete-conflicting-outputs
cd ../..

# 2. Analysis
dart analyze                     # root: all members
cd app && flutter analyze       # app needs the Flutter SDK's package config

# 3. Tests
dart test                        # root: runs fermata_core + fermata_data suites
cd packages/fermata_core && dart test
cd packages/fermata_data && dart test
cd app && flutter test          # `dart test` will NOT work in app/

# 4. Run
cd app && flutter run
```

**`build_runner` is not optional.** `app_database.dart:5` is `part 'app_database.g.dart';`, and
`.gitignore:12` ignores `*.g.dart` — all drift codegen is untracked. `AppDatabase extends
_$AppDatabase` will not compile, and `dart test` in `fermata_data` will not run, without it. This
was the cause of 461 analyzer errors on a fresh clone.

SDK: workspace needs **Dart ≥ 3.13** (`app` requires `^3.13.0`; packages `^3.12.0`).

## Layout

```
fermata_workspace/
├── app/                          Flutter UI + composition root + platform adapters
│   ├── lib/main.dart
│   └── lib/src/
│       ├── app.dart              FermataApp, AppShell (plain Navigator, IndexedStack tabs)
│       ├── providers/            DI + infra providers (11), pdfrx_page_counter.dart
│       ├── theme/fermata_theme.dart
│       └── features/{library,viewer}/    + widgets/
├── packages/fermata_core/        Pure Dart domain: models, geometry, duplicate rules, repo interfaces
└── packages/fermata_data/        Pure Dart: drift tables/db/repos, dart:io storage, import pipeline
```

### Layering rules (these are enforced by convention + doc comments, not by lint)

```
            fermata_core   (no Flutter, no dart:io, no drift)
            ▲         ▲
  fermata_data         │        app/  (the only place Flutter, pdfrx,
  (pure Dart)         │        drift_flutter, path_provider, file_picker appear)
        ▲──────────────┘
```

1. **`fermata_core` must stay pure Dart.** No `package:flutter`, no `dart:io`, no drift. All
   internal imports are relative. Models crossing this line use packed ARGB `int` for colors, never
   `Color` (`geometry/stroke.dart:88-90`).
2. **Repository contracts live in core, implementations in data.**
   `ScoreRepository`/`AnnotationRepository` are declared in
   `fermata_core/lib/src/repositories/repositories.dart`; `Drift*` implementations live in
   `fermata_data`. UI depends on the interface, never on `AppDatabase`.
3. **Enums cross layers by `.name` string, never ordinal.** All have a defensive `orElse`.
4. **Everything Fermata owns lives under one root directory** (`<app docs>/fermata`) and **every
   path stored in the DB is relative**. `repository_test.dart:624` asserts `p.isRelative(stored)`.
   Never persist an absolute path.
5. **`app/lib/` has no public API** — everything is under `lib/src/` and imported as
   `package:fermata/src/…`. `app/test/helpers/fake_page_renderer.dart:4` imports an implementation
   path, so **nothing under `lib/src/` may move to `lib/`** without breaking it.

## Load-bearing invariants

These are the things that silently break if you "clean them up".

- **Normalized coordinates.** Ink is stored as `[0,1]` fractions of the page box
  (`geometry/normalized_point.dart:3-9`) and stroke width as a fraction of page width
  (`stroke.dart:92-94`). The painter resolves both through `size`, the same box the page image
  occupies. **Never store pixels or PDF points in an annotation.** ⚠️ *Known bug: the gesture side
  (`page_stack.dart:244,317-323`) normalizes against `constraints.biggest` (the viewport) while the
  painter multiplies by `_logicalSize` (the fitted page). These agree only when the page exactly
  fills the viewport. Fix before tuning anything else about drawing.*
- **`pdfrx` is a document loader and page rasteriser — never a widget library.** Stated three times
  (`app/pubspec.yaml:16-19`, `providers/pdfrx_page_counter.dart:11-14`,
  `viewer/pdfrx_page_renderer.dart:11-17`). Its bundled viewer widgets live in the separate
  `material_ui` package (a transitive dep at `material_ui 1.4.0`), which would be a second
  component library alongside the M3 theme. **Do not reach for `PdfViewer`/`PdfPageView`.** We need
  a custom viewer anyway: the overlay must share a box with the page, and draw-vs-pan gestures need
  routing.
- **`PdfPage.render` returns native memory that must be disposed**, and accepts a cancellation
  token so a fast scroll can abandon a render. The `_rasters`/`_Raster` cache exists only to manage
  `ui.Image` lifetimes. A new cache layer must honour `evict`/`clear` or leak native memory.
- **`FileHasher` must not use `openRead(chunkSize)` or `sha256.bind(stream).first`.**
  `storage/file_hasher.dart:17-27` documents two SDK traps: the crypto `Sink` only digests on
  `close()`, and on Dart 3.13.4 `File.openRead(chunkSize)` yields **zero chunks for a small file**,
  which would hash every file as empty and defeat duplicate detection. The hand-rolled
  `RandomAccessFile` loop is load-bearing; `storage_test.dart:125-151` exists to pin it.
- **Stroke draw order depends on the `newId()` string format.** Drift stores `DateTime` as whole
  seconds, so same-second strokes tie on `createdAt`; the tie is broken by `id ASC`
  (`annotation_repository.dart:154-157`). That only works because `newId()` time-prefixes with a
  **fixed-length** base-36 microsecond string, making lexicographic order equal chronological order.
  The undo stack depends on it. ⚠️ *`page_stack.dart:364` re-implements this with a
  variable-length counter — already a latent violation.*
- **Foreign keys are enabled per connection** via `DriftNativeOptions.setup`, not in the migration
  (`library_providers.dart:31-36,54-56`): a pragma set on one connection doesn't survive the pool
  opening the next, and every cascade delete depends on it. This is why the app depends on `sqlite3`
  directly — it names `CommonDatabase`.
- **Setlist positions are unique per setlist**, so writes go through a two-pass negative staging
  range (`stagingBase = -1000000`, `organization_repositories.dart:216-221,249-281`). Writing
  positions directly deadlocks when moving the last entry to the front.
- **Filtering and sorting happen in Dart, not SQL** (`score_repository.dart:14-17`) — hundreds of
  scores, and one place so the orders can't drift apart. "Never-opened sorts last", not first.
- **Highlighter paints before pen, in two ordered passes** regardless of creation order
  (`annotation_painter.dart:39-66`), with `BlendMode.multiply` for highlighter. This is deliberate;
  per-stroke z-order is not achievable without changing it.
- **`layerIds` empty means "all layers", not "no layers"** (`annotation_repository.dart:162`).
- **The whole v1 schema is front-loaded** (`app_database.dart:12-15`) — MIDI, recordings, setlists
  and pedal mappings are declared now so later work is feature code, not schema churn. There is
  **no `onUpgrade` yet**: `schemaVersion => 1` is hard-coded. The *first* schema change is where the
  migration strategy has to be written. Prefer adding columns before anything ships.

## Conventions

- **Commands:** root `dart analyze`/`dart test`; `cd app && flutter test`. No CI yet.
- **Naming:** `snake_case.dart`; interfaces have no suffix (`ScoreRepository`, not
  `IScoreRepository`); implementations are `Drift` + interface name. Constants are `kCamelCase`.
  Providers are `<thing>Provider`, notifiers `<Thing>Notifier`.
- **Imports:** single quotes, trailing commas, `prefer_relative_imports`, `directives_ordering`,
  prefixed imports (`as p`, `as math`, `as ui`), records for multi-value returns.
- **Doc comments explain *why*, including rejected alternatives.** This codebase argues with itself
  in comments — see `duplicate_detection.dart:52-56,101-107,151-168`, `file_hasher.dart:17-27`,
  `score_repository.dart:14-17`. Match that: state the tradeoff, don't just describe the code.
- **Barrels open with a prose `///` doc** stating the layer's constraint, then `library;`, then
  exports. No license headers anywhere.
- **No mocking library.** Fakes are hand-written classes. Follow the existing patterns: the
  `PdfPageCounter` stub (`import_service_test.dart:15-24`) for the one thing plain Dart can't run,
  `FakePageRenderer`/`HangingPageRenderer` for anything touching PDFium, and
  `NativeDatabase.memory()` + `Directory.systemTemp.createTemp()` + `setUp`/`tearDown` for the data
  layer.
- **Commit and push frequently**, in small logical increments. Log any departure from `DESIGN.md`
  in `Todo.md`'s deviations section, with the reason.

## Gotchas

- **Analysis strictness is asymmetric.** The two packages get `strict-casts`,
  `strict-inference`, `strict-raw-types`, `todo: warning` and ~14 extra lints.
  `app/analysis_options.yaml` is still the **stock `flutter create` file** — no strict modes, no
  extra rules. So app code won't be held to the packages' bar, and a future TODO in `app/` won't
  warn. Worth fixing.
- **Zero Android permissions are declared.** No `INTERNET`, no storage, no Bluetooth. `file_picker`
  uses SAF so none are needed today; pedal support will require adding Bluetooth ones. Don't add
  permissions speculatively.
- **`minSdk = 24`** was chosen for the *planned* MIDI/soundfont plugins
  (`app/android/app/build.gradle.kts:19-21`). Release builds are signed with **debug keys**
  (`build.gradle.kts:29-31`) — the one literal TODO outside Dart.
- **Providers live in two places** — `src/providers/library_providers.dart` (infrastructure) and
  feature files (`library_screen.dart`, `page_stack.dart`). Inconsistent, but the viewer-local ones
  are deliberate: resolving them in the widget would need restructuring when layers land.
- **Six of the eleven infra providers are constructed but never read** (organization, playback,
  recording, pedalMapping…). That's ahead-of-feature wiring, not dead code.
- `*.mid`/`*.midi`/`*.sf2` are marked `binary` in `.gitattributes`, and there's a deliberately
  no-op `*.mid file-not-ignored=false` rule — don't add a blanket ignore for music files.