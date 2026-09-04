---
name: forge-reflect
phases: [engineering]
description: "Mandatory Reflect-phase walk that closes a feature — run once every code PR is raised and the tracker is at `phase: ship`. Answers the four Reflect questions, promotes findings to `.forge/lessons.md`, and flips the feature to `done`. Not for mid-implementation reflection — record those as findings instead."
---

# /forge-reflect

Mandatory Reflect-phase walk per CLAUDE.md §5. Closes a feature properly: synthesizes lessons, captures generalizable findings into `.forge/lessons.md`, commits + pushes the output to the current branch (typically `feature/<ticket>-plan`), and flips the tracker to `done`. Runs once all PRs are **raised** — does not wait for merges. **If no file changes, Reflect wasn't done.**

## How to Use

```
/forge-reflect <ticket>
```

`<ticket>` is the feature id, e.g. `PROJ-002`. If invoked without an argument, print usage and exit.

## When to Use

- All PRs for the feature have been **raised** (spec PR, plan PR, every code PR). Merge status is irrelevant — Reflect ships findings/lessons alongside the open PRs so reviewers see them in context.
- The tracker shows `phase: ship` (all code PRs merged, CI green, not yet `done`). If still at `phase: review`, the skill will warn before proceeding.
- Directly at Stage 8 of `/forge-deliver`, or manually after `/forge-pr-open --artifact code` has opened the last code PR.

## When NOT to Use

- Any PR has not yet been **raised** — the orchestrator hasn't completed Stage 6 for every WI. Wait until all code PRs are open before reflecting (we need the post-implementation experience to be complete).
- The feature's `phase` is already `done` — re-running is a no-op but emits a one-line *"already reflected"* note.
- Mid-implementation reflection — capture those discoveries in plan `## Failed Approaches` or as findings (`F-NNN`) in `<ticket>-findings.md`. Reflect is a *closing* ritual.

## Process

### 1. Validate inputs

Read `.forge/tracker.yaml` `features.<TICKET>`:
- Confirm the feature exists. Abort if not.
- Confirm `phase` is `ship`. If `review` — warn: *"Feature is at phase: review (PRs may not be merged). The expected starting state for Reflect is `ship` (all code PRs merged + CI green). Proceed? [y/n]"* If `done` — print *"Feature already at phase: done."* and continue read-only.

**Locate all PRs and confirm they're raised** (state must be `OPEN` or `MERGED`; not `CLOSED`):

Scan `features.<TICKET>.notes` for:
- `Spec PR #<N>` (every feature)
- `Plan PR #<N>` (every feature)
- *Single-plan*: `Code PR #<N>` (one per touched repo)
- *Decomposed*: `WI <wi-id>: PR #<N>` (one per WI per touched repo, every WI represented)

Run `gh pr view <N> --json state` for each. Acceptable states: `OPEN`, `MERGED`. Abort on:
- Any `CLOSED` PR: *"PR #<N> is closed. Investigate before reflecting."*
- A WI with no PR number recorded (decomposed only): *"WI <wi-id> has no PR number. Was it implemented? Proceed? [y/n]"*
- The spec/plan PR missing entirely: *"Missing <spec|plan> PR reference in tracker notes. Did `/forge-pr-open --artifact <spec|plan>` run? Reflect only runs after all artifact PRs are raised."*

**Merge status is not gated.** Reflect output is intended to ship with the plan PR for human review alongside the other artifacts.

### 2. Ensure findings file exists

