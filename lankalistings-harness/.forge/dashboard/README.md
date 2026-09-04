# Tracker dashboard

A self-contained, double-clickable HTML view of `.forge/tracker.yaml`. Reads from
sibling files (`tracker.js`, `signals.js`, optionally `metrics.js` / `usage.js`) that mirror
project state as `window.TRACKER` / `window.SIGNALS` / `window.METRICS` / `window.USAGE`. No web
server, no build step.

## Files

| File | Contents | Source | Refresh |
|------|----------|--------|---------|
| `index.html` | Main dashboard — hero, KPI strip, setup gates, **tabbed delivery phases**, conditional release/UAT section, signals tiles, conditional delivery-metrics section, conditional usage line, recent activity rail. | hand-edited | n/a |
| `usage.html` | Per-phase / per-day / per-developer / per-model token-usage breakdown. Linked from the index Usage section when local usage data exists. | hand-edited | n/a |
| `tracker.js`  | `window.TRACKER` = JSON mirror of `tracker.yaml`. | `.forge/tracker.yaml` (via `yq`) | `regen-tracker-dashboard.sh` hook |
| `signals.js`  | `window.SIGNALS` = precomputed inputs for the S4 (rework rate) and S6 (lessons cadence) signal tiles. | `.forge/specs/**/*.md` + `.forge/plans/**/*.md` + `.forge/lessons.md` | `regen-tracker-dashboard.sh` hook |
| `metrics.js`  | `window.METRICS` = aggregate delivery-metrics / estimation signals. | `.forge/metrics/*.jsonl` | `regen-metrics-dashboard.sh` hook |
| `usage.js`    | `window.USAGE` = aggregated token-usage data for this project. **Gitignored** (per-developer-per-machine). | `~/.claude/forge-usage.jsonl` (filtered by current project) | `regen-usage-dashboard.sh` hook |

## View

Double-click `index.html`. It opens in your default browser via `file://`. All
three data files are loaded via regular `<script>` tags (no `fetch()`, which is
blocked under `file://`). Missing data files are handled gracefully: tracker
absent → full-page fallback; signals absent → S4/S6 read as placeholders; metrics
absent or empty → Delivery Metrics doesn't render; usage absent → the Usage
section doesn't render at all.

## Refresh

**Automatic.** Two `PostToolUse` hooks keep the data files in sync:

- `.claude/hooks/regen-tracker-dashboard.sh` — regenerates `tracker.js` when
  `.forge/tracker.yaml` is edited, and regenerates `signals.js` when any of
  `.forge/specs/**/*.md`, `.forge/plans/**/*.md`, or `.forge/lessons.md` are
  edited (tracker.yaml edits trigger both).
- `.claude/hooks/regen-metrics-dashboard.sh` — regenerates `metrics.js` from
  `.forge/metrics/*.jsonl` after tracker edits or metrics-ledger edits. Empty
  ledgers produce `window.METRICS.empty = true`, so the section hides.
- `.claude/hooks/regen-usage-dashboard.sh` — regenerates `usage.js` on every
  Claude Code Stop event in this project.

After Claude edits any of those source files, just refresh the browser tab.

**Manual fallback** for `tracker.js` (e.g., after a hand-edit outside Claude):

```bash
cd .forge/dashboard
{ printf 'window.TRACKER = '; yq -o=json . ../tracker.yaml; printf ';\n'; } > tracker.js
```

`yq` is already required by the harness gate-state hooks — install with
`brew install yq` (macOS) if needed. Without `yq` the hook fails open with a
one-line stderr note; `tracker.js` will go stale until you install it or run
the manual command.

The dashboard never edits `tracker.yaml`, spec/plan files, or `lessons.md` —
it's a read-only view.

## What the dashboard shows

### Hero
The project name, a one-line **status string** answering "where is the current
phase?" (one of 10 conditions in the spec, derived from `setup.*` +
`delivery.current_phase` + `delivery.phases`), and a secondary line with open
risks, blocked features, and last-updated relative time (suppressed when all
zero).

### At-a-glance
Four KPI tiles — **Total features**, **Shipped**, **In flight**, **Remaining**
— plus a project-wide **overall progress bar** (shipped ÷ total). All four
values come from `tracker.yaml` alone, so the strip renders whether or not
local usage data exists.

