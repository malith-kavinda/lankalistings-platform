---
name: forge-pr-open
phases: [engineering]
description: "Open the PR for a Forge artifact — spec, plan, or implementation code (including wave-mode wave PRs). Use when a spec or plan has just been approved, or an implementation worktree has passed `/forge-pre-pr-review` and is ready to push. Invoked as `/forge-pr-open`; mode auto-detects from the branch."
---

# /forge-pr-open

Open the PR for one artifact of a feature: the spec, the plan(s), or the implementation code. Wraps `gh pr create` with the Forge-standard PR body — including a verification checklist whose pre-ticked items prove the artifact passed each automated gate.

> **Non-dispatch guardrail (load-bearing).** This skill runs **inline / non-dispatching**. In wave/feature mode it is invoked by an implementer agent (`backend-implementer` / `frontend-implementer`) in the **finalize** path, after that agent has run its gates. Claude Code forbids recursive sub-agent dispatch, so this skill **must never dispatch a sub-agent** — every step here runs in the calling context. (Same constraint applies to `forge-test-verify` and `forge-pre-pr-review`, the sibling finalize-path skills.) If a step seems to want a sensor sub-agent, do it inline instead.

> **GitHub org is read from the tracker.** All `gh ... --repo <owner>/<repo>` commands below use `<github-org>` as a placeholder. At runtime, read `github_org` from `.forge/tracker.yaml` (top-level field) and substitute it. Never hardcode an org name. If `github_org` is empty, abort with: *"`.forge/tracker.yaml github_org` is unset — set the GitHub org before opening cross-repo PRs."*

## How to Use

```
# Harness session (spec / plan PRs)
/forge-pr-open <ticket> --artifact spec
/forge-pr-open <ticket> --artifact plan

# App-repo worktree session (per-WI / single-plan code PRs)
/forge-pr-open                       # auto-detect ticket + WI from branch name
/forge-pr-open <ticket>              # explicit ticket
/forge-pr-open <ticket> <wi-id>      # explicit WI

# Harness session (wave-mode wave PRs — wave-as-ship-unit, FR-8 / FR-14)
/forge-pr-open <ticket> --artifact code --wave <N>
```

If `--artifact` is omitted, the skill infers: `spec` or `plan` when invoked from inside the harness repo (based on which artifact branch is checked out), `code` when invoked from inside an app-repo worktree. `--wave <N>` only valid with `--artifact code`, and only for features at `ship_unit: wave`.

`<ticket>` examples below use a `PROJ-NNN` form (e.g. `PROJ-002`); substitute your project's real ticket prefix. The branch / WI-id **grammar** (`feature/<ticket>-spec`, `feature/<ticket>-WI-<wave>.<index>-<slug>`, `feature/<ticket>-wave-<N>`) is fixed — only the ticket prefix in the examples changes.

## When to Use

- **`--artifact spec`** — `/forge-spec-review` has just flipped the spec to `Status: approved`. Harness has uncommitted changes to `.forge/specs/<ticket>-*-spec.md`, optionally `<ticket>-findings.md`, `.forge/tracker.yaml`, `.forge/features.md`.
- **`--artifact plan`** — All plan files are at `Status: approved` (single plan, or Key WI + every sub-WI for decomposed features). Harness has uncommitted plan changes plus tracker updates.
- **`--artifact code`** — `/forge-pre-pr-review` has just produced `Ready to push` or `Nits only`. Plan's `## Progress` is fully checked. All implementation commits are local.

## When NOT to Use

- The artifact's review hasn't passed — abort on missing approval markers.
- An open PR already exists for this artifact — idempotent; print existing URL and exit 0.
- Wrong session location (`--artifact code` from harness, `--artifact spec/plan` from a worktree).

## Process — `--artifact spec`

### 1. Validate

- Confirm running inside the harness repo (`<harness-repo>` — path ends in `/<harness-repo>`).
- Confirm `.forge/specs/<TICKET>-*-spec.md` exists and contains `Status: approved` and `Reviewed-via: /forge-spec-review`.
- Read `.forge/tracker.yaml` `features.<TICKET>`. Confirm `phase` is `plan` (i.e. spec approval already moved phase forward) or `spec` with spec `Status: approved`.

### 2. Branch setup

Branch name: `feature/<TICKET>-spec`.

```bash
EXISTING_BRANCH=$(git branch --show-current)
if [ "$EXISTING_BRANCH" = "feature/<TICKET>-spec" ]; then
  : # already on it, continue
elif git show-ref --verify --quiet "refs/heads/feature/<TICKET>-spec"; then
  git checkout feature/<TICKET>-spec
else
  # branch from current HEAD (must be main and clean of unrelated diffs)
  git checkout -b feature/<TICKET>-spec
fi
```

If current HEAD is not on `main` and the branch doesn't exist: abort — *"Harness HEAD is on `<branch>`; expected `main` to branch from. Switch and re-run."*

### 3. Detect & stage spec-scoped changes

Stage **only** these paths if they have uncommitted changes:

