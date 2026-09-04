---
name: forge-pre-pr-review
description: >
  Adversarial self-review of the local diff against the spec, plan, and project
  conventions before pushing. Use as the mandatory pre-PR step from an
  implementation worktree, or for a second opinion on uncommitted work.
  Produces a Blocker / Important / Nit verdict — no live PR needed;
  /forge-review-pr covers open PRs.
phases: [engineering]
---

# forge-pre-pr-review

Run a framework-aware adversarial review of the current branch before opening
a pull request. Invoke from the worktree session while implementation context
is still hot — Claude can reason about *why* decisions were made, not just what
changed.

> **Non-dispatch guardrail (load-bearing).** This skill MUST remain **inline /
> non-dispatching** — it never spawns a sub-agent. That is exactly why an
> implementer (already a dispatched sub-agent) may run it in the `finalize`
> path: Claude Code **forbids recursive sub-agent dispatch**, so a skill that an
> implementer self-runs cannot itself dispatch. `forge-pre-pr-review`,
> `forge-test-verify`, and `forge-pr-open` are the three finalize-path skills
> bound by this rule. If this skill ever needs a deeper, fresh-context review,
> the orchestrator (the persistent main session) dispatches the `backend-reviewer`
> / `frontend-reviewer` — this skill itself does not. Treat the non-dispatching
> nature of all three as load-bearing.

## Invocation modes

Invoked explicitly as `/forge-pre-pr-review` from the implementation worktree
session; an implementer sub-agent may self-run it in the `finalize` path (see
the guardrail above). Ticket and WI are derived from the branch name (Step 1) —
it takes no arguments. The verdict format is identical to `/forge-review-pr`;
the difference is that this skill reviews the **local diff** and requires no
live PR, while `/forge-review-pr` reviews an already-open GitHub PR.

## When to use

- As the penultimate step in every plan (the mandatory pre-PR task)
- Whenever you want a second opinion on uncommitted work mid-implementation
- Never skipped — if a Blocker is found, fix it before pushing

## Stack calibration — read this first

This skill is **stack-neutral by construction.** The check *categories* below
are framework-agnostic; the concrete bullets are deliberately delegated. Before
running any check, read the repo's **Stack Profile** so the checks match the
actual framework, ORM, language version, and test stack in play:

- For a backend repo: `<backend-repo>/CLAUDE.md` `## Backend Stack` + `## Common Commands`
- For a frontend repo: `<frontend-repo>/CLAUDE.md` `## Frontend Stack` + `## Common Commands`
- For locked invariants: the project `CLAUDE.md` `## Architecture Decisions (DO NOT REVERSE)` table

Map each generic category (transaction boundaries, ORM footguns, design tokens,
auth coverage) to the concrete construct the repo's Stack Profile names
(annotations, decorators, config keys, idioms). If the repo declares no Stack
Profile, note the reduced calibration and review against the generic categories
plus your own knowledge of the named stack.

## Process

### Step 0 — Test-verify precondition (must pass before any other step)

This skill is gated by `/forge-test-verify`. The **orchestrator runs the suite
to green first**, then `/forge-test-verify` (the green-status guard) emits
`Pass`, then this review runs (the `finalize` step). A `Pass` verdict *means*
"the orchestrator's run is green," not "this skill ran the suite."

Derive the ticket and WI ID from the branch name (same logic as Step 1 below). Locate the audit file:

- Decomposed WI: `<harness-repo>/.forge/plans/<ticket>/<wi-id>-test-verify.md`
- Single-plan: `<harness-repo>/.forge/plans/<ticket>-test-verify.md`

Read the most recent block in the file (audit entries are appended top-to-bottom; the last `> Verdict:` line is the current verdict).

**Abort conditions:**

- Audit file does not exist:
  > Test-verify precondition failed: no audit file at `<expected path>`.
  > Run `/forge-test-verify` from this worktree first; this review cannot proceed until it emits Pass.

- Audit file's latest verdict is `Fail` or `Re-run required`:
  > Test-verify precondition failed: latest verdict at `<path>` is `<Fail | Re-run required>`.
  > `Re-run required` means the orchestrator must (re-)run the suite to green; `Fail` means a missing file / uncovered AC / failing cheap-tier test. Resolve it (orchestrator re-runs, or re-dispatch the responsible agent) and confirm `/forge-test-verify` emits Pass before re-running this review.

- Branch does not match a Forge implementation branch shape (no `feature/<ticket>-*` or `fix/<ticket>-*`):
  > Cannot derive ticket from branch `<branch>`. The test-verify precondition cannot be checked. Confirm the branch name and re-run.

