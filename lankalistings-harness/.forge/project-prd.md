# LankaListings — Project PRD

> Status: draft
> Last updated: 2026-08-24 <!-- deliberate doc-level header — not a per-fact date stamp -->
> Reviewed by: (pending Gate 1 — `/forge-prd-check`)

The single source-of-truth product requirements document for this engagement. Verified by
`/forge-prd-check` (Gate 1) before the team commits to delivering against it.

> **Provenance warning — read before treating any line here as settled.** This PRD was authored from a
> **reconstructed** discovery pack. The original engineering pack published a map of eight documents but
> only its index was ever written; the seven substantive documents were rebuilt on 2026-08-24 from real
> artefacts (the locked-decision table, two design-system token files, 17 Stitch screen exports, three
> app skeletons) plus a scoping conversation with the product owner. Statements traceable to those
> sources are load-bearing; statements filling a gap are engineering proposals and are tagged as such in
> `.forge/discovery/docs/`. **34 open questions** are live in
> [`project-prd-signals.md`](project-prd-signals.md). Gate 1's job here is not ceremonial — it is to
> convert proposals into decisions or explicit deferrals.

## Gate Status

> Snapshot of engagement-readiness gates. Updated automatically by `/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose` in full mode. Detailed run history lives in [`engagement-gate-runs.md`](engagement-gate-runs.md). Structured state and accepted risks/spikes live in [`tracker.yaml`](tracker.yaml) under `setup.*`.