- `.forge/specs/<TICKET>-*-spec.md`
- `.forge/specs/<TICKET>-*-findings.md` (if exists)
- `.forge/tracker.yaml` (only the `features.<TICKET>` entry's diff — verify via `git diff`)
- `.forge/features.md` (if regenerated)

Refuse to stage anything outside this list. If working tree has unrelated changes, abort: *"Working tree has changes outside spec scope: `<files>`. Commit or stash first."*

### 4. Commit

```bash
git commit -m "$(cat <<'EOF'
feat: <ticket> <feature-title> spec

Spec approved via /forge-spec-review (Pass 2 clean).
Tracker advanced to phase: plan.

Refs: <TICKET>

🤖 Opened via /forge-pr-open --artifact spec
EOF
)"
```

### 5. Check for existing PR; push

```bash
git push -u origin "feature/<TICKET>-spec"
EXISTING_PR=$(gh pr view --json url,number,state 2>/dev/null)
```

If an `OPEN` PR exists on this branch: print URL and exit 0. If `CLOSED`/`MERGED`: abort — spec already shipped, no new PR.

### 6. Open PR

**Title** — `feat: <ticket> <feature-title> spec` (under 70 chars).

**Body** (HEREDOC):

```markdown
## Summary

Spec for <ticket> — <feature-title>. Drafted via `/forge-spec-author`, reviewed via `/forge-spec-review` (Pass 2 clean).

- Spec: `.forge/specs/<ticket>-*-spec.md`
- Findings: `.forge/specs/<ticket>-*-findings.md` (if exists)
- Tracker: `features.<ticket>` → phase: plan, spec Status: approved

## Scope

<one-paragraph scope summary pulled from the spec's ## Context>

## Verification

- [x] Spec template sections present (Context, Requirements, Acceptance Criteria, Scope Boundaries, Constraints & Dependencies, Open Questions, Input Sources)
- [x] `/forge-gap-check` run — <N> Blockers resolved, <M> Warnings noted (from `## Open Questions`)
- [x] `/forge-spec-review` Pass 2 clean — 0 Blockers, 0 Importants, <K> Nits (header annotation `Reviewed-via: /forge-spec-review`)
- [x] Tracker updated — `features.<ticket>` phase advanced, `spec` path set, `last_updated` bumped
- [ ] Peer review on GitHub

## What's next

After this PR merges, the next `/forge-deliver <ticket>` invocation continues with workitem decomposition. The plan PR will stack on this branch (`feature/<ticket>-plan` → base: `feature/<ticket>-spec`).

Refs: <ticket>

🤖 Opened via /forge-pr-open --artifact spec
```

```bash
gh pr create \
  --title "<TITLE>" \
  --body "$(cat <<'EOF'
<BODY>
EOF
)" \
  --base main
```

Capture PR number + URL.

### 7. Tracker update

Append to `features.<TICKET>.notes`: *"Spec PR #<N> opened (<URL>). Base: main."*

Bump global `last_updated`.

### 8. Final report

```
## Spec PR opened — <ticket>

- Branch:  feature/<ticket>-spec
- PR:      <URL>
- Base:    main
- Tracker: features.<ticket> notes updated

The plan PR (next stage) will branch from feature/<ticket>-spec and
target it as base, so its diff stays plan-only until the spec PR merges.

Next: /forge-deliver <ticket>  (continues to workitem decomposition)
```

---

## Process — `--artifact plan`

### 1. Validate

- Confirm running inside the harness repo (`<harness-repo>`).
- Detect `ship_unit` (engagement default at `delivery.ship_unit`, overridden by per-feature `features[<TICKET>].ship_unit`).
- Confirm plan approval state — schema differs by mode:
  - **Single-plan (any mode):** `.forge/plans/<ticket>-*-plan.md` at `Status: approved` with `Reviewed-via: /forge-plan-review`.
  - **Decomposed, `ship_unit: feature` (legacy):** every entry in tracker `features.<TICKET>.workitems[]` at `plan_status: approved`; every plan file under `.forge/plans/<ticket>/` at `Status: approved`. The Key Workitem at `.forge/plans/<TICKET>/<TICKET>-WI-1.1-plan.md` is the orchestration artifact.
  - **Decomposed, `ship_unit: wave`:** tracker `features.<TICKET>.decomposition_plan.status: approved`; every entry in `features.<TICKET>.waves[].workitems[]` at `plan_status: approved`; every plan file under `.forge/plans/<ticket>/` (including `<TICKET>-decomposition-plan.md`) at `Status: approved`. The Decomposition Plan is the orchestration artifact.

  In the decomposed cases, in wave mode the orchestrator may invoke `--artifact plan` **incrementally** (Wave 1's plans first, later waves appending) — so "every WI at approved" applies to whichever waves' plans the orchestrator has gathered for this commit. The branch-based idempotency check in step 5 handles the multi-push case.
- Confirm `feature/<TICKET>-spec` branch exists locally (the spec PR's branch — base for stacking).

### 2. Branch setup

Branch name: `feature/<TICKET>-plan`. Base: `feature/<TICKET>-spec`.

```bash
EXISTING_BRANCH=$(git branch --show-current)
if [ "$EXISTING_BRANCH" = "feature/<TICKET>-plan" ]; then
  : # continue
