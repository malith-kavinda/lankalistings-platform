# LankaListings — Test Strategy

> Status: draft — **toolchain proposed, not yet installed.**
> Last updated: 2026-08-24
> Related: `.forge/checklists/quality-checklist.md`, `.forge/design/architecture.md`, `.forge/discovery/docs/06-delivery-quality.md`

> ## ⚠️ Current reality — read before claiming any test gate
>
> **There is no test framework in any repo on this project.** All three client workspaces have zero test
> dependencies, and `lint` in each is aliased to `tsc --noEmit` — a typecheck, not a lint. No backend code
> exists at all.
>
> Until foundation slices **F-008** (real linter + CI) and **F-011** (test harness per tier per runtime +
> the deterministic seed dataset) land, "lint and tests pass" cannot be truthfully claimed on this
> project. State what actually ran.
>
> ## Project-specific toolchain — PROPOSED
>
> Nothing in the project inputs names a test framework, so the table below is an engineering proposal for
> Gate 2 to confirm. It replaces the `[…]` placeholders in the tier tables further down.
>
> | Tier | Spring Boot services | FastAPI services | `frontend-web` / `management-portal` | `mobile` |
> |---|---|---|---|---|
> | **T1 unit** | JUnit 5 + Mockito | pytest + `unittest.mock` | Vitest + React Testing Library | Jest + React Native Testing Library |
> | **T2 integration** | Spring Boot Test + Testcontainers Postgres | pytest + `httpx.AsyncClient` against an ephemeral Postgres | Vitest + MSW | Jest + MSW |
> | **T3 seam** | Cross-runtime contract tests against the frozen per-wave contract — **no browser** | ← same | — | — |
> | **T3 / T-E2E browser** | Playwright against a booted stack + an accessibility scan per visited page | ← same | ← same | Maestro or Detox for native flows |
>
> Coverage tool: JaCoCo (JVM), `coverage.py` (Python), Vitest/Jest built-in (clients).
>
> ## Two rules that matter more here than on a single-runtime project
>
> 1. **The seam tier is the load-bearing tier.** Five services across two runtimes serving three clients
>    means most defects will be *boundary* defects: enum casing, error-shape divergence, money as float,
>    timestamp format, pagination style. T3 seam tests against the frozen wave contract are what catch
>    those — and they must run **cross-runtime**. A Spring Boot contract test that only exercises Spring
>    Boot proves nothing about what FastAPI returns.
> 2. **FastAPI's framework defaults lose.** Its default `422` validation body and `{"detail": …}` error
>    shape both conflict with the project's error contract (`.forge/discovery/docs/05-api-contract.md` §3)
>    and must be overridden. Assert the project contract in tests, not the framework default.
>
> ## Always-test list for this product
>
> Non-negotiable regardless of tier budget:
>
> - **Every advertisement status transition, valid *and* invalid.** The status machine is the product's
>   central invariant.
> - **Non-`active` invisibility on every public read path** — browse, search, featured rail, detail by
>   reference — on all three clients, returning **404 not 403**. This is SC-4 and it is the product's core
>   promise expressed in code. One unguarded path breaks it silently.
> - **Ownership scoping** on every seller mutation and on featuring purchase.
> - **Role enforcement** on every operator endpoint, at the service and not only at the gateway.
> - **The featuring gate** — purchase rejected with `409 AD_NOT_ACTIVE` for a non-`active` or non-owned ad
>   (SC-9).
> - **Webhook idempotency** — the same settlement delivered twice yields exactly one featured window
>   (SC-15).
> - **Money** — no float anywhere in the path, in any of five services or three clients; formatting correct
>   at `Rs. 45,000,000` scale.
> - **Field validation, client *and* server** — title ≤70, description ≤4000, required fields.
> - **Filter and sort correctness**, including featured-first ranking with **both** a live and an expired
>   featured window present in the fixture — the ranking rule is untestable without both.
>
> ## Coverage targets
>
> | Category | Target |
> |---|---|
> | Service business logic (status machine, authorisation, money, ranking) | ≥85% |
> | Service API layer | ≥80% |
> | Interactive UI components | ≥70% |
> | Presentational components | Covered by E2E/visual rather than brittle markup assertions |
> | **Every success criterion in PRD §Success Criteria (SC-1…SC-15)** | **100% mapped to at least one test** |
>
> The last row is the contract. The percentages are guardrails.
>
> ## Seed dataset
>
> One deterministic dataset shared across T2/T3/T-E2E. Minimum shape is specified in
> `.forge/discovery/docs/04-data-model.md` §9 — all 9 provinces and 25 districts, all 9 categories with
> attribute definitions for at least three structurally different ones, accounts covering every role, ads
> in **every** status, one live-featured and one expired-featured ad, a 12-image gallery, a reported ad and
> an automated-flag ad.

