---
description: Tracker update rules, phase gates, bug tracking, rework lineage, release & UAT lifecycle, end-of-session check, lessons-entry format, gate audit protocol. Loads when editing tracker.yaml, engagement-gate-runs.md, project-prd.md, bugs.md, lessons.md, or release evidence files.
globs: .forge/tracker.yaml, .forge/engagement-gate-runs.md, .forge/project-prd.md, .forge/bugs.md, .forge/lessons.md, .forge/release/**
---

# Tracker & Gate Audit Rules

`.forge/tracker.yaml` is the project status file. Leadership uses it for visibility.

## Update Rules

- Add new features/tasks to the tracker (even at backlog stage)
- Update artifact status when you create or update a spec/plan
- Update phase when work advances
- Update `blocked_by` when a blocker is identified or resolved
- Always update `last_updated` (ISO 8601 timestamp) when you touch the tracker
- Keep `notes` brief — one line, current state only, not a history log
- **Serialize concurrent writes under a lock.** Any automated `yq -i` mutation of `tracker.yaml` (e.g. from `forge-pr-open` / `forge-worktree-up` during parallel `/forge-deliver --wave <N>` sessions) must run inside a `flock` critical section on `.forge/.tracker.lock` (bounded `-w` timeout; **fail open with a warning if `flock` is absent**, matching the harness hook posture). Two writers read-modify-writing the same file otherwise clobber each other and the shared `last_updated`. Terminal flips (`wave-closed`, `done`) are last-writer-wins-safe. See `.claude/commands/forge-deliver.md` § Notes ("Tracker writes must be serialized under a lock").

## Phase Gates

- `spec` → spec artifact exists
- `plan` → spec approved
- `dev` → plan approved
- `review` → dev work complete
- `ship` → quality checks passed
- Skipping a gate is the developer's call — but ask and note in tracker
- `paused` and `dropped` are exit states — record reason in `notes`

### Workitem decomposition (in flight)

`/forge-wave-decompose` breaks an approved spec into work items shipped in **waves** (one PR per wave to `main`). A decomposed feature gains the fields documented in the wave-mode schema block in `.forge/tracker.yaml`; the load-bearing ones for status tracking are:

- `decomposed: true` — the feature has a Decomposition Plan and work items
- `spec_branch: "feature/<feature-id>-<description>"` — the single spec-level branch all WI sessions commit to; `null` when the spec has no user-facing ACs
- `decomposition_plan: {path, status}` — the orchestrator's plan (wave mode only)
- `waves[].workitems[]` (wave mode) or a flat `workitems[]` (feature mode), each WI carrying `id`, `title`, `type` (`sub | verify | e2e`), `tier` (`T1 | T2 | T3 | T-E2E`), `plan_path`, `plan_status` (`backlog | draft | in-review | approved`), and once implementation starts `impl_status`, `branch`, `base_branch`, `pr_number`/`pr_url`.

**`impl_status` lifecycle** (wave mode): `pending → dispatched → pr-open → wave-closed`. The `dispatched → pr-open` flip is written by each WI's own `/forge-pr-open` run (the actor that opens the per-WI PR) and is the transition the orchestrator's "await all WIs at `pr-open`" integration barrier blocks on. The terminal value is **`wave-closed`** (written by `/forge-pr-open --wave` when the per-WI PR is superseded by its wave PR) — **not** `merged`. The Decomposition Plan itself has no `impl_status` (it ships no code).

Because review and implementation interleave, a decomposed feature can be at `phase: dev` (≥1 wave dispatched) while later-wave WIs are still at `plan_status: backlog` — the per-WI `plan_status`/`impl_status` pair is the authoritative state; feature-level `phase` is a coarse indicator only.

See `.forge/plans/_TEMPLATE-decomposition-plan.md` for the Decomposition Plan shape and `.claude/commands/forge-deliver.md` / `forge-wave-decompose.md` for the full wave-mode workflow.

## Delivery Phase Rules

`delivery.phases` groups features into stakeholder-facing milestones. Each feature carries `delivery_phase: <int>` referencing a phase `id`. Phases are layered on top of the dependency graph — `blocked_by` still drives sequencing within a phase; phases drive the stakeholder narrative.

**Phase status vocabulary** (four values, distinct intents):

- `planning` — being shaped *right now*. Used during the Gate 3 proposal step while phases are still being defined; rarely seen post-Gate-3 except during an explicit replan.
- `in-progress` — currently active. Exactly one phase at a time. This is the phase whose features the team is presently developing and shipping.
- `complete` — sealed. Every feature in this phase is `done` or `dropped`, the developer has confirmed the seal, and `sealed: <ISO date>` is set.
- `locked` — defined but not opened yet. The phase has a title and theme and feature assignments, but development on its features has not started. After Gate 3 lands, every phase except the first is `locked`.

**Invariants (enforced by ASK rather than by hook):**

- At most one phase has `status: in-progress` at any time.
- `delivery.current_phase` equals the `id` of the `in-progress` phase, or `null` if no phase is active.
- A phase with `status: in-progress` must have `started: <ISO date>` set; phases in `planning` or `locked` keep `started: null`.
- A phase with `status: complete` must have `sealed: <ISO date>` set; phases in any other status must have `sealed: null`. `started` is preserved on `complete` (it records when work began).
- A feature's `delivery_phase` may reference any phase id (including `locked` or `complete`) or be `null`. Specing and planning a feature ahead of its phase is allowed; advancing it to `dev` while its phase is `locked` is an ASK FIRST action — surface the override and record it in `notes`.
- Renaming a phase title is safe (features reference `id`, not title). Reassigning a feature to a different phase is safe but should be noted in the feature's `notes`.

**Status transitions and what to update:**

- **Defining phases (Gate 3, full mode):** `/forge-decompose` populates `delivery.phases` and assigns each feature a `delivery_phase`. The first phase flips to `in-progress` with `started: <today>`; all others stay `locked` with `started: null`. `current_phase` is set.
- **Sealing a phase:** when every feature in a phase is `done` (or `dropped`) **and no open bug targets the phase** (see "Bug Tracking" → phase-seal rule), ask the developer to confirm the phase is sealable. On confirmation: flip the phase to `complete`, set `sealed: <today>` (preserve `started`), flip the next phase to `in-progress` and set its `started: <today>`, and update `current_phase`. Do not auto-seal — the developer's verdict is required.
- **Opening a phase ahead of schedule:** ASK FIRST — describe what's still open in the current phase and confirm before flipping statuses. Set `started: <today>` on the phase being opened.
- **Adding a feature post-Gate-3:** new feature gets `delivery_phase: <id>` (or `null`); confirm placement with the developer.
- **Splitting/dropping a feature:** preserve the `delivery_phase` on the split children unless the developer says otherwise; for dropped features, leave `delivery_phase` in place for record.

**After the last phase seals — the release lifecycle.** Sealing the final delivery phase is **not** the end of the engagement. Once every delivery phase in a release's scope is `complete` (V1 feature-complete), the project enters the **post-delivery release lifecycle** — pre-UAT regression, handover to UAT, UAT, post-UAT stabilization, sign-off. That is modeled by the top-level `release:` track, **not** by another delivery phase (a delivery phase groups *features*; the release track groups *phases*). See "Release & UAT Lifecycle" below.

**Optional for small projects.** If the engagement has fewer than ~10 features and the team doesn't want a phased narrative, leave `delivery.phases: []` and `current_phase: null`. Every feature's `delivery_phase` stays `null`. The dashboard hides the delivery view in that case.

**Delivery dates (`due_date`).** Each phase entry and each feature carries an optional `due_date` (ISO date). **Dates are never set by `/forge-decompose`** — it writes every `delivery.phases[*].due_date` and `features[*].due_date` as `null`. Set them afterward with the **`/forge-set-dates`** command, which prompts for a phase target date per phase and (opt-in only) cascades proportional per-feature dates. Phase-level dates are the primary deadline unit and drive the dashboard delivery view; per-feature dates are off by default. All `due_date` fields stay `null` until `/forge-set-dates` runs — the dashboard renders the null case gracefully (no date shown, feature-date column omitted).

## Bug Tracking

Post-ship defects live in the top-level `bugs:` collection in `tracker.yaml` (a sibling of `features:`), **not** nested under features. Rationale: a bug is genuinely M:N (a shared-primitive defect breaks several features at once), "what open bugs exist?" must be a flat query, and a bug's lifecycle is independent of any feature's `phase`. The structured fields are documented inline in `tracker.yaml`; the **full description (repro / expected / actual / fix) lives in `.forge/bugs.md`**, one section per bug, joined by `id`.

**Id scheme:** `BUG-NNN` — global, zero-padded, monotonic. **Not** feature-suffixed (a bug may affect multiple features).

**The feature↔bug link is single-sourced from `affects`.** Features do **not** store a duplicate `bugs:` list. The per-feature bug list is *derived* (by the dashboard) by filtering the collection on `affects`. If a human-readable mirror on the feature is ever wanted, it must be generated — never hand-edited.

**A bug does not reopen its feature.** The feature stays `done`; the bug carries its own `status` (`open → in-progress → fixed`, or `→ wontfix`). The dashboard shows e.g. "feature-a · done · 1 open bug" — the shipped record stays intact while the defect stays visible.

**`delivery_phase` is the scheduled-fix milestone**, distinct from the affected feature's (which is frozen history — where it shipped). It defaults to `delivery.current_phase` at discovery; bump it forward to defer — a deliberate, tracked action, not silent slippage.

**Phase-seal rule (load-bearing, ASK-enforced):** a delivery phase `N` cannot be sealed (`complete`) while any bug with `status ∈ {open, in-progress}` and `delivery_phase: N` exists. Before sealing, query the collection for such bugs; each must be either driven to `fixed`/`wontfix` **or** explicitly reassigned to a later phase (`delivery_phase: N → N+1`) — a deferral the developer confirms. This makes "couldn't make the deadline → move to next phase" an auditable action, mirroring the existing developer-confirms-the-seal gate.

**Bugs are atomic; a shared fix can span several.** Each defect is its own `BUG-NNN` with independent `status` / `severity` / `delivery_phase` — never collapse multiple defects into one entry (that hides which sub-bug is still open). Several small bugs fixed in one PR simply share the same `fix_pr` (e.g. `BUG-002/003/004` all `fix_pr: <repo>#62`); each still closes individually.

**The bug-fix flow is right-sized — NOT `forge-deliver`.** Bugs do not go through spec authoring, gap-check, or decomposition/waves:

1. The **`bugs.md` entry is the spec** (repro + fix approach). No spec file.
2. **Plan is optional and proportionate** — the `Fix:` line suffices for a small bug; a short plan (approach + files + test) only when the fix is non-trivial (multi-file/repo, a design choice, real risk). The fix approach is always written down *before* code is touched.
3. Branch `fix/BUG-NNN-<desc>` (the existing `fix/` convention in `git-conventions.md`).
4. **Mandatory regardless of size:** a **regression test** that fails before the fix and passes after, plus a **pre-merge diff review** — `/forge-review-pr` once the PR is open, or `/council` / direct adversarial review of the working diff before pushing.
5. On PR merge: set `status: fixed` + `fix_pr` in `tracker.yaml` — which is what unblocks the phase seal.

**Append-only.** `fixed`/`wontfix` bugs keep their `tracker.yaml` entry and `bugs.md` section as a historical record (the dashboard filters to open by default). A heavy bug may graduate to its own `.forge/bugs/BUG-NNN.md` via the optional `doc:` field.

**UAT-originated bugs (the parallel-gate case).** A defect raised during UAT is routed into this same `bugs:` collection — but it is found when **no delivery phase is active** (all phases have sealed). Such a bug carries `delivery_phase: null` (there is no active phase to schedule the fix into) and so its `delivery_phase` does **not** drive a phase seal. It is instead gated by the **release sign-off gate** (see "Release & UAT Lifecycle" → Sign-off gate). The bug is linked back from its UAT issue via `bug_ref` + `release_id`. The phase-seal rule and the sign-off gate are the same shape at two different lifecycle stages — a defect found during phase delivery blocks a *phase seal*; a defect found during UAT blocks a *release sign-off*. Don't confuse the two: a `delivery_phase: null` bug is not "unscheduled and ignorable", it's "scheduled against the release, not a phase".

All of the above is **enforced by ASK, not by hook** — surface the rule and confirm with the developer, consistent with the delivery-phase invariants.

## Release & UAT Lifecycle

After the **last delivery phase seals** (V1 feature-complete), the engagement enters a stabilization-and-acceptance lifecycle the feature/phase model can't represent. The top-level **`release:`** track models it, and a triaged **`uat_issues:`** collection holds what comes back from UAT. The `release:` track groups *delivery phases* the way a delivery phase groups *features* — it is a **distinct top-level concept, not a delivery phase and not a feature `phase: testing`** (per-feature testing already lives in wave `verify`/`e2e` WIs; adding a feature-level testing phase would double-count it).

The schema for both collections is documented inline in `tracker.yaml`. These are the *rules*. The lifecycle is driven interactively by the **`/forge-release`** command — a state-aware orchestrator that detects the current stage and proposes the next step — though every transition can also be hand-edited; the command automates the steps below, it does not replace them.

### Lifecycle

```
build-complete → regression → uat → stabilize → signed-off → live
```

- `build-complete` — every delivery phase in `scope_phases` is sealed (`complete`); the release track is open but regression hasn't started.
- `regression` — internal pre-UAT testing/regression cycles (`RC-n`) are running against the *assembled* product (cross-feature flows, not per-wave — that already happened during build).
- `uat` — the build is handed to the client; a UAT cycle (`UC-n`) is being executed.
- `stabilize` — between/after UAT rounds; accepted defects are being fixed before the next round. `uat` and `stabilize` may alternate across multiple rounds.
- `signed-off` — the client has formally accepted the release.
- `live` — the signed-off build has been deployed to production. This is a **go-live marker** (records `live` date + `live_by`), not a production-support subsystem: post-go-live defects use the normal bug-fix flow ("Bug Tracking"), not a new collection.

All transitions are **ASK-enforced** — surface the gate, the developer/lead confirms, never auto-advance (same posture as the phase-seal and bug-fix gates). `/forge-release` enforces this: it proposes, the human confirms, then it writes.

### Cycles

`release.cycles[]` holds the discrete testing runs. Two types:

- `regression` (id `RC-n`) — internal, pre-UAT.
- `uat` (id `UC-n`) — client-executed; `round` increments for re-tests (a re-run of `UC-1` is `UC-1` round 2).

Cycle status: `planned → running → passed | passed-with-risks | failed`. Each cycle carries a compact summary in the tracker (status, owner, dates, a `flows[]` critical-flow checklist, `blocking_issues[]`, `accepted_risks[]`) and points at detailed **plan** and **report** evidence files under `.forge/release/<id>/`. **Regression cycles reference per-feature `*-test-stats.jsonl` numbers — they do not re-run them** (avoids double-counting build-time results); they add cross-feature/assembled-product flow coverage only.

**Evidence-backed (no self-approved validation).** Every cycle marked `passed` and every `manual`/`exploratory` flow marked `passed` must point at an `evidence:` file. No "all flows validated" claim without the receipts — same doctrine as the gate-evidence rule.

### The three gates (all ASK-enforced)

1. **Entry gate** (`build-complete` activation): the release track may open only when **every delivery phase in `scope_phases` is `complete`**. Opening it earlier is ASK FIRST and recorded in `release.notes`.
2. **Handover gate** (`regression → uat`): at least one `regression` cycle must be `passed` or `passed-with-risks` — the team's internal certification that the assembled product is ready for UAT.
3. **Sign-off gate** (`stabilize → signed-off`): the release may **not** be signed off while any **blocking** `uat_issue` of `kind: defect` is unresolved (`status ∈ {triage, accepted, fixed}` — `fixed` still awaits verification), **and** the latest `uat` cycle must be `passed`/`passed-with-risks`. Change-requests do **not** block sign-off unless explicitly flagged `blocking: true`; by default they route to a future release. Sign-off requires a recorded `signoff_by` + `signed_off` date. The developer/lead confirms; never auto-sign-off.

**Go-live (`signed-off → live`)** is a confirmed **marker**, not a blocking gate: once signed off, record the production deployment (`live` date + `live_by`) on developer confirmation. It does not gate on anything further — post-go-live defects use the normal bug-fix flow. (Deliberately scoped as a go-live milestone, not a production-support/incident subsystem.)

### UAT issue triage + routing

Each `uat_issue` is triaged by `kind`, and routing depends on it:

- **`defect`** → a genuine bug. On acceptance it **routes into the existing `bugs:` collection + right-sized bug-fix flow** (see "Bug Tracking"); the UAT issue keeps a `bug_ref: BUG-NNN` link and mirrors the bug's resolution. The routed bug carries `delivery_phase: null` (the parallel-gate case above). **Change-requests are deliberately kept out of the bug ledger** — forcing them in would corrupt "what open bugs exist?".
- **`change-request`** → new/changed behaviour the client wants. On acceptance it becomes a **normal backlog feature** (added manually via the standard flow / `/forge-deliver`) **or** is deferred to a future release; tracked via `resolution` + `feature_ref` (e.g. `backlog FEAT-030 (V1.1)`). **Never a bug**, never auto-creates a `features:` entry — the developer backlogs it manually (manual-first).
- **`query`** → a question, not a code change. Answered and `closed`.

Issue `status`: `triage → accepted | rejected | deferred`, then accepted defects flow `→ fixed → closed` (mirroring `bug_ref`'s lifecycle). Full prose (repro / steps / client comment / screenshots) lives in `.forge/release/<release_id>/uat-issues.md`, one section per issue joined by `id` — the same prose-home pattern as `bugs.md`.

### Driving it — `/forge-release` (and by hand)

The lifecycle is driven by the **`/forge-release`** command (`.claude/commands/forge-release.md`) — a state-aware orchestrator that reads the tracker, detects the current stage, and interactively proposes the next step (open → regression → uat → triage → sign-off → go-live). It scaffolds cycle plans/reports from the `.forge/release/` templates, **derives candidate critical flows from feature ACs**, and runs each gate check. It is **manual-first in posture** (framework §5.1): like every Forge gate it proposes and the human confirms — no auto-advance, no self-sign-off, no hook. Every step also remains hand-editable; the command automates the rules above, it does not replace them, and when the two disagree the rules win.

There is **no hook** for this lifecycle (consistent with the gate-by-ASK posture) and **no `/forge-validate` cycle-runner** yet — cycle running is folded into `/forge-release`; a separate runner is a later extraction only if it grows heavy. v1 models a **single active `release:` object**; sequential releases (V1.1, …) graduate it to a `releases: []` list later (a signed-off/live record is retained as history and its evidence kept under `.forge/release/<id>/` until the next release opens, developer-confirmed).

### Worked example (round-trips the schema)

A three-phase project reaches V1 feature-complete:

1. **Entry.** Phases 1–3 are all `complete`. The developer confirms the release track opens: `release.id: V1`, `status: build-complete`, `scope_phases: [1, 2, 3]`, `opened: <today>`.
2. **Regression.** A regression cycle `RC-1` (`type: regression`, `round: 1`) runs the critical assembled-product flows. It passes with one accepted risk → `status: passed-with-risks`, with `RC-1-report.md` and per-flow evidence. The release moves to `regression` then — handover gate satisfied (RC-1 passed-with-risks) — the developer confirms `regression → uat`.
3. **UAT.** The build is handed over: `status: uat`, `handover_date: <today>`, cycle `UC-1` opens. The client raises two issues:
   - `UAT-001` (`kind: defect`, `blocking: true`) → accepted → routed to `bugs:` as `BUG-014` (`delivery_phase: null`), `bug_ref: BUG-014`. The defect is fixed via the bug-fix flow (`fix/BUG-014-…`, regression test, PR review) → `BUG-014.status: fixed`, `UAT-001.status: fixed`.
   - `UAT-002` (`kind: change-request`) → deferred to V1.1 → `status: deferred`, `feature_ref: FEAT-030`, `resolution: "backlog FEAT-030 (V1.1)"`. It does **not** enter `bugs:` and does **not** block sign-off.
4. **Stabilize → sign-off.** The release moves to `stabilize` while `BUG-014` is fixed, then `UC-1` round 2 re-tests and passes. Sign-off gate: no blocking defect unresolved (`UAT-001` verified → `closed`), latest UAT cycle `passed`. The lead confirms → `status: signed-off`, `signed_off: <today>`, `signoff_by: <lead>`. `UAT-002` remains `deferred` against V1.1.
5. **Go-live.** The signed-off build deploys to production. The developer confirms → `status: live`, `live: <today>`, `live_by: <name>`. The V1 record is retained as history; a future V1.1 (carrying `UAT-002`) opens its own `release:` object.

Every step above is driven by `/forge-release` (it detects the stage and proposes the next action) or hand-edited — same result either way.

## Rework Lineage

A feature gains an optional `follow_up_of: [<feature-id>...]` naming the feature(s) it reworks/continues — *"this feature is a later pass over those."*

- `follow_up_of` is **distinct from `blocked_by`**: `blocked_by` is dependency / sequencing ("can't start until these land"); `follow_up_of` is continuation ("this redoes / uplifts those"). A feature can have both.
- It is also distinct from a **spec/plan Rev**: a Rev covers typo fixes and clarifications too, so it is *not* a rework signal. Rework lineage is recorded **only** via `follow_up_of`.
- `follow_up_of` is **authoritative** for lineage; the reciprocal "reworked by" marker is derived by the dashboard. Do not hand-maintain a reverse list.
- The dashboard's **Rework** signal counts features with a non-empty `follow_up_of` and maps each to the features it reworks.

## Lessons Entry Format

`.forge/lessons.md` holds engagement-level lessons learned, queued for upstream sync to `forge-harness`. Ordering and entry shape are stated authoritatively in the file's own header: **chronological — append new entries at the bottom** (newest at bottom, matching the top-to-bottom upstream-sync read order and `forge-reflect`'s append behavior).

The dashboard's **Lessons cadence** signal counts entries per week, so each entry needs a parseable date. The parser accepts either shape, in any order:

- **Template shape (canonical — what `forge-reflect` writes):** `## L-NNN — <short title>` heading with a `**Date:** YYYY-MM-DD` line in the body. The `L-NNN` id is load-bearing — findings reference it via `Promoted: L-NNN`.
- **Dated-heading shape:** `### YYYY-MM-DD — <short title>` — the date in the heading is what the parser reads.

Example (template shape):

```
## L-007 — Always run harness-change-reviewer before pushing

- **Date:** 2026-05-19
- **Sync target:** upstream — `.claude/agents/harness-change-reviewer.md`

We pushed three commits in a row that each had small CHANGELOG omissions...
```

If a lesson predates these conventions, leave it alone — the parser ignores entries it can't date, which is the correct outcome (those entries aren't counted in cadence).

## End-of-Session Check

Wrapping up tracked work and developer hasn't stated status → ask: *"Before we wrap up — should I update the tracker? [Current item] is at [current status]."*

## Harness Version Sync

`tracker.yaml` carries `harness_version` — it pins the last upstream `forge-harness` version whose template/CHANGELOG content has been synced into this project.

- Whenever upstream changelog entries are ported into this harness, bump `harness_version` to the highest synced version in the same change.
- Source of truth for available versions: `forge-harness/CHANGELOG.yaml` (top entry = latest).
- Always refresh `last_updated` alongside the bump.
- If a partial sync is intentional, do not bump — record the partial scope in `notes` and leave the pin at the last fully-synced version.

## Gate Audit Protocol

The pre-implementation gates (`/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose`) need persistent audit because the artifacts they verify (PRD, architecture, backlog) don't have built-in `## Revisions` sections like specs do.

**Audit storage matches artifact scope:**

- **Engagement-level gates** → audit file at `.forge/engagement-gate-runs.md`. Plus snapshot in `.forge/project-prd.md` `## Gate Status` table and structured state in `.forge/tracker.yaml` under `setup.*`.
- **Per-feature gates** (spec/plan review, adversarial review, security review) → reuse spec body + `## Revisions`, plan `## Notes` + `## Progress`. No new files.
- **Tool-call-level gates** (hooks, lint, typecheck) → ephemeral. Stderr only. No persistent audit.

**When engagement-level commands run in full mode**, three writes happen atomically:

1. Append `## Gate N Run M` block to `.forge/engagement-gate-runs.md`.
2. Update Gate N row in `.forge/project-prd.md` `## Gate Status` table.
3. Update `.forge/tracker.yaml` `setup.<gate>` (status, last_gate_run, accepted_risks, spikes for Gate 2).

**Skip all three writes in `dry-run` mode** — print findings only.

**Never assume gate outcome.** Ask the developer for the verdict (pass / pass-with-risks / pass-with-spikes / fail) before writing. Ask for id, owner, and reasoning of each accepted risk or scoped spike.
