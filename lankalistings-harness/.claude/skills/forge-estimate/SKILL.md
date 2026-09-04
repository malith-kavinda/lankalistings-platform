---
name: forge-estimate
description: "Estimate how long a feature, phase, or whole scope will take, in harness-native units (waves x work-items x measured cycle medians) rather than gut-feel days. Auto-triggers on natural-language estimation asks — 'how long would X take', 'rough estimate for <feature>', 'the client wants a number for <scope>', 'when will <phase> land' — including PRE-SPEC asks where nothing is written yet. Never sets a date; that is /forge-set-dates."
---

# forge-estimate

Harness-native delivery estimation. Under Forge, delivery is not predicted by human-effort-days — it is predicted by a feature's **size vector** (waves x work items) multiplied by **measured cycle medians** in fractional wall-clock days. This skill produces that signal: predict the size vector, hand the arithmetic to the deterministic lib helper, and present an honest range with its provenance.

This is the replacement for human-day gut-feel. It works from the first day of delivery (org baselines as a prior) and gets sharper as the project accrues its own history.

## When to use

- Any natural-language estimation ask, at any lifecycle stage:
  - **Pre-spec** — "roughly how long for a bulk-export feature?" (nothing written yet)
  - **Post-decompose** — "how long until PROJ-014 is done?"
  - **Client-facing** — "the client wants a number for the reporting module"
  - **Phase / scope** — "when does Phase 2 land?", "estimate the whole V1.1 scope"
- Whenever someone is about to quote a number to a stakeholder and there is no measured basis in front of them.

## When NOT to use

- To *set* a delivery date — that is `/forge-set-dates` (a human decision the developer confirms). This skill offers a derived anchor; it never writes a date.
- To report *actual* progress or velocity — that is the dashboard's Delivery Metrics section, generated from the ledgers.
- As a commitment. The output is an estimation signal, never a promise (see "What this is / isn't" below).

## The unit model

| Signal | Meaning |
|--------|---------|
| `spec_days` | `feature_started -> spec_approved` (authoring + review + any queue wait in that window) |
| `wave1_days` | `spec_approved -> first wave merged` (decomposition + first build) |
| `later_wave_days` | consecutive `wave_merged` deltas (build only, spec already exists) |
| `waves_per_feature`, `wis_per_feature` | the size-vector priors |

Baselines come from the deterministic helper, which resolves each metric to the project's **own** median once it has >= 5 own samples, otherwise the baked **org** baseline shipped in `.claude/skills/forge-estimate/baselines.json`. Every number carries its sample size `n` and its source.

## Procedure

### 1. Gather what's known

Pull whatever exists for the target, in priority order — stop as soon as you have enough to predict a size vector:

- PRD `## Feature Decomposition` row for the feature (capabilities, substrate brought, dependencies).
- The feature spec (`.forge/specs/<ticket>-*-spec.md`) if one exists — FRs, ACs, scope.
- The tracker entry (`.forge/tracker.yaml` `features.<ticket>`) — priority, `blocked_by`, `decomposed`, any `waves[]`.
- If a Decomposition Plan already exists, its wave/WI counts are the size vector directly — skip the prediction in step 2 and use them.
- For a plain verbal ask with nothing written, use the description itself.

If the input is thin, ask **at most 2-3** sizing questions, then proceed:

- Single layer, or both API and UI (cross-layer)?
- Roughly how many distinct capabilities / screens / endpoints?
- One repo or several?

Do not turn this into a spec interview — the point is a fast, honest signal.

### 2. Predict the size vector (waves x WIs)

Anchor on the same structural signals `/forge-decompose` step 8 uses, with the baseline `waves_per_feature` / `wis_per_feature` medians as priors:

- **Cross-layer spread** — substrate + backend service + frontend surface pushes toward more waves.
- **Capability density** — count of distinct named capabilities; >= 5 indicates a larger feature.
- **Capability clusters** — cohesive clusters that share neither state nor surface tend to become separate waves/WIs.

