# /forge-wave-decompose

Single entry point for plan-shaping in **wave mode** after a feature spec is approved. Idempotent and state-aware. Slash-only — never auto-loads, never auto-triggers. Lives in `.claude/commands/` so it costs zero context budget when not invoked.

This command is the decomposition entry point for wave-mode delivery:

- Produces a **Decomposition Plan**: `.forge/plans/<ticket>/<ticket>-decomposition-plan.md`.
- Uses template `.forge/plans/_TEMPLATE-decomposition-plan.md`.
- Wave numbering starts at **1 for the first shipping wave**. There is no "wave 1 = Key WI" convention.
- After the inventory + AC coverage + Test Strategy Map are set, runs a **wave-vertical-decision step (5.b.8)** that computes the ship-unit 4-item checklist (C1–C4) per wave and writes the `## Wave Ship Plan` section.
- Writes the **nested tracker schema** — `features[].decomposition_plan` as a sibling of `features[].waves[]`, with `waves[].workitems[]` nested inside each wave entry (see `.forge/tracker.yaml`'s wave-mode schema block).
- Refuses if the engagement (or the per-feature override) is at `ship_unit: feature` — this harness ships wave-mode decomposition only.

Doctrine: the wave-mode workflow is described in `.forge/forge-harness-framework.md` (read on demand).

Scope is **spec approval → all workitem plans authored as drafts**. Each plan is reviewed individually via `/forge-plan-review`. Implementation is downstream of this command (`/forge-deliver`) and out of scope.

## How to Use

```
/forge-wave-decompose <spec-id>
```

`<spec-id>` is the feature ID exactly as it appears in `.forge/specs/`, e.g. `PROJ-042`. The command resolves the spec path as `.forge/specs/<spec-id>-*-spec.md` (single match required).

If invoked without an argument, print usage and exit.

## When to Use

- A feature spec has just been approved via `/forge-spec-review` and the engagement is in wave mode.
- The Decomposition Plan for a decomposed spec is at `Status: approved` and you want the next wave's authoring brief.
- A previous invocation was interrupted; re-invoking picks up at the next pending step.

## When NOT to Use

- **Spec is not yet approved** — run `/forge-spec-review` first. The command aborts if `spec_status != approved`.
- **Single plan already exists and is approved** — feature is past plan-authoring; nothing to do.
- **Reviewing a plan** — use `/forge-plan-review` (this command writes plans; it does not review them).
- **Foundation specs** — out of scope (foundation specs were approved via the manual pre-Gate-3 cycle).
- **Engagement at `ship_unit: feature`** — this harness provides wave-mode orchestration only. The mutual-exclusion guard in step 1 enforces this.

## Process

### 1. Validate inputs + mutual-exclusion guard

```bash
SPEC_ID="<spec-id>"     # as passed by the user, e.g. PROJ-042
[ -n "$SPEC_ID" ] || { echo "Usage: /forge-wave-decompose <spec-id>"; exit 1; }

# Resolve spec path — single glob match required.
SPEC_PATH=$(ls .forge/specs/${SPEC_ID}-*-spec.md 2>/dev/null | head -1)
[ -f "$SPEC_PATH" ] || {
  echo "Spec not found for ID '$SPEC_ID' under .forge/specs/. Aborting."
  exit 1
}

# Foundation-spec exclusion.
case "$SPEC_PATH" in
  *.forge/specs/foundation/*)
    echo "$SPEC_PATH is a foundation spec — out of scope. Aborting."
    exit 1
    ;;
esac

# Verify spec is approved.
STATUS=$(grep -m1 '^> Status:' "$SPEC_PATH" | sed 's/.*Status: //; s/[[:space:]]*$//')
[ "$STATUS" = "approved" ] || {
  echo "Spec '$SPEC_ID' is at Status: $STATUS, not approved. Run /forge-spec-review first. Aborting."
  exit 1
}

# Mutual-exclusion guard: refuse if engagement OR feature is in `feature` mode.
# Engagement default lives at delivery.ship_unit; per-feature override at features[].ship_unit.
ENG_SHIP_UNIT=$(yq '.delivery.ship_unit // "wave"' .forge/tracker.yaml)
FEAT_SHIP_UNIT=$(yq ".features[] | select(.id == \"$SPEC_ID\") | .ship_unit // \"\"" .forge/tracker.yaml)
EFFECTIVE_MODE="$ENG_SHIP_UNIT"
[ -n "$FEAT_SHIP_UNIT" ] && EFFECTIVE_MODE="$FEAT_SHIP_UNIT"

if [ "$EFFECTIVE_MODE" = "feature" ]; then
  echo "Engagement (or feature '$SPEC_ID') is at ship_unit: feature."
  echo "This harness provides wave-mode decomposition only."
  echo "Set ship_unit: wave (delivery.ship_unit, or features[$SPEC_ID].ship_unit) to proceed,"
  echo "or decompose the feature manually. Aborting."
  exit 1
fi
```

> **Tracker field-shape note.** The `yq` paths above assume `features` is a mapping/sequence carrying an `id` field, matching this template's `.forge/tracker.yaml`. If a project stores `features` as a map keyed by id, adjust the selector accordingly.

### 2. Detect state

The state machine has five branches:

```bash
SINGLE_PLAN_PATH=".forge/plans/${SPEC_ID}-*-plan.md"
DECOMP_PLAN_PATH=".forge/plans/${SPEC_ID}/${SPEC_ID}-decomposition-plan.md"

# Check single-plan file
if ls $SINGLE_PLAN_PATH 2>/dev/null | head -1 | grep -q .; then
  STATE="single-plan-exists"
elif [ -f "$DECOMP_PLAN_PATH" ]; then
  DECOMP_STATUS=$(grep -m1 '^> Status:' "$DECOMP_PLAN_PATH" | sed 's/.*Status: //; s/[[:space:]]*$//')
  case "$DECOMP_STATUS" in
    approved) STATE="decomp-approved-dispatch-wave" ;;
    draft|in-review) STATE="decomp-in-review" ;;
    *) STATE="decomp-unknown-status" ;;
  esac
else
  STATE="fresh-start"
fi
```

Branch handling:

| State | Action |
|---|---|
| `fresh-start` | Run size assessment (step 3), confirm with developer, branch single or multi (steps 4 or 5). |
| `single-plan-exists` | Print: *"Plan exists at `<path>`. Run `/forge-plan-review <path>`."* Exit. |
| `decomp-in-review` | Print: *"Decomposition Plan at `<path>` is `Status: <status>`. Run `/forge-plan-review <path>` first, then re-invoke this command."* Exit. |
| `decomp-approved-dispatch-wave` | Skip to step 6 (wave dispatch). |
| `decomp-unknown-status` | Abort with a clear message — Decomposition Plan header is malformed. |

### 3. Size assessment (only on `fresh-start`)

Compute five signals from the spec:

| Signal | How to measure |
|---|---|
| Acceptance criteria count | Count rows in the spec's `## Acceptance Criteria` table or list. |
| Estimated files-to-modify | Read the spec's `## Constraints and Dependencies` and `## Requirements` for file-count hints; ask the developer if no signal in the spec. |
| Cross-repo scope | Look for both backend and frontend references in the spec body. |
| Migration scope | Count migration mentions in the spec. |
| Cross-feature dependency consumption | Count features that list this spec in `blocked_by` in `.forge/tracker.yaml`. |

Thresholds (advisory): ≥8 ACs, ≥15 files, cross-repo with deep coupling, >2 migrations, ≥3 downstream consumers. If **any** signal is tripped, default recommendation is multi-plan; otherwise single-plan.

Print:

```
Spec <SPEC_ID> size assessment (wave mode):

  ✔ <N> acceptance criteria              (threshold: 8)
  ✔ ~<N> files-to-modify estimated       (threshold: 15)
  ✔ Cross-repo: backend + frontend
  ✔ <N> migrations                       (threshold: 2)
  ✔ Consumed by <list of downstream IDs>

Default recommendation: <MULTI-PLAN | SINGLE-PLAN> (<N> signals tripped).
```

**MANDATORY — invoke `AskUserQuestion`** to capture the developer's choice. Hard interactive stop. Do NOT infer the choice, do NOT proceed under Auto Mode, do NOT skip even when the recommendation is strong.

Question shape (verbatim labels — downstream branching reads them):

| Field        | Value                                                                                                                              |
|--------------|------------------------------------------------------------------------------------------------------------------------------------|
| question     | "How should `<SPEC_ID>` decomposition proceed? Default recommendation is `<MULTI-PLAN \| SINGLE-PLAN>` (`<N>` signals tripped)."   |
| header       | "Plan shape"                                                                                                                       |
| multiSelect  | false                                                                                                                              |
| option 1     | label: "Multi-plan (Decomposition Plan + sub-WIs in waves)"  /  description: "Author the Decomposition Plan, then iterate wave-by-wave through `/forge-plan-review` on each sub-WI. Each wave ships to main as its own PR." |
| option 2     | label: "Single-plan (one plan file, one wave)"  /  description: "Write one plan covering the whole spec — this plan IS the only wave. Carries its own `## Wave Ship State` section." |
| option 3     | label: "Cancel"  /  description: "Abort the decomposition; no artifacts written, tracker unchanged."                               |

The recommended option is always first.

Branch on the selection:

- Multi-plan label chosen → step 5
- Single-plan label chosen → step 4
- Cancel chosen → print "Aborted. Tracker and disk unchanged." and exit
- "Other" with free-text → if unambiguously single/multi/cancel, branch accordingly; otherwise re-ask with the original text quoted back.

### 4. Single-plan branch (wave mode)

If the developer picks single-plan:

#### a. Author the plan interactively

Read `_TEMPLATE-plan.md`. Walk the developer through each required section (Approach, Decisions, Subtasks, Files to Modify, Risks, Test Approach, **Wave Ship State**, Progress, Notes). Confirm each section before moving on.

The plan KEEPS the `## Wave Ship State` section (single-plan features in wave mode own their wave state in the plan, not in a separate Decomposition Plan). Fill its fields:

- `ship_type` — propose `vertical` by default; switch to `monolithic` only if the ship-unit 4-item checklist (C1–C4) fails for legitimate reasons.
- `Ship state on main` — one-line active voice description.
- `Acceptance criteria satisfied` — list every AC ID from the spec.
- `Verification` — smoke command(s) or "see ## Test Approach".
- `Monolithic reason` — only if `ship_type: monolithic`. Must be legitimate.

Write to `.forge/plans/<SPEC_ID>-<descriptive-suffix>-plan.md` with `Status: draft`.

#### b. Tracker write (atomic)

Update the feature's tracker entry — the schema in wave mode for single-plan features carries `ship_unit: wave` and no `waves[]` (the plan IS the only wave):

```yaml
- id: "<SPEC_ID>"
  phase: plan
  spec: .forge/specs/<SPEC_ID>-<suffix>-spec.md
  plan: .forge/plans/<SPEC_ID>-<suffix>-plan.md
  decomposed: false
  ship_unit: wave
  notes: "<refresh — note size assessment recommended <multi|single>, developer chose single-plan in wave mode, plan drafted today>"
```

No `waves[]` written for single-plan in wave mode — the plan IS the wave, and shipping uses the plan's `## Wave Ship State` directly. (The orchestrator treats a single-plan-in-wave-mode feature as having one implicit wave; the dashboard's Wave Drumbeat renders that one wave when the plan is at `phase: ship`.)

