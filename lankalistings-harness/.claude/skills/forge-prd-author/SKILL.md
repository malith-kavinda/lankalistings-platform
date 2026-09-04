---
name: forge-prd-author
phases: [discovery]
description: "Author the project PRD by structured interview against `.forge/discovery/` inputs. Auto-triggers when `.forge/project-prd.md` is missing or still a stub at session start, after `/forge-prd-check` (Gate 1) fails with major gaps, or when the user says 'write the PRD' / 'interview me for the PRD'. Engagement-level only — feature-spec gaps are forge-gap-check."
---

# forge-prd-author

Engagement-level PRD authoring assistant. Runs a five-round structured interview to author or fill in `.forge/project-prd.md` based on discovery inputs and user answers. Writes section-by-section with user approval. Decoupled from Gate 1 — produces a draft PRD; `/forge-prd-check` (Gate 1) audits whatever exists.

## When to use

- `.forge/project-prd.md` is missing, or contains only template scaffolding (no body content under any of the 13 content sections)
- `/forge-prd-check` (Gate 1) just failed with two or more ❌ items in the same major PRD section
- User says "write the PRD" / "interview me for the PRD" / "let's start the PRD"

## When NOT to use

- The PRD already has substantive content and Gate 1 isn't failing — run `/forge-prd-check` instead and act on its findings
- Per-feature spec authoring — `forge-gap-check` is the right tool there
- Updating an approved PRD with a small change — use the PRD's `## Revisions` section directly

## Procedure

### 1. Detect PRD state

Read `.forge/project-prd.md`. Determine state:

- **Missing** — file does not exist → mode = **fresh**
- **Stub** — file exists but for each of the 12 content sections (Problem Statement, Industry/Domain Context, Business Specifics, Scope and Boundaries, Domain Model, Users and Access, Functional Surface, Non-functional Requirements, Constraints, Input Sources, Risks, Success Criteria), check if any non-comment, non-blank line exists between its heading and the next heading. If zero sections have body content → **stub** → mode = **fresh**. (Open Questions and Revisions are NOT in the PRD body — they live in `project-prd-signals.md` and `project-prd-history.md` respectively. See `.claude/rules/prd.md`.)
- **Partial** — at least one but not all of the 12 sections has body content → ask:
  ```
  PRD exists at .forge/project-prd.md (N of 12 sections have body content).
  Choose mode:
    [a] Re-interview from scratch (creates a revision entry, replaces sections)
    [b] Fill missing or thin sections only (keeps existing content)
    [c] Cancel
  ```

### 2. Inventory discovery inputs

List the files in `.forge/discovery/` and note which exist:

- `meeting-notes/*.md`
- `feature-inventory.md`
- `screenshots/` directory contents (paths only — do not read images)
- `flows/` directory contents (paths only)

Print a one-line summary:

> *Discovery inputs found: 3 meeting notes, feature inventory (12 features classified), 2 flow diagrams.*

If no discovery directory exists, surface to user: *"No `.forge/discovery/` found. Interview will rely on user answers only. Continue?"*

### 3. Run the rounds

The interview runs five rounds. Each round targets 1–3 PRD sections.

| Round | Targets | Typical questions |
|-------|---------|-------------------|
| **1 — Problem & domain** | Problem Statement; Industry/Domain Context; Business Specifics | What is being built and for whom? What industry? Org structure? Current pains / legacy systems being replaced? |
| **2 — Scope & boundaries** | Scope and Boundaries (V1 / out of scope / deferred) | What's in V1? What's explicitly out? What's deferred and why? Are there features in `feature-inventory.md` not yet classified? |
| **3 — Domain & users** | Domain Model; Users and Access | Key entities and their relationships? Lifecycle states? Roles and capabilities? Multi-tenancy / org-hierarchy expectations? |
| **4 — Functional surface** | Functional Surface; Input Sources | Per-feature description (one paragraph each); user journeys for the most critical flows; integration points with external systems. Link each described feature to its discovery sources. |
| **5 — NFR, constraints, risks, success** | Non-functional Requirements; Constraints; Risks (in PRD body); Open Questions (to `project-prd-signals.md` — see §6.1); Success Criteria | Performance numbers? Security stance? Accessibility? Tech stack constraints? Regulatory? Known unknowns with owners? How will we know we delivered the right thing? |

### 4. Per-round flow

```
1. Print round header + 2-line context summary of what's about to be drafted
2. State which discovery inputs are being used as context
3. Ask question 1 (one at a time, multiple choice when possible)
4. User answers
5. Ask question 2
   ...
6. Draft the section(s) for this round
7. Print draft inline in chat
8. Prompt: "Approve this section, revise, or skip for now? [a/r/s]"
9. On 'a' → write to .forge/project-prd.md
10. On 'r' → ask what to change, redraft, loop back to step 7
11. On 's' → write a TBD placeholder and move to next round
```

