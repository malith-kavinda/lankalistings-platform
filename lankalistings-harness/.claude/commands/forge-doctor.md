# /forge-doctor

Read-only diagnostic. Walks `.forge/tracker.yaml` against the actual filesystem and audit log to surface drift like *"tracker says feature X is in `dev`, but no `<feature>-plan.md` exists"* or *"engagement gate marked passed, but no entry in `engagement-gate-runs.md`."*

Report-only. The command never modifies files. The developer reads the report and acts.

The visible output must be stable: the same state on two different runs produces the same shape. Stable shape lets developers diff reports across time to confirm fixes landed.

## How to Use

```
/forge-doctor                    # full report — runs all five check tiers
/forge-doctor --tier <N>         # only run tier N (1, 2, 3, 4, or 5)
/forge-doctor --feature <id>     # scope checks to a single feature (Tiers 2 + 4 only)
```

## Process

### 1. Announce mode

Print exactly one of these lines, followed by a blank line:

- Full: `🩺 /forge-doctor — full report. Read-only; no files will be modified.`
- Tier-scoped: `🩺 /forge-doctor — Tier <N> only. Read-only; no files will be modified.`
- Feature-scoped: `🩺 /forge-doctor — feature <id> only (Tiers 2 + 4). Read-only; no files will be modified.`

### 2. Read inputs

Read in this order. If any required input is missing, surface the missing path and stop — do not produce a partial report.

- `.forge/tracker.yaml`
- `.forge/engagement-gate-runs.md`
- `.forge/specs/` directory listing (excluding the `_TEMPLATE-*.md` files)
- `.forge/plans/` directory listing (excluding `_TEMPLATE-plan.md`)
- `.forge/lessons.md` (optional — if missing, Tier 4 is reported as N/A)
- For each tracked feature in `tracker.yaml.features.*`, the spec, plan, and findings files referenced or implied by the entry

### 3. Run check tiers

Default (no flag): all five tiers. With `--tier <N>`, only that tier. With `--feature <id>`, only Tiers 2 and 4 scoped to that feature.

#### Tier 1 — Tracker ↔ Audit log

Walk `setup.*` against `engagement-gate-runs.md`:

- For each gate where `setup.<gate>.status` matches `gate{1,2,3}-passed*`:
  - There must be at least one `## Gate <N> Run M` block in `engagement-gate-runs.md`. If none → 🔴 drift.
  - The latest gate-run block for that gate — by the date in its heading, not by file position — should match `setup.<gate>.last_gate_run`. Mismatch → 🔴 drift.
  - Every `setup.<gate>.accepted_risks[].id` should appear under `**Risks accepted:**` in the corresponding gate-run audit entry. Missing → 🔴 drift.
- For `setup.foundation.status = done`:
  - Every slice in `setup.foundation.slices[]` should have `status: done`. Any slice not done → 🔴 drift.

#### Tier 2 — Tracker ↔ Filesystem

Walk `tracker.yaml.features.*`:

- For each feature where `phase != backlog` and `phase != paused` and `phase != dropped`:
  - The `spec` field must be a real path (not `n/a`); the file must exist on disk → 🔴 drift if missing.
  - When `phase` ∈ {`plan`, `dev`, `review`, `ship`, `done`}, the `plan` field must be a real path; the file must exist → 🔴 drift if missing.
