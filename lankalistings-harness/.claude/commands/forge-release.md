# /forge-release

## What This Command Does

The single, **state-aware front door** to the post-delivery release lifecycle — the stabilization-and-acceptance arc that begins once every promised feature has shipped (V1 feature-complete): **pre-UAT regression → handover to UAT → UAT execution → post-UAT stabilization → sign-off → go-live.**

It reads `.forge/tracker.yaml`, figures out **where the release is in its lifecycle**, and interactively proposes the next step — scaffolding cycle plans, suggesting critical flows, triaging UAT issues, running the gate checks, and writing the `release:` / `uat_issues:` state. It is the conversational driver for the rules in `.claude/rules/tracker.md` → "Release & UAT Lifecycle"; it does not invent new workflow, it automates the manual steps those rules describe.

Defined as a plain slash command (not a skill) so it costs **zero standing context** — its body loads only when invoked. Like every Forge gate, **it writes nothing without the developer's explicit confirmation** — Claude proposes, the human decides (no auto-advance, no self-sign-off).

`/forge-release` is to a *release* what `/forge-deliver` is to a *feature*: the orchestrator that walks it from feature-complete to live.

## How to Use

```
/forge-release              # state-aware — detect lifecycle position, propose the next step
/forge-release open         # jump: open the release track (entry gate)
/forge-release regression   # jump: create / record a regression (RC-n) cycle
/forge-release uat          # jump: open / record a UAT (UC-n) cycle
/forge-release triage       # jump: triage incoming UAT issues
/forge-release sign-off     # jump: run the sign-off gate
/forge-release go-live      # jump: record go-live to production
/forge-release status       # read-only — print the current lifecycle state, no writes
```

With no argument, the command auto-detects the stage from `release.status` and proposes the most likely next action. A stage argument jumps straight to that step (still gated).

## When to Use

- All delivery phases are sealed (V1 feature-complete) and you're ready to begin pre-UAT regression.
- You're mid-lifecycle (a regression or UAT cycle is running) and want to record results, open the next cycle, or run a gate.
- UAT has raised issues you need to triage and route.
- The client has accepted and you're recording sign-off and/or go-live.

## When NOT to Use