---

## Purpose

This document defines how code is tested across the project — what is tested, at which **tier**, with which tools, and when each tier runs. It is the spine of the Forge delivery workflow: decomposition assigns a **test tier** to every work item (`## Test Strategy Map`), plans declare their tier in `## Test Approach`, the test specialists author tests for their tier, and `/forge-test-verify` guards that the prescribed tests exist and are green.

**This file is a template.** The *tier model* and the *workflow wiring* below are framework doctrine — keep them. The concrete **toolchain** (test frameworks, runners, commands, file layout) is project-specific — fill in the `[…]` placeholders with your stack's choices. Every feature plan must reference this document and specify which tiers apply.

`<backend-repo>` / `<frontend-repo>` below are your repo names (declared in `CLAUDE.md` §2). A single-repo or backend-only project simply omits the frontend rows.

---

## The Test Tier Model (framework-level — do not rename)

Forge delivery is organized around four tiers. The tier names (`T1`/`T2`/`T3`/`T-E2E`) are referenced by the decomposition `## Test Strategy Map`, plan `## Test Approach`, `forge-plan-review` (TC-2 tier-match, TC-3 AC-coverage), `forge-test-verify`, and the test-specialist agents — they are stable across projects. What *changes* per project is the toolchain that implements each tier.

| Tier | What it proves | Scope | Who **authors** | Who **runs** it |
|------|----------------|-------|-----------------|-----------------|
| **T1 — Unit** | Individual functions/classes/components in isolation; dependencies mocked. | Within one file/module. | the implementer (backend/frontend) | the implementer (sub-agent can run it) |
| **T2 — Integration** | Units work together with real in-repo dependencies (DB, in-process API, framework context). | Within one repo. | the implementer | the implementer, if the infra is available in-session (e.g. a container) |
| **T3 — Seam + WI-scope E2E** | (a) the **BE↔FE seam**: the API contract holds across repos, no browser (`seam-test-implementer`, verify Phase 1); (b) **WI-scope browser E2E**: the slice this wave shipped works in a real browser (`e2e-test-implementer`, verify Phase 2). | Cross-repo / through a running stack. | the **test specialists** (author + static-check only) | the **orchestrator** (`/forge-deliver` boots the servers and runs the live suite — a torn-down sub-agent cannot) |
| **T-E2E — Full suite** | All user workflows across all roles, end to end. | The whole product. | `e2e-test-implementer` (final-wave `type: e2e` WI) | the **orchestrator** |

> **Execution-decoupling contract (load-bearing).** A dispatched sub-agent is torn down when it returns, so it cannot keep two dev servers booted or drive a live browser. Therefore the T3/T-E2E specialists **author + static-check** tests and commit "Ready to run"; the persistent **main orchestrator runs** the live suites and owns the *run → classify → dispatch-fix → re-run-until-green* loop (test bug → the test specialist in `test-fix` mode; code bug → the owning implementer). T1/T2 are sub-agent-runnable, so the implementers both write and run them. `/forge-test-verify` is the green-status guard that runs *after* the orchestrator's run is green.

