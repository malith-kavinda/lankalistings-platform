# LankaListings — Architecture Readiness Checklist

> Used by `/forge-arch-probe` (Gate 2). Customize per project — drop items that don't apply, add items that do.
>
> Each item is **pass / pass-with-spike / fail / N/A**. Failures are logged with a *specific missing decision*, not "we should think about this more."

## Tech stack viability

- [ ] Stack chosen and justified against PRD constraints
- [ ] Mandatory tech constraints from the PRD honored
- [ ] Stack capability gaps named (e.g., "we'll need a separate service for X because the primary stack can't handle it")

## Foundational architecture decisions

> **Reference convention.** Both the project constitution (`.claude/CLAUDE.md` § Architecture Decisions) and the PRD (`.forge/project-prd.md` `## Architecture Decisions`) carry their own decision tables. When a checklist item below cites a decision number, it must say which table it points to. Use `Constitution Decision #N` for the constitution and `PRD Architecture Decision #N` for the PRD. The two tables are independent — `Constitution Decision #11` and `PRD Architecture Decision #11` are different decisions.

- [ ] Data model approach decided (relational / document / graph / hybrid)
- [ ] Auth model decided (provider, session/token, RBAC vs. ABAC)
- [ ] Tenancy model decided where applicable (shared / siloed / hybrid)
- [ ] Sync vs. async boundaries identified
- [ ] Integration patterns for external systems decided (push / pull / event)

## Build feasibility

- [ ] Highest-risk PRD requirements identified (the things that, if they don't work, sink the engagement)
- [ ] At least a paper sketch of how each high-risk requirement will be implemented
- [ ] Spike work scoped for any item where a paper sketch isn't enough

## Resource and timeline reality

- [ ] Team capacity vs. PRD scope sanity-checked
- [ ] Skills gap identified (e.g., "we've never done X — buy time or buy expertise")
- [ ] Critical-path estimate against the agreed delivery window

## In-house-first audit

- [ ] External dependencies enumerated
- [ ] Each external dependency justified vs. an in-house alternative
- [ ] Rationale recorded for each external choice

## Security & supply chain

- [ ] Dependency-vulnerability CI gate planned in the Build & CI foundation slice — tool chosen (one tool applied uniformly across every repo), CVSS threshold + how it's made configurable, and per-repo `dependency-check-suppressions.xml` governance (justification + expiry per entry). See framework.md §4.10.

## Honesty

- [ ] Architectural unknowns / TBDs explicitly listed
- [ ] Reversible vs. irreversible decisions distinguished
- [ ] Decisions deferred to later phases noted explicitly with trigger conditions ("revisit when X happens")