Bump the global top-level `last_updated`.

#### c. Final report

```
## Single-plan path complete (wave mode)

- Plan: `.forge/plans/<SPEC_ID>-<suffix>-plan.md` at `Status: draft`
- Wave Ship State: declared in the plan's `## Wave Ship State` section
  (ship_type, ship state on main, ACs satisfied, verification)
- Tracker: feature `<SPEC_ID>` at `phase: plan`, ship_unit: wave, last_updated <today>
- Size assessment: <N> signals tripped, multi-plan was the default recommendation, single-plan chosen

Next step — review the plan in a fresh session:

    /forge-plan-review .forge/plans/<SPEC_ID>-<suffix>-plan.md

When the plan is at `Status: approved`, run `/forge-deliver <SPEC_ID>` to
ship the single wave.
```

**STOP. End the assistant turn here.** Print the fenced block and exit. Do NOT auto-invoke `/forge-plan-review`. The developer initiates the review in a fresh session.

### 5. Multi-plan branch — Decomposition Plan authoring

If the developer picks multi-plan:

#### a. Propose slicing principle

**Strong default: `capability`.** A wave should be a vertical capability slice — one user-facing capability shipped DB-through-UI in one wave — NOT a layer cake (Wave 1 schema, Wave 2 API, Wave 3 UI). Layer cuts maximize same-wave file disjointness but compromise the ship-unit checklist's C3 (flag-or-inert) and C4 (verifiable increment), and the project's code-quality conventions (a wave that ships only a data entity without a service or endpoint is functionally inert on main and tempts dead-code merges).

Propose `capability` as the recommendation; explain the trade-off; ask the developer to confirm or override. Only fall back to `layer` when:
- The spec is genuinely a substrate / schema-only feature with no user surface (e.g., shared-schema work, audit-table additions)
- The developer asserts and the auto-derive agrees that capability slicing would produce same-wave file collisions that the team cannot resolve with verify-WIs

```
Slicing principles available:
  [capability] — recommended — by user-facing capability (login, registration, password reset); each wave is a vertical DB+API+UI slice shipping one capability end-to-end
  [layer]      — by application layer (DB → data layer → service → endpoint → frontend); use only for substrate-only specs OR when capability cuts produce irresolvable file collisions
  [repo]       — by repo (backend, frontend, infra) with cross-repo contracts pinned; rarely best for wave mode (C3 violation risk is high)
  [ac]         — one workitem per acceptance criterion (rarely best — fine-grained)

