# Delivery Metrics — estimation ledgers

Append-only **data-plane** ledgers that give future delivery estimation a factual
baseline grounded in real Forge runs (how much agent work a feature took, how long
it spent in each stage, how often auto-repair fired, how complexity correlates with
lead time). This is **not** about judging individual developers — it is about
estimating future Forge work from real Forge history.

The split mirrors the rest of the harness: **`tracker.yaml` is the control plane**
(what is active, blocked, sealable); **these ledgers are the data plane** (what
happened, append-only). The dashboard's **Delivery Metrics** section is generated
*from* these files — see `.forge/dashboard/`.

## Files

| File | Holds | Producer |
|------|-------|----------|
| `events.jsonl` | Delivery lifecycle events (spec/decomp/WI/wave/feature transitions, bugs). | `/forge-deliver` appends (see its event-emission Note) |
| `agent-runs.jsonl` | Dispatched-agent lifecycle (role, dispatch mode, attempt, outcome, repair lineage). | `/forge-deliver` appends |
| `estimation-snapshots.jsonl` | One complexity-vs-actual row per feature at completion — the estimation payload. | `/forge-deliver` Stage 15 |
| `../dashboard/metrics.js` | `window.METRICS` = aggregates derived from the three ledgers. **Generated.** | `regen-metrics-dashboard.sh` hook |
| `backfill-from-history.sh` | One-time reconstruction of `events.jsonl` + partial `estimation-snapshots.jsonl` for a project whose engineering finished before metrics were wired. | run manually, once |

## Backfilling a completed project

A project that finished delivery before the metrics ledgers existed has empty
ledgers and a hidden dashboard section. `backfill-from-history.sh` reconstructs
what it can from data that already exists — run it **once**, from the project root:

```bash
bash .forge/metrics/backfill-from-history.sh          # dry-run: print a per-feature fidelity report, write nothing
bash .forge/metrics/backfill-from-history.sh --write   # append source:"backfill" rows, then refresh the dashboard
```

Pass `--repo <owner>/<repo>` for each repo that holds the project's PRs (app repos
**and** the harness repo where spec/plan PRs live) — `--repo` overrides auto-discovery,
so list them all. Sources, best to worst fidelity: **GitHub merged PRs** (`gh`,
datetime, matched by branch `feature/<id>-wave-<N>` / `feature/<id>-spec`) →
**`tracker.yaml` `waves[].merged_at`** (day resolution) → **local git** (only when no
spec PR: `git --follow` first commit on `.forge/specs/<id>-*-spec.md`, rename-aware).
`feature_started` prefers the **spec PR's `createdAt`** — a fixed point immune to the
spec renames/reslices that corrupt git's first-commit; a reconstructed start that
post-dates the feature's first wave merge (a reslice/rename artifact) is dropped rather
than allowed to skew the medians. Every reconstructed row is tagged `"source":"backfill"`
+ `"fidelity":"gh-pr|tracker-date|git|derived"`.

What backfill **can** recover: feature cycle, later-wave cycle, WIs/feature, and —
with `gh` — spec authoring and wave-1 cycle. What it **cannot**: agent-runs (never
historically recorded → `agent_runs: null`, agent-run tiles stay blank); and backfilled
spec-authoring measures the spec PR's open→merge window (the pre-PR authoring/interview
time isn't in any artifact), so it is a lower bound. **Throughput** tiles
read ~0 for a finished project — they are a *rolling, recent-velocity* signal, so the
historical value lives in cycle-time + complexity, not throughput. Validate the
dry-run report against one real project before `--write` — adjust the branch-name /
spec-glob patterns in the script if your repos diverge from the conventions above.

## Discipline

- **Append-only.** One JSON object per line. **Never** read-modify-write a ledger
  (line-atomic append only — the same rule as `.forge/plans/**/*-test-stats.jsonl`).
  This keeps parallel `--wave <N>` sessions from clobbering each other.
- **Schema-versioned.** Every row carries `"schema": "forge-metrics/v1"`. When the
  shape changes, bump the version rather than mutating old rows.
- **Fail open per row.** The dashboard generator drops an unparseable line rather
  than erroring — a malformed row never blanks the whole section.
