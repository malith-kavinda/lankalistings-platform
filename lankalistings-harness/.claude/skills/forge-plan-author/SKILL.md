---
name: forge-plan-author
phases: [engineering]
description: "Draft an implementation plan from an approved feature spec (single-plan mode) or an approved workitem (WI mode), grounded in the repos' existing code patterns. Use when a spec or Decomposition Plan is approved and the plan is still a stub. Leaves it at `Status: draft` — `/forge-plan-review` is next."
---

# /forge-plan-author

Per-feature or per-workitem plan-drafting assistant. Reads an approved spec (and, in WI mode, the orchestration artifact + upstream WI plans) and the relevant repo code, then writes a complete plan grounded in existing patterns. Leaves the plan at `Status: draft` for `/forge-plan-review` to audit.

**Stack-neutral by construction.** This skill assumes no framework. Before grounding any decision in repo code, read the touched repo's **Stack Profile** — the repo's `CLAUDE.md` `## Backend Stack` / `## Frontend Stack` section — so the patterns, commands, and idioms you cite match the engagement's actual frameworks, language versions, and test stack rather than a hardcoded assumption. (Same calibration discipline as `plan-reviewer`'s "calibrate per stack".)

## How to Use

```
/forge-plan-author <ticket>                     # single-plan mode
/forge-plan-author <ticket> <wi-id>             # WI sub-plan mode (e.g. PROJ-002 PROJ-002-WI-2.1)
```