Path: `.forge/specs/<TICKET>-*-findings.md` (mirror the spec's stem, swap `-spec.md` for `-findings.md`).

If missing, instantiate from `.forge/specs/_TEMPLATE-findings.md`. If the template is missing, abort with an error referencing the CLAUDE.md §10 rule.

### 3. Reflect interview — four questions from CLAUDE.md §5

Ask the user, one at a time. Capture answers. Free-form.

```
Reflect on <ticket> — <feature title>. Four questions per CLAUDE.md §5.

1. What worked? (Pick 1–3 things to keep doing.)
2. What didn't? (Pick 1–3 things to stop / change.)
3. Should anything change in the framework? (CLAUDE.md, rules/, hooks/,
   templates, skills/, agents/. Be specific — file path + suggested change.)
4. Walk <ticket>-findings.md. For each F-NNN: promote to lessons.md or
   stay scoped?
```

If nothing for a question, prompt once more; if still empty, record *"Nothing surfaced this round."*

### 4. Walk findings → promote generalizable ones to lessons.md

Read `.forge/specs/<TICKET>-*-findings.md`. For each entry with an unresolved `F-NNN` ID:

Present to the user:
```
F-<N>: <one-line summary>
Body:
  <quote the entry body>

Promote to lessons.md? [y / n / scoped]
```

For each `y`:
1. Read `.forge/lessons.md`. Find highest existing `L-NNN`. Next = `L-<N+1>`.
2. Append new lesson entry. Reuse finding body; add generalization framing if user provides one.
3. Edit finding to set `Promoted: L-NNN`.

For `n` / `scoped`: set `Promoted: scoped`.

### 5. Apply framework changes (Q3)

If Q3 produced concrete change requests (file path + edit), apply them with Edit. Skip vague suggestions — push back: *"Q3 needs a specific file path and concrete edit. Skip or restate?"*

If the change touches CLAUDE.md, rules, or a skill, surface it for a follow-up PR rather than landing it here.

### 6. Flip tracker to `done`

Edit `.forge/tracker.yaml` `features.<TICKET>`:
- `phase: ship` → `phase: done`
- `last_updated: "<today>"`
- Append to `notes`: *"Reflected <today>. Findings: <N> promoted (<L-IDs>), <M> scoped. Framework changes: <list or "none">."*

Bump the global `last_updated`.

### 7. Commit + push to the plan branch

Reflect output (lessons.md updates, finding annotations, any framework-file edits, tracker flip) ships with the plan PR's diff so reviewers see it alongside the spec + plan.

```bash
CURRENT_BRANCH=$(git branch --show-current)
```

- Expected branch: `feature/<TICKET>-plan` (set by orchestrator Stage 4f). If on something else (e.g., manual invocation from `main` or a topic branch), abort: *"Reflect must commit to the plan branch. Current: `<branch>`. Switch to `feature/<TICKET>-plan` and re-run."*

Stage only reflect-scoped paths:
- `.forge/lessons.md` (if modified)
- `.forge/specs/<TICKET>-*-findings.md` (Promoted annotations)
- `.forge/tracker.yaml` (phase + notes diff)
- Any framework files edited from Q3 (`CLAUDE.md`, `.claude/rules/*`, `.claude/skills/*/SKILL.md`, etc.)

```bash
git commit -m "$(cat <<'EOF'
chore: <TICKET> reflect — <N> lessons promoted, <M> scoped

Reflect-phase walk per CLAUDE.md §5. Findings/lessons captured while
the implementation experience is fresh (PRs raised; not waiting on
merges). Tracker advanced to phase: done.

Refs: <TICKET>

🤖 Authored via /forge-reflect
EOF
)"
git push
```

**Merged / stale plan-branch fallback (load-bearing).** Reflect does not gate on merge, so by the time it runs the plan PR may have **already been merged and its branch deleted on the remote** — `git push` then fails (`error: src refspec ... does not match any` after a local `git pull --prune` removed the upstream, or *"Updates were rejected / no upstream branch"*). Do **not** abort and do **not** force-push onto a merged branch. Instead:

1. Re-check the plan PR state: `gh pr view <plan-PR-#> --json state,mergedAt`.
2. **If the plan PR is `MERGED`:** the plan branch is closed for new commits. Land the reflect commit on a fresh follow-up branch off the default branch and open a small follow-up PR so the lessons/findings still ship and are reviewable:
   ```bash
   git switch -c chore/<TICKET>-reflect main   # or the repo default branch
   # (the reflect commit is already made; cherry-pick it if it landed elsewhere)
   git push -u origin chore/<TICKET>-reflect
   gh pr create --title "chore: <TICKET> reflect output" \
     --body "Reflect-phase lessons/findings for <TICKET>. Plan PR #<plan-PR-#> already merged; this carries the Reflect output separately." \
     --base main
   ```
   Record the follow-up PR number in `features.<TICKET>.notes`.
3. **If the plan branch merely lost its upstream tracking but the PR is still `OPEN`:** restore tracking and push — `git push -u origin feature/<TICKET>-plan`.
4. **If `git push` is rejected as non-fast-forward (someone pushed ahead):** `git pull --rebase` then push again; never `--force` a shared plan branch.

The plan PR's diff now includes the reflect output (or the follow-up PR carries it when the plan branch was already merged). The PR body's "Verification" checklist isn't updated automatically — reflect notes that go in the plan PR description are added by the orchestrator's Stage 8 (which can also `gh pr edit` the plan PR to append a `## Reflect` section linking the reflect commit).

### 8. Final report

```
## Reflect complete — <ticket>

- Tracker: features.<ticket> → phase: done
- Findings: <N> promoted to lessons.md (<L-IDs>), <M> kept scoped
- Framework changes: <list of files touched, or "none">
- Commit:  <SHA> pushed to feature/<ticket>-plan (ships with plan PR)
           — or — follow-up PR #<N> (plan branch already merged)

Feature is closed at the tracker level. PRs (spec, plan, code) still
need human review + merge — that's an out-of-band activity.

Worktree cleanup (run after PRs merge — destructive):
<single-plan:>
  git -C <backend-repo> worktree remove worktrees/<ticket>/<backend-repo>
  git -C <frontend-repo> worktree remove worktrees/<ticket>/<frontend-repo>
  rmdir worktrees/<ticket>
<decomposed:>
  <one `git -C <repo> worktree remove worktrees/<ticket>/<wi-id>/<repo>` per WI per repo>
  rmdir worktrees/<ticket>
```

## Notes

- **All-PRs-raised gate, not all-PRs-merged.** Reflect runs when every artifact (spec, plan, code per unit) has an open or merged PR. The implementation experience is in-hand at PR-open time; review feedback that surfaces a new finding later can be appended to `lessons.md` (append-only) in a follow-up.
- **Output ships with the plan PR — or a follow-up PR if the plan branch already merged.** Reflect commits to `feature/<TICKET>-plan` and pushes, growing the plan PR's diff. If the plan PR merged first (Reflect doesn't gate on merge), the Step 7 fallback lands the reflect commit on a fresh `chore/<TICKET>-reflect` follow-up PR instead of force-pushing a merged branch. Humans review reflect output alongside the plan and code PRs either way.
- **Findings template instantiation.** Creates `<ticket>-findings.md` lazily — many features produce zero findings, so the file isn't a precondition.
- **No silent promotion.** Every finding promotion is asked. Lessons are durable, general artifacts — false positives are expensive.
- **Q3 has teeth.** This is how compounding engineering (CLAUDE.md §9) actually happens.
- **Worktree cleanup is suggested, not automatic.** Removing a worktree drops uncommitted state — the skill never does it. Run after PRs merge.
