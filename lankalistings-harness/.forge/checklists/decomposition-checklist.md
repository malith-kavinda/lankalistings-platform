# LankaListings — Decomposition Readiness Checklist

> Used by `/forge-decompose` (Gate 3). Customize per project — drop items that don't apply, add items that do.
>
> Each item is **pass / fail / N/A**. Failures are logged with the *specific feature(s) at issue*.

## Slicing

- [ ] Slicing principle stated (by module / by user journey / by capability / by phase)
- [ ] Slicing principle applied consistently across the breakdown (don't mix journey-sliced and module-sliced units silently)

## Coverage

- [ ] Every in-scope item from the PRD maps to at least one feature spec
- [ ] No feature spec exists that doesn't map back to the PRD (no scope creep at decomposition time)

## Separation

- [ ] No two feature specs claim ownership of the same surface
- [ ] Shared concerns (auth, data model, design system) live in their own foundation specs, not duplicated across feature specs

## Dependencies

- [ ] Dependency graph between features is drawn (mermaid block in `.forge/features.md`)
- [ ] No cycles
- [ ] Critical path identified — what blocks what
- [ ] Foundation features (auth, schema, design system) sequenced before features that depend on them

## Sizing

- [ ] Feature sizing audit (FR-1) run — three signals computed for every candidate (cross-layer spread / substrate-slice consumers / multi-cluster capability); tripped features either accepted via FR-2 cut proposal (substrate-cut / cluster-cut / read-vs-write-cut) or kept-as-one with FR-4 one-sentence justification recorded in `engagement-gate-runs.md`
- [ ] If reslice mode was used (`/forge-decompose --reslice`), the dry-run audit + precondition reports were reviewed before any `--apply` pass; FR-7.a preconditions honored for every applied feature
- [ ] Each feature spec is independently implementable in one agent run (rough heuristic: a single backend + frontend + tests cycle, not a multi-week epic)
- [ ] Features that don't fit the size heuristic are split or flagged for further decomposition

## Per-feature spec readiness

- [ ] Each stub feature spec follows `_TEMPLATE-spec.md`
- [ ] Each one is self-contained enough that an agent reading only that spec + the PRD can implement it

## Delivery Phases (optional — skip for projects under ~10 features)

- [ ] Delivery phases defined (count, titles, themes) — captured in `tracker.yaml` `delivery.phases` and mirrored in `features.md` `## Delivery Plan`
- [ ] Each phase has a stakeholder-facing theme (one sentence — what does this phase deliver?)
- [ ] Every in-scope feature is assigned a `delivery_phase` (or explicitly left `null` with reasoning in `notes`)
- [ ] Phase ordering respects the dependency graph — features in Phase N only depend on features in Phase ≤ N
- [ ] Exactly one phase is at `status: in-progress` at Gate-3 sign-off; the rest are `locked`; `current_phase` matches
- [ ] Each phase is independently demonstrable — sealing the phase produces something the team can show stakeholders
