# 04 — Data Model

> Reconstructed 2026-08-24. Provenance tags per `README.md`.
> Entities are grouped by owning service per [03-architecture.md](03-architecture.md) §3.
> Field-level detail belongs in each service repo's own `docs/data-model.md`; this is the cross-service
> shape and the ownership map.

## 1. Ownership map

| Owning service | Entities |
|---|---|
| `identity-service` (Spring Boot) | Account, Credential, OAuthIdentity, Role, SellerVerification |
| `listing-service` (Spring Boot) | Advertisement, AdvertisementAttribute, Category, CategoryAttributeDefinition, Province, District, City, ModerationDecision, AdReport, Favourite, AdMetrics |
| `payment-service` (Spring Boot) | PromotionPlan, FeaturingPurchase, PaymentTransaction |
| `media-service` (FastAPI) | MediaAsset, MediaDerivative, (ExtractionJob, ExtractedField — only if FR-34 is scoped in) |
| `admin-service` (FastAPI) | None. It owns no state — it projects and composes. Any table it needs of its own (saved operator filters, export jobs) is a Gate-2 addition |

**Cross-service reference rule** `[PROPOSED]`: entities reference across a service boundary by opaque
id only — never a foreign key, never a join. `Advertisement.owner_account_id` is a value, not a
relationship the database enforces.

## 2. Identity

### Account
The single user identity. There is no separate seller entity — the same account sells and buys
(doc 01 §3). `[DERIVED]`

| Field | Notes |
|---|---|
| `id` | Internal primary key |
| `email` | Unique, case-insensitively |
| `email_verified_at` | Nullable. Gates publishing per FR-3 `[PROPOSED]` |
| `display_name` | Rendered as "Hello, Chaminda!" `[DERIVED]` |
| `phone` | Sri Lankan mobile format; shown on ad detail `[DERIVED]` |
| `phone_verified_at` | Nullable. Detail page renders `(Verified)` beside the number `[DERIVED]` |
| `status` | `active` / `suspended` — implied by the admin Users surface `[PROPOSED]` |
| `created_at`, `updated_at` | New-users-today KPI reads `created_at` `[DERIVED]` |

### Credential and OAuthIdentity
Two authentication methods over one Account, per FR-1/FR-2. `Credential` holds the password hash;
`OAuthIdentity` holds `(provider, provider_subject_id)` with a uniqueness constraint. Both point at
`account_id`. An account may have either, or both — this is what makes account **linking** rather than
duplication possible, and FR-2 depends on the model allowing it. `[PROPOSED]`

### Role
`member` / `moderator` / `super_admin`. `[DERIVED]` from the two operator personas plus the implicit
member role. Modelled as a set on the account rather than a single column, so an operator who also
sells does not need a second login. `[PROPOSED]`

### SellerVerification
Carries the "Verified Seller" state behind FR-4's badge and the `Verified Sellers Only` search facet.
**What earns it is undecided**, so model the state and the granting event, not the criteria:
`account_id`, `verified_at`, `method`, `granted_by`. `[PROPOSED]`

## 3. Taxonomy and location

### Category
Two levels — top-level category and subcategory. `[DERIVED]` from the `Home > Vehicles > Cars > Toyota`
breadcrumb, reading `Toyota` as an attribute value rather than a taxonomy node.

| Field | Notes |
|---|---|
| `id`, `parent_id` | `parent_id` null at top level |
| `slug`, `name` | Slug drives URLs |
| `icon` | Line-art icon reference per the consumer design system |
| `display_order`, `is_active` | Admin-manageable per FR-40 |

The nine top-level categories are locked: vehicles, property, land, jobs, electronics, services,
home & garden, fashion, other. `[LOCKED]` Subcategories are unspecified except `Vehicles > Cars`.

### CategoryAttributeDefinition
**The load-bearing unspecified entity.** FR-9 requires per-category attribute sets; only Vehicles is
specified. This entity is what lets the other eight be added without a schema migration per category.

