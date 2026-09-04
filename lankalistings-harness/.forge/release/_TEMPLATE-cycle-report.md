# [Cycle ID] — Cycle Report

> Release: [release id, e.g. V1]
> Cycle: [RC-n | UC-n] · Type: [regression | uat] · Round: [n]
> Owner: [name / team]
> Verdict: [passed | passed-with-risks | failed]
> Started: YYYY-MM-DD · Completed: YYYY-MM-DD

The report for one completed test/validation cycle. Written when the cycle
finishes; flips the tracker's `release.cycles[]` entry to its terminal status.
For `regression` cycles, a `passed`/`passed-with-risks` verdict satisfies the
**handover gate** (`regression → uat`). See `.claude/rules/tracker.md` →
"Release & UAT Lifecycle".

---

## Summary verdict

[One-paragraph plain statement: what was tested, the outcome, and whether the
build is ready to hand to UAT (regression) / accepted (UAT round).]

## Flow results

| Flow ID | Name | Type | Status | Evidence | Issues filed |
|---------|------|------|--------|----------|--------------|
| FLOW-001 | [name] | e2e | passed | `evidence/[Cycle ID]/FLOW-001.md` | — |
| FLOW-002 | [name] | manual | failed | `evidence/[Cycle ID]/FLOW-002.md` | UAT-001 |

Tally: **[NN] / [MM] passed** · [k] failed · [j] blocked · [i] deferred.

## Command evidence

[Captured output / links to CI runs for the automated portion. For regression
cycles, cite the referenced per-feature `*-test-stats.jsonl` numbers rather than
re-running them.]

## Issues filed

Issues raised by this cycle (each becomes a `uat_issues[]` entry for UAT cycles;
a regression cycle may file `bugs:` directly). Triage routing: defect → `bugs:`
via `bug_ref`; change-request → backlog feature; query → answered/closed.

| Issue | Kind | Severity | Blocking | Routed to | Status |
|-------|------|----------|----------|-----------|--------|
| UAT-001 | defect | high | true | BUG-014 | accepted |

## Accepted risks

Required for a `passed-with-risks` verdict — each must also be recorded in the
tracker `release.cycles[].accepted_risks[]`.

| ID | Description | Accepted by | Date | Notes |
|----|-------------|-------------|------|-------|
| R-REL-001 | [risk] | [name] | YYYY-MM-DD | [reasoning / follow-up trigger] |

## Sign-off notes

[For a UAT cycle: client comments, conditions, what remains before formal
sign-off. For the final UAT round: the basis for the sign-off-gate decision.]
