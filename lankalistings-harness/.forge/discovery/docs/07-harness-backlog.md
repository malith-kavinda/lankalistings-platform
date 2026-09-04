# 07 — Harness Backlog

> Reconstructed 2026-08-24. Provenance tags per `README.md`.
> **This is a proposal, not the decomposition.** `/forge-decompose` (Gate 3) regenerates
> `.forge/features.md` as the authoritative feature set. This document is the input to that
> conversation — a sequenced set of thin vertical slices with a definition of done each, sized so any
> one of them is independently reviewable.

The original pack's own instruction governs: *"Treat every backlog item as a small, independently
reviewable change. Before implementation, copy its acceptance criteria into the task brief."* `[LOCKED]`

## Slicing principle

**Vertical slices by journey step, per milestone.** Each slice owns its full stack — service endpoint,
persistence, all three clients where user-facing, and tests at the tiers doc 06 assigns. A slice that
ships a backend endpoint with no client, or a UI with a fixture, is not a slice; it is half a slice and
it hides integration risk until later.

Rejected alternatives, recorded so a future re-slicing conversation has the reasoning: `[PROPOSED]`

- **By service** (all of `identity-service`, then all of `listing-service`, …) — rejected: nothing is
  demonstrable until the last service lands, and the seam defects doc 06 §3 warns about surface at the
  end instead of continuously.
- **By client** (all web, then mobile) — rejected: guarantees the mobile client falls permanently behind
  and violates AC-11.
- **By layer** (all schemas, then all APIs, then all UI) — rejected: the classic horizontal-slice trap;
  no user-visible progress for a long time and no early feedback.

## Foundation slices — M0

Foundation is substrate, not features. The tooling-vs-instance test applies: *migration tooling
configured* is foundation, *the ads table migration* is a feature.

| ID | Slice | Definition of done | Repo(s) |
|---|---|---|---|
| **F-001** | Repository and workspace shape | Git initialised; service repo layout agreed and created; branch/PR conventions documented; `.env.example` in every repo. **The `advertising/` workspace is currently not a git repository at all** `[DERIVED]` | all |
| **F-002** | Gateway + two service skeletons | One Spring Boot and one FastAPI service, each with a health endpoint, reachable through the gateway with routing, TLS termination, CORS and rate limiting configured. **This is the R-ARCH-01 spike made permanent** | gateway, two services |
| **F-003** | Shared auth substrate | JWT issuance in `identity-service`; independent validation working in **both** runtimes; role model; a documented pattern each service follows. No user-facing auth yet | identity + both runtimes |
| **F-004** | Data layer scaffolding | Postgres per service; migration tooling configured in both runtimes (Flyway/Liquibase + Alembic); repository/session pattern; **no entity migrations** | all services |
| **F-005** | Object storage + image pipeline scaffolding | `media-service` boots; upload to object storage works; derivative generation pipeline exists with no ad coupling | media-service |
| **F-006** | Consumer design-system primitives | Full consumer token set as one source of truth (not the current lossy partial translation, doc 02 §2); Button, Input, Card, Chip, price formatter, skeleton loader — shared across `frontend-web` and `mobile`; icon set standardised | frontend-web, mobile |
| **F-007** | Operator design-system primitives | Operational token set as a **separate** file; DataTable (sticky header, 48px rows, hover striping, inline row actions), MetricCard, StatusChip, BulkActionToolbar, collapsible sidebar, `Cmd+K` search | management-portal |
| **F-008** | Build and CI | Lint (**a real linter, not `tsc --noEmit` aliased as `lint`** `[DERIVED]`), typecheck, test, build green per repo; dependency-vulnerability gate wired at a chosen CVSS threshold | all |
| **F-009** | Observability substrate | Structured JSON logging in both runtimes with one schema; correlation id propagated gateway → service → service and returned on error; client error reporting with release tagging; PII exclusion enforced | all |
| **F-010** | Local stack orchestration | **One command boots five services, three clients, Postgres and object storage.** Non-negotiable — the alternative is every developer hand-starting eight processes daily | all |
| **F-011** | Test harness + seed dataset | Every tier in doc 06 §3 runnable in every repo; the deterministic seed dataset of doc 04 §9 loads | all |
| **F-012** | Reference data | Provinces, districts, cities; the nine top-level categories with subcategories; Vehicles attribute definitions seeded | listing-service |
| **F-013** | Developer onramp | README per repo; "how to add a feature" walkthrough; the seam-contract workflow documented | all |