---

## Tier toolchain — FILL IN

Replace each `[…]` with your stack's choice. The *concepts* (mock isolation, real-dependency integration, browser E2E + accessibility) are universal; the tools are yours.

### T1 — Unit

| Aspect | `<backend-repo>` | `<frontend-repo>` |
|--------|------------------|-------------------|
| Framework | `[backend unit framework]` | `[frontend unit framework + component testing lib]` |
| What to mock | external services, data-access layer, security context | API calls, router, auth context |
| What NOT to mock | the unit under test, simple value objects | the component under test |
| Naming / location | `[convention]` | `[convention — e.g. co-located *.test.*]` |
| Run command | `<backend-test-cmd>` (see CLAUDE.md §Common Commands) | `<frontend-test-cmd>` |

**Unit-test per feature:** every method with business logic, every state-transition rule, every validation rule, every component with conditional rendering or interaction, every custom hook/util. **Don't** unit-test trivial accessors, framework-generated code, or styling.

### T2 — Integration

| Aspect | `<backend-repo>` | `<frontend-repo>` |
|--------|------------------|-------------------|
| Framework | `[backend integration framework + real-dependency harness, e.g. ephemeral DB]` | `[frontend integration approach, e.g. API mocking lib]` |
| Scope | data-access against a real DB, controller→service→data flows, auth/security chain, role-based data scoping | page-level rendering with mocked API, form-submission flows, protected-route behavior |
| Real dependency | `[how you stand up a real DB/services for tests]` | `[API mock layer]` |
| Run command | `<backend-check-cmd>` | `<frontend-test-cmd>` |

### T3 — Seam + WI-scope E2E