`<ticket>` is the feature id, e.g. `PROJ-005`. `<wi-id>` is the full workitem ID, e.g. `PROJ-002-WI-2.1`. (The `<ticket>` / `<ticket>-WI-X.Y` grammar is fixed; only the project's ticket prefix changes.)

If invoked without arguments, print usage and exit.

## When to Use

**Single-plan mode** (`/forge-plan-author <ticket>`):
- The spec at `.forge/specs/<ticket>-*-spec.md` is at `Status: approved`.
- The feature is non-decomposed (`decomposed: false` or field absent in tracker).
- The plan path `.forge/plans/<ticket>-*-plan.md` either doesn't exist or is a stub.

**WI sub-plan mode** (`/forge-plan-author <ticket> <wi-id>`):
- The feature is decomposed (`decomposed: true`) and the orchestration artifact (wave mode: the Decomposition Plan; feature mode: the Key Workitem `<ticket>-WI-1.1`) is at `Status: approved`.
- All upstream WI plans (lower-wave deps) are at `plan_status: approved`.
- The target WI's `plan_path` is null or the file is a stub.
- `/forge-deliver` is at the wave-dispatch stage authoring sub-WI plans.

## When NOT to Use

- The spec is still `draft` or `in-review` — wait for spec approval first.
- In WI mode: the orchestration artifact is not yet approved — wait for its review first.
- In WI mode: this WI has upstream deps whose plans are still `draft` (contract shapes aren't locked yet).
- The plan body is already drafted — even partially. Overwriting risks clobbering human edits.
- Foundation plans (`.forge/plans/foundation/**`) — different conventions, out of scope.

## Inputs read (in order)

**Always:**
1. `.forge/tracker.yaml` `features.<ticket>` — for `blocked_by`, priority, delivery_phase, owner, `decomposed`, `ship_unit` (engagement default at `delivery.ship_unit`, overridden by per-feature `ship_unit`), and the WI inventory: `workitems[]` for legacy `feature` mode, `waves[].workitems[]` for wave mode. Use the shape-agnostic lookup pattern (`features[].workitems[]? // features[].waves[].workitems[]?`) when resolving a specific WI by ID; the higher-level feature fields (`blocked_by`, `priority`, etc.) live at the top of the feature entry regardless of shape.
2. The approved spec (`.forge/specs/<ticket>-*-spec.md`) — every FR, NFR, AC, scope boundary, constraint.
3. `.forge/design/architecture.md` — relevant subsections (the spec's `Constraints` section names which).
4. `<backend-repo>/CLAUDE.md` and `<frontend-repo>/CLAUDE.md` — **read the Stack Profile** (`## Backend Stack` / `## Frontend Stack`) plus repo-specific patterns and `## Common Commands`. These supply the framework, language version, test-runner, and idioms this plan grounds against — do not assume them.
5. `<backend-repo>/src/**` and `<frontend-repo>/src/**` (relevant slice) — grep for likely call-sites of dep-spec types/endpoints. (The actual source roots come from each repo's Stack Profile; the project may organize source differently.) **Distinctly, for a data-layer plan: grep the SUBSTRATE repo for the expected repository/interface symbols BEFORE authoring — confirm each one actually exists.** This is *not* the call-site grep above (that confirms where a type is consumed); this confirms the substrate symbols you ground against are present, and surfaces the MISSING ones whose ownership step 2's `## Shared Contracts` handling must assign.
6. `.forge/plans/_TEMPLATE-plan.md` — the required section schema.
7. `.claude/rules/plans.md` — the lifecycle rules this skill must honor.
8. `.claude/CLAUDE.md` (Boundaries) — the mandatory pre-PR-review + PR-opened subtasks.
9. `.forge/test-strategy.md` — the framework-level tier model (T1 / T2 / T3 / T-E2E).

**WI mode additionally:**
10. The orchestration artifact — scope summary, consumes/owns contracts, ACs assigned to this WI. Path depends on mode:
    - Wave mode: `.forge/plans/<ticket>/<ticket>-decomposition-plan.md` (the Decomposition Plan).
    - Feature mode: `.forge/plans/<ticket>/<ticket>-WI-1.1-plan.md` (the Key Workitem).
    Both files have the same section structure for the parts this skill reads (`## Workitem Inventory`, `## Shared Contracts`, `## Acceptance Criterion Coverage`, `## Test Strategy Map`); only the wave mode file additionally has `## Wave Ship Plan` (not relevant to sub-WI authoring).
11. For each upstream dep WI (from `depends_on`): the approved WI plan at `.forge/plans/<ticket>/<dep-wi-id>-plan.md` — extract the contract shapes this WI consumes.
12. `.forge/specs/<dep>-spec.md` for each feature-level `blocked_by` entry — public contracts consumed by this feature.
13. **Wave mode — the frozen wave contract** (if present): `.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md` for this WI's wave. When it exists at `Status: frozen`, it — not the upstream WI's plan — is the authoritative seam shape (contract-first integration). A backend-WI on the seam declares the endpoints/shapes the contract pins; a frontend-WI on the seam consumes them. The contract is **read-only**; this plan conforms to and cites it, never re-invents it. (See `forge-contract-author`.)

## Procedure

### 1. Validate target and determine mode

```bash
TICKET="<first arg>"
WI_ID="<second arg, or empty>"

SPEC_PATH=$(ls .forge/specs/${TICKET}-*-spec.md 2>/dev/null | head -1)
[ -z "$SPEC_PATH" ] && abort: "No spec at .forge/specs/${TICKET}-*-spec.md."
```

Confirm spec `Status: approved`. Abort otherwise.

**Single-plan mode** (WI_ID empty):
- Determine plan path: swap `-spec.md` for `-plan.md` (e.g. `.forge/specs/PROJ-005-org-mgmt-spec.md` → `.forge/plans/PROJ-005-org-mgmt-plan.md`).
- If plan exists and body beyond template stub is populated, abort with overwrite warning.
- Confirm `decomposed` is false or absent. If `decomposed: true`, abort: *"Feature is decomposed — use `/forge-plan-author <ticket> <wi-id>` to author sub-WI plans."*

**WI sub-plan mode** (WI_ID provided):
- Confirm feature is `decomposed: true` in tracker.
- Determine the **orchestration artifact** based on `ship_unit`:

  ```bash
  ENG_SHIP_UNIT=$(yq '.delivery.ship_unit // "feature"' .forge/tracker.yaml)
  FEAT_SHIP_UNIT=$(yq ".features[] | select(.id == \"$TICKET\") | .ship_unit // \"\"" .forge/tracker.yaml)
  EFFECTIVE_MODE="$ENG_SHIP_UNIT"
  [ -n "$FEAT_SHIP_UNIT" ] && EFFECTIVE_MODE="$FEAT_SHIP_UNIT"

  if [ "$EFFECTIVE_MODE" = "wave" ]; then
    ORCHESTRATION_PATH=".forge/plans/$TICKET/$TICKET-decomposition-plan.md"
    ORCHESTRATION_KIND="Decomposition Plan"
    ORCHESTRATION_STATUS_PATH=".features[] | select(.id == \"$TICKET\") | .decomposition_plan.status"
  else
    ORCHESTRATION_PATH=".forge/plans/$TICKET/$TICKET-WI-1.1-plan.md"
    ORCHESTRATION_KIND="Key Workitem"
    ORCHESTRATION_STATUS_PATH=".features[] | select(.id == \"$TICKET\") | .workitems[] | select(.id == \"$TICKET-WI-1.1\") | .plan_status"
  fi
  ```

  Confirm the orchestration artifact file exists and is at `Status: approved`. Abort with a clear message naming the missing/unapproved file.
- Resolve the WI entry via **shape-agnostic lookup** (search both shapes; first match wins):

  ```bash
  WI_JSON=$(yq -o=json ".features[] | select(.id == \"$TICKET\") | .workitems[]? | select(.id == \"$WI_ID\")" .forge/tracker.yaml 2>/dev/null)
  [ -z "$WI_JSON" ] || [ "$WI_JSON" = "null" ] && WI_JSON=$(yq -o=json ".features[] | select(.id == \"$TICKET\") | .waves[]?.workitems[]? | select(.id == \"$WI_ID\")" .forge/tracker.yaml 2>/dev/null)
  [ -z "$WI_JSON" ] || [ "$WI_JSON" = "null" ] && abort: "WI $WI_ID not found under either flat workitems[] or nested waves[].workitems[] for $TICKET."
  ```

  Abort if `plan_status: approved` already (already authored + approved).
- Determine plan path: `.forge/plans/<ticket>/<wi-id>-plan.md`.
- Confirm all `depends_on` WI plans are at `plan_status: approved` (contract shapes are locked). Use the same shape-agnostic lookup for each dep. If any dep is at `draft` or `backlog`, abort: *"Dep WI `<dep-wi-id>` is at `plan_status: <status>` — contract shapes aren't locked yet. Review and approve it first."*
- If plan exists and body beyond template stub is populated, abort with overwrite warning.

### 2. Read inputs

Walk the Inputs-read list for the active mode. **On turn 1 of grounding, read each touched repo's Stack Profile** (`<backend-repo>/CLAUDE.md` `## Backend Stack`, `<frontend-repo>/CLAUDE.md` `## Frontend Stack`) before citing any pattern, command, or idiom — the plan must reflect the engagement's actual stack, not an assumed one.

**In WI sub-plan mode**, extract from the orchestration artifact (`$ORCHESTRATION_PATH` — either the Decomposition Plan in wave mode or the Key Workitem in feature mode; same internal structure for the sections this skill reads):
- The **scope summary** for this WI (one-line job description from `## Workitem Inventory`).
- The **WI type** from `## Workitem Inventory` — `sub` or `e2e`. T-E2E WIs (`type: e2e`) get the special drafting treatment described in step 3.
- The **tier** for this WI from the `Tier` column in `## Workitem Inventory` (must be one of `T1 | T2 | T3 | T-E2E`).
- The **tier rationale** for this WI from `## Test Strategy Map` (one-sentence reason that explains why the tier fits).
- The **contracts this WI owns** from `## Shared Contracts` (what it produces for consumers — shape will be locked by this plan).
- The **contracts this WI consumes** from `## Shared Contracts` (what it needs from upstream WIs — shapes come from those WIs' approved plans).

For a **data-layer plan**, before locking `## Shared Contracts`, **grep the SUBSTRATE repo for the expected repository/interface symbols this WI grounds against** (per inputs-read item 5). For each symbol that already exists, ground against it; for each **MISSING** symbol, declare the **smallest owner** of it in `## Shared Contracts` — the narrowest WI/layer that can legitimately produce it — rather than silently assuming the substrate provides it. A missing substrate symbol with no declared owner is a contract gap that surfaces only at implementation.
- The **ACs on hook** from `## Acceptance Criterion Coverage` (which spec ACs this WI is responsible for).

Then for each consumed contract, read the owning WI's approved plan and extract the contract shape.

For repo-code grounding, **prefer reading existing files over inventing patterns**. Pick 2–3 representative files per layer and cite them in `## Decisions` as the pattern to follow.

### 3. Draft sections

Write the plan file. If it doesn't exist, create it from `_TEMPLATE-plan.md`, then populate via Edit calls (one section at a time).

**Header:**

*Single-plan mode:*
```markdown
# <feature-title> — Plan

> Spec: `.forge/specs/<ticket>-*-spec.md`
> Status: draft
> Author: <git config user.name>
> Reviewed by:
> Date: <today>
```

*WI sub-plan mode:* write the `> Key Workitem:` field to point at the orchestration artifact resolved in step 1 — in wave mode this is the Decomposition Plan, in feature mode this is the Key Workitem itself. `plan-reviewer` reads this header field as `key_workitem_path` and tier-matches against the artifact's `## Test Strategy Map`, which is structurally the same in both files.

```markdown
# <wi-id> — <wi-title>

> Spec: `.forge/specs/<ticket>-*-spec.md`
> Key Workitem: `$ORCHESTRATION_PATH`   <!-- = `.forge/plans/<ticket>/<ticket>-decomposition-plan.md` in wave mode; `.forge/plans/<ticket>/<ticket>-WI-1.1-plan.md` in feature mode -->
> WI ID: `<wi-id>`
> Type: sub-workitem
> Wave: <wave number>
> Tier: <T1 | T2 | T3 | T-E2E>
> Status: draft
> Author: <git config user.name>
> Reviewed by:
> Date: <today>
```

The `> Key Workitem:` and `> WI ID:` header fields are required for sub-WI plans (they tell `/forge-plan-review` how to resolve the parent orchestration artifact for tier and AC-coverage checks). The `> Tier:` field mirrors the tier assigned to this WI in the orchestration artifact's `## Workitem Inventory` and `## Test Strategy Map` sections — it must match exactly.

**Do not** write a `Reviewed-via:` annotation — `/forge-plan-review` writes it at approval time.

**`## Approach`** — 2–5 paragraphs. Cover: which repos are touched, slice ordering, key abstractions introduced, what's out of scope (deferred to other WIs or follow-up tickets). In WI mode: name the upstream contract shapes this WI builds on (cite the owning WI's plan), and which contracts this WI locks.

**`## UI / Design Adherence`** — **WIs touching user-visible UI only**, **and only if the project has a design reference**. The UI source roots are whatever the frontend repo's Stack Profile declares (e.g. an `app/` + `components/` tree); read it rather than assuming a layout. If a design reference exists (`.forge/design/ui/<design-system>.md` + a prototype/mockup), first read the design-system spec (its token, component, layout, screen, and cross-cutting-convention sections) and the prototype; then declare the semantic tokens, custom components, and screen layouts this WI conforms to, and add **at least one design-conformance bullet to `## Success Criteria`** (e.g. "all new components use the design system's semantic tokens — no hand-picked colors; screens match the prototype"). **If the WI ships a sub-view** (routed detail / `…/[id]` / `…/new` / `…/edit`), declare its back-navigation affordance (breadcrumb or labelled back button per the design system's navigation convention) and add a Success Criterion for it. **Follow the design system's capitalization rule** for all UI text. **For a screen that has a per-screen design reference**, cite that reference file **and** its prototype source, and transcribe the **component tree + arrangement + spacing** — **not just tokens/colors** — naming what composes from what, in what order, with which surface / toolbar / row structure. State explicitly that **the reference is authoritative over the existing app structure**: change the app to match the reference; do **not** preserve the app's structure and only swap colors. Read exact values (sizes, spacing, weights) from the **prototype source**, never from a rounded design-token / CSS-variable export (they round and drift — e.g. 13px vs 14px). For backend-only WIs, or projects with no design reference, delete the section. `plan-reviewer`'s design-conformance dimension gates this.

**`## Decisions`** — a table of specific technical choices. Each decision must cite either a `CLAUDE.md`/architecture rule or an existing repo file:line. **On any choice that touches an Architecture Decision** (read `.claude/CLAUDE.md § Architecture Decisions (DO NOT REVERSE)`), conform to it — if the plan would violate one, STOP and escalate rather than deciding around it.

**`## Subtasks`** — numbered, ordered. Each subtask is small enough to be a single Claude Code session.

In WI mode, scope the subtask list to what THIS WI covers (the scope summary + ACs on hook from the orchestration artifact). Don't duplicate work owned by other WIs.

Order: backend data layer → service → API boundary → tests → frontend client → UI → tests → integration. (Adapt the layer names to the actual stack from each repo's Stack Profile.)

**T-E2E WI special case** — when this WI is `type: e2e` in the orchestration artifact's inventory:
- `## Approach` describes the E2E test architecture (page objects, fixtures, role setup, browsers, parallelism) for the project's `<e2e-framework>`.
- `## Subtasks` is the E2E suite to write — one subtask per AC or per logical test scenario. No functional code subtasks.
- `## Files to Modify` lists only test files (the E2E test directory the frontend repo's Stack Profile names — e.g. an `e2e/` directory by convention) and any `<e2e-framework>` config changes.
- `## Test Approach` declares `Tier: T-E2E` and fills only the **Full E2E Suite** subsection.

**Verify-WI special case (wave mode)** — when this WI is `type: verify` in the Decomposition Plan inventory, it is test-only and a **two-phase gate** on one branch (no functional `src/` subtasks):
- **T3 (two-phase):** `## Test Approach` declares `Tier: T3` and fills BOTH the **Integration Tests** subsection (Phase 1 — API/contract seam tests authored by `seam-test-implementer`, no browser: assert the running endpoints conform to the frozen `<ticket>-Wave-<N>-contract.md` — field shapes, enums, envelope, auth handshake, multi-step flow) AND the **WI-scope E2E (browser)** subsection (Phase 2 — wave-scoped browser e2e authored by `e2e-test-implementer`). A T3 verify-WI plan missing either group is a `plan-reviewer` Important.
- **T2 (single-phase):** `## Test Approach` declares `Tier: T2` and fills only **Integration Tests** (contract-conformance smoke, no browser).
- `## Approach` names the seam (backend-WI ↔ frontend-WI), cites the frozen contract as the assertion ground truth, and notes the two phases. `## Subtasks` are test-authoring only.
- `## Success Criteria` are smoke-level (`Ownership: smoke` in the Decomposition Plan's AC Coverage) — the backend/frontend sub-WIs own the authoritative ACs.

> **Dispatch / execution-decoupling note (load-bearing).** `seam-test-implementer` and `e2e-test-implementer` **author + static-check** their tests only — a dispatched sub-agent is torn down on return and cannot keep dev servers booted or drive a live browser. The persistent **main orchestrator** RUNS the live API-seam and browser suites and owns the run → classify → fix → re-run auto-repair loop. Only the implementer agents (backend/frontend) and the final finalize dispatch self-run their own gates. Do not write subtasks that ask a verify/e2e sub-agent to live-run a suite.

Always append these two final subtasks:

```markdown
### N-1. Pre-PR review
- **What:** Run /forge-pre-pr-review from the worktree session, resolve any Blockers, record verdict in this plan's ## Notes.
- **Files:** this plan's ## Notes section
- **Pattern:** Skill produces verdict block; copy verbatim under "## Pre-PR Review — <wi-id or ticket>" heading in ## Notes.

### N. PR opened
- **What:** /forge-pr-open builds PR body from spec + plan + ## Progress + pre-PR verdict, runs gh pr create, updates tracker.
- **Files:** none (the skill drives gh + tracker)
- **Pattern:** Conservative auto-flow stops here. Human merges after /forge-review-pr <N> + CI green.
```

> **Non-dispatch guardrail (load-bearing).** `/forge-pre-pr-review`, `/forge-test-verify`, and `/forge-pr-open` must run **inline / non-dispatching** — the implementer agent runs them in the finalize path, and Claude Code forbids recursive sub-agent dispatch. Never write a subtask that dispatches a sub-agent to run any of those three.

**`## Files to Modify`** — table with `File`, `Repo`, `Change` columns. Match the union of subtask file references. In WI mode, only files in scope for this WI — no overlap with sibling WIs (same-wave file collisions are a Blocker at `/forge-plan-review`).

**Contracted-seam conformance (wave mode, when a frozen wave contract exists for this WI's seam):**
- In `## Approach` and `## Decisions`, cite `.forge/plans/<ticket>/<ticket>-Wave-<N>-contract.md` as the seam authority — name the endpoints/types this WI owns or consumes per the contract. Do NOT re-derive the shape from an upstream plan; the frozen contract supersedes it.
- In `## Files to Modify`, list the contract as a **read-only** row (`Change: read-only — seam authority, conform to it, never edit`). It is not a file this WI writes; listing it makes the read-only dependency explicit and satisfies the cross-WI consistency gate's contract-conformance check.
- In `## Success Criteria`, emit a **conformance criterion** (per `_TEMPLATE-plan.md`'s contracted-seam examples): backend-WI → "`<endpoint(s)>` responses conform to `<ticket>-Wave-<N>-contract.md`"; frontend-WI → "API client/types for `<endpoint(s)>` match `<ticket>-Wave-<N>-contract.md` — no unchecked casts at the API boundary." This is the definition-of-done the `seam-test-implementer` checks the running seam against. If this WI proves the contract is wrong, that is a contract defect → halt → re-decompose (never edit the frozen contract).

**`## Risks`** — 3–6 bullets. In WI mode, include cross-WI contract shape risks (if upstream WI plans need revision, this WI may need re-drafting).

**`## Test Approach`** — required section per `_TEMPLATE-plan.md`. Drives `/forge-plan-review`'s tier-discipline checks (TC-1..TC-5). The tier vocabulary (T1 / T2 / T3 / T-E2E) is framework-level — see `.forge/test-strategy.md`.

In WI mode, the tier comes from the orchestration artifact's `## Workitem Inventory` table (the `Tier` column for this WI). Reproduce it verbatim — no choosing or guessing.

Write the tier-appropriate subsections, **delete the others** (don't leave empty tables):

| Tier | Required subsections |
|---|---|
| T1 | Unit Tests |
| T2 | Unit Tests + Integration Tests |
| T3 | Unit Tests + Integration Tests + WI-scope E2E (browser) |
| T-E2E | Full E2E Suite only (no functional subsections) |

Header fields under `## Test Approach`:
```
**Tier:** <T1 | T2 | T3 | T-E2E>
**Rationale:** <one sentence — pull from the orchestration artifact's ## Test Strategy Map row for this WI>
```

Every AC this WI is on the hook for (per the orchestration artifact's ## Acceptance Criterion Coverage row) must appear in at least one test row across the populated subsections. Coverage gaps are a Blocker at `/forge-plan-review`.

In single-plan mode, pick whichever tier fits the plan's scope. Most single-plan features are T2 or T3.

**`## Progress`** — one checkbox per subtask. Leave unchecked.

**`### Failed Approaches`** — leave empty.

**`## Notes`** — leave empty.

**`## Wave Ship State`** — wave-mode single-plan features only. Detect mode:

```bash
# Read effective ship_unit (engagement default, overridden by per-feature)
ENG_SHIP_UNIT=$(yq '.delivery.ship_unit // "feature"' .forge/tracker.yaml)
FEAT_SHIP_UNIT=$(yq ".features[] | select(.id == \"$TICKET\") | .ship_unit // \"\"" .forge/tracker.yaml)
EFFECTIVE_MODE="$ENG_SHIP_UNIT"
[ -n "$FEAT_SHIP_UNIT" ] && EFFECTIVE_MODE="$FEAT_SHIP_UNIT"
```

Behavior matrix:

| Mode | Plan type | Action |
|---|---|---|
| `feature` (legacy) | single-plan | **Delete** the `## Wave Ship State` template stub before writing. |
| `feature` (legacy) | sub-WI | **Delete** the stub (legacy sub-WIs never had it). |
| `wave` | single-plan | **Keep** the section and populate every field (this plan IS the only wave). |
| `wave` | sub-WI | **Delete** the stub — the Decomposition Plan's `## Wave Ship Plan` table owns wave ship state for sub-WIs. |

For `wave`-mode single-plan only, populate:

```markdown
## Wave Ship State

- **ship_type:** vertical | monolithic        <!-- propose vertical by default; flip to monolithic only when the vertical-shipping checklist (C1–C4) cannot be satisfied -->
- **Ship state on main:** <one-line active voice — derived from the spec's headline AC>
- **Acceptance criteria satisfied:** <list every AC ID from the spec — single-plan covers them all>
- **Verification:** <smoke command(s) — pull from the plan's ## Test Approach if available, else propose a smoke command per the spec's primary AC, using the repo's Stack Profile commands (e.g. <backend-check-cmd> / <e2e-cmd-scoped> / a curl against the headline endpoint)>
- **Monolithic reason** (only if ship_type: monolithic): <legitimate reason — schema migration with no safe intermediate state, security-sensitive refactor, irreversible data transformation>
- **Feature-flag gating** (optional): <flag name + reason it's gated, OR delete the line>
```

`plan-reviewer`'s Wave Ship State audit (WS-1 + WS-5) checks this section's presence and content.

### 4. Update tracker

**Single-plan mode:**
- `plan: null` → `plan: <plan-path>`
- `phase` stays at `plan`
- `notes: "Plan drafted via /forge-plan-author. <N> subtasks across <repos>. Awaiting /forge-plan-review."`

**WI sub-plan mode:** write at the SAME shape the WI was located at in step 1 (flat OR nested; never both — same discipline as `forge-worktree-up`).

- Flat shape (legacy `feature` mode): `features[].workitems[] | select(.id == "<wi-id>") | .plan_path` ← `<plan-path>`, `.plan_status` ← `draft`.
- Nested shape (wave mode): `features[].waves[].workitems[] | select(.id == "<wi-id>") | .plan_path` ← `<plan-path>`, `.plan_status` ← `draft`.
- `notes: "WI <wi-id> plan drafted via /forge-plan-author. <N> subtasks, <repos>. Awaiting /forge-plan-review."`

Bump the global `last_updated`.

### 5. Final report

```
## Plan drafted — <ticket or wi-id>

- Plan: <PLAN_PATH> (Status: draft)
- Spec: <SPEC_PATH> (approved)
<WI mode only:>
- Orchestration artifact: <ORCHESTRATION_PATH> (approved — Decomposition Plan in wave mode, Key Workitem in feature mode)
- Tier: <T1 | T2 | T3 | T-E2E> (from the orchestration artifact's Workitem Inventory)
- ACs on hook: <AC-IDs from the AC Coverage table>
- Contracts locked by this plan: <list or "none">
- Contracts consumed (shapes from upstream plans): <list or "none">
- Sections written: Approach, Decisions (<N> rows), Subtasks (<M> incl. pre-PR + PR-opened),
  Files to Modify (<K> files), Risks (<R> bullets), Test Approach (<tier> with <X> test rows)
- Tracker: updated (plan_path set, plan_status: draft)

Next: /forge-plan-review <PLAN_PATH> [--auto-approve-on-clean]
```

## Notes

- **No plan→approved transition.** The skill leaves `Status: draft`. `/forge-plan-review` is the only path to `approved`.
- **Stack-neutral grounding.** This skill hardcodes no framework. The patterns, commands, and source layout it cites come from each touched repo's Stack Profile (`CLAUDE.md` `## Backend Stack` / `## Frontend Stack`) — read it on turn 1 of grounding, then ground against it.
- **WI mode scoping.** Subtasks and Files-to-Modify are scoped to the WI's assigned ACs and contracts. `/forge-plan-review` cross-checks that no same-wave sibling WI claims the same file.
- **Contract shapes are locked by the owning WI's approved plan.** This skill reads them from the upstream plan but doesn't re-pin them. If the upstream plan's shape changes after this plan is drafted, a plan revision is required here too.
- **Repo-code grounding is mandatory.** Every decision and "Pattern:" line must cite a concrete repo path or `CLAUDE.md` rule. Plans without grounding fail Pass 1 of `/forge-plan-review`.
- **Pre-PR-review and PR-opened subtasks are non-optional.** The orchestrator depends on these existing to drive the conservative auto-flow's final stages.
- **Tier comes from the orchestration artifact, not from this skill.** In WI mode, the tier (T1/T2/T3/T-E2E) is set during decomposition by `/forge-wave-decompose` and lives in the Decomposition Plan's (or Key Workitem's) `## Workitem Inventory` and `## Test Strategy Map`. This skill mirrors it into the sub-WI plan's header and `## Test Approach` section — it never picks the tier.
- **T-E2E WI plans are test-only.** No functional subtasks. The E2E suite covers the full spec; prior WIs' code is already in this branch's working tree via the wave-stacking chain (L-027: same-repo compile coupling stacks on the owner branch as base; cross-repo seams branch parallel from `main`).
- **Idempotent.** Aborts cleanly on an in-flight or approved plan.
