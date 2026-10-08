# Bar positions — design

How `StaffSystem.barStarts` gets populated, now that the glyph heuristic is gone.

Status: design only. Nothing implemented. Superseded twice; rewritten 2026-10-08.

## The requirement

Bar-by-bar navigation steps the viewer to the next measure. The viewer scrolls the
**original page raster**, so a bar position is a fraction of page width, not an index
into a list of measures. `StaffSystem.barRange()` returns page fractions and the
navigation bar scrolls and zooms accordingly.

That constraint is the whole design problem, and it is why most of what follows is
about *coordinates* rather than about *music*.

## History

**v1 — `BarDetector`, gap analysis over glyph positions (2026-10-03 to 2026-10-08).
Removed.** Read the page's text layer and treated wide horizontal gaps in a run of ink
as barlines. It was removed because it never worked, not because it was wrong.

Every score PDF checked on this machine is a scan with the music as an embedded JPEG:

| file | size | `/Font` | `/FontDescriptor` | `/DCTDecode` | verdict |
|---|---|---|---|---|---|
| `Mercy mercy mercy full score 1.pdf` | 5.2 MB | 0 | 0 | 9 | scan |
| `phinneasrabies25.pdf` | 176 KB | 0 | 0 | 1 | scan |
| `sheet.pdf` | 3 KB | 0 | 0 | 1 | scan |

Zero case-insensitive matches for `font` anywhere in the files, and `/ObjStm` absent, so
those greps are reliable rather than an artefact of compression. `pdfrx`'s `loadText()`
returned nothing for every page, so `BarDetector` never saw a glyph and every page
answered `BarLayout.empty`. **Its thresholds were never validated against real
engraving.** Shipping a feature whose only observable behaviour was "off" is worse than
not shipping it: the UI offered a bar-by-bar toggle that did nothing.

**v2 — bar-scribe, rasterise and look for the strokes (2026-10-03, designed, never
built).** Described below, in "Rejected: bar-scribe". Superseded by v3 before any code
existed, so no JavaScript was written and nothing had to be undone.

**v3 — feed positions from OMR (current).** homr is the OMR path under consideration
(`DESIGN.md` §9A). It segments bar lines as part of its UNet stage. This document is
about the part of homr's output that is *not* sufficient, and what Fermata has to add.

## What homr gives us, and what it does not

homr ([liebharc/homr](https://github.com/liebharc/homr)) converts a photographed or PDF
score into MusicXML. `DESIGN.md` §9A scopes it for playback and the piano visualizer,
which is the right scope: MusicXML carries notes, measures, clefs and time signatures,
and that is everything those two features need.

**MusicXML carries no page geometry.** It is a logical notation format. `<measure>` says
"this is measure 12", not "this is measure 12 at x=0.46 of page 3". There is no page
number, no system, no x-coordinate anywhere in the format. So:

- **Measure counts are available.** Useful and non-trivial — a system with four measures
  is steppable once you know it has four, and that is more than we have today.
- **Bar positions are not.** The viewer would have to scroll to a measure it cannot locate.

Three ways to close that gap, none of them settled:

**(a) Make homr emit coordinates.** Its UNet stage already finds the bar lines in pixel
space; it throws that away when it writes MusicXML. A side output of bar-line positions,
mapped to page fractions, is a change to homr. This is the cleanest answer and the least
likely to happen, since it needs upstream work or a fork.

**(b) Run OMR in Fermata and keep the intermediate geometry.** Only viable if the
runtime question in `DESIGN.md` §9A resolves to an in-process model (TFLite/ONNX), since
bundling Python or calling a server both conflict with offline-first. Larger project.

**(c) Map measures onto systems after the fact.** Count measures per system from the
MusicXML, then divide each system's width evenly between its bars. Cheap, fully offline,
and **wrong whenever a system does not have equal-width measures** — which is most of
them, since measures are spaced by duration, not evenly. Good enough for "the next bar is
about here", useless for landing exactly. Rejected as a default; viable as a labelled
low-confidence fallback.

Confidence, as in v2, is per-system in `[0, 1]`. Under (c) it would be low by construction,
and the honest response is to refuse to navigate rather than jump to the wrong bar — the
same rule the app already applies to `BarNavigator.positionIn` returning `null`.

## Rejected: bar-scribe

The v2 design: a static browser tool that rasterises at ~200 DPI, binarises with an
adaptive threshold, deskews, finds staff lines by horizontal projection, and finds
barlines as columns of dark pixels spanning most of the staff height. It wrote a
`score.bars.json` sidecar that Fermata read in preference to any heuristic.

Dropped because it duplicates `StaffSystem` in JavaScript — geometry, JSON schema and bar
semantics get a second implementation with its own bugs — and because a browser tool has
no place in a CI that runs `dart test` per member. If it comes back, it should be a Dart
CLI in this workspace so it shares the models and the tests.

Its pipeline notes are kept in case the problem returns: deskew **first**, or every
vertical projection is smeared; stems are the confusable case against barlines and height
is what separates them; dense semiquaver runs close up a measure's interior so its
trailing gap stops standing out.

## Integration shape

Unchanged from v2, and deliberately so — the seam was built for this and is what
survived the detector's removal:

- `PageRenderer.barLayout` is the single seam. It currently returns `BarLayout.empty` for
  every page. A source with positions is one implementation behind it, and the viewer,
  `BarNavigator` and the navigation bar need no changes.
- `PdfrxPageRenderer.textRunsFrom` is kept although nothing calls it: it is the only
  PDF-space to normalized-space conversion in the codebase, and any source reading a PDF
  text or vector layer needs it. Nine tests pin it.
- The sidecar, if that path is taken, is copied in by the import pipeline and stored
  score-relative, alongside the PDF, under the same `fermata` root. Every stored path stays
  relative, per the invariant in `repository_test.dart:624`.
- A sidecar whose `version` is unknown, or whose page count disagrees with the PDF, is
  ignored with a warning rather than partially applied.

`barStarts` is `StaffSystem.barStarts` exactly. It starts at the system's left edge and
ends at the closing barline, because `barRange()` already runs the final bar out to
`bounds.right` — appending `bounds.right` would manufacture a zero-width trailing bar.

A system that cannot be measured is **omitted**, not guessed. An empty `systems` array
means "this page has no bars" and the viewer falls back to page turning. That fallback is
the current, permanent behaviour.

## Open questions

- **Which of (a), (b) or (c).** Blocked on the runtime and licensing questions in
  `DESIGN.md` §9A, which need answering before the source can be chosen. AGPL-3.0 is the
  live risk, not the engineering.
- **Confidence threshold**, and whether a low-confidence system should be navigable at all.
- **Whether bar-by-bar is worth it without exact positions.** Honest possibility that it is
  not, and that page turning plus a measure-count readout is the better feature. Cheaper,
  and it works on every score instead of none.