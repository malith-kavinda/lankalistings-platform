---
name: forge-spec-author
phases: [engineering]
description: "Draft a feature spec body from the PRD, meeting notes, and dependency specs. Use when a stub spec exists and the ask is 'spec out X' / 'draft the <ticket> spec'; runs forge-gap-check first, then leaves the spec at draft for `/forge-spec-review`. Feature specs only — PRD authoring is forge-prd-author."
---

# /forge-spec-author

Per-feature spec-drafting assistant. Mirrors `forge-prd-author`'s shape one level down: structured walk through the spec template's required sections, grounded in the engagement-level inputs that already exist. Leaves the spec at `Status: draft` for `/forge-spec-review` to audit.

## How to Use

```
/forge-spec-author <ticket>
```

`<ticket>` is the feature id, e.g. `PROJ-005`. (The `<ticket>` grammar is fixed; only the project's ticket prefix changes.) If invoked without an argument, print usage and exit.

## When to Use

- A stub spec at `.forge/specs/<ticket>-*-spec.md` exists (Gate 3 / `/forge-decompose` created it) and only `## Context` is populated.
- The feature's tracker `phase` is `backlog` or `spec`.
- The orchestrator (`/forge-deliver`) is driving the conservative auto-flow and is at the spec-draft stage.
- The user says "spec out X" / "draft the X spec" / "start writing the PROJ-005 spec".

## When NOT to Use

- The spec body is already drafted — even partially. Authoring over an in-flight draft risks overwriting human edits. Re-run only if the body is empty or matches the template stub.
- The spec is at `Status: approved` — use the Spec Revision Convention in `.claude/rules/specs.md` instead.
- Gates 1–3 haven't passed yet — the inputs the skill grounds in (PRD, architecture, feature inventory, decomposition stubs) won't exist. Run the gate commands first.
- PRD-level authoring — that's `forge-prd-author`.

## Inputs read (in order)

1. The target spec stub (`.forge/specs/<ticket>-*-spec.md`) — for the existing `## Context` content + any pre-existing `## Open Questions` from prior `forge-gap-check` runs.
2. `.forge/tracker.yaml` `features.<ticket>` — for title, priority, `blocked_by`, owner, delivery_phase.
3. `.forge/project-prd.md` — find the matched entry in `## Feature Decomposition` (case-insensitive title match); read `## Risks` for `R-PRD-N` that touch this feature.
4. `.forge/project-prd-signals.md` — open (`⏳`) / partial (`◐`) open questions whose `Blocks` column names this feature. Post-trichotomy (harness ≥ v0.24.0) live OQs live here, **not** in `project-prd.md`. `forge-gap-check` reports feature-blocking OQs as Blockers (and halts).
5. `.forge/discovery/feature-inventory.md` (falling back to PRD `## Reference System Classification`) — replicate / redesign / defer / discard classification.
6. `.forge/discovery/meeting-notes/*.md` — files mentioning the feature title.
7. `.forge/design/architecture.md` — relevant subsections.
8. `.forge/specs/<dep>-spec.md` for each `blocked_by` entry — **must be at `Status: approved`**. A dep still at draft / in-review (or missing) is a **Blocker**, not a Warning: `forge-gap-check` reports it as a Blocker and this skill halts at Step 2. Do not draft against an unapproved dependency's moving contract.
9. `.forge/specs/_TEMPLATE-spec.md` — the required section schema.
10. `.claude/rules/specs.md` — the lifecycle rules this skill must honor.

## Procedure

### 1. Validate target

```bash
TICKET="<ticket>"
SPEC_PATH=$(ls .forge/specs/${TICKET}-*-spec.md 2>/dev/null | head -1)
[ -z "$SPEC_PATH" ] && abort: "No spec stub at .forge/specs/${TICKET}-*-spec.md. Run /forge-decompose first."
```

Read the spec header — confirm `Status: draft`. Abort cleanly otherwise per the When NOT to Use table.

Read sections below `## Context`. If *any* of `## Requirements`, `## Acceptance Criteria`, `## Scope Boundaries`, `## Constraints and Dependencies`, `## Input Sources` has body content beyond the template comment, treat as in-flight: abort with: *"Spec body already has draft content beyond ## Context. Re-running forge-spec-author would risk overwriting. Either revert the file or continue manually."*

### 2. Run `/forge-gap-check` first — and HALT on any Blocker

Invoke the `forge-gap-check` skill against `$SPEC_PATH`.

**If *any* Blocker is present in gap-check's report — STOP. Do not proceed to Step 3.** This is not a soft prompt and there is no "continue anyway": Blockers come from an unapproved dependency, a feature-blocking open question (`project-prd-signals.md`), or a feature-scoped unresolved risk, and each one means the spec's contract is not yet knowable. Drafting over it produces a guess that will need a revision. gap-check reports Blockers to the session and writes nothing to the spec, so honoring the halt is this skill's responsibility. Print:

```
HALT — forge-gap-check reports <N> Blocker(s) for <ticket>. Not drafting.
Nothing has been written to the spec.

  <list each Blocker: id, source (dep / OQ / risk), one-line gap>

These must be cleared before the spec body is drafted. Asking the human how
to proceed:
  • Resolve — answer each Blocker and fold the decision into the relevant
    PRD/spec section. (Approve a draft dep via /forge-spec-review; answer an
    OQ via the OQ-resolution procedure in .claude/rules/prd.md.)
  • Waive — with explicit human sign-off; the human records the waiver and
    its reason where they choose (e.g. the spec's ## Notes).

Re-run /forge-spec-author once Blockers are cleared. gap-check re-derives
Blockers from source, so a cleared Blocker simply stops being reported; the
spec stays at draft so the orchestrator can resume.
```

The halt is **prompt-enforced** — by this step and by `forge-gap-check` Step 7. There is no `guard-spec-blocker-halt.sh` hook backstop, so honoring the halt is the agent's discipline. In orchestrator auto-mode (`/forge-deliver`) the halt stops the orchestrator and escalates — Blockers are explicitly outside the conservative auto-policy.

If gap-check returns Warnings only (`W-N`), continue. Warnings will be addressed inline during drafting (the skill answers what it can and leaves the rest in `## Open Questions`).

### 3. Read inputs

Walk the Inputs-read list above. For each, extract content relevant to this feature. Build a working synthesis:

- **PRD entry** — the one-line `## Feature Decomposition` row + any deeper section mentioning the feature.
- **Reference-system classification** — replicate / redesign / defer / discard. Drives Scope Boundaries.
- **Architecture decisions** — locate `architecture.md` decisions tagged for this feature; pull into Constraints.
- **Dependency specs** — for each approved dep, extract its public surface (entities owned, endpoints, helpers). Decide what this spec consumes vs. owns.

If a critical input is missing (no PRD entry, no architecture coverage, no dep spec for a `blocked_by` entry), surface as an Open Question and continue — `/forge-spec-review` will flag it as a structural issue if it's load-bearing.

### 4. Draft sections

Write each required section in order, respecting `_TEMPLATE-spec.md`'s schema. Apply Edit to populate, one section at a time. **Never overwrite `## Context` if it has body content — augment only if obviously stub-level.**

> Reaching this step means Step 2 found no Blockers in gap-check's report (or they were explicitly waived). If a Blocker is still live, go back to Step 2 — do not draft the body. The halt is prompt-enforced (there is no hook backstop), so this discipline is yours to keep.

**`## Requirements`** — split into `### Functional Requirements` and `### Non-Functional Requirements`. Number each (`FR-1`, `FR-2`, …, `NFR-1`, …). Anchor every requirement in a PRD line, an architecture decision, or a dep-spec contract. Each FR is a single sentence stating the system behavior, followed by a short rationale paragraph referencing the source. Aim for 6–15 FRs and 4–10 NFRs for a typical P0 feature.

**`## Acceptance Criteria`** — one checkbox per FR plus any cross-cutting NFR-derived criteria. Each AC must be testable (verb + observable outcome). Pattern: *"Given <state>, when <action>, then <observable outcome>"* or *"<endpoint>/<method> returns <status> when <condition>"*. **For a user-facing screen, and only if the project has a design reference** (`.forge/design/ui/<design-system>.md` + a prototype/mockup, or a per-screen reference file), add **observable visual ACs that name the design reference and the token / layout / state it pins** — not just "looks good". Read the design-system spec's token, component, layout, and state sections (and the per-screen reference, if one exists) and write ACs naming the specific semantic token, layout structure, or component state the screen must render: e.g. *"the table renders on a Card surface with an in-card filter toolbar, using the design system's surface and header tokens, per `<design-system>.md` §Layout"* / *"status renders as text + a colored state dot using the status-tone token (not a pill badge)"*. These visual ACs are the fidelity contract the plan (`## UI / Design Adherence`) and the pre-PR vision-diff are checked against. **For a backend-only feature, or a project with no design reference, state functional ACs only** — do not invent visual ACs.

**`## Scope Boundaries`** — both `### In Scope` and `### Out of Scope` must be populated. Pull Out-of-Scope from the reference-system inventory (`discard` / `defer`) + adjacent features that own bordering surface.

**`## Constraints and Dependencies`** — list the `blocked_by` specs with their roles. List architecture-decision IDs (`AD #N`) that constrain this feature. List PRD risks (`R-PRD-N`) that touch this feature.

**`## Input Sources`** — bulleted list pointing at the specific PRD section, architecture subsection, dep-spec FRs, and meeting-note filenames that informed the spec. Concrete paths, not narrative.

**`## Open Questions`** — preserve any `W-N` entries already added by `forge-gap-check` (Blockers are never written there — reaching this step means there were none, or they were waived). Add a final `## Open Questions` entry per Warning the drafting itself couldn't close (cite as `[YYYY-MM-DD, spec-author]` to distinguish from `gap-check` entries).

**`## Revisions`** — leave empty. This section populates after approval.

### 5. Set the header

Use a single Edit to set the header block:

```markdown
# <feature-title> — Spec

> Status: draft
> Author: <git config user.name>
> Reviewed by:
> Date: <today>
```

**Do not** write a `Reviewed-via:` annotation — that's `/forge-spec-review`'s job at approval time. Writing one prematurely defeats the `guard-spec-approval.sh` enforcement.

### 6. Update tracker

Edit `.forge/tracker.yaml` `features.<TICKET>`:

- `phase: backlog` (or `spec`) → `phase: spec`
- `last_updated: "<today>"`
- `notes: "Spec drafted via /forge-spec-author. <N> FRs, <M> NFRs, <K> ACs. <X> gap-check Warnings carried into ## Open Questions. Awaiting /forge-spec-review."`

Bump the global top-level `last_updated` to the current timestamp.

### 7. Final report

```
## Spec drafted — <ticket>

- Spec: <SPEC_PATH> (Status: draft)
- Sections written: Context (preserved), Requirements (<N> FRs + <M> NFRs),
  Acceptance Criteria (<K> ACs), Scope Boundaries (<X> in / <Y> out),
  Constraints (<deps>, <ADs>, <risks>), Input Sources, Open Questions
  (<gap-check carry-over> + <author-added>)
- Tracker: features.<ticket> → phase: spec
- gap-check: <Blockers + Warnings counts>

Next: /forge-spec-review <SPEC_PATH>
  Conservative auto-flow: pass --auto-approve-on-clean to auto-flip on
  zero-Blockers / zero-Importants Pass 2.
```

## Notes

- **Idempotent on dry stubs.** Running twice on an empty-body spec is safe (the second run sees `forge-gap-check` already populated `## Open Questions` and the drafted body — abort path #2 above catches this).
- **No spec creation.** The skill only fills body sections of stubs created by `/forge-decompose`. Creating new spec files is `/forge-decompose`'s job (Gate 3 territory). If a stub is missing, the skill aborts.
- **Conservative grounding.** Every FR/NFR cites a source (PRD line, AD #, dep spec FR). Citations make Pass 1 of `/forge-spec-review` faster and Pass 1 findings easier to apply.
- **Never auto-approve.** Even if the spec looks complete, leave at `Status: draft`. The full review cycle decides approval — this skill only authors.
- **Reviewed-via annotation deliberately absent.** Writing it here would let an attacker (or a sloppy session) skip review. `guard-spec-approval.sh` checks for the annotation at approval time only.
- **Open Question carry-over.** `forge-gap-check`'s `W-N` IDs (Warnings only — Blockers are never written to the spec) and `forge-spec-author`'s `[spec-author]`-tagged entries can coexist in the same `## Open Questions` section. `/forge-spec-review`'s sub-agent treats them as distinct sources (audit dimension §12 vs. body audit).
