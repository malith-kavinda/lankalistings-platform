# LankaListings — PRD History

> Sidecar to [`project-prd.md`](project-prd.md). Carries **audit trail only** — questions that have been answered (with the answer folded into the PRD body) and PRD revisions.

## What lives here

- **Resolved open questions** — every OQ that was once in [`project-prd-signals.md`](project-prd-signals.md) and has since been answered. The answer itself has already been folded into [`project-prd.md`](project-prd.md) (or into an AD in `.claude/CLAUDE.md` for architectural decisions). The entry here is the historical record with a pointer to where the answer now lives.
- **PRD revisions** — every meaningful change to [`project-prd.md`](project-prd.md) after first sign-off. The PRD body itself no longer carries a `## Revisions` section; entries are appended here instead.

## What does NOT live here

- **Open / partial OQs** — those live in [`project-prd-signals.md`](project-prd-signals.md).
- **The live contract** — lives in [`project-prd.md`](project-prd.md).

## How to add an entry

The OQ resolution procedure and the revision convention are defined in [`.claude/rules/prd.md`](../.claude/rules/prd.md). Three-step lift on resolution: fold the answer into the PRD body, move the OQ row from `project-prd-signals.md` to `## Resolved Open Questions` below, append a `### Rev N` entry under `## Revisions`.

Append-only. No curation in v1 — if this file becomes hard to navigate later, that's a signal to revisit the lifecycle, not to silently prune.

## Resolved Open Questions

> Each entry preserves the original question and records where the answer was folded. `Resolved in Rev N: see §X` or `see AD #Y` is the canonical pointer format.

| # | Section | Topic | Question | Resolution | Resolved in | Date |
|---|---------|-------|----------|------------|-------------|------|
| OQ-02 | §Deferred (Post-V1) | AI/OCR intake scope | **Is AI/OCR-assisted ad intake in MVP scope?** `review_ad_admin_desktop` is a fully designed surface for it — source image, raw OCR text, per-field confidence and warnings — yet no locked decision mentions it. It is also the strongest technical justification for FastAPI being in the stack. Recommendation: defer, but keep the review UI's field-level provenance model so extraction can later be switched on by adding data rather than redesigning review | **In scope, and split in two.** Operator-side newspaper OCR intake is already built and shipped in `media-service`. Seller-side AI-guided ad creation is now S-3's delivery shape. The review UI keeps its field-level provenance model, which the guided flow reuses for AI-assisted markers | Rev 1: see §In Scope (V1) S-3 and §Functional Surface > Ad creation | 2026-09-19 |
| OQ-03 | §Functional Surface > Ad creation | Wizard steps | Which post-ad stepper is correct? `post_your_ad_ad_details_desktop` shows `… Photos → Preview → Publish`; `post_your_ad_final_step_desktop` shows `… Photos → Price & Contact → Publish` — and both carry a pricing block. One is stale; the wizard cannot be built against two contradictory designs | **Neither — a six-stage stepper supersedes both.** Both variants carried pricing because price is a required *core* field, so it belongs in stage 2 with the other essentials; contact, preview and submit merge into one final stage. Two genuinely new surfaces (Smart follow-ups, Generate and refine) are added | Rev 1: see §Functional Surface > Ad creation | 2026-09-19 |
| OQ-04 | §Domain Model | Category attributes | What are the attribute schemas for the **eight non-Vehicle categories**? Only Vehicles is specified (Make, Model, Year, Mileage, Transmission, Fuel Type, Engine Capacity, Registration). The largest content gap in the pack — and the schemas drive ad creation, ad detail, and search filters simultaneously | **All nine authored in full**, with reference datasets for vehicle makes/models, property types, land extent units and job families. Every dynamic data source carries an `Other` manual fallback | Rev 1: see §Domain Model | 2026-09-19 |
| OQ-12 | §Functional Surface > Ad creation | Photo limits | Photo count minimum/maximum, per-file size cap, accepted formats? The gallery shows 12 images; no maximum is stated | **Minimum 1, maximum 12, 5 MB per file; JPEG, PNG, WebP, HEIC.** Twelve matches the gallery design; the mobile "up to 10" copy is stale and corrected. HEIC accepted because iPhone is a common in-market capture device. *Set to unblock delivery — cheap to change, worth a product-owner confirmation* | Rev 1: see §Functional Surface > Ad creation | 2026-09-19 |
| OQ-21 | §Constraints > Tech Stack | Service split | Confirm or reject the proposed five-service split (identity / listing / payment on Spring Boot; admin / media on FastAPI) and its capability-based language boundary. The F-002 spike informs this; rejecting it triggers the documented two-deployable fallback | **Confirmed, plus `gateway-service`** as edge infrastructure rather than a sixth business service. The gateway owns CORS and authentication with coarse route-level role gating; every service still enforces resource-level authorisation independently | Rev 1: see §Constraints > Tech Stack | 2026-09-19 |
| OQ-23 | §Constraints > Tech Stack | Database | Database engine per service. PostgreSQL proposed — relational filtering, exact integer money, built-in full-text search | **PostgreSQL 17, database-per-service.** Already proven in `media-service`, which runs it in local, test and production | Rev 1: see §Constraints > Tech Stack | 2026-09-19 |
| OQ-25 | §Constraints > Tech Stack | Async transport | What carries the asynchronous paths — settlement, notifications, image derivatives? Queue, event bus, or scheduled polling | **The database-backed lease queue already proven in `media-service`** — claim token, lease, heartbeat, reaper — rather than introducing a broker. Carries content generation and attribute extraction now; default for the other three unless measured load justifies a broker | Rev 1: see §Constraints > Tech Stack | 2026-09-19 |
| OQ-30 | §Domain Model | Attribute modelling | Dynamic attribute definitions or per-category typed models? Dynamic is proposed because the same definitions must drive four surfaces at once; its cost is weaker type safety and harder multi-attribute filtering. **Spike against three structurally different categories before Gate 3** | **Both, with one source.** A versioned schema *document* is authoritative for asking and validating (a flat table cannot express visibility conditions, AI sensitivity or follow-up eligibility); each accepted answer projects into a typed `AdvertisementAttribute` row so multi-attribute filtering stays indexable | Rev 1: see §Domain Model | 2026-09-19 |

