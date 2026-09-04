---
name: forge-worktree-up
phases: [engineering]
description: "Provision the git worktree(s) and branch for a ticket (single-plan) or one workitem, reading the plan's `## Files to Modify` to decide which repos to touch. Use when a plan is at `Status: approved` and implementation is about to begin. Invoked as `/forge-worktree-up <ticket> [<wi-id>]`."
---

# /forge-worktree-up

Provision worktree(s) for a single-plan feature or for one specific sub-workitem — only for the repos the plan actually touches. Single-responsibility primitive that wraps the `git worktree add` commands from `.claude/rules/git-conventions.md` so the orchestrator and humans don't have to remember the exact incantation.

## How to Use

```
/forge-worktree-up <ticket>                                   # single-plan feature
/forge-worktree-up <ticket> <wi-id>                           # one sub-workitem (auto-detects base branch from tracker chain)
/forge-worktree-up <ticket> <wi-id> --base-branch <branch>    # explicit base branch (overrides auto-detect)
```

If invoked without arguments, print usage and exit.

## When to Use

- A plan (single or WI) is at `Status: approved` and implementation is about to begin.
- Driven by `/forge-deliver` between plan approval and implementation dispatch.
- Manual invocation when a human is taking over implementation.

## When NOT to Use

- The plan is not yet approved — worktrees aren't useful without a plan to follow.
- A worktree already exists and you want a clean reset — that's destructive; use `git worktree remove` first.
- The plan's `## Files to Modify` table is empty or missing the `Repo` column — abort rather than guessing.

## Process

### 1. Validate inputs and determine mode

```bash
TICKET="<first arg>"
WI_ID="<second arg, or empty>"
```

**Single-plan mode** (WI_ID empty):
- Read `.forge/tracker.yaml` `features.<ticket>`. Confirm `phase` is `plan` or `dev` and `decomposed: false` (or absent). Read `plan` path.
- Derive branch slug from feature title (lowercase, kebab, trim to 4 words).
- Branch name: `feature/<TICKET>-<slug>` (e.g. `feature/PROJ-002-auth-core`).
- Worktree base: `<workspace>/worktrees/<TICKET>/`.

**WI sub-plan mode** (WI_ID provided):
- Read `.forge/tracker.yaml` `features.<ticket>`. Confirm `decomposed: true`.
- Locate the WI entry via **shape-agnostic lookup** — search both legacy flat (`features[].workitems[]`) and new nested (`features[].waves[].workitems[]`) shapes. First match wins:

  ```bash
  # Search flat shape first (legacy, ship_unit: feature)
  WI_JSON=$(yq -o=json ".features[] | select(.id == \"$TICKET\") | .workitems[]? | select(.id == \"$WI_ID\")" .forge/tracker.yaml 2>/dev/null)
  if [ -z "$WI_JSON" ] || [ "$WI_JSON" = "null" ]; then
    # Search nested shape (ship_unit: wave)
    WI_JSON=$(yq -o=json ".features[] | select(.id == \"$TICKET\") | .waves[]?.workitems[]? | select(.id == \"$WI_ID\")" .forge/tracker.yaml 2>/dev/null)
  fi
  [ -z "$WI_JSON" ] || [ "$WI_JSON" = "null" ] && abort: "WI $WI_ID not found in features[$TICKET] under either flat workitems[] (legacy) or nested waves[].workitems[] (wave mode)."
  ```

  Read fields off `$WI_JSON`: `plan_status`, `plan_path`, `type`, `tier`, `base_branch`. Confirm `plan_status: approved`. T-E2E WIs have `type: e2e`.
- Derive branch slug from the WI title (lowercase, kebab, trim to 3 words).
- Branch name: `feature/<TICKET>-<WI_SUFFIX>-<slug>` where `WI_SUFFIX` is the wave.index part (e.g. `WI-2.1`), producing e.g. `feature/PROJ-002-WI-2.1-auth-layer`.
- Worktree base: `<workspace>/worktrees/<TICKET>/<WI_ID>/`.

**Determine the base branch**:
- If `--base-branch <branch>` was passed: use it verbatim (orchestrator-driven). This is the path taken by `/forge-deliver` (wave-as-ship-unit: **always `main`** because every wave branches from main).
- Else auto-detect:
  - **Wave mode** (the WI was found under `features[].waves[].workitems[]`): base is always `main`. Wave mode never stacks WI branches; per FR-7.2 every wave branches from main after the previous wave's PR merges, and within a wave WIs branch from the wave's shared base (also main).
  - **Legacy stacked-PR model** (the WI was found under `features[].workitems[]`): compute the dependency-chain order:
    1. List all non-key workitems sorted by `(wave ascending, id ascending)`. Result is `CHAIN`.
    2. Find this WI's position in `CHAIN`. If it's the first entry → base = `main`. Otherwise → base = the previous entry's branch name.
    3. The previous entry's branch name is derived the same way: `feature/<TICKET>-<prev-WI-SUFFIX>-<prev-slug>`. Look it up in the tracker's `workitems[<prev-wi-id>].branch` field if present (orchestrator stores it after first provisioning); otherwise compute it from the prev WI's title (same slug rule as above).
