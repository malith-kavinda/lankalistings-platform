# Forge Harness — Sub-Agents

Sub-agents in this directory are invoked via the Task tool by main Claude (or by an orchestrator command). They run with their own context window, separate from the main session.

## Pattern

Sub-agents come in **three flavors** per the framework doctrine (`forge-harness-framework.md` §3.6):

- **Guides** — interactive, stay in the main session because their quality depends on dialogue with the developer (spec authoring, plan authoring). Guides do **not** live here.
- **Sensors** — read-only, run independently because adversarial independence from the writing session is the point (review, verification). They hold no `Edit`/`Write` tools.
- **Implementer & test specialists** — orchestrator-dispatched **writing** roles that hold `Edit`/`Write`/`Bash` and commit code or tests under an approved plan. They exist because a delivery orchestrator (`/forge-deliver`) needs to fan work out to stack-specialized workers in parallel, each scoped to its own files. They are *not* interactive guides (no developer dialogue mid-run) and *not* read-only sensors (they write) — a distinct third category.

This directory holds **sensors** and **implementer/test specialists**. The "read-only" rule below applies to sensors only.

### Sensors

Each sensor sub-agent should:
- Have read-only tools (no `Edit`, `Write`, `MultiEdit`).
- Accept inputs via the dispatch prompt (caller provides paths, versions, scope).
- Produce a deterministic output structure: verdict, findings table, recommendation.
- Be advisory by default — the human (via main Claude) decides whether to act.

### Implementer & test specialists

Each writing specialist should:
- Read its stack-specific knowledge from the **project's repo `CLAUDE.md` stack profile** (`## Backend Stack` / `## Frontend Stack`) on turn 1 — the agent definition is stack-agnostic; the project supplies framework/version/command facts. This is what makes the same agent reusable across projects.
- Be **scope-locked** to the files its work item declares (`## Files to Modify`); never touch a sibling work item's files.
- Run its own gates where it can (lint, unit/integration tests, pre-PR review) and open its own PR — **except** live-server / browser test tiers, which a dispatched sub-agent cannot sustain (it is torn down on return); those are **authored** by the test specialists and **run by the orchestrator** (the execution-decoupling contract — `forge-harness-framework.md` §3.6).
- Never re-dispatch a sub-agent (Claude Code does not allow recursive dispatch). The skills they run in the `finalize` path (`forge-pr-open`, `forge-test-verify`, `forge-pre-pr-review`) are inline by contract for this reason.
- Be **specialized per project**: rename / refill the stack profile to match your stack (this template ships generic backend/frontend/e2e/seam roles; a Go+React project fills them with Go and React facts, a Spring+Next project with Spring and Next facts).

## Currently Wired

### Sensors (read-only)

| Sub-agent | Invoked when | Reviews |
|---|---|---|
| `harness-sync-reviewer.md` | At the end of every upstream forge-harness sync | CHANGELOG.yaml application correctness — every declared change applied, tracker.yaml.harness_version bumped, no scope creep, no clobbered customizations |
| `spec-reviewer.md` | Each pass of `/forge-spec-review` (fresh context per pass) | Feature spec audit against `_TEMPLATE-spec.md`, PRD, architecture decisions, dependent specs, and CLAUDE.md required sections — produces Blockers / Important / Nits findings. Foundation specs are out of scope. |
| `plan-reviewer.md` | Each pass of `/forge-plan-review` (fresh context per pass) | Plan audit against its spec, harness conventions, and toolchain pitfalls — produces Blockers / Important / Nits findings. In wave mode adds §11 (wave vertical-shipping audit), TC-2/TC-3 (tier-match / AC-coverage), and DC-6/7/8 (design conformance). |
| `backend-reviewer.md` | `/forge-review-pr` and `/forge-pre-pr-review` on a backend diff | Stack-specific backend correctness (transaction/atomicity boundaries, ORM N+1 & lazy-loading, auth coverage on new endpoints, migration safety, concurrency) a generic review misses — generic dimensions + a project-supplied STACK-SPECIFIC checklist from the backend stack profile. Read-only, advisory. |

### Implementer & test specialists (orchestrator-dispatched, writing)

| Sub-agent | Dispatched by | Does |
|---|---|---|
| `backend-implementer.md` | `/forge-deliver` (per backend-touching WI) | Implements the backend slice of a work item per its approved plan; writes unit + integration tests; lint + test + commit per subtask; self-runs pre-PR review + opens its PR. Stack from the backend stack profile. |
| `frontend-implementer.md` | `/forge-deliver` (per frontend-touching WI) | Implements the frontend slice; writes unit/component tests; typecheck + lint + test + build per subtask; self-runs pre-PR review + opens its PR. Builds the API client from the frozen wave contract. NOT browser E2E (that is the e2e specialist). Stack from the frontend stack profile. |
| `seam-test-implementer.md` | `/forge-deliver` (verify WI, Phase 1) | **Authors + static-checks** API/contract seam tests proving the BE↔FE wiring against the frozen wave contract — no browser. Does NOT live-run (the orchestrator runs the API gate). Three dispatch modes: author / test-fix / finalize. Toolchain deferred to the WI plan's `## Test Approach`. |
| `e2e-test-implementer.md` | `/forge-deliver` (verify WI Phase 2 + final-wave e2e) | **Authors + static-checks** browser E2E + accessibility tests. Does NOT live-run (the orchestrator runs the browser suite). Same three dispatch modes. Browser toolchain named in the project's `.forge/test-strategy.md` / WI plan `## Test Approach`. |

## Future Pattern Slots (Not Currently Wired)

- **Adversarial code reviewer** — reviews diffs against a spec/plan, flags semantic mismatches and missed edge cases. Pattern preserved per framework.md §3.6; will return when a `/forge-review` command is reintroduced through real engagement experience.
- **Security reviewer** — reviews code for OWASP-style issues using a project threat model (`.forge/design/threat-model.md`) when present. Pattern preserved per framework.md §3.6; will return with a `/vuln-check` command.
- **Frontend reviewer** — a read-only frontend counterpart to `backend-reviewer` (the template ships a backend reviewer only). Add one symmetrically if your stack benefits.

## Why sensors are "read-only"

If a *sensor* sub-agent could write files, the main session would be tempted to push fix-up logic into the reviewer (because the agent has just inspected the code and "knows" the answer). That collapses the adversarial-independence boundary — the same agent both writes and reviews, which is the failure mode this pattern exists to prevent. Keep sensor tools read-only and let main Claude do the writes after reading the verdict.

This rationale is **scoped to sensors**. Implementer/test specialists write by design — their independence guarantee is different: they are *scope-locked* (each owns only its WI's files) and their tests are *run by the orchestrator*, not self-attested, so a specialist cannot both write code and bless its own live-tier result.