Recommended: [capability]. Override? [capability | layer | repo | ac | other]
```

Confirm. Record in the Decomposition Plan's `## Decomposition Strategy` section, including which alternatives were considered and why rejected.

#### a.2. Fixture / seed-data check (front-loading)

**Before proposing waves**, scan the spec for fixture / seed-data / migration prep signals:

| Signal | Search | Front-load action |
|---|---|---|
| Seed data tables (lookup, reference data) | spec body for "seed", "reference data", "lookup table", "static data" | Surface in Wave 1's WI inventory; data migration WI typically T1 |
| E2E test fixtures (role logins, sample tenants, sample records) | spec body for "test user", "test tenant", "fixture", "demo data"; T-E2E section if present | Surface as a Wave 1 sub-WI OR as a per-environment seeder; do NOT defer to T-E2E wave |
| Demo data for stakeholder review | spec body for "demo", "preview" | Surface in Wave 1 if any wave's verify-WI will need them |
| Auth roles / permissions migrations | spec body for new roles, permissions, role-grant flows | Wave 1 — downstream WIs cannot test without them |
| Pre-existing migrations from upstream features | dependency specs in `blocked_by` | Confirm they're on main already (deps must be at `phase: ship`/`done`); if not, halt + flag at step 1 |

If any signal hits, propose a Wave 1 sub-WI for fixtures BEFORE proposing the rest of the wave inventory. Reasoning: the spec's T-E2E wave is the last to ship; if fixtures aren't migrated in early, the T-E2E suite blocks at the merge-to-main gate with a "fixtures missing" failure. Front-loading them in Wave 1 keeps every wave's verify-WI testable end-to-end as it ships.

Record the front-loaded fixture WI in the Decomposition Plan's `## Decomposition Strategy` section: *"Wave 1 includes WI-1.X fixture seeding because the spec requires <fixtures-list> for T-E2E coverage; deferring would block the T-E2E wave on missing seeds."*

#### b. Propose DAG, inventory, shared-contracts inventory, AC coverage, Test Strategy Map, Wave Ship Plan

Walk through the proposals with the developer. After each, accept feedback and iterate before moving to the next — confirm explicitly before advancing. The Decomposition Plan is deliberately thin — file paths, contract shapes, and implementation strategy are all per-sub-WI plan decisions, NOT Decomposition Plan decisions.

1. **DAG**: propose a `graph TD` Mermaid diagram showing workitems and their `depends_on` edges. Use generic IDs at this step. Get developer confirmation.

2. **Workitem inventory**: propose a table with columns: ID, title, type, wave, **tier**, depends_on, **scope summary**. Compute waves from the DAG. **Wave 1 = the first shipping wave** (containing items with no upstream deps); wave N = items whose deps are all in waves <N. Rename IDs to `<SPEC_ID>-WI-<wave>.<index>` format.

   No Key WI takes wave 1. The Decomposition Plan is structurally separate — it sits at `features[].decomposition_plan`, not inside `waves[]`.

   Assign a tier using:

   | WI characteristic | Tier |
   |---|---|
   | Migrations, entity definitions, pure data structures, config — no service logic, no API surface, no UI | T1 |
   | Service layer, API controllers, repositories, backend-only | T2 |
   | Frontend pages/components, full-stack WI that closes a user-visible AC testable with prior-wave WIs already on main | T3 |
   | Dedicated E2E workitem (see step 5.b.6) | T-E2E |

   **Smell check**: if the inventory contains only 1 sub-WI, pause and warn: *"Your slicing produced only 1 sub-WI. A Decomposition Plan + 1 sub-WI is structurally identical to a single-plan with decomposition overhead. Back out to single-plan, or re-do slicing to produce ≥2 sub-WIs?"* On `back out`, discard proposals and restart at step 4. On `proceed`, record the reason in `## Notes`.

3. **Shared-contracts inventory + coupling classification (L-027)**: propose a table naming every cross-WI contract. Columns: contract name, **owning WI**, **consumed by**, **Coupling**. **Do NOT pin shapes here.** Shapes are locked by the owning WI's approved plan; consumers cite that plan, not this Decomposition Plan.

   **Coupling classification is load-bearing for dispatch correctness.** For each shared contract, classify the owner↔consumer relationship:

   | Coupling | When | Dispatch consequence |
   |---|---|---|
   | `seam` | Owner and consumers are in **different repos / modules / languages** and integrate over a JSON/HTTP (or other serialized) contract — they compile independently. | Safe to dispatch all WIs **parallel-from-`main`** (empty within-wave `depends_on`, `base_branch: main`). Freeze the seam shape with a contract before plan authoring (`/forge-deliver` Step 0). |
   | `compile` | Owner and a consumer are in the **same repo / module / language** and the consumer references the owner's types/classes **at compile time**. | **Parallel-from-`main` is UNSAFE** — the consumer cannot compile (and the pre-commit/CI compile gate blocks even a commit) until the owner's symbols exist. Resolve by EITHER (a) declaring a within-wave `depends_on: [<owner-WI>]` and **stacking** the consumer's branch on the owner's (`base_branch: <owner branch>`, not `main`), OR (b) placing owner and consumer in **separate waves**. |

   This is the L-027 detector. The cheap test: **a shared contract whose owner and consumer are in the same repo is a compile coupling; cross-repo is a JSON seam.** The default invariant — "all `type: sub` WIs in a wave branch from `main` in parallel with empty within-wave `depends_on`" — holds ONLY for cross-repo seams. Never assume it for shared compile-time types.

   For every `compile` coupling, record the resolution: set the consumer WI's `depends_on` and `base_branch` (stacking option a) in the inventory + tracker, OR move the consumer to a later wave (option b) and update the DAG. Surface the classification to the developer for confirmation — a mis-classified `seam` that is really a `compile` coupling produces "cannot find symbol" failures at dispatch that block the wave.

