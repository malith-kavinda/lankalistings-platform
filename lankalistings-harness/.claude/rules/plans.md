---
description: Plan lifecycle — required sections, progress updates, failed approaches, rework triggers, status transitions. Loads when editing files under .forge/plans/.
globs: .forge/plans/**
---

# Plan Lifecycle Rules

Section schema lives in `.forge/plans/_TEMPLATE-plan.md`. These are the *rules* for working with plans.

## Required Sections

Every plan must have all the following sections populated:

- **Approach** — implementation strategy and key decisions
- **UI / Design Adherence** — REQUIRED for WIs shipping user-visible UI, **only if the project has a design reference** (`.forge/design/ui/<design-system>.md` + a prototype/mockup, both project-set). Cite the design-system spec + the prototype and declare the semantic tokens, custom components, and screen layouts the WI conforms to. Sub-views (detail / `…/[id]` / `…/new` / `…/edit`) must declare a back-navigation affordance; all UI text follows the design system's capitalization rule. The spec is authoritative over the prototype. Omit (delete the section) for backend-only WIs or projects with no design reference.
- **Decisions** — specific technical choices (patterns, libraries, why)
- **Subtasks** — ordered, numbered list — small enough to be a session boundary
- **Files to modify** — specific paths with what changes in each
- **Risks** — what could go wrong and mitigation
- **Test Approach** — tier (T1/T2/T3/T-E2E — see `.forge/test-strategy.md`), rationale, and test tables for the assigned tier; sub-WI plans must match the tier in the Decomposition Plan's `## Test Strategy Map`. **Runtime-verifiable**: every row's test file must exist on the worktree at PR-open time, every AC on hook (filtered by the `Ownership` column for verify-WIs) must be covered by at least one row, and the suite must be green. **Execution decoupling (Dispatch Invariant):** the test specialists (`e2e-test-implementer`, `seam-test-implementer`) **author + static-check** these tests but do NOT live-run them — a dispatched sub-agent is torn down on return and cannot keep dev servers booted or drive a live browser. The **main orchestrator** runs the live browser / API-seam tiers and drives a run → classify → dispatch-fix → re-run-until-green loop; `/forge-test-verify` then acts as the **green-status guard** (files exist, ACs covered, the orchestrator's run is green; for T1/T2 it runs the cheap command itself). Test files are durable, reusable artifacts — reuse existing tests for previously-built functions and author new rows only for new functionality. Plan-time `/forge-plan-review` TC-2 (tier-match) and TC-3 (AC-coverage) are the static counterparts; in wave mode plan-reviewer §11 (Wave Vertical-Shipping Audit) adds verify-WI-aware checks.
- **Progress** — updated as subtasks complete; includes failed approaches
- **Notes** — review feedback, discoveries, anything that doesn't fit above

**Sub-WI plan header fields** (decomposed specs only): fill `> Key Workitem:` and `> WI ID:` from the template — `/forge-plan-review` uses these to detect sub-WI plans and run tier-match (TC-2) and AC-coverage (TC-3) checks. `> Key Workitem:` points at the owning Decomposition Plan; `> WI ID:` is this plan's work-item id. Plans that predate this convention and carry `> Parent Key Workitem:` are grandfathered at their current approved status; new or revised sub-WI plans must use `> Key Workitem:` + `> WI ID:`.

## Status Transitions

- New plan → `Status: draft` in both file and tracker
- Never assume approval. Only mark `approved` when the developer explicitly confirms
- Approval requires a `Reviewed-via: /forge-plan-review` annotation in the header — the `guard-plan-approval` hook enforces this at write time (foundation and feature plans both gated)

## Progress Discipline

- Update the plan's `## Progress` section before ending any implementation session
- Record failed approaches in `## Failed Approaches` — what was tried and why it didn't work. Prevents the next session from repeating dead ends
- Follow patterns referenced in the plan — if the plan says "follow UserService", follow it

## Rework Triggers

- **Check fails** → fix in the same worktree and re-run. Record the fix in `## Progress`. Normal development loop.
- **Review rejects implementation** → record feedback in `## Notes` (what was wrong, what needs to change). Fix and resubmit. If the fix needs a different approach, update the plan with the new approach and note what changed and why.
- **Spec changed mid-implementation** → if the change invalidates the current plan, pause implementation and revise the plan first.

## Deviation

Deviating from the approved plan's approach is an **ASK FIRST** action — surface it before coding, not after.
