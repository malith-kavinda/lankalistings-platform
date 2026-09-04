---
name: forge-gap-check
phases: [engineering]
description: "Pre-spec gap sensor — use before fleshing out any feature spec body beyond `## Context`. Scans the PRD, live signals, risks, discovery notes and dependency specs, then reports Blockers (which halt drafting) and Warnings. Surfaces gaps, never decides them. Feature specs only — PRD-level gaps are forge-prd-author's."
---

# forge-gap-check

Per-feature pre-spec sensor. Surface ambiguities in the inputs *before* the spec body is drafted. **Blockers are reported to the session and HALT — they are never written into the spec.** Warnings (`W-N`) are appended to the target feature spec's `## Open Questions` section, but only when no Blocker is present.

## When to use

- About to flesh out a feature spec body beyond `## Context`
- User says "let me spec out X" / "let's start the X spec"
- A stub spec exists at `.forge/specs/<feature>-spec.md` (created by Gate 3) and only `## Context` has content
- Re-run after resolving Blockers to confirm no new gaps surfaced

## When NOT to use

- Before Gate 3 has run (no stub specs to target yet)
- For PRD-level gaps — that's `forge-prd-author` territory
- After the spec is approved — revise the spec via the Spec Revision Convention instead (see `.claude/rules/specs.md`)

## Inputs read (in order)

1. The target spec itself (`.forge/specs/<feature>-spec.md`) — needed to find existing IDs and the matched PRD section
2. `.forge/project-prd.md` — find the matched feature in `## Feature Decomposition` (case-insensitive title match). Also read `## Risks` for `R-PRD-N` risks touching this feature.
3. `.forge/project-prd-signals.md` — open (`⏳`) and partial (`◐`) open questions whose `Blocks` column names this feature. After the PRD trichotomy split, live OQs live here, **not** in `project-prd.md` (see `.claude/rules/prd.md`). Each one is a candidate Blocker.
4. `.forge/discovery/feature-inventory.md` (if present) — replicate / redesign / defer / discard classification. If empty/template-only, classification may live in `project-prd.md` `## Reference System Classification` — check there before flagging a missing classification.
5. `.forge/discovery/meeting-notes/*.md` — only files mentioning the feature title (case-insensitive substring match)
6. `.forge/design/architecture.md`
7. `.forge/features.md` — read this feature's `Blocked By` cell to know which other specs to read
8. Each dependency spec named in `Blocked By` — read its header `Status:`. A dep **not** at `Status: approved` (draft / in-review / missing) is a Blocker (the contract this feature consumes is not yet locked).

## Procedure

### 1. Locate target

The target spec is either passed as an argument (`<feature>` or full path) or inferred from the file most recently being edited. If no target can be determined, stop and ask: *"Which feature spec should gap-check run against?"*

### 2. Validate target exists

Stop with this message if no stub spec is found at the expected path: *"No spec at `.forge/specs/<x>-spec.md`. Run `/forge-decompose` first to create stubs, or create the stub manually from `_TEMPLATE-spec.md`."*

### 3. Parse existing IDs

Read the target spec's `## Open Questions` section. Extract bullets whose ID matches `^W-\d+$` and record the highest existing `W-N`; new Warnings continue from that value + 1. **Blockers are not read from the spec** — they are never persisted there (Step 5), so they are numbered fresh from `B-1` each run for the session report (Step 6) and re-derived from source every time.

If the section is missing, create it (it is required per `_TEMPLATE-spec.md`).

### 4. Read inputs and classify gaps

Walk the input list above. Classify findings as:

**Blockers (`B-N`)** — gaps that prevent meaningful spec authoring. A Blocker comes from one of three sources — **deps, open questions, or risks** — and any one of them halts drafting (see Step 7):

- **Dep:** a `blocked_by` dependency spec is not at `Status: approved` (draft / in-review / missing), or has unresolved Blockers of its own — the contract this feature consumes is not locked.
- **OQ:** an open (`⏳`) or partial (`◐`) open question in `project-prd-signals.md` whose `Blocks` column names this feature.
- **Risk:** a feature-scoped, unresolved risk (`R-PRD-N`) whose subject is this feature's **core mechanism** (e.g., the permission model for a permission-centric feature) and that has no recorded mitigation.
- Domain entity referenced in PRD but undefined in `## Business Domain — Key Entities`
- Feature classified as "redesign" but no behavioral target stated anywhere
- Contradictions between PRD and `architecture.md` for this feature
- Required inputs are missing entirely (e.g., the PRD has no entry for this feature in `## Feature Decomposition`)

**Warnings (`W-N`)** — gaps that allow drafting but should resolve before the plan:

- An **accepted-with-mitigation** engagement risk (`R-PRD-N` / `R-ARCH-N`) that touches this feature only peripherally — surfaced for context, not a halt. (Risks already injected by `inject-relevant-risks-spikes.sh` need not be duplicated unless they rise to Blocker level above.)
- PRD says "TBD" / "eventually" / "soon" for a bound relevant to this feature
- Non-functional requirements vague (no perf number, no error-handling stance)
- Multiple meeting notes have conflicting wording but no explicit decision was logged
- No reference-system classification for this feature in either `feature-inventory.md` or PRD `## Reference System Classification`, when other features are classified

### 5. Record findings

**If any Blocker is present, write nothing to the spec — skip straight to Step 6 (report) and Step 7 (halt).** Blockers are reported to the session only; the skill never mutates the spec while the feature's contract is unknowable. *Why:* the spec is a contract — gap-check must not auto-annotate it under a Blocker. Blockers are re-derived from source on every run, so nothing is lost by not persisting them.