4. **AC coverage**: propose a `WI → AC-IDs` table. Cross-cutting ACs get a dedicated row. The union must cover all spec ACs — gaps are Blocker-class.

5. **Verify-WI auto-propose (per-wave integration)**: per wave, scan the wave's WI inventory for cross-stack parallelism that needs integration testing:

   | Detection signal | Auto-propose |
   |---|---|
   | Wave contains ≥1 backend-touching WI AND ≥1 frontend-touching WI (per each WI's Stack Profile / touched repos), AND the wave's ship-state includes a user-facing flow that wires them | Add a `type: verify`, `tier: T3` WI to this wave with `depends_on: [<BE-WI>, <FE-WI>]`. ID: `<SPEC_ID>-WI-<wave>.<next-index>`. Title: `Verify — <wave capability>`. Scope: a **two-phase seam gate** on one branch — **Phase 1** API/contract-level integration smoke (`seam-test-implementer`, no browser) proving BE+FE are wired per the frozen contract; **Phase 2** (only if Phase 1 passes) a **wave-scoped browser e2e** (`e2e-test-implementer`) for this wave's capability. The cheap API check fails fast before the browser run. (Distinct from the final T-E2E `type: e2e` WI, which is the full cross-wave spec suite.) |
   | Wave has only backend WIs OR only frontend WIs (single stack) | No verify-WI. The backend WI's integration tests or the frontend WI's WI-scope tests cover verification. No contract is authored either (no BE↔FE seam). |
   | Wave has multiple backend WIs with shared contracts they all consume (e.g., a contract owner + 2 consumers) | Optional verify-WI for contract-conformance smoke (`tier: T2`, single-phase — `seam-test-implementer` only, no browser Phase 2). Propose; let developer decide. |

   > **Seam marker for contract-first integration.** A `type: verify` WI is the signal that this wave has a BE↔FE seam needing a frozen contract. `/forge-deliver` Stage 7 Step 0 invokes `forge-contract-author` for exactly the waves that carry a verify-WI — the contract and the verify-WI fire on the same seam set by construction. The contract (`.forge/plans/<SPEC_ID>/<SPEC_ID>-Wave-<wave>-contract.md`) freezes the seam shape before parallel plan-authoring; the verify-WI's Phase 1 proves the running system conforms to it post-integration, and (for T3) Phase 2 proves the wired flow works in the browser.

   The verify-WI has a few important properties:
   - **Within-wave deps allowed** — verify-WIs MAY declare `depends_on: [<sibling-id>]` within the same wave. Within-wave `depends_on` is otherwise reserved for compile-coupled consumers (step 5.b.3); `type: verify` is the other allowed case.
   - **Dispatched after Pass-1 integration, two-phase** — `type: sub` WIs dispatch first (parallel) and integrate into the wave branch (`/forge-deliver` Pass 1); the verify-WI then runs on that integrated wave branch: **Phase 1** to `seam-test-implementer` (API seam check) → on pass → **Phase 2** (T3 only) to `e2e-test-implementer` (wave-scoped browser e2e, same branch). On a Phase-1 seam defect, the seam-test-implementer emits a root-cause report that drives the orchestrator's bounded auto-repair loop (the D11 loop) — in-wave defects auto-fix via the owning implementer; pre-existing-code regressions and contract defects escalate. The cheap API Phase 1 is sequenced AHEAD of the browser Phase 2 (and the final-wave `type: e2e` suite) so a seam shape/flow failure short-circuits before any expensive browser run.
   - **Owns smoke ACs, not authoritative ones** — the verify-WI's `## Acceptance Criterion Coverage` row uses `Ownership: smoke`; the BE-WI or FE-WI it depends on owns the authoritative test (e.g., a perf NFR's smoke is owned by the verify-WI, but the authoritative perf bench lives on the BE-WI).
   - **Auto-proposed; developer may decline** — propose via `AskUserQuestion`. Developer can say "no, we'll cover integration in a sibling WI's WI-scope browser test" — that's their call.

   *Why this exists:* an early validation pass surfaced that when a BE-WI and FE-WI run in parallel, neither agent has the full picture (the backend works against the contract, the frontend works with mock data per the contract). Without a verify-WI, integration falls on the orchestrator at wave-merge time — overwhelming for a session already orchestrating dispatch + tracker writes + halt-and-resume. A verify-WI carries this load explicitly.

6. **Test Strategy Map + T-E2E WI**: the T-E2E WI in wave mode is the **final wave**, not a special integration step. The T-E2E PR is just a regular wave PR.

   **a. T-E2E WI smell-check**: scan the spec's ACs for user-visible behavior. If any exist, add a T-E2E workitem to the inventory as the final wave (`<SPEC_ID>-WI-<N+1>.1`, title `E2E — <Feature Title>`, type `e2e`, tier `T-E2E`, depends on all T3 WIs and verify-WIs from prior waves). Update the DAG and inventory. If no user-facing ACs exist, note in `## Notes`: "No T-E2E WI — spec has no user-facing acceptance criteria."

   **b. Test Strategy Map**: propose the per-WI tier table for the `## Test Strategy Map` section. Confirm. Also confirm the spec branch name: `feature/<SPEC_ID>-<description>` (mirroring the spec file suffix).

7. **Per-WI Success Criteria**: for every WI in the inventory (sub, verify, e2e), derive a one-line verifiable Success Criterion from:
   - The AC(s) this WI owns (from the AC Coverage table) — for `sub` WIs, the authoritative ACs; for `verify` WIs, the smoke ACs
   - The wave's ship-state one-liner (where this WI fits into the wave's user-observable change)
   - For E2E WIs: "Full browser E2E suite green against wave-N branch on `main`"

   Add to the Workitem Inventory's `Success criteria` column. This column is passed VERBATIM by `/forge-deliver`'s impl-agent dispatch to each agent as the agent's `# Success Criteria` block — the agent uses it as its halt-condition (if subtasks done but criteria unmet → halt + escalate).

   *Why this exists:* an early validation pass surfaced that impl agents need explicit success criteria from the orchestrator. Without them, agents over-implement (writing tests for ACs they don't own) or under-implement (declaring done when only some of the wave's responsibilities are covered). The orchestrator giving each agent its definition-of-done up-front + the agent's plan codifying it in `## Success Criteria` = consistent, scoped completion. See `_TEMPLATE-plan.md`'s `## Success Criteria` section.