### Setup
A four-dot row (PRD → Architecture → Foundation → Decomposition) with labels
and gate-pass dates. Foundation slices collapse behind a disclosure. When all
four gates pass and foundation is done, the section collapses to a one-line
`✓ Setup complete · sealed YYYY-MM-DD` summary with the dot row still visible
and the labels behind a disclosure.

### Delivery
Two render modes, decided by `delivery.phases.length`:

- **Phased mode** (`delivery.phases` non-empty): **tabbed phase strip**. Each
  tab shows the phase number, title, status pill, mini progress bar, and
  done/total count. Click a tab to view its detail panel. The active tab is
  the in-progress phase by default; selection persists in
  `localStorage` under `forge-tracker-phase-state`. Locked-phase panels show
  feature-title preview pills; in-progress and complete panels show feature
  rows with gate dots (G1/G2/G3/G4 derived from each feature's sub-status)
  sorted by sub-status priority. Data drift (a `complete` phase missing
  `sealed`, or a feature whose `delivery_phase` doesn't match any phase id)
  surfaces inline with a ⚠ on the affected tab/row.
- **Flat mode** (`delivery.phases: []`): one-row-per-feature list grouped by
  sub-status, sorted by `last_updated`. No phase scaffolding. Used by small
  projects that opt out of phases (under ~10 features).

There is no "Attention" section — paused / blocked / drift surface inline on
the feature rows they describe. Accepted risks live in `project-prd.md`;
scoped spikes live in `design/architecture.md`.

### Release / UAT (conditional)
The post-delivery lifecycle, rendered from `window.TRACKER.release` and
`window.TRACKER.uat_issues` — both ride the existing `regen-tracker-dashboard.sh`
mirror, so **no new generation hook**. Placed after Delivery, before Signals (it
is the post-delivery stage). Populated interactively by the **`/forge-release`**
command (or by hand). It shows:

- the release id, lifecycle status, scoped delivery phases, and the sign-off /
  go-live date once reached;
- a six-step lifecycle track (`build-complete → regression → uat → stabilize →
  signed-off → live`) with the current step highlighted;
- the cycle list (`RC-n` regression / `UC-n` UAT), each with a flow pass-count
  (e.g. `07 / 10 flows passed`) and status;
- a callout for any **blocking** UAT issues gating sign-off;
- a UAT-issue triage breakdown (total · defects · change-requests · queries ·
  open).

The entire section **hides when `release` is empty (`{}`)** — exactly like the
Usage section's empty state, so existing projects render unchanged (NFR-1).
Detailed per-cycle plans/reports and per-flow evidence live under
`.forge/release/<id>/`; the tracker (and this section) hold only the compact
summary + links.

### Wave Drumbeat (conditional)
A cross-feature wave-cadence view, rendered from each feature's `waves[]` in
`window.TRACKER`. It appears (after Release / UAT, before Signals) only when at
least one feature is decomposed into waves; otherwise it stays hidden. Each
wave-decomposed feature shows its waves in order with per-wave status
(`planned` / `pr-open` / `merged`) and the work-items in each — a quick read of
"which wave is in flight and what's left" across the whole delivery.

### Signals (the new section)
Seven leading-indicator tiles that surface harness-effectiveness over time. Each
tile is a single number + sub-label; no bordered cards.

| ID | Question | Source |
|----|----------|--------|
| **S1 Phase throughput** | How many features did we ship in the current phase, and how many are in flight? | `tracker.yaml` features grouped by `delivery_phase` + sub-status |
| **S2 Phase pace** | Are we on pace, given how long previous phases took? | `delivery.phases[].started` + `sealed` (median of completed phases) |
| **S3 Lead time** | How long does a feature take, end to end? | Feature `started` → `last_updated` for `phase: done`; median + p75 + last-4-week trend |
| **S4 Rework** | Are we redoing earlier passes over shipped features? | Count of features with a non-empty `follow_up_of` — browser-computed from `window.TRACKER` (NOT `signals.js`) |
| **S5 Paused / dropped** | What share of decomposed features stopped before shipping? | Count of features with `phase: paused` or `dropped`, over decomposed total |
| **S6 Lessons cadence** | Is the team still in heavy learning mode, or has the workflow stabilized? | Weekly count over the last 4 weeks (sparkline) of `.forge/lessons.md` entries — a dated `### YYYY-MM-DD — title` heading, or a `## L-NNN — title` heading's body `**Date:**` line (precomputed into `signals.js`) |
| **S7 Open bugs** | How many post-ship defects are open, and where? | Count of `tracker.yaml` `bugs[]` with status `open`/`in-progress`, grouped by scheduled-fix phase — browser-computed from `window.TRACKER` |

**Reading the signals.** These establish a baseline and surface direction —
they do not (and cannot, in v1) prove the harness improved productivity. A
non-harness comparison point doesn't exist inside this dashboard. Lessons
cadence dropping over time is **good** (stabilization). Rework rate dropping
is good; rising can be either thrashing (bad) or higher-quality specs
catching more issues earlier (good) — needs human read of which. Phase pace
is wall-clock, not effort.

**Pricing never appears in the Signals section.** Pricing is a local-data
feature (depends on per-developer `usage.jsonl`), and the rest of the
dashboard renders correctly without it — see Usage below.

### Delivery Metrics (conditional)
Delivery Metrics is the estimation-baseline layer, rendered from `window.METRICS`
which is generated from `.forge/metrics/*.jsonl` ledgers. It appears after
Signals and before Usage only when at least one metrics row exists. It shows
three grouped panels plus a baseline-volume footnote:

- **Cycle time** — median feature cycle (`feature_started → feature_done`), spec
  authoring (`feature_started → spec_approved`), wave-1 cycle (`spec_approved →
  wave-1 merged`, decomp + first build), and later-wave cycle (`prev-wave merged →
  this-wave merged`, build only). Splitting wave-1 from later waves shows how much
  faster waves run once the spec is paid for.
- **Throughput** — features/day and waves/day over a rolling window (default 14
  days; override with `FORGE_METRICS_WINDOW_DAYS`).
- **Complexity signals** — median workitems per feature and median agent runs.
- **Baseline volume** (footnote) — completed features, merged waves, agent runs
  (with repair/retry count), and snapshot count: the denominators behind the medians.

These are labelled as **baselines / estimate signals**, not predictions or
commitments. The source ledgers are append-only, role/project-level facts and are
safe to commit; future token-joined `*.local.jsonl` variants stay gitignored.

### Usage (conditional)
A one-line current-week summary — **tokens this week · est. cost · link to
`usage.html`** — that renders **only** when `window.USAGE` has at least one
row scoped to the current project. When local usage data is absent, the
entire Usage section is hidden; no empty card, no placeholder, no "0
tokens" line. The full per-phase / per-day / per-developer / per-model
breakdown lives in **`usage.html`** (the link target), which reuses the same
`usage.js` data and rate table.

**Pricing appears only in the Usage section and `usage.html`.** Currency
values do not appear in the hero, KPI strip, signals, or activity rail
(FR-11 invariant — grep the rendered DOM for `$` and you'll see this).

### Recent activity
The 5 most recent events derived from tracker timestamps (phase
sealing/opening, feature last-updated transitions, gate runs). Listed
newest-first with relative timestamps.

## Privacy

`usage.js` and the underlying `.forge/usage.jsonl` are **gitignored** — they
contain `user_email` values from `git config user.email` and are
per-developer-per-machine local state. `metrics.js` and the three base
`.forge/metrics/*.jsonl` ledgers carry role/project-level delivery facts and are
safe to commit. Future token-joined metrics variants (`*.local.jsonl`) are
gitignored. The tracker data files (`tracker.js`, `signals.js`, plus the source
`tracker.yaml`) carry no per-developer fields and are safe to commit.

For team-wide rollup across developers, Phase 2 of the token-usage spec
(`docs/engineering/specs/2026-05-14-token-usage-tracking.md`) ships data to
a shared sink — not part of v1.

## Updating Anthropic API rates

When Anthropic changes API prices, edit the `RATES` block (and the
`RATES_VERIFIED_DATE` constant) in **two places**, identically:

1. The inline script in `index.html` (used by the Usage one-line summary).
2. The inline script in `usage.html` (used by the cost card + by-model
   breakdown).

Existing rows in `~/.claude/forge-usage.jsonl` need no migration — cost is
computed at render time, not at capture time. The dashboards apply the new
rates to all history on the next refresh.

## Customising

Templates ship generic. To rebrand for your project, edit `index.html`:

- The Forge mark (inline SVG in the header)
- Colors (CSS custom properties in the `:root` block at the top)
- Section titles ("Setup", "Delivery", "Signals", etc.)

`tracker.js`, `signals.js`, and `usage.js` are generated — do not hand-edit.