Defense in depth: the orchestrator's green-status guard is the primary enforcement. This Step 0 prevents the review from being run out of order during manual sessions or after a reorganisation of the pipeline.

### Step 1 — Gather context

Run all of the following before any analysis:

```bash
git branch --show-current                       # branch name → derive ticket ID
git log main..HEAD --oneline                    # commits on this branch
git diff main...HEAD --stat                     # files changed summary
git diff main...HEAD                            # full diff (capped at ~3000 lines)
```

Derive the **ticket ID** from the branch name: `feature/PROJ-001-schema-substrate`
→ `PROJ-001`. (The example prefix is illustrative — use the project's own
ticket grammar.) Wave branches follow `feature/<ticket>-wave-<N>`. If the branch
does not follow `feature/<ticket>-*` or `fix/<ticket>-*`, ask the developer to
confirm the ticket before proceeding.

Locate the harness as `../<harness-repo>` relative to the repo root (per the
workspace structure in CLAUDE.md). Confirm the path exists before reading.

### Step 2 — Load spec, plan, and conventions

Read in this order:

1. `<harness-repo>/.forge/specs/<ticket>-*-spec.md` — acceptance criteria, scope,
   requirements. If not found, warn and continue without AC coverage check.
2. `<harness-repo>/.forge/plans/<ticket>-*-plan.md` — decisions, files-to-modify,
   subtasks. If not found, warn and continue.
3. `.claude/CLAUDE.md` (current repo) — the repo's **Stack Profile**
   (`## Backend Stack` / `## Frontend Stack`), `## Common Commands`, and the
   project's `## Architecture Decisions` + Boundaries. The project's locked
   ADs are the hard constraints — any diff that violates one is a Blocker.

### Step 3 — Framework checks

Run these checks against the diff + loaded context. Flag each finding with
severity (Blocker / Important / Nit) and file:line where applicable. The
categories are stack-neutral; map each to the concrete construct the repo's
**Stack Profile** names.

**AC Coverage**
For each acceptance criterion in the spec, locate the implementation surface
in the diff. Flag as **Important** any AC with no corresponding code or test.

**Plan alignment**
Compare "Files to Modify" in the plan against files actually changed. Flag as
**Important** any unplanned file touched (unless it's a test, config, or
obvious consequence). Flag as **Nit** any plan file not touched (may be
legitimately deferred — note it).

**Architecture Decisions (locked) — always checked**
Read the project `CLAUDE.md` `## Architecture Decisions (DO NOT REVERSE)` table
and flag any diff that violates a locked invariant as a **Blocker** — and
**STOP and escalate**: a violation means the plan/design is wrong, not that the
code should be patched around it. These are project-specific (config-swap
invariants, data-access boundaries, tenancy/scoping rules, status workflows,
role models, etc.) — read them from the table; do not assume them here.

**Convention conformance (from the Stack Profile)** — always checked
Map these stack-neutral hazards to the framework constructs the Stack Profile
names:
- No environment-branching / build-time-config-divergence code where the ADs
  mandate a config-swap invariant
- No secrets, keys, or credentials committed
- No direct push to main / no CI bypass flags
- Transaction & atomicity boundaries respected — declarative transaction
  annotations only where the stack intends them (service layer, not
  controllers/repositories); audit/side-effect writes inside the same
  transaction as the audited action, never fire-and-forget
- Data-access layer matches the AD-locked mechanism (e.g. the sanctioned
  ORM/driver, not a forbidden client SDK)
- No raw file bytes proxied through the API where a presigned/direct-URL
  pattern is mandated

**Test quality** — map tiers to the repo's test stack
- New public methods / functions / SQL routines have at least one **T1 (unit)** test
- Constraint-violation / DB-boundary tests use parameterised statements —
  never string-interpolated user data into SQL
- Tests using raw connections outside the framework's managed transaction clean
  up after themselves (idempotency under container/runner reuse)
- No absolute `COUNT(*) FROM <table> == N`-style assertion against a table other
  tests mutate. In a shared test-DB / container singleton this is an
  order-dependent failure that detonates in a sibling work item's wave. Flag as
  **Important**; the fix is to assert `>=`, scope the count to the test's own
  authored keys, or have the mutating test clean up after itself (L-026)
- No transaction annotation on constraint-violation tests where the violation
  must abort the transaction to be observable
- Tier discipline: T1 (unit) / T2 (integration) / T3 (API-seam + WI-scope E2E)
  / T-E2E (full browser suite) — confirm the diff's new tests land in the tier
  the test strategy assigns, and that the implementer authored only the tiers
  it owns (BE/FE author T1/T2; T3/T-E2E belong to the test specialists)

