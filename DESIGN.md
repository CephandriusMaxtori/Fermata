# Fermata — Design Doc

## 1. Overview

Fermata is a simple sheet music keeping app for Android, built with Flutter. It lets musicians store, organize, and annotate their sheet music digitally — replacing paper binders and generic PDF readers with something purpose-built for reading, marking up, and practicing with scores.

## 2. Problem Statement

Musicians commonly deal with sheet music as scattered PDFs, photocopies, or physical binders. Existing PDF readers aren't built for musical workflows: annotating fingerings, dynamics, or practice notes is clunky, there's no music-specific organization (by piece, composer, setlist, instrument, etc.), and there's no support for the practice mechanics musicians actually use (looping a tricky passage, following along with a reference recording, turning pages hands-free). Fermata aims to be a focused tool that covers score-keeping, annotation, and practice support in one place.

## 3. Goals

- Import and store sheet music (PDF and/or image-based scores) on-device.
- Organize scores into a simple library (by title, composer, tags, setlists).
- Provide low-friction annotation tools directly on the score: freehand drawing/pen, highlighting, text notes, music-specific stamps, layered/versioned annotations.
- Support MIDI import and playback as a reference/practice aid, with a synced piano visualizer.
- Support practice mechanics: metronome, A-B loop, auto-scroll, hands-free page turns, count-in.
- Fast, reliable offline-first reading and playback — no dependency on network access during practice or performance.
- Simple, distraction-free UI suited to quick access during rehearsal, styled with Material 3 and One UI–inspired conventions.
- iOS support, planned for a later phase (Flutter chosen partly to make this feasible).

## 4. Non-Goals