**If only Warnings were found (no Blockers)**, append the new `W-N` entries to the spec's `## Open Questions` section in this exact format:

```markdown
- **W-1** [YYYY-MM-DD, gap-check] PRD says "eventually" for batch-import; pin a phase before plan.
```

Each entry: ID (next unused `W-N`), ISO date, source tag `gap-check`, then a single sentence stating the gap and what closes it.

**Existing entries are never modified or deleted.** Resolution is human work — the user removes a bullet and folds the answer into the relevant spec section.

### 6. Report findings to session

Show every finding — Blockers and Warnings — so the user sees them without opening the spec:

```
## forge-gap-check findings — <feature> — YYYY-MM-DD

| ID | Class | Source | Gap |
|---|---|---|---|
| B-1 | Blocker | dep | Dependency spec #<ticket> is at Status: draft... |
| W-1 | Warning | risk | PRD says "eventually" for batch-import... |
```

Then state what was written:
- **If Blockers were present:** *"N Blocker(s) reported — nothing written to the spec (see Step 7)."*
- **If only Warnings:** *"M Warning(s) appended to .forge/specs/<feature>-spec.md `## Open Questions`. No existing entries modified."*

If no new gaps were found: print *"No new gaps. Existing Warnings: W-2, W-5."* and exit without writing.

### 7. Halt (only if Blockers are present)

If any Blocker is present, **HALT**. Do not auto-continue, and do not offer a `[y/n]` prompt that proceeds on a bare "yes". The skill has written nothing to the spec (Step 5); the Blockers live only in the session report (Step 6). Print:

```
HALT — <N> Blocker(s) reported for <feature>. These come from deps / open
questions / risks and must be cleared before the spec body is drafted.
Nothing has been written to the spec.

Ask the human how to proceed:
  • Resolve — answer each Blocker and fold the decision into the relevant
    PRD/spec section (approve a draft dep via /forge-spec-review; answer an
    OQ via the procedure in .claude/rules/prd.md).
  • Waive — with explicit human sign-off, the human records the waiver and
    its reason where they choose (e.g. the spec's ## Notes).

Re-run forge-gap-check after resolving — Blockers are re-derived from source,
so a cleared Blocker simply stops being reported.
```

In auto-mode orchestration this stops the orchestrator and escalates to the human — Blockers are explicitly outside any conservative auto-policy.

The halt is **prompt-enforced** — by this Step 7 AND by `forge-spec-author` Step 2 (the dual-enforcement contract that replaced the retired `guard-spec-blocker-halt.sh` hook). Because gap-check never writes `**B-N**` into the spec, no hook backstop is needed; the contract file is left untouched under a Blocker by construction.

If only Warnings were found, no halt — let the user proceed (Warnings are addressed during drafting or before the plan).

## Idempotency

- **Warnings:** `W-N` IDs are append-only across runs — numbering moves monotonically forward from the highest `W-N` already in the spec; resolved IDs are never reused.
- **Blockers:** re-derived from source (dep-spec status, `project-prd-signals.md`, `## Risks`) on every run and never persisted, so a re-run after a Blocker is cleared simply stops reporting it. `B-N` labels are session-local and renumber from `B-1` each run.
- A re-run with no new gaps prints existing Warnings and exits without writing.
- The skill never modifies or deletes existing `## Open Questions` entries — that is the user's job.

## What this skill deliberately doesn't do

- **No new files.** Honors the per-feature-no-new-files doctrine in `.claude/rules/tracker.md` "Gate Audit Protocol".
- **No Complexity Score.** Sizing is Gate 3's job; duplicating it here adds noise without signal.
- **No automatic resolution.** The skill surfaces gaps; humans decide (resolve or explicitly waive).
- **No `tracker.yaml` writes.** This is an advisory primitive, not a gate.
- **Never writes to the spec under a Blocker.** On any Blocker the skill reports to the session and halts — the spec is left untouched (gap-check must not auto-annotate the contract while it is blocked). Only Warnings are appended, and only when no Blocker is present.
- **The Blocker halt is prompt-enforced, not hook-enforced.** It lives in this skill's Step 7 AND in `forge-spec-author` Step 2 — the documented dual prompt-enforcement contract that replaced the retired `guard-spec-blocker-halt.sh` hook. Because the spec is never written under a Blocker, there is nothing for a hook to backstop.

## Edge cases

| Case | Behavior |
|------|----------|
| Stub spec doesn't exist at expected path | Stop with: *"No spec at `.forge/specs/<x>-spec.md`. Run `/forge-decompose` first."* |
| `## Open Questions` section missing in spec | Create it; this would only happen if the template was deviated from |
| Feature title not found in PRD `## Feature Decomposition` | Surface a Warning (`W-N`): *"Feature title not found in PRD; gap analysis ran without PRD context."* |
| `feature-inventory.md` missing or template-only | Fall back to PRD `## Reference System Classification`; only Warn if neither classifies this feature (and others are classified) |
| `project-prd-signals.md` missing (pre-trichotomy PRD) | Skip the signals input silently; fall back to any inline `## Open Questions` in `project-prd.md` if present |
| All discovery directories missing | Run with whatever inputs exist; surface a Warning if nothing was readable |
| Existing entries contain non-`W-` bullets | Leave them alone; only IDs matching `^W-\d+$` participate in the Warning numbering counter |

## Related

- Spec template: `.forge/specs/_TEMPLATE-spec.md`
- Gate 3 (creates the stubs this skill operates on): `/forge-decompose`
- PRD authoring counterpart (engagement-level): `forge-prd-author`
- PRD trichotomy + OQ lifecycle: `.claude/rules/prd.md`
