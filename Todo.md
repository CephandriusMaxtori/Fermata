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

**Baseline: `flutter analyze` clean, 318 tests passing** (90 `app` + 149 `fermata_core` + 79 `fermata_data`).
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
- [x] **`deleteScore` doesn't delete files.** Fixed — `DriftScoreRepository` now takes `FileStore` and invokes `deleteScoreAssets` when deleting a score, fulfilling the contract in `repositories.dart:34-35`. Tested in `repository_test.dart`.
- [x] **`pixelRatio` is dropped in production** (issue #10). Fixed — `PdfrxPageRenderer.render` now multiplies `fitted.width` and `fitted.height` by `pixelRatio` when calling `pdfPage.render` and `instantiateImageCodec`, and includes `pixelRatio` in the cache key.
- [x] **No re-render on rotate or resize** (issue #11). Fixed — `ScorePageView` now tracks constraint/size changes via `LayoutBuilder` and re-renders when orientation or size changes, preventing stretched rasters.
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
- [x] **`_rasteriseBitmap` leaks the `ImageCodec`** (issue #10). Fixed — `codec.dispose()` is now called after getting the first frame.
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
- [x] **Pen output read as "rope" instead of ink** (issue #1). Ink was smoothed *four* times over, and in
      an order that destroys the shape it is smoothing. Three compounding causes, all fixed:

  1. `finalize` ran simplify **before** smooth, so RDP collapsed a straight leg to its two endpoints and
     a right-angle mark reached the spline as just three points. No spline through three widely spaced
     points can turn sharply without bulging outward: a 90° corner came out as a **151° reversal**
     straying ~3 % of page width (~17 pt on A4) off the finger's path. Swapped to thin → smooth →
     simplify. Lowering the tolerance does *not* help — a straight leg collapses at any tolerance.
  2. Catmull-Rom has a continuous tangent at every control point, so it cannot represent a corner even
     once the order is fixed; the 90° turn still smeared to ~24°. `smooth` now breaks the spline into
     runs at vertices turning more than `cornerThresholdRadians` (0.7) and emits each corner vertex
     exactly once, unblurred. Real handwriting curve samples turn ~0.008–0.2 rad, so the threshold has
     an order of magnitude of headroom; it is the one tuning knob here.
  3. `AnnotationPainter` then smoothed a *fourth* time, drawing quadratics through the midpoints of
     consecutive points "to remove residual faceting" the conditioning pass had already removed. That
     cut every vertex by a fixed fraction regardless of angle: the 90° corner reached the screen as
     26°, and a mark spanning x 200–500 drew out to x 522. It is now a plain polyline.

  Net effect on a 90° drag: 151° reversal → 90° corner, and ink stays inside the box it was drawn in.
  Pinned by `stroke_conditioner_test.dart` (corner stays sharp, curve is not faceted, no bulge on either
  leg, never strays from the finger's path) and `app/test/annotation_painter_test.dart`, which is new —
  there was previously **no** test asserting anything about what the painter puts on screen.

  Two pre-existing tests used 90°-turning V shapes to stand in for "a curve". Those are corners by any
  reading and are now left sharp on purpose, so both were re-based on real arcs; they now state what they
  meant to test. `pathFor` is static and public purely so paint geometry is testable without a canvas,
  and `_paintPoints` is its only caller.
- [x] **`mipmap-*/true.png` could not build — APK step was red on `main`** (found by CI, fixed with
  issue #2). `pubspec.yaml:49` had `android: "true"` under `flutter_launcher_icons`. That key is the
  *launcher resource name*, not a flag; the tool dutifully emitted `mipmap-{m,h,xh,xxh,xxxh}dpi/true.png`
  plus `mipmap-anydpi-v26/true.xml`, and the resource merger rejects `true` as a reserved Java keyword.
  The artwork was fine — only the name was wrong. Renamed to `ic_launcher_new`, `AndroidManifest.xml:5`
  repointed. **Worth remembering: `flutter_launcher_icons.android` is a name, and a bool there will
  build a launcher called `true` or `false`.**
- [x] **Three bugs in the bar-detection path**, found while writing its tests (issue #2):
  - `NormalizedRect.fromPdfEdges` ordered the vertical edges but **never flipped the axis**. PDF's origin
  is bottom-left, so a box at y 0.90..0.95 is the *top* of the page. Un-flipped, every bar landed on the
  wrong system and it reads as bad detection rather than a coordinate bug.
  - `BarDetector._joins` tested `NormalizedRect.overlapArea`. The glyphs of a staff sit *side by side*
  horizontally and never overlap at all, so the second glyph of a row failed to join the first and every
  run became its own single-glyph band — no systems, no bars, silently. It now tests *vertical* overlap
  relative to the shorter box, which is the axis a system is defined along.
  - A degenerate glyph box was `continue`d in place instead of ending the run, so every later character
  was paired against the wrong rect (`abc` came out as `ac`). It now flushes the run.
- [x] **Uniform Catmull-Rom hooked on unevenly-spaced input** (issue #4, "Pen tool acting like a
  lasso"). Issue #1's fix reordered `finalize` to thin → smooth → simplify and that was necessary,
  but not sufficient. Uniform CR takes its tangent at a control point from the chord *across* that
  point's neighbours, `(p[i+1] - p[i-1]) / 2`, which scales with the long segment regardless of how
  short the segment being drawn is. `thin` guarantees a *minimum* spacing and nothing more, so a
  stroke drawn fast and then settled reaches the spline with one segment orders of magnitude shorter
  than the one before it. Measured: a stroke that strayed **0.0086** from the finger's path (≈4.4
  logical px on a 510px page) now strays **0.0001**. Why #1 missed it: all four of its fixtures are
  evenly spaced (ratio ≤ 1.33), which real finger input never is. Fixed by `_respace`, which re-spaces
  each corner run while still emitting its original vertices — re-spacing, not decimation, so a
  corner (a run *boundary*) can never be cut. Costs a little curvature (flatness 0.00076 → 0.00104 on
  a measured arc) and buys 7× less stray (0.000122 → 0.000018); both stay inside the 0.0015
  tolerance.
- [x] **`thin` kept its last point unconditionally**, so the final segment could be any length however
  short. A finger decelerates before lifting, making that the *normal* end of a stroke rather than an
  edge case, and it is what hands the spline the pathological spacing above. Now absorbed into the
  previous kept point when closer than `minDistance`, which moves that point to the true end position
  rather than dropping it.
- [ ] **Corner detection is anisotropic** and the docs claimed more headroom than exists. x is a
  fraction of page width and y of page height, so on A4 the same physical 45° corner measures
  **0.615 rad travelling horizontally and 0.956 rad travelling vertically** — it is preserved or
  smoothed depending on which way the pen happened to be going. Separately, the doc at
  `stroke_conditioner.dart:50-54` claimed real handwriting turns 0.008–0.2 rad, an order of magnitude
  below the 0.7 threshold; measured through `thin` with a pixel of capacitive jitter it is
  **0.16–0.46 rad**, and past ~0.006 of jitter the worst vertices cross 0.7 and `_cornerRuns` starts
  firing on noise — returning only two-point runs, so the stroke silently falls back to a raw
  polyline with no spline at all. Not fixed here: correcting it means measuring the angle in a space
  where the page is square, which is a separate change. Comment corrected, default left alone.
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

### M2b — Bar-by-bar navigation (issue #2)

Built. Tapping the page's outer thirds, or the chevrons, steps **one bar** instead of one page once bar
mode is on. Opt-in via a "Find bars" control rather than automatic:

  - Detection reads the text layer of **every** page up front. Stepping backwards off the front of a
    page has to know the last bar of the page before it, so discovering layouts lazily would leave a
  - control enabled that does nothing.
  - A score with no text layer finds nothing, so auto-running would make every scan pay a wait for no
    benefit. When detection finds no staff, the viewer stays page-based and the page picker says
    "No bars detected" rather than pretending.

**The honest limitation, stated once here:** barlines are drawn strokes, not characters.
`PdfPage.loadText` returns glyph boxes, so a barline is visible only as a gap where glyphs are absent.
`BarDetector` treats gaps wider than the system's median gap as barlines. That works on clean
digitally-engraved PDFs and **fails outright on a scan, a vector-only export, or a hand-typeset score
with no text layer** — the last being the common case for printed music. This is a progressive
enhancement, never a foundation.

- [x] **`BarDetector` removed: it had never worked on a single score** (2026-10-08). It read the page's
  text layer and treated wide horizontal gaps in a run of ink as barlines. Checked 2026-10-03 by
  inspecting the raw bytes of every score PDF on this machine — `Mercy mercy mercy full score 1.pdf`
  (5.2 MB), `phinneasrabies25.pdf` (176 KB), `sheet.pdf` (3 KB). **All three have no text layer:**
  zero case-insensitive matches for `font`, `/FontDescriptor`/`/BaseFont`/`/Widths` all absent, and
  `/DCTDecode` present, i.e. the music is an embedded JPEG of a printed page. So every score the
  project has actually been tried against is a scan, and detection has never once returned a bar.
  The thresholds in `BarDetector` (`_kBarGapFactor`, `_kMinRunsPerWidth`, `_kMinSystemHeight`) were
  therefore **never validated**, and issue #2 had been closed as working on the strength of the code
  reading correctly, not on a score where it did. Shipping a feature whose only observable behaviour
  was "off" is worse than not shipping it: the viewer offered a "By bar" toggle that did nothing.
  How to tell: a text-layer PDF contains `/Font` and `/BaseFont`; a scan contains `/Image` and
  `/DCTDecode` and no font keys at all.

  - **Kept deliberately:** `bar_layout.dart` (`TextRun`, `StaffSystem`, `BarLayout`), all of
    `bar_cursor.dart`, the navigation bar UI, and `PageRenderer.barLayout` — which now returns
    `BarLayout.empty` for every page. That interface is the seam a source with real positions drops
    into without the viewer, `BarNavigator` or the UI changing. `PdfrxPageRenderer.textRunsFrom` is
    also kept although nothing calls it: it is the only PDF-space to normalized-space conversion in
    the codebase and any future source needs it, pinned by nine tests.
  - **Why not delete the whole feature:** the navigation model is sound and fully tested; only the
    *source* of bar positions was wrong. Throwing that away means rebuilding it.
  - **The replacement is not OMR's MusicXML.** `DESIGN.md` §9A scopes homr for playback and the piano
    visualizer, which is right — but MusicXML is a logical format: `<measure>` says "measure 12", not
    "measure 12 at x=0.46 of page 3". There is no page, system or x-coordinate anywhere in it, so
    measures have to be mapped back onto the page before they can drive navigation. homr's UNet stage
    *does* find the bar lines in pixel space and discards them when it writes MusicXML; that output is
    the actual prize. Three routes, none settled — see `bar-scribe-design.md`.
  - **Open question worth taking seriously:** whether bar-by-bar is worth having without exact
    positions at all. Page turning plus a measure-count readout is cheaper and works on every score
    instead of none.
  - Still true of the vector route: the exact answer is in the page's vector drawing operators, and
    **pdfrx does not currently expose them.** When it does, it should replace
    `fermata_core/lib/src/measure/` outright rather than be merged in: "glyph gaps" and "actual
    strokes" are different sources of truth, and averaging them is worse than either.

  - Lyrics are excluded by requiring a band to be tall enough to hold several staff lines, which a line
  of lyrics never is. A one-line title is excluded the same way. *(How `BarDetector` kept sung text
  out of the layout; still the rule a future source should follow.)*
  - A system of *uniformly* spaced glyphs yields **one** bar, because no gap stands out. Inventing
  barlines by dividing the row evenly would be worse than admitting there is one. **This rule still
  binds whatever replaces the detector** — it is what rules out the "divide each system evenly by
  its measure count" route in `bar-scribe-design.md`.

Design notes worth keeping (`BarNavigator`, retained — these are independent of where the positions
came from):

  - `BarNavigator` carries `(page, system, bar)` rather than a flat index across the score. Layouts are
    discovered per page and asynchronously, so a flat count has to be rebuilt whenever any page
    finishes loading and the cursor re-based onto it. The triple makes a step "the next sibling of
    where I already am" with no global index.
  - Going **back** into a system lands on its *last* bar. Forward from bar 2 of system 1 reaches bar 1
    of system 2, so coming back must arrive at bar 2 of system 1 — otherwise reverse stepping drifts
    a bar per press, which is exactly how hands-free page turning comes to feel broken.
  - The bar number is **omitted** when a preceding page has no staff. "Bar 4 of 12" that silently
    skipped a page's worth of bars is a lie; the footer falls back to page numbers instead.

- [x] **`BarNavigator.forward` was the one function in `bar_cursor.dart` that indexed without bounds-checking**
  (`back`, `positionIn` and the page skipping all guarded). `isLast` calls it and the footer calls that
  from `build`, so a cursor pointing at a page with no staff threw a `RangeError` *mid-frame* rather
  than failing a tap — issue #5. Reachable two ways, both deterministic: detection finding nothing
  (the scan case) and then the un-gated "By bar" button, or a score whose page 0 is a title page while
  `isNavigable` is true because a later page has staff.
- [x] **Bar mode was one flag doing two jobs.** `BarNavigationBar.barMode` is documented tri-state
  (`null` not run / `false` ran-but-found-nothing / `true` found), and switching bar mode *off* wrote
  `false` into it, so one round trip through the toggle erased the fact that bars had been found and
  made the mode impossible to switch back on. Split into `_detection` (what detection found) and
  `_barMode` (is it on), with the toggle disabled when nothing was detected and `_toggleBarMode`
  refusing the switch as a second line of defence.
- [x] **`BarCursor.start` is a constant, not a lookup** — it means page 0 system 0 whatever page 0 is.
  Added `BarNavigator.firstNavigable`, and the viewer now starts there. `BarCursor.start` remains as
  the fallback so callers never handle a nullable cursor.
- [x] `_scrollToCursor` read the layout via `_currentPage` but indexed it with the *cursor's* system and
  bar, then called the assertive `barRange()`. The two desync on every bar-mode switch, since enabling
  resets the cursor to page 0 while `PageView` stays where the user was.
- [x] Detection failures are caught (`_runDetection`) and land on "nothing found". The footer reads
  `null` as "still looking", so an escaping exception stranded it on "Looking for bars..." for good.

#- [ ] **bar-scribe: extract barlines from scanned scores.** Design in [`bar-scribe-design.md`](bar-scribe-design.md).
  Every score on this machine is a scan, so bar-by-bar has never worked and the `BarDetector`
  thresholds are unvalidated. bar-scribe is a static browser tool (pdf.js, nothing uploaded) that
  rasterises, deskews, binarises, finds staff lines and then finds barline columns, emitting
  `StaffSystem`-shaped JSON with a per-system confidence score. **MIDI transcription was considered
  and rejected**: it has no spatial model, so there is nothing to derive page fractions from, and no
  bar structure either. bar-scribe duplicates `StaffSystem` in JS as a result, which is a real cost —
  if it proves useful, move the geometry into `fermata_core` and share it.

## M2 — Basic PDF viewer

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
- [x] `StrokeConditioner` — thin → smooth (Catmull-Rom, corner-preserving) → simplify (RDP), pure Dart,
      well tested. **Order and corner handling changed** — see Bugs, issue #1
- [x] Annotation persistence: compact 1/10000-integer JSON, pinned by test
- [x] `AnnotationPainter` — two-pass (highlighter under pen, `BlendMode.multiply`), `CustomPaint` in a
      `Stack` sharing the page's box, `RepaintBoundary`. Draws a plain polyline via `pathFor`; it used
      to smooth a fourth time with quadratics through midpoints — see Bugs, issue #1
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
| No CI | **Resolved** — `.github/workflows/ci.yml`: analyze, per-member tests, debug APK. Runner pinned to `ubuntu-24.04`. Both workflows green as of 2026-10-08; the release workflow had been failing to start since a Discord step referenced `secrets` in an `if`, which is not an allowed context there. |
| Bar-by-bar view never worked | **Resolved by removal** — `BarDetector` deleted 2026-10-08; every score on this machine is a scan with no text layer, so it had never returned a bar. Seam retained for a coordinate-bearing source. |
| 16 KB page sizes | Not enforced (no Play Store). Revisit only if distribution changes. |

---

## Notes / deviations

- **`BarDetector` removed in favour of feeding bar positions from OMR** (2026-10-08). Not a
  `DESIGN.md` departure — the design never promised a detection method — but it does reverse
  `bar-scribe-design.md` v2, which proposed a browser tool to find barlines in scans. That tool was
  never built, so nothing was undone. **The departure worth recording:** the project's position is now
  that bar-by-bar navigation needs *page coordinates*, and OMR's MusicXML does not have them, so
  "use OMR" does not by itself restore bar-by-bar view. The navigation model
  (`bar_layout.dart`, `bar_cursor.dart`, the UI, `PageRenderer.barLayout`) is retained unchanged and
  `barLayout()` returns `BarLayout.empty` for every page until a coordinate-bearing source exists.
  `DESIGN.md` §9A's homr work is unaffected — it is scoped for playback and the piano visualizer,
  which MusicXML does fully serve. See `bar-scribe-design.md` for the three candidate routes.
- **`org.gradle.caching=true`, and no NDK cache** (2026-10-08). The NDK is 13.6s of a 3m24s
  `Build debug APK` job, but the unpacked NDK is ~2.9GB and `actions/cache` would move more bytes
  than the download it replaces. The Gradle build cache targets the ~98s of gradle work around it and
  needs no new cache step, since `~/.gradle/caches/build-cache-1` is already inside the tree
  `actions/setup-java`'s `cache: gradle` preserves.
- **Obtainium is the update channel, and `INTERNET` is the cost of an in-app check.** Not a
  `DESIGN.md` departure — §4's "no store, sideload only" left the *mechanism* open, and Obtainium is
  the one that installs from the project's own releases. Two halves, deliberately separable:
  `.github/workflows/release.yml` publishes a signed APK on a `v*` tag (the distribution side), and
  `app/lib/src/update/` deep-links into Obtainium from Settings (the hand-off). The in-app GitHub
  check is why the app needs a network permission it otherwise would not; the release half needs
  none. If the permission ever has to go, delete `updateCheckProvider` and keep
  `ObtainiumApp` — Obtainium's background poller already does the checking.
  See [`docs/obtainium.md`](docs/obtainium.md).
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
- **`android:label` is hand-set, not derived.** `flutter create` copied it from the pubspec `name:`
  (`fermata`, which has to be a legal Dart identifier), so the launcher read "fermata" in the app
  drawer. Fixed to `"Fermata"` (issue #3). Renaming the pubspec `name:` will *not* fix this — that
  field has to stay a valid identifier, so the label in `AndroidManifest.xml` is the only place the
  display name lives, and the two will drift apart on every future rename.
- **An earlier draft of this file credited `pdfx` and assumed a fresh single-package project.** Both
  wrong: the real repo is a pub workspace using `pdfrx`. Corrected after reading the code.