**F-002 gates everything.** If it overruns its time box, doc 03 §2's two-deployable fallback triggers
before feature work starts, not after.

## Feature slices

Ordered by the locked build order. `DoD` lists the acceptance criteria the slice must satisfy plus its
own specifics; every slice additionally carries the doc 06 §5 checklist.

### M1 — Accounts

| ID | Slice | Definition of done |
|---|---|---|
| **1** | Email/password registration + verification | Register, receive verification email, verify, sign in. AC-1. Publishing gated on a verified email (FR-3) |
| **2** | Google OAuth sign-in | Google sign-in issues tokens. AC-2 |
| **3** | Account linking | Google sign-in against an existing email-registered address links to the same account rather than creating a second. FR-2. **Own slice, not folded into #2** — this is the branch that quietly ships broken and is expensive to unwind |
| **4** | Password reset | Request, emailed token, confirm, sign in with the new password. FR-5 |
| **5** | Profile and session across all three clients | `/me` read and update; sign-out; token refresh; secure token storage on mobile. FR-28 |
| **6** | Operator roles and portal sign-in | Moderator and Super Admin sign in to the portal; role enforcement at the service, not just the gateway |

### M2 — Ad creation and moderation

| ID | Slice | Definition of done |
|---|---|---|
| **7** | Ad status machine + persistence | Every transition in doc 01 §5 implemented and tested valid-and-invalid; `LL-NNNNN` reference minted and unique; soft delete. No UI |
| **8** | Category attribute schema mechanism | Attribute definitions drive create, detail and filters from one source; Vehicles plus two structurally different categories seeded and working. **Blocks #9 — resolves D-3** |
| **9** | Post-ad wizard, steps 1–2 | Category and subcategory selection; common fields with the observed constraints (title ≤70 with counter, description ≤4000 with counter, condition); category-specific attributes; draft save. Web + mobile. **Requires the FR-6 stepper-variant conflict resolved first** |
| **10** | Photo upload | Multi-image upload, ordering, main-photo designation, derivatives; native camera and photo-library permissions on mobile. FR-11 |
| **11** | Location capture | Province → District → City cascading selection. FR-12 |
| **12** | Wizard final step + submit | Pricing with `Negotiable`; full preview; T&C + Privacy acceptance; moderation notice; submit → `pending`. AC-3 |
| **13** | Non-`active` invisibility | Every public read path returns only `active` ads — browse, search, featured rail, detail by reference; 404 not 403 for hidden ads; verified on all three clients. **AC-4. The single most important slice in the product** |
| **14** | Moderation queue | Oldest-first queue with age, seller, category, flags. FR-32 |
| **15** | Review, approve, reject | Open an ad, edit fields, approve or reject with a reason code and note; `ModerationDecision` recorded. AC-5, AC-7 |
| **16** | Seller-visible rejection + revise | Rejected state and reason shown to the owner; revise and resubmit → `pending`. AC-7, R-3. **Needs design — no screen exists** (doc 02 §3) |
| **17** | My Ads | Status-tabbed list with row actions Edit / Mark as Sold / Delete; overview counters. FR-29, FR-30, AC-10 |
| **18** | Re-moderation on edit | Editing a moderated field on an `active` ad returns it to `pending`; non-moderated fields do not. R-4 |
| **19** | Bulk moderation actions | Bottom toolbar bulk approve/reject on a selection. FR-36 |

### M3 — Public discovery

