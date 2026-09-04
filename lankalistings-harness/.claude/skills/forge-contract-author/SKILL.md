---
name: forge-contract-author
phases: [engineering]
description: "Author or refresh the backend↔frontend seam contract for ONE wave, then auto-validate and flip it to `Status: frozen` so the wave's plans are authored against a pinned seam. Use before a wave's parallel plan fan-out, or when a re-decompose changed the seam shape. Wave mode only."
---

# /forge-contract-author

Serial, per-wave, interface-only authoring step that produces the **frozen contract** the wave's backend-WI and frontend-WI both build against. It is the layer that moves contract/shape drift (field name/casing, nullability, enum values, date/number formats, error-body shape, pagination envelope, auth handshake) **left** — out of the late, expensive `type: verify` halt and into a cheap artifact frozen before parallel impl begins.

A contract is a **seam-level** artifact owned by neither WI (proposal D2). `decompose` is the wrong altitude (structural, would be overloaded with deep API design); `plan-author` is the wrong cardinality (per-WI + parallel = can't coordinate a shared artifact). This skill is the single serial owner, scoped to one wave's seams.

## How to Use

```
/forge-contract-author <ticket> <wave>
```

`<ticket>` is the feature id (e.g. `PROJ-011`); `<wave>` is the integer wave number. Resolves the contract path as `.forge/plans/<ticket>/<ticket>-Wave-<wave>-contract.md`.

If invoked without both arguments, print usage and exit.

## When to Use

- `/forge-deliver` Stage 7 Step 0 invokes this once per wave, **before** Step 1 (parallel plan authoring), so plans are authored AGAINST a frozen contract.
- A wave's seam shape needs refreshing because a re-decompose changed it (the only legitimate way a frozen contract changes — proposal D3/D11).

## When NOT to Use

- **Decomposition Plan not approved** — the wave inventory + verify-WI aren't locked yet. Abort.
- **The wave has no backend↔frontend seam** — single-stack waves (backend-only or frontend-only) have no contract. The skill detects this and exits cleanly (no file written).
- **Reviewing or approving a plan** — use `/forge-plan-review`.
- **Feature mode (`ship_unit: feature`)** — contracts are a wave-mode construct. Abort with a steer.

## Inputs read (in order)

1. `.forge/tracker.yaml` `features.<ticket>` — `ship_unit`, `decomposition_plan.status`, the wave's `waves[].workitems[]` (WI ids, `type`, `depends_on`).
2. `.forge/plans/<ticket>/<ticket>-decomposition-plan.md` — `## Workitem Inventory` (scope summaries, which WI is backend vs frontend), `## Shared Contracts` (owner + consumers per contract — the shapes are NOT here, this skill pins them), `## Acceptance Criterion Coverage`, `## Wave Ship Plan` (the wave's ship-state one-liner).
3. The approved spec (`.forge/specs/<ticket>-*-spec.md`) — the requirements + ACs that pin what the seam must carry (request/response fields, enums, error cases).
4. `.forge/design/architecture.md` + project `CLAUDE.md` §Architecture Decisions — envelope/format conventions (wire casing, date format, error body shape, pagination envelope, auth handshake). Read these for the project's settled conventions; STOP+escalate on any seam that would violate a recorded Architecture Decision.
5. `.forge/plans/_TEMPLATE-contract.md` — the required section shape.
6. Any prior-wave frozen contract under `.forge/plans/<ticket>/` — reuse its envelope/format conventions verbatim so they don't drift wave-to-wave.

## Procedure

### 1. Validate inputs + mode

```bash
TICKET="<first arg>"; WAVE="<second arg>"
[ -n "$TICKET" ] && [ -n "$WAVE" ] || { echo "Usage: /forge-contract-author <ticket> <wave>"; exit 1; }

ENG_SHIP_UNIT=$(yq '.delivery.ship_unit // "feature"' .forge/tracker.yaml)
FEAT_SHIP_UNIT=$(yq ".features[] | select(.id == \"$TICKET\") | .ship_unit // \"\"" .forge/tracker.yaml)
EFFECTIVE_MODE="$ENG_SHIP_UNIT"; [ -n "$FEAT_SHIP_UNIT" ] && EFFECTIVE_MODE="$FEAT_SHIP_UNIT"
[ "$EFFECTIVE_MODE" = "wave" ] || { echo "$TICKET is at ship_unit: feature — contracts are wave-mode only. Aborting."; exit 1; }

DECOMP_STATUS=$(yq ".features[] | select(.id == \"$TICKET\") | .decomposition_plan.status" .forge/tracker.yaml)
[ "$DECOMP_STATUS" = "approved" ] || { echo "Decomposition Plan not approved (status: $DECOMP_STATUS). Aborting."; exit 1; }
```

### 2. Detect the wave's seam(s)

**Primary signal — the `type: verify` WI.** The Decomposition Plan's verify-WI auto-propose (`/forge-wave-decompose` step 5.b.5) already fired on exactly the backend+frontend parallelism that needs a contract. So:

- Read the wave's WIs. For each `type: verify` WI, its `depends_on` names the **backend-WI** and **frontend-WI** it integrates — those are the seam's two sides.
- One contract per wave, with a `## Owners` row per seam if the wave has more than one verify-WI (proposal OQ-1: per-wave is the default; split to per-pair only when a wave spans several independent seams).

**Fallback — backend+frontend without a verify-WI.** If the wave has ≥1 backend-touching WI AND ≥1 frontend-touching WI (per `## Workitem Inventory` scope summaries / repo signals — the same heuristic as `/forge-wave-decompose` step 5.b.5) but NO `type: verify` WI, the developer declined the integration gate. Emit:

```
⚠ Wave <N> has a backend↔frontend seam (<backend-WI> ↔ <frontend-WI>) but no verify-WI —
the developer declined the integration gate at decompose time. Authoring the contract
anyway: the read-only freeze + conformance Success Criteria still help, but there is no
seam-test-implementer to catch behavioral seam bugs before the browser E2E.
```

…then author the contract.

**No seam.** If the wave is single-stack (only backend WIs or only frontend WIs), print *"Wave `<N>` has no backend↔frontend seam — no contract needed."* and exit 0 with no file written. `/forge-deliver` Step 0 treats this as a clean pass and proceeds to Step 1.

### 3. Author / refresh the contract

Create `.forge/plans/<ticket>/<ticket>-Wave-<wave>-contract.md` from `_TEMPLATE-contract.md` (or refresh in place if it exists at `Status: draft`; a `frozen` contract is only refreshed on an explicit re-decompose — see step 6).

Pin every section the template requires:

- **Seam Summary** — capability, backend owner, frontend consumer, how the wave's ship-state wires them (from `## Wave Ship Plan`).
- **Owners** — backend-WI + frontend-WI rows from the verify-WI's `depends_on`.
- **Endpoints** — method, path, auth, request/response types, error responses. Derive from the spec's requirements/ACs and the `## Shared Contracts` inventory's contract names.
- **Field Definitions** — EXACT field name + casing, wire type, nullability, enum values, format, per request/response type. This is the layer that kills shape drift; be precise.
- **Envelope & Convention Rules** — pagination envelope, error body shape, date/number formats, casing, auth handshake. Read the project's conventions from `.forge/design/architecture.md` + `CLAUDE.md` §Architecture Decisions (the wire casing, date format, error envelope, pagination shape, and auth scheme are project-settled, not assumed here). **Reuse a prior-wave frozen contract's conventions verbatim** when one exists.
- **Read-Only to Implementers (D3)** — keep the template's note.
- **Machine-Readable Schema** — Minimal path: optional (leave the placeholder or delete the fenced block). Full path: mandatory fenced schema block (e.g. `openapi`/`yaml` — match the project's wire spec) kept in sync with the Field Definitions tables.

Write with header `Status: draft` and empty `Validated-via`.

### 4. Auto-validate (no human gate — D5)

Run the validation gate deterministically against the drafted contract. The wave does NOT wait on a human here (unlike spec-review / plan-review). Check:

1. **Well-formed** — every type referenced in `## Endpoints` has a `## Field Definitions` block; every table parses; no `<placeholder>` tokens remain.
2. **frontend-expected ⊆ backend-declared** — every field the frontend-WI will consume (from the spec's UI/AC requirements + the frontend-WI's scope summary) appears in a backend-declared response type. A field the client expects that the server doesn't provide is the canonical drift bug — flag it.
3. **Schema lint (Full path only)** — if a `## Machine-Readable Schema` block is present, it must parse as a valid schema in the project's wire-spec format and agree with the Field Definitions tables.

Write the outcome into the contract's `## Validation Record` table (✓/✗/n-a per row).

### 5. Freeze on pass / bounded re-author on fail

- **All checks pass** → flip header `Status: draft → frozen`, write `Validated-via: forge-contract-author (auto-validated, <today>)`. The contract is now read-only to implementers.
- **A check fails** → fix the contract in place and re-validate. Bounded to **N=2** re-author attempts. If still failing after N=2, the seam definition is genuinely under-specified — **escalate to the human** with the failing check(s) and the gap (a malformed/under-specified contract is a decompose-level problem, not something to loop on forever — proposal §8 "auto-validation is weaker than a human reviewer; async human review is the backstop").

### 6. Re-author of a frozen contract (re-decompose only)

A `frozen` contract changes ONLY when a re-decompose changes the seam shape (proposal D3/D11 "contract defect"). On such a re-author: bump a `## Revisions` entry recording the trigger + the WIs re-planned, re-run step 4's validation, re-freeze. Never silently overwrite a frozen contract without a revision entry.

### 7. Tracker + final report

**No tracker schema change** — the contract path is derivable (`.forge/plans/<ticket>/<ticket>-Wave-<wave>-contract.md`) and the contract is not a WI. Optionally refresh the feature's `notes` to mention the wave's contract was frozen. Bump `last_updated` only if `notes` changed.

```
## Wave <N> contract — <frozen | no seam | escalated>

- Contract: .forge/plans/<ticket>/<ticket>-Wave-<wave>-contract.md (Status: <frozen|draft>)
- Seam: <backend-WI> ↔ <frontend-WI>   (or "none — single-stack wave")
- Endpoints pinned: <N>
- Validation: well-formed <✓>, frontend⊆backend <✓>, schema-lint <✓|n-a>
- Read-only to implementers: yes (D3) — both WIs list it in ## Files to Modify as read-only

Next: /forge-deliver Step 1 authors this wave's plans AGAINST the frozen contract.
```

## Notes

- **No human gate (D5).** The pipeline must not wait on a human between decompose and the parallel fan-out. A human MAY review the contract asynchronously (it's co-located with the plans), but the wave does not block on that.
- **The verify-WI is the seam marker.** Authoring fires on exactly the seams `/forge-wave-decompose` step 5.b.5 flagged with a verify-WI — they are the same set by construction (proposal §8). This is the deterministic detection signal.
- **Frozen = read-only to implementers (D3).** A WI that needs a contract change HALTS and escalates → re-decompose. It never edits the frozen contract.
- **Shapes live HERE, not in the owning WI's plan.** Contract-first formalizes what wave-mode previously left to "the owning WI's approved plan locks the shape." The owning WI's plan now CONFORMS to and CITES the frozen contract. (`/forge-plan-author` emits a conformance Success Criterion when a WI sits on a contracted seam.)
- **Minimal vs Full (proposal §7).** Minimal: prose tables are the contract; the seam-test-implementer + conformance Success Criteria do the detection. Full: add the machine-readable schema block + frontend codegen + backend conformance test (subtask 3, app-repo work).
- **Bounded self-validation, not infinite loop.** N=2 re-author attempts, then escalate. Auto-validation catches shape problems, not semantic API-design mistakes — async human review is the backstop.
- **One wave per invocation.** Scoped to one wave's seam(s) — bounded and tractable (D4).
