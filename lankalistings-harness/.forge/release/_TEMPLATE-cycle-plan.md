# [Cycle ID] — Cycle Plan

> Release: [release id, e.g. V1]
> Cycle: [RC-n | UC-n] · Type: [regression | uat] · Round: [n]
> Owner: [name / team]
> Status: [planned | running | passed | passed-with-risks | failed]
> Date: YYYY-MM-DD

The plan for one test/validation cycle in the release lifecycle. Pair it with the
tracker's `release.cycles[]` entry (same id) and write the matching
`[Cycle ID]-report.md` when the cycle completes. See `.claude/rules/tracker.md`
→ "Release & UAT Lifecycle".

---

## Scope

- **Target:** [which delivery phases / which assembled product slice this cycle exercises — `scope_phases`]
- **Cycle intent:** [internal pre-UAT regression certification | client UAT round N | re-test after stabilization]
- **Out of scope:** [what this cycle deliberately does NOT cover]

## Critical flows

The flow checklist this cycle runs. Each row mirrors a `release.cycles[].flows[]`
entry in the tracker. `priority`: critical | high | normal. `type`: e2e | manual
| exploratory | accessibility | security.

| Flow ID | Name | Source refs (ACs/features) | Priority | Type | Evidence path |
|---------|------|----------------------------|----------|------|---------------|
| FLOW-001 | [e.g. Lead → student conversion end to end] | [feature-a AC-2, feature-d AC-4] | critical | e2e | `evidence/[Cycle ID]/FLOW-001.md` |
| FLOW-002 | | | | | |

## Test commands

Commands run for the automated portion (referenced, not duplicated, from
per-feature `*-test-stats.jsonl` — regression cycles **reference** build-time
numbers, they do not re-run them):

```bash
# e.g. full assembled-product e2e suite against staging
```

## Manual / exploratory checklist

Steps the operator walks by hand (each `manual`/`exploratory` flow needs an
evidence file before it can be marked `passed`):

- [ ] [step / scenario]
- [ ] [step / scenario]

## Accounts / environment

- **Environment:** [staging URL / build ref]
- **Accounts / roles:** [test accounts, roles, credentials location]
- **Data:** [seed data / fixtures / client data set]

## Risk areas

- [areas of higher uncertainty to probe harder]

## Exit criteria

What makes this cycle `passed` (or `passed-with-risks`):

- [ ] All `critical` flows `passed` (with evidence)
- [ ] No unresolved blocking issue (`blocking_issues[]` empty or accepted)
- [ ] Any `passed-with-risks` carries each accepted risk recorded in the tracker `accepted_risks[]`