Start from the org/project priors (e.g. a typical feature is `waves_per_feature` waves / `wis_per_feature` WIs) and adjust up or down from the structural signals. **State the predicted vector and a one-line reason** — e.g. *"Predicting 2 waves / 5 WIs: cross-layer (schema + API + one screen), ~4 capabilities, single cluster — a shade below the org median of 3/7."*

### 3. Call the lib helper for the arithmetic

The skill never does the day math itself — the helper is the single deterministic source. Call it in **invoked mode** (a real `bash` interpreter — do NOT `source` it, which breaks under an interactive zsh shell):

```bash
bash .claude/lib/forge-estimate.sh range --waves <N> --wis <M>
# add  --include-spec false  ONLY when the feature's spec is already approved
```

Pass `--include-spec false` only when the target already has an approved spec (that time is spent — don't count `spec_days` again). For a pre-spec or backlog feature, keep the default (`true`).

To inspect the resolved baselines directly (e.g. to read the basis line without a range): `bash .claude/lib/forge-estimate.sh baselines`.

**If the helper returns `{"error": ...}` (uncalibrated / missing baselines): SAY SO and STOP.** Tell the user the org baselines have not been calibrated yet (the baked `baselines.json` still ships uncalibrated; a maintainer calibrates it via `forge-rollup --emit-baselines` before release) and that you will not invent a number. Do not fabricate a range from memory.

### 4. Present

Report, in this shape:

- **The range, never a point** — "roughly `low_days`-`high_days` wall-clock days, once picked up."
- **The size vector** — "N waves / M work items" with the one-line reasoning from step 2.
- **The mandatory basis line** — source per metric group (project history vs org baseline), the `n`, the `baseline_version`, and `generated_at`. Read these from the helper's `basis` block. Example: *"Basis: org baseline v2026-07 (generated 2026-07-16) — spec 0.2d (n=15), wave-1 0.3d (n=12), later-wave 0.2d (n=29); project has < 5 own samples so org medians are used."* When a metric is `source: "project"`, say so ("this project's own history, n=7").
- **The mandatory caveat, verbatim-ish:** these are wall-clock medians *at measured cadence, once the work is picked up* — calendar delivery is usually dominated by **human queue time** (review turnaround, merge waits, stakeholder answers), which this number does **not** include. The real calendar date is this range plus however long things sit in someone's queue.

### 5. Multi-feature asks (a phase / a whole scope)

When the ask spans more than one feature (a delivery phase, a release scope):

1. Estimate each feature individually (steps 1-4), calling the helper per feature.
2. **Sum the ranges** (sum the `low_days`, sum the `high_days`).
3. Flag two things explicitly:
   - The sum inherits a **parallel-delivery assumption** — it does not model one developer working features serially, or WIP limits. Under single-owner load the calendar span is longer.
   - The **queue-time caveat applies even more strongly** across a multi-feature scope, because each feature carries its own review/merge/answer waits.

Present the phase/scope total as a range with the same basis line, and name the per-feature breakdown so the number is inspectable.

## What this is / isn't

- **It is** an estimation *signal* derived from measured Forge history — the harness-native replacement for human-day gut-feel.
- **It is not** a commitment, a deadline, or an active-effort measurement. Wall-clock medians count idle/queue time inside each segment; they are lead-time signals, not effort.
- The unit is **waves/WIs x measured cycle medians**, not person-days. If someone asks "how many developer-days", reframe: Forge measures cycle time, and calendar delivery is cycle time plus queue time.
- Every number is only as good as its `n`. A small `n` or an org (not project) source means wider real-world variance — say so.

## Related

- Deterministic arithmetic + baselines resolution: `.claude/lib/forge-estimate.sh` (`--self-test` for the contract).
- Baked org baselines: `.claude/skills/forge-estimate/baselines.json` (regenerated by `forge-rollup --emit-baselines` in the meta repo; never hand-edit).
- Ledger source of the measured cycles: `.forge/metrics/` (`events.jsonl`, `estimation-snapshots.jsonl`) — see `.forge/metrics/README.md`.
- Date setting (the human decision this skill feeds): `/forge-set-dates`.
- Structural sizing signals this skill borrows: `/forge-decompose` step 8.
