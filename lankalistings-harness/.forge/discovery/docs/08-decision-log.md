# 08 — Decision Log

> Reconstructed 2026-08-24. Provenance tags per `README.md`.
> **Confirmed decisions** are locked and reversing one is a PRD revision. **Open decisions** are the
> authoritative list of what Gate 1 and Gate 2 must resolve; each is mirrored as a row in
> `.forge/project-prd-signals.md`, which is the live tracking home.

## Part A — Confirmed decisions

### From the original pack index — product

| # | Decision | Rationale |
|---|---|---|
| D-01 | Any user may create an advertisement | Open marketplace; no seller onboarding gate |
| D-02 | Nine broad categories: vehicles, property, land, jobs, electronics, services, home & garden, fashion, other | Generalist classifieds positioning |
| D-03 | An ad is public **only** after admin approval | Quality and spam control is the product's core promise |
| D-04 | Standard publication is free; the seller pays only to feature an approved ad | Supply-side growth first, monetise attention |
| D-05 | Google OAuth **and** email/password | Low-friction sign-up without excluding non-Google users |
| D-06 | Sri Lanka; LKR; Province → District → City | Single-market product |
| D-07 | English-only UI at MVP; Sinhala and Tamil are future work | Scope control, with localisation named as a known future need |
| D-08 | Build order: foundation → accounts → ad creation/moderation → discovery → featured payment → hardening | Each stage is the precondition of the next |
| D-09 | Payment capture is not built before an approved ad can be promoted | Correctness constraint — featuring is meaningless without an approvable ad |

### From the 2026-08-24 scoping conversation

| # | Decision | Rationale |
|---|---|---|
| D-10 | Public marketplace is Next.js; management portal is Vite + React | Already committed as skeletons |
| D-11 | A mobile app (Expo React Native, Android + iOS) is an **MVP surface**, not a later phase | Product owner: "this app will also be available as a mobile app" |
| D-12 | The backend is **microservices** | Product owner |
| D-13 | Both **Spring Boot and FastAPI** are used as backend runtimes | Product owner |
| D-14 | FastAPI serves the **management portal's CRUD** surface | Product owner |

### Engineering decisions taken during reconstruction

Recorded so they are visible and challengeable, not smuggled in. Each is `[PROPOSED]` and needs Gate
confirmation, but each is a decision the reconstruction had to make to be coherent.

| # | Decision | Rationale | Confirm at |
|---|---|---|---|
| D-15 | Design-system front-matter tokens are authoritative; the prose hexes in `DESIGN.md` are illustrative | The two disagree (doc 02 §2) and the front-matter is what the Stitch screens compile from | Gate 2 |
| D-16 | Two separate token files — consumer for web + mobile, operational for the portal | The two systems assign **different values to the same token names**; one shared file corrupts both | Gate 2 |
| D-17 | Language split follows capability: JVM owns the transactional core, Python owns image/ML work and the operator BFF | Makes "why is this in Python?" answerable the same way every time | Gate 2 |
| D-18 | Five services: identity, listing, payment (Spring Boot); admin, media (FastAPI) | Minimum count that satisfies D-12/D-13/D-14 without inventing boundaries | Gate 2 |
| D-19 | `admin-service` is a BFF and **never writes ad state** — it requests transitions from `listing-service` | Two code paths that can approve an ad defeats D-03 | Gate 2 |
| D-20 | Search stays inside `listing-service` at MVP; no separate search service or read model | A separate read model adds an eventual-consistency bug class to the most visible surface | Gate 2 |
| D-21 | Money is stored and transported as integer LKR minor units, never float, never a formatted string | Standard money discipline; three clients formatting independently makes a wire-format string dangerous | Gate 2 |
| D-22 | `/api/v1` from the first commit | An installed mobile client cannot be force-updated in step with a server deploy — D-11's hidden cost | Gate 2 |
| D-23 | Ads are addressed publicly by `reference` (`LL-NNNNN`), not internal id | Already user-facing and quotable in the designs | Gate 2 |
| D-24 | A hidden (non-`active`) ad returns **404, not 403** | A 403 confirms existence and leaks the moderation queue | Gate 2 |
| D-25 | Cursor pagination on public collections; offset permitted on operator tables | Public corpus grows and mobile appends; operator tables want page numbers and stable totals | Gate 2 |
| D-26 | Vertical slicing by journey step, with all three clients shipped per slice | Alternatives (by service, by client, by layer) each defer integration risk — doc 07 | Gate 3 |
| D-27 | Mobile is a surface, not a milestone; AC-11 makes parity an acceptance criterion of every milestone | Prevents the native client falling permanently behind | Gate 3 |
| D-28 | Recommendation: **defer in-app messaging** past MVP, ship phone contact only | Large feature absent from every locked decision; deferring keeps MVP honest | **Gate 1 — needs a product decision, not an engineering one** |
| D-29 | Recommendation: **defer OCR/AI ad intake** past MVP, but keep the review UI's field-provenance model | Large capability absent from every locked decision; keeping the provenance model means turning it on later adds data rather than reshaping review | **Gate 1 — needs a product decision** |
| D-30 | Standardise on `lucide-react` for icons and map the exports' Material Symbols names centrally | Already a committed dependency in both web apps; mixed icon sets break the 1.5px stroke rule | Gate 2 |