- The chosen base is recorded in this WI's tracker entry as `<wi-path>.base_branch` so subsequent invocations and `forge-pr-open` see the same value. `<wi-path>` is whichever path the WI was located at (flat or nested) — write back to the same shape, never copy across shapes.

**Wave-branch stacking at Stage 7 (verify / e2e WIs).** The base branch for a verify (`type: verify`, T2/T3 seam tests) or e2e (`type: e2e`, T-E2E full browser suite) WI is **re-pointed to the wave integration branch** `feature/<ticket>-wave-<N>` rather than `main` or an implementer branch. This is the stacking point: implementer WIs in wave N land on the wave branch, then the verify/e2e WI branches from that same wave branch so its tests compile and run against the full set of merged implementer changes for the wave. The orchestrator passes this explicitly via `--base-branch feature/<ticket>-wave-<N>`; in direct/recovery invocation under wave mode, auto-detect resolves a verify/e2e WI's base to the current wave integration branch when one exists in the tracker, falling back to `main` otherwise. See L-027 below for the same-repo-coupling vs. cross-repo-seam distinction that governs whether stacking applies.

Confirm the harness root: `$CLAUDE_PROJECT_DIR` should end in `<harness-repo>`. Workspace parent is `$CLAUDE_PROJECT_DIR/..`.

Verify the plan's `## Notes` doesn't already pin a different branch name — if it does, prefer the pinned one and note in the final report.

### 2. Determine touched repos

Read the plan file's `## Files to Modify` table. Collect distinct values from the `Repo` column into `TOUCHED_REPOS`:

- Valid values: `<backend-repo>`, `<frontend-repo>` (the actual on-disk repo directory names for this project — read them from the project CLAUDE.md §Repos / §Common Commands; case-sensitive; other values are a plan-content bug — surface to human).
- If the table is absent or has zero data rows — abort: *"Plan at `<path>` has an empty or missing `## Files to Modify` table. Fix the plan before provisioning."*
- If `TOUCHED_REPOS` is empty after parsing — same abort.

Confirm each repo in `TOUCHED_REPOS` exists as a sibling directory at `<workspace>/<repo>`. Abort on missing repo.

### 3. Validate base branch is clean (and present)

`BASE_BRANCH` is the branch this WI's worktree will branch from — `main` for single-plan and for the first WI in the dependency chain, the previous WI's branch for stacked WIs, or the wave integration branch `feature/<ticket>-wave-<N>` for verify/e2e WIs at Stage 7.

For each repo in `TOUCHED_REPOS`:

```bash
git -C "<workspace>/<repo>" fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
DIRTY=$(git -C "<workspace>/<repo>" status --porcelain 2>/dev/null)
```

- `DIRTY` non-empty → abort: *"`<repo>` working tree has uncommitted changes. Commit or stash before provisioning."*
- If `BASE_BRANCH != main` and the branch doesn't exist locally in this repo → abort: *"Base branch `<BASE_BRANCH>` not found in `<repo>`. The previous WI in the chain (or the wave integration branch for a verify/e2e WI) must be provisioned + implemented before this one. Stacking is sequential by design."*
- If `BASE_BRANCH == main`: verify it's not far behind origin. If `origin/main` is ahead by N: warn *"`<repo>` main is `<n>` commits behind origin/main. Worktree branches from local main. Continue? [y/n]"*

### 4. Provision worktrees (idempotent)

For each repo in `TOUCHED_REPOS`:

```bash
WTPATH="<worktree-base>/<repo>"
BRANCH="<derived branch name>"
BASE_BRANCH="<main | previous WI's branch | feature/<ticket>-wave-<N>>"

if [ -d "$WTPATH" ]; then
  EXISTING=$(git -C "$WTPATH" branch --show-current)
  if [ "$EXISTING" != "$BRANCH" ]; then
    abort: "Worktree at $WTPATH is on branch '$EXISTING', expected '$BRANCH'."
  fi
  echo "Worktree already provisioned: $WTPATH ($BRANCH) from base $BASE_BRANCH"
else
  # If branch already exists (prior aborted run) and isn't checked out elsewhere, attach without -b.
  if git -C "<workspace>/<repo>" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "<workspace>/<repo>" worktree add "$WTPATH" "$BRANCH"
  else
    git -C "<workspace>/<repo>" worktree add -b "$BRANCH" "$WTPATH" "$BASE_BRANCH"
  fi
fi
```

After successful provisioning, write back to tracker — at the SAME shape the WI was located at (flat OR nested; never copy across shapes):

```bash
# Flat shape (legacy ship_unit: feature)
yq -i "(.features[] | select(.id == \"$TICKET\") | .workitems[]? | select(.id == \"$WI_ID\") | .branch) = \"$BRANCH\"" .forge/tracker.yaml
yq -i "(.features[] | select(.id == \"$TICKET\") | .workitems[]? | select(.id == \"$WI_ID\") | .base_branch) = \"$BASE_BRANCH\"" .forge/tracker.yaml

# OR nested shape (wave mode)
yq -i "(.features[] | select(.id == \"$TICKET\") | .waves[]?.workitems[]? | select(.id == \"$WI_ID\") | .branch) = \"$BRANCH\"" .forge/tracker.yaml
yq -i "(.features[] | select(.id == \"$TICKET\") | .waves[]?.workitems[]? | select(.id == \"$WI_ID\") | .base_branch) = \"$BASE_BRANCH\"" .forge/tracker.yaml
```