| Field | Notes |
|---|---|
| `id`, `category_id` | Attached to a category (inherited by its subcategories) |
| `key`, `label` | e.g. `mileage_km` / "Mileage (km)" |
| `data_type` | `text` / `integer` / `decimal` / `enum` / `boolean` |
| `enum_values` | For `enum`: Transmission = Automatic/Manual/Tiptronic; Fuel = Hybrid/Petrol/Diesel/Electric `[DERIVED]` |
| `unit` | `km`, `cc` `[DERIVED]` |
| `is_required`, `is_filterable`, `display_order` | `is_filterable` drives the search rail's category-specific block (FR-18) |

Observed Vehicles set, in order: Make, Model, Year of Manufacture, Mileage (km), Transmission, Fuel
Type, Engine Capacity, Registration. `[DERIVED]`

**Gate-2 decision:** dynamic attribute definitions (this model) versus per-category typed models. The
dynamic model is proposed because the same definitions must simultaneously drive the create wizard, the
detail spec table, the search filters, and the admin taxonomy screen — four surfaces that would
otherwise each need per-category code for nine categories. Its cost is weaker type safety and harder
filtering; the index note in §7 addresses the second.

### Province / District / City
A locked three-level hierarchy, strictly nested. `[LOCKED]` Sri Lanka: 9 provinces, 25 districts. The
admin dashboard aggregates by province (`Western Province 12,450`, `Central Province 4,120`, …), so
province must be derivable from an ad without a runtime join chain. `[DERIVED]`

Reference data, not user data — seeded, versioned, and treated as a foundation slice.

## 4. Advertisement — the core aggregate

| Field | Notes |
|---|---|
| `id` | Internal primary key |
| `reference` | Public, human-quotable, `LL-NNNNN` `[DERIVED]`. Unique. Distinct from `id`, and never reused |
| `owner_account_id` | Cross-service opaque reference |
| `category_id` | The subcategory; top-level derived via `parent_id` |
| `title` | Required, **max 70 chars** `[DERIVED]` |
| `description` | Required, **max 4000 chars** `[DERIVED]` |
| `condition` | `brand_new` / `used` / `reconditioned` `[DERIVED]` — `Reconditioned` appears as a search facet, so it belongs in the domain even though the create form observed only two options. **Flag:** create-form options and search facets disagree; resolve at Gate 1 |
| `price_lkr_cents` | Integer minor units. Never floating point (NFR-4) |
| `is_negotiable` | "I'm open to offers" `[DERIVED]` |
| `city_id` | Resolves to district and province |
| `status` | `draft` / `pending` / `active` / `rejected` / `expired` / `sold` `[DERIVED]` |
| `published_at` | First transition to `active`. Drives "Posted 2 hours ago" `[DERIVED]` |
| `expires_at` | Drives R-5. Duration undecided |
| `featured_until` | Nullable. Non-null and future ⇒ promoted treatment and ranking boost (FR-22). Denormalised here from `payment-service` so the hot search path needs no cross-service call `[PROPOSED]` |
| `created_at`, `updated_at`, `submitted_at` | `submitted_at` drives queue age ("8 min") `[DERIVED]` |

**Status is the product's central invariant.** Only `active` is publicly readable (R-2). Transitions are
owned exclusively by `listing-service` — `admin-service` requests them, never performs them
(doc 03 §3).

### AdvertisementAttribute
The value side of `CategoryAttributeDefinition`: `(advertisement_id, definition_id, value_text,
value_numeric)`. Two typed columns rather than one text column, so numeric filtering and range queries
(Year, Mileage, Engine Capacity) stay indexable. `[PROPOSED]`

### MediaAsset reference
Photos are owned by `media-service`; `listing-service` stores an ordered list of asset ids with one
marked main. `[DERIVED]` — gallery `1 / 12`, `+8 photos`, and a labelled `Main Photo` in the publish
preview. Count limits, size cap and formats undecided.

