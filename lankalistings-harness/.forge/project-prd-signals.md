# LankaListings — PRD Signals

> Sidecar to [`project-prd.md`](project-prd.md). Carries **live signals only** — open and partial open questions that the engagement still needs to settle.

## What lives here

- **Open questions** raised during PRD authoring, the three engagement gates (`/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose`), or mid-engagement when a new ambiguity surfaces.
- **Only `⏳ open` and `◐ partial` rows.** Once an OQ is answered (`✅`), it moves to [`project-prd-history.md`](project-prd-history.md) `## Resolved Open Questions`, with the answer folded into the PRD body itself. See [`.claude/rules/prd.md`](../.claude/rules/prd.md) for the resolution procedure.

## What does NOT live here

- **The live contract** — problem, domain, scope, NFRs, success criteria — lives in [`project-prd.md`](project-prd.md).
- **Risks** — risks live in `project-prd.md` `## Risks`. They are part of the engagement contract; OQs are not.
- **Resolved questions and PRD revisions** — both live in [`project-prd-history.md`](project-prd-history.md).

## Why the split exists

Mixing live signals and audit trail into the PRD body bloats every read of the contract. Selective loading on the consumer side (e.g. `spec-reviewer` filtering signals by feature ID via the `Blocks` column) is only possible when signals are in their own file. See `.claude/rules/prd.md` for the full rationale and the shape-guard hook contract.

## Status Legend

- ⏳ **open** — no answer yet
- ◐ **partial** — answer in progress; some aspects settled, others outstanding

(Answered ✅ rows live in [`project-prd-history.md`](project-prd-history.md) — not here.)

## Open Questions

> The `Section` column anchors each OQ to a PRD body section (e.g. `§Domain Model`, `§Functional Surface > [Feature X]`) so the answer's eventual home is obvious.
>
> The `Blocks` column lists feature IDs the OQ blocks — comma-separated, or `—` if none. The `spec-reviewer` sub-agent filters this table by feature ID during `/forge-spec-review`, so only OQs relevant to the spec under review are loaded into its context.

> **Context for this table.** OQ-01…OQ-34 came out of reconstructing the discovery pack on
> 2026-08-24 (see `project-prd.md` → provenance warning). The count is a genuine finding about the inputs,
> not a reconstruction artefact — the original pack locked seven product decisions and left everything
> else unstated. **OQ-35…OQ-37 were surfaced by Gate 1 Run 1** (2026-08-24, outcome `fail` — see
> [`engagement-gate-runs.md`](engagement-gate-runs.md)). `Blocks` references the slice IDs in
> [`.forge/discovery/docs/07-harness-backlog.md`](discovery/docs/07-harness-backlog.md); slice numbering is
> provisional until `/forge-decompose` regenerates `features.md` at Gate 3.
>
> **Answer OQ-01 and OQ-20 first.** Each changes the *shape* of the plan, not a detail within it: a large
> capability the UI already assumes but no decision covers, and the complete absence of any team size or
> delivery window. **OQ-02 was the third of that set and is now resolved** — AI-assisted ad intake is in
> scope — along with OQ-03, OQ-04, OQ-12, OQ-21, OQ-23, OQ-25 and OQ-30. See
> [`project-prd-history.md`](project-prd-history.md) Rev 1.

### Product decisions — Gate 1 (`/forge-prd-check`)

