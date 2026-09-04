# [Feature Name] — Plan

> Spec: `.forge/specs/<feature>-spec.md`
> Status: draft | in-review | approved
> Author:
> Reviewed by:
> Date:
> Sign-off: PENDING   <!-- human reviewer: replace PENDING with your name/initials before approving -->
> Key Workitem: `.forge/plans/<SPEC_ID>/<SPEC_ID>-decomposition-plan.md`   <!-- sub-WI plans only; points to the wave-mode Decomposition Plan. Delete this line for single-plan specs. The field name "Key Workitem" is what plan-reviewer's `key_workitem_path` parameter reads; the file it points to carries `## Test Strategy Map`, `## Acceptance Criterion Coverage`, `## Workitem Inventory`, `## Shared Contracts`. -->
> WI ID: `<SPEC_ID>-WI-X.Y`   <!-- sub-WI plans only; delete this line for single-plan specs -->

## Success Criteria
<!--
Verifiable definition-of-done for this plan, passed verbatim to the
implementation agent's `# Success Criteria` block when dispatched by
`/forge-deliver`. The agent uses this as its halt-condition: if it
finishes its subtasks but the criteria below aren't met, halt and
escalate.

In wave mode (single-plan or sub-WI), pull from:
  - The spec's AC(s) this WI/plan owns (see Decomposition Plan's
    `## Acceptance Criterion Coverage` for sub-WIs; spec directly for
    single-plan)
  - The wave's ship-state one-liner (from Decomposition Plan's
    `## Wave Ship Plan` row, or this plan's `## Wave Ship State` for
    single-plan-in-wave-mode)

Each bullet must be:
  - Verifiable by a concrete command, file inspection, or DB query
  - Scoped to what this WI alone is responsible for (not its sibs)
  - Worded as a state-on-disk-or-on-main, not a process step