## Part B — Open decisions

Ordered by blast radius. Each becomes a signals row; the "Blocks" column names what cannot proceed.

### Product decisions — Gate 1

| # | Question | Blocks | Notes |
|---|---|---|---|
| OQ-01 | **Is in-app messaging in MVP scope?** | An entire potential milestone; slice #26's inquiry counter; doc 02's Messages screen | The UI assumes it (`Messages / 5`, `12 Inquiries`, a `Chat` primary action) but no locked decision mentions it. See D-28 |
| OQ-02 | **Is OCR/AI ad intake in MVP scope?** | `media-service` scope; the review surface; the strongest justification for FastAPI | A fully designed admin screen exists for a capability no decision mentions. See D-29 |
| OQ-03 | Which of the two post-ad stepper variants is correct? | Slice #9, #12 — the create wizard cannot be built against two contradictory designs | `Photos → Preview → Publish` vs `Photos → Price & Contact → Publish`, and both screens carry pricing |
| OQ-04 | What are the attribute schemas for the eight non-Vehicle categories? | Slice #8 beyond three categories; create, detail, and filters simultaneously | The largest content gap in the pack (FR-9) |
| OQ-05 | Which payment gateway? | Slice #30 — the only revenue flow in the product | Nothing in the inputs names one. PayHere is the leading LKR candidate |
| OQ-06 | What is the promotion plan catalogue — names, prices, durations? | Slices #28–#32 | The admin surface to manage plans exists; the plans do not |
| OQ-07 | How long does an ad stay live before expiring? | Slice #40; `expires_at` | An `Expired` seller tab exists, so expiry is intended |
| OQ-08 | What earns the "Verified Seller" badge? | Verified-seller granting; the `Verified Sellers Only` filter is meaningless without criteria | Phone verification is the obvious candidate |
| OQ-09 | Is the 24-hour moderation promise a target or an SLA? | Operator staffing; queue tooling; NFR-6 monitoring | It is already literal UI copy shown to sellers |
| OQ-10 | Is the seller's phone number visible to unauthenticated visitors, or gated behind sign-in? | Slice #24 | Scraping exposure vs. conversion friction |
| OQ-11 | What is the featured-vs-organic ranking interleave? | Slice #31 | "All featured first" vs a capped allocation per page — affects both revenue and result quality |
| OQ-12 | Photo count limits, file size cap, accepted formats? | Slice #10 | Gallery shows 12; nothing states a maximum |
| OQ-13 | What are the rejection reason codes? | Slices #15, #16 | Required for R-3 and AC-7 |
| OQ-14 | Which fields are "moderated" and therefore trigger re-moderation on edit? | Slice #18 | R-4's exact field set |
| OQ-15 | Report-an-ad reasons, and can visitors report anonymously? | Slice #27 | Operator side exists; intake is undesigned |
| OQ-16 | What are the automated flags and the rule behind each? | Slice #14 | `Price anomaly`, `Duplicate images`, `Warranty claim` are free-text in the committed mock |
| OQ-17 | What is in Reports and Settings? | Slice #41 | Two sidebar destinations with no defined contents |
| OQ-18 | Are Moderator and Super Admin the only operator roles? | Slice #6 | Finer roles (content, finance) may be needed |
| OQ-19 | What counts as a "view"? | Slice #26 | Unique vs raw, bot filtering |
| OQ-20 | Team size and delivery window? | **All sizing and every date** | Absent from every input. Gate 2's Resource & Timeline Reality section cannot be completed without it |