| # | Section | Topic | Question | Status | Resolution / Owner | Blocks |
|---|---------|-------|----------|--------|--------------------|--------|
| OQ-01 | §Deferred (Post-V1) | Messaging scope | **Is in-app messaging in MVP scope?** The account surface renders `Messages / 5` and per-ad `12 Inquiries`, and the consumer design system specifies a Chat primary action — but no locked decision mentions messaging. It is a large feature (threads, notifications, read state, abuse handling, message-content moderation). Recommendation: defer, ship phone contact only. If deferred, the Messages nav item and inquiry counters must be **removed**, not left as dead affordances | ⏳ open | Product | An entire potential milestone; #26 |
| OQ-20 | §Constraints | Team + timeline | **What is the team size and the delivery window?** Absent from every input. Gate 2's Resource & Timeline Reality section cannot be completed without it, and nothing sized at Gate 3 is trustworthy until it lands | ⏳ open | Product | **All sizing and every date** |
| OQ-05 | §Integration Points | Payment gateway | **Which payment gateway?** Nothing in the inputs names one. PayHere is the leading LKR candidate. The product's only revenue flow depends entirely on this answer | ⏳ open | Product / Lead | #30 |
| OQ-06 | §Functional Surface > Featured payment | Plan catalogue | What are the promotion plans — names, prices (LKR), durations? The admin surface to manage them exists in the sidebar; the plans themselves do not | ⏳ open | Product | #28, #29, #30, #31, #32 |
| OQ-07 | §Domain Model > Lifecycle States | Ad expiry | How long does an ad stay live before expiring? An `Expired` seller tab exists so expiry is intended, but no duration is stated anywhere | ⏳ open | Product | #40 |
| OQ-08 | §Users and Access | Verified Seller | What earns the "Verified Seller" badge? It appears on the account surface, on ad cards, and as a `Verified Sellers Only` search facet — the facet is meaningless without criteria. Phone verification is the obvious candidate, since the detail page renders `077 123 4567 (Verified)` | ⏳ open | Product | Verified-seller granting; #22 |
| OQ-09 | §NFR > Performance | Moderation SLA | Is "typically live within 24 hours" a target or an SLA? It is already literal UI copy shown to sellers, so it is a commitment either way — the question is what it obliges operationally | ⏳ open | Product | Operator staffing; #14; NFR-6 monitoring |
| OQ-10 | §Functional Surface > Public discovery | Contact visibility | Is the seller's phone number visible to unauthenticated visitors, or gated behind sign-in? Scraping exposure versus conversion friction | ⏳ open | Product | #24 |
| OQ-11 | §Functional Surface > Featured payment | Featured ranking | What is the featured-vs-organic interleave — all featured first, or a capped allocation per page? Affects both revenue and result quality | ⏳ open | Product | #31 |
| OQ-13 | §Functional Surface > Moderation | Rejection reasons | What are the rejection reason codes? Required to make R-3 and SC-7 implementable | ⏳ open | Product | #15, #16 |
| OQ-14 | §Domain Model > Lifecycle States | Re-moderation | Which fields are "moderated" and therefore trigger a return to `pending` when edited on an `active` ad? | ⏳ open | Product / Lead | #18 |
| OQ-15 | §Functional Surface > Report an ad | Report intake | What are the report reasons, and may visitors report anonymously? The operator flagged queue exists with nothing feeding it | ⏳ open | Product | #27 |
| OQ-16 | §Glossary | Automated flags | What are the automated flags and the rule behind each? `Price anomaly`, `Duplicate images`, `Warranty claim` are free-text strings in the committed mock — they need to become a typed, machine-generated set with a rule each, or be dropped from the queue UI | ⏳ open | Product / Lead | #14 |
| OQ-17 | §Functional Surface > Operator administration | Reports + Settings | What is in the Reports and Settings sections? Two sidebar destinations with no defined contents | ⏳ open | Product | #41 |
| OQ-18 | §Users and Access | Operator roles | Are Moderator and Super Admin the only operator roles, or are finer roles (content, finance) needed? | ⏳ open | Product | #6, #35 |
| OQ-19 | §Functional Surface > Public discovery | View counting | What counts as a "view" — unique or raw, and how is bot traffic filtered? | ⏳ open | Product / Lead | #26 |
| OQ-34 | §Glossary | Condition values | Is `Reconditioned` a create-form option or search-only? The create form offers two conditions (`Brand New`, `Used`); search offers three | ⏳ open | Product | #9, #22 |
| OQ-35 | §NFR > Performance | Performance targets | **What are the latency and throughput targets?** No endpoint target exists in any input — OQ-09 covers only the moderation promise. `GET /ads` is named as the busiest endpoint in the product and the funnel for all three discovery surfaces, so it needs a p95 at the planning volumes (24,150 active ads), as do search, ad detail, and the operator dashboard's by-province aggregation. Without a number, the performance pass has no pass criterion | ⏳ open | Product / Lead | #21, #33, #39 |
| OQ-36 | §Domain Model > Lifecycle States | Account lifecycle | **What are the Account states, and what does suspension do?** §NFR > Observability makes "user suspension" an auditable operator action and slice #35 offers Suspend, but no Account state machine is modelled anywhere. Specifically: does suspending an account hide its `active` ads from public discovery, block sign-in only, or both — and is the state operator-reversible? | ⏳ open | Product | #6, #35 |
| OQ-37 | §Functional Surface > Report an ad | Report resolution states | **What are the AdReport resolution states, and what closes one?** S-8 specifies "a resolution workflow" with no states named; OQ-15 covers report reasons and anonymity only. Needs the state set (e.g. open → actioned / dismissed), whether resolving a report can itself transition the reported ad, and whether the reporter is told the outcome | ⏳ open | Product | #27 |

### Architecture decisions — Gate 2 (`/forge-arch-probe`)

| # | Section | Topic | Question | Status | Resolution / Owner | Blocks |
|---|---------|-------|----------|--------|--------------------|--------|
| OQ-22 | §Constraints > Tech Stack | Admin data access | Accept or reject `admin-service` reading the listing store **directly, read-only**, for operator table projections and KPI aggregation? If rejected, `listing-service` grows operator-facing query endpoints instead | ⏳ open | Lead / Gate 2 | #33, #34, #35, #36 |
| OQ-24 | §Integration Points | Object storage + CDN | Which object storage provider and which CDN? A listings marketplace is image-bandwidth-dominated | ⏳ open | Lead / Gate 2 | F-005, #39 |
| OQ-26 | §Constraints > Tech Stack | Notifications | Is notification dispatch a sixth service or a shared library? A library plus one queue is proposed at MVP | ⏳ open | Lead / Gate 2 | M1 onward |
| OQ-27 | §NFR > Observability | Observability stack | Which logging, metrics, tracing and error-reporting stack? Observability per change is required by the definition of done but nothing is named | ⏳ open | Lead / Gate 2 | F-009 |
| OQ-28 | §Constraints > Deployment | Deployment | Deployment target, container orchestration, and CI/CD platform. Sri Lanka-proximate region proposed for latency | ⏳ open | Lead / Gate 2 | F-008, F-010 |
| OQ-29 | §Integration Points | Email provider | Which transactional email provider? Needed for verification, password reset, rejection notices, and receipts | ⏳ open | Lead / Gate 2 | M1, #16 |
| OQ-31 | §Constraints > Deployment | Mobile release | Mobile release pipeline, versioning, and OTA-vs-store-update policy. Two app stores and review latency are a delivery path the web surfaces do not have | ⏳ open | Lead / Gate 2 | Every milestone's mobile parity |
| OQ-32 | §NFR > Security and Compliance | Data protection | What is the PDPA posture — retention periods, data export, and deletion cascades for account deletion, media past ad deletion, and PII in logs? Cheaper to decide now than to retrofit | ⏳ open | Lead / Product | Data-model §8; #38 |
| OQ-33 | §NFR > Security and Compliance | CVE threshold | What CVSS threshold fails the dependency-vulnerability build gate? It needs a number to be enforceable | ⏳ open | Lead / Gate 2 | F-008 |