## Revisions

> One `### Rev N — YYYY-MM-DD` heading per revision, newest at the bottom. Body is free-form prose: what changed, why, and (if applicable) which OQ this resolved.

<!-- Example shape:

### Rev 1 — YYYY-MM-DD
- **Changed:** Tightened §Per-Role Capability Matrix to enumerate each role's allowed actions explicitly.
- **Why:** OQ-7 surfaced ambiguity between Counsellor and Supervisor write permissions.
- **Resolves:** OQ-7 (moved to `## Resolved Open Questions` above).
- **Approved by:** [name]
-->

### Rev 1 — 2026-09-19

- **Changed:**
  - **§In Scope (V1)** — S-3 restated as a six-stage AI-guided wizard: schema-rendered essential fields, a
    bounded set of decision-model-selected follow-ups, AI-drafted title and description, and AI attribute
    suggestions. Every AI output is a suggestion; none writes ad state without explicit seller acceptance,
    and the flow completes with every AI integration disabled.
  - **§Deferred (Post-V1)** — the AI/OCR intake row is removed (now in scope). Two narrower rows replace
    it: AI-generated **price guidance** (blocked on a comparable-ad corpus a greenfield marketplace does
    not have) and AI-generated **Sinhala/Tamil ad content** (blocked by the locked English-only decision).
  - **§Functional Surface > Ad creation** — rewritten around the six stages, with the stepper
    contradiction resolved and photo limits set. The `**Blocked:**` line is removed.
  - **§Domain Model** — `CategoryAttributeDefinition` superseded by `CategorySchemaVersion`; six entities
    added (`AdvertisementAttribute`, `AdCreationSession`, `QuestionDecision`, `ContentGeneration`,
    `AttributeSuggestion`, `AuditEvent`). Attribute modelling and the nine-category gap both settled.
  - **§Constraints > Tech Stack** — five-service split confirmed and `gateway-service` added; PostgreSQL 17
    database-per-service confirmed; async transport settled; the Java platform (Java 17, Spring Boot
    3.5.16, Gradle, Flyway, Testcontainers) and RS256 key distribution fixed; the two external AI providers
    named for the first time.

- **Why:** the AI-Guided Post Ad specification
  (`docs/product/ai-guided-post-ad-implementation-plan.md`, Phase 0) could not be built against a PRD that
  deferred the capability, carried two contradictory steppers, specified one of nine attribute schemas, and
  left the service split, database, async transport and attribute modelling open.

- **Resolves:** OQ-02, OQ-03, OQ-04, OQ-12, OQ-21, OQ-23, OQ-25, OQ-30 — all moved to
  `## Resolved Open Questions` above. Twenty-nine open questions remain, OQ-01 and OQ-20 still first.

- **Approved by:** Product owner decision, 2026-09-19 — **taken outside the Gate 1 ritual.** Gate 1
  (`/forge-prd-check`) has still not been run, and these rows were therefore *not* promoted into
  `.claude/CLAUDE.md § Architecture Decisions`, whose own rule is "do not promote a row here until its gate
  confirms it". They are recorded here instead so the audit trail stays honest about how they were taken.