8. **Wave-vertical-decision**: for each wave (data + T-E2E if present), compute the ship-unit 4-item checklist signal-by-signal against the wave's WIs + spec body, and propose `ship_type`, `ship_state`, `verification` per wave.

   Per-wave, compute:

   | # | Item | How to compute |
   |---|---|---|
   | C1 | Main stays green — build / lint / existing tests stay green after merge | Heuristic: scan the wave's WIs for tier mix. Pure T1/T2 waves are almost always green-on-main. T3/T-E2E waves need a UI surface that doesn't break existing flows. If the spec has explicit reverse-compat ACs, flag as `✓`. |
   | C2 | No orphan scaffolding | Heuristic: for each prior wave, identify mocks/stubs introduced by it (cite spec body or Decomposition Strategy). For each, confirm this wave either consumes or removes them. If a mock from wave 1 is still unused after wave 2, flag `✗`. |
   | C3 | Flag-or-inert for unfinished surfaces | Heuristic: scan the wave's user-facing WIs (T3). If any introduce a route/screen/button visible to end users that won't be functional until a later wave, require either feature-flag gating or internal-only (no nav entry). If neither, flag `✗`. |
   | C4 | Verifiable increment | Heuristic: produce the smoke command or pointer that observably proves the wave landed. For data-layer waves with no API surface, a `curl` against a probe endpoint or a `SELECT` query suffices. For UI waves, a browser smoke. Pure refactors with no behavioral delta are allowed ONLY when the next wave's correctness depends on the refactor; if so, call it out in `## Notes` and mark `✓` with the deferred-verification note. |

   **For each wave, propose**:

   ```
   Wave <N>:
     ship_type:      vertical | monolithic
     ship state:     <one-line active voice>
     verification:   <smoke command or "see WI plans">
     checklist:      C1: ✓ | C2: ✓ | C3: ✓ | C4: ✓
     (or)
     monolithic_reason: <one-sentence legitimate reason if ship_type=monolithic>
   ```

   **MANDATORY — present each wave proposal via `AskUserQuestion`** to the developer for accept/override. Auto-derived proposals are review surfaces, not declarations. The developer's explicit selection is the lock.

   Question shape per wave (verbatim labels):

   | Field        | Value                                                                                                                              |
   |--------------|------------------------------------------------------------------------------------------------------------------------------------|
   | question     | "Wave `<N>` ship declaration — proposed `<ship_type>` with state `<ship state>`. Accept, override, or modify?"                    |
   | header       | "Wave `<N>` ship"                                                                                                                  |
   | multiSelect  | false                                                                                                                              |
   | option 1     | label: "Accept proposal as-is"  /  description: "Lock the auto-derived `ship_type` + ship state + verification + checklist."     |
   | option 2     | label: "Override ship_type"  /  description: "Flip ship_type (vertical↔monolithic). Will prompt for the new reason if monolithic." |
   | option 3     | label: "Modify ship state or verification"  /  description: "Keep ship_type, edit the ship state one-liner or verification command." |
   | option 4     | label: "Edit checklist items"  /  description: "Change which of C1–C4 are satisfied. Will revisit ship_type if any flips to ✗."  |

   Iterate per wave until the developer confirms. Record the locked declaration in the Wave Ship Plan table draft.

   **Monolithic-reason validation**: if any wave is declared `monolithic`, require a one-sentence `reason` and check it against the illegitimate-reason patterns: "didn't want to slice it", "easier this way", "would take longer", "couldn't think of a clean cut". If a match, push back: *"`<reason>` matches an illegitimate-reason pattern. Propose a cleaner cut instead, or rephrase the reason to articulate why a vertical slice isn't possible (schema migration with no safe intermediate state, security-sensitive refactor, irreversible data transformation)."* Re-ask.

   **`Depends on waves` column** — compute per wave from the DAG: for each wave N, the set of upstream waves containing any WI that any of wave N's WIs depend on. Defaults to `[N-1]` for purely linear features; populate explicitly when the DAG produces a non-linear shape (fork-join across waves). Wave 1 has empty deps.

