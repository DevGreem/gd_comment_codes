# Design documents

Index of design material in this repository. Documents published here are **snapshots for feedback**;
the living copy of a brainstorming brief stays at the repository root (`concepts_brief.md`) and the
formal design document, once written, replaces it.

| Document | What it is | Status | Date |
| :--- | :--- | :--- | :--- |
| [gd-comment-codes-editor-hints.md](gd-comment-codes-editor-hints.md) | Comment-driven value suggestions in the script editor: concept, decisions D1–D18, open questions Q1–Q6 | RFC, awaiting feedback | 2026-11-11 |
| [../spikes/completion-api.md](../spikes/completion-api.md) | Test plan against the Godot 4.7 completion API: repo cleanup, fixtures, 17 checks with pass/fail criteria | Not executed | 2026-11-11 |

## Order of work

The RFC cannot become a formal design document until the spike answers three things: whether an
addon's entries can coexist with the engine's own completion list (spike check 1), whether the editor
exposes a place for the context selector (spike check 7), and whether the existing
`Godot-Code-Completions` addon can carry values produced by executing project code — that last one is
not a check in the spike but staging step 3 of the brief, and the spike only measures what happens when
both addons own the completion hook (check 15).

## Related files outside this folder

* `../../concepts_brief.md` — the living brainstorming brief that this RFC was copied from.
* `../../concept.md` — the first-round statement of the idea, kept for reference and superseded.
* `../../egm.config.json` — points the review skills at `./docs`.
