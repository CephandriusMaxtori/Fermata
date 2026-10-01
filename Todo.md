# Fermata — Todo

Living checklist derived from [`DESIGN.md`](DESIGN.md). Tick items as they land, add newly
discovered work, and log deviations at the bottom.

## How to read this

| Mark | Meaning |
|---|---|
| `[ ]` | Not started |
| `[~]` | In progress |
| `[x]` | Done and verified |
| `[!]` | Blocked on a decision |
| `[-]` | Deliberately deferred (see [Deferred](#deferred-not-in-v1)) |

All items below were verified by reading the implementation, not inferred from file names.

**Baseline: `flutter analyze` clean, 193 tests passing** (15 `app` + 111 `fermata_core` + 67 `fermata_data`).
Note `dart test` at the workspace root fails — it needs a reporter arg; run it per package.

Our own Standard MIDI File reader lives in `packages/fermata_core/lib/src/midi/smf/`:
`byte_cursor.dart` (bounds-checked reads, VLQ), `smf_parser.dart` (lossless event layer),
`smf_midi_score.dart` (interpretation). Add format quirks there, never at a call site.

---

## Immediate next steps

1. [ ] Add `flutter_midi_engine` behind an `AudioEngine` interface (see [M7](#m7---midi-import--playback--metronome))
2. [ ] Fix `deleteScore` so it deletes files, not just rows (see [Bugs](#bugs-found-in-existing-code))
3. [ ] Tags + setlists UI (M6)
4. [ ] Score thumbnails — the grid always shows a placeholder

## Tracking

A Notion project tracker mirrors this checklist for planning — see the
[Projects & Tasks](https://app.notion.com/p/60fd677f1c2f8262a34881428b2fa08c?pvs=204)
workspace page. **`Todo.md` stays authoritative** because it is versioned with the
code; update it in the same change as the code.

---

## Bugs found in existing code

Not part of a milestone — fix as encountered. All verified by reading the source.

- [x] **3 tests were failing: cascades did nothing, because the test databases never enabled foreign
  keys.** `NativeDatabase.memory()` leaves `PRAGMA foreign_keys` off (sqlite's default), while the
  app switches it on per connection via `DriftNativeOptions.setup`. So `deleting a score cascades to
  its pages and layers` and `deleting a layer removes its strokes` were both genuinely failing, and
  `enables foreign keys so cascades fire` — a test that asserts the pragma — failed too, which is
  what exposed it. Fixed by adding `test/helpers/test_database.dart` with `openTestDatabase()`, used
  by all three data-layer test files. **The suite had been reporting green-ish while cascade deletes
  were broken in production config.**

- [x] **Ink was misplaced whenever the page didn't exactly fill the viewport.** The
  `GestureDetector` wrapped `Center`, so its hit box was the whole `PageView` viewport, while
  `AnnotationPainter` resolved coordinates through `_logicalSize` (the fitted page). The two only
  agreed when the page exactly filled the viewport, so on any letterboxed page — which is most of
  them — every mark landed in the wrong place, and tap-to-turn zones were wrong too. Fixed by moving
  the detector *inside* the `SizedBox`, so the gesture box **is** the paint box, plus zero-size
  guards for the pre-measurement frame. Pinned by `app/test/page_stack_alignment_test.dart`, which
  was verified to fail against the old code.
- [x] **Committed strokes didn't appear.** `strokesForPageProvider` was a
  `FutureProvider.autoDispose.family` calling `getStrokes` — a one-shot — while `_persistStroke`
  invalidated nothing, so the overlay kept its stale list until the widget rebuilt. `watchStrokes`
  existed for exactly this and was unused. Now a `StreamProvider` over `watchLayers` +
  `watchStrokes`, which also makes layer visibility reactive.
- [x] **`BrushSelection.copyWith` dropped `kind`** — it always called the pen constructor, so
  choosing a colour or dragging the width slider while the highlighter was selected silently
  switched the tool back to pen. Fixed with an explicit private constructor. A second issue surfaced
  while fixing it: the pen and highlighter palettes are **disjoint**, so switching tools carried
  over a colour the new palette does not offer, leaving the toolbar with no selected dot and the
  user drawing in a colour they could not pick again. `withKind` now falls back to the new
  palette's first colour.
- [x] **Live-stroke preview ignored the brush** — `annotation_painter.dart` hard-coded a red 3px
  stroke, so a user with the highlighter selected saw a thin red line that became a thick translucent
  band on lift. The painter now takes the `BrushSelection` and applies the same colour, width and
  blend rules as a committed stroke.
- [x] **`BrushSelection` moved out of `brush_toolbar.dart`** into its own `brush_selection.dart` —
  the toolbar, the painter and the provider all need it, so a shared value type should not be
  nested inside one of its consumers.
- [ ] **`deleteScore` doesn't delete files.** The contract says "…its layers, its annotations **and
  its files**" (`repositories.dart:34-35`) but `score_repository.dart:88-93` only deletes rows.
  `FileStore.deleteScoreAssets` exists and is called only from tests — `ScoreRepository` has no
  `FileStore`. Will bite whoever builds delete-in-UI.
- [ ] **`pixelRatio` is dropped in production.** `pdfrx_page_renderer.dart:51-55,87-91` accepts it
  and passes *logical* pixels to `pdfPage.render`, so rasters are 1× and upscaled by
  `RawImage(fit: BoxFit.fill)` on high-DPI screens. `FakePageRenderer` *does* apply it, so tests
  can't catch this.
- [ ] **No re-render on rotate or resize.** `didUpdateWidget` (`page_stack.dart:180-190`) only
  reacts to `page.id` changes, contradicting the cache-key comment at
  `pdfrx_page_renderer.dart:65-66` that assumes a rotate requests a new raster.
- [ ] **No index on `Scores.contentHash`** despite `tables.dart:15-18` promising "a single indexed
  lookup" — `findByContentHash` is a full scan. Moot today (import loads the whole library and
  compares in Dart) but fix before `contentHash` grows real traffic.
- [ ] **`applyScoreQuery` silently ignores `tagIds` and `setlistId`** (`score_repository.dart:186-219`).
  `ScoreQuery.hasFilters` and `copyWith({clearSetlist})` imply they work, and
  `duplicate_detection_test.dart:250-270` exercises them — but nothing filters on them. `LibraryFilter`
  never populates them either.
- [ ] **Every `watch*` repository method is unused.** Only `libraryProvider` streams. The overlay
  needs `watchStrokes` (see above); the rest land with their features.
- [ ] **`PdfrxPdfPageCounter` never calls `pdfrxFlutterInitialize()`** (`pdfrx_page_counter.dart:18`)
  while `PdfrxPageRenderer._documentFor` does (`:121`) — the first native pdfrx call in the app
  happens during import, before initialization.
- [ ] **`_rasteriseBitmap` leaks the `ImageCodec`** — `pdfrx_page_renderer.dart:108-113` never
  calls `codec.dispose()`.
- [ ] **Two `newId()` implementations.** `fermata_data`'s is fixed-length base-36 (load-bearing for
  draw order); `page_stack.dart:364-373` re-implements it with a variable-length counter. The
  ordering invariant is already violated in principle. Use the shared one.
- [ ] **`ensureDirectories()` omits `webPath`** (`fermata_layout.dart:46-56`), though it's in the
  documented layout.
- [ ] **`AppSettings` table has no repository, provider or test** — declared, entirely unused.
- [ ] **`ScaffoldMessenger.of(context)` captured before an `await`** (`import_sheet.dart:19`, used
  at `:40`) — unsafe.
- [ ] `Tag.colorValue` can never round-trip — the `tags` table has no color column, and
  `watchTags`/`getTags` hard-code `colorValue: null`.
- [ ] Text/stamp vocabulary is unreachable end-to-end: `AnnotationKind.text`/`.stamp` and the
  `textContent`/`anchorX`/`anchorY` columns exist, but `_strokeCompanion` never writes them and
  `_toStroke` never reads them. Expected — that's M4.
- [ ] Minor: unused `dart:async` import (`library_screen.dart:1`); dead `await makeScores(database)`
  (`storage_test.dart:269`); unused `FakePdfPageCounter` (`storage_test.dart:38`);
  `MidiFiles.linkedScoreId` FK is one-way, so deleting a MIDI leaves a dangling
  `Scores.linkedMidiId`; redundant `UNIQUE (score_id, page_index, layer_id, id)` on `Annotations`
  (strict superset of the PK); import progress reports `0/1` during copying (`import_service.dart:248-255`);
  `preview()` runs one full-table `getScores()` per candidate.

---

## Milestones

Mirrors `DESIGN.md` §11.

### M1 — Score import + library list

Substantially **done**. Remaining:

- [x] Workspace scaffold; storage layout, file store, file hasher
- [x] Duplicate detection — hash hard-block, metadata soft-suggest, deliberately asymmetric
      (`duplicate_detection.dart:101-107`); Unicode folding for CJK/Cyrillic/ligatures
- [x] `ImportService` — multi-page PDF, multi-file combine in picker order, bitmaps, progress stream
- [x] `Score`/`ScorePage` models, `ScoreRepository`, drift schema
- [x] Library screen, empty state, import sheet, score card, list/grid, sort by recent/title/composer/date
- [x] Search (title + composer), empty-no-matches and error states
- [x] Default annotation layer per score (`kDefaultLayerName`)
- [ ] Multi-file import **UI affordance** — service handles ordering; verify the picker path is exposed
- [ ] Grid/list toggle — implemented (`toggleLayout`), verify against `DESIGN.md` §6.1
- [ ] Thumbnails — `_Thumbnail` (`score_card.dart:135-173`) is a permanent placeholder; it never reads
      `score.thumbnailPath`. Generation is outstanding.
- [ ] Tag / setlist filters — blocked behind M6 (see `applyScoreQuery` bug above)

### M2 — Basic PDF viewer

- [x] `pdfrx` via `pdfrx_engine`'s render only (never its `material_ui` viewer widgets)
- [x] `PageRenderer` interface; `PdfrxPageRenderer` is the only production impl
- [x] Page geometry, A4 fallback, size-keyed raster cache, cancellation tokens
- [x] `PageView` + `InteractiveViewer` (outer zoom wraps inner paged view)
- [x] Page jump sheet, prev/next, tap-to-turn thirds
- [~] Pinch-to-zoom + pan — present; fix the `pixelRatio` and resize bugs above
- [ ] Page count badge / thumbnails strip for fast navigation (`DESIGN.md` §6.2 "thumbnails or page jump")
- [ ] Low-end device perf pass (`DESIGN.md` §10 risk #2)

### M3 — Annotation layer v1

The hard part is built and well tested; what's missing is correctness at the seams.

- [x] `NormalizedPoint` + `PageGeometry`, pixel round-trip tested to `1e-9`
- [x] `StrokeConditioner` — thin → simplify (RDP) → smooth (Catmull-Rom), pure Dart, well tested
- [x] Annotation persistence: compact 1/10000-integer JSON, pinned by test
- [x] `AnnotationPainter` — two-pass (highlighter under pen, `BlendMode.multiply`), `CustomPaint` in a
      `Stack` sharing the page's box, `RepaintBoundary`
- [x] Pen + highlighter, 2 palettes, width slider (0.1 %–3 % of page width)
- [x] Live stroke held outside the DB, committed on finger-lift
- [!] Fix alignment bug (gesture vs paint box) — see Bugs
- [!] Fix committed strokes not appearing — switch to `watchStrokes` + invalidate
- [ ] Undo / redo — `deleteStrokes` exists ("used by the eraser and by undo") but is called from nowhere

### M4 — Text notes + stamps + eraser

- [ ] Text notes anchored to a page position — schema and `AnnotationKind` ready; needs a painter path
      (`AnnotationPainter` only knows `Stroke`)
- [ ] Music stamps: fermata, accent, crescendo/decrescendo hairpin, fingering numbers
- [ ] Font/glyph source for stamps + notes — pick a source and license it (`.gitattributes` already
      anticipates `*.sf2`)
- [ ] Eraser — `deleteStrokes` ready
- [ ] Stamp/pen z-order decision (painter is currently two-pass by kind, not per-stroke)

### M5 — Annotation layers / versions

- [x] `AnnotationLayer` model, table, repository CRUD; cascade delete verified
- [x] Per-layer `visible` flag, toggles independently
- [ ] Layer picker UI — `activeLayerProvider` (`page_stack.dart:53-59`) currently guesses "first
      visible, else first" and its doc says v1 has no picker yet
- [ ] Multiple visible layers rendered together (`getStrokes` already accepts a `layerIds` set)
- [ ] Layer-aware undo/redo

### M6 — Tags / setlists + search

- [x] `Tag`/`Setlist`/`SetlistEntry` models, tables, repositories
- [x] Ordered setlists — contiguous positions, two-pass negative staging, `reorderSetlistEntries`
- [x] Case-insensitive unique tags; `ensureTag` handles the NOCASE collision
- [x] Search across title + composer, combined with sort
- [ ] Tags UI
- [ ] Setlists UI (tab is a `_PlaceholderTab`, `app.dart:46-51`)
- [ ] Wire `tagIds`/`setlistId` into `applyScoreQuery` and `LibraryFilter`

### M7 — MIDI import + playback + metronome

Stack decision (researched 2026-09-30):

| Concern | Choice | Why |
|---|---|---|
| Parsing | **Our own SMF reader** (`fermata_core/lib/src/midi/smf/`) | Written in-repo. See the note below. |
| Pitch math | **`music_notes` ^0.28.0** | Note names, enharmonics, frequencies. BSD-3, pure Dart. |
| Audio | **`flutter_midi_engine` ^0.1.5** | Decided 2026-09-30. See below. |

**Audio engine: `flutter_midi_engine`.** Chosen over `flutter_midi_pro` on integration risk,
not on features — since we drive notes ourselves from `MidiScore`, the headline advantage of
`flutter_midi_pro` (a built-in pitch-preserving MIDI file player) is not something we use.

- **AGP 9 support, explicitly.** It detects the AGP major version and adapts, so it works on this
  project's AGP 9.0.1 / Gradle 9.1.0. `flutter_midi_pro` needs a CMake native build plus a ~40 MB
  FluidSynth download, which is a materially larger integration surface.
- **A jitpack Maven AAR, not a native build.** Android pulls
  `com.github.billthefarmer:mididriver:1.25`. No CMake, no NDK, no 40 MB download.
- **SF2 and SF3**, 16 channels, per-channel volume/pan, program changes, reverb and chorus.
- **Bluetooth/headset route re-routing** — directly relevant, since §6.5 practice happens with
  headphones on.
- Also matches the intent already recorded at `app/android/app/build.gradle.kts:19-20`.

⚠️ **Adoption is thin: 3 stars, 1 fork, last push 2026-06-18.** Treat it as a swappable adapter
behind our own `AudioEngine` interface, never as a dependency to call directly. If it rots, the
swap is one class.

- [ ] Add `flutter_midi_engine` and put it behind an `AudioEngine` interface
- [ ] Wrap the plugin in an adapter so `fermata_core` and the UI never import it
- [ ] Soundfont asset: pick an SF2/SF3 and check its licence and size before bundling

**On writing our own parser:** the Dart ecosystem has no maintained SMF reader.
`flutter_sequencer` and `flutter_midi` both declare pre-null-safety SDK constraints
and cannot resolve on Dart 3.13. `dart_midi_pro` works but is a ~23-downloads/month
package with an unverified uploader. Since every future extension (measure mapping,
cue points, OMR output, MIDI *writing*) lands in this layer, owning it is worth
~500 lines. Note the split: we own the **parser**, not the **synth** — the synth is
FluidSynth either way, so owning a wrapper around it buys nothing.

- [x] `MidiFile` model + `PlaybackEdits` (tempo scale, `LoopRange`, muted channels, count-in bars,
      cue points), `editsJson` round-trip tested; malformed blob falls back to defaults
- [x] `MidiFiles` table, `DriftPlaybackRepository`, layout `midi/<id>.mid`
- [x] `MidiScore` interface in `fermata_core`: notes by tick, tempo map, time signatures,
      tick↔measure, tick↔duration, `pitchRange`. Pure Dart, no plugin.
- [x] `SmfParser` — own SMF reader. Header/format/division, chunk framing, VLQ,
      **running status**, all channel voices, meta events, SMPTE division, and
      bounds-checked reads that throw `MidiFormatException` with a byte offset.
- [x] `SmfMidiScore` — interpretation layer: note pairing (incl. zero-velocity
      note-offs and unterminated notes), tempo/signature assembly, markers and cue
      points read from the file.
- [x] 111 `fermata_core` tests, including 26 parser tests over real byte fixtures.
- [!] **Decide: engine file player vs. driving notes ourselves.** `flutter_midi_engine` exposes only
      `playNote`/`stopNote`, so the timeline is ours either way — which settles the §7 shared-clock
      question in our favour by construction. Drive notes from `MidiScore` and treat the engine as a
      dumb synth behind an interface.
- [!] **Decide: engine file player vs. driving notes ourselves.** Either engine owns its
      own clock. Driving `playNote`/`stopNote` from our `MidiScore` timeline makes §7's
      shared-clock rule structural and makes the engine a swappable adapter.
      **Prototype both early** (§10 risk #5); start with the engine's player since it
      sounds correct immediately.
- [ ] `.mid`/`.midi` import alongside PDFs/images
- [ ] Associate MIDI with a Score, or standalone library item
- [ ] On-device playback + soundfont loading (needs an SF2 asset; check its license/size)
- [ ] Standalone metronome
- [ ] MIDI *writing* — needed for OMR output (stretch goal) and for exporting edits

### M8 — A-B loop + count-in + tempo-independent pitch

- [x] `LoopRange` model (`contains` is half-open), `CuePoint`, persisted
- [ ] A-B loop by time and/or measure (needs the tick↔measure map from M7)
- [ ] Count-in (bars, via `countInBars`)
- [ ] Tempo-independent pitch — `setMidiTempo` if using the plugin's player, our own scheduling otherwise

### M9 — Piano visualizer

- [ ] Virtual piano keyboard, keys highlight in sync with playback
- [ ] Falling-notes lane
- [ ] Landscape mode — full-width keyboard
- [ ] Driven by the `MidiScore` timeline, not plugin callbacks

### M10 — Auto-scroll + Bluetooth pedal

- [x] `PedalMapping` model + `kDefaultPedalMappings` (arrows → page turn, media keys → play-pause and
      metronome toggle), table, repository, `resetToDefaults`
- [ ] Pedal input as **mappable HID key events** — use Flutter's built-in `HardwareKeyboard`. No plugin
      (`flutter_keyboard_visibility` reports the *soft* keyboard and is the wrong tool).
- [ ] Settings UI for mappings (`pedalMappingRepositoryProvider` exists, unconsumed)
- [ ] Auto-scroll at a set pace, optionally locked to MIDI tempo — **subscribes to the same clock** (§7)
- [x] Tap-to-turn fallback for thumb use
- [ ] Add Bluetooth permissions to `AndroidManifest.xml` — currently declares **zero** permissions

### M7a — 16 KB page size (not a current concern)

Fermata is **not going to Google Play**, so the 16 KB page-size requirement is not
enforced and `flutter_midi_16kb` is not needed. Revisit only if distribution changes.

It is still a *device* concern: newer Android hardware uses 16 KB pages, and a native
library not compiled for that alignment can fail to load there. Worth knowing before
distribution changes, not worth designing around now.

### M11 — Backup / restore

- [x] Layout has `exports/`; `FileStore.writeExport` ready (unconsumed)
- [ ] Export-all to a single archive — zip of DB export + asset files (§9 leans single zip)
- [ ] Import-from-file restore, honouring relative paths
- [ ] `deleteScoreAssets`/`deleteMidiAsset` wiring so deletes and backups agree

### M12 — Accessibility

- [x] M3 theme scaffolded with the One UI traits — pill search/buttons/chips, 22dp cards, pill nav
      indicator, large bold tracked headings (`fermata_theme.dart`)
- [ ] Font size + contrast scaling for UI chrome only — **not** score content (§6.8)
- [ ] No `fontFamily` override (SamsungOne isn't bundled); no dynamic colour

### M13 — Polish

- [ ] Performance on large multi-page scores, low-end Android testing
- [ ] Freehand precision UX — stylus vs fingertip, palm rejection (§10 risk #3)
- [ ] Thumbnails (see M1)

---

## Deferred, not in v1

- [-] **iOS phase** (`DESIGN.md` §11.14) — not scaffolded
  - [x] Plugin iOS-support audit — **nothing chosen blocks iOS** (table below)
  - [ ] Never use `path_provider`'s `getExternalStorage*` — **doesn't exist on iOS**. Use
        `getApplicationDocumentsDirectory`/`getApplicationSupportDirectory` on both. Already done.
  - [ ] iOS deployment target 14.0+ when scaffolding (`file_picker` requires it)
  - [ ] Plan deep links early if wanted — `Info.plist` URL scheme + associated domains
- [-] **OMR-generated MIDI via homr** (§11.15) — **go/no-go pending**
  - [ ] Runtime integration strategy (TFLite/ONNX vs bundled Python vs server; (c) breaks offline-first)
  - [ ] **AGPL-3.0 legal review** — may require publishing Fermata's own source
  - [ ] Review [Andromr](https://github.com/aicelen/Andromr)'s approach
  - [ ] Must present OMR output as best-effort/proofread-able, never equal to a hand-authored import
- [-] **Practice recording** (§6A.16) — `Recording` model, table and `DriftRecordingRepository` all exist
      and are tested; no UI, no UI consumer
- [-] **Companion web UI** (§6A.17) — needs local server lifecycle/discovery/concurrency design

---

## Open questions

- [!] **MIDI engine: plugin player vs. our own scheduling** (see M7). Everything in M8/M9 depends on it.
- [ ] Scanned image scores in v1, or defer? The import pipeline already handles bitmaps; this is about
      UI commitment.
- [ ] Backup format — §9 leans single zip.
- [ ] Flattened PDF export of annotated scores — in scope?
- [ ] Time-stretching — scope depends on MIDI-only vs. audio-file playback. Currently MIDI-only, and
      a soundfont synth re-renders at any tempo without pitch shift, so §9's phase-vocoder branch is
      moot unless audio-file playback is ever added.

---

## iOS readiness

Audited 2026-09-30. **No current choice blocks iOS.**

| Package | iOS | Notes |
|---|---|---|
| `pdfrx` ^2.6.5 | ✅ | First-class. |
| `drift` ^2.35.1 | ✅ | Pure Dart; iOS work is in `sqlite3`. |
| `sqlite3` ^3.0.0 | ✅ | Dart build hooks / native assets; prebuilt arm64 device + both simulator slices. |
| `flutter_riverpod` ^3.4.3 | ✅ | Pure Dart. |
| `file_picker` ^13.1.0 | ✅ | **Requires iOS 14.0+.** v13 breaking rewrite: `pickFiles()` returns `List<PlatformFile>`, `FilePickerResult` is gone, `PlatformFile.length()` is `Future<int?>` (null ≠ empty). |
| `path_provider` ^2.1.5 | ✅ | See the external-storage warning above. |
| `flutter_midi_pro` | ⚠️ partial | SF2 synth ✅; **MIDI file player is Android-only** (iOS/macOS throw `UNSUPPORTED`). Another reason the engine is a swappable adapter. |
| `go_router` | ✅ | Pure Dart. *(Not yet used — the app uses a plain `Navigator` by design.)* |

---

## Risks

| Risk | Status |
|---|---|
| Annotation alignment drift across zoom/scroll | **Fixed** — gesture box now equals the paint box; pinned by a widget test that fails against the old code. |
| Large multi-page score performance | Open. Raster cache exists; no low-end testing. |
| Freehand precision (stylus vs fingertip) | Open. |
| MIDI fidelity varies by device/soundfont | Open; blocked on the M7 decision. |
| Shared clock across visualizer / auto-scroll / audio | **Unstarted** — this is the M7 prototype. |
| Pedal hardware is device-dependent | Mitigation planned: on-screen fallback everywhere. |
| Android-only plugins block iOS | **Resolved** — audit found none. |
| OMR runtime mismatch + AGPL-3.0 | Go/no-go before commitment. |
| No CI | **Resolved** — `.github/workflows/ci.yml`: analyze, per-member tests, debug APK. First run passed; actions bumped off deprecated versions and the runner pinned to `ubuntu-24.04`. |
| 16 KB page sizes | Not enforced (no Play Store). Revisit only if distribution changes. |

---

## Notes / deviations

- **Workspace, not a single package.** `DESIGN.md` §7's layering is realised as three packages
  (`fermata_core` / `fermata_data` / `app`) rather than folders.
- **`pdfrx`, not the `pdfx`/`syncfusion_flutter_pdfviewer` candidates in §5.** §5 predates this
  implementation; `syncfusion` would have been wrong anyway (commercial license, public repo), and
  `pdfx` was evaluated against `pdfrx` on styling grounds — see the three code comments.
- **Android-only scaffold** per §4 — no `ios/` directory. `minSdk = 24` chosen for the planned MIDI
  plugins.
- **`go_router` not used.** `AppShell` deliberately uses a plain `Navigator` + `IndexedStack`
  (`app.dart:25-28`): library + viewer + two stub tabs isn't enough surface yet.
- **The v1 schema is front-loaded** — MIDI/recordings/setlists/pedal tables exist before their
  features, deliberately, to avoid a migration per feature (§8 note at `app_database.dart:12-15`).
  Consequence: no `onUpgrade` yet, so the first schema change must add the migration strategy.
- **Filter/sort runs in Dart, not SQL** — deliberate (`score_repository.dart:14-17`), diverges from
  what a SQL-first reader would expect.
- **Fermata's own SMF parser instead of a package.** `DESIGN.md` §9 lists `flutter_midi` and
  `flutter_sequencer` as candidates; both declare pre-null-safety SDK constraints and cannot resolve
  on Dart 3.13, so neither is usable. `dart_midi_pro` worked but had ~23 downloads/month. We own the
  *parser*; the *synth* stays FluidSynth behind an interface, because owning a wrapper around someone
  else's synth would buy nothing.
- **An earlier draft of this file credited `pdfx` and assumed a fresh single-package project.** Both
  wrong: the real repo is a pub workspace using `pdfrx`. Corrected after reading the code.