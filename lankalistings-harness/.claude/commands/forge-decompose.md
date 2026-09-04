# /forge-decompose

## What This Command Does

Decomposes the project PRD into a backlog of agent-sized feature specs, then verifies the breakdown is complete, non-overlapping, dependency-aware, and correctly sized for one-pass agent runs. This is **Gate 3** of the pre-implementation gates.

Interactive guide — produces draft feature specs and a dependency map for human review.

## How to Use

```
/forge-decompose                                       # full run — creates feature spec stubs, regenerates .forge/features.md, populates tracker entries; writes audit
/forge-decompose dry-run                               # propose the breakdown and walk the checklist, write nothing
/forge-decompose --reslice                             # post-Gate-3 audit — FR-1 sizing + FR-2 would-split + FR-7.a preconditions against existing features; writes nothing
/forge-decompose --reslice --apply [<feature-id>...]   # post-Gate-3 apply — dry-run first, then FR-7.b seven coordinated writes (with rollback snapshot for writes 1–5) for eligible features
```

**Always announce the mode at the start of the run:**

- Full mode: `🔒 Gate 3 — full mode. Will create feature spec stubs, regenerate .forge/features.md, write tracker entries; audit will be appended to .forge/engagement-gate-runs.md.`
- Dry-run mode: `🧪 Gate 3 — dry-run mode. No files will be created or modified. Proposed breakdown will be printed to the session only.`
- Reslice dry-run: `🧪 Gate 3 — reslice dry-run (FR-7). Will run FR-1 sizing audit + FR-2 would-split report + FR-7.a precondition report against existing features. No files will be created or modified.`
- Reslice apply: `🔒 Gate 3 — reslice apply (FR-7.b). Will run the dry-run audit first, then apply accepted splits via the seven coordinated writes (with rollback snapshot for writes 1–5). Eligibility gated by FR-7.a preconditions. Aborts the feature's reslice on any write 1–5 failure and restores files from snapshot; other features in the same batch are unaffected.`

**Dry-run is especially important for this command** — full mode creates many files (one stub spec per feature, plus the regenerated `.forge/features.md`, plus tracker entries). Dry-run lets you see the proposed shape without committing.

## Process

