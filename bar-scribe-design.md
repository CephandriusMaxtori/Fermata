# bar-scribe — design

A static, client-side tool that reads a score PDF and writes a sidecar file of barline
positions, so Fermata's bar-by-bar view works on scores it cannot read today.

Status: design only. Nothing implemented. Written 2026-10-03 while working through
issues [#3](https://github.com/CephandriusMaxtori/Fermata/issues/3),
[#4](https://github.com/CephandriusMaxtori/Fermata/issues/4) and
[#5](https://github.com/CephandriusMaxtori/Fermata/issues/5).

## The problem

Bar-by-bar navigation (M2b, issue #2) is built and, as of #7, no longer throws. It has
also never worked on a single real score, because every score PDF on this machine is a
scan with no text layer at all:

| file | size | `/Font` | `/FontDescriptor` | `/DCTDecode` | verdict |
|---|---|---|---|---|---|
| `Mercy mercy mercy full score 1.pdf` | 5.2 MB | 0 | 0 | 9 | scan |
| `phinneasrabies25.pdf` | 176 KB | 0 | 0 | 1 | scan |
| `sheet.pdf` | 3 KB | 0 | 0 | 1 | scan |

Zero case-insensitive matches for `font` anywhere in the files, and `/ObjStm` absent, so
the object dictionaries are uncompressed and these greps are reliable rather than an
artefact of compression. The music is an embedded JPEG of a printed page.

`PdfrxPageRenderer.barLayout` calls `pdfPage.loadText()`, gets nothing, and returns
`BarLayout.empty`. `BarDetector` never sees a glyph.

This is the limitation already flagged in `Todo.md` and in `bar_detector.dart:15-18`, and
it is not a defect in the detector: it does gap analysis over glyph positions, and a scan
has no glyphs. **The `BarDetector` thresholds are unvalidated**, because the only inputs
available have never reached them.

## What this tool is not

### Not a MIDI transcription

Asked for, rejected. MIDI cannot carry what bar-by-bar view needs, structurally rather
than as a matter of difficulty:

- **No bar structure.** MIDI has ticks and tempo. Time signature is not reliably present
  in a Standard MIDI File, and barlines are not encoded at all.
- **No spatial model.** No page, no system, no x-coordinate. `StaffSystem.barRange()`
  returns fractions of page width; MIDI has nothing to return them from.
- **No notation.** No clef, key signature, noteheads, stems, beams, slurs or lyrics. A
  score is *notation*; MIDI is a *performance*.
- **No staves.** `StaffSystem` exists because music is read as two parallel rows of marks
  on a page. MIDI interleaves them into one time-ordered stream, which is exactly the
  structure bar-by-bar navigation has to preserve.

Transcribing to MIDI would make **playback** possible (M7). It cannot make bar-by-bar view
work, and it is not on the critical path to it.

### Not a reflowed PDF

`barRange()` already returns page fractions and the viewer already scrolls the original
page. A reflowed PDF would change the page layout, break the ink-alignment invariant
pinned by `page_stack_alignment_test.dart`, and force a re-rasterisation — all to produce
a number that a sidecar carries directly.

### Not full OMR

Re-typesetting the music (reading every notehead, clef and stem) is a much harder problem
than finding barlines, and there is no browser-quality implementation of it. bar-scribe
only looks for vertical strokes and does not attempt to understand the music.

## What it does

```
score.pdf ──► [browser, nothing uploaded] ──► score.bars.json ──► Fermata
```

Reads barline positions out of a PDF and writes them as page fractions, which is the
coordinate space `StaffSystem` already speaks.

### Output

```json
{
  "version": 1,
  "source": "mercy-mercy-mercy.pdf",
  "pages": [
    {
      "page": 1,
      "widthPt": 612,
      "heightPt": 792,
      "systems": [
        {
          "top": 0.104,
          "bottom": 0.146,
          "barStarts": [0.081, 0.204, 0.335, 0.462, 0.588, 0.715, 0.842],
          "confidence": 0.92
        }
      ]
    }
  ]
}
```

`version` is checked on read so a future format change fails loudly rather than silently
producing wrong bar numbers.

`barStarts` is `StaffSystem.barStarts` exactly. It starts at the system's left edge and
ends at the closing barline, because `barRange()` already runs the final bar out to
`bounds.right` — appending `bounds.right` here would manufacture a zero-width trailing
bar, which is the bug already documented at `bar_detector.dart:172-174`.

`confidence` is per-system, in `[0, 1]`. It exists because a scan gives no ground truth:
the tool cannot know whether it found the barlines or merely some vertical strokes that
look like them. Fermata should refuse to navigate a system below a threshold rather than
jump the user to the wrong bar, which is the same honesty rule the app already applies to
`positionIn` returning `null` for an untrustworthy count.

A system that cannot be measured is **omitted**, not guessed. An empty `systems` array
means "this page has no bars" and the app falls back to page turning.

## Pipeline

Runs entirely in the browser via pdf.js. No server, no upload, nothing leaves the machine
— worth stating plainly, since sheet music is copyrighted and a hosted transcription
service would be a problem in itself.

1. **Rasterise** the page at ~200 DPI. Above ~150 DPI staff lines and barline gaps stop
   improving and the page gets slow; below ~100 DPI they blur together.
2. **Binarise** with an adaptive threshold. A scan's background is never uniform —
   book gutter, shadow, page curl — so a global threshold loses a whole edge of the page.
3. **Deskew**, estimating rotation from the distribution of horizontal ink runs. **This
   must come first**: at 2° of skew every subsequent vertical projection is smeared and
   the vertical stroke test below fails everywhere.
4. **Find systems.** Rows containing ink, grouped into bands. Within a band, locate the
   five staff lines by horizontal projection. A staff is *taller* than one line of text,
   which is what separates it from lyrics and titles without recognising any characters.
5. **Find barlines.** Within a system's vertical extent, a barline is a column of dark
   pixels spanning most of the staff height. Note stems are the confusable case: they are
   shorter and do not reach both edges, which is what the height threshold separates.
6. **Confidence.** From the evenness of the barline spacing and the height consistency of
   the strokes found. Real engraving is regular; a wrong answer usually is not.

Each stage degrades rather than guesses. A page where staff lines are not found yields no
systems for that page.

### Failure modes, stated in advance

- **Skew and low contrast** are the two that will actually bite, which is why deskewing
  and adaptive thresholding are steps 3 and 2 rather than afterthoughts.
- **Stems vs barlines** on music with very short staves.
- **A scan of an already-low-quality photocopy** may have no usable threshold at all.
- **Dense semiquaver runs** close up a measure's interior, so its trailing gap stops
  standing out. Same limitation `bar_detector.dart:22-25` documents.

## The honest cost

**This duplicates `StaffSystem` in JavaScript.** The geometry, the JSON schema and the
bar semantics get a second implementation with its own bugs, and nothing tests it — a
browser tool has no place in this repo's CI, which runs `dart test` per member.

A Dart CLI in the workspace would share the models and the tests. It was chosen against
here for genuinely better reasons: zero install, no toolchain, and the guarantee that a
score file never leaves the machine. Those are real, and they are worth an untested second
implementation — but it is a trade, not a free win, and the first sign of the two
disagreeing should reopen it.

If bar-scribe is going to be maintained rather than used once, moving the geometry into
`fermata_core` as a Dart package that both the tool and the app depend on is the better
shape. That is the change to make if this proves useful.

## Fermata-side integration

Not part of this document's scope, but the shape it implies:

- `PageRenderer.barLayout` gains a sidecar path that takes precedence over `BarDetector`,
  so a score with a sidecar never runs the glyph heuristic.
- The sidecar is copied in by the import pipeline and stored score-relative, alongside
  the PDF, under the same `fermata` root. Every stored path stays relative, per the
  existing invariant in `repository_test.dart:624`.
- A sidecar whose `version` is unknown, or whose page count disagrees with the PDF, is
  ignored with a warning rather than partially applied.
- `BarNavigator` and `StaffSystem` need no changes. That is the point of matching their
  shape.

## Open questions

- **Confidence threshold.** What value is trustworthy enough to navigate? Unknown until
  this has been run against real scans and compared against the paper.
- **Whether `BarDetector` should be kept at all** once sidecars exist. If every score
  ends up with one, the glyph heuristic is a second way to be wrong.
- **Whether OMR is worth it after all**, once barlines are reliable. That is the only
  route to real playback of a scanned score, and it is a much larger project.