- Not a music notation editor (not competing with MuseScore/Sibelius) — Fermata annotates existing scores, it doesn't create new engraved notation from scratch.
- No cloud sync/collaboration in v1 (may be considered later). A manual backup/restore export is provided instead.
- No practice recording (audio/MIDI-in capture of the user's own playing) in v1 — deferred, see Section 6A.
- No companion web UI in v1 — deferred, see Section 6A. All MIDI and annotation editing happens in the app itself for now.
- iOS is a later phase, not part of the initial Android release.

## 5. Target Platform & Stack

- **Framework:** Flutter (Dart), Android target.
- **Rationale for Flutter:** single codebase, strong custom-rendering/canvas support (important for annotation layers and the piano visualizer), good performance for gesture-heavy UI, future cross-platform option (iOS, web UI reuse).
- **Local storage:** on-device file storage for score/MIDI/recording assets + a local database (e.g., sqlite via `sqflite` or `drift`) for metadata (library entries, tags, setlists, annotation data, playback edit state).
- **Rendering:** PDF pages rendered via a PDF rendering package (e.g., `pdfx` or `syncfusion_flutter_pdfviewer`) with a custom annotation overlay drawn on top using Flutter's `CustomPainter`/canvas APIs.
- **UI system:** Material 3 (Flutter's Material widgets/theming), with visual styling drawing on Samsung One UI conventions — large bold headers, pill-shaped search/buttons/chips, generously rounded cards, bottom navigation with a pill highlight on the active tab.

## 6. Core Features (v1 scope)

1. **Library**
   - Import PDF (and scanned image) scores from device storage.
   - Multi-page/multi-file import: combine several scanned pages or PDFs into a single score entry.
   - Duplicate detection on import (e.g., by file hash or title+composer match) to avoid the same piece being added twice from different sources.
   - List/grid view of scores with title, composer, tags/setlists.
   - Basic search and filtering.

2. **Score Viewer**
   - Page-by-page or continuous scroll viewing.
   - Pinch-to-zoom, pan.
   - Fast page navigation (thumbnails or page jump).
   - Auto-scroll mode: scrolls the score at a set pace, optionally locked to the MIDI playback tempo, so the player doesn't need a free hand to turn pages.
   - Bluetooth page-turn pedal support (standard AirTurn/PageFlip-style pedals, which typically emulate keyboard arrow/media-key presses) and tap-anywhere-to-advance as a non-pedal alternative.

3. **Annotation Layer**
   - Freehand pen/drawing tool (multiple colors, adjustable stroke width).
   - Highlighter tool.
   - Text notes/callouts anchored to a position on the page.
   - Music-specific stamps: quick-insert common symbols (fermata, accent, crescendo/decrescendo hairpin, fingering numbers) instead of freehand-only for common markup.
   - Eraser / undo-redo for annotations.
   - Annotation layers/versions: e.g. a "teacher's edits" layer and a "my fingering" layer on the same score, toggled independently rather than mixed into one undifferentiated set of marks.
   - Annotations persisted per-page, per-score, overlaid on render (not baked into the source file, so the original stays intact).
   - Annotations will also be viewable/editable from the companion web UI once that ships (see Section 6A — deferred to a later version), since both will read the same local data.

4. **Organization**
   - Tags for loose grouping (e.g., "Warm-ups").
   - Setlists: an ordered list of scores for a specific performance, distinct from tags — order matters and is preserved, unlike a tag/collection.
   - Sort by title, composer, recently opened.

5. **MIDI Import & Playback**
   - Import `.mid`/`.midi` files into the library alongside PDF/image scores.
   - Play back imported MIDI on-device (instrument/soundfont choice TBD).
   - Associate a MIDI file with a score entry (e.g., a reference recording for a piece) or treat it as its own library item.
   - **Optional Optical Music Recognition (OMR) path**: in addition to manual MIDI import, generate MIDI/MusicXML directly from an already-imported scanned/photographed score, so the Piano Visualizer and playback features work without the user needing a separate MIDI file. See Section 9A for the specific approach under consideration (homr) and its trade-offs.
   - Count-in (e.g., a bar of clicks) before playback starts, so the player can come in on time.
   - Tempo-independent pitch: slowing playback down for practice uses time-stretching rather than naive resampling, so slowed audio doesn't drop in pitch.
   - A-B loop: mark a start/end point (by time or measure) and loop just that range — the core "practice this bit until it's solid" mechanic.
   - Metronome: standalone click track, independent of or synced with the MIDI tempo control.

6. **Piano Visualizer**
   - An on-screen virtual piano keyboard that highlights keys in sync with MIDI playback, so the user can see which notes are sounding in real time.
   - Lives alongside the MIDI playback controls (tempo, loop, mute) as another view/panel on the same screen.
   - Supports a landscape orientation mode: the keyboard spans the full screen width, giving more usable key width and room for a wider falling-notes lane — the natural way to actually play along.
   - Falling-notes view (notes scrolling toward the keyboard) alongside simple key-highlighting.

7. **Backup & Restore**
   - Export-all-to-a-file and import-from-file, as a manual safety net given the amount of annotation/practice effort that accumulates without any cloud sync in v1.

8. **Accessibility**
   - Font size and contrast scaling for the app's UI chrome (library, toolbars, dialogs) — not the score content itself, which renders at native resolution/zoom. Material 3's theming makes most of this close to free.

## 6A. Deferred to a Later Version

These were considered for v1 but pushed out — tracked here so they aren't lost, with the v1 features they'll eventually hook into noted for context.

- **Practice Recording**: recording the user's own playing (audio, and/or MIDI-in from a connected keyboard/controller) to compare against the reference MIDI. Deferred because it pulls in its own hardware-compatibility questions (MIDI-in over USB-OTG/BLE) and storage-growth concerns (audio recordings can grow the app's on-device footprint quickly, needing a retention/cleanup story) that are independent of getting the core score-keeping/annotation/MIDI-playback loop working first. Will attach to the MIDI Import & Playback and Score data model once scheduled.
- **Companion Web UI**: the Flutter Web build (hosted locally by the phone) for editing MIDI playback and annotations from a browser. Deferred because its local web server has its own lifecycle/discovery/concurrency design work (see Open Questions) that's separable from shipping the app itself; the app's own MIDI and annotation editing UI covers the same functionality for v1, just without the browser surface. Also carries its own risks when scheduled: battery/background-execution implications of running a local server on Android, and concurrency between a browser tab and the app editing the same data.

## 7. Architecture Sketch

```
┌─────────────────────────────┐
│         UI Layer            │  Flutter widgets: Library, Viewer, Annotation Toolbar,
│                              │  MIDI Playback, Piano Visualizer, Setlists, Settings
├─────────────────────────────┤
│      State Management       │  (e.g., Riverpod / Bloc — TBD)
├─────────────────────────────┤
│   Domain / Services Layer   │  ScoreRepository, AnnotationRepository, ImportService,
│                              │  MidiPlaybackService, PedalInputService, BackupService
├─────────────────────────────┤
│        Data Layer            │  Local DB (metadata, annotation vector data, setlists,
│                              │  playback edit state) + File storage (scores, MIDI,
│                              │  exported backups)
└─────────────────────────────┘
```

(RecordingService and LocalWebServerService are deferred along with Practice Recording and the Companion Web UI — see Section 6A — and will slot into this same layering once scheduled.)

- **Annotations as data, not pixels:** store annotation strokes/notes/stamps as structured data (points, color, tool type, page reference, layer id) rather than flattening them into the rendered image. This keeps originals untouched and supports layers/versions and export toggling.
- **Page rendering + overlay composition:** the PDF page renders as an image/texture; the annotation canvas sits in a `Stack` above it, sized/scaled to match the page's coordinate space so annotations stay aligned across zoom levels and orientations.
- **Playback + visualizer share a clock:** MIDI playback position drives both the audio engine and the piano visualizer/falling-notes view off a single shared timeline, so they can't drift out of sync — the auto-scroll feature in the Score Viewer can optionally subscribe to the same clock.
- **Pedal input as a keyboard-event source:** most Bluetooth page-turn pedals present as HID keyboards, so pedal support is implemented as a mappable key-event listener (arrow keys / media keys → "next page" / "previous page" / "toggle playback") rather than a pedal-specific protocol.

## 8. Data Model (draft)

- **Score**: id, title, composer, file path, date added, tags[], setlist ids[], linked MIDI id (nullable)
- **Setlist**: id, name, ordered score ids[]
- **Annotation**: id, score id, page number, layer id, type (pen/highlight/note/stamp), points/geometry or stamp type, color, style, timestamp
- **AnnotationLayer**: id, score id, name (e.g. "My fingering", "Teacher's edits"), visible (bool)
- **Note** (text annotation): id, score id, page number, position, text content
- **MidiTrackFile**: id, file path, title, associated score id (nullable), playback edit metadata (tempo overrides, loop start/end, muted channels, pitch-preserved flag)
- **PedalMapping**: id, key code, mapped action (next page / previous page / play-pause / etc.)

(**Recording** and any web-UI-specific tables are deferred along with those features — see Section 6A.)

## 9. Open Questions / Alternatives Considered

- **State management choice** — Riverpod vs Bloc vs simple ChangeNotifier: needs a decision based on team familiarity and app complexity.
- **PDF rendering package** — evaluate `pdfx` (lighter, open-source) vs `syncfusion_flutter_pdfviewer` (more features, commercial license considerations) vs rendering pages to images via `pdf_render`.
- **Image-based scores (scanned sheet music)** — worth supporting from v1, or defer? Affects import pipeline design.
- **Duplicate detection method** — file hash (exact-duplicate only) vs fuzzy title/composer matching (catches re-scans/re-exports but risks false positives); likely start with hash-based and treat metadata matches as a soft suggestion, not an automatic block.
- **Cloud sync** — deferred for general library sync. Backup/restore export is the interim safety net.
- **MIDI playback engine** — need a Flutter-compatible MIDI/soundfont playback library (e.g., `flutter_midi`, `flutter_sequencer`) capable of also supporting time-stretching for tempo-independent pitch; confirm what an "edit" means once the companion web UI (Section 6A) is scheduled and also produces edits.
- **Time-stretching approach** — a soundfont-based synth re-renders naturally at any tempo without pitch shift, but if audio playback (rather than synthesized MIDI) is ever supported, a proper time-stretch algorithm (e.g., phase vocoder) would be needed; scope this once the "is this MIDI-only or also audio-file playback" question is settled.
- **Pedal compatibility** — most Bluetooth page-turn pedals emulate HID keyboards, but exact key codes vary by brand; a configurable mapping (per PedalMapping above) is safer than hardcoding one pedal's codes.
- **Backup format** — a single archive (zip) containing the DB export + all asset files is simplest.
- **Export** — should annotated scores be exportable as flattened PDFs? Useful for printing/sharing but adds complexity.
- **iOS timing** — confirmed as a later phase; worth flagging any Flutter plugin choices now (PDF rendering, MIDI playback, pedal support) that lack iOS support, to avoid a rewrite later.
- **MIDI-in for recording** and **local web server on-device / discovery** — both deferred along with the features they support (Section 6A); revisit when Practice Recording and the Companion Web UI are scheduled.

## 9A. Candidate: OMR-Generated MIDI (homr)

[liebharc/homr](https://github.com/liebharc/homr) is an Optical Music Recognition tool that converts photographed or PDF sheet music into MusicXML, which could in turn drive MIDI playback and the Piano Visualizer without requiring the user to separately import a MIDI file — closing the gap between "I scanned my sheet music" and "I get a working reference recording and visualizer" in one step.

**How it works:** a two-stage pipeline — UNet-based image segmentation (staff lines, noteheads, stems, bar lines, clefs) adapted from the `oemer` project, followed by a transformer model (based on Polyphonic-TrOMR) that performs end-to-end symbol recognition per staff (pitch, rhythm, articulation, dynamics) and emits MusicXML.

**Why it's attractive for Fermata:**
- Removes a whole manual step (hunting down or creating a separate MIDI file) for the MIDI/visualizer features to work at all.
- There's existing Android precedent: [Andromr](https://github.com/aicelen/Andromr) already wraps homr for an Android app, which is a useful reference for how to handle the on-device/runtime problem below.

**Trade-offs and open questions to resolve before committing:**
- **Runtime mismatch**: homr is a Python project (UNet + transformer, run via Poetry/pip, optional GPU acceleration via CUDA/ROCm). Fermata is Flutter/Dart on Android. Integration options: (a) convert the models to a mobile-friendly runtime (TFLite/ONNX) and reimplement the pipeline around them, (b) bundle a Python runtime on-device, or (c) call out to a server running homr. Each has very different cost, offline-availability, and privacy implications — and (c) conflicts with the project's offline-first goal.
- **Licensing**: homr is AGPL-3.0 (copyleft). Depending on how it's integrated (in-process library vs. a separate networked service), AGPL's terms could require Fermata's own source to be made available. This needs a real legal review before adoption, not just a build-time decision.
- **Accuracy limitations** (per homr's own documentation): current recognition focuses on pitch and rhythm on treble/bass clef, and neglects dynamics, articulation, and double sharps/flats. Good enough for a visualizer/reference track, not something to present as authoritative notation.
- **Scope boundary**: if adopted, OMR-generated MIDI should likely be presented as a best-effort auto-generated reference (editable/correctable, akin to OCR text needing proofreading) rather than silently treated as equivalent to a hand-authored MIDI import.

**Recommendation:** treat as a v1.x/stretch feature rather than core v1 scope — the runtime integration and licensing questions above should be resolved (including a look at how Andromr handled them) before it's committed to a milestone.

## 10. Risks

- PDF annotation alignment across zoom/scroll can be finicky — needs careful coordinate-space handling to avoid drift, especially once layers and stamps add more overlay content.
- Performance on large multi-page scores (rendering + overlay) needs testing on lower-end Android devices.
- Touch-based freehand drawing precision (fingertip vs stylus) may need different UX affordances (e.g., stylus-only mode toggle, palm rejection considerations).
- MIDI playback fidelity depends on soundfont/plugin choice and may vary in quality across devices.
- Keeping the piano visualizer, auto-scroll, and audio playback all in sync on a single shared clock is more moving parts than playback alone — worth prototyping the shared-clock approach early rather than bolting sync on after each feature ships independently.
- Bluetooth pedal hardware support on Android is inherently device-dependent — plan for a fallback (on-screen controls) in every feature that depends on external hardware.
- Committing to Flutter plugins without iOS support now creates rework when the iOS phase starts — worth auditing plugin choices against iOS availability early, even though iOS isn't in this phase.
- If OMR (Section 9A) is pursued, the Python/Dart runtime mismatch and AGPL licensing terms are both significant enough to derail the feature late if not resolved up front — treat them as go/no-go questions, not implementation details to sort out during development.

## 11. Milestones (suggested)

1. Score import (incl. multi-page/multi-file, duplicate detection) + library list.
2. Basic PDF viewer (pan/zoom/page nav).
3. Annotation layer v1 (pen + highlighter, persisted).
4. Text notes + music stamps + eraser/undo.
5. Annotation layers/versions.
6. Tags/setlists + search.
7. MIDI import + basic on-device playback + metronome.
8. A-B loop + count-in + tempo-independent pitch.
9. Piano visualizer (portrait), then landscape mode.
10. Auto-scroll + Bluetooth pedal support in the Score Viewer.
11. Backup/restore export.
12. Accessibility pass (font/contrast scaling).
13. Polish pass: performance tuning, low-end device testing.
14. iOS phase: audit/replace any Android-only plugins, port UI.
15. (Stretch, pending go/no-go) OMR-generated MIDI via homr or similar — contingent on resolving the runtime and licensing questions in Section 9A.

### Later Version (post-v1)

16. Practice recording (audio, then MIDI-in if feasible).
17. Local web server + Flutter Web UI build for playback + annotation editing.