elif git show-ref --verify --quiet "refs/heads/feature/<TICKET>-plan"; then
  git checkout feature/<TICKET>-plan
else
  git checkout feature/<TICKET>-spec
  git checkout -b feature/<TICKET>-plan
fi
```

If `feature/<TICKET>-spec` doesn't exist locally: abort — *"Spec branch missing. Run `/forge-pr-open <ticket> --artifact spec` first."*

### 3. Detect & stage plan-scoped changes

Stage **only** these paths:

- `.forge/plans/<ticket>-*-plan.md` (single-plan), OR
- `.forge/plans/<ticket>/` directory entirely (decomposed: Key WI + sub-WIs)
- `.forge/tracker.yaml` (only `features.<TICKET>` diffs)
- `.forge/features.md` (if updated)

Same refuse-on-out-of-scope rule as spec mode.

### 4. Commit

```bash
git commit -m "$(cat <<'EOF'
feat: <ticket> <feature-title> plan

<Single-plan:>
Plan approved via /forge-plan-review (single-pass, clean).
<Decomposed, ship_unit: feature (legacy):>
Decomposition: <N> workitems across <W> waves.
Key Workitem approved (human-reviewed); <N-1> sub-WI plans
approved via /forge-plan-review (single-pass, clean each).
<Decomposed, ship_unit: wave:>
Decomposition Plan approved (human-reviewed) — <N> WIs across <W> waves
(includes Wave Ship Plan declaring ship_type per wave). <N> sub-WI plans
approved via /forge-plan-review (single-pass, clean each).

Tracker advanced to phase: plan with full plan inventory.

Refs: <TICKET>

🤖 Opened via /forge-pr-open --artifact plan
EOF
)"
```

### 5. Push + check for existing PR

```bash
git push -u origin "feature/<TICKET>-plan"
EXISTING_PR=$(gh pr view --json url,number,state 2>/dev/null)
```

If an `OPEN` PR exists on this branch: print URL and exit 0 (idempotent). If `CLOSED`/`MERGED`: abort — plan already shipped, no new PR needed on this branch.

### 6. Open PR

**Title** — `feat: <ticket> <feature-title> plan` (under 70 chars).

**Body**:

```markdown
## Summary

<Single-plan:>
Implementation plan for <ticket> — <feature-title>. Drafted via `/forge-plan-author`, reviewed via `/forge-plan-review` (single-pass, clean).
<Decomposed:>
Decomposition for <ticket> — <feature-title>. <N> workitems across <W> waves.

