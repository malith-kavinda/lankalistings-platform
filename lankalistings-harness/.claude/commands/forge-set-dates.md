# /forge-set-dates

## What This Command Does

The single tool for assigning or updating **delivery dates** on an already-decomposed project. `/forge-decompose` is purely structural — it never sets dates. Run this command afterward (or any time dates change) to set phase target dates and, **optionally**, per-feature target dates.

Defined as a plain slash command (not a skill) so it costs no standing context — its body loads only when invoked.

Phase dates are the primary deadline unit and drive the dashboard's delivery view. **Per-feature dates are optional** — they are off by default and only set if you opt in.

## How to Use

```
/forge-set-dates              # interactive — walk phases, set dates, optionally cascade to features
```

## When to Use

- After `/forge-decompose` (which leaves all `due_date` fields `null`)
- When delivery dates change and need updating across one or more phases
- Retroactive date assignment on already-decomposed projects (including cross-harness projects)
- To update a single phase's dates without re-running decomposition

## When NOT to Use

- Before `/forge-decompose` has run (no `delivery.phases` in `tracker.yaml` to assign dates to)
- To tweak one feature's `due_date` in isolation — edit `tracker.yaml` directly

## Inputs read

1. `.forge/tracker.yaml` — `delivery.phases` and `features`

## Procedure

### 1. Pre-flight check

Read `.forge/tracker.yaml`. If `delivery.phases` is empty or missing, stop with:
*"No delivery phases found in `tracker.yaml`. Run `/forge-decompose` first to define phases before assigning dates."*

If phases exist, print a summary table of current state:

```
Phase | Title         | Status      | Current due_date | Features
------+---------------+-------------+------------------+---------
P1    | Platform Core | in-progress | —                | 8
P2    | KB & AI       | locked      | —                | 6
```

### 2. Prompt for phase dates

For each phase in id order, ask:
`"Phase N: [title] ([status]) — target delivery date? (YYYY-MM-DD, or Enter to keep [current / skip])"`

- Accept a YYYY-MM-DD date, or Enter to leave the current value unchanged.
- If a phase already has a `due_date` and the developer presses Enter, keep the existing value.
- **If the developer has no date in mind, offer the derived forecast as a suggested anchor** — **but only if `.claude/skills/forge-estimate/baselines.json` is calibrated** (`baseline_version` is not `"uncalibrated"`, `n` values non-zero). Predict each phase-member feature's size vector, get its range from the lib helper in invoked mode (`bash .claude/lib/forge-estimate.sh range --waves <N> --wis <M>` — do not `source` it, which breaks under an interactive zsh shell), and present the phase's forecast range under the parallel-delivery assumption with the basis line (source, `n`, `baseline_version`) and the wall-clock/queue-time caveat — lean on the `forge-estimate` skill for this presentation. Frame it as *"the measured baselines suggest roughly [today + range]; want to use a date near there, or set your own?"* If the helper returns `{"error": ...}` (uncalibrated / missing baselines), skip the offer silently — never fabricate a number. **The forecast is a suggested anchor, not a decision:** the developer confirms the actual date (or types their own). Never auto-write a date from the forecast — the ASK posture in step 5 is unchanged.

### 3. Ask whether per-feature dates are wanted (optional)

After collecting phase dates, ask **once**:
*"Also assign a target date to each individual feature? Feature-level dates are optional — many teams track only phase deadlines. (y/N)"*

- **Default is No.** If the developer declines, **do not set any feature `due_date`** — every `features[*].due_date` stays `null`. Skip to step 5 (write only phase dates).
- Only if the developer opts in, proceed to step 4.

### 4. Calculate feature due dates (only if opted in)

For each phase that has a `due_date` (newly set or pre-existing), calculate the `due_date` for every feature assigned to that phase.

**Algorithm:**

1. **Phase start estimate** (in priority order):
   - Use the phase's `started` date if it is set (in-progress phase).
   - Otherwise use the previous phase's `due_date` (locked/future phase).
   - Otherwise use today's date (ISO format).

2. **Feature weight:** `high=3`, `medium=2`, `low=1`. Default to `medium` (2) if `priority` is not set.

3. **Sort features within the phase:**
   - Topological sort by `blocked_by` edges within the phase (a feature is placed after all its in-phase blockers).
   - Within the same dependency tier, sort by priority (`high` first, then `medium`, then `low`).
   - Features with inter-phase dependencies (blocked by a feature in a different phase) are treated as unblocked for sorting purposes within this phase.

4. **Assign dates proportionally:**
   - Compute `total_weight = sum of all feature weights in this phase`.
   - Walk sorted features, accumulating `cumulative_weight` after each.
   - `feature_due = phase_start + round((cumulative_weight / total_weight) x (phase_due_date - phase_start))` in calendar days.
   - Result is always >= `phase_start` and <= `phase_due_date`.

5. Features in phases that have no `due_date` (skipped) get `due_date: null`.
6. Already-shipped features (`phase: ship` or `phase: done`) keep their calculated date — the calculation is forward-looking, not retroactive-only.

### 5. Confirm and write

Summarise what will change and ask for confirmation before writing:
*"Confirm: update due dates as shown above? (yes/no)"*

On confirmation, update `.forge/tracker.yaml`:
- Set `due_date` on each phase entry in `delivery.phases[*]`.
- Set `due_date` on each feature entry in `features[*]` **only if the developer opted into feature dates** — otherwise leave each feature `due_date: null`.
- Bump `last_updated` to the current ISO timestamp.

Print a confirmation summary after writing:

```
Updated tracker.yaml:
  Phase 1 "Platform Core"  due_date: 2026-07-15
    (feature dates: per-feature opt-in — set / left null)
  Phase 2 "KB & AI"        due_date: 2026-09-01
```

### 6. Dashboard refresh

After writing, regenerate `tracker.js` so the dashboard reflects the new dates (the `regen-tracker-dashboard.sh` PostToolUse hook does this automatically on a `tracker.yaml` edit; run the manual command if the hook didn't fire — e.g. in a worktree session):

```
cd .forge/dashboard
{ printf 'window.TRACKER = '; yq -o=json . ../tracker.yaml; printf ';\n'; } > tracker.js
```

The dashboard renders phase dates on the delivery tab cards and panel headers. The per-feature due-date **column appears only when at least one feature has a `due_date`** — so phase-only projects show no feature-date column.

## Notes

- **Idempotent:** re-running overwrites existing `due_date` values with freshly-calculated ones (when feature dates are opted into). Use deliberately when phase plans change.
- **Partial update:** skipping a phase (Enter with no existing date) leaves that phase and its features `due_date: null` — not shown in the deadline view.
- **Backward-compatible:** projects without dates (`due_date: null`) render correctly in the dashboard; date fields are strictly additive.
