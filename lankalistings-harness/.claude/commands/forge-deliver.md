# /forge-deliver

End-to-end orchestrator for **wave mode** delivery. Drives a feature from `backlog` through wave-by-wave PRs to `done`. Slash-only — never auto-loads, never auto-triggers. Lives in `.claude/commands/` so it costs zero context budget when not invoked.

It carries a feature through Spec → Plan → Reflect bookends with a shipping layer that collapses to one PR per wave per touched repo, direct to `main`. There is no T-E2E integration PR — the T-E2E WI is just the final wave.

**This is the single front door to feature delivery.** It *invokes* the per-phase skills (`forge-spec-author`, `forge-spec-review`, `forge-wave-decompose`, `forge-plan-author`, …) in order with the gates and human checkpoints — you do **not** hand-run them one-by-one. The `forge-feature-flow` skill exists only to route natural-language asks ("how do I start `<ticket>`?") here; experienced developers invoke `/forge-deliver <ticket>` directly.

Doctrine: the wave-mode workflow is described in `.forge/forge-harness-framework.md`.

## How to Use

```
/forge-deliver <ticket>
/forge-deliver <ticket> --wave <N>             # work wave N specifically (manual parallel waves)
/forge-deliver <ticket> --from <stage>         # skip ahead to a stage
/forge-deliver <ticket> --no-implement         # stop after all plans approved
/forge-deliver <ticket> --manual-approve       # human approves at every gate
/forge-deliver --next                          # pick the next unblocked backlog feature
```

`<ticket>` is the feature id, e.g. `PROJ-042`. The orchestrator reads `.forge/tracker.yaml` `features.<ticket>` on every invocation to determine current state and enters at the first incomplete step.

If invoked without an argument and `--next` was not passed, print usage and exit.

> Note: `<github-org>` in every `gh ... --repo <github-org>/<repo>` below is the value of `github_org` in `.forge/tracker.yaml`. Read it once at Stage 0 (e.g. `GITHUB_ORG=$(yq '.github_org' .forge/tracker.yaml)`); the literal `<github-org>` shown in commands is a placeholder for that value.

## Human Checkpoints

1. **Spec review** (Stage 3) — `forge-spec-review` runs 2-pass review, presents verdict, asks for approval. Halt on reject; resume on re-invocation.
2. **Size-assessment question** (Stage 5) — `/forge-wave-decompose` asks single-plan vs multi-plan. Explicit `AskUserQuestion`.
3. **Decomposition Plan review** (Stage 6, multi-plan path) — the Decomposition Plan locks waves, inventory, AC coverage, **and Wave Ship Plan**. Always human-reviewed.
4. **Sub-WI plan reviews + dispatch** (Stage 7, multi-plan) and **single plan review** (Stage 8) — within each wave, plan authoring agents run in parallel, then a cross-WI consistency gate runs once, then human reviews drafts one-by-one. Each WI's implementation dispatches on its own plan approval.
5. **Wave merge** (after each wave PR opens) — orchestrator halts, prints PR URLs, exits. Developer merges in GitHub UI; re-invokes `/forge-deliver <ticket>` to advance to the next wave.
6. **PR review on each wave PR** — out-of-band `/forge-review-pr <N>` per wave PR (human action, not orchestrator-driven).

