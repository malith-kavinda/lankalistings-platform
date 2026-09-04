# Engagement Gate Runs

> Append-only audit log for the three pre-implementation gates: PRD readiness, architecture probe, decomposition.
>
> **Format:** chronological — append new entries at the bottom (newest at bottom). One `## Gate N Run M` block per run. Updated automatically by `/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose` in full mode (skipped in `dry-run` mode).
>
> **Why this file exists:** the engagement-level artifacts (PRD, architecture, backlog) don't have a natural lifecycle-metadata section like specs do (`## Revisions`). This file is their shared audit trail. Per-feature gates (spec review, plan review, adversarial review, security review) record their findings inside the per-feature spec / plan artifacts and do **not** appear here. Tool-call-level gates (hooks) are ephemeral and do **not** appear here.
>
> **Audit storage principle:** see `.claude/rules/tracker.md` "Gate Audit Protocol" section.

---

## Gate 1 Run 1 — 2026-08-24 (malith3)

**Mode:** full
**Outcome:** fail
**Trigger:** end-of-discovery Gate 1 run — first gate run of the engagement, against the PRD authored from the reconstructed discovery pack

| Section | Item | Status | Reasoning |
|---|---|---|---|
| Scope and boundaries | In-scope features explicitly listed | ✅ | §Scope and Boundaries > In Scope (V1) enumerates S-1…S-9 in locked build order, each with a priority and a definition-of-done cell. |
| Scope and boundaries | Out-of-scope features explicitly listed (incl. negative-space exclusions, with won't-build reason) | ❌ | Negative-space exclusions are present (ratings/reviews, saved searches with alerts, seller storefronts, price-history analytics) but collapsed into **one** bullet whose stated reason is provenance — "none appear in any input" — not a won't-build reason; two further bullets (no seller charge other than featuring; auto-publication without moderation) carry no reason at all. |
| Scope and boundaries | Deferred items separated from out-of-scope, each tagged with target phase or trigger | ❌ | §Deferred (Post-V1) has a populated "Trigger to revisit" column, but the two lists are not cleanly separated — **Sinhala and Tamil UI appears in both** §Out of Scope (`[LOCKED]`) and §Deferred — and the two largest deferred rows (in-app messaging, AI/OCR intake) are self-labelled "Recommendation, not a decision", so their deferral is contingent on OQ-01/OQ-02 rather than decided. |
| Scope and boundaries | Phasing / sequencing intent — ordered priorities with dependencies | ✅ | §Phasing / Sequencing Intent states the ordered chain S-1 → S-2 → S-3+S-4 → S-5 → S-6 → S-7/S-8/S-9 with a precondition rationale per link, and the In Scope table carries P0/P1 per row. |
| Scope and boundaries | Reference-system classification (Replicate / Redesign / Defer / Discard) | ➖ | No reference system — §Business Specifics states this is a greenfield build with no legacy system to migrate from or replicate. |
| Domain model | Key entities named | ✅ | §Domain Model > Key Entities defines 12 entities (Account, Advertisement, Category, CategoryAttributeDefinition, geography, ModerationDecision, PromotionPlan, FeaturingPurchase, PaymentTransaction, MediaAsset, AdReport, Favourite). |
| Domain model | Entity relationships described (1:1, 1:N, N:N) | ❌ | The Key Relationships column is prose with no cardinality notation — "has Credential and/or OAuthIdentity", "referenced by FeaturingPurchase" leave 1:1 vs 1:N unstated; the referenced `04-data-model.md` contains no cardinality notation either, so the pointer does not close the gap. |
| Domain model | Entity lifecycle states named where applicable | ❌ | Advertisement and FeaturingPurchase are fully specified, but two entities with demonstrable lifecycles are not: **Account** (§Observability makes "user suspension" an auditable action, yet no account states are named) and **AdReport** (S-8 specifies "a resolution workflow" with no states). |
| Domain model | Glossary for client-specific terminology | ✅ | §Glossary defines 12 project-specific terms, including the load-bearing Flag-vs-Report distinction and the `LL-NNNNN` reference format. |
| Users and access | User roles enumerated | ✅ | §Users and Access > Roles enumerates Visitor, Member, Moderator, Super Admin. |
| Users and access | Per-role capabilities — explicit per-role × per-resource Create/Read/Update/Delete/Approve/Configure breakdown | ❌ | Only a narrative "Primary Capabilities" column, which the checklist explicitly rejects; no role × resource matrix exists for Advertisement, Account, Category/AttributeDefinition, PromotionPlan, AdReport, so SC-14 ("every endpoint rejects unauthenticated and cross-owner access") has no enumerated matrix to test against. |
| Users and access | Multi-tenancy / org-hierarchy model described where applicable | ✅ | §Multi-Tenancy / Org Hierarchy states none is required — single marketplace, single operator organisation, no tenant isolation model. |
| Functional surface | Each in-scope feature has at least a one-paragraph description | ❌ | §Functional Surface covers S-1…S-8 but has **no subsection for S-9 Hardening**, whose In Scope cell carries five distinct deliverables (per-surface WCAG verification with a CI scan, per-role authorisation-matrix testing, performance measurement at planning volumes, empty/loading/error states everywhere, the ad expiry job). |
| Functional surface | User journeys identified for headline flows — end-to-end path per top-3 / all P0 features | ❌ | Two flows are documented (seller post-to-live, featuring payment) against six P0 rows; there is no end-to-end path for **S-5 public discovery** (the buyer journey home → filter → detail → contact/favourite, the product's most-trafficked surface) or for **S-2 accounts**, whose auth flow R-2 also records as entirely undesigned. |
| Functional surface | Integration points with external systems named | ✅ | §Integration Points names six systems with direction and purpose, each undecided one carrying its OQ (gateway OQ-05, email OQ-29, storage/CDN OQ-24, OCR conditional on OQ-02). |
| Non-functional | Performance expectations (at least order-of-magnitude) | ❌ | The PRD states outright that no targets exist in any input; it supplies planning **volumes** from mock data (24,150 active ads, 482 pending, 156 new users/day) but **no latency or throughput target for any endpoint** — including `GET /ads`, which it names as the busiest in the product and the funnel for all three clients. |
| Non-functional | Security / compliance requirements named | ✅ | §Security and Compliance specifies per-service JWT validation (gateway validation explicitly insufficient), the three in-service authorisation questions, exact-integer LKR minor units, webhook idempotency on gateway reference, 404-not-403 leakage control, the supply-chain CI gate, and PDPA applicability. |
| Non-functional | Accessibility commitments named | ✅ | §Accessibility commits to WCAG 2.1 AA (`[PROPOSED]`), made testable by SC-13 and an automated scan on every page visited in E2E, with four named at-risk areas in the current designs. |
| Non-functional | Observability / audit requirements named | ✅ | §Observability and Audit names structured JSON logs on one schema across both runtimes, correlation-id propagation, per-client error reporting, an explicit domain-event list, queue-depth/oldest-pending metrics tied to the 24-hour promise, and append-only attribution for every operator action. |
| Constraints | Tech stack constraints (mandatory vs preferred vs open) | ✅ | §Tech Stack splits cleanly three ways — Mandatory `[LOCKED]` (three client stacks; polyglot microservices with FastAPI serving portal CRUD), Proposed for Gate 2 (five-service split, per-service PostgreSQL, `/api/v1`), and Open (OQ-21…OQ-31). |
| Constraints | Regulatory constraints | ✅ | §Regulatory names Sri Lanka's PDPA as applicable and Terms of Service + Privacy Policy as a delivery dependency (the publish wizard already gates on both); the undecided posture is tracked as OQ-32. |
| Constraints | Deployment / hosting constraints | ✅ | §Deployment and Hosting defers the target to Gate 2 (OQ-28) but records the constraints that do bind — three environments, one-command whole-stack local boot as non-negotiable at five services plus three clients, staging with gateway sandbox and deterministic seed data, Sri Lanka-proximate production region for latency. |
| Honesty | Open questions / TBDs explicitly listed | ✅ | 34 OQs live in `project-prd-signals.md` per the trichotomy rule, each anchored to a PRD section with an owner and a `Blocks` column, and the three shape-changing ones (OQ-01, OQ-02, OQ-20) are called out for answering first. |
| Honesty | Known risks / unknowns logged | ✅ | §Risks logs R-1…R-10 with owner, status and a mitigation on each material one, including the reconstruction risk on the PRD's own provenance (R-10). |
| Honesty | Success criteria stated | ✅ | §Success Criteria gives SC-1…SC-15 as demonstrable end-to-end criteria across all three surfaces, plus five business outcomes; SC-9, SC-11 and SC-15 encode the moderation, parity and idempotency invariants as tests. |
| Honesty | Input sources / provenance recorded | ❌ | §Input Sources tables seven sources with dates, but the **product-owner scoping conversation has no artefact** — `.forge/discovery/meeting-notes/` contains only `.gitkeep`, so the sole source for the two largest locked decisions (polyglot microservices with Spring Boot + FastAPI; mobile as an MVP surface) is an unrecorded conversation. |

**Advisory:**

- **Risk-ID drift, `CLAUDE.md` vs PRD:** `.claude/CLAUDE.md:83` (AD #10) cites risk `R-ARCH-01`, which exists only in `.forge/discovery/docs/03-architecture.md` and `07-harness-backlog.md`. The PRD renumbered that risk to `R-1` in §Risks.
- **Acceptance-criterion ID drift, `CLAUDE.md` vs PRD:** `.claude/CLAUDE.md:82` (AD #9) cites `AC-11` for mobile parity. The PRD calls it `SC-11`, and `.forge/features.md` already uses `SC-11`. `AC-11` survives only in the discovery pack.
- **`R-n` namespace collision inside the PRD:** §Functional Surface cites `R-1…R-7` as the *rules/invariants* in `01-product-requirements.md`, while §Risks defines `R-1…R-10` as *risks*. Signals row OQ-13 cites "R-3" meaning the rule; PRD `R-3` is the unscoped-capabilities risk.
- **Dangling PRD section pointer:** `.forge/features.md:18` refers to "The PRD's §Feature Decomposition"; `project-prd.md` has no such heading — the equivalent is §Scope and Boundaries > In Scope (V1).

**Follow-up:** three new open questions were surfaced by this run and appended to `project-prd-signals.md` — OQ-35 (performance targets), OQ-36 (Account lifecycle / suspension semantics), OQ-37 (AdReport resolution states). The remaining six failures are authoring gaps, not decisions, and are closed by re-running `forge-prd-author` in fill mode.