`yq`'s `| select(.id == "$WI_ID")` is a no-op when the path doesn't contain the WI, so running both expressions safely lands the write on whichever shape exists. Pick the one matching the shape the WI was found at to avoid silent no-ops.

Also write `workitems[<wi-id>].touched_repos[] = TOUCHED_REPOS` (already part of the WI shape per FR-10; the wave-mode tracker write from `/forge-wave-decompose` initializes it to `[]`).

### 5. Final report

```
## Worktree(s) provisioned — <ticket or wi-id>

Plan: <plan-path>
Touches: <comma-separated TOUCHED_REPOS>
Base:   <BASE_BRANCH>   <!-- main (single-plan or first-in-chain) | feature/<TICKET>-<prev-WI-suffix>-<prev-slug> (stacked) | feature/<ticket>-wave-<N> (verify/e2e WI at Stage 7) -->

| Repo             | Branch                              | Base                          | Path                                              |
|------------------|-------------------------------------|-------------------------------|---------------------------------------------------|
<one row per touched repo>

Next: implementation runs from inside each worktree. The orchestrator
(/forge-deliver) dispatches the implementation agent with these
paths; manual implementation: cd into the worktree and start a fresh
Claude Code session pointing at the plan.

Worktree cleanup is handled by /forge-deliver immediately after
each WI's PR is opened (branch is on remote at that point). No manual
cleanup needed. If you need to re-enter a worktree after cleanup:
  git -C <workspace>/<repo> worktree add <WTPATH> <BRANCH>
```

The skill returns the provisioned `(repo, path)` pairs as structured output so the orchestrator can build the implementation agent dispatch prompt without re-deriving paths.

## Notes

- **Idempotent.** Re-running on existing worktrees is a no-op if the branch matches; mismatched branch state aborts cleanly.
- **WI mode uses a dedicated worktree subtree.** Each WI gets its own worktree directory under `worktrees/<ticket>/<wi-id>/` and its own feature branch (`feature/<ticket>-<wi-suffix>-<slug>`). This keeps sibling WI branches clearly separated and avoids accidental cross-contamination.
- **Wave base branches (orchestrated flows) — `/forge-deliver` (`ship_unit: wave`, wave-as-ship-unit, FR-7.2).** `--base-branch` is always passed explicitly when called by the orchestrator: every wave branches from `main`. `--base-branch main` is always passed regardless of wave number. The previous wave's PR merges to `main` first; the next wave then branches from the updated `main`. No per-wave stacking.

  WIs within a wave share the same base — they do not stack on each other within a wave. `forge-pr-open --artifact code` reads `workitems[<wi-id>].base_branch` (written by this skill) to set each PR's base.
- **Verify / e2e WIs re-point to the wave branch (Stage 7).** A `type: verify` or `type: e2e` WI branches from the wave integration branch `feature/<ticket>-wave-<N>`, not from `main` or an implementer branch — so its seam/E2E tests compile and run against the full set of merged implementer changes for the wave. This is the deliberate stacking point in the wave lifecycle.
- **L-027 — same-repo compile coupling vs. cross-repo seam.** When a WI's tests share a compilation unit with the code under test (same repo), the WI must stack on the owner branch (base = owner branch) or split across waves so the dependency lands first; the compiler will otherwise fail to resolve the symbols under test. When the relationship is a cross-repo seam (the test repo and the code repo are different repos talking over an API/contract boundary), there is no compile coupling — the seam-test WI branches in parallel from `main`. Use this distinction to decide a verify/e2e WI's base branch.
- **Stacked-PR auto-detect fallback (direct invocation without `--base-branch`).** When invoked directly without `--base-branch`, auto-detect uses the legacy stacked-PR model: each WI branches from the previous WI's branch tip in `(wave ascending, id ascending)` order. Correct for manual/recovery use on sequentially-decomposed features; will produce the wrong base for wave-parallel features — always pass `--base-branch` explicitly when recovering those.
- **Sequential invocation required.** This skill does a read-modify-write on `tracker.yaml` to record each WI's `branch` and `base_branch` fields. Concurrent invocations for the same ticket will race on that file — always invoke sequentially even when provisioning multiple WIs for the same wave. The orchestrator enforces this.
- **Only provisions repos the plan touches.** Backend-only WIs get one worktree. Cross-repo WIs get two. Empty/untouched repos get nothing.
- **No commits, no pushes.** Only creates worktrees + branches. First commit happens during implementation.
- **Dirty working tree is a hard abort.** Branching with uncommitted changes silently bakes them into the feature branch.
- **Cleanup is the orchestrator's responsibility.** `/forge-deliver` removes each worktree inline after the WI's PR is opened — no post-merge step required.
