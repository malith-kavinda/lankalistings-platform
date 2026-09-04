# LankaListings — PRD History

> Sidecar to [`project-prd.md`](project-prd.md). Carries **audit trail only** — questions that have been answered (with the answer folded into the PRD body) and PRD revisions.

## What lives here

- **Resolved open questions** — every OQ that was once in [`project-prd-signals.md`](project-prd-signals.md) and has since been answered. The answer itself has already been folded into [`project-prd.md`](project-prd.md) (or into an AD in `.claude/CLAUDE.md` for architectural decisions). The entry here is the historical record with a pointer to where the answer now lives.
- **PRD revisions** — every meaningful change to [`project-prd.md`](project-prd.md) after first sign-off. The PRD body itself no longer carries a `## Revisions` section; entries are appended here instead.

## What does NOT live here

- **Open / partial OQs** — those live in [`project-prd-signals.md`](project-prd-signals.md).
- **The live contract** — lives in [`project-prd.md`](project-prd.md).

## How to add an entry

The OQ resolution procedure and the revision convention are defined in [`.claude/rules/prd.md`](../.claude/rules/prd.md). Three-step lift on resolution: fold the answer into the PRD body, move the OQ row from `project-prd-signals.md` to `## Resolved Open Questions` below, append a `### Rev N` entry under `## Revisions`.

Append-only. No curation in v1 — if this file becomes hard to navigate later, that's a signal to revisit the lifecycle, not to silently prune.

## Resolved Open Questions

> Each entry preserves the original question and records where the answer was folded. `Resolved in Rev N: see §X` or `see AD #Y` is the canonical pointer format.

| # | Section | Topic | Question | Resolution | Resolved in | Date |
|---|---------|-------|----------|------------|-------------|------|
| | | | | | | |

## Revisions

> One `### Rev N — YYYY-MM-DD` heading per revision, newest at the bottom. Body is free-form prose: what changed, why, and (if applicable) which OQ this resolved.

<!-- Example shape:

### Rev 1 — YYYY-MM-DD
- **Changed:** Tightened §Per-Role Capability Matrix to enumerate each role's allowed actions explicitly.
- **Why:** OQ-7 surfaced ambiguity between Counsellor and Supervisor write permissions.
- **Resolves:** OQ-7 (moved to `## Resolved Open Questions` above).
- **Approved by:** [name]
-->