### ModerationDecision
One row per decision, append-only — an ad can be rejected, revised, resubmitted and approved, and the
history matters for both operator accountability and repeat-offender handling. `[PROPOSED]`

| Field | Notes |
|---|---|
| `advertisement_id`, `decision` | `approved` / `rejected` |
| `moderator_account_id`, `decided_at` | Operator accountability |
| `reason_code`, `reason_note` | Powers R-3 and AC-7. Reason codes are undecided |
| `field_edits` | What the moderator changed before approving (FR-33) |

### AdReport
Buyer/visitor reports feeding the operator's flagged queue (FR-35): `advertisement_id`,
`reporter_account_id` (nullable if anonymous reporting is allowed), `reason_code`, `note`,
`created_at`, `resolution`. Reporting intake is undesigned — the operator side exists
(`Reported Ads / 34`, `Flagged (12)`) with nothing feeding it. `[DERIVED]` for the operator side,
`[PROPOSED]` for the entity.

Distinguish **`AdReport`** (a person reported this ad) from **automated flags** (`Price anomaly`,
`Duplicate images`, `Warranty claim` — `[DERIVED]` from `management-portal/src/lib/data.ts`). The
committed mock carries flags as a free-text string; they need to become a typed, machine-generated set
with a rule behind each, or be dropped from the queue UI.

### Favourite
`(account_id, advertisement_id, created_at)`, unique on the pair. Powers Saved Ads and the `Saved 24`
counter. `[DERIVED]`

### AdMetrics
View count and inquiry count per FR-31 (`1,240 Views`, `12 Inquiries`). `[DERIVED]` Kept separate from
`Advertisement` because view counting is a high-write, low-value-per-write path and must not contend
with the ad row on every page load. Definition of a "view" is undecided. `[PROPOSED]`

## 5. Payment

### PromotionPlan
The featuring product catalogue behind FR-41/FR-45: `name`, `description`,
`price_lkr_cents`, `duration_days`, `is_active`, `display_order`. Catalogue contents, prices and
durations are entirely unspecified — the admin surface to manage them exists in the sidebar, the plans
themselves do not. `[DERIVED]` for the surface, `[PROPOSED]` for the entity.

### FeaturingPurchase
Joins a member, an ad, and a plan to a paid window: `advertisement_id`, `account_id`, `plan_id`,
`price_lkr_cents_at_purchase` (captured at purchase — plan prices change), `status`
(`initiated`/`settled`/`failed`/`refunded`), `featured_from`, `featured_until`, `created_at`.

**Invariant:** a purchase may only be initiated against an ad whose status is `active` and whose owner
matches the purchaser (R-7, FR-44, AC-9). Enforced server-side in `payment-service` by asking
`listing-service`, not by trusting the client.

### PaymentTransaction
The gateway conversation: `purchase_id`, `gateway`, `gateway_reference` (**unique — this is the
idempotency key for repeated webhooks**), `amount_lkr_cents`, `currency` (`LKR`), `status`,
`raw_payload`, `created_at`. Gateway undecided (FR-46). `[PROPOSED]`

## 6. Media

### MediaAsset / MediaDerivative
`MediaAsset`: `id`, `owner_account_id`, `storage_key`, `content_type`, `byte_size`, `width`, `height`,
`checksum`, `created_at`. `MediaDerivative`: one row per generated size (thumbnail, card, gallery,
main), each with its own `storage_key`.

`checksum` is what makes the `Duplicate images` automated flag implementable — without a content hash
stored at upload, duplicate detection has nothing to compare. `[PROPOSED]`

