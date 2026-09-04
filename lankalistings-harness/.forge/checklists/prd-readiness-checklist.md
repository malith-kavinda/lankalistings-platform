# LankaListings — PRD Readiness Checklist

> Used by `/forge-prd-check` (Gate 1). Customize per project — drop items that don't apply, add items that do.
>
> Each item is **pass / fail / N/A**. Failures are logged with a *specific gap statement*, not a vague "weak in this area."

## Scope and boundaries

- [ ] In-scope features explicitly listed
- [ ] Out-of-scope features explicitly listed — including **negative-space exclusions** (features a comparable system in this market would normally include but this project will **not build**); each item carries a one-line **won't-build reason**, distinct from a deferral reason
- [ ] Deferred-to-later-phase items separated from out-of-scope — deferred items appear in a **distinct list or column**, each tagged with a **target phase or trigger condition** (not just a free-text reason that could be read either way)
- [ ] Phasing / sequencing intent stated — **ordered priorities** (P0/P1/P2 or equivalent) with **dependencies** between items
- [ ] Reference-system classification complete — for every major capability in the reference system, an explicit **Replicate / Redesign / Defer / Discard** decision is recorded (per project constitution §4). N/A for projects without a reference system.

## Domain model

- [ ] Key entities named
- [ ] Entity relationships described (1:1, 1:N, N:N)
- [ ] Entity lifecycle states named where applicable (e.g. application: draft → submitted → approved → rejected)
- [ ] Glossary for client-specific terminology

## Users and access

- [ ] User roles enumerated
- [ ] Per-role capabilities described — for each role, what they can **Create, Read, Update, Delete, Approve, Configure** is enumerated **per resource type** (e.g. Student, Application, User, Org). A narrative paragraph that mentions some verbs does not satisfy this item; an explicit per-role × per-resource breakdown does.
- [ ] Multi-tenancy / org-hierarchy model described where applicable

## Functional surface

- [ ] Each in-scope feature has at least a one-paragraph description
- [ ] User journeys identified for headline flows — at least one **end-to-end path** named for each of the **top-3 features** (or all P0 features if fewer than 3)
- [ ] Integration points with external systems named

## Non-functional

- [ ] Performance expectations (at least order-of-magnitude)
- [ ] Security / compliance requirements named
- [ ] Accessibility commitments named
- [ ] Observability / audit requirements named

## Constraints

- [ ] Tech stack constraints (mandatory vs. preferred vs. open)
- [ ] Regulatory constraints
- [ ] Deployment / hosting constraints

## Honesty

- [ ] Open questions / TBDs explicitly listed (not silently missing)
- [ ] Known risks / unknowns logged
- [ ] Success criteria stated — how we'll know we delivered the right thing
- [ ] Input sources / provenance recorded — every major requirement traces back to a **screenshot, meeting note, discovery file, or research source** (per project constitution §19)
