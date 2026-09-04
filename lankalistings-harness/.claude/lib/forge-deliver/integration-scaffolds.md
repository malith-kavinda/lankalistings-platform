# /forge-deliver payload — wave integration scaffolds (Stage 11)

> Stage-loaded payload (context-rightsizing FR-2, v0.36.0): read by the `/forge-deliver`
> orchestrator when it enters Stage 11 (either pass). Extracted verbatim from the command
> body — edit HERE; the command holds only the pointer. The surrounding Stage 11 semantics
> (pass triggers, single-plan skip, tracker discipline) remain in `forge-deliver.md`.

## Pass 1 — Sub-WI integration

```bash
# Illustrative scaffold — the <…> placeholders and the `if conflicts:` branch are
# pseudocode the orchestrator realizes with real Agent/Bash calls, NOT literal bash.
SUB_WI_REPOS=<union of workitems[*].touched_repos[] for WIs in this wave where type == sub>
ALL_WAVE_REPOS=<union of workitems[*].touched_repos[] for ALL WIs in this wave (sub + verify + e2e)>
WAVE_BRANCH="feature/<TICKET>-wave-<N>"

# Create the wave branch in EVERY repo touched by ANY WI in this wave —
# even repos touched only by verify/e2e WIs need the branch so Step 5c
# (verify) / Step 5e (e2e) can provision their worktrees on it.
for REPO_PATH in $ALL_WAVE_REPOS; do
  cd "$REPO_PATH"   # main checkout, e.g. <workspace>/<backend-repo>
  git fetch origin main
  git checkout -b "$WAVE_BRANCH" origin/main   # WAVE_BASE = main always

  # membership test — does a sub-WI touch this repo? (`[ X in Y ]` is NOT valid test syntax)
  case " $SUB_WI_REPOS " in *" $REPO_PATH "*) REPO_HAS_SUB=true ;; *) REPO_HAS_SUB=false ;; esac
  if [ "$REPO_HAS_SUB" = true ]; then
    for WI in <sub-WIs touching this repo, in topological order>; do
      git merge "<WI.branch>"
      if conflicts:
        dispatch conflict-resolution Agent (see "#### Conflict-resolution agent" in forge-deliver.md)
        wait for agent
        if escalates: halt (see "Irresolvable merge conflict" under "#### Halt conditions" in forge-deliver.md)
    done
  fi
  # If repo is verify/e2e-only (no sub-WIs touch it), the branch is just main+0 commits.

  git push origin "$WAVE_BRANCH"
done

# Sub-WI worktrees can be cleaned now — branches are on remote, integration is pushed.
for WI in <sub-WIs in this wave>; do
  for (repo, wtpath) in WI.touched_repos:
    git -C <workspace>/<repo> worktree remove <wtpath>
  rmdir worktrees/<TICKET>/<WI.id>
done
```

## Pass 2 — Verify/E2E integration

```bash
# Illustrative scaffold — <…> placeholders + `if conflicts:` are pseudocode, not literal bash.
VERIFY_E2E_REPOS=<union of workitems[*].touched_repos[] for WIs in this wave where type in (verify, e2e)>
WAVE_BRANCH="feature/<TICKET>-wave-<N>"   # already on remote from Pass 1

for REPO_PATH in $VERIFY_E2E_REPOS; do
  cd "$REPO_PATH"   # main checkout
  git fetch origin "$WAVE_BRANCH"
  git checkout "$WAVE_BRANCH"
  git pull --ff-only origin "$WAVE_BRANCH"   # in case a concurrent session advanced it

  for WI in <verify/e2e-WIs touching this repo, in topological order — verify before e2e>; do
    git merge "<WI.branch>"
    if conflicts:
      dispatch conflict-resolution Agent (see "#### Conflict-resolution agent" in forge-deliver.md)
      wait for agent
      if escalates: halt
  done
  git push origin "$WAVE_BRANCH"
done

# Verify/e2e worktrees cleaned now.
for WI in <verify/e2e-WIs in this wave>; do
  for (repo, wtpath) in WI.touched_repos:
    git -C <workspace>/<repo> worktree remove <wtpath>
  rmdir worktrees/<TICKET>/<WI.id>
done
```
