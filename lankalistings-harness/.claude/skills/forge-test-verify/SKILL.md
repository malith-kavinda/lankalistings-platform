---
name: forge-test-verify
phases: [engineering]
description: "Test-coverage + green-status guard: verifies the test files a WI plan prescribes exist, the ACs on hook are covered, and the suite is green — then emits Pass / Re-run required / Fail plus an audit file. Run at the finalize stage of an implementation run, before `/forge-pre-pr-review`. Invoked as `/forge-test-verify`."
---

# /forge-test-verify

> **Non-dispatch guardrail (load-bearing).** `/forge-test-verify` is **inline / non-dispatching** — it never spawns a sub-agent. It runs in the implementer's `finalize` path (or in the orchestrator session directly), and Claude Code forbids recursive sub-agent dispatch — an agent already running as a sub-agent cannot dispatch another. The same constraint binds `/forge-pr-open` and `/forge-pre-pr-review`; all three are deliberately inline so the finalize implementer can chain them. Keep this skill free of Task-tool / agent-dispatch calls. The orchestrator's run → classify → dispatch-fix → re-run loop is the ONLY thing that dispatches, and it lives in `/forge-deliver`, not here.

The runtime counterpart of `/forge-plan-review`'s static TC-2 (tier-match) and TC-3 (AC-coverage) checks. Where plan-review validates the plan's *intent*, this skill validates the worktree's *execution*: are the files actually there, and do they actually pass at the tier-appropriate scope.

