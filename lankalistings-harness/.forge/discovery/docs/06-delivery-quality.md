# 06 — Delivery and Quality Plan

> Reconstructed 2026-08-24. Provenance tags per `README.md`.
> Downstream: the tier model here specialises `.forge/test-strategy.md`; the milestones feed Gate 3.

## 1. Build order

The original pack index locks the sequence: `[LOCKED]`

> platform foundation → accounts → ad creation/moderation → public discovery → featured-payment flow →
> hardening.
>
> "Do not build payment capture before an approved ad can be promoted."

That ordering is not arbitrary — each stage is the precondition of the next. Moderation is meaningless
without accounts to attribute ads to; discovery is meaningless without approved ads to discover;
featuring is meaningless without an approved ad to feature. Payment last is a correctness constraint, not
a prioritisation preference.

## 2. Milestones

| M | Milestone | Exit condition |
|---|---|---|
| **M0** | Platform foundation | Gateway routes to one Spring Boot and one FastAPI service; shared JWT validation works in both runtimes; Postgres + migrations per runtime; object storage wired; both design-system token sets and their primitives exist; lint/typecheck/test/build green in every repo; dependency-vulnerability gate wired; structured logging with correlation ids; **one-command local boot of the whole stack**; seed dataset loads |
| **M1** | Accounts | AC-1, AC-2. Email/password + Google, verification, reset, account linking, roles, `/me` |
| **M2** | Ad creation and moderation | AC-3, AC-4, AC-5, AC-7. The wizard, the status machine, the queue, approve/reject with reason. **AC-4 is the milestone's hardest gate** — non-`active` invisibility across every read path on all three clients |
| **M3** | Public discovery | AC-6. Home, search, filter rail, sort, grid/list, detail page, favourites |
| **M4** | Featured payment | AC-8, AC-9. Plan catalogue, purchase, gateway settlement, featured ranking, expiry |
| **M5** | Hardening | AC-11, AC-12, AC-13, AC-14. Cross-surface parity, accessibility, security, performance against NFR-9 volumes, operator dashboards reconciled |

Mobile is **not** a milestone. It is a surface, and every one of M1–M4 ships its mobile equivalent —
AC-11 makes that explicit. Treating mobile as a trailing phase is how a native client ends up six
features behind the web client permanently. `[PROPOSED]`

## 3. Test tiers

Specialises the framework tier model (`.forge/test-strategy.md`). Toolchain is `[PROPOSED]` — nothing in
the inputs names a test framework, and **none of the three skeletons has any test dependency at all**.

| Tier | Spring Boot services | FastAPI services | Web clients | Mobile |
|---|---|---|---|---|
| **T1 unit** | JUnit 5 + Mockito (or Spock) | pytest + `unittest.mock` | Vitest + React Testing Library | Jest + React Native Testing Library |
| **T2 integration** | Spring Boot Test + Testcontainers Postgres | pytest + `httpx.AsyncClient` against a real ephemeral Postgres | Vitest + MSW for API mocking | Jest + MSW |
| **T3 seam** | Contract tests against the frozen per-wave contract, no browser — run cross-runtime | | | |
| **T3 / T-E2E browser** | Playwright against a booted stack, plus an accessibility scan per visited page | | | Maestro or Detox for native flows |

Two rules that matter more here than in a single-runtime project:

1. **The seam tier is the load-bearing tier.** With five services across two runtimes and three clients,
   most defects will be boundary defects: enum casing, error-shape divergence, money as float, timestamp
   format, pagination style. T3 seam tests against the frozen wave contract are what catch those, and
   they must run cross-runtime — a Spring Boot contract test that only exercises Spring Boot proves
   nothing about what FastAPI returns.
2. **Execution decoupling holds.** T1/T2 are authored and run by the implementer; T3 and T-E2E are
   authored by the test specialists and **run by the orchestrator**, which is the only actor that can
   keep a multi-service stack booted.

### Always-test list

Non-negotiable regardless of tier budget:

- **Every status transition in doc 01 §5, valid and invalid.** This is the product's core invariant.
- **Non-`active` invisibility on every public read path** — browse, search, featured rail, detail by
  reference, and each client's cache. One unguarded path breaks the locked publication rule.
- **Ownership scoping** on every seller mutation and on featuring purchase.
- **Role enforcement** on every operator endpoint.
- **Featuring gate** — purchase rejected for non-`active` or non-owned ads (AC-9).
- **Webhook idempotency** — the same settlement delivered twice results in one featured window.
- **Money** — no float anywhere in the path; formatting correct at `Rs. 8,750,000` scale.
- **Field validation** at both client and server: title ≤70, description ≤4000, required fields.
- **Filter and sort correctness**, including featured-first ranking with both a live and an expired
  featured window present.

