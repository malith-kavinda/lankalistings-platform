# /forge-deliver payload — implementation agent prompt template

> Stage-loaded payload (context-rightsizing FR-2, v0.36.0): read by the `/forge-deliver`
> orchestrator at each implementation dispatch site (Stage 7 Steps 3/5c/5e, Stage 10).
> Extracted verbatim from the command body — edit HERE; the command holds only the pointer.
> The Dispatch Invariants and the Verify-WI / T-E2E adaptation notes remain in
> `forge-deliver.md` beside the pointer — read them together with this file.

Build dynamically. Self-contained — agent starts cold.

```
Agent(
  description: "Implement <ticket> WI <wi-id>",
  subagent_type: <selected per the "Specialist agent selection" table in forge-deliver.md Stage 7>,
  prompt: """
You are picking up implementation for <feature-title> (<ticket>), workitem <wi-id>.

# Success Criteria (your definition-of-done)

<verbatim copy of this WI's `Success criteria` cell from the Decomposition Plan's ## Workitem Inventory; if a single-plan wave-mode feature, copy from the plan's ## Success Criteria section>

If your subtasks complete but these criteria are not met → HALT and escalate.
Do NOT mark `## Progress` items done unless their tied criterion is satisfied.

# Paths (read in this order)

1. <abs path to plan>                — <plan-path> (approved)
2. <abs path to spec>                — .forge/specs/<ticket>-*-spec.md (approved)
3. <abs path to Decomposition Plan>  — .forge/plans/<ticket>/<ticket>-decomposition-plan.md (approved)
<if this wave has a frozen contract (WI is on a BE↔FE seam):>
4. <abs path to wave contract>       — .forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md (FROZEN — READ-ONLY: this is the authoritative seam shape; conform to it, never edit it. If it's wrong, STOP and escalate — see Scope discipline.)
<for each (repo, path) in this unit's TOUCHED_WORKTREES:>
N. <path>/.claude/CLAUDE.md          — <repo> conventions and common commands (note: lives under .claude/, NOT at repo root)
<if this WI touches frontend route/component files (per the repo's Stack Profile) AND a design reference exists:>
N+1. <abs path to harness>/.forge/design/ui/<design-system>.md   — design system (authoritative): the design-system sections the plan's ## UI / Design Adherence cites (tokens, component + icon mapping, per-screen layouts, cross-cutting conventions such as back-navigation and capitalization). This file is the source behind those citations — read it directly, do not rely on the plan's excerpt alone.
<and ONLY if this WI's plan names a screen AND a design reference exists — omit for non-screen WIs such as a shared badge/tone or app-shell-chrome WI:>
N+2. <abs path to harness>/.forge/design/ui/<screen>.png   — the screen's visual target (a prototype screenshot/mockup) for the screen this WI builds; match it (read as an image).

IMPORTANT: none of these files need to be MERGED to main for you to read them.
They live in the harness session's working tree on branch feature/<ticket>-plan.
Read them directly from the harness paths above — they are approved at Status:
approved and that is the only gate.

# Working directories

Workspace layout: `<workspace>/{<backend-repo>, <frontend-repo>, <harness-repo>}` plus worktrees under `<workspace>/worktrees/<ticket>/<wi-id>/<repo>/` (the orchestrator substitutes `<workspace>` with the absolute workspace path at dispatch time — same as the `# Paths` block above).

<for each (repo, path) in TOUCHED_WORKTREES for this WI:>
- <repo> changes: cd <path>  (already on branch feature/<ticket>-WI-<wave>.<index>-<slug>)
  Base branch: <"main" for type: sub WIs | "feature/<ticket>-wave-<N>" for type: verify / e2e WIs>

⚠ Within-wave sibling rules:
  - For type: sub WIs — this WI runs in PARALLEL with sibling sub-WIs: <list sibling sub-WI IDs in this wave>.
    Do NOT modify any file listed in a sibling's ## Files to Modify table.
    If you discover a file overlap, STOP immediately and escalate.
  - For type: verify / type: e2e WIs — your worktree was provisioned from the wave-integration branch
    feature/<ticket>-wave-<N>, which already contains ALL sub-WIs in this wave merged together (Stage 11
    Pass 1 ran before you were dispatched). You do NOT need to git fetch sibling branches or do any
    ad-hoc integration in your worktree — the integrated code is already present from turn 1. Verify by:
      cd <your worktree>
      git log --oneline -20    # you should see the sub-WIs' merge commits in your history
    Your job is to ADD tests on top of this integrated state — per your plan's ## Test Approach.
    Commit those tests on your per-WI branch; the orchestrator merges your branch into the wave
    branch via Stage 11 Pass 2 after you reach impl_status: pr-open.
    ► type: verify is TWO-PHASE on ONE branch: seam-test-implementer runs Phase 1 (API/contract
      seam check, no browser) first; for a T3 verify-WI, e2e-test-implementer then runs Phase 2
      (wave-scoped browser e2e) on the SAME branch and opens the PR. Your dispatched agent's own
      system prompt (seam-test-implementer or e2e-test-implementer) is authoritative on which
      phase you are and how you exit — follow it. A T2 verify-WI is single-phase (integration-
      verifier only, opens its own PR).
    ► For type: e2e WIs in the final wave: same shape — your wave branch starts from main (no sub-WIs
      in your own wave to merge), but ALL prior waves are already on main, so your worktree sees the
      complete cumulative feature surface.

# Scope discipline (HARD BOUNDARY — read before writing anything)

You may WRITE ONLY to files listed in your plan's ## Files to Modify table, inside the
worktree(s) named under # Working directories above. That table is the exhaustive scope of
your write authority for this WI.

You may READ outside that scope freely — spec, your plan, sibling plans, the Decomposition
Plan, repo CLAUDE.md, application source for pattern lookup. Cross-context reading is part
of doing the work well.

You may NOT WRITE outside that scope. Specifically forbidden — STOP IMMEDIATELY and
escalate to plan ## Notes if you find yourself about to do any of these:

  - Modify `.claude/**` in ANY repo (slash commands, skills, hooks, agents, rules,
    settings.json). Those are framework-level concerns. Even if you spot a real bug or
    finding in an orchestrator command file while reading it for context, do NOT fix it
    inline — record the finding in your plan's ## Notes and let Reflect-phase promote it.
    Framework changes are NOT impl-phase actions, ever.
  - Modify another WI's plan, spec, progress, or notes at `<harness>/.forge/plans/**` or
    `<harness>/.forge/specs/**`. Your OWN plan's ## Progress and ## Notes sections ARE in
    scope — update them as you work.
  - Modify the FROZEN wave contract at `<harness>/.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md`.
    It is the authoritative, read-only seam shape — conform to it. If your work proves the contract
    is WRONG (a field is missing, a type is off, the flow can't be satisfied under it), that is a
    contract defect — STOP, record in your plan's ## Notes, and escalate. The fix is a re-decompose /
    contract re-author, NEVER a silent edit (D3).
  - Modify `<harness>/.forge/tracker.yaml`. That's orchestrator scope; the /forge-pr-open
    skill writes your WI's fields for you at the end.
  - Modify another WI's worktree at `<workspace>/worktrees/<other-wi-id>/**`.
  - Modify CI/CD config or repo-level config files (`.github/**`, `.npmrc`, `package.json`
    scripts beyond what your plan explicitly enumerates) unless your plan lists them.

The harness's absolute paths are visible to you for READING (they appear in # Paths above).
Readability is a convenience, not an invitation to write. Treat the harness as read-only
except for the two carve-outs: your own plan's ## Progress and ## Notes sections.

If your plan turns out to REQUIRE modifying a file outside its ## Files to Modify table to
satisfy a Success Criterion, that is a plan defect — STOP, record in plan ## Notes,
escalate. Do NOT silently broaden scope to make the work compile.

# Wave ship context (from Decomposition Plan's ## Wave Ship Plan)

This WI is part of wave <N>, which declares:
  ship_type:    <vertical | monolithic>
  ship state:   <one-line>
  verification: <smoke command or "see WI-<n>.<i> verify plan">

When the wave's WIs are all PR-open, the orchestrator merges them into
feature/<ticket>-wave-<N> in each touched main app repo (NOT in the worktree
— in the main checkout). That branch then PRs to main as the wave PR.
Your per-WI PR will be auto-closed when the wave PR opens.

# Test tier

This WI is **tier <T1 | T2 | T3 | T-E2E>** per the Decomposition Plan's ## Test Strategy Map.
Write only tier-appropriate tests. The plan's ## Test Approach section lists exactly which tests to write.

# Task

Work the plan's ## Subtasks list IN ORDER. For each subtask:
1. Read the referenced pattern file.
2. Implement the subtask.
3. Run lint per the repo's `.claude/CLAUDE.md` `## Common Commands` (in the repo's .claude folder, not at repo root).
4. Run tests for the touched file/module.
5. Commit (one commit per subtask, message per .claude/rules/git-conventions.md).
6. Update plan ## Progress.

After every subtask, re-check Success Criteria. If a criterion is now satisfied, note it. If a subtask completed and no criterion advanced → either the subtask was wrong (plan defect — record and halt) or the criterion is too coarse (plan defect — record and halt).

# Mandatory final subtasks

(You have no Agent/Skill tool — run each `/forge-*` skill below by executing its
deterministic steps inline via Bash/Edit. None of them dispatches a sub-agent, so
this works; do not attempt to "dispatch" them.)

- Run /forge-pre-pr-review from this worktree. Fix Blockers; record verdict in plan ## Notes.
- Run /forge-test-verify from this worktree. Besides validating tier coverage, it writes a
  `## Test Stats (machine-readable)` block into your WI's audit file — the orchestrator harvests
  that into the feature's test-stats ledger at Stage 12b. Run it even if you are not a test-writing
  specialist, so your WI's counts are captured (unit/integration for sub WIs; the integrated
  cumulative counts for verify/e2e WIs).
- Verify EVERY Success Criterion is checked off in plan ## Success Criteria before opening PR.
- Run /forge-pr-open. This pushes, opens the per-WI PR, and updates the harness tracker.
  PR base is read from tracker's workitems[<wi-id>].base_branch:
    - "main" for type: sub WIs (Pass-1 integration consumes their branches against main)
    - "feature/<ticket>-wave-<N>" for type: verify / type: e2e WIs (Pass-2 integration consumes them against the wave branch)
  Your per-WI PR will be auto-closed when the wave PR opens — it exists as a review surface only.

# Locked decisions

<list architecture decisions + plan ## Decisions entries>

# Execution discipline (background dispatch — proceed continuously)

You were dispatched as a **background** Agent (`run_in_background: true`).
There is no human in the loop between your turns — the orchestrator does
not gate you turn-by-turn. Do NOT stop at turn boundaries.

Start by reading the paths above in order, then proceed **immediately and
sequentially** through the plan's ## Subtasks. Continue across turn
boundaries without pausing. The only valid stopping conditions are the
escalation triggers under "# Failure handling" below and the natural end
of the work (all subtasks complete, Success Criteria met, final subtasks
— pre-PR review + PR open — run).

If you find yourself about to "wrap up turn 1 with a summary and wait for
input" — STOP that instinct. There is no input coming. Keep working.

(This block deliberately replaces the "no writes on turn 1, propose on
turn 2" discipline from foreground-interactive dispatches. That discipline
is correct when a human is reviewing each turn; it silently breaks
background dispatch by making the agent self-terminate after the
"proposal" turn, with `status: completed` and zero edits — which the
orchestrator then interprets as agent-finished. If you ever dispatch this
template foreground for debugging, re-add the turn-1 discipline manually.)

# Failure handling

- Test fails and fixable in-place: fix and re-commit.
- Subtask reveals the plan is wrong: STOP. Record in plan ## Notes. Exit with clear message.
- File overlap with sibling WI: STOP and escalate.
- Subtasks complete but a Success Criterion remains unmet: STOP and escalate. Do NOT open the PR.
- >10 turns without progress on a subtask: STOP and escalate.

Everything you need is in the paths above.
"""
)
```