### Architecture decisions — Gate 2

| # | Question | Blocks | Notes |
|---|---|---|---|
| OQ-21 | Confirm or reject the five-service split (D-18) and the language boundary (D-17) | All of M0 | The R-ARCH-01 spike (F-002) informs this |
| OQ-22 | Accept or reject `admin-service`'s read-only direct access to the listing store (D-19's exception) | Slices #33–#36 | If rejected, `listing-service` grows operator query endpoints |
| OQ-23 | Database engine per service | F-004 | PostgreSQL proposed — relational filtering, exact money, full-text search built in |
| OQ-24 | Object storage provider and CDN | F-005, slice #39 | An image-bandwidth-dominated product |
| OQ-25 | Asynchronous transport for settlement, notifications, derivative generation | F-002, slice #30 | Queue vs event bus vs scheduled polling |
| OQ-26 | Notification mechanism — a sixth service or a shared library? | M1 onward | A library plus one queue proposed |
| OQ-27 | Observability stack | F-009 | The pack requires observability per change but names nothing |
| OQ-28 | Deployment target, orchestration, CI/CD platform | F-008, F-010 | Sri Lanka-proximate region proposed for latency |
| OQ-29 | Transactional email provider | M1 | Verification, reset, rejection notices, receipts |
| OQ-30 | Attribute modelling: dynamic definitions or per-category typed models? | Slice #8 — and it shapes four surfaces at once | Dynamic proposed; spike against three categories first |
| OQ-31 | Mobile release pipeline, versioning, OTA-vs-store-update policy | Every milestone's mobile parity | Two app stores and review latency are a delivery path the web surfaces do not have |
| OQ-32 | Data-protection posture under Sri Lanka's PDPA — retention, export, deletion cascades | Doc 04 §8; slice #38 | No compliance regime is named in the inputs |
| OQ-33 | Dependency-vulnerability gate CVSS threshold | F-008 | Needs a number to be enforceable |
| OQ-34 | Is `Reconditioned` a create-form option, or search-only? | Slices #9, #22 | The create form offers two conditions; search offers three |

## Part C — Reconstruction caveat

Every `[PROPOSED]` line in this pack is an engineering proposal made to fill a genuine gap, not a
recorded decision. The seven documents in this folder were **reconstructed from artefacts, not
transcribed from source documents** — the originals never existed on disk.

Two consequences worth stating plainly:

1. **Gate 1 is not a formality here.** Its job is to convert the `[PROPOSED]` set into either `[LOCKED]`
   decisions or explicit deferrals. Twenty product questions in Part B is a genuine finding about the
   inputs, not a reconstruction artefact.
2. **OQ-01, OQ-02 and OQ-20 are the three that change the plan's shape** — two large undecided
   capabilities that the UI already assumes, and the complete absence of team size or delivery window.
   Nothing sized at Gate 3 is trustworthy until those three are answered.