## 4. Coverage targets

`[PROPOSED]` — the pack's own definition of done demands automated tests per change but names no number.

| Category | Target |
|---|---|
| Service business logic (status machine, authorisation, money, ranking) | ≥85% |
| Service API layer | ≥80% |
| Interactive UI components | ≥70% |
| Presentational components | Covered by visual/E2E rather than unit assertions |
| Every acceptance criterion in doc 01 §8 | 100% mapped to at least one test |

The last row is the one that matters. Coverage percentage is a guardrail; AC-to-test mapping is the
actual contract.

## 5. Definition of done

The pack states it directly: *"A change is not complete until its automated tests, accessibility checks,
API contract checks, and relevant observability are included."* `[LOCKED]`

Expanded into a per-change checklist:

- [ ] Spec approved before planning; plan approved before code (Forge mandatory gates)
- [ ] T1 + T2 written and green in every repo the change touches
- [ ] T3 seam tests green against the frozen wave contract, where the change crosses BE↔FE
- [ ] Accessibility scan green on every page the change adds or alters (NFR-3)
- [ ] API contract checks green — envelope, error codes, enum casing, money shape (doc 05)
- [ ] Observability included — structured logs at the right level, correlation id propagated, no PII in
      log output
- [ ] Lint, typecheck, build green in every touched repo
- [ ] Dependency-vulnerability gate green
- [ ] Mobile parity where the change is user-facing (AC-11)
- [ ] Placeholder fixture removed if the change replaces one (doc 02 §7)
- [ ] Diff reviewed against spec and plan

## 6. Observability

`[LOCKED]` in principle, stack undecided. `[PROPOSED]` minimum:

- **Structured JSON logs**, one schema across both runtimes, correlation id on every line.
- **Correlation propagation** gateway → service → service, returned to the client in `error.correlation_id`.
- **Domain events worth logging explicitly:** ad submitted, approved, rejected (with reason), expired;
  featuring purchase initiated and settled; webhook received and its idempotency outcome; moderation
  queue depth; login failure rate.
- **Operational metrics tied to real promises:** moderation queue depth and oldest-pending age (NFR-6's
  24-hour promise is unmonitorable without this), `GET /ads` latency, image-upload failure rate, payment
  settlement success rate.
- **Error reporting** with release tagging in all three clients — a mobile client in the field cannot be
  debugged by reading server logs.
- **No PII in logs** — contact details are the obvious leak, and it is a foundation-slice concern.

## 7. Release gates

| Gate | Applies to | Blocks |
|---|---|---|
| Spec approved | Every feature | Planning |
| Plan approved | Every feature | Implementation |
| Lint / typecheck / build green | Every repo touched | The wave PR |
| T1 + T2 green | Every repo touched | The wave PR |
| T3 seam green | Cross-repo waves | The wave PR |
| Accessibility scan green | Every UI change | The wave PR |
| Dependency-vulnerability gate | Every repo | The build |
| T-E2E full suite | Final wave of a feature | Merge |
| Manual operator smoke | M2 onward | Milestone acceptance — moderation is human work and deserves a human check |
| Mobile store submission | M1 onward | Milestone acceptance. Store review latency is real; do not discover it at M5 |

## 8. Delivery risks

| # | Risk | Mitigation |
|---|---|---|
| D-1 | Foundation cost overruns and squeezes feature time (doc 03 §2) | Time-boxed two-service spike before committing; documented fallback to two deployables |
| D-2 | Design debt — roughly as many screens missing as exist (doc 02 §3), including the entire payment flow | Gate 3 sizing must count design work as work, not assume UI is a thin layer |
| D-3 | Nine categories, one attribute schema specified (FR-9) | Spike the schema mechanism against three structurally different categories before Gate 3 |
| D-4 | Two undecided scope items — messaging and OCR/AI intake — both large, both already in the UI | Force explicit in/out decisions at Gate 1. Neither should be discovered mid-delivery |
| D-5 | Three clients × five services = wide seam surface | T3 seam tier as the primary defect net; one generated API client per surface from a single schema |
| D-6 | No payment gateway chosen; the only revenue flow is undesigned and unspecified | Decide the gateway at Gate 2; design the flow before M4 planning, not during it |
| D-7 | Mobile treated as a trailing surface | AC-11 makes parity an acceptance criterion of every milestone |
| D-8 | No git history, no CI, no tests, and an unenforced linter in the committed skeletons | All of it lands in M0 as explicit foundation slices |