### ExtractionJob / ExtractedField — only if FR-34 is scoped in
`ExtractionJob`: `source_asset_id`, `status`, `raw_ocr_text`, `model_version`, `created_at`.
`ExtractedField`: `job_id`, `field_key`, `extracted_value`, `confidence` (`high`/`medium`/`low`),
`warning_note`, `accepted_value`, `accepted_by`. `[DERIVED]` — the review screen renders exactly this
shape: raw OCR text, per-field value, a confidence chip, and a warning string
("OCR extracted '8,75O,000/=' (contains letter 'O')").

Doc 01's FR-34 recommendation is to defer extraction but keep the review UI's field-provenance model —
which in data terms means the moderation review surface reads *optional* per-field provenance, so
turning extraction on later adds rows rather than reshaping the review path.

## 7. Index plan

Driven by the observed query surfaces, not speculative. `[PROPOSED]`

| Query surface | Index |
|---|---|
| Public browse and search (FR-17…FR-22) | Composite on `(status, category_id, city_id, price_lkr_cents)` — every public query is `status = active` first. Partial index `WHERE status = 'active'` keeps the hot index small as `rejected`/`expired` rows accumulate |
| Featured-first ranking | `(status, featured_until DESC, published_at DESC)` |
| Newest-first sort | `(status, published_at DESC)` |
| Free-text on title and description | Full-text index. Postgres `tsvector` if Postgres is chosen; a dedicated search engine is out of scope at MVP per doc 03 |
| Attribute filtering | `(definition_id, value_numeric)` and `(definition_id, value_text)` on `AdvertisementAttribute`. **This is the dynamic-attribute model's weak point** — multi-attribute filtering becomes multiple index lookups intersected. Measure before Gate 3 |
| Seller's My Ads, tabbed by status | `(owner_account_id, status, updated_at DESC)` |
| Moderation queue, oldest first | `(status, submitted_at ASC)` partial `WHERE status = 'pending'` |
| Flagged queue | Partial index on unresolved `AdReport` |
| Admin register with filters | `(status, category_id, created_at DESC)` |
| Province aggregation for the dashboard | Province denormalised onto the ad, or a materialised rollup — a three-level join per dashboard load is avoidable |
| Reference lookup | Unique on `reference` |
| Favourites | Unique `(account_id, advertisement_id)`; `(account_id, created_at DESC)` for the list |
| Webhook idempotency | Unique on `(gateway, gateway_reference)` |
| Account lookup | Unique lower(`email`); unique `(provider, provider_subject_id)` |

## 8. Deletion, retention, audit

`[PROPOSED]` — none of this is specified in the inputs and all of it is cheaper to decide now.

- **Ad deletion** (`Delete` in the My Ads row menu, `[DERIVED]`) is a soft delete. A moderation history
  and a payment record must survive the ad, or refund disputes become unanswerable.
- **Account deletion** needs a defined cascade — ads, favourites, media, and payment records each need a
  decision. Under a data-protection regime (NFR-7) this is a legal obligation, not a nicety.
- **Media retention** past ad deletion needs a rule; orphaned images are the default failure mode and
  they cost storage indefinitely.
- **Operator action audit.** Every approve, reject, edit, user suspension and plan change is attributable
  and append-only. `ModerationDecision` covers ad decisions; user and plan administration need the same
  treatment.
- **PII in logs.** Contact details must not reach log output — this is a foundation-slice logging
  concern, not something to fix per feature.

## 9. Seed dataset requirement

The test strategy needs one deterministic dataset (doc 06). Minimum shape to exercise the real
permutations `[PROPOSED]`:

- All 9 provinces, all 25 districts, a usable city set
- All 9 top-level categories with subcategories, and full attribute definitions for at least Vehicles
  plus two structurally different categories (a Property-style one, a Jobs-style one)
- Accounts covering every role, plus one verified and one unverified seller
- Ads in **every** status, including a `pending` one with a queue age and a `rejected` one with a reason
- One featured ad with a live window and one with an expired window — the ranking rule (FR-22) is
  untestable without both
- One ad with a full 12-image gallery, one with a single image
- One reported ad and one automated-flag ad
