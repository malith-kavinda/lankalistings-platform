# 05 — API Contract

> Reconstructed 2026-08-24. Provenance tags per `README.md`.
> This document defines the **conventions** every service obeys and the **resource surface** the three
> clients need. It is not an OpenAPI spec — per-wave seam contracts are frozen at delivery time using
> `.forge/plans/_TEMPLATE-contract.md`, and this document is what they must conform to.

## 1. Why conventions come first

Five services in two runtimes (doc 03) serving three clients is precisely the shape where envelope,
error, pagination and money conventions drift — one service returns `{data: …}`, another returns a bare
array; one returns `400` for a validation failure, another `422` (FastAPI's default). Every drift becomes
per-client special-case code.

So: **the conventions in §2–§7 and §12–§13 are binding on all five services, and where a framework
default conflicts with them, the framework default is overridden.** FastAPI's default `422` validation body and its
`{"detail": …}` error shape both conflict and must be replaced. `[PROPOSED]`

## 2. Envelope

`[PROPOSED]`

Single resource:
```json
{ "data": { "…": "…" }, "error": null }
```

Collection:
```json
{
  "data": [ { "…": "…" } ],
  "error": null,
  "meta": { "total": 1245, "limit": 24, "next_cursor": "eyJwIjoxfQ", "has_more": true }
}
```

Error:
```json
{ "data": null, "error": { "code": "AD_NOT_ACTIVE", "message": "…", "details": [], "correlation_id": "…" } }
```

`total` is required on the public search collection — the UI renders "Showing 1,245 ads matching your
criteria". `[DERIVED]`

## 3. Error contract

`[PROPOSED]`

| HTTP | Meaning | `error.code` examples |
|---|---|---|
| 400 | Malformed request | `MALFORMED_REQUEST` |
| 401 | Missing/invalid/expired token | `UNAUTHENTICATED`, `TOKEN_EXPIRED` |
| 403 | Authenticated but not permitted — includes cross-owner access | `NOT_AD_OWNER`, `ROLE_REQUIRED` |
| 404 | Not found **or** deliberately hidden. A `pending` ad fetched by a non-owner returns 404, never 403 — a 403 confirms the ad exists, which leaks the moderation queue | `AD_NOT_FOUND` |
| 409 | State conflict | `INVALID_STATUS_TRANSITION`, `AD_NOT_ACTIVE`, `ALREADY_FEATURED` |
| 422 | Field validation failure, with per-field `details` | `VALIDATION_FAILED` |
| 429 | Rate limited | `RATE_LIMITED` |
| 5xx | Server fault. Never leaks internals; always carries `correlation_id` | `INTERNAL_ERROR`, `UPSTREAM_UNAVAILABLE` |

Validation `details` shape — one entry per failing field, because the create wizard shows errors inline
per field ("Title is required" `[DERIVED]`):
```json
{ "field": "title", "code": "MAX_LENGTH", "message": "Title must be 70 characters or fewer" }
```

**`error.code` is the client's branching key; `error.message` is for humans and may change without a
version bump.** Clients must never branch on message text.

## 4. Money, dates, identifiers

`[PROPOSED]` except where noted.

- **Money** is always an integer of LKR minor units plus an explicit currency, never a float and never a
  formatted string: `{"price": {"amount_cents": 875000000, "currency": "LKR"}}`. Formatting
  (`Rs. 8,750,000`) is a client concern; the `Rs.` prefix and mandatory thousands separators are
  `[LOCKED]` presentation rules from the consumer design system.
- **Timestamps** are RFC 3339 UTC. Relative rendering ("Posted 2 hours ago", queue age "8 min") is
  client-side. `[DERIVED]`
- **Ad identity in URLs** uses the public `reference` (`LL-49210`), not the internal id — it is already
  user-facing and quotable. `[DERIVED]`
- **Enums** are lower snake_case on the wire (`brand_new`, `price_low_high`), title-cased by clients.
  This is the single most likely FE↔BE drift point across three clients and five services.

## 5. Pagination

`[PROPOSED]` — cursor-based on all public collections (FR-21), because offset pagination over a growing
moderated corpus degrades and the mobile surface appends rather than paginates. Operator tables may use
offset pagination, where a page-number control and a stable total matter more than deep-scan cost.

## 6. Authentication

`[PROPOSED]` — `Authorization: Bearer <access_token>`. Short-lived access token, longer-lived refresh
token. Every service validates independently; the gateway's validation is not a substitute (doc 03 §6).

Three enforcement rules the contract makes explicit because AC-4, AC-9 and AC-14 test them:

1. **Public read paths return only `active` ads.** No query parameter, header, or role short-circuits
   this on a public endpoint.
2. **Seller mutations are ownership-scoped**, verified server-side against the token subject.
3. **Operator endpoints require a role**, checked in the service, not just at the gateway.

## 7. Correlation

Every request carries or is assigned `X-Correlation-Id`; it propagates across service hops and is
returned in `error.correlation_id`. `[PROPOSED]` — non-optional in a five-service polyglot backend.

## 8. Resource surface

Grouped by owning service. Paths shown as the gateway exposes them.

### `identity-service` — `/api/v1/auth`, `/api/v1/me`

| Method | Path | Purpose | Notes |
|---|---|---|---|
| POST | `/auth/register` | Email + password registration | FR-1 |
| POST | `/auth/login` | Email + password sign-in | FR-1 |
| POST | `/auth/google` | Exchange a Google credential for tokens | FR-1. **Links to an existing account on email match** (FR-2) |
| POST | `/auth/refresh` | Rotate tokens | |
| POST | `/auth/logout` | Revoke refresh token | |
| POST | `/auth/verify-email` | Consume a verification token | FR-3 |
| POST | `/auth/password-reset/request` · `/auth/password-reset/confirm` | Reset by emailed token | FR-5 |
| GET/PATCH | `/me` | Own profile | FR-28 |
| POST | `/me/phone/verify` | Phone verification | Candidate criterion for FR-4's badge |

### `listing-service` — public read

| Method | Path | Purpose | Notes |
|---|---|---|---|
| GET | `/categories` | Taxonomy tree with ad counts | FR-16 |
| GET | `/categories/{slug}/attributes` | Attribute definitions for the create form, spec table, and filter rail | FR-9/FR-40. One endpoint serving three surfaces |
| GET | `/locations/provinces` · `/districts` · `/cities` | Location hierarchy | FR-12 |
| GET | `/ads` | Search, filter, sort, paginate | The product's busiest endpoint — §9 |
| GET | `/ads/{reference}` | Ad detail | `active` only for non-owners; 404 otherwise (§3) |
| GET | `/ads/featured` | Home featured rail | FR-16 |

### `listing-service` — seller

| Method | Path | Purpose | Notes |
|---|---|---|---|
| POST | `/ads` | Create as `draft` | FR-13 |
| PATCH | `/ads/{reference}` | Update a draft, or an owned ad | Applies R-4's re-moderation rule server-side |
| POST | `/ads/{reference}/submit` | `draft` → `pending` | R-1 |
| POST | `/ads/{reference}/sold` | → `sold` | FR-30 / R-6 |
| DELETE | `/ads/{reference}` | Soft delete | Doc 04 §8 |
| GET | `/me/ads?status=` | My Ads, tabbed | FR-30 |
| GET | `/me/ads/summary` | Active / Pending / Saved / Unread counters | FR-29 |
| POST/DELETE | `/ads/{reference}/favourite` | Save / unsave | FR-25 |
| GET | `/me/favourites` | Saved Ads | FR-28 |
| POST | `/ads/{reference}/report` | Report an ad | FR-35 — the missing intake for the operator's flagged queue |
| POST | `/ads/{reference}/view` | Record a view | FR-31. High-write; needs a definition of a view and abuse protection |

### `listing-service` — AI-guided creation flow

Added for the AI-guided Post Ad flow. These extend the seller surface above; `POST /ads`,
`PATCH /ads/{reference}` and `POST /ads/{reference}/submit` are unchanged and remain the create, update
and submit path. Every endpoint is ownership-scoped (§6 rule 2) and addressed by `reference` (§4).

| Method | Path | Purpose | Notes |
|---|---|---|---|
| GET | `/ads/{reference}/creation-flow` | Resolved stage, pinned schema snapshot, saved answers, pending and stale AI results, next required or follow-up questions | The browser receives rendered field metadata only — never prompts, provider payloads, or unvalidated schema |
| PATCH | `/ads/{reference}/creation-flow/answers` | Validate, persist, clear or skip answers | Version precondition required (§12). `422` with per-field `details` on validation failure |
| POST | `/ads/{reference}/creation-flow/next-questions` | Resolve required fields, then invoke the decision provider when eligible | **No client-supplied question keys are trusted.** Never called while a required field is missing or invalid |
| POST | `/ads/{reference}/content-generations` | Start an asynchronous title/description generation | Idempotency key required (§13) |
| GET | `/ads/{reference}/content-generations/{generation_id}` | Read the seller's own generation status and result | |
| POST | `/ads/{reference}/attribute-suggestions/{suggestion_id}/accept` | Validate, normalise and apply a proposed field value | Validated exactly as if the seller had typed it |
| POST | `/ads/{reference}/attribute-suggestions/{suggestion_id}/ignore` | Record seller rejection | |

### `media-service` — `/api/v1/media`

| Method | Path | Purpose | Notes |
|---|---|---|---|
| POST | `/media` | Upload an image, returns asset id + derivative URLs | FR-11. Limits undecided |
| DELETE | `/media/{id}` | Delete an owned asset | |
| POST | `/media/{id}/extract` | Start OCR/AI extraction | **Only if FR-34 is scoped in** |
| GET | `/media/{id}/extraction` | Raw OCR text + per-field values with confidence | Only if FR-34 is scoped in |
| POST | `/internal/ad-copy` | Generate title/description **candidates** from confirmed seller facts | Service-to-service only, not gateway-exposed. Returns candidates; `listing-service` validates and persists. Never writes ad state |
| POST | `/internal/attribute-extraction` | Propose values for empty numeric/free-text schema fields from seller notes | Service-to-service only. Enum and boolean fields use the decision provider instead (doc 09 §8.3) |

### `payment-service` — `/api/v1`

| Method | Path | Purpose | Notes |
|---|---|---|---|
| GET | `/promotion-plans` | Active plan catalogue | FR-45 |
| POST | `/ads/{reference}/featuring` | Initiate a featuring purchase | **Rejects with 409 `AD_NOT_ACTIVE` unless the ad is `active` and owned by the caller** (R-7, AC-9) |
| GET | `/me/purchases` | Purchase history and featured windows | FR-48 |
| POST | `/webhooks/payments/{gateway}` | Settlement callback | Unauthenticated but signature-verified; **idempotent on `gateway_reference`** (doc 04 §5) |

### `admin-service` — `/api/v1/admin`

FastAPI, per the locked decision that FastAPI serves the management portal's CRUD surface.

| Method | Path | Purpose | Notes |
|---|---|---|---|
| GET | `/dashboard/kpis` | Awaiting Review, Active, Reported, New Users Today, each with a trend delta | FR-37 |
| GET | `/dashboard/by-category` · `/by-province` | Distribution breakdowns | FR-37 |
| GET | `/ads` | Operator register — filter by status, category, location, flagged | FR-38 |
| GET | `/ads/export` | CSV export | FR-38 |
| POST | `/ads` | Operator-created ad | FR-38 |
| GET | `/moderation/queue` | Pending queue, oldest first, with age and flags | FR-32 |
| GET | `/moderation/ads/{reference}` | Review payload, including extraction provenance when present | FR-33/FR-34 |
| POST | `/moderation/ads/{reference}/approve` | Approve, optionally with field edits | **Delegates the transition to `listing-service`** — doc 03 §3 |
| POST | `/moderation/ads/{reference}/reject` | Reject with reason code and note | R-3/AC-7 |
| POST | `/moderation/bulk` | Bulk approve/reject on a selection | FR-36 |
| GET | `/reports/ads` · POST `/reports/ads/{id}/resolve` | Flagged-ad workflow | FR-35 |
| CRUD | `/users` | User administration | FR-39 |
| CRUD | `/categories`, `/categories/{id}/attributes` | Taxonomy and attribute schemas | FR-40 |
| CRUD | `/promotion-plans` | Plan administration | FR-41 |
| GET | `/reports/*` | Reports | FR-42 — contents undecided |
| GET/PATCH | `/settings` | System settings | FR-43 — contents undecided |

## 9. `GET /ads` — the contract that matters most

Every consumer discovery surface across three clients funnels through this one endpoint, so its
parameters are specified exactly. All `[DERIVED]` from `search_results_desktop` unless noted.

| Parameter | Values |
|---|---|
| `q` | Free-text over title and description |
| `category` | Category or subcategory slug |
| `province` / `district` / `city` | Location filter at any level |
| `price_min` / `price_max` | LKR minor units |
| `condition` | `brand_new` / `used` / `reconditioned` |
| `verified_sellers_only` | Boolean |
| `attr[<key>]` | Repeatable category-specific filter, e.g. `attr[make]=toyota&attr[transmission]=automatic` |
| `sort` | `newest` (default) · `price_low_high` · `price_high_low` |
| `limit` / `cursor` | Cursor pagination (§5) |

Response contract:

- `meta.total` populated (the UI renders the count).
- Each item carries everything an ad card renders and nothing more: reference, title, price, main-photo
  derivative URL, city name, posted-at, `is_featured`, `is_verified_seller`, `condition`.
- **Featured-first ordering is applied by the server, within the requested sort.** FR-22's exact
  interleave is undecided; the client must not re-sort, or the two web clients and the mobile client
  will each invent a different ranking.
- **Only `active` ads, always.** No parameter overrides this.

## 10. Client-side seam notes

- **Three clients, one contract.** `frontend-web`, `mobile`, and `management-portal` share the envelope,
  error contract and enum vocabulary. A generated client per surface from one schema source is worth the
  setup cost here — hand-written clients across three codebases are how enum drift ships.
- **No API client layer exists in any of the three skeletons today** — all three render hard-coded
  fixtures (`frontend-web/src/lib/listings.ts`, `management-portal/src/lib/data.ts`, `mobile`'s
  `ListingCard`). Each of those fixture modules is a replacement site, and removing it belongs in the
  definition of done of the feature that first needs real data (doc 02 §7).
- **Seam tests are authored against a frozen per-wave contract** (`.forge/plans/_TEMPLATE-contract.md`),
  which must conform to this document. Where a wave needs a convention this document does not cover, the
  convention is added here first, then frozen in the wave contract — not invented in the wave.

## 11. Versioning

`[PROPOSED]` — `/api/v1` from the first commit. The mobile client is the reason: an installed app version
cannot be forced to update in step with a server deploy, so the API must be able to serve an old client
while a new one ships. This is the one architectural cost of having mobile in MVP scope that is easy to
forget until it is expensive.

## 12. Optimistic concurrency

`[PROPOSED]` — added for the AI-guided create flow (doc 09), where a seller can edit an answer on one
device while a generation job started from an earlier answer snapshot is still in flight.

Every mutable resource a client can edit carries an integer `version` in its `data` payload, incremented
server-side on every accepted mutation.

- A conditional mutation sends `If-Match: "<version>"`.
- A stale precondition returns **`409 VERSION_CONFLICT`**, carrying the current version in `details`.
  Never a silent overwrite.
- Every accepted mutation returns the new `version`, so a client never needs a re-read to keep editing.
- Omitting `If-Match` where it is required is **`428 PRECONDITION_REQUIRED`**.

Derived AI output additionally records the `source_version` it was produced from. Once the resource
version moves past it, that output is marked `stale` rather than silently reused.

## 13. Idempotency

`[PROPOSED]` — binding on every endpoint that can create a job, a payment, or a durable record.

- The client sends `Idempotency-Key: <opaque>`, unique per logical operation.
- A repeat with the same key **and the same request body** returns the original response and creates no
  second job or record.
- A repeat with the same key and a *different* body is **`409 IDEMPOTENCY_KEY_REUSED`**.
- Keys are scoped per authenticated subject and retained for a configured window.

This already holds informally for `POST /webhooks/payments/{gateway}` (idempotent on `gateway_reference`,
doc 04 §5) and for `media-service`'s batch upload. §12 and §13 generalise both into one platform
convention instead of three service-local ones.