**Design conformance** — *only if the project has a design reference, and only
for diffs touching visible-UI source:* the design system lives at
`<harness-repo>/.forge/design/ui/<design-system>.md` plus a `<prototype>`. If a
design reference exists, flag: hardcoded color values that should be semantic
design tokens (Important); new components that don't match the design spec's
component shapes, or screens diverging from the prototype (Important); a new
**sub-view** (routed detail / `…/[id]` / `…/new` / `…/edit` screen) with no
in-app back navigation — breadcrumb or labelled back button per the design
spec's navigation rules (Important); UI-text capitalization violating the design
spec's casing rules — labels/buttons/titles/nav not in the prescribed case, or
prose forced into Title Case, excluding proper nouns and API-owned status
strings (Important); note any visual AC lacking a corresponding assertion.
Skip entirely for backend-only diffs **and** for projects with no design reference.

**Security**
- No SQL/queries constructed from user-supplied strings without parameterisation
- No sensitive data (passwords, tokens, PII) in log statements
- Auth guard present on every new API endpoint
- No hardcoded credentials in any file type

**Dependency direction**
Per the project's `## Architecture Decisions` / module layout: a shared
utilities layer must not import from domain packages, and cross-layer imports
must respect the declared direction. Flag as **Important** any import that
violates the layering the project defines.

**Resource lifecycle**
Any new closeable resource (DB connections, object-store clients, HTTP clients,
streams) must be released — via the stack's idiomatic mechanism
(try-with-resources / `using` / context manager / framework-managed bean
lifecycle). Flag unclosed resources as **Important**.

**Migration hygiene** — if the diff touches DB migrations
- New migrations are idempotent per the migration tool's idioms (`IF NOT EXISTS`
  / `CREATE OR REPLACE` / equivalent), per the project's NFRs
- Migration filename is in the correct version block for this feature's ticket
  (per the migration version-block map in the repo's `CLAUDE.md`, if one exists)
- No migration file has been edited after initial creation (checksum invariant —
  hooks may catch writes, but check anyway)

### Step 4 — Adversarial pass

Open-ended sweep — ask: *"What could go wrong at runtime or under edge cases
that the tests as written would not catch?"* Calibrate the specific footguns to
the repo's Stack Profile.

Focus areas (map to the stack):
- Logic bugs in queries / SQL routines (off-by-one in ranges, missing NULL
  handling, wrong join conditions)
- ORM / persistence footguns (value objects without `equals`/`hashCode`,
  lazy-loading outside an open session, scope/lifetime bean interactions)
- Race conditions (double-insert without an upsert/conflict guard,
  non-atomic read-modify-write)
- Partial-failure scenarios (what happens if step 2 of a 3-step operation fails?)
- Test isolation (shared mutable state between tests, container/runner reuse
  without cleanup; absolute `COUNT(*) FROM <table> == N` assertions against a
  table other tests mutate — order-dependent in a shared test-DB/container
  singleton, so it passes alone but detonates in a sibling work item's wave) (L-026)

### Step 5 — Verdict

Produce a structured verdict in this exact format:

```
## Pre-PR Review — <ticket> (<branch>)

**Verdict:** [Ready to push | Fix Blockers first | Nits only — your call]

### 🔴 Blockers  (must fix before push)
- `file:line` — <what> — <why> — <suggested fix>

### 🟡 Important  (should fix; flag in PR if deferred)
- `file:line` — <what> — <why>

### 🔵 Nits
- `file:line` — <what>

### ✅ What's solid
- <2–3 specific strengths worth naming>
```

If there are no findings in a category, omit that section.

### Step 6 — Resolution loop

**If Blockers exist:**
- List them clearly; do not proceed
- After the developer fixes them, offer to re-run: "Fix committed — re-run
  `/forge-pre-pr-review` to confirm clean"

**If clean or Nits only:**
- Print the verdict
- Remind: "Record this review in the plan's ## Notes section, then push and
  open the PR (`/forge-pr-open`)."

## Must not

- Invent spec paths — only use paths confirmed to exist on disk
- Run `git push` or open a PR — that remains `/forge-pr-open` / the developer's explicit action
- Skip the adversarial pass even if framework checks are clean
- Mark the review as passed if any Blocker is outstanding
- Dispatch a sub-agent — this skill is **inline / non-dispatching** (see the
  Non-dispatch guardrail header); the orchestrator owns any deeper reviewer dispatch
- Hardcode a framework, ORM, test runner, or GitHub org — read them from the
  repo's Stack Profile and `TRACKER.github_org` in `.forge/tracker.yaml`