Examples (use your project's commands from CLAUDE.md §Common Commands):
  - `<backend-check-cmd>` exits 0 from this WI's worktree
  - The data-layer migrations for this WI apply cleanly to an empty DB
  - `GET /api/v1/<resource>` returns the seed list shaped per
    `<ResponseType>` (contract from the wave contract / WI-1.1's plan)
  - `<e2e-cmd-scoped>` passes against `feature/<ticket>-wave-1` after
    this wave's sub-WIs are integrated

CONTRACTED-SEAM CONFORMANCE (wave mode, BE↔FE seam with a frozen contract):
  When this WI sits on a seam that has a frozen
  `.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md`, carry a
  conformance Success Criterion so the seam-test-implementer's seam test
  has a stated definition-of-done to check against:
    - server-WI: `<endpoint(s)>` responses conform to the field names,
              types, nullability, enums, and envelope declared in
              `<ticket>-Wave-<N>-contract.md` (the frozen contract is
              read-only; this WI conforms to it, never edits it)
    - client-WI: the API client/types for `<endpoint(s)>` match
              `<ticket>-Wave-<N>-contract.md` — no unchecked casts at
              the API boundary
  (Full path — once FE codegen + BE schema-conformance are wired: tighten
  to "client generated from the contract; regenerate + `git diff` clean"
  and "responses validate against the contract in an integration test".)
-->

- [ ] <verifiable bullet 1>
- [ ] <verifiable bullet 2>
- [ ] <verifiable bullet 3>

## Approach
<!-- How will this be implemented? High-level strategy. -->

## UI / Design Adherence
<!-- REQUIRED when this WI touches user-visible UI (your frontend source roots, e.g. <frontend-source-globs>). DELETE this whole section for backend-only / data-layer WIs. -->
<!-- Design system: .forge/design/ui/<design-system>.md (authoritative for tokens/components/layouts). Visual target: <prototype path the project sets> — screens must match the prototype; on conflict, the design-system spec wins. -->

- **Semantic tokens used:** <!-- design-system tokens this WI relies on; never hand-pick hex/rgb colors -->
- **Custom components:** <!-- any new component + why a design-system primitive wasn't enough; "none" = pure primitive composition -->
- **Screen layouts referenced:** <!-- design-system screen entries this WI implements, or "new route — no entry yet" -->
- **Intentional deviations:** <!-- justify any divergence from the design system/prototype, or "none" -->

## Decisions
<!-- Technical decisions made for this implementation. Reference CLAUDE.md patterns where applicable. -->

| # | Decision | Why |
|---|----------|-----|

## Subtasks

### 1. [Subtask Name]
- **What:** <!-- What this subtask accomplishes -->
- **Files:**
  - `path/to/file` — <!-- what changes -->
- **Pattern:** <!-- Reference existing patterns: "Follow the pattern in <module>/..." -->

### 2. [Subtask Name]
- **What:**
- **Files:**
- **Pattern:**

## Files to Modify

| File | Repo | Change |
|------|------|--------|

## Risks
<!-- What could go wrong? What assumptions might be wrong? -->

## Test Approach

<!--
Tier (from the Decomposition Plan's Test Strategy Map — must match):
  T1     — unit tests only
  T2     — unit + integration tests
  T3     — unit + integration + WI-scope browser E2E (and/or API seam tests)
  T-E2E  — full browser E2E suite only (no functional code)
  (single-plan specs: choose whichever tier fits the plan's scope)
See .forge/test-strategy.md for the tier model.

Fill the subsections that apply to your tier. Delete the others.
Every AC in this WI's AC-ownership row must appear in at least one test row.

RUNTIME ENFORCEMENT (see .forge/test-strategy.md — execution-decoupling contract):
After implementation, the MAIN ORCHESTRATOR runs the suite (the live browser / API-seam
tiers — a sub-agent can't) and drives a run -> classify -> dispatch-fix -> re-run-until-
green loop, then /forge-test-verify acts as the green-status GUARD against this section:
it confirms every listed file exists, every AC on hook is covered, and the orchestrator's
run is fully green (for T1/T2 it runs the cheap command itself). A missing file or
uncovered AC -> Fail; a non-green live run -> Re-run required (orchestrator re-runs). This
section is a runtime contract, not just documentation. The test files are durable, reusable
artifacts — reuse existing tests for previously-built functions; author NEW test rows only
for this WI's new functionality (don't re-author coverage a prior wave already wrote).
-->

**Tier:** <!-- T1 | T2 | T3 | T-E2E -->
**Rationale:** <!-- one sentence explaining why this tier fits -->

### Unit Tests
<!-- T1 / T2 / T3 only -->

| Class / Component | Test file | What to cover |
|---|---|---|

### Integration Tests
<!-- T2 / T3 only -->

| Scenario | Test file | What to verify |
|---|---|---|

### WI-scope E2E (browser)
<!-- T3 only — covers user-visible behavior owned by this WI.
     Prior-wave WIs are already on the spec branch; no mocking of earlier waves needed.
     Full multi-role and multi-browser regression is deferred to the T-E2E WI. -->

| Test file | ACs covered | Browsers |
|---|---|---|

### Full E2E Suite
<!-- T-E2E only — full spec suite; all user-visible ACs; all roles; multi-browser.
     Precondition: all prior WIs implemented on spec branch before this session. -->

| Test file | ACs covered | Roles tested | Browsers |
|---|---|---|---|

**Coverage check:** <!-- list each AC in the spec; mark DB-only / backend-only / user-visible; confirm every user-visible AC maps to a test row above -->

## Wave Ship State

<!--
WAVE MODE, SINGLE-PLAN FEATURES ONLY.

  - Sub-WI plans in wave mode: DELETE this section. The wave's ship
    state lives in the parent Decomposition Plan's `## Wave Ship Plan`
    table row, not here.
  - Single-plan features in wave mode: KEEP this section — this plan
    IS the only wave, so the wave's ship declaration lives here.

ship_type values:
  - vertical   — this plan ships independently to main and satisfies
                 all four vertical-shipping checklist items (C1 main stays
                 green, C2 no orphan scaffolding, C3 flag-or-inert for
                 unfinished surfaces, C4 verifiable increment)
  - monolithic — single-plan but declared monolithic for a legitimate
                 reason (rare for single-plan; most single-plans are
                 vertical by construction)

ILLEGITIMATE monolithic reasons (plan-reviewer flags as Important):
  - "Didn't want to slice it"
  - "Easier this way"
  - "Would take longer to slice"
  - "Couldn't think of a clean cut"
-->

- **ship_type:** vertical | monolithic
- **Ship state on main:** <one-line active voice — e.g. "users can list <resource> via GET /api/v1/<resource>">
- **Acceptance criteria satisfied:** <list of AC IDs from spec>
- **Verification:** <smoke command(s) or "see ## Test Approach">
- **Monolithic reason** (only if `ship_type: monolithic`): <one sentence>
- **Feature-flag gating** (optional): <flag name + reason it's gated>

## Progress
<!-- Updated during implementation. Mark subtasks as done, note discoveries. -->
- [ ] Subtask 1
- [ ] Subtask 2
- [ ] Pre-PR review (`/forge-pre-pr-review`) — Blockers resolved, verdict recorded in ## Notes
- [ ] PR opened

### Failed Approaches
<!-- What was tried and didn't work, with reasoning. Prevents the next session from repeating dead ends. -->

## Review Checklist
<!-- Tick all items and change Sign-off in the header from PENDING to your name before approving. -->

- [ ] I have read the plan end-to-end and cross-referenced against the spec
- [ ] Files to Modify table is complete and all paths are verified
- [ ] Test Approach covers all ACs assigned to this WI/plan
- [ ] Risks section addresses the real implementation risks

## Notes
<!-- Implementation notes, review feedback, discovered issues. -->
<!-- Pre-PR review verdict goes here before the PR is opened. -->