- Plan(s): <plan path(s)>
- Spec:    `.forge/specs/<ticket>-*-spec.md` (PR #<spec-pr-number> — stacked base)
- Tracker: `features.<ticket>` → phase: plan, plan path(s) set

## Decomposition (decomposed only)

| WI | Wave | Title | Status |
|----|------|-------|--------|
<one row per WI — read from `features.<TICKET>.workitems[]` (feature mode) OR `features.<TICKET>.waves[].workitems[]` (wave mode); first match wins per the shape-agnostic lookup>

<wave mode only — also include the Wave Ship Plan table from the Decomposition Plan:>

### Wave Ship Plan

| Wave | Depends on | ship_type | Ship state on main | Verification |
|------|------------|-----------|--------------------|--------------|
<one row per wave — read from the Decomposition Plan's `## Wave Ship Plan` table>

## Verification

- [x] Plan template sections present (Approach, Decisions, Subtasks, Files to Modify, Risks, Progress, Notes)
- [x] Every Decision cites a repo file:line or a CLAUDE.md / architecture.md rule
- [x] Mandatory final subtasks present (Pre-PR review + PR opened) per CLAUDE.md plan-discipline rule
- [x] Files-to-Modify table populated (used by `/forge-worktree-up` to determine touched repos)
<Decomposed, ship_unit: feature (legacy) only:>
- [x] Key Workitem approved — always human-reviewed (no `--auto-approve-on-clean`)
- [x] All <N-1> sub-WI plans approved via `/forge-plan-review` (single-pass, clean each)
- [x] No same-wave cross-WI file collisions in Files-to-Modify
- [x] Contract shapes locked by each owning WI's plan; consumers read from upstream plans
<Decomposed, ship_unit: wave only:>
- [x] Decomposition Plan approved — always human-reviewed; plan-reviewer §11 (WS-1..WS-5) audit passed
- [x] All <N> sub-WI plans approved via `/forge-plan-review` (single-pass, clean each)
- [x] No same-wave cross-WI file collisions in Files-to-Modify
- [x] Contract shapes locked by each owning WI's plan; consumers read from upstream plans
- [x] Wave Ship Plan declares ship_type per wave; vertical waves satisfy FR-2 C1–C4; monolithic waves carry legitimate reasons
<Single-plan only:>
- [x] `/forge-plan-review` single-pass clean — 0 Blockers, 0 Importants, <K> Nits
- [x] Tracker updated — `features.<ticket>` plan path set, Status: approved
- [ ] Peer review on GitHub

## Stacking

Base branch: `feature/<ticket>-spec` (spec PR #<spec-pr-number>).
GitHub auto-retargets this PR to `main` when the spec PR merges.

## What's next

After this PR merges, `/forge-deliver <ticket>` provisions worktree(s) via `/forge-worktree-up` and dispatches the implementation Agent. Code PR(s) will open against `main` from the app repos (one per touched repo per unit).

Refs: <ticket>

🤖 Opened via /forge-pr-open --artifact plan
```

```bash
gh pr create \
  --title "<TITLE>" \
  --body "<BODY>" \
  --base "feature/<TICKET>-spec"
```

### 7. Tracker update

Append to `features.<TICKET>.notes`: *"Plan PR #<N> opened (<URL>). Base: feature/<ticket>-spec (stacked)."*

Bump global `last_updated`.

### 8. Final report

```
## Plan PR opened — <ticket>

- Branch:  feature/<ticket>-plan
- PR:      <URL>
- Base:    feature/<ticket>-spec (stacked; auto-retargets to main on spec merge)
- Tracker: features.<ticket> notes updated

Next: /forge-deliver <ticket>  (provisions worktrees + dispatches impl Agent)
```

---

## Process — `--artifact code` (default)

### 1. Locate context

```bash
BRANCH=$(git branch --show-current)
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
```

**Derive TICKET and WI_ID from branch name:**

- `feature/<TICKET>-<slug>` (no `WI-N.M`) → single-plan mode; `WI_ID` empty.
- `feature/<TICKET>-WI-<wave>.<index>-<slug>` → WI mode; `WI_ID = <TICKET>-WI-<wave>.<index>`.

If the branch doesn't match either pattern, ask the human to confirm TICKET (and WI_ID if relevant) before continuing.

Locate the harness: walk up from `worktrees/<ticket>[/<wi-id>]/<repo>` to the workspace parent, then to the `<harness-repo>` sibling. Abort if missing.

### 2. Validate readiness

Read the plan from the harness:
- Single-plan: `<harness>/.forge/plans/<TICKET>-*-plan.md`
- WI mode: `<harness>/.forge/plans/<TICKET>/<WI_ID>-plan.md`

Confirm:
- `> Status: approved` in header.
- `## Notes` contains a `/forge-pre-pr-review` verdict (`## Pre-PR Review — <ticket or wi-id>` heading present). If not found, abort.
- Verdict resolves to `Ready to push` or `Nits only — your call`. If `Fix Blockers first`, abort.

**Determine PR base (WI mode only — stacked-PR model):**

Read tracker `features.<TICKET>.workitems[<WI_ID>]`:
- `type`: `sub` or `e2e`.
- `base_branch`: set by `forge-worktree-up` when the worktree was provisioned. This is the literal base for the PR — **unless** the WI is `type: e2e`, in which case the PR is the **integration PR** and base = `main` regardless of what `base_branch` says.

So:
- T-E2E WI (`type: e2e`) → PR base = `main`. This single PR's diff is the whole feature (T-E2E branch transitively contains every prior WI's code via the stacking chain). This PR is what humans merge to ship.
- First WI in chain (`base_branch: main`) → PR base = `main`. Per-WI review-only PR.
- Subsequent functional WIs → PR base = `base_branch` (the previous WI's branch). Per-WI review-only PR; diff is just this WI's commits.

> **L-027 (same-repo vs cross-repo base):** Same-repo compile-coupled WIs **stack** — the consumer WI bases off the owner WI's branch (or off the wave branch once integrated) so the consumer compiles against the producer's code. Cross-repo seam WIs (e.g. a backend WI and a frontend WI that only meet at an API contract, no shared compile unit) branch **parallel-from-`main`** — they don't compile-couple, so stacking would only create false sequencing. `forge-worktree-up` writes `base_branch` per this rule; this step honors it.

Single-plan mode: PR base is always `main`.

### 3. Check for an existing PR

```bash
gh pr view --json url,number,state 2>/dev/null
```

If a PR exists on this branch and is `OPEN`: print the existing URL and exit 0 (idempotent). If `CLOSED` or `MERGED`, abort: *"Branch already has a closed/merged PR. New work needs a new branch."*

### 4. Extract verification evidence from plan ## Notes

Look in the plan's `## Notes` for these blocks (written by `/forge-pre-pr-review`):

- Lint output: command + exit status + violation count
- Tests output: command + pass/fail counts
- Build output: command + status
- Pre-PR verdict block

Pre-tick the verification list items that have evidence; leave unproven items unchecked.

### 5. Assemble PR title and body

**Title** — format `<type>: <description>` per `.claude/rules/git-conventions.md`, under 70 chars.

*WI mode*: include the WI reference — `feat: PROJ-002-WI-2.1 — <short title>`.

**Body**:

```markdown
## Summary

<2–4 bullets from the plan's ## Approach section>

## Spec & Plan

- Spec: `.forge/specs/<TICKET>-*-spec.md` (Status: approved, shipped via spec PR)
- Plan: <plan path> (Status: approved, shipped via plan PR)
<WI mode only:>
- Key Workitem: `.forge/plans/<TICKET>/<TICKET>-WI-1.1-plan.md` (Status: approved)
- WI scope: <scope summary from Key Workitem inventory>
- Tier: <T1 | T2 | T3 | T-E2E> (from Key Workitem ## Test Strategy Map)
- ACs on hook: <AC-IDs from Key Workitem coverage table>
- PRD section: <PRD section title from the spec's ## Context>

<WI mode, NOT T-E2E:>
## Stacking (review-only PR)

- Base: `<base_branch>` (previous WI's branch, or `main` if this is the first in the chain)
- This PR is for **review of just this WI's changes**. The integration PR (T-E2E WI's PR to `main`) is what actually ships the feature — merging this PR is optional; its commits will land in `main` when the integration PR merges.
- GitHub will auto-retarget this PR's base to `main` if the parent PR merges first.

<WI mode, T-E2E only:>
## Integration PR — full feature

- Base: `main`
- This branch transitively contains every prior WI's code via the stacking chain, plus this WI's full browser E2E suite (the project's E2E framework — read the repo's Stack Profile).
- **This is the merge-to-main PR for the feature.** Full E2E gates merge here.
- Per-WI review-only PRs (`<list sibling WI PR numbers>`) cover the per-WI diffs separately.

## What changed

<bullets from the plan's ## Progress section — subtasks marked done>

## Plan deviations

<list deviations recorded in plan ## Notes; "None" if plan was followed exactly>

## Verification

- [x] Lint passes — `<lint command>` (<violation count or "0 violations">, run <date>)
- [x] Tests pass — `<test command>` (<pass/fail counts>)
- [x] Build passes — `<build command>` (where applicable)
- [x] `/forge-pre-pr-review` verdict: `<Ready to push | Nits only — your call>` (full block in plan ## Notes)
- [x] Plan `## Progress`: all subtasks marked done
<WI mode, T-E2E only:>
- [x] Full E2E suite passes locally (`<e2e command — read the repo's Stack Profile>`) — <N passed / M total>
- [ ] CI green on PR (full E2E re-run)
<other:>
- [ ] CI green on PR
- [ ] <feature-specific manual verification step from plan>

## Companion PR

<if backend PR, link frontend companion (if any) and vice versa.
For WI mode: also link sibling WI PRs that are already open.
"Standalone — single-repo" if not paired.>

Refs: <TICKET>

🤖 Opened via /forge-pr-open --artifact code
```

### 6. Push the branch + open the PR

```bash
git push -u origin "$BRANCH"
# PR_BASE was determined in step 2 (main, previous WI branch, or main for T-E2E integration PR).
gh pr create --title "<TITLE>" --body "<BODY>" --base "$PR_BASE"
```

Capture the PR number and URL.

### 7. Update the harness tracker

> **Serialize this write under `flock`.** When parallel `/forge-deliver --wave <N>` sessions run, several per-WI `/forge-pr-open` invocations race to read-modify-write the same `tracker.yaml`. Wrap the `yq -i` mutations + `last_updated` bump in this step in a `flock` critical section on `<harness>/.forge/.tracker.lock` (bounded `-w` timeout; **fail open with a warning if `flock` is absent**, matching the harness hook posture). Two writers otherwise clobber each other and the shared `last_updated`. See `.claude/rules/tracker.md` → "Serialize concurrent writes under a lock". Terminal `impl_status` flips are last-writer-wins-safe.

**Single-plan mode:**
- `phase: dev` → `phase: review`
- Append to `notes`: *"Code PR #<N> opened in `<repo>` (<URL>). Awaiting CI + human merge."*

**WI mode (review-PR WIs — `type: sub` and `type: verify`):**
- `workitems[<wi-id>].pr_number = <N>`, `workitems[<wi-id>].pr_url = <URL>`, `workitems[<wi-id>].pr_role = "review"`.
- Append to feature `notes`: *"WI <wi-id> review PR #<N> opened in `<repo>` (<URL>). Base: `<base_branch>`."*
- Leave `phase: dev` — no per-WI review PR flips phase. (Feature mode: only the T-E2E integration PR flips it, below. Wave mode: `/forge-deliver` Stage 15 flips it after the final wave merges.)

**WI mode (T-E2E WI, `type: e2e`):**
- `workitems[<wi-id>].pr_number = <N>`, `workitems[<wi-id>].pr_url = <URL>`, `workitems[<wi-id>].pr_role = "integration"`.
- Append to feature `notes`: *"Integration PR #<N> opened in `<repo>` (<URL>) — T-E2E WI <wi-id>. Base: main. E2E gates merge."*
- **Feature mode (`ship_unit: feature`) only:** flip `phase: dev → review` for this repo's portion. If the feature touches multiple repos, only flip when every touched repo has an integration PR open. **Wave mode (`ship_unit: wave`): do NOT flip phase here** — the e2e WI is the final wave's per-WI review surface (auto-closed by the wave PR); `/forge-deliver` Stage 15 owns the phase flip after the wave PR merges.

**WI mode — flip `impl_status` (ALL WI types: `sub`, `verify`, `e2e`):**
- `workitems[<wi-id>].impl_status: dispatched → pr-open` (via `yq -i`). **This is the transition `/forge-deliver` Stage 7 Step 5a/5d waits on** at the "await all WIs at `impl_status: pr-open`" barrier — without this write the wave never integrates and the wave PR never opens (deadlock). The PR-opener owns this write because it is the actor that just opened the per-WI PR; no other actor writes `dispatched → pr-open`.

Bump the global `last_updated`.

**Commit the harness state (sweeps up agent's accumulated `.forge/` writes).**

Throughout the impl session, the agent has been writing to `<HARNESS>/.forge/plans/.../<WI_ID>-plan.md` (## Progress, ## Notes) via absolute paths from the worktree. This skill just wrote `workitems[<wi-id>].*` fields and the `notes` line into `<HARNESS>/.forge/tracker.yaml`. None of those harness-side writes have been committed yet — they accumulate as uncommitted diff in the harness checkout, detached from any session that would normally commit them. Without this step, the harness branch drifts silently from PR state: the tracker says "still working" while GitHub shows the PR open, and the plan's ## Progress doesn't reflect what actually shipped.

Sweep them up now so the harness branch matches reality:

```bash
cd "$HARNESS"
# .forge/ scope ONLY — never touch .claude/** from a worktree-dispatched skill invocation.
git add .forge/
if ! git diff --cached --quiet; then
  git commit -m "chore(<TICKET>): <WI_ID> impl_status → pr-open

- Plan ## Progress / ## Notes updates from impl subtasks
- tracker.yaml workitems[<WI_ID>] PR fields populated
- Code PR: <URL> (base: <PR_BASE>)
"
fi
# Do NOT push from the skill — harness pushes happen at orchestrator stage
# boundaries (e.g. /forge-deliver Stage 9 plan PR open). The local commit
# is sufficient; the next orchestrator invocation pushes if needed.
```

If the staged diff is empty (rare — e.g. re-running `/forge-pr-open` after a manual cleanup), skip the commit silently.

### 8. Final report

```
## Code PR opened — <ticket or wi-id>

- Branch:  <branch>
- Repo:    <repo>
- PR:      <URL> (base: <PR_BASE>)
- Role:    <review-only | integration (T-E2E)>
<WI mode:>
- WI:      <wi-id> (wave <N>, tier <tier>)
- Tracker: workitems[<wi-id>].pr_* updated; phase: <current phase>
  (phase flips to review once the T-E2E WI's integration PR is open)

Next steps (conservative auto-flow):
  1. /forge-review-pr <N>    — framework-aware second-opinion review
  2. CI runs; address failures from inside this worktree
                              (E2E failures get fixed on the T-E2E WI branch)
  3. Human merges integration PR via GitHub UI once review approves + E2E green
  4. Post-PR-open: orchestrator runs /forge-reflect <ticket> at Stage 8
```

---

## Process — `--artifact code --wave <N>` (wave-mode wave PRs)

**Wave-mode only.** Refuse if `delivery.ship_unit != wave` AND the feature has no `ship_unit: wave` override. Steer to legacy `--artifact code` (per-WI / single-plan PRs) in that case.

This mode opens the **wave PR(s)** — one per touched repo — after wave integration has merged every WI in the wave into `feature/<ticket>-wave-<N>` in each touched main app repo (see `/forge-deliver` Stage 11 — two-pass wave integration). The wave PR is the actual ship surface; the per-WI PRs are review surfaces that this mode auto-closes.

### 1. Validate

- Confirm running inside the harness repo (`<harness-repo>`) — not in a worktree. Wave integration is in main app repos, but `--wave` is dispatched from the harness.
- Read `.forge/tracker.yaml` `features.<TICKET>`:
  - `ship_unit` is `wave` (engagement or feature override).
  - `waves[<N>]` exists.
  - `waves[<N>].status` is `in-progress` (set by Stage 7 Step 3 when its first sub-WI dispatched). Already `pr-open` → idempotent re-entry; skip to step 5.
  - Every `waves[<N>].workitems[*].impl_status` is `pr-open`. (Stage 11 — two-pass wave integration merge — does not mutate `impl_status`; the per-WI `dispatched → pr-open` flip is written by each WI's own `/forge-pr-open` run, and the `pr-open → wave-closed` flip happens here in step 5 once the wave PR opens.) If any are `pending`, `dispatched`, or missing, abort: *"Wave `<N>` has WI(s) at unexpected impl_status — wave integration may not have completed. Re-run `/forge-deliver <TICKET>`."*
- Read the Decomposition Plan at `.forge/plans/<TICKET>/<TICKET>-decomposition-plan.md`. Locate the wave's row in the `## Wave Ship Plan` table. Extract: `ship_type`, `Ship state on main`, `Verification`, checklist marks, `Monolithic reason`.

### 2. Compute touched repos

```bash
TOUCHED_REPOS=$(yq ".features[] | select(.id == \"$TICKET\") | .waves[] | select(.wave == $N) | .workitems[].touched_repos[]" .forge/tracker.yaml | sort -u)
```

Union of every WI's `touched_repos` for this wave. Each becomes one wave PR.

### 3. For each touched repo: pre-check + open PR (idempotent)

Read `GITHUB_ORG` from `.forge/tracker.yaml` `github_org` once before the loop. For each repo in `TOUCHED_REPOS`:

```bash
GITHUB_ORG=$(yq '.github_org' .forge/tracker.yaml)
WAVE_BRANCH="feature/<TICKET>-wave-<N>"

# Verify the wave branch exists on remote (Stage 11 Pass 1 should have pushed it).
git -C "$REPO_PATH" fetch origin "$WAVE_BRANCH" 2>/dev/null || {
  echo "Wave branch $WAVE_BRANCH not on remote in $REPO_NAME. Run wave integration first."
  exit 1
}

# Pre-check — is a wave PR already open?
OPEN_WAVE_PR=$(gh pr list --repo $GITHUB_ORG/$REPO_NAME --head "$WAVE_BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$OPEN_WAVE_PR" ]; then
  echo "Wave PR already open in $REPO_NAME: #$OPEN_WAVE_PR — skipping."
  continue
fi

# Compose PR body (see step 4) and open.
gh pr create \
  --repo $GITHUB_ORG/$REPO_NAME \
  --head "$WAVE_BRANCH" \
  --base main \
  --title "<TICKET> wave <N> — <ship state one-liner>" \
  --body "$(compose_wave_pr_body $REPO_NAME)"
```

`<github-org>` in the `gh --repo <github-org>/<repo>` form is the `$GITHUB_ORG` value above — the tracker's `github_org`. Never hardcode it.

### 4. Wave PR body shape

```markdown
# <TICKET> — Wave <N>: <Ship state one-liner from Decomposition Plan>

## Wave Ship Plan (from Decomposition Plan)

| Wave | Depends on waves | ship_type | Ship state on main | Verification | C1 | C2 | C3 | C4 | Monolithic reason |
|------|------------------|-----------|--------------------|--------------|----|----|----|----|-------------------|
| <N>  | <deps>           | <type>    | <ship state>       | <verif>      | <✓/✗> | <✓/✗> | <✓/✗> | <✓/✗> | <reason or —> |

Source: `.forge/plans/<TICKET>/<TICKET>-decomposition-plan.md` `## Wave Ship Plan`

## Work Items in this Wave (touched repo: <repo>)

| WI ID | Title | Tier | Plan | Per-WI PR (auto-closed on open) |
|-------|-------|------|------|---------------------------------|
| <wi-id> | <title> | <tier> | `<plan-path>` | <per-WI PR number/URL> |

## Spec & Decomposition Plan

- Spec: `.forge/specs/<TICKET>-<suffix>-spec.md` (Status: approved)
- Decomposition Plan: `.forge/plans/<TICKET>/<TICKET>-decomposition-plan.md` (Status: approved)
- Spec PR: <#N or URL>
- Plan PR: <#N or URL>

## Verification

<from Decomposition Plan's ## Wave Ship Plan Verification column>

- [x] All WIs in wave at `impl_status: pr-open` before integration
- [x] Wave integration merge clean (no unresolved conflicts)
- [x] Lint clean across touched repos
- [x] Unit tests pass for all touched modules
- [ ] CI green on this PR
- [ ] Human review approves the wave's ship state on main

## Next

After merge, re-run `/forge-deliver <TICKET>` to dispatch wave <N+1>
(or to complete the feature if this was the last wave).
```

For `ship_type: monolithic` waves, also include a `> ⚠ Monolithic wave: <reason>` callout at the top of the body, explaining why this wave is not independently revertable.

### 5. Tracker update + auto-close per-WI PRs

> **Serialize the `tracker.yaml` mutations below under `flock`** on `.forge/.tracker.lock`, same posture as `--artifact code` step 7 (fail open if `flock` absent). The wave-status flip + per-WI `impl_status → wave-closed` flips + `last_updated` bump are one critical section.

```bash
GITHUB_ORG=$(yq '.github_org' .forge/tracker.yaml)

# Tracker: flip wave status
yq -i ".features[] |= (select(.id == \"$TICKET\") | .waves[] |= (select(.wave == $N) | .status = \"pr-open\"))" .forge/tracker.yaml

# Bump global last_updated
yq -i ".last_updated = \"$(date -u +%Y-%m-%dT%H:%M:%S)\"" .forge/tracker.yaml

# Auto-close per-WI PRs
for WI_ID in $(yq ".features[] | select(.id == \"$TICKET\") | .waves[] | select(.wave == $N) | .workitems[].id" .forge/tracker.yaml); do
  WI_BRANCH=$(yq ".features[] | select(.id == \"$TICKET\") | .waves[] | select(.wave == $N) | .workitems[] | select(.id == \"$WI_ID\") | .branch" .forge/tracker.yaml)
  WI_REPOS=$(yq ".features[] | select(.id == \"$TICKET\") | .waves[] | select(.wave == $N) | .workitems[] | select(.id == \"$WI_ID\") | .touched_repos[]" .forge/tracker.yaml)

  for REPO_NAME in $WI_REPOS; do
    WI_PR=$(gh pr list --repo $GITHUB_ORG/$REPO_NAME --head "$WI_BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null)
    [ -n "$WI_PR" ] && gh pr close "$WI_PR" --repo $GITHUB_ORG/$REPO_NAME --comment "Superseded by wave PR. The full diff of WI $WI_ID is in the wave PR for review context. Per-WI branches remain on the remote for git history; this PR is no longer needed as a review surface."
  done

  # Flip impl_status
  yq -i ".features[] |= (select(.id == \"$TICKET\") | .waves[] |= (select(.wave == $N) | .workitems[] |= (select(.id == \"$WI_ID\") | .impl_status = \"wave-closed\")))" .forge/tracker.yaml
done
```

**Commit the harness state.** Same discipline as per-WI `--artifact code` Step 7, but invoked from the harness directly so no `-C` needed. This sweeps up the wave-status flip + the impl_status flips for every per-WI in the wave + the `last_updated` bump:

```bash
git add .forge/
if ! git diff --cached --quiet; then
  git commit -m "chore(<TICKET>): wave <N> status → pr-open

- Wave PR(s) opened in: <touched repos comma-separated>
- Per-WI impl_status flipped to wave-closed for: <wi-ids comma-separated>
- Per-WI PRs auto-closed (Superseded by wave PR)
"
fi
# Do NOT push — harness pushes happen at /forge-deliver stage boundaries.
```

### 6. PR URL is not stored in tracker

Per OQ-M / FR-10: PR URLs are NOT stored in `tracker.yaml`. They are derived on demand:

```bash
GITHUB_ORG=$(yq '.github_org' .forge/tracker.yaml)
gh pr list --repo $GITHUB_ORG/<REPO_NAME> --head "feature/<TICKET>-wave-<N>" --state all --json number,url,state
```

This avoids stale PR URL drift across re-opens and renames.

### 7. Final report

```
## Wave <N> PR(s) opened — <ticket>

Wave Ship Plan (from Decomposition Plan):
  ship_type:    <vertical | monolithic>
  ship state:   <one-line>
  verification: <smoke command or pointer>

Wave PRs:
  <repo-1>: <URL>  (head: feature/<ticket>-wave-<N>, base: main)
  <repo-2>: <URL>  (head: feature/<ticket>-wave-<N>, base: main)

Per-WI PRs auto-closed:
  <wi-id-1>: <repo-1> PR #<N> closed (Superseded by wave PR)
  <wi-id-2>: <repo-1> PR #<N> closed
  ...

Tracker: features.<ticket>.waves[<N>].status = pr-open
         features.<ticket>.waves[<N>].workitems[*].impl_status = wave-closed

Next steps (out of band):
  1. (optional) /forge-review-pr <N> per wave PR — framework-aware review
  2. Merge each wave PR via GitHub UI when CI green + review approves
  3. Re-run /forge-deliver <ticket> to dispatch wave <N+1>
     (or to complete the feature if this was the last wave)
```

---

## Notes

- **Stacked at every level.** Harness: spec PR → main, plan PR → spec branch (auto-retargets to main on spec merge). App-repo code (decomposed): per-WI review PRs stack in dependency-chain order; T-E2E WI's PR → main is the integration PR. No merge-waits at any level.
- **Per-WI PRs are review-only.** Their commits land in `main` indirectly when the integration PR (feature mode) or wave PR (wave mode) merges. Humans don't need to merge each one — though approving them gives explicit review sign-off and lets GitHub auto-retarget bases as the chain unwinds.
- **T-E2E WI's PR is the merge gate (feature mode).** The full browser E2E suite (the project's E2E framework — read the repo's Stack Profile) runs as its CI. Merge it once green; the whole feature ships in one commit (or merge commit, depending on the project's merge strategy).
- **Integration PR base = `main` regardless of `base_branch`.** The T-E2E WI's `base_branch` (set by `forge-worktree-up`) points at the previous WI's branch — that's the branch the worktree was created from, not the PR base. The `type: e2e` flag overrides PR base to `main`.
- **Idempotent on existing open PRs.** Re-running prints the existing URL and exits cleanly.
- **Pre-ticked verification items are evidence-based.** A `[x]` means the skill has the proving command output to back it. Unproven items (CI, manual checks) stay `[ ]`.
- **Out-of-scope staging is a hard refuse.** Spec mode commits only spec-scoped paths; plan mode only plan-scoped. Mixed working trees abort with an actionable message.
- **Non-dispatching.** This skill runs inline in the finalize path; it never dispatches a sub-agent (Claude Code forbids recursive dispatch — see the header guardrail).
- **Org from the tracker.** Every cross-repo `gh ... --repo` call reads `github_org` from `.forge/tracker.yaml`; no org is hardcoded.
- **Conservative auto-flow contract.** This skill STOPS at PR open. No auto-merge.
