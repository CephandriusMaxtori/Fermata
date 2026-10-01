# Fermata — Todo

Living checklist derived from [`DESIGN.md`](DESIGN.md). Keep this current: tick items as they
land, add newly discovered work, and log deviations from the design doc at the bottom.

## How to read this

| Mark | Meaning |
|---|---|
| `[ ]` | Not started |
| `[~]` | In progress |
| `[x]` | Done and verified |
| `[?]` | Looks implemented on disk, **not yet verified** — confirm before trusting |
| `[-]` | Deliberately deferred / descoped (see [Deferred](#deferred-not-in-v1)) |
| `[!]` | Blocked — needs a decision |

Status of `[?]` items was inferred from the file tree and commit history, not by reading the
implementation. The first pass at verifying them is the top task below.

---

## Immediate next steps

- [!] **Verify the `[?]` items below** by reading the implementation, then flip them to `[x]` or `[ ]`
- [ ] Write [`AGENTS.md`](AGENTS.md) (not present in the repo yet)
- [ ] Audit existing code against `DESIGN.md` §6 v1 scope — report gaps and risks
- [ ] Decide the `DESIGN.md` §9 open questions that are still blocking (see [Open questions](#open-questions))

---

## Milestones

Mirrors `DESIGN.md` §11.

### M1 — Score import + library list

- [x] Pub workspace scaffold (`app`, `fermata_core`, `fermata_data`)
- [x] Storage layout service (`fermata_data/storage/fermata_layout.dart`)
- [x] File store (`fermata_data/storage/file_store.dart`)
- [x] File hasher for duplicate detection (`fermata_data/storage/file_hasher.dart`)
- [x] Duplicate detection logic (`fermata_core/import/duplicate_detection.dart`)
- [x] `ImportService` (`fermata_data/import/import_service.dart`)
- [x] Score model + `ScoreRepository`
- [x] Library screen, empty state, import sheet, score card (`app/lib/src/features/library/`)
- [?] Multi-page / multi-file import — combine pages into one Score entry
- [?] Duplicate detection wired into the import flow (hash hard-block, metadata soft suggestion)
- [?] List/grid view toggle
- [?] Sort by title / composer / recently opened
- [?] Basic search and filtering

### M2 — Basic PDF viewer

- [x] `pdfrx` ^2.6.5, used only via `pdfrx_engine`'s `PdfPage.render()` (deliberately **not** pdfrx's own viewer widgets — they depend on `material_ui`, which clashes with our Material 3 / One UI styling; see comment in `app/pubspec.yaml`)
- [x] `PageRenderer` abstraction (`app/lib/src/features/viewer/page_renderer.dart`)
- [x] `PdfrxPageRenderer` implementation
- [x] Page stack composing rendered page + annotation overlay (`page_stack.dart`)
- [x] Page counter provider (`app/lib/src/providers/pdfrx_page_counter.dart`)
- [x] Test fake for the renderer (`app/test/helpers/fake_page_renderer.dart`)
- [?] Pinch-to-zoom + pan
- [?] Page-by-page vs continuous scroll modes
- [?] Fast page navigation (thumbnail strip / page jump)
- [?] Memory-conscious page cache for large multi-page scores
- [?] Coordinate-space contract for the overlay (`DESIGN.md` §10 risk #1 — highest-risk area)

### M3 — Annotation layer v1

- [x] Normalized coordinate space (`fermata_core/geometry/normalized_point.dart`, `page_geometry.dart`)
- [x] Stroke model + conditioning (`fermata_core/geometry/stroke.dart`, `stroke_conditioner.dart`)
- [x] Annotation painter (`app/lib/src/features/viewer/annotation_painter.dart`)
- [x] Brush toolbar (`app/lib/src/features/viewer/brush_toolbar.dart`)
- [x] Annotation persistence + codec (`fermata_data/db/annotation_points_codec.dart`)
- [x] `AnnotationRepository`
- [?] Pen tool — multiple colors, adjustable stroke width
- [?] Highlighter tool
- [?] Undo / redo
- [?] Annotations stored as structured data, never flattened into the PDF (`DESIGN.md` §7)

### M4 — Text notes + stamps + eraser

- [ ] Text notes anchored to a page position
- [ ] Music stamps: fermata, accent, crescendo/decrescendo hairpin, fingering numbers
- [ ] Eraser
- [ ] Font rendering for notes/stamps (symbol set + license source)

### M5 — Annotation layers / versions

- [x] `AnnotationLayer` model (`fermata_core/models/annotation_layer.dart`)
- [ ] Layer CRUD ("My fingering", "Teacher's edits")
- [ ] Independent per-layer visibility toggle
- [ ] Layer-aware undo/redo

### M6 — Tags / setlists / search

- [x] `Tag` and `Setlist` models (`fermata_core/models/`)
- [x] `OrganizationRepositories` abstraction
- [ ] Tags UI
- [ ] Setlists UI — **order matters and is preserved**, unlike tags
- [ ] Search + filtering UI

### M7 — MIDI import + playback + metronome

- [x] `MidiTrackFile` model + playback edit metadata (`fermata_core/models/midi_file.dart`)
- [!] **MIDI playback engine undecided** (`DESIGN.md` §9) — no maintained Flutter package does
      tempo change without pitch shift. Must be resolved before any of the below is useful.
- [ ] `.mid`/`.midi` import alongside PDF/image scores
- [ ] Associate MIDI with a Score, or stand alone as a library item
- [ ] On-device playback engine + soundfont selection
- [ ] **Shared playback clock** — prototype early (`DESIGN.md` §10 risk #5)
- [ ] Standalone metronome

### M8 — A-B loop + count-in + tempo-independent pitch

- [ ] A-B loop by time and/or measure
- [ ] Count-in before playback
- [ ] Tempo-independent pitch (soundfont re-render path)

### M9 — Piano visualizer

- [ ] Virtual piano keyboard, keys highlight in sync with playback
- [ ] Falling-notes lane
- [ ] Landscape mode — full-width keyboard

### M10 — Auto-scroll + Bluetooth pedal

- [ ] Auto-scroll at a set pace, optionally locked to MIDI tempo
- [ ] `PedalMapping` model — exists (`fermata_core/models/pedal_mapping.dart`)
- [ ] Pedal input as **mappable HID key events** — no plugin; use Flutter's built-in
      `HardwareKeyboard` (`DESIGN.md` §7)
- [ ] Tap-anywhere-to-advance fallback
- [ ] On-screen fallback controls for every pedal-dependent feature (§10 risk #6)

### M11 — Backup / restore

- [ ] Export-all to a single archive — zip of DB export + asset files (§9)
- [ ] Import-from-file restore
- [ ] Backup format decision (§9 leans single zip)

### M12 — Accessibility

- [ ] Font size + contrast scaling for UI chrome only — **not** score content (§6.8)
- [x] Material 3 theme scaffolded (`app/lib/src/theme/fermata_theme.dart`)

### M13 — Polish

- [ ] Performance on large multi-page scores
- [ ] Low-end Android device testing
- [ ] One UI styling pass — bold headers, pill search/buttons/chips, rounded cards,
      pill-highlight bottom nav (§5). **Watch for `material_ui` collision** with pdfrx.
- [ ] Freehand precision UX — stylus vs fingertip, palm rejection considerations (§10 risk #3)

---

## Deferred, not in v1

- [-] **iOS phase** (`DESIGN.md` §11.14) — not scaffolded, `android/` only
  - [x] Plugin iOS-support audit — **nothing chosen blocks iOS** (see [iOS readiness](#ios-readiness))
  - [ ] Set iOS deployment target to 14.0+ when scaffolding (`file_picker` requires it)
- [-] **OMR-generated MIDI via homr** (§11.15) — **go/no-go pending**
  - [ ] Python/Dart runtime integration strategy (TFLite/ONNX vs bundled runtime vs server)
  - [ ] **AGPL-3.0 legal review** — may require Fermata's own source to be published
  - [ ] Review how [Andromr](https://github.com/aicelen/Andromr) handled both
  - [ ] Must surface OMR output as best-effort / proofread-able, never as equal to a
        hand-authored MIDI import
- [-] **Practice recording** (§6A.16) — `Recording` model already exists
      (`fermata_core/models/recording.dart`) but nothing consumes it yet
- [-] **Companion web UI** (§6A.17) — local server lifecycle/discovery/concurrency

---

## Open questions

From `DESIGN.md` §9. Resolved ones get struck through with the answer.

- [!] **MIDI playback engine** — needs pitch-preserving tempo change. No maintained Flutter
      package does this; blocking M7/M8/M9 entirely.
- [ ] Scanned image scores — v1 or defer? Affects the import pipeline.
- [ ] Duplicate detection method — hash (hard block) vs fuzzy title/composer (soft suggest).
      §9 leans: start hash-only, metadata matches are a soft suggestion.
- [ ] Backup format — §9 leans single zip.
- [ ] Flattened PDF export of annotated scores — in scope?
- [ ] Time-stretching approach — scope depends on MIDI-only vs. audio-file playback.

---

## iOS readiness

Audited 2026-09-30. **No current choice blocks iOS.** Landmines to design around, all cheap to avoid now:

- [ ] Never use `path_provider`'s `getExternalStorage*` APIs as the primary location —
      they **do not exist on iOS**. Use `getApplicationDocumentsDirectory()` /
      `getApplicationSupportDirectory()` on both platforms.
- [ ] iOS deployment target 14.0+ (`file_picker` uses `PHPicker`).
- [ ] `pdfx`'s `WEBP` page format is Android-only (not applicable — project uses `pdfrx`).
- [ ] Plan deep links now if ever wanted — needs `Info.plist` URL scheme + associated domains.

Packages chosen and their iOS status:

| Package | iOS | Notes |
|---|---|---|
| `pdfrx` ^2.6.5 | ✅ | First-class. |
| `drift` ^2.35.1 | ✅ | Pure Dart; iOS work is in `sqlite3`. |
| `sqlite3` ^3.0.0 | ✅ | Dart build hooks / native assets; prebuilt arm64 device + both simulator slices. |
| `flutter_riverpod` ^3.4.3 | ✅ | Pure Dart. |
| `file_picker` ^13.1.0 | ✅ | **Requires iOS 14.0+.** v13 is a breaking rewrite: `pickFiles()` returns `List<PlatformFile>` directly, `FilePickerResult` is gone, `PlatformFile.length()` is `Future<int?>` (null ≠ empty). |
| `path_provider` ^2.1.5 | ✅ | See external-storage warning above. |
| `go_router` | ✅ | Pure Dart. |

---

## Risks

From `DESIGN.md` §10, plus findings from the dependency audit.

| Risk | Status |
|---|---|
| Annotation alignment across zoom/scroll drifts | **Highest risk.** `NormalizedPoint`/`PageGeometry` exist — verify they're actually used for all stored points, not just at draw time. |
| Performance on large multi-page scores, low-end devices | Open. No page-cache strategy yet? |
| Freehand precision (stylus vs fingertip) | Open. |
| MIDI playback fidelity varies by device/soundfont | Open, and blocked on the engine decision. |
| Shared clock across visualizer / auto-scroll / audio | **Prototype early** — more moving parts than playback alone. |
| Bluetooth pedal support is device-dependent | Mitigation planned: on-screen fallback everywhere. |
| Android-only plugins block iOS later | **Resolved** — audit found none. |
| OMR runtime mismatch + AGPL-3.0 | Go/no-go before commitment. |

---

## Notes / deviations

Log any departure from `DESIGN.md`, with the reason.

- **Workspace is a Dart pub workspace**, not a single package. `DESIGN.md` §7 describes a
  layered architecture; that layering is realised as three packages rather than folders.
- **`pdfrx` instead of `pdfx`/`syncfusion_flutter_pdfviewer`.** `DESIGN.md` §5 lists
  `pdfx` and `syncfusion_flutter_pdfviewer` as candidates; the project uses `pdfrx`, using
  only its render engine to avoid the `material_ui` styling clash. `syncfusion` was the wrong
  call anyway for a public repo (commercial license).
- **Android-only scaffold** per §4 — no `ios/` directory generated.
- `Recording` model exists although practice recording is deferred (§6A). Intentional or
  premature? Verify before relying on it.