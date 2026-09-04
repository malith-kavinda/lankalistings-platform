# [Feature] — Findings

> Tactical learnings during this feature's development. Per-feature, scoped.
> Engagement-wide strategic lessons live in `.forge/lessons.md`. Promotion from
> findings to lessons happens during the **Reflect** phase — see
> `forge-harness-framework.md` §4 and the project `CLAUDE.md` Workflow Phases
> table for the ritual.

## Conventions

- **One entry per coherent finding.** Don't pile multiple insights into one
  entry; break them apart so each can be promoted (or not) on its own merit.
- **Newest entries at the bottom.** Append-only.
- **ID format: `F-NNN`** — per-feature counter, monotonically increasing.
  Don't reuse IDs even when an entry is moved or deleted.
- **What belongs here vs. elsewhere:**
  - Plan `## Notes` → decisions made *during planning*, before code starts
  - Plan `## Progress` → what got done; failed approaches and why
  - **This file** → tactical learnings during/after the feature (debugging
    insight, API quirk, "next time do X first") — specific to this feature
  - `lessons.md` → strategic learnings that should flow upstream or apply to
    future features in this engagement

The boundary: if removing the lesson would only affect *this* feature, it
belongs here. If it would change how *future* features are approached, it's
a candidate for promotion to `lessons.md` during Reflect.

## Promotion (during Reflect)

When the feature ships, walk this file as part of the Reflect ritual:

1. For each entry, decide: does this generalize beyond this feature?
2. If yes, abstract it into an engagement-level entry in `.forge/lessons.md`
   (assign a new `L-NNN` ID), then annotate this file's entry with
   `Promoted: L-NNN` — the bare lesson ID, no word "promoted" in the value.
3. If no, mark it `Promoted: scoped`. The entry stays here as historical
   record; it doesn't bubble up.
4. Don't delete entries. The full per-feature record is the audit trail.

---

<!-- Example entry shape — delete this comment block when the first real entry lands. -->

<!--

## F-001 — Short title naming the finding, not the feature

> Date: YYYY-MM-DD
> Context: <where it came from — debugging, code review, integration testing, …>
> Promoted: pending          # values: pending | L-NNN | scoped

<2–6 sentences on what was learned and what was done about it. Be specific
about the trigger (the bug, the failure, the surprise) and the resolution
(what now exists in the code, what convention got added). The next person
should be able to read this and understand both the lesson and the situation
that produced it.>

-->