**Out-of-scope at the Decomposition Plan level** (deliberate):
- File ownership map (each sub-WI's `## Files to Modify` is where files land)
- Shared-contract shapes (the owning sub-WI's plan locks the shape; consumers reference that plan)
- Per-WI implementation strategy (each sub-WI's `## Approach`)
- Class names, method signatures, package layout (each sub-WI's plan)

#### c. Verify the existence of `_TEMPLATE-decomposition-plan.md`

```bash
DECOMP_TEMPLATE=".forge/plans/_TEMPLATE-decomposition-plan.md"
[ -f "$DECOMP_TEMPLATE" ] || {
  echo "Decomposition Plan template not found at $DECOMP_TEMPLATE."
  echo "This command depends on the template being in place."
  echo "Add the template before re-invoking. Aborting."
  exit 1
}
```

#### d. Write the Decomposition Plan

Use `_TEMPLATE-decomposition-plan.md` as the starting shape. Fill required sections:

- `## Context` — one paragraph naming the spec and the size-assessment signals that justified multi-plan.
- `## Decomposition Strategy` — slicing principle + rejected alternatives.
- `## Wave Dependency Graph` — wave-level mermaid `graph TD` (wave nodes, not WI nodes) + a "Waves that can run in parallel" bullet list. Edges encode the cross-wave dep relation (`waves[N].depends_on`). The orchestrator reads this for next-ready selection. Required.
- `## Workitem Dependency Graph` — within-wave WI-level structure shown as mermaid subgraphs per wave, with verify-WI deps (within-wave) and cross-wave T-E2E deps. Edges may only flow: (a) sibling-to-verify within a wave, (b) sibling-to-compile-coupled-consumer within a wave (L-027), or (c) lower-wave to higher-wave. Required.
- `## Workitem Inventory` — the table from step (b.2) with `tier` + the new `Success criteria` column populated from step (b.7); include the T-E2E WI row if present AND any verify-WIs from step (b.5).
- `## Shared Contracts` — owner+consumers+`Coupling` table from step (b.3).
- `## Acceptance Criterion Coverage` — `WI → AC-IDs` table from step (b.4) WITH the structured `Ownership` column (`full | smoke | authoritative | split-across`) + coverage-verification line. The `smoke` / `authoritative` pair captures the verify-WI vs sub-WI ownership split.
- `## Test Strategy Map` — tier table from step (b.6) + Spec branch and E2E test path lines.
- `## Wave Ship Plan` — one row per wave from step (b.8), columns: `Wave | Depends on waves | ship_type | Ship state on main | Verification | C1 | C2 | C3 | C4 | Monolithic reason`.
- `## Progress` — one drafted/approved pair per sub-WI (including T-E2E if present) + terminal advance row.
- `## Failed Approaches` — empty initially.
- `## Review Checklist` — copy the template's checklist items verbatim (left unchecked). `/forge-plan-review` ticks them and sets `> Sign-off` at approval; `guard-plan-approval.sh` blocks `Status: approved` while any box is unchecked or `Sign-off` reads `PENDING`.
- `## Notes` — empty initially (or populated with deferred-verification notes from C4 reasoning if applicable).

Write to `.forge/plans/<SPEC_ID>/<SPEC_ID>-decomposition-plan.md` with header:

```markdown
# <Feature Title> — Decomposition Plan

> Spec: `.forge/specs/<SPEC_ID>-<suffix>-spec.md`
> Type: decomposition-plan
> Status: draft
> Author: <git config user.name>
> Sign-off: PENDING
> Date: <today>
> Spec branch: `feature/<SPEC_ID>-<description>`   <!-- omit if no user-facing ACs -->
```

Create the `.forge/plans/<SPEC_ID>/` directory if it doesn't exist.

#### e. Tracker write (atomic) — NESTED schema

This write is **atomic**: feature entry + decomposition_plan + every wave + every workitem entry must land together. If any part fails, roll back.

```yaml
- id: "<SPEC_ID>"
  phase: workitem-decompose           # the orchestrator's state is "decomposition authored"
  spec: .forge/specs/<SPEC_ID>-<suffix>-spec.md
  plan: null                          # plans live under waves[].workitems[]
  decomposed: true
  spec_branch: "feature/<SPEC_ID>-<description>"   # omit (or null) if no user-facing ACs
  ship_unit: wave                     # locked at decomposition time, immutable thereafter

  decomposition_plan:                 # sibling of waves[], NOT nested inside it
    path: ".forge/plans/<SPEC_ID>/<SPEC_ID>-decomposition-plan.md"
    status: draft                     # mirrors file header; flips to approved via /forge-plan-review

  waves:                              # nested — wave is the structural container
    - wave: 1                         # integer, 1-indexed at first shipping wave
      status: planned                 # planned | in-progress | pr-open | merged
      merged_at: null
      depends_on: []                  # wave numbers this wave depends on; computed from DAG (see Wave Ship Plan)
      workitems:
        - id: "<SPEC_ID>-WI-1.1"
          title: "<title from inventory>"
          type: sub                   # sub | verify | e2e
          tier: T1                    # T1 | T2 | T3 | T-E2E
          plan_path: null             # not authored yet
          plan_status: backlog        # backlog | draft | in-review | approved
          impl_status: pending        # pending | dispatched | pr-open | wave-closed
          branch: null                # set by /forge-worktree-up
          base_branch: "main"         # main for cross-repo seam sub-WIs; the OWNER's branch
                                      #   for a same-repo compile-coupled consumer (L-027, step 5.b.3)
          touched_repos: []           # set by the sub-WI's plan
          depends_on: []              # empty for a cross-repo seam sub-WI; [<owner-WI>] for a
                                      #   same-repo compile-coupled consumer (L-027)
        - id: "<SPEC_ID>-WI-1.3"
          title: "Verify — <wave 1 capability>"
          type: verify                # verify-WI auto-proposed by step 5.b.5 when BE+FE parallel
          tier: T3                    # verify-WIs are typically T3 (two-phase: seam-test API check → e2e wave-scoped browser test)
          plan_path: null
          plan_status: backlog
          impl_status: pending
          branch: null
          base_branch: "main"
          touched_repos: []
          depends_on: ["<SPEC_ID>-WI-1.1", "<SPEC_ID>-WI-1.2"]   # within-wave deps ALLOWED for type: verify
        # ... more wave-1 WIs ...
    - wave: 2
      status: planned
      merged_at: null
      depends_on: [1]                 # from DAG analysis
      workitems:
        - id: "<SPEC_ID>-WI-2.1"
          ...
    # ... more waves; include T-E2E wave as the final entry if present ...

  notes: "<refresh — note size assessment outcome, slicing principle chosen, N sub-workitems across M waves, Decomposition Plan drafted today, wave ship plan locked>"
```

**NOT written to tracker** (derived or in the plan): `pr_url`, `ship_type`, `ship_state`, `verification`, `monolithic_reason`. All available from the Decomposition Plan or `gh pr list`.

Bump the global top-level `last_updated`.

Use `yq` if available (cleaner YAML edits); otherwise plain Edit on the YAML.

#### f. Final report

```
## Decomposition Plan authored — awaiting review

- Decomposition Plan: `.forge/plans/<SPEC_ID>/<SPEC_ID>-decomposition-plan.md` at `Status: draft`
- Tracker: feature `<SPEC_ID>` at `phase: workitem-decompose`, ship_unit: wave, decomposed: true
- Waves: <N> shipping waves (wave 1: <M1> WIs, wave 2: <M2> WIs, ...; T-E2E wave: <yes|no>)
- Total sub-workitems registered (plan_status: backlog): <total>
- Slicing principle: <name>; spec branch: `feature/<SPEC_ID>-<description>`
- Wave Ship Plan locked: all <N> waves declared (vertical: <count>, monolithic: <count>)

Next steps:

1. Review the Decomposition Plan in a fresh session:

       /forge-plan-review .forge/plans/<SPEC_ID>/<SPEC_ID>-decomposition-plan.md

   Plan-reviewer §11 (Wave Vertical-Shipping Audit) runs on this file —
   it re-validates the ship-unit checklist per wave and flags any drift.

2. Once the Decomposition Plan is approved, create the spec branch
   (run from the workspace parent directory):

       git -C <backend-repo> checkout -b feature/<SPEC_ID>-<description> main
       git -C <frontend-repo> checkout -b feature/<SPEC_ID>-<description> main
       git -C <backend-repo> worktree add worktrees/<SPEC_ID>/<backend-repo> feature/<SPEC_ID>-<description>
       git -C <frontend-repo> worktree add worktrees/<SPEC_ID>/<frontend-repo> feature/<SPEC_ID>-<description>

   (Omit if spec has no user-facing ACs. See .claude/rules/git-conventions.md → Spec Branches.)

3. Re-invoke this command to receive the WAVE-1 authoring brief:

       /forge-wave-decompose <SPEC_ID>

Each re-invocation emits the handoff for ONLY the next ready wave —
one wave at a time. Sub-WI plans carry NO `## Wave Ship State` section
(the Decomposition Plan's `## Wave Ship Plan` table owns it).
```

**STOP. End the assistant turn here.** Print the fenced block and exit. Do NOT auto-invoke `/forge-plan-review` or chain into another `/forge-wave-decompose` call. The developer opens a fresh session, runs `/forge-plan-review <decomposition-plan-path>`, and after approval re-invokes `/forge-wave-decompose <SPEC_ID>` (with the spec ID argument explicitly typed) themselves.

### 6. Multi-plan branch — Iterative wave dispatch (re-invocation with `decomp-approved-dispatch-wave`)

After Decomposition Plan approval the command is re-invoked **once per wave**. Each invocation:

- verifies the Decomposition Plan is at `Status: approved`,
- reads the tracker for the feature's `waves[]`,
- computes wave-readiness state,
- emits the handoff for **only the next ready wave** (or a terminal report),
- exits.

#### a. Verify Decomposition Plan header

```bash
DECOMP_STATUS=$(grep -m1 '^> Status:' "$DECOMP_PLAN_PATH" | sed 's/.*Status: //; s/[[:space:]]*$//')
[ "$DECOMP_STATUS" = "approved" ] || {
  echo "Decomposition Plan at $DECOMP_PLAN_PATH is at Status: $DECOMP_STATUS, not approved."
  echo "Run /forge-plan-review on it first, then re-invoke this command."
  exit 1
}
```

#### b. Reconcile Decomposition Plan tracker entry

Mirror the Decomposition Plan's approved status into the tracker:

```yaml
decomposition_plan:
  status: approved        # mirrors file
```

Bump `last_updated`.

Then **reconcile each sub-WI's `plan_status` against on-disk state**: for each WI across all waves, if a plan file exists at its expected path and the file's `Status:` header is `draft`, update its tracker `plan_status: backlog → draft` (and set `plan_path` if not already set). `Status: approved` flips are owned by `/forge-plan-review`, not this command.

#### c. Compute wave-readiness state

For each wave w in ascending order (wave 1, 2, ...):

```
sub_wis = [waves[w].workitems]
states = collect plan_status across sub_wis

WAVE_PLANS_COMPLETE = all states == "approved"
WAVE_PLANS_READY    = any state in {"backlog", "draft"} AND all waves in waves[w].depends_on are WAVE_PLANS_COMPLETE
WAVE_PLANS_IN_REVIEW = any state == "draft" (a plan is drafted but not approved)
WAVE_PLANS_BLOCKED  = any state in {"backlog", "draft"} AND some dependency wave is not WAVE_PLANS_COMPLETE
```

Find the lowest-numbered wave that is WAVE_PLANS_READY. Branching:

| State | Action |
|---|---|
| All waves WAVE_PLANS_COMPLETE | Terminal — step 6.e |
| Found WAVE_PLANS_READY wave w | Emit wave-w handoff — step 6.d |
| No READY but some IN_REVIEW | Print: *"Wave `<w>` is in review — sub-WI(s) [list] are at `plan_status: draft`. Run `/forge-plan-review` on each before re-invoking."* Exit. |
| BLOCKED with no READY | Print diagnostic naming the blocked wave and the unapproved upstream dependency waves. Exit. |

#### d. Emit wave handoff

For the READY wave, emit a per-WI authoring brief listing only WIs in this wave at `plan_status` in `{backlog, draft}`:

```
## Decomposition Plan approved — Wave <N> handoff

Decomposition Plan: `.forge/plans/<SPEC_ID>/<SPEC_ID>-decomposition-plan.md`  (Status: approved)
Wave <N> Ship Plan (from Decomposition Plan):
  ship_type:      <vertical | monolithic>
  ship state:     <one-line>
  verification:   <smoke command or "see WI plans">
  (monolithic_reason if applicable: <reason>)
Wave <N> contains <M> sub-workitem(s):

────────────────────────────────────────────────────────────────────────
<SPEC_ID>-WI-<N>.<i> — <title>
  Status:        plan_status: <backlog|draft>
  Tier:          <T1|T2|T3|T-E2E>
  Depends on:    [<upstream WI IDs, with pointers to their approved plans>]
  Base branch:   <main, or the owner WI's branch for a compile-coupled consumer>
  Scope:         <scope summary from Decomposition Plan inventory>
  Consumes:      <shared contracts this WI consumes — read the owner's approved plan for the shape>
                   - <contract name> (<coupling>) — owned by WI-<x>, locked in <plan path>
  Owns:          <shared contracts this WI owns — its plan locks these shapes>
                   - <contract name> (<coupling>) — consumed by [<WI IDs>]
  ACs on hook:   <AC-ID ranges from Decomposition Plan's AC Coverage table>

  Next action — open a fresh session at the harness root and:

    1. Draft the plan at:
         .forge/plans/<SPEC_ID>/<SPEC_ID>-WI-<N>.<i>-plan.md
       using `.forge/plans/_TEMPLATE-plan.md`. Fill the `> Key Workitem:`
       header line with the Decomposition Plan path (in wave mode it
       points at the Decomposition Plan). Fill `> WI ID:`.
       DELETE the `## Wave Ship State` section — the Decomposition
       Plan's `## Wave Ship Plan` table owns this wave's ship state.
       Save with Status: draft.

    2. In `## Context`, cite each upstream WI by ID and each shared
       contract this WI consumes, with a pointer to the owner's
       approved plan (shape lives there, not in the Decomposition
       Plan).

    3. In `## Files to Modify`, list the files this plan touches.
       Same-wave file collisions are a Blocker-class finding at
       /forge-plan-review — check sibling WIs in this wave before
       drafting.

    4. Then review the plan:
         /forge-plan-review .forge/plans/<SPEC_ID>/<SPEC_ID>-WI-<N>.<i>-plan.md
       On approval, plan_status flips draft → approved.

────────────────────────────────────────────────────────────────────────
(repeat block per sub-WI in this wave)

After EVERY sub-WI in this wave is at plan_status: approved, re-invoke
this command to advance to the next wave:

    /forge-wave-decompose <SPEC_ID>

Concurrency hint: <Decomposition Plan's Concurrency header, default 3>
— at most <N> sub-WIs in this wave may be drafted in parallel across
fresh sessions.
```

**STOP. End the assistant turn here.** Print the fenced wave-handoff block and exit. Do NOT auto-invoke `/forge-plan-review`, do NOT auto-author any sub-WI plan, do NOT chain into another `/forge-wave-decompose` call. The developer drafts each sub-WI plan in a fresh session and runs `/forge-plan-review` on it themselves.

#### e. Terminal — all sub-WI plans across all waves approved

When every sub-WI is at `plan_status: approved`, do the atomic terminal write:

```yaml
- id: "<SPEC_ID>"
  phase: plan          # advanced from workitem-decompose
  # decomposition_plan + waves[] (with all workitems) retained as audit trail
```

Bump `last_updated`. Emit:

```
## Decomposition complete — feature advanced to phase: plan

All <N> sub-workitem plans approved (across <M> waves):

  Wave 1:
    <SPEC_ID>-WI-1.1  approved   .forge/plans/<SPEC_ID>/<SPEC_ID>-WI-1.1-plan.md
    <SPEC_ID>-WI-1.2  approved   .forge/plans/<SPEC_ID>/<SPEC_ID>-WI-1.2-plan.md
  Wave 2:
    ...
  Wave <last> (T-E2E):
    <SPEC_ID>-WI-<last>.1 approved ...

Feature <SPEC_ID> is now at phase: plan, ship_unit: wave.

Next step — open a fresh session and run:

    /forge-deliver <SPEC_ID>

This launches the wave-ship loop: wave 1 dispatches off main, ships its
PR to main, halts for human merge; re-invoke /forge-deliver after
merge to dispatch wave 2; ... ; last wave merges; Reflect runs.
```

**STOP. End the assistant turn here.** Print the terminal block and exit. Do NOT auto-create worktrees, do NOT auto-launch implementation sessions, do NOT chain into `/forge-deliver`. The developer initiates wave-ship in a fresh session.

## Tracker writes — summary

| Event | Tracker writes |
|---|---|
| Mutual-exclusion guard tripped (step 1) | None — abort; this harness is wave-mode-only. |
| Single-plan branch: plan written | Feature `phase: plan`, `decomposed: false`, `ship_unit: wave`, `plan` path set. No `waves[]`. |
| Multi-plan branch: Decomposition Plan written | Feature `phase: workitem-decompose`, `decomposed: true`, `ship_unit: wave`, `spec_branch` set (if user-facing ACs), `decomposition_plan.{path,status: draft}`, `waves[]` populated with N wave entries each carrying `status: planned`, `depends_on: [...]` from DAG, and `workitems[]` (all at `plan_status: backlog`, `impl_status: pending`; `base_branch: main` for cross-repo seam sub-WIs, the owner branch for compile-coupled consumers). |
| `/forge-plan-review` approves Decomposition Plan | `decomposition_plan.status: draft → approved`. |
| Re-invocation: wave dispatch | Reconcile `decomposition_plan.status: approved`; for each sub-WI whose plan file exists on disk at `Status: draft`, set `plan_status: backlog → draft` + `plan_path`. Emit wave handoff. No `plan_status: approved` flips. |
| Developer drafts sub-WI plan | WI's `plan_status: backlog → draft`, `plan_path` set. |
| `/forge-plan-review` approves sub-WI plan | WI's `plan_status: draft → approved`. |
| Re-invocation: terminal | Feature `phase: workitem-decompose → plan`. `decomposed: true` + `decomposition_plan` + `waves[]` retained. |

The global top-level `last_updated` is bumped on every write.

## Notes

- **Workitem ID format is `<SPEC_ID>-WI-<wave>.<index>`.** Wave 1 is the first shipping wave (no Key WI takes wave 1).
- **Stop discipline at every re-invocation boundary.** Steps 4.c, 5.f, 6.d, 6.e ALL end the assistant turn the moment their fenced report block is printed. Auto-chaining into `/forge-plan-review` or `/forge-deliver` is a recurring bug — its most common failure mode is losing the spec-ID argument.
- **Idempotent and state-aware.** Running twice from `fresh-start` produces the same artifacts. Re-invoking mid-flow picks up at the next pending step.
- **No auto-approval.** This command never flips a plan to `Status: approved`. Plans go through `/forge-plan-review` for approval.
- **Tracker writes are atomic.** Any partial state would mislead leadership.
- **Coupling classification is mandatory (L-027).** Step 5.b.3 classifies every shared contract as `seam` (cross-repo, parallel-from-main) or `compile` (same-repo, stack-or-split). A mis-classified compile coupling dispatched parallel-from-`main` produces "cannot find symbol" failures that block the wave — the consumer cannot reach `impl_status: pr-open` on its own branch. Never assume parallel-from-main for shared compile-time types.
- **Wave dispatch is gated on Decomposition Plan approval.** The state machine refuses to emit any sub-workitem handoff until the Decomposition Plan is at `Status: approved`.
- **One wave per re-invocation.** Step 6's dispatcher is iterative.
- **Decomposition Plan is deliberately thin.** Locks waves, inventory, DAG, shared-contract graph (owner + consumers + coupling — NOT shapes), AC coverage, Test Strategy Map, **and Wave Ship Plan**. Does NOT lock file paths, contract shapes, class/method names, or per-WI implementation strategy.
- **Sub-WI plans in wave mode carry NO `## Wave Ship State` section.** Delete that template stub when drafting. The Decomposition Plan's `## Wave Ship Plan` table owns wave ship state.
- **Wave-vertical-decision is auto-derived, developer-locked.** Step 5.b.8 auto-derives the ship-unit checklist + ship_type + ship state + verification per wave; the developer reviews each wave's proposal via `AskUserQuestion` and either accepts, overrides, or modifies. The developer can override the proposal contents but cannot bypass mandatory-monolithic-reason validation.
- **Foundation specs out of scope.** Hard-coded check at step 1.
- **Manual mode.** Multi-plan operation is developer-driven end-to-end — the developer authors each sub-workitem plan against the Decomposition Plan's locked surface.
- **Scope ends at all-drafts.** Implementation is downstream and out of scope (use `/forge-deliver`).
- **Doctrine reference.** The wave-mode workflow is described in `.forge/forge-harness-framework.md`.