| ID | Slice | Definition of done |
|---|---|---|
| **20** | Home | Category grid with real counts; featured rail. FR-16. Removes `frontend-web/src/lib/listings.ts` |
| **21** | `GET /ads` search core | Free-text, category, location, price, condition, sort, cursor pagination, `meta.total`. Doc 05 §9 |
| **22** | Filter rail | All filters including the category-specific block and `Verified Sellers Only`; active-filter chips; Clear All; keyboard operable. FR-18 |
| **23** | Results presentation | Grid/list toggle, result count, ad card per the design system, skeleton loaders. FR-19–FR-21 |
| **24** | Ad detail | Gallery, spec table from attribute definitions, description, price, location, posted-at, `LL-` reference, seller contact with verification marker. AC-6 |
| **25** | Favourites | Save/unsave from card and detail; Saved Ads list; counter. FR-25, FR-28 |
| **26** | Ad metrics | View and inquiry counters, with a documented definition of a view and abuse protection. FR-31 |
| **27** | Report an ad | Report intake feeding the operator flagged queue; resolution workflow. FR-35 — **closes the loop on an operator surface that currently has no input** |

### M4 — Featured payment

| ID | Slice | Definition of done |
|---|---|---|
| **28** | Promotion plan catalogue + admin | Plans with price and duration, administered in the portal. FR-41, FR-45 |
| **29** | Featuring purchase initiation | Purchase against an `active`, owned ad only; 409 otherwise. AC-9, R-7 |
| **30** | Gateway integration + settlement | Payment captured; **idempotent** webhook keyed on gateway reference; featured window started on settlement only. AC-8. **Requires the gateway decision (D-6)** |
| **31** | Featured ranking + expiry | Promoted treatment in results and detail; server-side featured-first ordering; expiry returns the ad to ordinary ranking without changing `active`. AC-8, FR-22, FR-47 |
| **32** | Purchase history + reconciliation | Seller sees what they paid for and when it expires; operator can reconcile. FR-48 |

### M5 — Hardening

| ID | Slice | Definition of done |
|---|---|---|
| **33** | Admin dashboard | KPI cards with trends, by-category and by-province distributions, reconciled against underlying data. AC-12, FR-37 |
| **34** | Advertisements register | Operator table with filters, flagged count, CSV export, operator ad creation. FR-38 |
| **35** | User administration | List, inspect, suspend, role assignment. FR-39 |
| **36** | Taxonomy administration | Categories and attribute-schema management. FR-40 |
| **37** | Accessibility pass | WCAG 2.1 AA verified across every surface; automated scan in CI. AC-13, NFR-3 |
| **38** | Security pass | AC-14 across every endpoint; authz matrix tested per role; secrets audit; rate limiting verified |
| **39** | Performance pass | `GET /ads` and the dashboard measured at NFR-9 volumes; index plan validated; image delivery via CDN |
| **40** | Ad expiry job | Scheduled expiry, seller notification, relist path. R-5 — **needs the duration decision** |
| **41** | Reports and settings | FR-42, FR-43 — **both need contents defined first** |
| **42** | Empty, loading and error states | Every surface, all three clients. Doc 02 §3 |

## Slices blocked on a decision

These cannot be estimated, let alone built, until the decision lands. Each has a row in
`.forge/project-prd-signals.md`.

| Blocked slice | Blocked on |
|---|---|
| Messaging / inquiry threads (would be its own milestone) | FR-27 in/out decision. **Note #26 counts inquiries — if messaging is deferred, the inquiry counter needs a definition or removal** |
| OCR/AI ad intake and extraction review | FR-34 in/out decision |
| #30 gateway integration | Payment gateway choice |
| #40 ad expiry | Live-duration decision |
| #41 reports and settings | Contents undefined |
| #8 beyond three categories | Attribute schemas for the remaining six categories |
| Verified-seller granting | What earns FR-4's badge |
| Anything sized against a delivery date | Team size and delivery window — absent from every input |

## Sizing note for Gate 3

Three things will make a naive sizing pass wrong, and all three are visible now:

1. **Design debt is work.** Roughly as many screens are missing as exist, including the entire payment
   flow (doc 02 §3). Slices #16, #28–#32, #41 and #42 carry design cost, not just build cost.
2. **Three clients per user-facing slice.** Every M1–M4 slice ships web, mobile and (where operator-facing)
   portal. AC-11 is an acceptance criterion, not a stretch goal.
3. **Foundation is thirteen slices.** M0 is not a week. It is the largest single block in the plan and
   the R-ARCH-01 consequence.