1. Parse arguments — detect `dry-run`, `--reslice`, `--apply`. Announce mode. **If `--reslice` is present, jump to the `## Reslice Mode (FR-7)` section below — the standard 15-step Process does not run.** Reslice without `--apply` is dry-run only (no writes). Reslice with `--apply [<feature-id>...]` runs the dry-run report first, then performs the FR-7.b seven coordinated writes against eligible features. The two reslice sub-modes share the audit/proposal logic; only the write contract differs.
2. Read `.forge/project-prd.md` — confirms in-scope features (Gate 1 must have passed first).
3. Read `.forge/project-prd-signals.md` (if present) — live open questions; surface any that block decomposition (e.g. unresolved scope OQ) as failures in step 12 (Surface failures). The history file is NOT loaded — it's audit trail, not input.
4. Read `.forge/design/architecture.md` — slicing must respect architecture (Gate 2 must have passed first).
5. Read `.forge/checklists/decomposition-checklist.md` — the checklist for this project.
6. Propose a slicing principle (by module / by user journey / by capability / by phase) and confirm with the developer.
7. Propose the feature breakdown and a dependency graph; print to session for review.
8. **Feature sizing audit (FR-1).** For each candidate feature from step 7, compute four signals readable from existing Gate 3 artifacts. No AC or file estimation at this gate — those belong to `/forge-wave-decompose`, which fires after the spec is authored and the counts are actually knowable. Gate 3's job is to catch **structural shape** (cross-layer spread, substrate-stall topology, multi-cluster capabilities, capability density).

    | # | Signal | Trips when | Read from |
    |---|--------|------------|-----------|
    | 1 | **Cross-layer spread** — feature owns substrate (DB/contract) *and* BE service/controller *and* FE surface | The PRD §Feature Decomposition "Substrate brought" column for this feature is non-empty AND the row's described capabilities reference both API and UI work | PRD §Feature Decomposition row + `architecture.md`'s BE/FE/substrate boundaries (cross-check) |
    | 2 | **Substrate-slice consumers** — downstream features need only a slice of this feature's substrate, not its surface | ≥ 1 downstream feature whose PRD row describes needing only schema/contract from this feature. Walk each `downstream → this-feature` edge in the step-7 dependency graph and classify schema-only vs. full-surface. | Step-7 dependency graph + each downstream's PRD §Feature Decomposition row |
    | 3 | **Multi-cluster capability** — PRD row describes ≥ 2 cohesive capability clusters that share neither state nor user-facing surface | ≥ 2 distinct nouns + verbs that don't share state. Trip example: "User CRUD" + "Counsellor reassignment" + "User activation flow" = 3 clusters. Pass example: "JWT mint" + "JWT verify" + "Refresh token rotation" = 1 cluster (shared cryptographic envelope). Cluster-counting is post-cohesion-evaluation. | PRD §Feature Decomposition row's described capabilities |
    | 4 | **Capability density** — raw count of distinct named capabilities in the PRD row, **without** the cohesion collapse Signal 3 applies | ≥ 5 named capabilities | Read the PRD row and count named verbs/nouns describing capabilities. Mechanical, no cohesion judgement. Catches cohesive-but-dense features (Auth-Core's 6 named capabilities collapse to 1 cluster under S3 but still indicate size) and dense features with no downstream slicer (e.g., a Branding feature with 5 capabilities + own substrate + own surface, but no schema-only consumer to anchor S2). |

    **Audit outcome rules:**
    - Signal 1 OR Signal 2 OR Signal 4 tripping flags the feature for a cut proposal — handled in step 9 (FR-2).
    - Signal 2 trips → default proposal is a **substrate-cut**, regardless of other signals (most expensive symptom: blocks other developers' downstream features; cleanest mechanical cut). **This default holds even when S2 trips at exactly 1 schema-only consumer** — surface a `borderline` marker on the proposal acknowledging the lower leverage, but propose the cut.
    - Signal 4 trips alone (S1/S2 don't fire) → Claude reads PRD + `architecture.md` + downstream PRD rows and auto-derives either a cut (substrate / cluster / read-vs-write, whichever the artifacts support) OR a pre-drafted `keep-as-one` verdict with a cohesion justification. Developer reviews the auto-derived proposal in step 9.
    - Signal 3 disambiguates the cut pattern when Signal 1 trips alone (no substrate-slice consumer to anchor a substrate-cut) and informs Claude's auto-derived proposal when Signal 4 trips alone.
    - Signal 3 tripping without Signals 1, 2, or 4 is borderline — print the clusters for developer awareness but do not flag for a split.
    - **Cohesion escape hatch (FR-4) is the developer's override path, never the auto-derive's default.** When S2 trips, the auto-derived proposal is **always substrate-cut**, regardless of how cohesive the feature looks at the capability-narrative level. Claude must not pre-apply the escape hatch on an S2 trip — the developer invokes `keep-as-one` with their own justification at step 9 if they want to override the proposal. Pre-applying the escape hatch happens only on Signal-4-only trips where no clean cut boundary exists in the artifacts (e.g., Auth-Core's "one cryptographic envelope" where no schema-only consumer anchors a substrate-cut).

    Print one row per candidate feature listing all four signal values, `Tripped? yes/no`, and (for tripped features) the identified clusters or downstream substrate-slice consumers or capability count. **No writes happen in this step** — it is interactive surfacing only. Cut-pattern proposals for tripped features are handled in step 9 (FR-2); the persisted audit table (FR-5) is written in step 15 alongside the existing `engagement-gate-runs.md` append.
9. **Cut-pattern proposal (FR-2, FR-3, FR-4).** For each feature flagged in step 8, propose a sibling split (or a pre-drafted `keep-as-one` verdict) before approving the feature. Skip features that were not flagged.

    **Auto-derive the proposal.** Claude reads the available artifacts — PRD row, `architecture.md`, downstream PRD rows, existing dependency graph — and produces a concrete proposal. The developer's role is review-and-accept-or-override, identical to how Signals 1–3 work in step 8. Do not ask the developer to author the proposal; produce one from the artifacts.

    **Choose the cut pattern from three documented forms:**

    1. **Substrate-cut** — default when signal 2 trips (downstream consumes only a slice), regardless of other signals tripped. Split into `<X>-a` (substrate piece — DDL + minimal JPA + contract) and `<X>-b` (surface piece — CRUD UI + workflows). Both inherit `<X>`'s priority.

    **Sibling ID naming (OQ-F resolved, 2026-05-26):** suffix the parent ID with `-a`, `-b`, `-c`, … in the order the cut is described. For substrate-cut, `-a` is conventionally the substrate piece and `-b` the surface piece. For cluster-cut, each `-a`/`-b`/`-c`/… is one cluster. For read-vs-write-cut, `-a` is the read sibling and `-b` the write sibling. The audit table caption identifies which is which; the suffix alone carries no semantic load beyond ordering. Stub spec filenames use the same suffix: `.forge/specs/<feature-id>-a-<name>-spec.md`. Branch names follow the standard `feature/<id>-<description>` convention (`feature/<feature-id>-a-...`).
    2. **Capability-cluster-cut** — when signal 3 trips alongside signal 1 (cross-layer spread) but signal 2 does not trip. Split into one sibling per cohesive capability cluster identified in step 8.
    3. **Read-vs-write-cut** — when the feature does both data ingest and a query/display surface and the two are separable. Split into `<X>-a` (read sibling) and `<X>-b` (write sibling).

    **Signal-4-only trips (capability density ≥ 5; S1/S2 don't fire):** Claude reads the artifacts and either picks one of the three patterns above (when cluster boundaries are identifiable from PRD + architecture) OR pre-drafts a `keep-as-one` verdict with a cohesion justification (when capabilities share state/surface and no clean cut exists — e.g., Auth-Core's "one cryptographic envelope"). The pre-drafted justification is printed alongside the proposal for developer accept/override.

    **Print the proposal:**

    - Sibling IDs + capability allocation (which capabilities from `<X>`'s PRD row land where).
    - Substrate allocation (which entries from `<X>`'s "Substrate brought" column land where; for substrate-cut, all substrate goes to `<X>-a`).
    - **Dependency retargeting preview (FR-3):**
      - For substrate-cut: walk each `<downstream> → <X>` incoming edge; classify schema-only vs. full-surface against the downstream's PRD row. Schema-only edges retarget to `<X>-a` (substrate); full-surface edges retarget to `<X>-b` (surface). Add internal `<X>-a → <X>-b` edge. Remove the original `<X>` node.
      - For cluster-cut: ask the developer per incoming edge which cluster(s) the downstream depends on (default: all clusters, then prune by developer confirmation).
      - For read-vs-write-cut: consumers of the read surface retarget to the read sibling; consumers of the write surface retarget to the write sibling.
      - Print the per-edge retargeting table so the developer can verify before accepting.

    **Developer choice — one of:**

    - **`accept-split`** — Gate 3 commits Claude's proposed siblings. The in-session candidate feature list and dependency graph are rewritten (sibling rows replace `<X>`, edges retargeted per the preview) **before step 10 (delivery phases) and step 15 (writes)**. Both siblings inherit `<X>`'s `priority`; `delivery_phase` is decided in step 10.
    - **`accept-keep-as-one`** — accept Claude's pre-drafted cohesion justification (used when Signal 4 trips and the auto-derived proposal was a `keep-as-one` rather than a split). Justification is recorded for the FR-5 audit table; the feature continues as one unit.
    - **`keep-as-one`** with developer-typed justification — escape hatch (FR-4). Used when Claude proposed a split but the developer believes the feature is cohesive. Requires a one-sentence justification. Canonical pass: "one cryptographic envelope" (Auth-Core). Canonical fail: "I don't want to split it." Justification is auditable but not blocking.
    - **`propose-alternative-cut`** — developer types a custom split (siblings + per-edge retargeting). Gate 3 re-validates that the proposed cut still resolves signal 2 — every previously-substrate-slice downstream must point at a sibling that owns only the substrate slice, not the surface. If the re-validation passes, treat as `accept-split`; if it fails, surface the specific failing edges and prompt for revision.

    **Record outcome for the FR-5 audit table** (written in step 15):
    - `kept-as-one` + justification text
    - `substrate-cut → <A>, <B>`
    - `cluster-cut → <A>, <B>, <C>` (N siblings)
    - `read-write-cut → <A>, <B>`

    **No persistent writes happen in this step** — the in-session rewrite is staged until step 15 commits all outputs.
10. **Propose delivery phases** (optional — skip if the breakdown has fewer than ~10 features and the developer waves it off). Phases group features into stakeholder-facing milestones layered *on top of* the dependency graph. Propose: count, titles, theme per phase, feature-to-phase assignment, and which phase opens at `in-progress`. Confirm with the developer. Respect the dependency graph — features in Phase N may only depend on features in Phase ≤ N. Foundation slices are NOT delivery phases; they stay under `setup.foundation`. If a feature was split in step 9 (accepted FR-2 cut), both siblings need `delivery_phase` assignments — default to the parent's intended phase and ask the developer when ambiguous.

    **Delivery dates are NOT assigned here.** `/forge-decompose` is purely structural — every phase (`delivery.phases[*].due_date`) and every feature (`features[*].due_date`) is written with `due_date: null` (step 15). Date-setting lives in its own command, **`/forge-set-dates`**, so decomposition stays focused and the date logic has a single home. After a full run, recommend it: *"Delivery dates aren't set during decomposition. Run `/forge-set-dates` to assign phase target dates — and, optionally, per-feature dates."* Phase-level dates alone are sufficient for dashboard deadline tracking; per-feature dates are optional and off by default.

    **Derived phase forecast (advisory annotation only).** When you print the proposed phases for developer review, **if — and only if — `.claude/skills/forge-estimate/baselines.json` is calibrated** (its `baseline_version` is not `"uncalibrated"` and its `n` values are non-zero), annotate each proposed phase with a derived forecast line. For each feature in the phase, predict its size vector (waves x WIs) from the step-8 structural signals, then get the day range from the lib helper in invoked mode (`bash .claude/lib/forge-estimate.sh range --waves <N> --wis <M>` — do not `source` it, which breaks under an interactive zsh shell); present the phase forecast as a range under the **parallel-delivery assumption** (the phase completes roughly when its longest member feature does), with the mandatory basis line (source per metric, `n`, `baseline_version`, `generated_at`) and the wall-clock/queue-time caveat — the `forge-estimate` skill owns this presentation, so lean on it rather than re-deriving. If the helper returns `{"error": ...}` (uncalibrated / missing baselines), print **no** forecast — never a fabricated number. **This is annotation for the developer's eyes only: zero writes happen, `due_date` stays `null` (step 15 is unchanged), and `/forge-set-dates` remains the single date-writer.** Do not let the forecast set, imply, or shortcut a date here — surfacing a signal is the whole job; committing a date is a separate, human-confirmed act.
11. Walk the decomposition-readiness checklist against the proposed breakdown (including the Delivery Phases section if used).
12. Surface failures (overlaps, coverage gaps, sizing concerns, dependency cycles, phase-dependency violations) for human resolution.
13. Ask the developer for the verdict: `pass` / `fail` (Gate 3 has no risk-acceptance path — failures must be fixed by re-slicing).
14. **Capture decomposition-surfaced open questions** to `.forge/project-prd-signals.md` (NOT to the PRD body — the `guard-prd-shape.sh` hook blocks that). Common at Gate 3: sequencing questions, feature-boundary questions, "who owns this feature" questions. Schema:

    ```
    | OQ-N | §Functional Surface / §<feature-area> | <topic> | <question> | ⏳ open | <owner, default lead> | <feature IDs blocked, else —> |
    ```

    The `Blocks` column is especially valuable from Gate 3 onward, because feature IDs now exist — fill it in. Skip this step if no new OQs were surfaced.

    If existing OQs in `project-prd-signals.md` had `Blocks: —` placeholders pre-decomposition and now map cleanly to specific feature IDs, update them with the new feature IDs as part of this step (low-cost grooming pass; selective loading in `spec-reviewer` depends on `Blocks` being accurate).

15. **(skipped in dry-run)** Write outputs per the next section.

## Output

In **full mode**, the following writes happen at the end of a run:

| Where | What | Format |
|-------|------|--------|
| `.forge/specs/<feature>-spec.md` (one per feature; or one per sibling when a feature was split via accepted FR-2 cut in step 9) | Create stub from `_TEMPLATE-spec.md` with feature title and a placeholder for context | Markdown |
| `.forge/features.md` | Regenerate the live feature index: slicing principle, `## Delivery Plan` section (if phases defined), mermaid dependency graph, feature table, cross-cutting NFRs | Markdown |
| `.forge/tracker.yaml` `features` | One entry per feature at `phase: backlog` with priority, `delivery_phase` (or `null`), `blocked_by` from the dependency graph, and `due_date: null` (dates are never set by decomposition — assign later via `/forge-set-dates`) | Structured YAML |
| `.forge/tracker.yaml` `delivery` | Populate `delivery.phases` (if defined). First phase flips to `in-progress`; rest to `locked`. `current_phase` set to the in-progress phase's id. Each phase carries `due_date: null` (set later via `/forge-set-dates`). Skip this write entirely if the developer opted out of phasing. | Structured YAML |
| `.forge/engagement-gate-runs.md` | Append `## Gate 3 Run N` block at the bottom of the file, including a `### Feature Sizing Audit` subsection (FR-5) | Narrative — date, runner, outcome, slicing principle chosen, feature count, phase plan summary (if any), checklist findings. The `### Feature Sizing Audit` subsection holds one row per candidate feature in a table: `\| Feature \| Cross-layer spread \| Substrate-slice consumers \| Capability clusters \| Capability density \| Tripped? \| Outcome \| Justification (if kept-as-one) \|` — `Capability clusters` is the post-cohesion cluster count; `Capability density` is the raw named-capability count (mechanical, no cohesion collapse). `Outcome` is one of `kept-as-one`, `substrate-cut → <A>, <B>`, `cluster-cut → <A>, <B>, <C>`, `read-write-cut → <A>, <B>`; `Justification` is `—` for split outcomes, the one-sentence cohesion reason for kept-as-one (whether Claude-pre-drafted-and-accepted or developer-typed). |
| `.forge/project-prd.md` `## Gate Status` | Update the Gate 3 row | Status + Last Run date + link to the audit entry |
| `.forge/tracker.yaml` `setup.decomposition` | Update `status`, `last_gate_run` | Structured YAML |

In **dry-run mode**, nothing is written — the proposed breakdown, dependency graph, sizing audit (FR-1), cut-pattern proposals (FR-2), delivery-phase plan, and checklist findings are only printed to the session.

### Delivery Plan section in `features.md`

When phases are defined, generate a `## Delivery Plan` section between `## Slicing Principle` and `## Dependency Graph` containing:

1. A short prose intro (one or two sentences naming the phasing rationale).
2. A phase table: `| Phase | Title | Theme | Features |`.
3. A per-feature breakdown table sorted by phase: `| ID | Title | Phase | Owner |` (Owner column only if owners are assigned at Gate 3).

When phases are not defined, omit this section entirely.

## Reslice Mode (FR-7)

`/forge-decompose --reslice` operates on an **already-decomposed engagement** (post-Gate-3). It re-runs the FR-1 sizing audit and FR-2 cut-pattern proposal against existing features rather than against the step-7 candidate breakdown, then reports apply-eligibility per the FR-7.a preconditions. Use this when a substrate-stall or oversizing pattern has emerged in the engagement and you want to surface and (optionally later) repair it.

### Dry-Run (default — `/forge-decompose --reslice`)

Read-only. Produces three reports for developer review. No writes — same posture as `dry-run` for the standard flow.

1. **Read existing artifacts:**
   - `.forge/features.md` — feature table + mermaid dependency graph + slicing principle.
   - `.forge/tracker.yaml` `features:` block — for each feature: `id`, `phase`, `priority`, `blocked_by`, `spec`, `plan`, `decomposed`, `workitems[]`.
   - `.forge/project-prd.md` §Feature Decomposition table — "Substrate brought" column + dependencies + priorities + per-row capability descriptions.
   - `.forge/project-prd-signals.md` (if present) — for the precondition 5 downstream-spec-citation check.

2. **Run the FR-1 sizing audit against each existing feature.** Same four signals as the standard Process step 8 (cross-layer spread / substrate-slice consumers / multi-cluster capability / capability density) — only the inputs change (existing PRD row + existing dependency graph instead of step-7 proposals). Foundation slices (`F-NNN` under `setup.foundation`) and `dropped` features are excluded from the audit.

3. **Print the would-split report (FR-2).** For each feature that trips the audit, produce the same proposal shape as the standard step 9:
   - Cut pattern proposed (substrate-cut default when signal 2 trips; cluster-cut or read-vs-write-cut per FR-2 disambiguation rules).
   - Proposed sibling IDs and capability/substrate allocation per the OQ-F-resolved naming convention (`<X>-a` = substrate piece for substrate-cut; per-cluster `-a`/`-b`/`-c` for cluster-cut; `-a` = read, `-b` = write for read-vs-write-cut). The audit table caption identifies which sibling owns what.
   - **Dependency retargeting preview (FR-3):** per-edge schema-only vs. full-surface classification against each downstream's PRD row; proposed retarget destination per edge.
   - Group output by feature, walking the existing dependency graph in topological order (substrate-first features printed first).

4. **Print the precondition report (FR-7.a) alongside each proposed split.** For each tripped feature, evaluate the five preconditions:

   | # | Precondition | Read from | Type |
   |---|--------------|-----------|------|
   | 1 | `tracker.yaml features.<id>.phase == backlog` | `tracker.yaml` `features:` block | Hard |
   | 2 | Spec at `.forge/specs/<id>-<name>-spec.md` is still the `/forge-decompose` stub. **Heuristic:** file size below ~80 lines OR (`Status: draft` AND no `## Revisions` section). If ambiguous, **prompt the developer**: *"Is `<spec-path>` authored or still a stub?"* before classifying. | Spec file `wc -l` + content scan | Hard |
   | 3 | No plan file at `.forge/plans/<id>-<name>-plan.md` AND no `.forge/plans/<id>/` directory (multi-WI). | Filesystem | Hard |
   | 4 | No `Reviewed-via:` annotation anywhere in feature artifacts (spec, plan, WI plans). | Grep across artifacts | Hard |
   | 5 | For each downstream feature that depends on `<id>`: is the downstream past `phase: backlog` AND does its authored spec cite `<id>` as a contract source? | Downstream tracker entries + downstream spec grep for `<id>` references | Soft (warning, not blocker) |

   Output format per feature:
   - `<feature-id>: APPLY-ELIGIBLE` — preconditions 1–4 all pass, no precondition 5 hit.
   - `<feature-id>: APPLY-ELIGIBLE-WITH-WARNINGS — downstream <ids> cite this feature in authored specs (retargeting required)` — preconditions 1–4 pass but precondition 5 warns.
   - `<feature-id>: APPLY-BLOCKED — <list of failing preconditions with specific reasons>` — at least one of preconditions 1–4 failed (e.g., `phase: dev (not backlog)`, `spec authored (235 lines, has ## Revisions)`, `plan exists at .forge/plans/<id>-<name>-plan.md`).

5. **Print the per-feature summary table** at the end of the run:

    ```
    | Feature | Cross-layer spread | Substrate-slice consumers | Capability clusters | Tripped? | Cut pattern | Apply eligibility | Notes |
    ```

    One row per audited feature. The `Cut pattern` column is `—` for untripped features. The `Apply eligibility` column is one of `eligible`, `eligible-with-warnings`, `blocked: <short reason>`, or `n/a` (untripped).

6. **Write nothing.** Reslice dry-run is read-only by contract — no `tracker.yaml`, no `features.md`, no `engagement-gate-runs.md`, no spec stubs touched. The developer reviews the three reports and decides which features (if any) to apply via `--reslice --apply` in a separate invocation.

### Apply Mode (`/forge-decompose --reslice --apply [<feature-id>...]`)

Performs the FR-7.b seven coordinated writes against eligible features. Writes 1–5 are rollback-protected via a session-local snapshot; writes 6–7 are append-only and idempotent.

1. **Parse arguments.** Detect the apply flag and the optional feature-id list:
   - `--reslice --apply` (no IDs) → **interactive mode:** dry-run first, then prompt the developer per tripped feature.
   - `--reslice --apply <feature-id> [<feature-id>...]` → **batch mode:** dry-run first, then apply each named feature in dependency-graph order.

2. **Run the dry-run audit first.** Execute the full six-step dry-run flow above. Print the would-split report, precondition report, and summary table. **The apply pass operates only on the features identified in this report** — no new audit is run during apply; the dry-run output is the input. If a `<feature-id>` was named in batch mode but wasn't tripped by the audit, refuse with a precise error and continue to the next named feature.

3. **Select features to apply:**
   - **Interactive mode:** for each tripped feature in dependency-graph order, prompt the developer with the auto-derived proposal and four choices: `accept` (apply Claude's proposed cut), `skip` (leave as-is, no writes), `propose-alternative` (developer types a custom split; Gate 3 re-validates that signal 2 still resolves before treating as `accept`), `keep-as-one-with-justification` (record the justification in writes 6 + record `Outcome: kept-as-one` in the audit table, no split writes).
   - **Batch mode:** apply Claude's proposed cut for each named feature ID. Skip the per-feature prompt.

4. **Enforce FR-7.a preconditions for each accepted feature.** Re-evaluate the five preconditions against the *current* state of the engagement (not the dry-run snapshot — anything could have changed between dry-run and apply: another developer authored a spec, a plan landed, etc.). If preconditions 1–4 fail, refuse that feature's apply with a precise reason and continue to the next. Precondition 5 prompts the developer for explicit confirmation if it warns (downstream specs cite this feature and will need retargeting).

5. **For each apply-accepted-and-eligible feature, perform the seven coordinated writes (FR-7.b).** Order matters; rollback semantics matter.

   **Snapshot first.** Before write 1, capture the *current* content of every file that will be touched by writes 1–5 into session memory:
   - `.forge/tracker.yaml`
   - `.forge/features.md`
   - `.forge/project-prd.md`
   - `.forge/project-prd-history.md`
   - `.forge/specs/<X>-<name>-spec.md`

   These are the rollback snapshot. If any of writes 1–5 fails, restore each file by writing its snapshot content back.

   **Writes 1–5 (rollback-protected):**

   1. **`.forge/tracker.yaml` `features:` block.** Replace the `<X>` entry with sibling entries (`<X>-a`, `<X>-b`, … per the OQ-F naming convention — substrate-cut: `-a` substrate, `-b` surface; cluster-cut: per-cluster; read-vs-write: `-a` read, `-b` write). Each sibling inherits `phase: backlog`, `priority`, `delivery_phase`, `owner` from `<X>`. For substrate-cut: `<X>-b` adds `blocked_by: [<X>-a]`. Retarget downstream `blocked_by` lists per the dry-run report's per-edge classification (schema-only → `<X>-a`; full-surface → `<X>-b`; cluster-cut: per cluster mapping; read-vs-write: per consumer surface). Update `last_updated` to today's ISO timestamp.

   2. **`.forge/features.md`.** Replace the `<X>` row in the feature table with sibling rows (one per sibling; same column structure: `ID | Title | Priority | Phase | Spec | Plan | Blocked By | OQ Blockers | Notes`). Update the mermaid dependency graph: replace the `<X>` node with sibling nodes (e.g., `F<X>a["#<X>-a <short>"]` + `F<X>b["#<X>-b <short>"]`), retarget incoming edges per the same logic as the tracker write, add internal sibling edges (e.g., `<X>-a → <X>-b` for substrate-cut). If the parent feature appeared in the `## Delivery Plan` per-feature breakdown, replace with sibling rows (siblings inherit the parent's phase per step 10 of the standard Process).

   3. **`.forge/project-prd.md` §Feature Decomposition table.** Replace the `<X>` row with sibling rows. "Substrate brought" column distributes: substrate items move to `<X>-a` (substrate piece for substrate-cut; per-cluster mapping for cluster-cut; read sibling for read-vs-write-cut); remaining capabilities to `<X>-b` (and subsequent siblings). "Dependencies" column updated to reflect the new dependency graph. This is a **live-contract edit** to a table — `guard-prd-shape.sh` does not block it (the hook blocks OQ rows, `## Open Questions` headings, and `## Revisions` headings/rows; the §Feature Decomposition table is part of the live contract). If §Feature Decomposition has a footer line listing live OQs by feature (`Live OQs by feature: ...`), update any entries referencing `<X>` to point at the sibling that inherits each OQ.

   4. **`.forge/project-prd-history.md`.** Append a `### Rev N — YYYY-MM-DD` block under `## Revisions` (compute `N` as one more than the highest existing Rev number in the file). Body describes the reslice: which feature was split, the cut pattern used (substrate-cut / cluster-cut / read-vs-write-cut), the audit signals that tripped (cite by S1/S2/S3/S4), and the developer's accept verdict. Include `Resolves: —` (structural, no OQ resolved). Do **not** add anything to `## Resolved Open Questions` — no OQ was resolved by this reslice.

   5. **`.forge/specs/<X>-<name>-spec.md`.** Delete the original stub. Create new sibling stubs at `.forge/specs/<X>-a-<short>-spec.md`, `.forge/specs/<X>-b-<short>-spec.md`, (and `-c`, `-d`, … for cluster-cut with N siblings). Use `.forge/specs/_TEMPLATE-spec.md` as the basis. Pre-fill `## Context` with: `"Created by /forge-decompose --reslice --apply from parent feature <X> on <YYYY-MM-DD>. See .forge/project-prd-history.md Rev N for the reslice rationale. Run forge-gap-check before fleshing out the body beyond ## Context (per harness ALWAYS DO)."`. Pre-fill `## Constraints and Dependencies` with the sibling's substrate / dependencies / priority pulled from the dry-run report's allocation table. Leave all other sections empty (template placeholders).

   **Writes 6–7 (append-only, idempotent — safe to re-run):**

   6. **`.forge/engagement-gate-runs.md`.** Append a new top-level `## Gate 3 Run N — Reslice` section at the bottom of the file (compute `N` as one more than the highest existing Gate 3 Run number in the file; do not collide with non-reslice Gate 3 runs). Include: date, runner (`Claude under <developer> direction` or similar), mode (`--reslice --apply`), feature(s) applied. Append a `### Feature Sizing Audit` subsection with the full FR-5 audit table covering all features that participated in the dry-run audit (not just the applied ones). Append a `### Applied Splits` subsection listing each applied feature, its cut pattern, the resulting sibling IDs, and the per-edge dependency retargeting that was performed. Append a `### Refused` subsection (if any features were refused by FR-7.a preconditions) listing each refused feature and the precondition that failed.

   7. **`.forge/tracker.yaml` `setup.decomposition`.** Bump `last_gate_run` to today's ISO date. Append a `reslice_runs:` array entry: `{date: <YYYY-MM-DD>, applied_features: [<feature-id>, ...], cut_patterns: {<feature-id>: <pattern>, ...}, refused: [...]}`. If `reslice_runs:` does not yet exist on `setup.decomposition`, create it as `[]` then append (additive — does not break existing readers).

   **Rollback semantics.**
   - If any of writes 1–5 fails (file write error, hook block, malformed content, snapshot-restore-needed condition), restore all five snapshot files to their pre-apply state by writing the snapshot content back. Print: `<feature-id>: REFUSED — rollback complete, restored from snapshot. Cause: <error>`. Do not perform writes 6–7 for this feature.
   - Writes 6–7 are append-only and idempotent — partial completion at 6 or 7 is tolerable; a re-run will idempotently complete them. The snapshot does not cover writes 6–7.
   - Each feature's seven writes are **independent of other features' writes** in the same batch. One feature's rollback does not affect features that already applied successfully in the same run.

6. **Print per-feature outcome summary** at the end of the run:
   - `<feature-id>: APPLIED → <sibling-a>, <sibling-b>[, <sibling-c>, ...]` (success — all seven writes landed)
   - `<feature-id>: APPLIED-WITH-PARTIAL-AUDIT → <siblings>` (writes 1–5 succeeded, writes 6 or 7 partial; surface so the developer can re-run idempotently)
   - `<feature-id>: REFUSED — <reason>` (precondition failure or write 1–5 failure with rollback complete)
   - `<feature-id>: KEPT-AS-ONE — "<justification>"` (interactive mode keep-as-one choice; recorded in writes 6 only, no other writes)
   - `<feature-id>: SKIPPED` (interactive mode skip choice; no writes)

7. **Final state check (advisory).** After all features are processed, walk the resulting `features.md` mermaid graph for cycles or dangling edges. Print a warning if any are found — these would indicate a bug in retargeting logic, not a normal outcome. Recommend `/forge-decompose --reslice` (dry-run) be re-run to confirm the engagement is now in a clean state.

## When to Run

**Standard Gate 3 (full / dry-run):**

- After Gate 2 (`/forge-arch-probe`) passes.
- After significant PRD or architecture changes that change what counts as a feature unit.

**Reslice (`--reslice` / `--reslice --apply`):**

- After Gate 3 has passed and a substrate-stall pattern emerges in the engagement (downstream features blocked on an oversized substrate-bringing feature — see FR-7 in `docs/engineering/specs/2026-05-26-gate3-feature-sizing.md` in the forge-harness repo for the canonical pattern).
- Before authoring the spec for any feature flagged in a previous dry-run reslice, so the spec is written against the substrate sibling rather than the original oversized feature.
- Safe to re-run — dry-run mode is read-only by contract; apply mode is gated by FR-7.a preconditions.

## Related

- Gate 1: `/forge-prd-check`
- Gate 2: `/forge-arch-probe`
- Per-feature workflow: feature stubs created here are picked up by the per-feature workflow once decomposition is approved. Per-feature tooling (spec authoring, plan authoring, checks, reviews, PR) is currently run via direct conversation with Claude — dedicated commands will be introduced as patterns stabilize through real engagement experience.
- Audit storage principle: see `.claude/rules/tracker.md` "Gate Audit Protocol" section.
- PRD trichotomy + OQ lifecycle: `.claude/rules/prd.md` (decomposition-surfaced OQs go to `project-prd-signals.md`, not into the PRD body; `Blocks` column is filled with feature IDs from this gate onward).