The tier vocabulary — **T1 (unit) / T2 (integration) / T3 (API-seam + WI-scope E2E) / T-E2E (full browser suite)** — is framework-level; see `.forge/test-strategy.md`. The concrete commands and frameworks per tier are project config, read from the project `CLAUDE.md` §Common Commands and the per-repo **Stack Profile** (`<backend-repo>`'s `CLAUDE.md ## Backend Stack` / `<frontend-repo>`'s `CLAUDE.md ## Frontend Stack`) — never hardcoded here. See the [tier config map](#tier-config-map) below.

## Mode awareness

> **⚠️ Two-phase green-status guard — the current model.** A dispatched sub-agent **cannot run live browser / live-server suites** (it is torn down on return, so it can't keep two dev servers booted or drive a browser) — so for T3 (API-seam, browser) and T-E2E this skill does **not** execute the suite. Instead it runs **after the MAIN ORCHESTRATOR has executed and greened the suite**, and acts as a **guard**: it confirms files exist, ACs are covered, and the orchestrator's **captured run status is fully green**. If the recorded status is missing / partial / not-green, the skill does **not** Pass — it emits **`Re-run required`** and signals the orchestrator to re-run the suite (up to **N** times) until green, *then* it continues. It is typically run by an implementer sub-agent in a `finalize` dispatch, or by the orchestrator directly. The sub-agent-runnable tiers (T1 unit, T2 integration) it still executes itself (Step 5a) — those need no browser.

The harness has two orchestration modes:

| Mode | This skill's role | Invoked by |
|---|---|---|
| **Feature-mode** (`ship_unit: feature`) | Green-status guard at the finalize stage, after the orchestrator's run. Confirms files/coverage; for browser/live-server tiers asserts the orchestrator's captured run is green, else `Re-run required`. `/forge-pre-pr-review` Step 0 reads the audit and aborts unless verdict is Pass. | The orchestrator, or the implementer sub-agent it dispatches, after the orchestrator's run |
| **Wave-mode** (`ship_unit: wave`, default) | Same green-status guard, run in the `finalize` dispatch (`/forge-deliver` Stage 7 — T2 verify finalize; T3 verify / `type: e2e` finalize) after the orchestrator's API-gate / browser run is green. Composes with per-WI Success Criteria + the verify-WI pattern. | The `finalize` implementer sub-agent (or the orchestrator); or the developer manually |

The skill body is identical across modes; only the caller and the consequence-of-failure differ. **Across both modes the live browser/API-seam execution belongs to the orchestrator, never this skill.**

## How to use

```
/forge-test-verify              # auto-detects ticket + WI from branch name
/forge-test-verify <wi-id>      # explicit WI id (rare; needed if branch naming ambiguous)
```

Run from the **implementation worktree session** after the impl agent (and `e2e-test-implementer` / `seam-test-implementer` for T3 / T-E2E) have authored, static-checked, and committed.

## When to use

- The finalize stage of an implementation run (automatic — the orchestrator/implementer invokes it).
- Mid-implementation sanity check when the developer wants to confirm test coverage before pushing manually.

## When NOT to use

- Foundation specs — out of scope (foundation work is governed by the manual pre-Gate-3 cycle).
- Mid-implementation when the impl agent is still committing — wait for the agent to exit, then run.
- As a substitute for `/forge-plan-review`'s static tier-match check — they validate different things. Both must pass for a WI to ship.

## Tier config map

The tier model is framework-level; the **commands, result paths, and frameworks that implement each tier are project config**. Read them — do not hardcode. Two sources:

1. **Commands** — project `CLAUDE.md` §Common Commands and the per-repo Stack Profile. The harness uses these placeholders; resolve each to the concrete command before running:
   - `<backend-test-cmd>` — backend unit-test command (`.forge/test-strategy.md` §"T1 — Unit").
   - `<backend-check-cmd>` — backend unit+integration command (T2 / T3 BE portion).
   - `<frontend-test-cmd>` — frontend unit/integration command.
   - `<e2e-cmd>` — full browser E2E suite (`<e2e-framework>`).
   - `<e2e-cmd-scoped>` — the same E2E command scoped to this WI's paths.
2. **Result paths + framework** — the per-repo Stack Profile names the test framework and where machine-readable results land (JUnit XML directories, the runner's summary format). Read it on turn 1; calibrate the counts-parsing in Step 5b to whatever the repo declares.

| Tier | What runs it | Backend portion | Frontend portion |
|---|---|---|---|
| `T1` (unit) | **this skill** (Step 5a) | `<backend-test-cmd>` | `<frontend-test-cmd>` |
| `T2` (integration) | **this skill** (Step 5a) | `<backend-check-cmd>` | `<frontend-test-cmd>` |
| `T3` (API-seam + WI-scope E2E) | **this skill** runs the BE unit/integration portion (`<backend-check-cmd>`) + `<frontend-test-cmd>`; the **orchestrator** runs the live API-seam + browser portion (`<e2e-cmd-scoped>`) | `<backend-check-cmd>` | `<frontend-test-cmd>` |
| `T-E2E` (full browser suite) | the **orchestrator** runs the live suite (`<e2e-cmd>`); this skill only reads the recorded result | — | `<e2e-cmd>` |

> If a project has only one repo, the rows for the absent repo are dropped — Step 5 runs only the commands for the repo the plan's `## Files to Modify` touches.

## Process

### Step 1 — Resolve ticket, WI, and plan path

Derive the ticket and WI ID from the current branch:

```bash
BRANCH=$(git branch --show-current)
# feature/PROJ-005-WI-2.1-organization-hierarchy → ticket=PROJ-005, wi=PROJ-005-WI-2.1
# feature/PROJ-005-spec → no WI; this skill only runs on impl branches
# feature/PROJ-002-auth-core (single-plan) → ticket=PROJ-002, wi=single
```

Pattern match (the branch/WI-id grammar is fixed; only the example prefix is illustrative):
- `feature/<ticket>-WI-<wave>.<index>-<slug>` → decomposed WI; `wi_id = <ticket>-WI-<wave>.<index>`.
- `feature/<ticket>-<slug>` → single-plan; `wi_id = single`.

If the branch does not match either pattern, abort:

> Branch `<branch>` does not match a Forge implementation branch shape. Aborting.

Locate the harness as `../<harness-repo>` relative to the worktree root (per workspace structure in `CLAUDE.md` §2). Resolve plan path:

- Decomposed: `<harness>/.forge/plans/<ticket>/<wi_id>-plan.md`.
- Single-plan: `<harness>/.forge/plans/<ticket>-*-plan.md` (single glob match required).

If the plan is missing or unreadable, abort:

> Plan not found at expected path. Aborting.

### Step 2 — Parse plan's `## Test Approach` section

Read the plan and extract:

1. **Tier** — the value on the `**Tier:**` line (`T1 | T2 | T3 | T-E2E`).
2. **Test tables** — every row across the four sub-section tables (`### Unit Tests`, `### Integration Tests`, `### WI-scope E2E`, `### Full E2E Suite`). For each row, capture the test file path and the ACs claimed in the "What to cover" / "ACs covered" / "What to verify" column.

Build a working list:

```
plan_tier:      <T1 | T2 | T3 | T-E2E>
required_files: [{path, acs_claimed: [...]}]
```

If the section is missing or empty, abort with verdict `Fail`:

> Plan `<path>` has no `## Test Approach` section. The gate cannot validate a plan that does not declare its tests. Add the section, re-run `/forge-plan-review`, then re-run this gate.

### Step 3 — File-existence check

For each `required_files` entry:

- Resolve the file path relative to the appropriate worktree (backend file path → `<worktree>/<backend-repo>/...`; frontend → `<worktree>/<frontend-repo>/...`).
- Confirm the file exists.

Collect missing files into a Blocker list. The check is fail-closed: any missing file means the verdict is `Fail`.

### Step 4 — AC-coverage check

Resolve the parent plan based on tracker mode:

```bash
SHIP_UNIT=$(yq ".features[] | select(.id == \"$TICKET\") | .ship_unit // .delivery.ship_unit // \"feature\"" <harness>/.forge/tracker.yaml)

if [ "$SHIP_UNIT" = "wave" ]; then
  PARENT_PLAN="<harness>/.forge/plans/$TICKET/$TICKET-decomposition-plan.md"
else
  PARENT_PLAN="<harness>/.forge/plans/$TICKET/$TICKET-WI-1.1-plan.md"
fi
```

For decomposed WIs, read the parent plan's `## Acceptance Criterion Coverage` table and find the row for `<wi_id>` — call this list `acs_on_hook`. For single-plan, `acs_on_hook` = every AC in the spec.

**Ownership column awareness (wave-mode).** The Decomposition Plan's coverage table has an `Ownership` column (`full | smoke | authoritative | split-across`). A verify-WI typically has `Ownership: smoke` for its row — the authoritative test lives in a sibling sub-WI. When verifying a `type: verify` WI, only `smoke` ACs are on hook for this WI's test coverage; `authoritative` ACs are someone else's responsibility. Read the column; if absent (single-plan or older plans), default every AC in the row to `full` ownership.

For each AC in `acs_on_hook` (filtered by ownership for verify-WIs), confirm at least one row in `required_files` claims to cover it. Collect uncovered ACs into a Blocker list.

(This is a defense-in-depth check — `/forge-plan-review`'s TC-3 should already have caught uncovered ACs at plan time. The runtime gate catches the case where the plan was updated post-approval without re-review, or where TC-3 misclassified.)

### Step 5 — Verify green status (run cheap tiers, read orchestrator's run for live tiers)

The check splits by what the runner can sustain. **Sub-agent-runnable tiers you execute directly (Step 5a); live-server / browser tiers you do NOT execute — you read the orchestrator's captured run and assert green (Step 5c).** Each command runs in its appropriate worktree (backend in `<worktree>/<backend-repo>`; frontend in `<worktree>/<frontend-repo>`). If the plan's Files to Modify only touches one repo, run only that repo's commands. Resolve every `<…-cmd>` placeholder to the concrete command via the [tier config map](#tier-config-map).

#### Step 5a — Sub-agent-runnable tiers (run directly)

These need no live server or browser, so this skill runs them itself:

| Tier | Backend command | Frontend command |
|---|---|---|
| `T1` | `<backend-test-cmd>` | `<frontend-test-cmd>` |
| `T2` | `<backend-check-cmd>` | `<frontend-test-cmd>` |
| `T3` | `<backend-check-cmd>` (BE unit/integration portion) | `<frontend-test-cmd>` |

> If the backend integration portion needs infrastructure that isn't available in this session (e.g. a container engine the runner can't start), treat that portion as an **orchestrator-run live tier** (Step 5c) rather than running it here. Read the backend Stack Profile for how this engagement stands up integration dependencies.

For each command capture: command string + working directory, exit code, wall-clock duration, last ~100 lines of output, and **test counts** (Step 5b). Any non-zero exit is a Blocker. Do not retry — that masks real defects.

#### Step 5c — Live-server / browser tiers (read the orchestrator's captured run; do NOT execute)

For the **API-seam** portion of a `T3` `type: verify` WI and the **browser E2E** portions of `T3` / `T-E2E`, this skill does **not** run anything — a torn-down sub-agent can't boot both servers or a browser. By the time this skill runs (the orchestrator's `finalize` step), the **main orchestrator has already executed the suite and recorded the result**. Read that record:

| Tier | Live-tier portion (orchestrator-run) | Where the result is recorded |
|---|---|---|
| `T3` | `<e2e-cmd-scoped>` and/or the API-seam run | The audit file's `## Test runs (orchestrator-executed)` section (Step 6), or the run-results path the orchestrator passes in the dispatch |
| `T-E2E` | `<e2e-cmd>` (full suite) | same |

Assert the recorded live-tier status is **fully green** (every test passed; 0 failed, 0 errored; skips justified):

- **Green** → record it, proceed.
- **Partial / not-green / failing** → do **NOT** Pass. Emit verdict **`Re-run required`** (Step 7) naming the failing tests, and **signal the orchestrator to re-run the suite** (it loops fix → re-run, up to **N** times — N=2 for the same failure — then escalates). Do not retry the browser run yourself; you can't.
- **Missing / stale** (no recorded run, or the recorded run's git SHA ≠ current worktree HEAD) → emit `Re-run required` with reason "no current orchestrator run on file" — the orchestrator must run the suite on this HEAD before this guard can Pass.

This is the load-bearing two-phase behavior: **the skill verifies green status and bounces back to the orchestrator until green; the orchestrator does the running.**

### Step 5b — Extract test counts (per run)

Counts are the raw material for the feature-level test-stats ledger that `/forge-deliver` harvests (`.forge/plans/<ticket>/<ticket>-test-stats.jsonl`). **Parse machine output — never hand-count.** The parsed totals *are* the receipts (project `CLAUDE.md` §Boundaries: no self-approved gate claims).

Prefer **JUnit XML** when the runner emits it; fall back to the captured stdout summary otherwise. The per-repo Stack Profile names the framework and the result-path convention — read it to know where the XML lands and how the summary line is shaped. For each command, emit one **run record** per distinct test source, classified by `test_type`:

| `test_type` | Source of counts | How to parse |
|---|---|---|
| `unit` | Backend unit-test result dir; Frontend unit-test runner output | JUnit XML: sum `<testsuite>` attrs `tests`, `failures`, `errors`, `skipped`, `time`. Runner without a JUnit reporter: parse its summary line (e.g. `Tests  N passed \| M failed \| K skipped (T)`). |
| `integration` | Backend integration-test result dir (often a separate task/target) | JUnit XML as above. If the project runs integration under the same task as unit, classify by package/path convention and note it. |
| `e2e` | `<e2e-framework>` JUnit reporter output if configured; else the run summary | JUnit XML, or parse `N passed`, `N failed`, `N flaky`, `N skipped` from the runner summary. Record `flaky` separately if the runner reports it. |

Per run record, compute `totals`: `{ tests, passed, failed, skipped, errors, flaky, duration_ms }` where `passed = tests - failed - errors - skipped`. If counts cannot be parsed (no XML, unrecognizable summary), set `totals: null` and `counts_source: "unparseable"` rather than guessing — the harvest will surface it as a gap, not a zero.

JUnit XML extraction snippet (dependency-light — `xmllint` ships with libxml2; point the glob at the result dir the Stack Profile names):

```bash
# sum testsuite attributes across all result files for a test task/target
for f in <backend-junit-xml-dir>/*.xml; do
  xmllint --xpath 'string(//testsuite/@tests)'    "$f"
  xmllint --xpath 'string(//testsuite/@failures)' "$f"
  xmllint --xpath 'string(//testsuite/@errors)'   "$f"
  xmllint --xpath 'string(//testsuite/@skipped)'  "$f"
done   # aggregate the four columns
```

> **Precision follow-up (out of scope for this gate, repo-config, ASK FIRST):** wiring a `junit` reporter into the frontend unit runner and the E2E runner config makes FE/E2E counts XML-exact instead of summary-parsed. Until then, FE/E2E counts come from the stdout summary and carry `counts_source: "stdout-summary"`.

### Step 6 — Write audit file

Persist the run to `<harness>/.forge/plans/<ticket>/<wi_id>-test-verify.md` (decomposed) or `<harness>/.forge/plans/<ticket>-test-verify.md` (single-plan). Format:

```markdown
# Test-Verify — <ticket> <wi_id>

> Tier: <T1 | T2 | T3 | T-E2E>
> Run: <ISO 8601 timestamp>
> Branch: <branch>
> Worktree HEAD: <short SHA>
> Verdict: <Pass | Re-run required | Fail>

## File-existence check

| File | ACs claimed | Status |
|---|---|---|
| `path/to/spec.ts` | AC-1, AC-2 | ✔ present |
| `path/to/other.ts` | AC-3 | ✘ MISSING |

## AC-coverage check

ACs on hook (from Key WI): AC-1, AC-2, AC-3, AC-4
- AC-1 ✔ covered by path/to/spec.ts
- AC-4 ✘ uncovered

## Test runs (sub-agent-executed — this skill ran them)

### Command 1: <backend-check-cmd>  (in <backend-repo>)
- Exit: 0
- Duration: 1m 42s
- Output tail:
  ```
  BUILD SUCCESSFUL in 1m 42s
  ```

## Test runs (orchestrator-executed — live-server / browser tiers)

> The orchestrator records its live-suite runs here (or passes a run-results path the skill copies in). This skill READS this section to assert green for T3/T-E2E live tiers — it does not run them. Each entry pins the git SHA so a stale run (SHA ≠ current HEAD) is treated as "no current run" → `Re-run required`.

### <e2e-cmd-scoped> (in <frontend-repo>) — run by orchestrator
- HEAD at run: a1b2c3d
- Exit: 1
- Duration: 4m 17s
- Output tail:
  ```
  1 failed
    [chromium] › modules/auth/login-flow.spec.ts:14:5 › AC-2 redirects to dashboard
      Expected URL /dashboard, got /login
  ```

## Verdict reason

<one-line summary of why Pass or Fail — e.g. "1 missing file, 0 uncovered ACs, 1 failing test suite">

## Test Stats (machine-readable)

<!-- forge-test-stats/v1 — harvested by /forge-deliver into <ticket>-test-stats.jsonl. Do not hand-edit. One block per test-verify run; the most recent block is authoritative. -->
```json
{
  "schema": "forge-test-stats/v1",
  "ticket": "PROJ-006-b",
  "wi_id": "PROJ-006-b-WI-1.4",
  "wave": 1,
  "wi_type": "verify",
  "tier": "T3",
  "branch": "feature/PROJ-006-b-WI-1.4-verify-upload-flow",
  "git_sha": "a1b2c3d",
  "captured_at": "2026-05-29T14:30:00Z",
  "verdict": "Pass",
  "runs": [
    { "test_type": "unit",        "framework": "<backend-unit-framework>", "repo": "<backend-repo>",  "command": "<backend-check-cmd>", "counts_source": "junit-xml",      "exit_code": 0, "totals": { "tests": 142, "passed": 140, "failed": 0, "skipped": 2, "errors": 0, "flaky": 0, "duration_ms": 18342 } },
    { "test_type": "integration", "framework": "<backend-int-framework>",  "repo": "<backend-repo>",  "command": "<backend-check-cmd>", "counts_source": "junit-xml",      "exit_code": 0, "totals": { "tests": 23,  "passed": 23,  "failed": 0, "skipped": 0, "errors": 0, "flaky": 0, "duration_ms": 40210 } },
    { "test_type": "e2e",         "framework": "<e2e-framework>",          "repo": "<frontend-repo>", "command": "<e2e-cmd-scoped>",   "counts_source": "stdout-summary", "exit_code": 0, "totals": { "tests": 8, "passed": 8, "failed": 0, "skipped": 0, "errors": 0, "flaky": 1, "duration_ms": 64000 } }
  ]
}
```
```

**Schema notes (`forge-test-stats/v1`):**
- `wi_type` ∈ `sub | verify | e2e | single`; `tier` is the plan tier. `wi_id`, `wave`, `branch`, `git_sha` identify the run uniquely.
- `runs[]` — one entry per distinct test source. `test_type` ∈ `unit | integration | e2e` is what answers "how many of each ran." `framework` and `repo` are read from the per-repo Stack Profile (illustrative placeholders above — replace with your stack). `counts_source` ∈ `junit-xml | stdout-summary | unparseable` records how trustworthy the numbers are.
- `totals` is `null` when `counts_source: "unparseable"` — the harvest surfaces that as a gap, never a fabricated zero.
- This block is the **producer contract**; `/forge-deliver` is the sole **consumer** that flattens it into the JSONL ledger. Don't change field names without updating the harvest step.

Append to the file if it already exists (re-runs build an audit log); the most recent verdict — and the most recent stats block — are what downstream consumers read.

### Step 7 — Emit structured verdict to the session

```
## Test-Verify — <ticket> <wi_id> (tier <tier>)

**Verdict:** [Pass | Re-run required | Fail]

### Files present
- <file> — <acs> ✔

### Files missing  (Blocker)
- <file> — <acs>

### ACs uncovered  (Blocker)
- <ac-id> — <summary>

### Sub-agent-runnable tier runs (this skill executed)
- <cmd> — exit <code> — <duration>
  <last 20 lines of output>

### Live-tier status (orchestrator-executed — read, not run)
- <tier portion> — recorded run: <git SHA> @ <ISO ts> — <green | N failing | none on file>
  <failing test names, if any>

### Audit
- <abs path to audit file>
```

Omit sub-sections with no entries.

**Verdict meaning:**
- **Pass** — files present, ACs covered, sub-agent-runnable tiers green, AND the orchestrator's live-tier run on this HEAD is green.
- **Re-run required** — files/coverage OK and (where applicable) the cheap tiers green, but the live-tier (browser / API-seam) run is missing, stale, or not-green. **Not a terminal failure** — the orchestrator must run/re-run the suite, then re-invoke this guard.
- **Fail** — missing files or uncovered ACs (a plan/coverage defect), or a sub-agent-runnable tier failed. Needs an agent re-dispatch or `/forge-plan-review`, not just a re-run.

### Step 8 — Exit code

Exit `0` on **Pass**. Exit non-zero on **Re-run required** and **Fail** (distinguished by the `**Verdict:**` line, which the orchestrator parses):
- **Re-run required** → the orchestrator (re-)runs the live suite — its run → classify → dispatch-fix → re-run loop — then re-invokes this guard. The guard never runs the browser itself.
- **Fail** → re-dispatch the responsible agent (missing files), or escalate to `/forge-plan-review` (uncovered ACs), or enter the code-bug auto-fix loop (a failing sub-agent-runnable tier).

## Resolution loop

The skill itself does not run the live suite and does not re-dispatch agents — it is a deterministic parse + (cheap-tier run) + green-status check + verdict + audit. The orchestrator reads the verdict line and acts:

- **`Re-run required`** (live-tier missing / stale / not-green) → the orchestrator (re-)executes the live suite via its **run → classify → dispatch-fix → re-run loop**: it runs the suite; on a **test bug** re-dispatches `e2e-test-implementer` / `seam-test-implementer` in `test-fix` mode; on a **code bug** dispatches `backend-implementer` / `frontend-implementer` (routed by the buggy file's repo) to fix on the same worktree — never weakening a test — then re-runs. Bounded at **N=2** fix attempts per failure; on exhaustion → escalate to a human. When green, the orchestrator records its run in the audit's `## Test runs (orchestrator-executed)` section and **re-invokes this guard**, which now Passes.
- **`Fail` — Missing files** → re-dispatch the responsible agent (implementer for unit/integration; `e2e-test-implementer` for E2E). Cap at 1 re-dispatch per WI; second Fail escalates.
- **`Fail` — failing sub-agent-runnable tier** (T1/T2 the skill ran) → code-bug auto-fix loop on the owning implementer, then re-invoke. Bounded at 2 attempts.
- **`Fail` — Uncovered ACs** → halt + escalate (a plan/coverage mismatch — needs `/forge-plan-review`, not a re-run).

When invoked manually by the developer, the developer reads the verdict and decides. **The key two-phase invariant: a non-green live suite yields `Re-run required`, and the orchestrator owns the running — the guard never launches a browser or boots servers.**

## Notes

- **The skill never modifies the plan, spec, or tracker.** Its only write is to the per-WI audit file — including the `## Test Stats (machine-readable)` block (Step 6). This keeps the gate a pure read+verify operation; plan revisions remain a human decision via `/forge-plan-review`.
- **Stats are a by-product, not a second gate.** Emitting the `forge-test-stats/v1` block costs one parse of output the gate already captured. The verdict is unchanged by it; a Fail still fails. The block exists so `/forge-deliver` can roll counts up per feature without re-running anything. Unparseable counts never change the verdict — they're recorded as a gap.
- **`/forge-pre-pr-review` reads the audit.** That skill aborts unless the audit file exists and the most recent verdict is `Pass`. Composing the two reviews this way means neither can be bypassed by skipping the other. (`/forge-pre-pr-review` is also inline / non-dispatching — see the guardrail at the top — so the finalize implementer chains test-verify → pre-pr-review → pr-open without recursive dispatch.)
- **Idempotent.** Running twice on the same worktree HEAD produces the same verdict. Each run appends a new block to the audit file with its own timestamp.
- **Foundation specs out of scope.** Hard-coded check at step 1 — branches like `feature/foundation-*` abort with "out of scope".
- **Single-plan and decomposed both supported.** Path resolution in step 1 branches on the `WI-` infix in the branch name.
- **Single-repo features supported.** If the plan's `## Files to Modify` only references one repo, only that repo's test commands run. Determined by parsing the plan's Files to Modify table for the `Repo` column values. A backend-only or frontend-only project simply has no rows for the absent repo.
- **Cost.** The guard itself is cheap: file/coverage checks + (for T1/T2) the unit/integration command (seconds to minutes). It does **not** add a browser run — the live browser / API-seam suite was already executed by the orchestrator before this guard runs; the guard only reads that recorded result. So there is no duplicate full-E2E run here.
- **No agent dispatch, no browser, no server boot from this skill.** The guard is a deterministic parse + cheap-tier run + status read + verdict — and it is inline / non-dispatching by design (see the header guardrail). Live execution is the orchestrator's. Its determinism is the whole point.
- **The audit file is committed by the orchestrator alongside the plan progress update.** Audit trails belong on the spec/plan branch (harness), not on the implementation branch (app repo). The finalize flow handles staging.