| Gate | Status | Last Run | Risks / Spikes | Detail |
|------|--------|----------|----------------|--------|
| 1. PRD Readiness (`/forge-prd-check`) | ❌ failed | 2026-08-24 | — | [Run 1](engagement-gate-runs.md#gate-1-run-1--2026-08-24-malith3) |
| 2. Architecture & Feasibility (`/forge-arch-probe`) | ⏳ not-started | — | — | — |
| 3. Decomposition (`/forge-decompose`) | ⏳ not-started | — | — | — |

Status legend: ⏳ not-started · 🚧 in-progress · ✅ passed · ⚠️ passed-with-risks · ⚠️ passed-with-spikes · ❌ failed

## Problem Statement

Sri Lankan buyers and sellers transact informally — through Facebook groups, WhatsApp broadcasts, and
newspaper classifieds — where listings are unstructured, unsearchable, unverifiable, and mixed with spam.
A buyer looking for a 2016 Prius in Colombo under Rs. 9,000,000 has no way to express that query. A
seller has no way to reach beyond their own network.

LankaListings is a general classifieds marketplace that makes both sides tractable: structured,
category-aware listings that are filterable by the attributes buyers actually care about, located within
a Province → District → City hierarchy, priced in LKR — and **moderated before publication**, so the
corpus stays worth searching. Moderation is the product's central bet: an unmoderated classifieds site
becomes spam-dominated, and spam-dominated means unsearchable, which removes the only reason to prefer
it over a Facebook group.

Revenue follows supply, not access. Publishing is free so listing volume grows; sellers pay only to
*feature* an ad that has already been approved. That ordering is a product constraint with a technical
consequence: **payment capture is never built before an approvable ad exists**.

## Industry / Domain Context

Online classifieds is a well-understood category with a well-understood failure mode. The economics are
two-sided: buyers arrive for inventory, sellers arrive for buyers, and the flywheel only turns if listing
quality holds. Every mature classifieds product in the category converges on the same three mechanisms —
structured category taxonomies with per-category attributes, geographic filtering, and moderation — and
LankaListings adopts all three.

Sri Lanka-specific context shaping the requirements:

- **Currency and formatting.** LKR only. Amounts run to eight digits for vehicles and property
  (Rs. 45,000,000 appears in the designs), so thousands separators are mandatory for legibility and
  exact-integer money handling is mandatory for correctness.
- **Geography.** 9 provinces, 25 districts. The hierarchy is a fixed reference dataset, not user data,
  and the operator dashboard aggregates by province.
- **Language.** Sinhala, Tamil and English are all in real use. MVP ships English only, with Sinhala and
  Tamil named as future work — which makes copy externalisation a day-one discipline rather than a
  retrofit.
- **Payments.** LKR consumer card acquiring in Sri Lanka is dominated by local gateways; PayHere is the
  leading candidate. **No gateway has been chosen** (OQ-05).
- **Mobile-first usage.** Mobile is an MVP surface, not a later phase.
- **Data protection.** Sri Lanka's Personal Data Protection Act applies to the contact details and
  user-uploaded imagery this system stores. No compliance posture has been decided (OQ-32).

## Business Specifics

This is a **greenfield build with no legacy system to migrate from or replicate** — which removes a large
class of risk and adds another: there is no existing behaviour to fall back on when a requirement is
ambiguous, so ambiguity has to be resolved by decision rather than by observation.

What exists today, in `advertising/`:

- **Three client skeletons**, all booting, all rendering hard-coded fixtures: `frontend-web` (Next.js
  14.2), `management-portal` (Vite 5.3 + React 18.2), `mobile` (Expo ~51 / RN 0.74.7), wired as npm
  workspaces.
- **Two complete design systems** — a consumer set and a deliberately different operator set — and 17
  Stitch screen exports covering roughly half the surfaces the requirements imply.
- **No backend at all.** Five services across two runtimes plus a gateway, entirely to be built.
- **No git history, no CI, no tests, and an unenforced linter** (`lint` is aliased to `tsc --noEmit`).

Two capabilities are **fully designed but appear in no locked decision**, and both are large:

1. **AI/OCR-assisted ad intake** — the admin review screen presents a source image, raw OCR text, and
   per-field extracted values with confidence levels and warnings. This implies an ingestion path where
   an ad originates as a photograph of a paper or WhatsApp advert. It is also the clearest technical
   justification for FastAPI being in the stack. (OQ-02)
2. **In-app messaging** — the account surface renders a Messages count and per-ad inquiry counts, and the
   consumer design system specifies a Chat primary action. (OQ-01)

Neither should be discovered mid-delivery. Both need an explicit in/out call at Gate 1.

## Scope and Boundaries

### In Scope (V1)

Ordered by the locked build order. Each row is elaborated in §Functional Surface.

| ID | Capability | Priority | Definition of done |
|---|---|:--:|---|
| S-1 | **Platform foundation** | P0 | Gateway routes to both runtimes; shared JWT validation in each; Postgres + migrations per runtime; object storage; both design-system token sets and their primitives; real lint/typecheck/test/build green per repo; dependency-vulnerability gate; structured logging with correlation ids; **one-command local boot of the whole stack**; deterministic seed dataset |
| S-2 | **Accounts** | P0 | Email/password registration with verification, Google OAuth, **account linking across both methods**, password reset, profile, session handling on all three clients, operator roles |
| S-3 | **Ad creation** | P0 | **Six-stage AI-guided wizard** with draft persistence and resume: category + subcategory, essential fields (title ≤70, description ≤4000, condition, LKR price with negotiable flag) rendered from the category's versioned schema, a **bounded set of decision-model-selected follow-up questions**, multi-photo upload with a main photo, Province → District → City, **AI-drafted title and description the seller edits and accepts**, **AI attribute suggestions the seller accepts or ignores**, preview, T&C gate, submit → `pending`. Every AI output is a suggestion; none writes ad state without explicit seller acceptance, and the flow completes with every AI integration disabled |
| S-4 | **Moderation** | P0 | Oldest-first queue with age and flags; review with pre-approval field edits; approve; reject with a reason the seller can see; append-only decision history; bulk actions. **Plus the hard invariant: a non-`active` ad is invisible on every public read path across all three clients** |
| S-5 | **Public discovery** | P0 | Category-led home with counts and a featured rail; free-text search; the full filter rail (category, location, price, condition, category-specific attributes, verified-sellers-only) with active-filter chips; three sort orders; grid/list toggle; result counts; cursor pagination; ad detail with spec table and `LL-NNNNN` reference; favourites |
| S-6 | **Featured payment** | P0 | Promotion plan catalogue and its administration; purchase against an `active`, owned ad only; gateway integration with **idempotent** settlement; featured window started only on settlement; server-side featured-first ranking; expiry back to ordinary ranking; purchase history and operator reconciliation |
| S-7 | **Operator administration** | P1 | Dashboard KPIs with trends and by-category / by-province breakdowns reconciled against source data; advertisements register with filters, flagged count, CSV export, operator ad creation; user administration; category and attribute-schema administration |
| S-8 | **Report an ad** | P1 | Reporting intake feeding the operator flagged queue, plus a resolution workflow. Closes the loop on an operator surface that currently has no input |
| S-9 | **Hardening** | P1 | WCAG 2.1 AA verified per surface with an automated scan in CI; authorisation matrix tested per role; performance measured at planning volumes; empty/loading/error states everywhere; ad expiry job |

**Mobile is not a scope row.** It is a surface. Every user-facing row above ships its mobile equivalent —
§Success Criteria makes that an acceptance criterion, not a stretch goal.

### Out of Scope

- Sinhala and Tamil UI. `[LOCKED]`
- Any seller charge other than featuring an approved ad — no listing fees, no subscriptions, no
  commission. `[LOCKED]`
- Auto-publication without moderation, under any condition, for any seller tier. `[LOCKED]`
- Buyer↔seller settlement, escrow, or any money movement between users. The platform's only money path is
  a seller paying the platform for featuring.
- Ratings and reviews, saved searches with alerts, seller storefronts, price-history analytics. None
  appear in any input; naming them keeps the boundary explicit.
- Native desktop apps; web is the desktop surface.

### Deferred (Post-V1)

| Capability | Reasoning | Trigger to revisit |
|---|---|---|
| **In-app messaging** (threads, notifications, read state, message-content moderation) | Large feature absent from every locked decision, though the UI assumes it. Phone contact covers the MVP job. **Recommendation, not a decision — OQ-01** | Once moderation load is understood and phone-contact conversion is measured |
| **AI-generated price guidance** | Requires a corpus of comparable published ads that a greenfield marketplace does not have. The service ships behind a per-category switch, default off | Per category, once that category holds enough recently-published ads to meet the comparator threshold |
| **AI-generated Sinhala and Tamil ad content** | Distinct from the deferred Sinhala/Tamil *UI* below, but blocked by the same locked decision | A formal reversal of the English-only decision, covering Sinhala/Tamil font loading and moderator staffing against the 24-hour review promise |
| Sinhala and Tamil UI | Named as future work in the locked decisions | Post-MVP, with copy already externalised |
| Separate search service or read model | A separate read model adds an eventual-consistency bug class to the most visible surface in the product | When measured `GET /ads` latency justifies it |
| Finer operator roles beyond Moderator and Super Admin | Two roles until a real permission conflict appears | First genuine conflict |

### Phasing / Sequencing Intent

The build order is locked and is a correctness constraint, not a prioritisation preference — each stage is
the precondition of the next. Moderation is meaningless without accounts to attribute ads to; discovery is
meaningless without approved ads to discover; featuring is meaningless without an approved ad to feature.

```
S-1 foundation → S-2 accounts → S-3 creation + S-4 moderation → S-5 discovery → S-6 featured payment → S-7/S-8/S-9 hardening
```

Two sequencing consequences worth stating explicitly:

- **Payment is last.** The original pack's own instruction: *"Do not build payment capture before an
  approved ad can be promoted."*
- **Foundation is large.** Thirteen substrate slices, not a week's work. It is the direct consequence of
  the polyglot-microservice decision (R-1) and it all lands before the first user-visible feature.

## Domain Model

### Key Entities

| Entity | Description | Key Relationships |
|--------|-------------|-------------------|
| **Account** | One identity that both sells and buys. No separate seller entity | has Credential and/or OAuthIdentity; has Roles; may have SellerVerification |
| **Advertisement** | The core aggregate. Owned by one Account, filed under one Category, located at one City, priced in LKR | owns AdvertisementAttributes, ordered MediaAssets, ModerationDecisions, AdMetrics |
| **Category** | Two-level taxonomy — top-level category and subcategory | has CategoryAttributeDefinitions; parent/child self-relation |
| **CategorySchemaVersion** | Immutable, versioned per-category question schema — field keys, labels, input types, validation, visibility and required conditions, follow-up eligibility and priority, AI sensitivity, filter mapping, re-moderation triggers. **The source of truth for every seller question and every structured public filter** | a draft pins one version at creation; supersedes the flat CategoryAttributeDefinition |
| **AdvertisementAttribute** | An accepted answer, projected out of the schema into a typed, filterable row | belongs to Advertisement; keyed by schema field |
| **AdCreationSession** | Resumable wizard state — resolved stage, answer snapshot, question budget, last decision source | belongs to Advertisement |
| **QuestionDecision** | Redacted trace of a decision-service call: the questions offered, the probabilities returned, and whether the result or the deterministic fallback was used | belongs to AdCreationSession |
| **ContentGeneration** | An AI-drafted title/description candidate with its source draft version, answer hash, prompt version, and status (proposed / accepted / rejected / stale / failed) | belongs to Advertisement |
| **AttributeSuggestion** | A proposed value for an empty schema field, with evidence and confidence, pending explicit seller acceptance | belongs to ContentGeneration |
| **AuditEvent** | Append-only record of decisions, suggestion acceptance and rejection, submission, moderation and publication | references Advertisement |
| **Province / District / City** | Fixed, strictly nested reference geography | Advertisement → City → District → Province |
| **ModerationDecision** | Append-only record of an approve/reject, its reason, its author, and any pre-approval field edits | belongs to Advertisement |
| **PromotionPlan** | A featuring product: price and duration | referenced by FeaturingPurchase |
| **FeaturingPurchase** | Joins Account + Advertisement + Plan to a paid featured window | has PaymentTransactions |
| **PaymentTransaction** | The gateway conversation, unique on gateway reference — the **idempotency key** | belongs to FeaturingPurchase |
| **MediaAsset** | An uploaded image plus its derivatives and content checksum | referenced by Advertisement |
| **AdReport** | A person reported an ad. Distinct from machine-generated flags | belongs to Advertisement |
| **Favourite** | Account ↔ Advertisement, unique on the pair | — |

**Attribute modelling is settled (OQ-30): a versioned schema document, projected into typed rows.** The
two candidates each failed alone — a flat dynamic definition table cannot express the visibility
conditions, required conditions, AI sensitivity, and follow-up eligibility the guided flow needs, while
per-category typed models cannot be edited by an administrator without a deploy. So the schema *document*
is authoritative for asking and validating, and every accepted answer is projected into a typed
`AdvertisementAttribute` row so multi-attribute search filtering stays indexable. One source, two
representations, with the projection owned by `listing-service`.

**All nine category schemas are authored in full (OQ-04)** — Vehicles (cars, motorcycles,
three-wheelers, vans/buses/lorries), Property, Land, Jobs, Electronics, Services, Home & Garden, Fashion
and Other — together with the reference datasets they depend on: vehicle makes and models, property
types, land extent units, and job families. Every dynamic data source carries an `Other` manual fallback
wherever its data may be incomplete.

Full field-level modelling, the index plan, and the cross-service ownership map are in
`.forge/discovery/docs/04-data-model.md`.

### Lifecycle States

**Advertisement** — the product's central invariant. Transitions are owned exclusively by
`listing-service`; the operator BFF requests them and never performs them.

```
draft → pending → active → sold
          ↓         ↓
       rejected   expired
          ↓         ↓
     (revise) → pending
```

- Only `active` is publicly readable, searchable, and eligible for featuring.
- `pending` is invisible on every public read path — and a hidden ad returns **404, not 403**, because a
  403 confirms existence and leaks the moderation queue.
- Editing a moderated field on an `active` ad returns it to `pending`; the exact moderated-field set is
  OQ-14.
- Expiry duration is undecided (OQ-07).

**FeaturingPurchase:** `initiated → settled | failed → refunded`. The featured window starts on
`settled` only.

### Glossary

| Term | Meaning |
|------|---------|
| **Ad / Advertisement** | A single listing. Public reference format `LL-NNNNN`, distinct from the internal id |
| **Featuring / Promoting** | The paid product: an approved ad ranks above non-featured ads and renders a promoted treatment for a paid window |
| **Moderation** | Human review before publication. The product's core quality mechanism |
| **Flag** | A **machine-generated** signal on a queued ad (price anomaly, duplicate images). Distinct from a Report |
| **Report** | A **human-submitted** complaint about a published ad |
| **Verified Seller** | An account-level trust badge, surfaced on cards and as a search facet. **What earns it is undecided** (OQ-08) |
| **Negotiable** | Seller-set flag meaning "open to offers" |
| **Reconditioned** | A condition value offered as a search facet but not (yet) as a create-form option — OQ-34 |
| **Surface** | One of the three clients: public web, management portal, mobile app |
| **Slice** | A vertical unit of delivery — service + persistence + every affected client + tests |

## Users and Access

### Roles

| Role | Description | Primary Capabilities |
|------|-------------|----------------------|
| **Visitor** | Unauthenticated | Browse categories, search and filter, view an approved ad, begin sign-up |
| **Member** | Authenticated. One account type sells and buys | Create/edit/delete own ads, save favourites, view own ad performance, purchase featuring for an approved own ad, manage profile |
| **Moderator** | Operational staff | Review the queue, approve, reject with reason, edit fields pre-approval, action reported ads |
| **Super Admin** | Full operator | Moderator capabilities plus user administration, category and attribute-schema administration, promotion plan administration, reports, settings |

Three distinct authorisation questions, none answerable at the gateway, each enforced in-service:

1. **Is this ad publicly readable?** Only if `active`. Enforced on every read path.
2. **Does this member own this ad?** Every seller mutation and every featuring purchase is
   ownership-scoped.
3. **Is this operator permitted?** Role-checked in the service, not only at the gateway.

### Multi-Tenancy / Org Hierarchy

None. A single marketplace, a single operator organisation. No tenant isolation model is required.

## Functional Surface

Each subsection summarises a scope row. Requirement-level detail (FR-1…FR-48, R-1…R-7, with per-statement
provenance) is in `.forge/discovery/docs/01-product-requirements.md`.

### Platform foundation (S-1)

The substrate every feature assumes: an API gateway, JWT validation working independently in both
runtimes, per-service Postgres with migration tooling in both runtimes, object storage and an image
pipeline, both design-system token sets with their atomic components, a real linter, a test harness per
tier per runtime, structured logging with correlation-id propagation, the dependency-vulnerability CI
gate, one-command local boot of the whole stack, and a deterministic seed dataset.

The tooling-versus-instance line holds: *migration tooling configured* is foundation; *the ads table
migration* is a feature.

### Accounts (S-2)

Email/password registration with email verification gating publication, Google OAuth, and — as its own
deliverable rather than a sub-task of OAuth — **account linking**, so signing in with Google against an
existing email-registered address resolves to one identity instead of creating a duplicate. Plus password
reset, profile management, session and token handling across all three clients with secure token storage
on mobile, and operator role assignment.

### Ad creation (S-3)

A **six-stage** AI-guided wizard with draft persistence at every stage, autosave, an explicit
*Save as Draft* affordance, and resume on a later session or device:

| Stage | Purpose |
|---|---|
| 1. Choose category | Category and subcategory. Changing it later requires confirmation, because category-specific answers can be removed |
| 2. Essential details | Every required core and category field, rendered from the category's pinned schema version |
| 3. Smart follow-ups | A **bounded** set of optional questions selected by the decision service from the schema's eligible set. Always skippable |
| 4. Photos and location | Multi-photo upload with ordering and a designated main photo, plus Province → District → City |
| 5. Generate and refine | AI-drafted title and description, and AI attribute suggestions. Every one is editable, and acceptance is explicit |
| 6. Contact, preview and submit | Contact preference, full buyer-view preview, T&C gate, submit → `pending` |

Common fields carry hard constraints read off the designs: title required and ≤70 characters with a live
counter, description required and ≤4000 with a live counter, condition, LKR price with an optional
negotiable flag. Category-specific attributes are rendered from the category's **versioned schema**
rather than hard-coded per category — the same definitions that drive the detail spec table and the
search filter rail. Mobile includes native camera and photo-library permissions. The final stage states
the moderation expectation to the seller and offers featuring as a **deferrable** upsell that never
blocks publication.

**The stepper contradiction is resolved (OQ-03).** The two Stitch variants disagreed on whether step 4
was Preview or Price & Contact, and both carried a pricing block — which was the tell. Price is a
*required core field*, so it belongs in stage 2 with the other essentials; contact preference, preview
and submit merge into a single final stage. The six-stage shape then adds the two genuinely new surfaces
(Smart follow-ups, Generate and refine) without inheriting either stale variant.

**Photo limits are set (OQ-12):** minimum 1, maximum 12, 5 MB per file, accepting JPEG, PNG, WebP and
HEIC. Twelve matches the gallery design; the mobile upload copy saying "up to 10" is stale and is
corrected. HEIC is accepted because iPhone is a common capture device in-market.

**AI is assistive, never authoritative.** The category schema — not the decision service and not the
language model — is the source of truth for what is asked, what is required, what validates, and what
becomes a public filter. Every AI result is a suggestion the seller can edit, accept, reject or ignore;
none writes ad state without explicit acceptance; and a seller can complete and submit an ordinary ad
with every AI integration failed or switched off. Any edit that changes the answer snapshot marks
dependent AI output **stale** rather than silently reusing it.

### Moderation (S-4)

An oldest-first queue showing age, seller, category and machine-generated flags. Review allows field
edits before approval. Approve transitions to `active` and stamps `published_at`; reject records a reason
code and note that the owning seller can see, with a revise-and-resubmit path. Every decision is recorded
append-only for operator accountability and repeat-offender handling. Bulk approve/reject on a selection.

**The invariant that matters most:** a non-`active` ad is invisible on every public read path — browse,
search, featured rail, detail by reference — on all three clients, returning 404 rather than 403. This is
enforced at a single query layer no read path can bypass, and it is the product's core promise expressed
in code.

### Public discovery (S-5)

A category-led home with real per-category counts and a featured rail. Free-text search over title and
description, scoped by category and location from the header. A filter rail covering category, location
at any hierarchy level, LKR price range, condition, the category-specific attribute block, and a
verified-sellers-only toggle — with individually dismissible active-filter chips and Clear All, all
keyboard-operable. Three sort orders, grid/list toggle, a result count, and cursor pagination. An ad
detail page rendering the gallery, the attribute-driven spec table, description, price, location,
relative posted-at, the `LL-NNNNN` reference, and seller contact with its verification marker. Favourites
from both card and detail, with a Saved Ads list.

**Featured-first ordering is applied server-side within the requested sort.** Three clients must not each
invent a ranking.

### Featured payment (S-6)

A promotion plan catalogue with price and duration, administered in the portal. Purchase is offered only
against an `active` ad owned by the caller, verified server-side — anything else is rejected. Gateway
integration captures payment in LKR; settlement arrives by webhook, is signature-verified, and is
**idempotent on the gateway reference** so a redelivered settlement yields exactly one featured window.
The window starts on settlement only, never on initiation. Plan price is captured at purchase time.
Expiry returns the ad to ordinary ranking without changing its `active` status. Sellers see what they
paid for and when it expires; operators can reconcile.

**Blocked:** no gateway is chosen (OQ-05), no plan catalogue exists (OQ-06), and the featured-versus-organic
interleave is undecided (OQ-11). This flow also has **no design artefact whatsoever** — see
`.forge/discovery/flows/02-featuring-payment.md`, including its failure paths, which are real,
user-visible, and entirely undesigned.

### Operator administration (S-7)

Dashboard KPIs with trend deltas (awaiting review, active, reported, new users today) plus by-category and
by-province distributions, all reconciled against source data. An advertisements register with status /
category / location filters, a flagged count, CSV export, and operator-side ad creation. User
administration. Category and attribute-schema administration — the schemas of S-3 have to be editable
somewhere.

### Report an ad (S-8)

Reporting intake with reason codes, feeding the operator flagged queue, plus a resolution workflow. The
operator side already exists in the designs; the intake does not.

### User Journeys

Two flows are documented step-by-step with sequence diagrams, rules, and their unresolved decisions:

- **Seller: post an ad through to live** — `.forge/discovery/flows/01-seller-post-to-live.md`
- **Seller: feature an approved ad** — `.forge/discovery/flows/02-featuring-payment.md`

### Integration Points

| System | Direction | Purpose |
|--------|-----------|---------|
| Google OAuth | Outbound | Federated sign-in (locked requirement) |
| Payment gateway (**undecided** — OQ-05) | Bidirectional | LKR capture for featuring; settlement webhook inbound |
| Transactional email (**undecided** — OQ-29) | Outbound | Verification, password reset, rejection notice, receipts |
| Object storage + CDN (**undecided** — OQ-24) | Bidirectional | Ad imagery and derivatives |
| Apple App Store / Google Play | Outbound | Mobile distribution — a release path the web surfaces do not have |
| OCR / vision model (**conditional** — OQ-02) | Outbound | Only if AI intake is scoped in |

## Non-Functional Requirements

### Performance

No targets are stated in any input (OQ-09 covers the one operational promise that is). The only volume
signal available is the designs' own mock data — 24,150 active ads, 482 pending, 156 new users per day —
which is a reasonable MVP planning basis and nothing more. `[PROPOSED]`

Where performance work actually lands: `GET /ads` is the busiest endpoint in the product and every
consumer discovery surface across three clients funnels through it; the operator dashboard's by-province
aggregation must not join three levels of geography per page load; and a listings marketplace is
image-bandwidth-dominated, so image delivery is a CDN concern rather than an application concern.

### Security and Compliance

- **Authentication** — short-lived JWT access tokens plus refresh tokens, issued by `identity-service`,
  validated independently by every service. Gateway validation is not a substitute: any service reachable
  inside the network is otherwise unprotected. Mobile stores tokens in the platform secure store, never
  AsyncStorage.
- **Authorisation** — the three questions in §Users and Access, each enforced in-service.
- **Money** — exact integer LKR minor units end to end. No floating point in the money path, in any of
  five services or three clients.
- **Idempotency** — payment webhooks are keyed on a unique gateway reference. Settlements are redelivered
  in practice, not in theory.
- **Information leakage** — hidden ads return 404 rather than 403; error messages never leak internals;
  contact details never reach log output.
- **Supply chain** — a dependency-vulnerability CI gate at a chosen CVSS threshold (OQ-33), wired once in
  foundation and confirmed green per change rather than re-decided.
- **Data protection** — Sri Lanka's PDPA applies. Retention, export, and deletion-cascade posture is
  undecided (OQ-32) and is cheaper to decide now than to retrofit; it shapes account deletion, media
  retention past ad deletion, and PII handling in logs.

### Accessibility

**WCAG 2.1 AA.** `[PROPOSED]` — no standard is named in the inputs, but the original pack requires
accessibility checks in every change's definition of done, which needs a named target to be testable.

Verified per-surface rather than at the end, with an automated scan on every page visited during E2E.
Four specific risks are already visible in the designs: the exports use generic containers throughout and
will not produce semantic landmarks or heading order by default; the filter rail, wizard stepper, table
inline row actions and bulk toolbar are all hover-revealed or pointer-first; the specified focus states
are not rendered in any export; and the @10%-opacity status chips plus 12px metadata text are the two most
likely contrast failures in the current palettes.

### Observability and Audit

Observability in every change is `[LOCKED]` in principle by the original pack's definition of done; the
stack is undecided (OQ-27).

Minimum: structured JSON logs on one schema across both runtimes; a correlation id propagated
gateway → service → service and returned to clients on error; client-side error reporting with release
tagging in all three clients, because a mobile client in the field cannot be debugged from server logs.

Domain events logged explicitly: ad submitted / approved / rejected with reason / expired; featuring
initiated and settled; webhook received and its idempotency outcome; login failure rate.

Operational metrics tied to real promises: **moderation queue depth and oldest-pending age** — the
24-hour promise is unmonitorable without them — plus `GET /ads` latency, image-upload failure rate, and
payment settlement success rate.

Audit: every approve, reject, pre-approval field edit, user suspension and plan change is attributable
and append-only.

## Constraints

### Tech Stack

**Mandatory** `[LOCKED]`: Next.js for the public marketplace; Vite + React for the management portal;
Expo React Native for mobile; a microservice backend using **both** Spring Boot and FastAPI, with FastAPI
serving the management portal's CRUD surface.

**Confirmed (OQ-21):** the five-service split and its language boundary stand — JVM owns the transactional
core (identity, listing, payment), Python owns image/ML work and the operator BFF (admin, media) — **plus
`gateway-service`**, which is edge infrastructure rather than a sixth business service. The gateway is the
single browser origin: it owns CORS, performs authentication and coarse route-level role gating, and every
service still enforces resource-level authorisation independently, because gateway-only enforcement leaves
anything reachable inside the network unprotected. `/api/v1` from the first commit, because an installed
mobile client cannot be force-updated in step with a server deploy.

**Confirmed (OQ-23):** PostgreSQL 17, database-per-service. S3-compatible object storage.

**Java platform:** Java 17, Spring Boot 3.5.16, Gradle, Flyway, Testcontainers — previously undecided,
now fixed by the service the identity fork is based on. Tokens are RS256: `identity-service` signs with
the private key, and the gateway and every other service verify with the public key only, which also
settles the key-distribution question the pack left open.

**Confirmed (OQ-25):** asynchronous work runs on the **database-backed lease queue already proven in
`media-service`** — claim token, lease, heartbeat, reaper — rather than introducing a broker. It carries
content generation and attribute extraction now, and is the default for settlement, notifications and
derivative generation unless measured load justifies a broker later.

**External AI providers** — no prior decision named one. Two are now in the stack, both server-side only,
both behind an internal adapter interface with a deterministic fake for tests and an administrator kill
switch: **TypeSafe Jev** (`jev-latest`) as the structured decision engine, called by `listing-service`;
and the existing swappable LLM provider registry in `media-service` for ad copy and attribute extraction.
Neither is ever called from a browser, and neither receives account email, phone, credentials, session
tokens, exact address, or raw image bytes.

**Open:** notification mechanism, observability stack, deployment target and orchestration, CI/CD
platform, and email provider (OQ-24, OQ-26…OQ-29, OQ-31…OQ-34).

### Regulatory

Sri Lanka's Personal Data Protection Act, scope and posture undecided (OQ-32). Consumer-facing Terms of
Service and Privacy Policy are required — the publish wizard already gates on accepting both, so the
documents themselves are a delivery dependency, not a nice-to-have.

### Deployment and Hosting

Entirely undecided (OQ-28) — a Gate-2 output. Three environments are assumed: local (whole stack bootable
by one command, non-negotiable at five services plus three clients), staging (full stack with a gateway
sandbox and seeded deterministic data), and production (Sri Lanka-proximate region for latency).

## Input Sources

| Source | Date / Version | Used For |
|--------|----------------|----------|
| Original engineering pack index — `advertising/discovery/README.md` | 2026-08-24 | The seven locked MVP product decisions; the locked build order. **The only original document that existed** |
| Reconstructed engineering pack — `.forge/discovery/docs/01`…`08` | Reconstructed 2026-08-24 | Requirements, UX scope, architecture, data model, API contract, delivery plan, backlog, decision log |
| Consumer design system — `stitch_advertising/lankalistings/DESIGN.md` | 2026-08-24 | Consumer token set, Corporate Modernism direction, component and formatting rules |
| Operator design system — `stitch_advertising/lankalistings_operational_interface/DESIGN.md` | 2026-08-24 | Operator token set, data-table / metric-card / status-chip specs, sidebar dimensions |
| 17 Stitch screen exports — `stitch_advertising/*/code.html` + `screen.png` | 2026-08-24 | Field lists and constraints, wizard steps, filter sets, admin IA, ad status vocabulary, the AI/OCR review surface, product copy commitments |
| Client skeletons — `frontend-web/`, `management-portal/`, `mobile/` | 2026-08-24 | Committed stacks and versions; existing fixtures and their replacement sites; the tooling gaps |
| Product-owner scoping conversation | 2026-08-24 | Microservices with Spring Boot + FastAPI; FastAPI for management-portal CRUD; mobile in MVP scope |

## Risks

| # | Item | Owner | Status |
|---|------|-------|--------|
| R-1 | **Polyglot microservices at MVP multiplies foundation cost** and it all lands before the first user-visible feature — per-service CI/CD, gateway, distributed auth, cross-service transaction reasoning, correlated observability, and a whole-stack local boot story. *Mitigation:* minimum service count; a capability-based language boundary; a time-boxed two-service spike (F-002) that either de-risks the shape or triggers the documented fallback to two deployables; re-examine granularity at the first retrospective | Lead / Gate 2 | open |
| R-2 | **Design debt is roughly as large as the design that exists** — 13 screen groups exist, ~11 are missing, including the **entire payment flow** (the only revenue path) and the **entire auth flow** (the first thing every user touches). Gate-3 sizing that treats UI as a thin layer over ready designs will be wrong | Lead / Gate 3 | open |
| R-3 | **Two large capabilities are designed but unscoped** — AI/OCR intake and messaging. Both are already visible in the UI, so leaving them undecided means either building them unplanned or shipping dead affordances | Product / Gate 1 | open |
| R-4 | **One of nine category attribute schemas is specified.** The mechanism shapes ad creation, ad detail, search filters and admin taxonomy simultaneously — four surfaces at once. *Mitigation:* spike the mechanism against Vehicles plus two structurally different categories before Gate 3 | Lead / Gate 2 | open |
| R-5 | **No payment gateway chosen, and the revenue flow's worst failure mode is invisible by default** — payment settles but the featured window fails to start. *Mitigation:* choose the gateway at Gate 2; build reconciliation and an operator alert deliberately, not as a log line | Lead / Gate 2 | open |
| R-6 | **Three clients × five services is a wide seam surface.** Expect boundary defects: enum casing, error-shape divergence, money as float, timestamp format, pagination style. *Mitigation:* T3 seam tests against a frozen per-wave contract as the primary defect net; one generated API client per surface from a single schema source | Lead | open |
| R-7 | **Mobile can fall permanently behind.** A native client treated as a trailing surface ends up features behind the web client. *Mitigation:* parity is an acceptance criterion of every milestone (SC-11), and store submission is a milestone gate from S-2 onward — store review latency should not be discovered at hardening | Lead | open |
| R-8 | **The committed skeletons have no git history, no CI, no tests, and an unenforced linter.** Until foundation lands, "lint and tests pass" cannot be truthfully claimed on this project | Lead | open |
| R-9 | **No team size and no delivery window exist in any input.** Nothing sized at Gate 3 is trustworthy until they do (OQ-20) | Product | open |
| R-10 | **This PRD derives from a reconstructed pack, not from source documents.** Its `[PROPOSED]` content is engineering judgement filling real gaps. *Mitigation:* every proposal is tagged and tracked in `project-prd-signals.md`; Gate 1 converts each into a decision or a deferral | Lead / Gate 1 | open |

## Success Criteria

### Functional acceptance

Demonstrable end-to-end across the public web, management portal, **and** mobile app.

| # | Criterion |
|---|-----------|
| SC-1 | A visitor registers with email/password, verifies the address, and signs in |
| SC-2 | A visitor registers and signs in with Google, and a second sign-in via the other method resolves to the **same** account |
| SC-3 | A member completes the post-ad wizard for a Vehicles ad; it lands in `pending`, not public |
| SC-4 | The ad is invisible to an unauthenticated visitor in browse, in search, and by direct URL while `pending` |
| SC-5 | A moderator sees it in the queue with its age, opens it, edits a field, and approves it |
| SC-6 | The approved ad is immediately findable by category, location, price range and free-text search, and renders fully with its `LL-NNNNN` reference |
| SC-7 | A moderator rejects a different ad with a reason, and the owning seller sees both the state and the reason |
| SC-8 | The seller buys featuring for the approved ad, payment settles, and the ad thereafter renders promoted and ranks above non-featured ads in the same result set |
| SC-9 | Featuring **cannot** be purchased for an ad that is not `active` |
| SC-10 | The seller marks the ad sold and it leaves public discovery |
| SC-11 | Every one of SC-1…SC-10 is completable on the mobile app **and** at a 375px browser viewport |
| SC-12 | The admin dashboard's counters agree with the underlying data |
| SC-13 | An automated accessibility scan passes at WCAG 2.1 AA on every page visited in SC-1…SC-11 |
| SC-14 | Every public and operator endpoint rejects unauthenticated and cross-owner access with the documented error contract |
| SC-15 | A redelivered payment settlement webhook produces exactly one featured window |

### Business outcomes

- A seller can go from "I have something to sell" to a live ad **without assistance**.
- A buyer can express a real query — category, location, price ceiling, category-specific attributes —
  and get relevant local results.
- The moderation queue stays inside its 24-hour promise at planning volumes, and the promise is
  **monitored**, not assumed.
- Featured ads convert: sellers who pay can observe the difference.
- The corpus stays worth searching. Moderation is the mechanism; queue depth and report rate are the
  measures.

## Sidecar Files

This PRD is the **live contract** — the frozen-at-Gate-1 statement of what we are building. Two sidecar files carry the content classes that change post-Gate-1 or are pure bookkeeping:

| File | Contents | Lifecycle |
|------|----------|-----------|
| [`project-prd-signals.md`](project-prd-signals.md) | Live signals — open and partial open questions, anchored to PRD sections and (optionally) to features that they block. | Authored as questions surface (interview, gates, mid-engagement). Resolved by folding the answer into this PRD body and moving the row to `project-prd-history.md`. |
| [`project-prd-history.md`](project-prd-history.md) | Audit trail — resolved open questions and PRD revisions. | Append-only. |

The OQ resolution procedure and shape-enforcement rules live in [`.claude/rules/prd.md`](../.claude/rules/prd.md) (path-scoped — loads when any `project-prd*.md` file is read or edited).