- Before all `scope_phases` are sealed — the entry gate will block (opening early is ASK-FIRST; the command surfaces what's still open).
- For per-feature delivery — that's `/forge-deliver`.
- For a post-go-live production defect — that's the normal bug-fix flow (`.claude/rules/tracker.md` → "Bug Tracking"); `live` is a marker, not a defect tracker.

## Inputs read

1. `.forge/tracker.yaml` — `delivery.phases` (seal state), `release:`, `uat_issues:`, `bugs:`, `features:`
2. `.forge/features.md` + `.forge/specs/**` + `.forge/plans/**/*-decomposition-plan.md` — to **derive candidate critical flows** from feature acceptance criteria when scaffolding a cycle
3. `.forge/release/` templates — `_TEMPLATE-cycle-plan.md`, `_TEMPLATE-cycle-report.md`, `_TEMPLATE-uat-issues.md`

## Procedure

### 0. Detect state

Read `.forge/tracker.yaml`. Determine the lifecycle position:

| `release` value | Detected stage | Default proposed action |
|---|---|---|
| empty `{}` / absent | **pre-open** | Step 1 — open the release (entry gate) |
| `status: build-complete` | opened, no regression yet | Step 2 — create the first regression cycle |
| `status: regression` | regression running | Step 2 — record results / handover gate |
| `status: uat` | UAT running | Step 3 — record UAT cycle / triage / sign-off gate |
| `status: stabilize` | between UAT rounds | Step 3 — re-test or open the next UAT round |
| `status: signed-off` | accepted, not live | Step 5 — record go-live |
| `status: live` | done | print the summary; nothing to do |

Print a one-screen status header first (always), e.g.:

```
Release V1 · status: uat · phases [1,2,3] sealed · opened 2026-06-15 · handover 2026-06-17
Cycles:  RC-1 regression  passed-with-risks   09/10 flows
         UC-1 uat round 1  running             02/05 flows   ⚠ blocked by UAT-001
UAT issues: 03 (01 defect · 01 change-req · 01 query) · 01 blocking sign-off
Next gate: sign-off — blocked while UAT-001 (defect) is unresolved
```

If a stage argument was given, jump to that step. Otherwise propose the default action for the detected stage and ask the developer to confirm or redirect.

### 1. Open the release (entry gate)

**Gate:** every delivery phase the release will bundle must be `complete` (sealed).

1. List the sealed phases. Propose `scope_phases` = all currently-`complete` phase ids. Confirm with the developer (they may bundle a subset).
2. If any intended phase is **not** sealed: this is ASK-FIRST. Describe what's still open and confirm an early open; record the override in `release.notes`.
3. Propose a release `id` (default `V1`; suggest `V1.1` etc. if a prior signed-off release exists).
4. On confirmation, write the `release:` block:
   ```yaml
   release:
     id: V1
     status: build-complete
     scope_phases: [1, 2, 3]
     opened: "<today>"
     handover_date: null
     signed_off: null
     signoff_by: null
     live: null
     live_by: null
     current_cycle: null
     notes: ""
     cycles: []
   ```
5. Offer to proceed straight into Step 2 (first regression cycle).

### 2. Regression cycle (RC-n)

Internal pre-UAT validation of the **assembled** product (cross-feature flows; per-wave testing already happened during build — **reference** per-feature `*-test-stats.jsonl` numbers, do not re-run them).

**Create a cycle:**

1. Allocate the next id (`RC-1`, `RC-2`, …).
2. **Propose critical flows.** Read feature ACs (specs / `features.md` / decomposition plans) and draft a candidate `flows[]` checklist — cross-feature user journeys, each with `name`, `source_refs` (the ACs/features it exercises), `priority`, and `type` (`e2e | manual | exploratory | accessibility | security`). Present the list; the developer edits/approves it. **This is the highest-value part of the command** — deriving the flow set by hand is the tedious step.
3. Ask for a `target_date` (planning date) and `owner`.
4. Scaffold `.forge/release/<id>/RC-n-plan.md` from `_TEMPLATE-cycle-plan.md`, pre-filled with the agreed flows, scope, and target date.
5. Write the cycle into `release.cycles[]` at `status: planned`, set `release.status: regression` and `current_cycle`.

**Record results:** when the developer reports the run is done, update each flow's `status` + `evidence` path, set the cycle `status` (`passed | passed-with-risks | failed`), capture `accepted_risks[]` for `passed-with-risks`, and scaffold `RC-n-report.md`. **Evidence rule:** a `passed` cycle and every `passed` manual/exploratory flow must carry an `evidence:` path — surface this, don't self-approve.

**Handover gate (`regression → uat`):** offer to advance only when ≥1 regression cycle is `passed`/`passed-with-risks`. Confirm with the developer, then go to Step 3.

### 3. UAT cycle (UC-n)

Client-executed acceptance testing.

1. **Open a cycle:** allocate `UC-n` (or bump `round` for a re-test of an existing UC-n). Set `release.status: uat`, write `handover_date` on first entry, scaffold `UC-n-plan.md`, ask for `target_date` + `owner` (the client team).
2. **Record results / triage:** as the client raises issues, route each through Step 4. Update flow statuses as flows are run.
3. **Sign-off gate:** when the developer says UAT is complete, go to Step 4's gate check (Step 5).

### 4. Triage UAT issues

For each issue the client raises, capture it in `uat_issues[]` + a prose section in `.forge/release/<id>/uat-issues.md` (scaffold from `_TEMPLATE-uat-issues.md`). Classify `kind` interactively:

- **defect** → propose filing it into the existing `bugs:` collection (`delivery_phase: null`, since no phase is active — the **release sign-off gate** is its gate, per the parallel-gate rule). Link via `bug_ref`. Then the normal bug-fix flow fixes it (`fix/BUG-NNN-…`, regression test, PR review).
- **change-request** → **never a bug.** Propose either a backlog feature (record `feature_ref`, the developer adds it via the normal flow) or deferral to a future release. Record in `resolution`.
- **query** → answer, set `status: closed`, record the answer in `resolution`.

Set `blocking` (defaults `false`; a blocking change-request must be explicitly flagged). Issue `status`: `triage → accepted | rejected | deferred`, then accepted defects flow `→ fixed → closed`.

### 5. Sign-off gate (`stabilize → signed-off`)

**Gate (ASK-enforced, never auto):**

1. Check no **blocking** `kind: defect` UAT issue is unresolved (`status ∈ {triage, accepted, fixed}` — `fixed` still awaits verification). List any that block.
2. Check the latest `uat` cycle is `passed`/`passed-with-risks`.
3. If blockers remain, set `release.status: stabilize` (if not already), summarize what's outstanding, and stop — do **not** sign off.
4. If clear, ask the developer/lead to confirm sign-off. On confirmation: set `status: signed-off`, `signed_off: <today>`, and ask for `signoff_by`.

Change-requests do not block unless explicitly `blocking: true`; note any deferred to a future release.

### 6. Go-live (record production deployment)

`live` is a **marker**, not a blocking gate (per the project's chosen scope — a go-live milestone, not a production-support subsystem). Post-go-live defects use the normal bug-fix flow.

1. Only available once `status: signed-off`.
2. Confirm the deployment happened; ask for `live_by` (who shipped it).
3. On confirmation: set `status: live`, `live: <today>`, `live_by: <name>`.
4. Print the closing summary (release id, scope, dates: opened → handover → signed-off → live, cycle count, UAT-issue tally). The release record is retained as history; a sequential release (V1.1) opens its own `release:` object later.

### 7. Write + dashboard refresh

Every write goes to `.forge/tracker.yaml` (`release:` / `uat_issues:`) and bumps `last_updated`. After writing, regenerate `tracker.js` so the dashboard reflects it — the `regen-tracker-dashboard.sh` PostToolUse hook does this automatically on a `tracker.yaml` edit; run the manual command if the hook didn't fire (e.g. in a worktree session):

```
cd .forge/dashboard
{ printf 'window.TRACKER = '; yq -o=json . ../tracker.yaml; printf ';\n'; } > tracker.js
```

The dashboard's **Release / UAT** section renders the lifecycle track, cycle flow pass-counts, blocking issues, and the triage breakdown — hidden until the release opens.

## Notes

- **Never auto-advances a gate.** Entry, handover, and sign-off are ASK-enforced; go-live is a confirmed marker. The verdict is always the developer's — consistent with every other Forge gate.
- **Thin wrapper, not new workflow.** Each step maps 1:1 to a step in `.claude/rules/tracker.md` → "Release & UAT Lifecycle". When the rules and this command disagree, the rules win — fix the command.
- **Defects reuse the bug flow.** A UAT defect routes into `bugs:` via `bug_ref` (it does not get a parallel fix machinery); change-requests are kept out of the bug ledger.
- **Idempotent / resumable.** Re-running on the same state re-prints the status header and re-proposes the next step; it does not duplicate cycles or issues already recorded.
- **Single active release (v1).** The command manages one `release:` object. Sequential releases (V1.1, …) graduate the schema to a `releases: []` list in a later version; for now, a signed-off/live release is retained as history and a new one opens a fresh object (developer-confirmed).
- **Evidence-backed.** The command will not mark a cycle or manual flow `passed` without an `evidence:` path — same no-self-approval doctrine as every Forge gate.