- For each feature `blocked_by[]` ID, that ID must exist as a key in `features.*` → 🔴 drift if not found.
- Spec body status (read from the spec file's `> Status:` line) should be consistent with `phase`:
  - `phase = plan` → spec status must be `approved` → 🟡 warning if not.
  - `phase = dev` → spec and plan must both be `approved` → 🟡 warning if not.

#### Tier 3 — Filesystem ↔ Tracker (orphans)

Walk `.forge/specs/` and `.forge/plans/` against `tracker.yaml.features.*`:

- For each `<feature>-spec.md` on disk (excluding `_TEMPLATE-spec.md` and `_TEMPLATE-findings.md`):
  - There must be a `features.<feature>` entry in tracker. Missing → 🔴 drift (orphan spec).
- For each `<feature>-plan.md` on disk:
  - There must be a `features.<feature>` entry in tracker. Missing → 🔴 drift (orphan plan).
  - If `features.<feature>.phase` is `backlog` or `spec`, a plan file existing is suspicious → 🟡 warning.
- Foundation specs and plans (under `.forge/specs/foundation/` and `.forge/plans/foundation/`) are validated against `setup.foundation.slices[]` — match by slice `id` (matched against the leading numeric prefix of the filename, e.g., `001-app-shell-spec.md` matches slice id `F-001`) **and** by slice `spec` / `plan` path (the file's path equals the slice's `spec` or `plan` field). Mismatch → 🔴 drift.

#### Tier 4 — Findings ↔ Lessons integrity

Walk `<feature>-findings.md` files against `.forge/lessons.md`:

- For each entry in any findings file with `Promoted: L-NNN` (regex-match against `Promoted: L-\d+`):
  - The cited `L-NNN` ID must appear as an entry in `lessons.md` → 🔴 drift if missing (orphan promotion annotation).
- For each `L-NNN` entry in `lessons.md` that cites a feature ID:
  - The cited feature must exist in `tracker.yaml.features.*` → 🟡 warning if missing.
- If `lessons.md` does not exist, mark Tier 4 as `N/A` rather than failing.

#### Tier 5 — Settings ↔ Phase alignment

Walk `.claude/settings.local.json` `skillOverrides` against the current engagement phase derived from `tracker.yaml`:

- Derive the current phase from `setup.*`: `discovery` (pre-Gate-1) → `architecture` (Gate 1 passed, pre-Gate-2) → `foundation` (Gate 2 passed, foundation not done) → `engineering` (foundation done).
- For each `.claude/skills/*/SKILL.md`, read the front-matter `phases:` field. Skills with no `phases:` field are always-on and should not appear in `skillOverrides` (or, if they do, must be `"on"`).
- For each phase-scoped skill, the expected override is `"on"` if the current phase is in its `phases:` list, otherwise `"off"`.
- Compare expected vs. actual `skillOverrides` in `.claude/settings.local.json`:
  - Skill should be `"off"` but is missing from `skillOverrides` or set to `"on"` → 🔴 drift.
  - Skill should be `"on"` but is set to `"off"` → 🔴 drift.
  - `skillOverrides` contains an entry for a skill that no longer exists in `.claude/skills/` → 🟡 warning (stale entry).
- If `.claude/settings.local.json` does not exist and at least one skill declares a `phases:` field, mark Tier 5 as 🟡 warning (missing settings file).

Every Tier 5 bullet's description ends with the fix command: *"Run `./.claude/hooks/phase-scope-skills.sh` then restart Claude Code."* — single canonical phrasing so two runs against the same state produce identical text.

### 4. Render the report

Output a single Markdown block with this exact shape:

```
# /forge-doctor — Report — YYYY-MM-DD

## Tier 1 — Tracker ↔ Audit log
✅ No issues.
<or>
🔴 N issues:
- **<short label>:** <description with file references>

## Tier 2 — Tracker ↔ Filesystem
[same shape]

## Tier 3 — Filesystem ↔ Tracker (orphans)
[same shape]

## Tier 4 — Findings ↔ Lessons integrity
[same shape, or `➖ N/A — lessons.md not present`]

## Tier 5 — Settings ↔ Phase alignment
[same shape]

## Summary
<X> drift, <Y> warnings, <Z> tiers clean.
```

Conventions:

- A clean tier prints `✅ No issues.` — exactly that string. Don't restructure.
- A tier with issues prints `🔴 <count> issue(s):` followed by a bullet list, one bullet per finding. The bullet's first phrase is a short label (the artifact / gate / feature involved); the rest is the description with file references.
- A tier with only warnings prints `🟡 <count> warning(s):` followed by a bullet list (same shape as drift).
- A tier with both prints both blocks: drift block first (`🔴 N issue(s):`), then warning block (`🟡 N warning(s):`).
- **Pluralization rule (locked for diff stability):** counts use grammatical agreement. `1 issue` and `N issues` (N≠1); `1 warning` and `N warnings`; `1 tier` and `N tiers`. The word "drift" is uncountable and stays singular regardless of count. Two runs against the same state always produce the same words; the agreement is deterministic.
- Severity icons in bullets:
  - 🔴 **drift** — contradiction between two sources of truth (tracker says X, filesystem says Y)
  - 🟡 **warning** — potentially intentional but worth surfacing (e.g., spec status not yet `approved` when phase advanced; could be a rare race or could be drift)
- The Summary line is exactly one line in this shape: `<X> drift, <Y> warning(s), <Z> tier(s) clean.` — agreement applies to "warning" and "tier"; "drift" stays singular.

### 5. No writes

The command never edits `tracker.yaml`, `engagement-gate-runs.md`, `lessons.md`, or any feature artifact. The developer reads the report and acts. There is no `--fix` flag and no automatic remediation.

## Example output (clean run)

```
🩺 /forge-doctor — full report. Read-only; no files will be modified.

# /forge-doctor — Report — 2026-05-07

## Tier 1 — Tracker ↔ Audit log
✅ No issues.

## Tier 2 — Tracker ↔ Filesystem
✅ No issues.

## Tier 3 — Filesystem ↔ Tracker (orphans)
✅ No issues.

## Tier 4 — Findings ↔ Lessons integrity
✅ No issues.

## Tier 5 — Settings ↔ Phase alignment
✅ No issues.

## Summary
0 drift, 0 warnings, 5 tiers clean.
```

## Example output (drift detected)

```
🩺 /forge-doctor — full report. Read-only; no files will be modified.

# /forge-doctor — Report — 2026-05-07

## Tier 1 — Tracker ↔ Audit log
🔴 1 issue:
- **Gate 2 audit drift:** `setup.architecture.status` is `gate2-passed`, but no `## Gate 2 Run` block exists in `.forge/engagement-gate-runs.md`. Either re-run `/forge-arch-probe` to write the audit, or correct the tracker status.

## Tier 2 — Tracker ↔ Filesystem
🔴 2 issues:
- **dashboard:** `tracker.yaml.features.dashboard.phase` is `plan`, but `.forge/plans/dashboard-plan.md` does not exist. Either create the plan file or roll the phase back to `spec`.
- **auth blocked_by:** `tracker.yaml.features.auth.blocked_by` includes `user-mgmt`, which is not present in `features.*`. Either add the missing feature entry or correct the dependency.

## Tier 3 — Filesystem ↔ Tracker (orphans)
✅ No issues.

## Tier 4 — Findings ↔ Lessons integrity
🟡 1 warning:
- **L-003 cites feature:** `lessons.md` entry `L-003` references feature `legacy-import`, which is not present in `tracker.yaml.features.*`. Either correct the citation or restore the feature entry.

## Tier 5 — Settings ↔ Phase alignment
🔴 1 issue:
- **forge-prd-author stale override:** current phase is `engineering` but `.claude/settings.local.json` `skillOverrides.forge-prd-author` is missing or `"on"` (expected `"off"`). Run `./.claude/hooks/phase-scope-skills.sh` then restart Claude Code.

## Summary
4 drift, 1 warning, 1 tier clean.
```

## When to Run

- After bulk operations on `tracker.yaml` (e.g., re-running `/forge-decompose`).
- When the team feels "something is off" but the source isn't obvious.
- Before a major engagement milestone (end of a phase, before sign-off) as a sanity check.
- Periodically — there is no rule, but every few weeks is a reasonable cadence.

## Related

- `tracker.yaml` schema: see the file's own example block and `.claude/rules/tracker.md` "Update Rules" / "Phase Gates".
- Engagement gate audit log: `.forge/engagement-gate-runs.md`.
- Per-feature findings: `.forge/specs/<feature>-findings.md` (template at `.forge/specs/_TEMPLATE-findings.md`).
- Engagement-wide lessons: `.forge/lessons.md`.
- v1 explicitly excludes hook-health checks; those are a different category and may be added in a future tier.