- **Best-effort emission.** A failed append never blocks delivery. Missing data
  shows as a hidden/empty dashboard section, not a broken one.

## Privacy — committable vs. local

- The **three base ledgers are committable.** They carry role/project-level facts
  only — no `user_email`, no per-machine state. `actor` is a **role** (e.g.
  `orchestrator`), never a person. They are the durable cross-engagement estimation
  baseline and are meant to be shared.
- **Token / user-level data stays local and gitignored.** v1 ships **no token data**
  in these ledgers (lifecycle metadata only). If local token-joining is later enabled
  (joining `agent-runs` to the gitignored `.forge/usage.jsonl` on a developer's
  machine), the enriched output is written to `*.local.jsonl` — gitignored, never
  committed. A team/shared sink is a separate, explicitly privacy-designed feature.

## Schemas (`forge-metrics/v1`)

### `events.jsonl`

```json
{ "schema": "forge-metrics/v1", "ts": "2026-06-18T10:12:00Z", "event": "wave_merged",
  "ticket": "ACME-021", "wave": 2, "wi_id": null, "from": null, "to": null,
  "delivery_phase": 3, "actor": "orchestrator", "source": "/forge-deliver Stage 14" }
```

Event vocabulary: `feature_started`, `spec_drafted`, `spec_approved`,
`decomposition_approved`, `wi_plan_approved`, `wi_dispatched`, `wi_pr_opened`,
`wave_pr_opened`, `wave_merged`, `feature_done`, `bug_opened`, `bug_fixed`.

`feature_started` is emitted **once per ticket** at the first `/forge-deliver`
invocation (Stage 1) — append only if no `feature_started` row for the ticket
already exists, so resumes/re-runs don't reset the feature clock. It is the start
anchor for the cycle-time metrics below.

**Derived dashboard metrics (computed by `regen-metrics-dashboard.sh`, no extra rows):**

- **Spec authoring** = `feature_started → spec_approved` — makes spec-authoring time
  visible instead of losing it (it precedes every other recorded event).
- **Wave-1 cycle** = `spec_approved → wave-1 merged` (decomposition + first build);
  **later-wave cycle** = `prev-wave merged → this-wave merged` (build only). The
  split shows how much faster waves run once the spec exists.
- **Feature cycle** = `feature_started → feature_done` (full lead time, incl. authoring).
- **Throughput** = `feature_done` / `wave_merged` counts per day over a rolling
  window (default 14 days; override via `FORGE_METRICS_WINDOW_DAYS`).

These are **wall-clock lead times** — idle/blocked time (e.g. a spec waiting on a
stakeholder answer) counts toward the segment it sits in. They are estimation
signals, not active-effort measurements.

### `agent-runs.jsonl`

```json
{ "schema": "forge-metrics/v1", "event": "agent_run",
  "ts_start": "2026-06-18T10:12:00Z", "ts_end": "2026-06-18T10:47:00Z",
  "ticket": "ACME-021", "wave": 2, "wi_id": "ACME-021-WI-2.1",
  "agent_role": "frontend-implementer", "dispatch_mode": "implement",
  "attempt": 1, "status": "completed", "outcome": "pr-open", "repair_of": null }
```

A `tokens` block (`{input, output, cache_read, cache_creation}`) is **optional and
deferred** — see Privacy above.

### `estimation-snapshots.jsonl`

```json
{ "schema": "forge-metrics/v1", "ts": "2026-06-18T18:00:00Z", "ticket": "ACME-021",
  "delivery_phase": 3, "ship_unit": "wave", "waves": 3, "workitems": 7,
  "verify_wis": 2, "e2e_wis": 1, "tiers": { "T1": 1, "T2": 2, "T3": 3, "T-E2E": 1 },
  "acceptance_criteria": 14, "touched_repos": ["acme-be", "acme-fe"],
  "agent_runs": 11, "auto_repair_loops": 3, "bugs_found": 2, "lead_time_days": 5,
  "tests": { "unit": 122, "integration": 46, "browser_e2e": 18 } }
```

One row per feature at completion. This is the estimation payload — future
estimation reads these rows ("features with 6–8 WIs, T3/T-E2E, two repos
historically took median X days / Y agent runs").