Per-wave **contract authoring + auto-validation** (Stage 7 Step 0) is automated with **no human gate** (D5) — the pipeline must not block between decompose and the parallel plan fan-out. The **test verification + auto-repair loop** (Stage 7 Steps 5c–5f) is also automated, and **this orchestrator runs the suites itself** — the verify/e2e agents author + static-check only (a sub-agent is torn down on return, so it can't keep servers booted to live-run the API seam or a browser; see **Dispatch invariants**). The orchestrator runs the API gate then the browser suite and drives a **run → classify → dispatch-fix → re-run-until-green** loop: in-wave seam/browser defects auto-fix via the owning implementer (`backend-implementer` / `frontend-implementer` for code bugs; `seam-test-implementer` / `e2e-test-implementer` for test bugs), no human, bounded N=2; only pre-existing-code regressions, ambiguous attribution, and contract defects escalate to a human. Implementation dispatch, worktree provisioning, wave-integration merges, conflict resolution, pre-PR review, and PR opening remain automated.

## PR strategy — spec PR + plan PR + one PR per wave per repo, all → main

| Artifact | Branch | Base | When raised |
|---|---|---|---|
| **Spec** | `feature/<ticket>-spec` (harness) | `main` | Stage 4 (after human approves spec) |
| **Plan** | `feature/<ticket>-plan` (harness) | `feature/<ticket>-spec` (stacked) | Stage 9 — opened **early** after Wave 1's plans approved; later waves' plans append as follow-up commits |
| **Code per wave per repo** (multi-plan) | `feature/<ticket>-wave-<N>` (in each touched app repo) | `main` | Stage 12 (opened when all the wave's WIs — sub, verify, e2e — are integrated into the wave branch via Stage 11's two-pass merge) |
| **Per-WI review PRs — `type: sub`** (multi-plan, transient) | `feature/<ticket>-WI-<wave>.<index>-<slug>` | `main` | Opened by impl agent during Stage 7 Step 5a; **auto-closed by Stage 12** with "Superseded by wave PR" comment when the wave PR opens |
| **Per-WI review PRs — `type: verify` / `e2e`** (multi-plan, transient) | `feature/<ticket>-WI-<wave>.<index>-<slug>` | `feature/<ticket>-wave-<N>` (the wave branch, post-Pass-1 integration) | Opened by the impl agent after Pass-1: a **T2 verify** PR by `seam-test-implementer` in Step 5d; a **T3 verify** PR by `e2e-test-implementer` in Step 5e (Phase 2); an **e2e** PR by `e2e-test-implementer` in Step 5e. **Auto-closed by Stage 12** when the wave PR opens |
| **Code (single-plan)** | `feature/<ticket>-<slug>` (app repos) | `main` | Stage 11 (one per touched repo) |

**PR-strategy notes (wave mode):**

- `WAVE_BASE = main` for every wave (no stacked-on-prior-wave model). Each wave branches from `main` after the previous wave's PR merges.
- No T-E2E integration PR. The T-E2E WI is the final wave; its PR is a wave PR like any other.
- Per-WI PRs are review-only review surfaces that auto-close when the wave PR opens — the wave PR is the actual ship surface.
- Wave merge is a **human checkpoint** between waves — orchestrator halts on wave PR open and resumes on re-invocation after the human merges.

**Delivery metrics note (best-effort, data-plane only).** When the project has `.forge/metrics/`, append `forge-metrics/v1` JSONL rows without blocking delivery. `events.jsonl`, in lifecycle order: **once at the first invocation for this ticket** (`feature_started` — this is the start of the feature clock, capturing spec-authoring time; append **only if no `feature_started` row for the ticket exists yet**, so resumes and re-runs don't reset it), at spec approval (`spec_approved`), WI dispatch (`wi_dispatched`), WI PR open (`wi_pr_opened`), wave PR open (`wave_pr_opened`), wave merge (`wave_merged`), and feature completion (`feature_done`). `agent-runs.jsonl`: **one row per dispatched agent, appended at the moment you process that agent's return** — the collection points are Stage 7 Steps 3/5b (sub-WI implementers), 5c/5d (seam-test author/test-fix/finalize dispatches), 5e (e2e author/finalize), every D11 auto-repair re-dispatch (link it via `repair_of`), and Stage 10's single-plan dispatch; fill `agent_role`, `dispatch_mode`, `attempt`, `status`, `outcome` per the schema in `.forge/metrics/README.md`. Before Stage 12 opens a wave PR, sanity-check the ledger has rows for this wave's dispatches — zero rows after a dispatched wave means appends were missed; backfill them from this session's dispatch history before proceeding. `estimation-snapshots.jsonl`: once at Stage 15 with the feature complexity/actuals summary. The dashboard derives cycle-time (spec authoring `feature_started → spec_approved`, wave-1 ramp `spec_approved → wave-1 merged`, later-wave build-only) and rolling throughput (features/waves per day) from these timestamps — so the `feature_started` and `spec_approved` rows are what make spec-authoring and wave-cycle time visible; without them the dashboard falls back to whatever later events exist. Failed appends are warnings at most — do not mutate `tracker.yaml` for metrics and do not include token/user data in committed ledgers.

## When to Use

- The user wants a feature shipped wave-by-wave through the new flow.
- The engagement is in wave mode (`delivery.ship_unit: wave` or per-feature override).
- A feature is at any phase from `backlog` to `review` and needs to advance.

## When NOT to Use

- Foundation features (`.forge/specs/foundation/**`) — manual cycle applies.
- Engagement is at `ship_unit: feature` AND the feature has no `ship_unit: wave` override — the mutual-exclusion guard at Stage 1 refuses (this harness provides wave-mode orchestration only).
- Gates 1–3 haven't passed — preflight aborts at Stage 2.

## Resume Protocol

**Stage 0 runs first on every invocation** — it reconciles the tracker against GitHub + git ground truth and heals or halts on drift *before* the entry stage is derived (see Stage 0). The table below then reads the reconciled tracker state.

Read `.forge/tracker.yaml` `features.<ticket>` and derive the entry stage from per-feature state + per-wave state:

| Tracker state | Entry stage |
|---|---|
| `phase: backlog` OR (`phase: spec`, spec body stub) | Stage 2 (preflight + spec draft) |
| `phase: spec`, spec body present, `Status: draft/in-review` | Stage 3 (spec review) |
| `phase: spec`, spec approved, no plan + no Decomposition Plan | Stage 4 (open spec PR), then Stage 5 |
| `phase: spec`, spec approved, no plan, Decomposition Plan exists | Stage 5 re-entry (state-aware) |
| `phase: workitem-decompose`, Decomposition Plan at `Status: draft/in-review` | Stage 6 (Decomposition Plan review) |
| `phase: workitem-decompose`, Decomposition Plan `approved`, some WI at `plan_status: backlog/draft` | Stage 7 (per-wave pipeline) |
| `phase: dev`, decomposed — some wave at `status: planned` | Stage 7 (next wave dispatch) |
| `phase: dev`, decomposed — some wave at `status: in-progress` | Stage 7 Step 5a–6 (resume in-progress wave — see "Resume sub-state derivation" in Stage 7) |
| `phase: dev`, decomposed — some wave at `status: pr-open` | Stage 14 (wave-merge-wait poll) |
| `phase: plan`, single-plan, plan at `Status: draft/in-review` | Stage 8 (single plan review) |
| `phase: plan`, single-plan, plan approved, no open plan PR | Stage 9 (open plan PR) |
| `phase: plan`, single-plan, plan approved, plan PR open | Stage 10 (single-plan worktree + impl dispatch) |
| `phase: dev`, single-plan (decomposed: false) | Stage 10 re-entry (idempotent — code PR open → Stage 15; else dispatch impl) |
| `phase: review` | Stage 15 (verify all waves merged → Reflect → done) |
| `phase: ship` | Stage 15 (Reflect → done) |
| `phase: done`, `paused`, `dropped` | Print state and exit |

<!-- INVARIANT: the entry-stage column above must match the "Stage map" ASCII box at the end of this file exactly. When renumbering stages, update BOTH this table AND every "Stage N" reference in the Notes section + cross-file refs in forge-pr-open / forge-wave-decompose. -->
<!-- pr-open → Stage 14 (poll), NOT Stage 12 (which OPENS the wave PR). review/ship → Stage 15 (Reflect), NOT Stage 13 (which HALTS for merge). -->


The orchestrator **never re-runs a completed stage**. `--from <stage>` is the explicit override (warn on backward jumps — destructive for approved artifacts).

`--wave <N>` overrides next-ready wave selection in Stage 7 — see FR-7.d below.

---

## Context budget & session scope

This command is long, and one feature spans many stages, many dispatches, and live test runs whose output accumulates in the session. To keep the orchestrator's own instructions dominant over a session's growing working context (agent verdicts, captured test tails), **one invocation drives one bounded session unit — not the whole feature.** This is a reliability measure, not just economy: a 1000-line procedure is followed faithfully when the working context above it is small, and skipped/mis-ordered when it has scrolled far back behind dozens of agent returns.

Everything the next unit needs is durable on disk — the approved spec, the Decomposition Plan, `tracker.yaml`, the wave plans (AD #4: *context lives in files, not conversations*) — and **Stage 0 re-derives state on every invocation**, so a fresh session is fully self-orienting.

| Session unit | Stages | Ends at | Boundary |
|---|---|---|---|
| **Shape** | 2–6 (spec author → review → spec PR → decompose → Decomposition Plan review) | Decomposition Plan approved | **Soft** — re-invoke now; no merge wait |
| **Wave N** (one per wave) | 7 (+11/12) for wave N | wave N PR(s) opened | **Hard** — re-invoke after the wave PR merges |

- **Soft boundary (Shape → Wave 1).** The Shape unit accumulates the heaviest one-shot reads — spec sources, two spec-review verdicts, the Decomposition Plan review — all dead weight once wave-1 *planning* begins, which reads only files. So after the Decomposition Plan is approved (Stage 6), **end the session and hand off to a fresh one for wave 1.** This is a **context reset, not a wait**: wave 1 does NOT depend on the spec PR merging (decompose already read the *approved* spec from disk), so the handoff says *start now*. (Single-plan features have a much lighter Shape phase — Stages 5 → 8 — and may stay in one session through Stage 10; the soft boundary is a multi-plan optimization.)
- **Hard boundary (per wave).** Each wave is the heaviest unit (parallel plan + impl agents, orchestrator-run live suites, fix loops). **Stage 13 already halts after each wave's PR opens and exits** — that halt *is* the per-wave context boundary. Re-invoke after the human merges the wave PR. Within a single wave's session, the next wave's plan-*shaping* may overlap the current wave's background impl (Stage 7 Step 4) — but a context-pressured session may also defer that overlap to the next invocation; the plans are filed either way.

**Handoff prompts MUST be concise.** Because Stage 0 + `tracker.yaml` make every fresh session self-orienting, a handoff is the **invocation plus only what is not already on disk** — never a stage recap, never a restatement of this command's operator guide. Required shape:

```
/forge-deliver <ticket>
```

followed by at most: (1) the boundary type — *soft: start now* or *hard: start after the wave-<N> PR(s) merge* — and (2) any decision made this session that is not yet filed (rare; if it can be filed, file it instead of putting it in the prompt). Nothing else.

---

## Process

### Stage 0 — State-reconciliation preflight (every invocation, before resume detection)

Runs **first on every invocation**, before Stage 1 derives the entry stage. The resume model trusts `tracker.yaml`, but three authoritative stores independently record "what's done" — the tracker, GitHub PR state, and pushed git branches — and they diverge when a background agent dies between pushing its branch / opening its per-WI PR and writing its tracker fields (the `dispatched → pr-open` flip is the agent's *last* action, so a crash after push-and-open leaves the tracker stale). Stage 1's resume table reads tracker fields verbatim; if those fields lie, the orchestrator re-dispatches onto a branch that already has commits and an open PR, silently. This stage reconciles the three stores against ground truth before any stage acts on tracker state.

Skip for `phase: backlog`/early-`spec` tickets with no branches or PRs yet (nothing to reconcile). Otherwise, for the ticket, diff the three stores per WI branch and per wave branch:

1. **tracker** — `workitems[*].impl_status`, `waves[*].status`, feature `phase`
2. **GitHub** — `gh pr list --repo <github-org>/<repo> --head <branch> --state all --json number,state` per per-WI branch and per-wave branch
3. **git** — `git ls-remote --heads origin <branch>` per per-WI and per-wave branch

**Reconciliation rules — ground truth is GitHub + git; the tracker is the derivative that heals or halts:**

| Divergence | Action |
|---|---|
| tracker `impl_status: dispatched` BUT per-WI PR is OPEN and branch is pushed | **Heal:** set `impl_status: pr-open`. Log to `engagement-gate-runs.md`. Continue. |
| tracker `waves[N].status: pr-open` BUT every wave PR is `MERGED` | **Heal:** set `waves[N].status: merged` + `merged_at: <today>`. Continue. (Stage 14 already does this for its own case; Stage 0 generalizes it to any entry.) |
| tracker `impl_status: dispatched` BUT branch pushed and **no** PR | **Halt** — ambiguous (agent pushed, died before opening PR). Print drift report; human decides resume-the-agent vs re-dispatch. |
| tracker `impl_status: dispatched` BUT **no** branch pushed AND **no** PR | **Heal → re-dispatchable:** the background agent died before pushing anything, so there is no work to clobber. Reset `impl_status: dispatched → pending` so Stage 7 re-provisions the worktree and re-dispatches. Log to `engagement-gate-runs.md`. Continue. (See the no-heartbeat note below — a `dispatched` WI with nothing on the remote is the one orphaned-dispatch case that is *safe* to auto-recover.) |
| tracker says `merged`/`done` BUT the PR is `CLOSED` (not `MERGED`) | **Halt** — never guess a close-vs-merge. Print drift report. |
| tracker `pr-open`/`merged` BUT neither branch nor PR found | **Halt** — tracker references artifacts that don't exist. Print drift report. |
| All three agree | No-op. Proceed to Stage 1. |

**Heal writes** append a block at the bottom of `.forge/engagement-gate-runs.md`:

```
## /forge-deliver state reconciliation on <YYYY-MM-DD>

Ticket: <TICKET>
Healed: <field> <from> → <to>
Evidence: <gh/git observation that established ground truth>
Operator: <git config user.name>
```

**Halts** print a three-store drift table (tracker vs GitHub vs git, per affected branch) and a resume hint — they never auto-correct an ambiguous divergence. The developer resolves the drift, then re-runs `/forge-deliver <ticket>`.

> **No-heartbeat note (background-agent recovery).** A WI at `impl_status: dispatched` whose background agent died (session crash / compaction) is **indistinguishable from one still running** — Claude Code has no durable per-agent heartbeat a fresh invocation could poll. Stage 0 therefore decides purely on what reached the remote: **nothing on the remote → safe to reset to `pending` and re-dispatch** (the new row above — there is no work to lose); **branch pushed but no PR → halt** (ambiguous: the dead agent may have left partial commits; a human decides resume-vs-re-dispatch); **PR open → heal to `pr-open`** (the agent's last action succeeded). This is why "resumable from any stage" holds in practice: the recovery decision is grounded in GitHub + git ground truth, not in trusting that a `dispatched` actor is alive.

Fails open if `gh`, `git`, or `yq` is unavailable — prints a warning and proceeds to Stage 1 (same posture as every harness hook). `--from <stage>` does **not** skip Stage 0; reconciliation always runs first.

---

### Stage 1 — Argument parsing + mutual-exclusion guard + resume detection

Parse flags: `--next`, `--from <stage>`, `--no-implement`, `--manual-approve`, `--wave <N>`.

If `--next` and no ticket: find the first feature with `phase: backlog`, every `blocked_by` at `phase: done` or `ship`, AND in wave mode (engagement-level or per-feature). If none, print: *"No wave-mode backlog features with all dependencies satisfied."* and exit.

**Mutual-exclusion guard:**

```bash
ENG_SHIP_UNIT=$(yq '.delivery.ship_unit // "wave"' .forge/tracker.yaml)
FEAT_SHIP_UNIT=$(yq ".features[] | select(.id == \"$TICKET\") | .ship_unit // \"\"" .forge/tracker.yaml)
EFFECTIVE_MODE="$ENG_SHIP_UNIT"
[ -n "$FEAT_SHIP_UNIT" ] && EFFECTIVE_MODE="$FEAT_SHIP_UNIT"

if [ "$EFFECTIVE_MODE" = "feature" ]; then
  echo "$TICKET is at ship_unit: feature — this harness provides wave-mode orchestration only. Set ship_unit: wave to use /forge-deliver."
  exit 1
fi
```

Read current `phase` and per-wave state for the ticket. Derive entry stage per the Resume Protocol table. If `--from` was passed, override. If `--wave <N>` was passed, the explicit-wave override applies during Stage 7 (FR-7.d).

---

### Stage 2 — Preflight + Spec Draft

**Preflight checks:**
1. **Engagement gates passed.** `setup.architecture.status` must be `gate2-passed*` and `setup.foundation.status` must be `done`.
2. **Ticket exists.** `features.<ticket>` present in tracker.
3. **Dependencies.** For each `blocked_by`, confirm `phase: done` or `ship`. If any dep is at `dev`/`review`/earlier, prompt for confirm in `--manual-approve` mode.

Abort on preflight failure; tracker untouched.

**Spec draft** (runs immediately after preflight passes):

Invoke `forge-spec-author <ticket>`. The skill runs `forge-gap-check` first. On new `B-N` Blockers: halt with resume hint. Otherwise drafts the spec body and flips `phase: backlog → spec`.

---

### Stage 3 — Spec review (human checkpoint)

Invoke `forge-spec-review .forge/specs/<ticket>-*-spec.md`. 2-pass review, fix Blockers/Importants between passes, present verdict, ask for approval.

- Human approves → `phase: spec → plan`. Continue to Stage 4.
- Human rejects → halt: *"Halted at Stage 3 — spec rejected. Revise and re-run /forge-deliver <ticket>."*
- Blocker survives Pass 2 → halt for manual rewrite.

---

### Stage 4 — Open spec PR

Branch-based entry check:

```bash
OPEN_SPEC_PR=$(gh pr list --repo <github-org>/<harness-repo> \
  --head "feature/<TICKET>-spec" --state open --json number --jq '.[0].number' 2>/dev/null)
```

If non-empty → already open; print URL and advance. If empty → invoke `forge-pr-open <ticket> --artifact spec`. Stays on `feature/<TICKET>-spec` after this stage.

---

### Stage 5 — Wave decompose

Entry condition: `phase: spec`, spec approved, no plan and no Decomposition Plan.

Invoke `/forge-wave-decompose <ticket>`. The command runs the size-assessment + `AskUserQuestion` for single-plan vs multi-plan — **mandatory human checkpoint**. Halts here; re-invoking after the human responds continues.

After `/forge-wave-decompose` returns:
- `phase: plan, decomposed: false, ship_unit: wave` → single plan drafted; continue to Stage 8.
- `phase: workitem-decompose, decomposed: true, ship_unit: wave` → Decomposition Plan drafted; continue to Stage 6.
- Cancelled → exit.

---

### Stage 6 — Decomposition Plan review (multi-plan path)

Entry condition: `phase: workitem-decompose`, Decomposition Plan at `Status: draft/in-review` (read from `features.<ticket>.decomposition_plan.status` AND the file header).

Invoke `forge-plan-review .forge/plans/<ticket>/<ticket>-decomposition-plan.md`. **Plan-reviewer's §11 (Wave Vertical-Shipping Audit) runs automatically** — re-validates the FR-2 checklist per wave + checks monolithic reasons + verification command validity.

- Human approves → `decomposition_plan.status: approved`. **End the Shape session here — soft boundary (see below).**
- Human rejects → halt: *"Halted at Stage 6 — Decomposition Plan rejected. Revise and re-run /forge-deliver <ticket>."*

**Parallelism wave check** — scan `waves[]` (excluding the T-E2E wave if present). For any wave with only 1 WI, print:

```
⚠ Wave <N> has only 1 WI (<wi-id>) — parallel dispatch won't apply for this wave.
Consider regrouping WIs across waves in the Decomposition Plan (edit + re-run /forge-plan-review)
to ensure ≥ 2 WIs per wave for meaningful parallelism.
Continuing with wave <N> as a single-agent wave.
```

Advisory only — orchestrator does not halt.

**Soft session boundary — end the Shape session, hand off to Wave 1 (see "Context budget & session scope").** The decomposition is approved and frozen on disk; everything wave-1 planning needs is in the approved spec + Decomposition Plan + `tracker.yaml`, and the Shape session's accumulated context (spec sources, spec-review verdicts, decompose) is now dead weight. **Print the concise handoff below and exit** — do NOT continue into Stage 7 in this session. This is a context reset, **not** a merge wait: wave 1 does not depend on the spec PR merging, so the developer re-invokes immediately.

```
## Shape complete — <ticket> decomposed and approved

Decomposition Plan: <path> (approved) · <N> waves · spec PR #<n> (open)

Boundary: SOFT — start the next session now (no merge wait).
Re-invoke in a fresh session to plan + ship Wave 1:

    /forge-deliver <ticket>
```

(Keep this block to the invocation + the soft/start-now line + the one decomposition-path pointer — Stage 0 re-derives everything else from the tracker. Do not pad it with a stage recap.)

**STOP. End the assistant turn here.** On re-invocation, Stage 0 + the Resume Protocol enter Stage 7 for wave 1.

> **`--manual-approve` / single-session override:** if the developer explicitly wants to barrel through without the context reset (e.g. a tiny 1–2-WI feature), they may re-invoke immediately or pass a flag; the soft boundary is a default for context hygiene, not a hard gate. The hard per-wave boundary (Stage 13) is non-negotiable.

---

### Stage 7 — Per-wave pipeline (interleaved plan-shaping + implementation)

Entry condition: `phase: workitem-decompose` (Decomposition Plan approved) or `phase: dev` (≥1 wave dispatched). Some WI at `plan_status: backlog/draft` OR some wave at `status: planned/in-progress/pr-open`.

Maintain per-WI fields: `plan_status` (existing) and `impl_status: pending | dispatched | pr-open | wave-closed`. Maintain per-wave `status: planned | in-progress | pr-open | merged`.

**Wave selection (FR-7.d / FR-7.e):**

- **Default selection** (no `--wave <N>`): pick the lowest-numbered wave whose `depends_on` waves are all `status: merged`. If no such wave exists but some wave is `status: planned/in-progress`, that's the active wave.
- **Explicit selection** (`--wave <N>`): force wave `N`. Run the soft dep-check:

  ```bash
  WAVE_DEPS=$(yq ".features[] | select(.id == \"$TICKET\") | .waves[] | select(.wave == $N) | .depends_on[]" .forge/tracker.yaml)
  for dep in $WAVE_DEPS; do
    dep_status=$(yq ".features[] | select(.id == \"$TICKET\") | .waves[] | select(.wave == $dep) | .status" .forge/tracker.yaml)
    [ "$dep_status" != "merged" ] && UNMET="$UNMET wave-$dep:$dep_status"
  done
  ```

  If `UNMET` is non-empty, print:

  ```
  Wave <N> depends on wave(s) <deps>; <unmet list>.
  Proceed anyway? [y/n]
  ```

  Advisory — not blocking. Developer answers `y` when waves are file-disjoint and rebase is acceptable.

  **Audit-trail discipline** (re-invocation safety): the override write happens **after** the developer's `y` response and **before** Stage 7 Step 1 dispatches any plan-authoring agents — so a re-invocation that exits at the `[y/n]` prompt leaves no trace, and a re-invocation after a halt mid-Step-1 sees the prior override recorded and skips re-prompting.

  On `y`, append a block at the bottom of `.forge/engagement-gate-runs.md` immediately:

  ```
  ## /forge-deliver --wave override on <YYYY-MM-DD>

  Ticket: <TICKET>
  Wave: <N>
  Deps unmet: <comma-separated unmet list with each dep's status>
  Operator: <git config user.name>
  Decision: proceeded — operator asserts wave is file-disjoint from unmet deps and accepts rebase risk if those deps mutate shared files later.
  ```

  Then proceed to Stage 7 Step 1. On `n`, exit before any work begins; no audit write.

**Phase-transition guard (FR-7.h):** before any `phase` flip (e.g., `dev → review → done`), **re-read tracker** and verify the target state isn't already set by a concurrent session. The `done` flip checks: is every wave at `status: merged`? If yes AND `phase != done`, flip. If yes AND `phase == done`, skip silently. `merged` and `done` are terminal — last-writer-wins is safe.

#### Wave-loop steps (per selected wave)

**Step 0 — Per-wave contract authoring (contract-first integration).** Before any plan authoring, freeze the wave's BE↔FE seam contract so both plan-authors and both implementers build against a fixed interface (not a hand-rolled mock each).

- **Detect the seam.** A seam exists when the wave has a `type: verify` WI — the verify-WI was auto-proposed by `/forge-wave-decompose` step 5.b.5 precisely because it detected ≥1 BE-touching WI AND ≥1 FE-touching WI, and its `depends_on` names the two sides. (Same detection set as the verify-WI — by construction.)
- **No seam** (single-stack wave — only BE WIs or only FE WIs, no `type: verify` WI): skip Step 0 entirely and proceed to Step 1. No contract is authored.
- **Seam present:** invoke `forge-contract-author <ticket> <N>`. The skill authors/refreshes `.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md`, runs the **automated validation gate** (well-formed; FE-expected ⊆ BE-declared; schema lint on the Full path), and **freezes on pass — no human wait** (D5). Block Step 1 until the contract reaches `Status: frozen`.
  - On validation failure, the skill loops its own authoring (bounded N=2) then re-validates. If it still fails after N=2, it escalates — **halt** with the skill's failing-check report; the seam is under-specified and needs human/decompose attention. Do NOT proceed to Step 1 with an unfrozen contract.
- **Idempotent re-entry:** if the contract already exists at `Status: frozen`, Step 0 is a no-op — print the path and advance. A frozen contract is re-authored only on an explicit re-decompose (the skill records a `## Revisions` entry).

Unlike the spec-review (Stage 3) and plan-review (Stage 8) checkpoints, **Step 0 has no human gate** — the pipeline must not block between decompose and the parallel fan-out (D5). A human may review the frozen contract asynchronously (it's co-located with the plans).

**Step 1 — Parallel plan authoring.** Dispatch ALL WIs in the wave at `plan_status: backlog` simultaneously as parallel Agents:

```
for each WI in this wave at plan_status: backlog:
  Agent(
    description: "Draft plan — <ticket> <wi-id>",
    subagent_type: "general-purpose",
    prompt: <invoke forge-plan-author <ticket> <wi-id>>
  )
```

Wait for ALL agents. Halt on abort with resume hint.

> **Contract-first:** when Step 0 froze a contract for this wave, the plan-authoring prompt points each author at `.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md` as the **read-only** seam authority. `forge-plan-author` then conforms the plan to it (cite the contract for consumed/owned shapes; list it in `## Files to Modify` as read-only) and emits a conformance Success Criterion. Authors do NOT re-invent the shape — the frozen contract is the single source of truth for the seam (D3).

> **Design conformance:** when a WI touches frontend route/component files (per the repo's Stack Profile), its `forge-plan-author` dispatch prompt also points at the project design-system spec (`.forge/design/ui/<design-system>.md`) + the prototype/mockup (project-set), IF a design reference exists, and requires the plan's `## UI / Design Adherence` section plus a design-conformance Success Criterion. Plan-reviewer §12 gates it at Step 3.

**Step 2 — Cross-WI consistency gate.** Run once over all the wave's drafts:
- **Contract conformance (when Step 0 froze a contract)** — every BE/FE plan on the seam conforms to the frozen `<ticket>-Wave-<N>-contract.md`: the shapes a plan declares it owns/consumes match the contract, and the contract is listed read-only in its `## Files to Modify`. A plan inventing a shape that diverges from the frozen contract is a **Blocker** → either the plan conforms, or the contract is genuinely wrong → **halt → re-decompose** (the contract changes only via re-author, never a silent plan edit).
- **Contract alignment (single-stack / no frozen contract)** — every contract a plan declares as consumed is owned and declared compatibly by another plan (this wave or a prior approved wave).
- **File-collision** — no two same-wave WIs list the same path in `## Files to Modify`.

Halt before reviewing or dispatching anything if the gate fails.

**Step 3 — Per-WI review + topologically-ordered dispatch (human checkpoint).** Review the wave's drafts one-by-one in `(wave, id)` order. For each WI:

1. Invoke `forge-plan-review <wi-plan-path>`. Audit + apply fixes, present verdict, ask for approval.
   - Reject or unresolved Blocker → halt.
   - Approve → `workitems[<wi-id>].plan_status: approved`.
2. **If this wave is impl-ready AND this WI is a `type: sub`**, dispatch now (parallel with sibling sub-WIs). `type: verify` and `type: e2e` WIs do NOT dispatch in Step 3 — they wait for Pass-1 integration to create the wave branch, then dispatch (with `--base-branch feature/<TICKET>-wave-<N>`): a `type: verify` WI's **Phase 1** in **Step 5c** (`seam-test-implementer`, API) and its **Phase 2** in **Step 5e** (`e2e-test-implementer`, browser — T3 only); a `type: e2e` WI in **Step 5e** (`e2e-test-implementer`, full suite, after the API verify gate passes). Leave them at `plan_status: approved, impl_status: pending`.

   **Within-wave dependency rule (spec Rev 1 + Option-A two-pass integration):**

   | WI type | `depends_on` within wave | Dispatch timing | Base branch |
   |---|---|---|---|
   | `sub` | MUST be empty | Dispatch immediately on plan approval if wave is impl-ready (parallel with other `sub` WIs in the wave) — Stage 7 Step 3 / 5a | `main` |
   | `verify` | MAY contain sibling WI IDs (typically the BE-WI + FE-WI it integrates) | **Two-phase, after Pass-1 integration.** Phase 1 dispatches in Step 5c (seam-test-implementer, API); Phase 2 (T3 only) dispatches in Step 5e (e2e-test-implementer, browser, same branch). The `depends_on` drives the Pass-1 wait (verify can't start until those sub-WIs are integrated) but no longer drives per-WI dispatch — Pass-1 is the gate. | `feature/<TICKET>-wave-<N>` (sees sub-WIs' code already integrated) |
   | `e2e` | MAY contain sibling WI IDs (typically all prior verify-WIs) | Dispatches in **Step 5e**, after Step 5d's API verify gate (+ auto-repair loop) passes. For the final T-E2E wave (no sub WIs in its own wave), Pass-1 creates an empty wave branch from `main` so the e2e WI has somewhere to branch from; all prior waves are already merged to `main`. | `feature/<TICKET>-wave-<N>` |

   Within-wave queue (post-Option-A): the only queue Stage 7 maintains for Step 3 is "sub-WIs at `plan_status: approved, impl_status: pending`, dispatched as plans approve". Verify/e2e WIs queue happens implicitly via the Step 5b → Step 5c (verify Phase 1) → Step 5d API gate → Step 5e (verify Phase 2 browser + e2e) barrier chain. The "on every WI's transition to `impl_status: pr-open`, re-check queue" logic from earlier revisions is no longer needed at the per-WI level — the wave-level barriers (all sub-WIs at `pr-open` → Pass-1 → API verify → browser) replace it.

   **Dispatch mechanics (per `type: sub` WI in Step 3):**
   - `forge-worktree-up <ticket> <wi-id> --base-branch main` (sequential — tracker write serialization). `type: sub` WIs in wave mode have `base_branch: main`.
   - Pick the `subagent_type` per the **Specialist agent selection** table below (Item 7 — based on the WI's type, tier, and `## Files to Modify`).
   - Dispatch a **background** implementation Agent for this WI (`run_in_background: true`) using the implementation-agent prompt template (`.claude/lib/forge-deliver/agent-prompt-template.md`), passing the WI's `Success criteria` verbatim from the Decomposition Plan's `## Workitem Inventory`. Set `workitems[<wi-id>].impl_status: pending → dispatched`.
   - Set `waves[<N>].status: planned → in-progress` (first WI dispatch flips the wave).
   - Continue to the next WI's review without waiting.

   (Dispatch mechanics for `type: verify` WIs live in Step 5c (Phase 1) + Step 5e (Phase 2); for `type: e2e` WIs in Step 5e.)

   **If not impl-ready** (a dep wave isn't merged yet), leave the whole wave at `plan_status: approved, impl_status: pending`. It will be dispatched when its dep waves complete (handled at the next `/forge-deliver` invocation that sees the deps satisfied).

#### Specialist agent selection (per WI) — by WI type, tier, and `## Files to Modify`

| WI characteristic | `subagent_type` | Rationale |
|---|---|---|
| `type: sub`, touches `<backend-repo>` only | `backend-implementer` | Backend systems specialist — reads the repo's `## Backend Stack` profile on turn 1. |
| `type: sub`, touches `<frontend-repo>` only | `frontend-implementer` | Frontend specialist — reads the repo's `## Frontend Stack` profile on turn 1. |
| `type: sub`, cross-repo (both `<backend-repo>` + `<frontend-repo>`) | Pick the specialist for the repo with more files in `## Files to Modify`; the agent works both worktrees. Include both repos' `.claude/CLAUDE.md` in the prompt's read-order. If file counts are tied, prefer `backend-implementer` (data layer typically drives the contract). | Single-agent simplicity |
| `type: verify`, T3 (**two-phase** seam gate) | **Phase 1 (Step 5c):** `seam-test-implementer` `dispatch_mode: author` — authors the API/contract seam tests vs the frozen `<ticket>-Wave-<N>-contract.md`; no browser, no run. **Phase 2 (Step 5e, only after the API gate is green):** `e2e-test-implementer` `dispatch_mode: author` — authors the wave-scoped browser e2e on the SAME verify-WI branch | Agents author + static-check; **the orchestrator runs the API gate (5d) then the browser suite (5e)**, fails fast on the cheap API check before the browser run (D8), and drives the run→classify→fix→re-run loop (D11). A `finalize` dispatch opens the verify-WI's single per-WI PR |
| `type: verify`, T2 (contract-conformance smoke — **single-phase**) | `seam-test-implementer` only — `dispatch_mode: author` then `finalize` (it opens its own per-WI PR after the orchestrator's API gate is green) | API-level specialist; test-only, never edits `src/`, never runs the live seam — the orchestrator runs it (5d) |
| `type: e2e` (T-E2E spec-level browser-e2e suite) | `e2e-test-implementer` `dispatch_mode: author` then `finalize` | Browser/UX + accessibility specialist; **authors** the full spec suite against the final wave branch. The **orchestrator runs** it (Step 5e) after the API gate passes (D8 fail-fast) + drives the loop; `finalize` opens the PR |
| Anything else (foundation, unusual scope) | `general-purpose` | Fallback |

**Selection happens at dispatch time** — the orchestrator reads the WI's `type`, `tier`, and `## Files to Modify` table, applies the matrix above, and passes the chosen `subagent_type` to `Agent(...)`. Specialists inherit their stack knowledge from their system prompt; the orchestrator's prompt body (the template later in this stage) supplies WI-specific context including the WI's `# Success Criteria` from the Decomposition Plan.

When Wave 1's plans are all approved, flip `phase: workitem-decompose → dev` and proceed to **Stage 9 to open the plan PR early** (Wave 1 plans + Decomposition Plan). For later waves, commit + push approved plan files to `feature/<ticket>-plan` as follow-up commits.

> **`--no-implement` mode:** skip dispatch entirely — the Step 3 sub-WI dispatch, the Step 5c verify Phase-1 dispatch, AND the Step 5e verify Phase-2 + e2e dispatch. Step 0 (contract authoring) still runs — contracts are plan-time artifacts and freezing them is part of "all plans authored against a fixed interface." Author + gate + review every wave's plans in ascending order (no impl-ready gating), open the bundled plan PR with all plans, flip `phase: workitem-decompose → plan` (not `dev`), halt at the `--no-implement` boundary.

**Step 4 — Start the next wave's plan-shaping (overlap).** Once the current wave's plans are all approved (contract shapes locked), the next plan-ready wave's Step 1–3 may begin **while the current wave's implementation agents run in the background**. Plan-shaping for wave N+1 does NOT depend on wave N's PR being merged — only contract-shape locking does, which happens at plan approval.

**Step 5a — Await sub-WI impl.** Wait for every `type: sub` WI in this wave to reach `impl_status: pr-open`. If any agent returned without a PR URL → halt. (Verify/e2e WIs are not dispatched yet — they're waiting for the wave branch to exist.)

**Step 5b — Pass-1 wave integration (early — Stage 11 Pass 1).** Once all sub-WIs are `pr-open`, hand off to **Stage 11 Pass 1**:
- Create `feature/<TICKET>-wave-<N>` from `main` in **every repo touched by this wave** (union of `workitems[*].touched_repos[]` across all WI types — sub, verify, e2e — so verify/e2e WIs targeting repos not touched by any sub-WI still have a wave branch to base on).
- Merge sub-WI branches into the wave branch in topological order. Push.
- Clean up sub-WI worktrees (their branches are on the remote, integration is pushed).

Stage 11 Pass 1 returns control here. The wave branch now exists on remote with all sub-WIs integrated.

Edge case — wave has no sub WIs (e.g., the final T-E2E wave where the only WI is the e2e WI): Step 5a is a no-op; Step 5b still creates the wave branch (from `main`, with no merges) and pushes it, so verify/e2e WIs (Step 5c / Step 5e) have somewhere to branch from.

> **⚠️ Phase 2 — the orchestrator runs the gates (execution decoupling — see the **Dispatch invariants** section below).** A dispatched sub-agent is torn down when it returns, so it cannot keep both servers booted for the API-seam gate or drive a live browser suite across the run (see **Dispatch invariants**) — so in Steps 5c–5f the verify/e2e agents **author + static-check only** (`dispatch_mode: author`), and **this orchestrator (a full session) executes the suites** and owns the **run → classify → dispatch-fix → re-run-until-green** loop (D11, now extended to the browser layer). After green, a `finalize` dispatch runs `/forge-test-verify` (green-status guard) → `/forge-pre-pr-review` → `/forge-pr-open` and flips `impl_status: dispatched → pr-open`.

**Step 5c — Verify Phase 1: dispatch verify-WIs to `seam-test-implementer` to AUTHOR the API seam tests (no run).** For each `type: verify` WI in this wave at `plan_status: approved, impl_status: pending`:
- `forge-worktree-up <ticket> <wi-id> --base-branch feature/<TICKET>-wave-<N>` (sequential — tracker write serialization). The verify-WI's per-WI branch (`feature/<TICKET>-WI-<wave>.<index>-<slug>`) branches **from the integrated wave branch**, NOT from `main`, so the agent sees the sub-WIs' code already merged in its worktree from turn 1. **This worktree is reused for the orchestrator's run (5d) and Phase 2 (5e) — do NOT clean it.**
- `subagent_type: seam-test-implementer`, `dispatch_mode: author` (per the **Specialist agent selection** table). Pass the frozen contract path (`.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md`), the verify-WI's `seam_owners` (BE-WI + FE-WI from its `depends_on`), and `two_phase: <true if tier T3 | false if tier T2>`. The agent **authors the API seam tests + static-checks (compile / test-listing, per the repo's `## Common Commands`) + commits + reports `Seam tests ready to run`** — it does NOT boot servers or run the seam.
- Dispatch a **background** Agent (`run_in_background: true`).
- Set `workitems[<wi-id>].impl_status: pending → dispatched`.

Edge case — wave has no `type: verify` WI (single-stack wave, or the final T-E2E wave whose only WI is `type: e2e`): Step 5c and Step 5d are no-ops; jump to Step 5e.

**Step 5d — Orchestrator runs the API verify gate + run→classify→fix→re-run loop (D11).** For each `type: verify` WI:

1. **Await the `author` dispatch.** If seam-test-implementer reported a `contract` defect at authoring → **halt → re-decompose** (the contract changes only via re-author; never patch in-loop).
2. **The orchestrator runs the API seam gate** on the verify-WI's worktree (the orchestrator is a persistent session, so it can keep both servers booted across the run; a dispatched sub-agent runs to completion in one shot and is torn down on return, killing any server it started — that is *why* the orchestrator runs live tiers, not a Bash-capability gap. See **Dispatch invariants**): per the verify-WI plan's `## Test Approach` toolchain (the project's API-seam / browser-e2e commands from `.forge/test-strategy.md` + the repo's `## Common Commands`). Capture exit + output and **record the run into the verify-WI's `<wi-id>-test-verify.md` audit `## Test runs (orchestrator-executed)` section** (pinned to the worktree HEAD SHA) so the later `/forge-test-verify` guard reads it.
3. **On failure, classify and route** (orchestrator decides):
   - **Test bug** (the test is wrong; the live response matches the contract) → re-dispatch `seam-test-implementer` `dispatch_mode: test-fix` with the failing test path + output. It fixes the *test*, re-statics, commits, hands back → **re-run step 2**.
   - **In-wave code bug** → **auto-repair (D11), no human**: authoritative file-ownership attribution — union of `## Files to Modify` across this wave's `sub` WIs; offending file **∈** that set → dispatch the owning implementer (`backend-implementer` BE / `frontend-implementer` FE) **scoped to the offending files** with the failure as the fix brief → re-integrate the fix into the wave branch (mini Pass-1 merge; conflict-resolution agent on conflicts) → **re-run step 2**.
   - **Contract defect** → halt → re-decompose. **Pre-existing/old code** (offending file **∉** this wave's WIs' `Files to Modify`) or **ambiguous attribution** → escalate to HUMAN (prefer escalation when origin is unclear — proposal §8).
   - **Bound N=2** per failure class; on exhaustion → escalate (a recurring defect is a contract/decomposition fault, not a bug to keep patching).
4. **Once the API gate is green:**
   - **T2 (single-phase):** dispatch `seam-test-implementer` `dispatch_mode: finalize` → it runs `/forge-test-verify` (the guard reads the green run recorded in step 2) → `/forge-pre-pr-review` → `/forge-pr-open` → `impl_status: dispatched → pr-open`. (The agent runs these three skills *inline* — it has no Agent/Skill tool; this is only safe because none of them re-dispatches. See **Dispatch invariants**.)
   - **T3 (two-phase):** no PR yet → proceed to Step 5e Phase 2.

When every verify-WI is either `pr-open` (T2) or API-gate-green (T3), proceed to Step 5e. The orchestrator never edits `src/` itself — even in the repair loop it *dispatches an implementer*. The agents author/fix; the orchestrator runs and routes.

**Step 5e — Verify Phase 2 (browser e2e) + final-wave `type: e2e` — author via `e2e-test-implementer`, run via the orchestrator.** Only after Step 5d's API gate passes. Two kinds of browser-e2e work, both on the wave branch:

- **(a) Verify Phase 2** — for each **T3** verify-WI that passed the API gate: dispatch `e2e-test-implementer` on the **SAME verify-WI worktree/branch** from Step 5c (do NOT re-provision — it carries seam-test-implementer's committed API tests). Pass `mode: wave`, `wi_type: verify`, `verify_phase: 2`, `dispatch_mode: author`. The agent **authors the wave-scoped browser e2e + static-checks + reports `Ready to run`** — it does NOT run the browser, does NOT open the PR.
- **(b) Final-wave e2e** — for each `type: e2e` WI at `plan_status: approved, impl_status: pending`: `forge-worktree-up <ticket> <wi-id> --base-branch feature/<TICKET>-wave-<N>`; dispatch `e2e-test-implementer` (`wi_type: e2e`, `dispatch_mode: author` — authors the full spec suite + static-checks). Set `impl_status: pending → dispatched`.

Background dispatch for both. Then, per WI:

1. **The orchestrator runs the browser suite** (per the verify-WI plan's `## Test Approach` toolchain — the project's API-seam / browser-e2e commands from `.forge/test-strategy.md` + the repo's `## Common Commands`) on that WI's worktree and records the run into its `<wi-id>-test-verify.md` audit `## Test runs (orchestrator-executed)` section (HEAD-pinned).
2. **On failure, classify and route** — same loop as 5d, **now extended to the browser layer**: **test bug** → `e2e-test-implementer` `dispatch_mode: test-fix` → re-run; **code bug** → route by the buggy file's repo to `backend-implementer` / `frontend-implementer` (D11 file-ownership attribution; for the final-wave e2e, "this wave's WIs" widens to all merged WIs the suite exercises — a defect ∉ any WI's `Files to Modify` escalates to human) → re-integrate → re-run; **bound N=2** → escalate.
3. **Once green:** dispatch `e2e-test-implementer` `dispatch_mode: finalize` on that branch → `/forge-test-verify` (guard reads the green run) → `/forge-pre-pr-review` → `/forge-pr-open` → `impl_status: dispatched → pr-open`. (Run inline by the agent — safe only because none of the three re-dispatches; see **Dispatch invariants**.) For a `type: verify` Phase-2 WI this single PR covers the combined branch (Phase-1 API tests + browser e2e).

Edge case — wave has no T3 verify-WI AND no `type: e2e` WI: Step 5e and Step 5f are no-ops; jump to Step 6.

**Step 5f — Await finalize.** Wait for every T3 verify-WI and every `type: e2e` WI to reach `impl_status: pr-open` (via its `finalize` dispatch). If the run→fix loop for a WI exhausts its N=2 bound without reaching green → halt and escalate.

**Step 5g — Design vision pass (UI waves with a design reference — L-022).** A standing runtime design-conformance gate for every wave that ships user-facing UI. **Gated on both:** (a) this wave ships ≥1 user-facing UI WI (a T3 WI touching frontend route/component files), AND (b) the project has a design reference (`.forge/design/ui/<design-system>.md` + a prototype/mockup, project-set). If either is absent, Step 5g is a no-op — jump to Step 6.

While the orchestrator still has the browser context from Step 5e's run, for each new or changed user-facing route this wave ships:

1. **Screenshot the running route** on the integrated wave branch (the same servers the Step 5e browser suite used).
2. **Compare against the design-of-record** — the prototype/mockup for that screen plus the design-system tokens/layout the WI plan's `## UI / Design Adherence` section cites. Record observed-vs-expected for the named tokens, layout regions, and key affordances the spec's observable visual ACs require.
3. **On material drift** (a divergence from a named token / layout region / affordance that an observable visual AC requires — not a subjective "looks off"), classify and route exactly like the Step 5d/5e D11 loop:
   - **In-wave implementation defect** (the drifting surface ∈ this wave's frontend WIs' `## Files to Modify`) → auto-repair via the owning `frontend-implementer`, scoped to the offending files, bounded N=2 → re-integrate (mini Pass-1 merge) → re-screenshot.
   - **Spec/prototype ambiguity** (the design-of-record itself is unclear or the AC under-specifies the visual) → escalate to a human; do not guess.
4. **Record the verdict** in the wave's audit (the per-WI `<wi-id>-test-verify.md` for the UI WI, a `## Design vision pass` section) — observed routes, drift found, resolution.

This pass is the runtime backstop to spec-time prototype transcription: it catches visual drift that green unit/e2e assertions mask (an assertion can pass while the rendered token/layout diverges from the design-of-record). It runs **before** Stage 12 opens the wave PR, so design drift is caught before the wave reaches the Stage 13 human-merge halt. The orchestrator runs the screenshots itself (persistent browser context); the `frontend-implementer` does any fixes (the orchestrator never edits `src/` — consistent with the D11 loop).

**Step 6 — Pass-2 wave integration → wave PR → halt (Stage 11 Pass 2 → Stage 12 → Stage 13).** Once all verify/e2e WIs are `pr-open`, hand off to **Stage 11 Pass 2** (merge verify/e2e WI branches into the existing wave branch, push, clean up verify/e2e worktrees), which flows into **Stage 12** (open wave PR via `forge-pr-open --wave <N>`), which flows into **Stage 13** (halt for human merge).

After Stage 13's halt, this command exits. The developer merges the wave PR(s) in GitHub UI and re-invokes `/forge-deliver <ticket>`. The next invocation picks up at **Stage 14** (wave-merge-wait poll), which on all-merged either dispatches the next wave's Stage 7 OR advances to Stage 15 (if this was the last wave).

**Termination.** After the last wave (T-E2E if present, else last data wave) is `status: merged`, flip `phase: dev → review` and advance to Stage 15.

**Resume sub-state derivation.** If `/forge-deliver` resumes mid-wave (`waves[<N>].status: in-progress`), derive Step 5 sub-state from per-WI `impl_status`:

| State | Resume at |
|---|---|
| Any `type: sub` WI in this wave not at `pr-open` | Step 5a (continue awaiting) |
| All `type: sub` WIs at `pr-open` AND wave branch not yet on remote | Step 5b (Pass-1 integration) |
| Wave branch on remote AND some `type: verify` WI's **API gate is not yet green** (T2: not `pr-open`; T3: no green orchestrator-run recorded for the API seam, and not `pr-open`) | Step 5c/5d (author seam tests if missing → orchestrator runs the API gate + D11 run→fix→re-run loop) |
| All verify WIs' API gates green (T2 → `pr-open`; T3 → API gate green) AND some T3 verify-WI not yet `pr-open` OR some `type: e2e` WI not yet `pr-open` | Step 5e/5f (author browser e2e if missing → orchestrator runs the browser suite + loop → finalize) |
| All `type: verify` + `type: e2e` WIs at `pr-open` (and Pass-2 hasn't run) | Step 6 (Pass-2 integration → Stage 12 → 13) |

Detect "verify API gate green" via the seam-test-implementer's committed API-test (`git log` on `feature/<TICKET>-WI-<wave>.<index>-<slug>` for the `test: … add API-level seam verification` commit) **plus** a green `## Test runs (orchestrator-executed)` entry in the WI's `<wi-id>-test-verify.md` audit whose pinned SHA matches the branch HEAD. The commit alone means "authored"; the recorded green run means "API gate passed." Re-entry on a `planned` wave (not yet in-progress) starts at **Step 0** (contract authoring) — idempotent: a frozen contract makes Step 0 a no-op.

Detect "wave branch on remote" via `git ls-remote --heads origin feature/<TICKET>-wave-<N>` (in any touched repo).

---

### Stage 8 — Single plan review (human checkpoint)

Entry condition: `phase: plan`, `decomposed: false`, plan at `Status: draft/in-review`.

Invoke `forge-plan-review <plan-path>`. The plan carries `## Wave Ship State` (single-plan-in-wave-mode). Plan-reviewer's §11 audits it (WS-1 section presence, WS-5 AC coherence).

- Human approves → plan `Status → approved`. Continue to Stage 9 (or halt at `--no-implement`).
- Human rejects → halt.

---

### Stage 9 — Open plan PR

Branch-based entry check. On first open, branch `feature/<TICKET>-plan` off `feature/<TICKET>-spec`'s tip and invoke `forge-pr-open <ticket> --artifact plan` (base: stacked on spec branch). On re-entry from later waves, append the wave's approved plan files as follow-up commits and push.

---

### Stage 10 — Worktree provisioning + single-plan implementation dispatch (single-plan only)

A single-plan-in-wave-mode feature has no Decomposition Plan and no `waves[]` — the one plan IS the only wave. This stage provisions the worktree, dispatches **one** implementation agent, and on PR open advances straight to **Stage 15** (Stages 11–14 are multi-plan-only and skipped, per Stage 11's "Single-plan: skip Stage 11–14 entirely").

**Live-tier guard — single-plan cannot run live (browser / API-seam) suites. Check FIRST, before the idempotent entry check or any provisioning.** Read the plan's `## Test Approach` tier. **If it is `T3` or `T-E2E`, HALT** — the single-plan path has no `type: verify` / `type: e2e` WI and **no orchestrator-run live gate** (Stages 11–14, which run the live API-seam + browser suites for decomposed features, are skipped here). Dispatching anyway would open a code PR with the feature's browser / API-seam acceptance criteria **never executed**. Print and exit:

```
## Halted at Stage 10 — single-plan feature has a live tier (<T3 | T-E2E>)

<ticket>'s plan declares tier <T3 | T-E2E>, which needs live browser / API-seam
tests. A single-plan feature has no verify/e2e WI and no orchestrator-run live
gate, so those tests would never run.

Re-decompose into waves so a `type: verify` / `type: e2e` WI carries the live gate:

    /forge-wave-decompose <ticket>      # choose multi-plan

(Most user-facing features are T3/T-E2E and should be multi-plan; this guard is
the backstop for a single-plan size assessment that picked wrong.)
```

Do NOT provision, dispatch, or open a code PR. **Pure `T1` / `T2` single-plan features proceed normally** — the implementer runs their own unit / integration suites (no live servers or browser needed), so the single-plan path is sound for backend / data-layer features.

> **Upstream-fix pointer (not in this change):** `/forge-wave-decompose`'s size assessment should steer T3/T-E2E features to multi-plan up front so this guard rarely fires. That's a `forge-wave-decompose` change — tracked separately; the Stage 10 halt here is the backstop.

**Idempotent entry check (re-invocation safety):** for each repo the plan's `## Files to Modify` touches:

```bash
OPEN_CODE_PR=$(gh pr list --repo <github-org>/<repo> \
  --head "feature/<TICKET>-<slug>" --state open --json number --jq '.[0].number' 2>/dev/null)
```

If a code PR is already open in every touched repo → skip dispatch and advance to Stage 15. Otherwise:

1. **Provision.** Invoke `forge-worktree-up <ticket>` (reads `## Files to Modify` to provision only the touched repos' worktrees; base `main`).
2. **Flip phase `plan → dev`.** Mirrors the multi-plan Wave-1 first-dispatch flip (Stage 7, line ~301). Required because `forge-pr-open`'s single-plan code-PR mode flips `phase: dev → review` — the feature must be at `dev` when the agent opens its PR. This is the only `phase` flip on the single-plan path before Stage 15.
3. **Select specialist.** Pick `subagent_type` from the plan's `## Files to Modify` per the Stage 7 **Specialist agent selection** table.
4. **Dispatch.** Dispatch ONE **background** implementation Agent (`run_in_background: true`) using the implementation-agent prompt template (`.claude/lib/forge-deliver/agent-prompt-template.md`), with single-plan annotations: no sibling-WI warning; base branch `main`; `# Success Criteria` copied verbatim from the plan's own `## Success Criteria` section; tier from the plan's `## Test Approach`; read-order = plan + spec + touched repos' `.claude/CLAUDE.md` (omit the Decomposition Plan path — single-plan has none), **plus the frontend design-system reads per the `# Paths` block when the plan touches frontend route/component files and a design reference exists — the design-system spec always, and the screen's visual target (prototype screenshot/mockup) only when the plan names a screen**. The agent runs its subtasks, then `/forge-pre-pr-review`, then `/forge-pr-open` (single-plan code mode — opens the code PR to `main` and flips `phase: dev → review`).
5. **Await.** Wait for the agent. If it returns without a PR URL → halt with a resume hint. On PR open → advance to **Stage 15**.

> **Multi-plan:** worktree provisioning is inline in Stage 7 — sub-WIs in Step 3 (`--base-branch main`), `type: verify` WIs in Step 5c and `type: e2e` WIs in Step 5e (both `--base-branch feature/<TICKET>-wave-<N>`, the wave branch built by Stage 11 Pass 1). WAVE_BASE = main always applies to the wave branch itself; verify/e2e per-WI branches base from the wave branch.

---

### Stage 11 — Wave integration merge (multi-plan only — two-pass per wave)

Stage 11 runs **twice per wave** in Option-A two-pass mode:
- **Pass 1 — Sub-WI integration** — triggered by Stage 7 Step 5b after all `type: sub` WIs reach `impl_status: pr-open`. Creates the wave branch and merges sub-WI branches in. The wave branch is then the base for verify WIs (dispatched in Step 5c) and e2e WIs (dispatched in Step 5e).
- **Pass 2 — Verify/E2E integration** — triggered by Stage 7 Step 6 after all `type: verify` and `type: e2e` WIs reach `impl_status: pr-open`. Reuses the wave branch from Pass 1, merges verify/e2e branches in. Then flows into Stage 12.

**Single-plan:** skip Stage 11–14 entirely. The single-plan agent's PR (opened in Stage 10's dispatch) IS the feature; advance directly to Stage 15.

**Multi-plan (FR-7.g):** both passes run from each touched main app repo checkout — NOT from any worktree.

#### Pass 1 — Sub-WI integration

**Execute the Pass 1 scaffold from `.claude/lib/forge-deliver/integration-scaffolds.md`** — read that file now; do not improvise the sequence from memory.

Pass 1 returns control to Stage 7 Step 5c, which dispatches the wave's `type: verify` WIs (seam-test-implementer) against the now-existing wave branch; `type: e2e` WIs dispatch later in Step 5e, after the verify gate (Step 5d) passes.

#### Pass 2 — Verify/E2E integration

**Execute the Pass 2 scaffold from `.claude/lib/forge-deliver/integration-scaffolds.md`** — read that file now if not already loaded this session; do not improvise the sequence from memory.

Pass 2 returns control to Stage 7 Step 6, which hands off to Stage 12 (open wave PR).

Edge case — wave has no verify/e2e WIs: Pass 2 is skipped entirely; Stage 7 Step 6 hands directly from Pass-1 completion to Stage 12.

**Tracker discipline (both passes):** Stage 11 does NOT mutate `impl_status` — the integration merge is a transient on-disk fact; the next tracker write happens in Stage 12 where `forge-pr-open --wave <N>` atomically flips `impl_status: pr-open → wave-closed` for **all** per-WI PRs in this wave (sub, verify, and e2e) and `waves[<N>].status: in-progress → pr-open` together. `impl_status` enum stays at FR-10's `pending | dispatched | pr-open | wave-closed`.

---

### Stage 12 — Open wave PR(s) via `forge-pr-open --wave <N>`

Invoke `forge-pr-open <ticket> --artifact code --wave <N>`. The skill:

1. Reads the wave's row from the Decomposition Plan's `## Wave Ship Plan` table.
2. Composes PR body from ship state one-liner + verification command + WI list + pre-ticked verification checklist.
3. Computes the wave's touched repos = union of `workitems[*].touched_repos[]` for this wave.
4. For each touched repo: opens PR with head=`feature/<TICKET>-wave-<N>`, base=`main`. Idempotent — `gh pr list --head` pre-check skips if already open.
5. Updates tracker `features.<ticket>.waves[<N>].status: in-progress → pr-open`. (PR URL is NOT stored — derived on demand via `gh pr list`.)
6. Auto-closes **all per-WI PRs in this wave — sub, verify, and e2e** — uniformly: `gh pr close $(gh pr list --head <WI-branch>) --comment "Superseded by wave PR..."`. Flip every `workitems[<wi-id>].impl_status: pr-open → wave-closed`. (Verify/e2e per-WI PRs have already been merged into the wave branch by Stage 11 Pass 2, so they show as "no commits ahead of base" by the time Stage 12 closes them — explicit close keeps the PR list tidy.)

After `forge-pr-open --wave <N>` returns, the orchestrator **harvests this wave's test stats** (Stage 12b).

#### Stage 12b — Harvest test stats into the feature ledger

The orchestrator owns `.forge/plans/<ticket>/<ticket>-test-stats.jsonl` (the append-only ledger) and `.forge/plans/<ticket>/<ticket>-test-report.md` (the regenerated human rollup). Both live in the plans folder — orchestrator write territory; impl agents never touch them.

> **Concurrency contract (`--wave <N>` parallel waves).** Two orchestrator sessions can run different waves at once (FR-7.d), and both would hit Stage 12b against the *same* ledger + report. To keep waves disjoint (the harness's existing parallel-wave invariant), the ledger is written **append-only** here and the human report is regenerated by a **single writer** — never read-modify-write a shared file from a wave session. Concretely: appends are line-atomic; dedup is deferred to read time; the `.md` regen is deferred to Stage 15 (the one terminal single-session rollup) except in the default non-`--wave` flow.

For each WI in this wave, read its per-WI audit file `.forge/plans/<ticket>/<wi-id>-test-verify.md` and extract the **most recent** `## Test Stats (machine-readable)` block (the `forge-test-stats/v1` JSON, written by `/forge-test-verify` — see that skill's Step 6):

1. **Flatten** the block's `runs[]` into one JSONL line per run, each carrying: `ticket`, `wi_id`, `wave`, `wi_type`, `tier`, `scope: "wi-pr-open"`, `test_type`, `framework`, `repo`, `counts_source`, `git_sha`, `captured_at`, and the run's `totals`.
2. **Append-only — never replace.** `>>`-append each line to the ledger. Do **not** read-modify-write to dedup (that races two `--wave` sessions and can drop lines). Idempotency is handled at *read* time instead (step 4 / Stage 15): re-runs and resumes append duplicate keys harmlessly; they collapse on read. A single sub-4KB JSON line appended with `O_APPEND` is atomic on a local filesystem, so concurrent waves don't corrupt each other.
3. **Missing or unparseable.** If a WI has no audit file (test-verify wasn't run for it) OR its block carries `counts_source: "unparseable"` / `totals: null`, append a line with `totals: null` and `gap_reason: "no-audit" | "unparseable"`. **Never synthesize a zero** — a gap and a genuine zero are different facts.
4. **Report regen — single-writer only.** **If this invocation was started *without* `--wave <N>`** (the default sequential flow — one orchestrator owns the whole feature), regenerate `<ticket>-test-report.md` now from the full ledger using `.forge/plans/_TEMPLATE-test-report.md`, deduping on read: group ledger lines by `(wi_id, scope, test_type, repo, git_sha)`, keep the latest `captured_at`, then group by `test_type` for as-shipped totals and by `wave` for the breakdown; list gaps explicitly. **If this invocation *was* started with `--wave <N>`** (parallel mode), **skip the `.md` regen** — Stage 15 does the authoritative single regen once all waves merge. The ledger is still queryable mid-flight either way.
5. **Commit.** Stage + commit the ledger (and, in the non-`--wave` flow, the report) to `feature/<ticket>-plan` alongside the wave's other harness writes (the harness branch, never the app-repo wave branch).

Coverage note: in wave mode the **verify/e2e WIs run against the integrated wave branch**, so their suite runs (per the verify-WI plan's `## Test Approach` toolchain — the project's unit / integration / browser-e2e commands from `.forge/test-strategy.md` + the repo's `## Common Commands`) already cover the wave's cumulative unit + integration + browser-e2e counts. A wave with **no** verify WI (pure sub-WI wave, no integration test) produces no `wi-pr-open` stats for that wave — the report lists it as a coverage gap rather than an empty wave.

---

### Stage 13 — Halt for wave merge (human checkpoint)

```
## Wave <N> PR(s) opened — awaiting human merge

Boundary: HARD — re-invoke only AFTER the wave PR(s) below merge.

Wave <N> ship plan (from Decomposition Plan):
  ship_type:    <vertical | monolithic>
  ship state:   <one-line>
  verification: <smoke command or pointer>

Wave PRs:
  <repo-1>: <wave PR URL>
  <repo-2>: <wave PR URL>
  ...

Action required:
  1. (optional) /forge-review-pr <N>          — per wave PR
  2. Merge each wave PR via GitHub UI when CI green + review approves

After all wave PRs are merged, re-invoke:
    /forge-deliver <TICKET>
to dispatch wave <N+1> off main (or to advance to Stage 15 if this was
the last wave).
```

This halt is the **per-wave hard boundary** (see "Context budget & session scope") — it ends the wave's session so the next wave starts with a fresh context. The block is intentionally kept to PR URLs + the merge action + the re-invocation; the wave's ship plan is read from the Decomposition Plan, and Stage 0 re-derives all state — do not expand it into a full recap.

**STOP. End the assistant turn here.** Print the fenced block and exit. Do NOT poll for merges, do NOT auto-advance.

---

### Stage 14 — Wave-merge-wait poll (re-invocation only)

On re-invocation when some wave has `status: pr-open`:

```bash
WAVE_PR_STATES=""
for REPO in $TOUCHED_REPOS; do
  state=$(gh pr view --repo <org>/$REPO --head "feature/<TICKET>-wave-<N>" --json state --jq '.state' 2>/dev/null)
  WAVE_PR_STATES="$WAVE_PR_STATES $REPO:$state"
done

if any state is OPEN:
  print "Wave <N> PR still open in: <repo(s)>. Merge in GitHub UI, then re-run /forge-deliver <TICKET>."
  print URLs
  exit
if any state is CLOSED (not MERGED):
  halt + escalate: "Wave <N> PR closed without merging in <repo>. Investigate, re-open or reset, then re-run."
if all MERGED:
  features.<ticket>.waves[<N>].status: pr-open → merged
  features.<ticket>.waves[<N>].merged_at: <today>
  proceed to Stage 7 for wave <N+1> (or Stage 15 if last wave)
```

---

#### Dispatch invariants (read before changing any dispatch or finalize site)

These three constraints are load-bearing for every `Agent(...)` dispatch in this command. Each is a real Claude Code execution limit, not a style choice — breaking one silently corrupts a wave.

1. **No recursive sub-agent dispatch.** A dispatched sub-agent CANNOT itself dispatch another sub-agent — there is no nested Task. The implementer/verifier agents (`backend-implementer`, `frontend-implementer`, `seam-test-implementer`, `e2e-test-implementer`) are provisioned with `tools: Read, Edit, Write, Bash, Grep, Glob` — **no Agent tool, no Skill tool.** So when a dispatched agent is told to "run `/forge-test-verify`, `/forge-pre-pr-review`, `/forge-pr-open`," it executes those skills' deterministic steps **inline / via Bash** (git, gh, lint, test commands) — it does NOT, and cannot, spawn a sub-agent for them.

2. **`finalize` is safe ONLY because those three skills never re-dispatch.** `/forge-test-verify`, `/forge-pre-pr-review`, and `/forge-pr-open` are inline/deterministic *by contract*: test-verify runs a command and reads an audit; pre-pr-review does an **in-context** adversarial sweep (NOT a sub-agent dispatch); pr-open runs git/gh. **If any of these is ever changed to dispatch a sub-agent, every `finalize` dispatch in Steps 5d/5e breaks** — the sub-agent will fail to spawn the nested agent and the WI never reaches `pr-open`. When editing those skills, preserve this invariant or move that work up to the orchestrator. The review skills that *do* dispatch sub-agents (`forge-spec-review` → `spec-reviewer`, `forge-plan-review` → `plan-reviewer`) are therefore only ever invoked by the **main orchestrator** (Stages 3, 6, 8) — never from inside a dispatched agent.

3. **Live servers / browsers run in the MAIN session, never a sub-agent.** A sub-agent runs to completion in one shot, so any dev server or browser it backgrounds is **torn down the moment it returns** — it cannot hold both servers up and drive a live suite across a run. That is why Steps 5d/5e have the agents *author + static-check only* and the **orchestrator** runs the live API-seam gate and browser suite (a persistent session keeps servers booted across turns). Do not "optimize" a live run back into a sub-agent — the limitation is process-teardown, not a Bash-capability difference (both have the same Bash sandbox).

#### Implementation agent prompt template (multi-plan + single-plan)

Build dynamically. Self-contained — agent starts cold. **Read `.claude/lib/forge-deliver/agent-prompt-template.md` before ANY implementation dispatch (Stage 7 Steps 3/5c/5e, Stage 10) and build each prompt by filling that template — never reconstruct it from memory.** The Verify-WI and T-E2E adaptation notes below apply on top of the template.

**Verify-WI note (contract-first, two-phase + Option-A two-pass integration):** a `type: verify` WI is a **two-phase gate on a single per-WI branch**, dispatched **after** Stage 11 Pass 1 has merged all sub-WIs into the wave branch (its worktree is provisioned with `--base-branch feature/<TICKET>-wave-<N>`, so it contains the integrated sub-WIs' code from turn 1 — no ad-hoc `git fetch` required; the worktree is **reused across both phases**):

- **Phase 1 — `seam-test-implementer` (Step 5c), `dispatch_mode: author`.** API/contract-level seam tests, **no browser, no accessibility checks** — and in **Phase 2 it AUTHORS + static-checks only; the orchestrator runs the API gate** (Step 5d). The orchestrator passes `contract_path` (the frozen `<ticket>-Wave-<N>-contract.md`), `seam_owners` (BE-WI + FE-WI from the verify-WI's `depends_on`), `two_phase` (true for T3, false for T2), and the `be_worktree`/`fe_worktree` paths, plus the standard plan/spec/Decomposition-Plan paths. The agent commits its seam tests + reports `Seam tests ready to run`. The **orchestrator then runs the API gate** and, on a failure, drives the **Step 5d run→classify→fix→re-run loop** (D11: test bug → `seam-test-implementer` `test-fix`; in-wave code bug → the owning implementer auto-fixes, no human, bounded N=2; pre-existing-code regressions and contract defects escalate). On a green API gate: **T2** verify-WIs are single-phase — a `finalize` dispatch of seam-test-implementer opens the per-WI PR and the WI reaches `pr-open`. **T3** verify-WIs proceed to Phase 2 (no PR yet).
- **Phase 2 — `e2e-test-implementer` (Step 5e, T3 only), `dispatch_mode: author`.** Dispatched on the SAME verify-WI worktree/branch (`wi_type: verify`, `verify_phase: 2`) to **author + static-check** the **wave-scoped browser e2e** for this wave's capability. The **orchestrator runs** the browser suite + the loop; once green, a `finalize` dispatch **opens the verify-WI's single per-WI PR** (base = wave branch, not `main`) — flipping `impl_status: dispatched → pr-open`.

Stage 11 Pass 2 merges the verify-WI's branch (carrying both the API tests and the browser e2e) back into the wave branch before the wave PR opens.

**T-E2E WI note:** Use the same prompt with these differences — no sibling WI warning (T-E2E is its own wave), tier always `T-E2E`, base branch is the wave branch (`feature/<ticket>-wave-<N>`, which Pass 1 created from `main` with no merges since the T-E2E wave has no sub-WIs). Annotation: *"Your base branch (the wave branch, branched from main) contains all prior waves' merged code on main. Read the prior WIs' plans for context — do not re-implement their work."*

---

#### Conflict-resolution agent (wave integration)

Resolves syntactic + non-contradictory merge conflicts during wave integration; escalates on genuine semantic contradiction. Dispatched by Stage 11 (both passes) on a conflicting `git merge`.

---

#### Halt conditions

- **Implementation escalation:** halt with the plan ## Notes pointer + resume command.
- **Irresolvable merge conflict during wave integration:** halt with conflicting WIs + agent's description + two resolution options (revise plans / manual resolve).
- **File overlap detected by impl agent:** halt with the conflicting file + WI IDs + resume command after plan revision.

---

### Stage 15 — Verify all waves merged + Reflect + flip to done

**Step 1 — Verify every wave at `status: merged`.**

```bash
ALL_MERGED=$(yq ".features[] | select(.id == \"$TICKET\") | .waves[] | .status" .forge/tracker.yaml | grep -v merged | wc -l)
if [ "$ALL_MERGED" -ne 0 ]; then
  echo "Not every wave is at status: merged — Stage 15 cannot run."
  exit 1
fi
```

Also `gh pr view` the spec PR + plan PR (must be `OPEN` or `MERGED`).

**Step 1b — Phase guard (FR-7.h):**

```bash
CURRENT_PHASE=$(yq ".features[] | select(.id == \"$TICKET\") | .phase" .forge/tracker.yaml)
if [ "$CURRENT_PHASE" = "done" ]; then
  echo "Feature $TICKET already at phase: done — concurrent session got here first. Exit clean."
  exit 0
fi
```

Flip `phase: dev → review` if not already there. Then flip `review → ship` (this is the "all waves merged" milestone — no separate code-PR-merged check needed since wave PRs ARE the code PRs).

**Step 2 — Ensure harness on plan branch.**

`git checkout feature/<TICKET>-plan` (should already be current).

**Step 2b — Final test-stats rollup (authoritative single regen).**

Stage 15 runs in exactly one session — when *all* waves are merged, on a single re-invocation — so it is the safe place to do the one authoritative report regeneration (parallel `--wave` sessions deliberately skipped the `.md` regen in Stage 12b step 4):

- **Multi-plan:** first ensure every wave's WI audit blocks are in the ledger (append-only re-harvest of any wave whose lines are missing — e.g. a wave that ran under `--wave` and only appended). Then **regenerate** `.forge/plans/<TICKET>/<TICKET>-test-report.md` from the full `.forge/plans/<TICKET>/<TICKET>-test-stats.jsonl`, **deduping on read**: collapse lines sharing `(wi_id, scope, test_type, repo, git_sha)` keeping the latest `captured_at`. This makes duplicate appends from re-runs/resumes harmless. Group by `test_type` for as-shipped totals, by `wave` for the breakdown, list gaps explicitly.
- **Single-plan:** the single-plan agent (Stage 10) ran `/forge-test-verify`, which wrote `.forge/plans/<TICKET>-test-verify.md` (sibling file — single-plan has no `<TICKET>/` folder). Append its stats block to the **sibling** ledger `.forge/plans/<TICKET>-test-stats.jsonl` with `scope: "single-plan"`, then regenerate `.forge/plans/<TICKET>-test-report.md` with the same dedup-on-read.

Commit both files to `feature/<TICKET>-plan` (folded into the Reflect commit in Step 3 is fine). If no audit files exist at all, write the report with an explicit "no test-stats captured" note rather than an empty table.

**Step 3 — Invoke Reflect.**

Invoke `forge-reflect <TICKET>`. The skill expects `phase: ship`. Runs the four Reflect questions, walks `<TICKET>-findings.md`, promotes lessons, applies framework changes, commits to `feature/<TICKET>-plan`, pushes. Flips tracker `phase: ship → done`.

**Step 4 — Append a `## Reflect` section to the plan PR description.**

Append a `## Reflect` block to the plan PR description summarizing the Reflect outcome (lessons promoted, framework changes).

**Step 5 — Print human handoff prompt:**

```
## /forge-deliver complete — <ticket> at phase: done (ship_unit: wave)

- Spec:     <SPEC_PATH> (approved)
- Decomposition Plan: <path> (approved) — for multi-plan
- Plan(s):  <plan path(s)> (approved)
- Spec PR:  <URL>  (base: main)
- Plan PR:  <URL>  (base: feature/<ticket>-spec — stacked; includes Reflect commit)
- Wave PRs:
    Wave 1:  <repo>: <URL> (MERGED)
    Wave 2:  <repo>: <URL> (MERGED)
    ...
    Wave <last>: <URL>(s) (MERGED)
- Reflect:  <N> lessons promoted, <M> scoped, framework changes: <list or "none">
- Test stats: <total tests> ran · <passed> passed · <failed> failed · <skipped> skipped
              (unit <u> · integration <i> · e2e <p>) — see <TICKET>-test-report.md
              <if any gaps: "⚠ <k> WI(s) with no/unparseable stats — see report">
- Tracker:  features.<ticket> → phase: done

Orchestrator work is done.

Re-running /forge-deliver <ticket> at phase: done is a no-op — prints this and exits.
```

If re-invoked at `phase: done`, print the status block and exit.

---

## Stage map

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ Stage  │ Skill / Action                     │ Tracker phase        │ Auto?       │
├────────┼────────────────────────────────────┼──────────────────────┼─────────────┤
│ 0      │ State-reconciliation preflight     │ — (heals tracker)    │ yes         │
│ 1      │ Argument parsing + mutual-exclusion │ —                   │ yes         │
│        │   guard + resume detection         │                      │             │
│ 2      │ Preflight + forge-spec-author      │ backlog → spec       │ yes*        │
│ 3      │ forge-spec-review                  │ spec → plan          │ CHECKPOINT  │
│ 4      │ forge-pr-open --artifact spec      │ — (notes: Spec PR #) │ yes         │
│ 5      │ /forge-wave-decompose              │ spec → plan/wi-dec.  │ CHECKPOINT  │
│ 6      │ forge-plan-review (Decomp Plan)    │ Decomp Plan approved │ CHECKPOINT  │
│        │ + plan-reviewer §11                │                      │             │
│        │ + parallelism wave check           │                      │             │
│ 7      │ PER-WAVE PIPELINE (multi-plan):    │ wi-decompose → dev   │ yes** /     │
│        │   Step 0:  forge-contract-author   │ (on Wave 1 dispatch) │ CHECKPOINT  │
│        │            (freeze seam contract — │                      │             │
│        │             auto-validated, NO gate)│                     │             │
│        │   Step 1:  forge-plan-author ×N    │                      │             │
│        │   Step 2:  cross-WI gate (+contract│                      │             │
│        │            conformance)            │                      │             │
│        │   Step 3:  per-WI review (CHKPT) + │                      │             │
│        │            dispatch sub-WIs (main) │                      │             │
│        │   Step 5a: await sub-WIs pr-open   │                      │             │
│        │   Step 5b: Pass 1 — sub integration│                      │             │
│        │   Step 5c: verify Phase 1          │                      │             │
│        │            (seam-test-implementer,  │                      │             │
│        │             API, no browser)       │                      │             │
│        │   Step 5d: await Phase 1 + D11     │                      │             │
│        │            auto-repair loop        │                      │             │
│        │   Step 5e: verify Phase 2 (browser)│                      │             │
│        │            + e2e (browser)         │                      │             │
│        │   Step 5f: await Phase 2 + e2e     │                      │             │
│        │   Step 5g: design vision pass      │                      │             │
│        │            (UI waves; L-022)       │                      │             │
│        │   Step 6:  Pass 2 + Stage 12 + 13  │                      │             │
│ 8      │ forge-plan-review (single-plan)    │ plan approved        │ CHECKPOINT  │
│ 9      │ forge-pr-open --artifact plan      │ — (notes: Plan PR #) │ yes         │
│        │ (multi-plan: opened early after    │                      │             │
│        │  Wave 1; later waves append)        │                      │             │
│ 10     │ forge-worktree-up (single-plan;    │ —                    │ yes         │
│        │  multi-plan provisioning is in 7)  │                      │             │
│ 11     │ Wave integration merge (TWO PASSES │ —                    │ yes***      │
│        │  per wave: Pass 1 = sub-WI         │                      │             │
│        │  integration after Step 5a; Pass 2 │                      │             │
│        │  = verify/e2e integration after    │                      │             │
│        │  Step 5f. Single-plan skips.)      │                      │             │
│ 12     │ forge-pr-open --artifact code      │ waves[N].status:      │ yes         │
│        │ --wave <N> (cross-repo wave PRs)   │ in-progress → pr-open│             │
│ 13     │ Halt for wave merge                │ —                    │ HUMAN       │
│ 14     │ Wave-merge-wait poll               │ waves[N].status:     │ yes         │
│        │ (re-invocation only)               │ pr-open → merged     │             │
│ 15     │ Verify all waves merged →          │ review → ship → done │ yes****     │
│        │ Reflect + flip to done             │                      │             │
│ —      │ /forge-review-pr <N> per wave PR   │ —                    │ HUMAN       │
│ —      │ Wave merge per wave PR             │ —                    │ HUMAN       │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Notes

- **Resumable always.** Re-running on any mid-flow ticket inspects tracker + disk + GitHub state. `--from` is the explicit override.
- **State reconciliation runs first (Stage 0).** Every invocation reconciles the three authoritative state stores — `tracker.yaml`, GitHub PR state, and pushed git branches — before deriving the entry stage. Ground truth is GitHub + git; the tracker is the derivative that heals (safe divergence, e.g. agent died after opening its PR but before flipping `impl_status`) or halts (ambiguous divergence, e.g. PR `CLOSED` not `MERGED`). This closes the silent failure mode where a stale tracker field caused re-dispatch onto a branch that already had commits and an open PR. Fails open if `gh`/`git`/`yq` are missing.
- **WAVE_BASE = main always.** Every wave branches from main after the previous wave's PR merges. No prior-wave integration branch in the base. Clean blast-radius: each wave is independently revertable.
- **Wave merge is a human checkpoint between waves.** Orchestrator halts on wave PR open. Re-invoke after merge.
- **No T-E2E integration PR.** The T-E2E WI is the final wave; its PR is a wave PR like any other.
- **Per-WI PRs auto-close on wave PR open.** Per-WI PRs are review surfaces during impl; the wave PR is the ship surface. Auto-close happens via `forge-pr-open --wave <N>` (Stage 12) and covers all per-WI PRs in the wave uniformly — sub, verify, and e2e.
- **Per-WI PR base differs by WI type (Option-A two-pass integration).** `type: sub` per-WI PRs base against `main`; `type: verify` and `type: e2e` per-WI PRs base against the wave branch `feature/<ticket>-wave-<N>` (post-Pass-1). This is because verify/e2e WIs need the integrated wave branch to exist before they can meaningfully test against it — their worktrees are provisioned from the wave branch in Stage 7 Step 5c (verify) / Step 5e (e2e), after Stage 11 Pass 1 creates it.
- **Contract-first integration (Stage 7 Step 0).** Each wave with a BE↔FE seam freezes a contract (`.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md`) via `forge-contract-author` **before** the parallel plan fan-out. The contract is the read-only seam authority both plan-authors and implementers conform to (D3) — it moves contract/shape drift (field names/casing, nullability, enums, envelope, auth handshake) left, out of the late `type: verify` halt. Auto-validated, **no human gate** (D5). The verify-WI's existence is the seam marker — contracts fire on exactly the seams `/forge-wave-decompose` flagged with a verify-WI.
- **Two-phase verify + the e2e split (D8) + sequencing.** A `type: verify` WI is a two-phase gate on one branch: **Phase 1** `seam-test-implementer` (authors API/contract-level seam tests, no browser; Step 5c) → the **orchestrator runs the API gate** (Step 5d) → on green → **Phase 2** `e2e-test-implementer` (authors wave-scoped browser e2e on the same branch; Step 5e, T3 only) → the **orchestrator runs the browser suite**. The cheap API gate fails fast before any expensive browser run. T2 verify-WIs are single-phase (seam-test-implementer only; a `finalize` dispatch opens its PR after the API gate is green); T3 verify-WIs open their single PR via a Phase-2 `finalize`. The final-wave `type: e2e` WI (full spec suite) is separate — also `e2e-test-implementer` (author), orchestrator-run, dispatched in Step 5e after the API gate passes. **Phase 2:** the agents author + static-check; the orchestrator runs every live tier (execution decoupling — see the **Dispatch invariants** section above).
- **Auto-repair loop (D11, Steps 5d/5e).** On a failure in the **orchestrator's own run** of the API gate (5d) or browser suite (5e), main classifies and routes: a **test bug** → the test specialist in `test-fix` mode; a **code bug** attributed by **file ownership** — offending files ∈ this wave's WIs' `## Files to Modify` ⇒ auto-fix via the owning implementer (no human, re-integrate, re-run, bounded N=2); ∉ (pre-existing/prior-wave code) ⇒ escalate to human (regression in old code). A `contract` defect ⇒ halt → re-decompose. Main never edits `src/` itself — it dispatches an implementer (consistent with conflict-resolution delegation). FR-10 is unaffected: the test specialists are test-only, no `sub → sub` within-wave dep is introduced.
- **Design vision pass (Step 5g, L-022).** For UI waves with a design reference, the orchestrator screenshots each new/changed route on the wave branch and compares to the design-of-record before opening the wave PR. Material drift from a named token/layout/affordance an observable visual AC requires routes to `frontend-implementer` (in-wave defect, D11-style, N=2) or escalates (spec/prototype ambiguity). Skipped when the wave ships no UI or the project has no design reference.
- **Plan-shaping overlaps implementation.** Wave N+1's plans can be authored/reviewed while wave N implements. Only impl **dispatch** waits on wave N's PR merge.
- **No merge required to start impl (FR-7.f).** Impl agent reads spec/plans from the harness's working tree on `feature/<ticket>-plan`. None of these need to be merged to main for impl to proceed — approval is the only gate.
- **Wave integration runs in main app repo checkout (FR-7.g) — two passes per wave.** Pass 1 (early, after sub-WIs at pr-open) creates the wave branch and merges sub-WIs in. Pass 2 (late, after verify/e2e WIs at pr-open) merges verify/e2e branches into the same wave branch. Both passes run from the main app checkout, NOT from any worktree. WI worktrees are cleaned per-pass — sub worktrees after Pass 1, verify/e2e worktrees after Pass 2.
- **`--wave <N>` enables manual parallel waves (FR-7.d).** Two terminals running `/forge-deliver TICKET --wave 3` and `--wave 4` simultaneously drive their waves through to PR-open halts independently. Soft dep-check (FR-7.e) prompts when deps not yet merged.
- **Phase-transition guard (FR-7.h).** Re-read tracker before any phase flip; skip if target state already set by a concurrent session. Monotonicity (`merged` and `done` terminal) makes last-writer-wins safe.
- **Cross-repo wave PR semantics (FR-7.b).** A wave touching R repos opens R wave PRs (one per repo, same branch name in each). Wave is `pr-open` from the moment the first PR opens; flips to `merged` only when all R have state `MERGED`.
- **Mutual exclusion.** Stage 1 refuses on `ship_unit: feature` features — this harness orchestrates wave mode only.
- **Plan-reviewer §11 fires automatically on Decomposition Plans and single-plan wave-mode plans.** The agent is shape-agnostic for §1–§10; §11 is gated on `ship_unit: wave`.
- **One feature at a time per ticket (except via `--wave <N>`).** Two parallel `/forge-deliver TICKET` invocations without `--wave` would race. `--wave <N>` partitions the work safely (different waves don't race on the same tracker keys except phase flips, which are guarded).
- **Tracker writes must be serialized under a lock (concurrency convention).** Under parallel `--wave <N>` sessions, the per-WI `impl_status` / `pr_number` flips and `waves[N].status` flips are written by the delegated skills (`forge-pr-open`, `forge-worktree-up`), each a read-modify-write (`yq -i`) on the **shared** `.forge/tracker.yaml`. Two writers touching the same file can clobber each other (and both touch the shared `last_updated` scalar). **Every tracker mutation must run inside a `flock` critical section** on a lockfile (`.forge/.tracker.lock`), bounded by `flock -w <timeout>`, **failing open with a warning if `flock` is unavailable** (macOS lacks it by default — same fail-open posture as every harness hook). This orchestrator emits **no inline `yq -i`** itself (all structural writes are delegated — see the last note below), so the substantive lock lives in the writer skills; this bullet is the convention they conform to, cross-referenced in `.claude/rules/tracker.md`. `merged`/`done` are terminal, so their flips remain last-writer-wins-safe even under the lock.
- **Stacked PRs at the spec/plan layer; flat at the code layer.** Spec PR → main. Plan PR → spec branch (stacked, auto-retargets). Wave PRs → main directly. No T-E2E integration PR. Wave PRs ship the whole feature wave-by-wave.
- **Reflect runs at Stage 15.** Lessons land on the plan branch alongside the Reflect commit.
- **Test-stats ledger (Stage 12b + Stage 15 Step 2b).** `/forge-test-verify` parses test counts from each WI's run and writes a `forge-test-stats/v1` block into its per-WI audit file (producer) — distinct filename per WI, so parallel impl agents never collide. The orchestrator harvests those blocks into `.forge/plans/<ticket>/<ticket>-test-stats.jsonl` (consumer). Counts group by `test_type` (unit/integration/e2e — matching the `forge-test-stats/v1` enum) for as-shipped totals and by `wave` for the breakdown. Single-plan features use sibling files (`.forge/plans/<ticket>-test-stats.jsonl`/`-test-report.md`). Gaps (no audit / unparseable counts) are recorded explicitly — never a fabricated zero.
- **Test-stats ledger is parallel-wave-safe (FR-7.d).** The ledger is written **append-only** (line-atomic; never read-modify-write), and idempotency is **dedup-on-read** on `(wi_id, scope, test_type, repo, git_sha)` — re-runs/resumes append duplicates that collapse when the report is built. The human `<ticket>-test-report.md` is regenerated by a **single writer**: in the default sequential flow, per wave at Stage 12b; under parallel `--wave <N>`, Stage 12b skips the `.md` regen and Stage 15 (the one terminal single-session rollup) does it once. This preserves the "different waves don't race on shared files" invariant the rest of the orchestrator already holds.
- **The orchestrator writes nothing structural itself.** All state mutations are via delegated skills/commands.
- **Doctrine.** the wave-mode workflow is described in `.forge/forge-harness-framework.md`.