### 5. Skipped sections

If a section is skipped during a round, write this placeholder to the PRD:

```
> _TBD — skipped during forge-prd-author interview on YYYY-MM-DD. Run forge-prd-author again to fill in._
```

This makes Gate 1 immediately surface the gap on next run, which is the right behavior.

### 6. Where open questions go

**OQs do not go in the PRD body.** When an open question surfaces during any round (most commonly Round 5, but possible anytime), write the row to `.forge/project-prd-signals.md` under `## Open Questions`, not to `.forge/project-prd.md`. Schema:

```
| OQ-N | <Section> | <Topic> | <Question> | ⏳ open | <Owner> | <Blocks-feature-IDs or —> |
```

- `<Section>` = the PRD body section the question anchors to (e.g. `§Domain Model`, `§Functional Surface > [Feature X]`).
- `<Blocks>` = comma-separated feature IDs the OQ blocks if any are known yet at PRD-authoring time (often empty pre-Gate-3 → use `—`).

`.forge/project-prd.md` is the live contract — adding an OQ row or an `## Open Questions` heading there will be blocked by the `guard-prd-shape.sh` PreToolUse hook. See `.claude/rules/prd.md` for the full trichotomy and lifecycle.

If `.forge/project-prd-signals.md` doesn't exist yet (rare — bootstrap creates it), create it from the template shape: a single `## Open Questions` heading followed by the schema table.

### 7. Revision-mode behavior

When mode = `re-interview`, append a revision entry to **`.forge/project-prd-history.md`** under `## Revisions` (NOT to the PRD body):

```markdown
### Rev N — YYYY-MM-DD
- **Changed:** Re-authored via forge-prd-author skill. Sections replaced: <list>.
- **Why:** <reason given by user; default "Gate 1 failed with major gaps">
- **Approved by:** <user name from git config>
```

Determine `N` by counting existing `### Rev ` entries in `project-prd-history.md` and adding 1.

When mode = `fill-missing`, no revision entry is added — filling gaps in a draft PRD isn't a revision in the contractual sense, it is still original authoring.

### 8. Closing

When all rounds complete (or user signals done):

1. Confirm `.forge/project-prd.md` (and, if any OQs were surfaced, `.forge/project-prd-signals.md`) is saved
2. Suggest next step: *"Run `/forge-prd-check` to verify the PRD against the readiness checklist."*
3. Do not run Gate 1 automatically — that is the user's call

## What this skill deliberately doesn't do

- **No domain-specific prompt scaffolding.** Round structure is generic; domain context comes from reading `meeting-notes/` and `feature-inventory.md`.
- **No dry-run mode.** Drafting is interactive by nature; the user reviews each section before it is written.
- **No automatic Gate 1 invocation after completion.** The user runs `/forge-prd-check` separately.
- **No overwriting a non-empty PRD without explicit user confirmation.**

## Edge cases

| Case | Behavior |
|------|----------|
| Discovery directory missing entirely | Surface: *"No `.forge/discovery/` found. Interview will rely on user answers only. Continue?"* |
| User pastes a long answer mid-round | Accept verbatim; don't reformat unless drafting the section |
| User asks a meta-question ("what does this section mean?") | Answer briefly using the relevant `Project PRD` required-sections definition; don't derail the round |
| Mode = `fill-missing` but every section has body content | Print: *"PRD has all 12 sections filled. Run `/forge-prd-check` to audit quality. Skill exiting."* |
| User force-quits mid-round | Already-approved sections persist; in-flight section is not partially written |
| Existing PRD has inline `## Open Questions` or `## Revisions` headings (legacy / not-yet-migrated) | Do not edit those sections from this skill. Surface to the user: *"This PRD predates the trichotomy split (.claude/rules/prd.md). Run the migration playbook in docs/methodology/migration-playbook.md before re-authoring, or proceed with new OQs going to project-prd-signals.md (legacy inline OQs stay in the body until migration)."* |
| Existing `.forge/project-prd-history.md` has prior `### Rev N` entries | New revision entry appends at the bottom; do not touch existing entries |

## Related

- PRD template (live contract): `.forge/project-prd.md`
- PRD signals (live OQs — where this skill writes open questions): `.forge/project-prd-signals.md`
- PRD history (audit trail — where this skill writes revision entries): `.forge/project-prd-history.md`
- PRD trichotomy + OQ lifecycle: `.claude/rules/prd.md`
- Gate 1 (audits the output of this skill): `/forge-prd-check`
- Per-feature counterpart (gaps in feature specs): `forge-gap-check`
- Required PRD sections: see `.forge/checklists/prd-readiness-checklist.md` (the Gate-1 audit checklist enumerates every required section)