| Aspect | Details |
|--------|---------|
| **Seam (Phase 1)** | API/contract tests proving the BE↔FE seam against the frozen wave contract (`<TICKET>-Wave-<N>-contract.md`) — **no browser**. Toolchain: `[seam test driver — e.g. an HTTP request fixture, or the backend's in-process integration harness]`. Authored by `seam-test-implementer`; named in the verify-WI plan's `## Test Approach`. |
| **WI-scope browser E2E (Phase 2)** | Browser tests for the slice this wave shipped + an accessibility scan on each visited page. Toolchain: `[browser E2E framework]` + `[accessibility checker]`. Authored by `e2e-test-implementer`. |
| Config / location | `[e2e config path]`, `[e2e test root]` |
| Run command | `<e2e-cmd-scoped>` (scoped to this WI's paths) |

### T-E2E — Full suite

| Aspect | Details |
|--------|---------|
| Scope | all user workflows, all roles, end to end; runs as the merge gate on the final-wave integration PR. |
| Toolchain | same browser-E2E framework as T3, full coverage. |
| Run command | `<e2e-cmd>` (full suite) |

> **Selector & fixture conventions** (prefer role/label queries over brittle CSS/XPath; reuse pre-authenticated state per role; assert behavior over pixels; run an accessibility scan on every visited page) belong in this file or a project E2E section — the `e2e-test-implementer` reads them here.

---

## When Tests Run

| Trigger | What runs | Failure blocks |
|---------|-----------|----------------|
| **Every code change** (dev loop) | affected T1 + lint | nothing — fast feedback |
| **Per-subtask** (implementer) | T1 + lint (+ T2 and build where runnable) | the subtask commit |
| **Verify gate** (`/forge-deliver` Stage 7, per wave) | the **orchestrator** runs the live T3 seam gate then the T3 browser suite + the run→classify→fix→re-run loop; `/forge-test-verify` then guards green status (files exist, ACs covered, run green) | PR open — guard returns `Re-run required` / `Fail` until green |
| **Wave PR merge** | CI runs the full suite for the wave; the final wave runs **T-E2E** as the merge gate | the wave PR merge |

---

## Coverage Targets

Coverage is a guardrail, not a goal — high coverage of trivial code is worthless; low coverage of critical paths is dangerous. Set targets per category (e.g. business-logic ≥ 80%, interactive UI ≥ 70%, critical-path acceptance criteria 100% mapped to a test). **Always test, no exceptions:** authentication/authorization, every state-transition (valid + invalid), data scoping per role permutation, form validation (client + server), pagination/filtering. Fill in concrete numbers + the coverage tool for your stack: `[coverage tool]`.

---

## Test Data & Isolation

A deterministic seed dataset shared across T2/T3/T-E2E keeps tests reproducible — size it to exercise your domain's hierarchy and role permutations. **Isolation:** T1 fully mocked (no shared state); T2 rolls back per test (or uses a fresh ephemeral DB); E2E resets/reseeds between test files and isolates data across parallel files.

> ⚠️ **Shared-fixture hazard (from real engagements).** In a shared test-DB/container singleton, **never assert an absolute `COUNT(*)`** on a table other tests mutate — it is an order-dependent failure that detonates in a *sibling* work item's wave. Assert `>=`, scope the count to your authored keys, or have mutating tests clean up. When sibling WIs in the same wave touch shared test infrastructure (e.g. a reused DB container), disable container reuse for the parallel run.

---

## Accessibility & Security

- **Accessibility** (if the product has a UI): a target standard (e.g. WCAG 2.1 AA) tested at component level (semantic HTML, ARIA, keyboard nav) and page level (an automated `[accessibility checker]` scan on every page visited during E2E — not optional).
- **Security**: test security-relevant features at the tier that proves them — injection & parameterized queries (T2), XSS (T1/T3), auth bypass / privilege escalation / token tampering (T2 seam), credential storage (T1). Use the project threat model (`.forge/design/threat-model.md`) when present.

---

## Mapping to the Forge Workflow

| Phase | Test activity |
|-------|---------------|
| **Spec** | Acceptance criteria are written so each maps to ≥1 test (observable + verifiable). |
| **Decompose** | `## Test Strategy Map` assigns a tier (T1/T2/T3/T-E2E) to every work item; AC coverage + ownership recorded. |
| **Plan** | `## Test Approach` declares the WI's tier + the test files; `forge-plan-review` TC-2 (tier-match) / TC-3 (AC-coverage) enforce it at plan time. |
| **Implement** | Implementers write + run T1/T2 alongside code; T3/T-E2E are authored by the test specialists. |
| **Verify** | The orchestrator runs the live tiers + the repair loop; `/forge-test-verify` guards green status. Pass is the precondition for `/forge-pre-pr-review` + `/forge-pr-open`. |
| **Review / Ship** | Tests exist for every AC; the wave PR's CI is the merge gate; the final wave runs the full suite. |
| **Reflect** | Note test patterns worth promoting; update this strategy if the approach changed. |

---

## Test Checklist for Implementation Plans

Every feature plan's `## Test Approach` should cover the applicable rows:

- [ ] T1 unit tests for all business-logic methods + interactive UI components
- [ ] T2 integration tests for all new API endpoints (happy + 401/403/400 paths)
- [ ] T2 integration tests for data scoping (if the feature touches scoped data)
- [ ] T3 seam tests against the frozen wave contract (BE↔FE waves)
- [ ] T3 WI-scope browser E2E for every acceptance criterion with user-visible behavior + an accessibility scan per new page
- [ ] T-E2E coverage folded into the full suite (final wave)
- [ ] Security tests if the feature touches auth, roles, or user input

---

## Writing Tests with Claude Code

1. Read the spec's acceptance criteria — each maps to ≥1 test.
2. Write tests alongside implementation, not after.
3. Run tests after every change (a Boundaries hard rule).
4. Name tests after the behavior, not the method.
5. **Reuse** existing tests for previously-built functions; author new tests only for new functionality.
