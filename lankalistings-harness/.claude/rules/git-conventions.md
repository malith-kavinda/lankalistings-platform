---
description: Git branch naming, commit format, PR conventions, and worktree commands
globs: "**/*"
---

# Git Conventions

## Branching — GitHub Flow

```
main                                    # Production-ready. Always deployable. Protected. Never commit directly.
feature/<ticket>-<short-description>    # All work — branches from main, merges back to main via PR
fix/<ticket>-<short-description>        # Bugfix work — same merge model as feature
hotfix/<ticket>-<short-description>     # Urgent prod fixes — same merge model
```

Rules:
- `main` is the only long-lived branch — no `develop`, no release branches
- Every piece of work (feature, fix, chore) gets its own branch from `main`
- Branches are short-lived — open a PR early, merge as soon as it passes review and checks
- `main` must always be in a deployable state
- **Tracked post-ship bugs** use the `fix/` prefix with the bug id: `fix/BUG-NNN-<short-description>` (e.g. `fix/BUG-001-unlink-last-child`). See the bug-fix flow in `.claude/rules/tracker.md` → "Bug Tracking".

## Commit Format

`<type>: <description>`

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

Rules:
- Imperative present tense ("add", not "added")
- Subject line under 72 characters
- No period at the end of the subject line
- Reference ticket in body when relevant: `Refs: <ticket>`

## Pull Requests

Every PR must include:
- PR title matches commit convention (`<type>: <description>`)
- Link to the spec file in `.forge/specs/`
- Link to the plan file in `.forge/plans/`
- Summary of what was built and any plan deviations
- Test evidence — screenshots or test output for UI/critical paths

## Worktree Commands

Run from the workspace parent directory.

### Single-plan specs (branch from `main`)

A single-plan spec gets one feature branch per repo, branched from `main`.

```bash
# Create
git -C <repo> worktree add -b feature/<ticket>-<description> worktrees/<ticket>/<repo> main
```

Multi-repo (one worktree per repo, branch coordinated):
```bash
git -C <backend-repo> worktree add -b feature/<ticket>-<description> worktrees/<ticket>/<backend-repo> main
git -C <frontend-repo> worktree add -b feature/<ticket>-<description> worktrees/<ticket>/<frontend-repo> main

# Cleanup (after merge to main)
git -C <backend-repo> worktree remove worktrees/<ticket>/<backend-repo>
git -C <frontend-repo> worktree remove worktrees/<ticket>/<frontend-repo>
rmdir worktrees/<ticket>
```

### Multi-plan specs (spec branch — see below)

A spec decomposed into multiple work items shares ONE spec branch (no per-WI sub-branches in the simple case; wave mode stacks per-WI branches off it — see `forge-worktree-up`).

```bash
# 1. Create the spec branch once (after the Decomposition Plan is approved)
git -C <backend-repo> checkout -b feature/<SPEC_ID>-<description> main
git -C <frontend-repo> checkout -b feature/<SPEC_ID>-<description> main

# 2. Create one worktree set — all WI sessions use these same worktrees
git -C <backend-repo> worktree add worktrees/<SPEC_ID>/<backend-repo> feature/<SPEC_ID>-<description>
git -C <frontend-repo> worktree add worktrees/<SPEC_ID>/<frontend-repo> feature/<SPEC_ID>-<description>

# 3. Cleanup (after the spec branch is merged to main)
git -C <backend-repo> worktree remove worktrees/<SPEC_ID>/<backend-repo>
git -C <frontend-repo> worktree remove worktrees/<SPEC_ID>/<frontend-repo>
rmdir worktrees/<SPEC_ID>
git -C <backend-repo> branch -d feature/<SPEC_ID>-<description>
git -C <frontend-repo> branch -d feature/<SPEC_ID>-<description>
```

## Spec Branches (multi-plan specs)

Applies when: a spec is decomposed into multiple work items (`decomposed: true` in tracker) **and** the spec has at least one user-facing acceptance criterion. Skip if the spec is pure backend/data-layer with no browser E2E tests.

**Model:**
- One `feature/<SPEC_ID>-<description>` branch for the whole spec — created once, branched from `main`.
- All WI implementation sessions commit onto this branch (directly for feature mode; for wave mode each wave's per-WI branches stack and integrate into `feature/<SPEC_ID>-wave-<N>`, which merges back to the spec branch — see `/forge-deliver`).
- `worktrees/<SPEC_ID>/` is the single worktree set; all WI sessions open here.
- The T-E2E WI session (final wave) adds the full browser E2E suite as the last commits.
- One PR from the spec branch to `main` covers the entire feature; CI runs the full suite on this PR.

**CI on the spec branch:**
- Every push to the spec branch triggers lint + unit + integration (progressive feedback as WIs land).
- T3 WI sessions also run WI-scope E2E tests before pushing.
- The spec branch → `main` PR runs the full browser E2E suite as the merge gate.

**Keeping the branch current:**
- If `main` advances during a long feature (hotfix, other feature merged), rebase the spec branch against `main` before opening the final PR. Do this after the T-E2E WI session so E2E validates against the current main state.

**Naming:**
- Spec branch: `feature/<SPEC_ID>-<description>` — same convention as single-plan branches; no `WI-` suffix.
- Example: `feature/<ticket>-auth-core` (not `feature/<ticket>-WI-2.1-db-schema`).
