# Graphical score review (experimental)

Branch: codex/graphical-review. Base: MuseScore Studio main (5.0 development), not a plugin for installed Studio 4.x.

## Use

1. Save the score once so MuseScore persists its score and measure EIDs.
2. Open **Revisione** above the score. Musical editing is blocked while this mode is active.
3. Use **Penna** or **Testo** anywhere within a score page. Text supports multiple lines.
4. **Accetta · stampa** marks drafts as printable. **Accetta · archivio** retains drafts for consultation without printing. **Scarta nuove** removes only drafts; accepted marks remain.
5. Open **Annotazioni** to change a single mark's disposition, delete it, or relocate it. **Ricolloca** then clicking on the score moves it to a new musical anchor.
6. **Termina revisione** returns to score editing. Marks remain visible and follow score layout.
7. **Salva revisione** creates a separate JSON file. **Apri revisione** validates its score/part identity before replacing the current review. Modified reviews are also saved locally for crash recovery, independently for each score/part.
8. **PDF con segni** exports the current score layout plus accepted printable marks; drafts and archived marks are omitted. Ordinary MuseScore PDF export remains unchanged.

Embedding the review inside the final MSCZ is deferred by agreement. The sidecar remains the source of review data.

## Anchor model

Each mark stores the existing persistent measure EID, stable staff ID, the nearest chord/rest segment's measure-relative beat, a fractional horizontal fallback inside that measure, and points expressed in staff-space units. The visual position comes from the current layout. The entire stroke keeps its shape; it is not stretched across newly wrapped systems.

Live lookup enumerates only measures attached to the score. Deleted measures may remain in MuseScore's EID registry for Undo, so a registry lookup alone would be unsafe. A missing measure/staff produces an orphan, never an automatic association by bar number. Undoing a deletion restores the original association. Hidden staves and collapsed measures are retained but cannot be rendered until visible. Drawings on compressed multi-measure rests require expanding them first.

Marks spanning multiple measures are anchored as one object at the initial gesture location. They may need manual relocation after major rhythmic or structural changes. Reopening an old score in software that discards EIDs can orphan its annotations.

## Validation

- `node buildscripts/review/tests/test_document.mjs`: serialization, reflow math, deletion/undo behavior, explicit relocation, acceptance/discard, malformed or wrong-score imports.
- `QT_QPA_PLATFORM=offscreen python3 buildscripts/review/tests/test_ui.py` (PySide6): loads the actual review QML component with a score adapter double and exercises drawing, text, recovery, relocation, undo/redo and score switching.
- `pyside6-qmllint src/notationscene/qml/MuseScore/NotationScene/ScoreReviewOverlay.qml`

All seven changed C++ translation units, including the new review bridge were checked with `g++ -fsyntax-only` against the checked-out MuseScore/Muse headers and Qt 6.8.3.

The `Graphical review checks` workflow runs the document and Qt UI tests and, on branch pushes, invokes the upstream Windows portable build.

These tests do not replace a full MuseScore build and end-to-end test with native scores. The branch remains a draft until that passes. No installer is supplied by this change.
