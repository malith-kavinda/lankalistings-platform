# <Feature Title> — Wave <N> Contract

> Spec: `.forge/specs/<SPEC_ID>-<suffix>-spec.md`
> Decomposition Plan: `.forge/plans/<SPEC_ID>/<SPEC_ID>-decomposition-plan.md`
> Type: wave-contract
> Wave: <N>
> Status: draft | frozen   <!-- draft while authoring; flips to frozen on auto-validation pass (no human gate — see forge-contract-author SKILL D5) -->
> Author: <git config user.name>
> Validated-via: <empty until validation passes — forge-contract-author writes "forge-contract-author (auto-validated, <YYYY-MM-DD>)">
> Date: <today>

<!--
WHAT THIS FILE IS
  The authoritative interface definition for the backend↔frontend seam(s) in
  this wave. Authored SERIALLY by `forge-contract-author` (or `/forge-deliver`
  Stage 7 Step 0) AFTER the seam is declared in the Decomposition Plan and
  BEFORE the wave's parallel plan-authoring fan-out. Frozen on auto-validation
  pass, then passed READ-ONLY to both plan-authors and both implementers.

WHY IT LIVES HERE
  Co-located with the wave's WI plans (`.forge/plans/<SPEC_ID>/`) so the seam
  definition sits next to the work that consumes it — no separate
  `.forge/contracts/` tree to hunt through.

CONTRACT VS WI PLANS (read-only discipline — D3)
  Implementers list this file in their plan's `## Files to Modify` as READ-ONLY.
  A WI that needs a contract change does NOT edit this file — it HALTS and
  escalates → the change is a plan-level event → re-decompose. A frozen contract
  is the single source of truth for the seam shape; the owning WI's plan
  CONFORMS to and CITES it, it does not re-invent it.

MINIMAL VS FULL (proposal §7)
  - Minimal path: the prose tables below ARE the contract; the `## Machine-Readable
    Schema` block is optional. Detection happens at the seam-test-implementer
    (API-level seam test) and via plan-time conformance Success Criteria.
  - Full path: the `## Machine-Readable Schema` block (fenced `openapi`/`yaml`) is
    mandatory — FE codegen and BE schema-conformance tests consume it. Delete the
    "optional on Minimal" note when adopting Full.

Delete these HTML comments when authoring a real contract.
-->

## Seam Summary

<!-- One paragraph: which user-facing capability this seam serves, which WI owns
     the server side, which WI consumes it on the client, and what the wave's
     ship-state says about how they wire together. -->

## Owners

| Side | WI ID | Repo | Role |
|------|-------|------|------|
| Server (provides) | `<SPEC_ID>-WI-<N>.<i>` | `<backend-repo>` | Declares the endpoints + response shapes below |
| Client (consumes) | `<SPEC_ID>-WI-<N>.<j>` | `<frontend-repo>` | Generates/builds its API client + types against the shapes below |

<!-- Add rows if a wave has more than one server↔client pair. If a wave has
     multiple independent seams, author one contract per pair OR one per wave
     with a section per seam (see Decomposition Plan OQ-1 / proposal OQ-1). -->

## Endpoints

| Method | Path | Auth | Request body | Success response | Error responses |
|--------|------|------|--------------|------------------|-----------------|
| `GET`  | `/api/v1/<resource>` | Bearer token (role: `<ROLE>`) | — | `200` → `<ResponseType>` | `401`, `403`, `404` → error envelope |
| `POST` | `/api/v1/<resource>` | Bearer token (role: `<ROLE>`) | `<RequestType>` | `201` → `<ResponseType>` | `400`, `401`, `403`, `409` → error envelope |

## Field Definitions

<!-- One block per request/response type referenced above. Pin EXACTLY: field
     name (and casing), JSON type, nullability, enum values, and format. This is
     the layer that kills name/casing drift, nullability surprises, and enum
     mismatches before parallel impl. -->

### `<ResponseType>`

| Field | JSON type | Nullable | Enum / format | Notes |
|-------|-----------|----------|---------------|-------|
| `id` | string (uuid) | no | — | |
| `status` | string | no | `<VALUE_A>` \| `<VALUE_B>` \| `<VALUE_C>` | enum values fixed by the contract |
| `createdAt` | string | no | ISO-8601 (`2026-05-29T10:00:00Z`) | UTC, always `Z` suffix |

### `<RequestType>`

| Field | JSON type | Required | Enum / format | Notes |
|-------|-----------|----------|---------------|-------|

## Envelope & Convention Rules

<!-- The cross-cutting shape rules both sides must agree on. These are the
     "compiled fine in isolation, broke once wired" failures the contract exists
     to prevent. The example shapes below are ILLUSTRATIVE — replace them with
     your stack's actual conventions. -->

- **Pagination envelope:** `<shape — e.g. { content: [...], page, size, totalElements }>`
- **Error body shape:** `<shape — e.g. { timestamp, status, error, message, path }>`
- **Date format:** ISO-8601, UTC, `Z` suffix. No epoch millis on the wire.
- **Number format:** `<integer vs decimal-as-string for money, etc.>`
- **Field casing:** `<the wire casing both sides serialize/expect — e.g. camelCase>`.
- **Auth handshake:** `Authorization: Bearer <token>`; `401` on missing/expired, `403` on role mismatch.

## Read-Only to Implementers (D3)

> This contract is **frozen**. Both the owning server-side WI and the consuming
> client-side WI list this file in their plan's `## Files to Modify` as **read-only**.
> Neither edits it. An implementer that discovers the contract is wrong (a field is
> missing, a type is off, a flow can't be satisfied) **STOPS and escalates** — the
> fix is a re-decompose / contract re-author, never a silent in-WI edit.
> (Proposal D3, D11 case "contract defect".)

## Machine-Readable Schema

<!-- FULL PATH ONLY (optional on the Minimal path). When present, FE codegen
     (your chosen OpenAPI→types generator) and the BE schema-conformance test
     consume THIS block as the source of truth. Keep it in sync with the tables
     above — the tables are human-readable, this block is machine-checkable.

     For non-HTTP seams (shared types, no API — proposal OQ-2), replace the
     OpenAPI block with the shared typed definition; same principle, different
     block. -->

```yaml
# openapi: 3.1.0  (delete this block on the Minimal path if not wiring codegen)
```

## Validation Record

<!-- forge-contract-author writes the auto-validation outcome here on each
     authoring/refresh pass. -->

| Check | Result | Notes |
|-------|--------|-------|
| Well-formed (tables parse; every referenced type is defined) | <✓/✗> | |
| FE-expected fields ⊆ BE-declared fields (no client field absent from server) | <✓/✗> | |
| Schema lint (Full path only — OpenAPI/YAML parses) | <✓/✗/n-a> | |

## Revisions

<!-- A frozen contract changes ONLY via re-decompose. Record each change here
     with the re-decompose trigger and the WIs re-planned as a result. -->

### Rev 1 — YYYY-MM-DD
- **Changed:** <what shape changed>
- **Trigger:** <which WI/seam-test surfaced the need; re-decompose reference>
- **WIs re-planned:** <list>
