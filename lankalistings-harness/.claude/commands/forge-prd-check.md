# /forge-prd-check

Walks the project PRD against the **PRD-readiness checklist** before the team commits to delivering against it. This is **Gate 1** of the pre-implementation gates.

Leadership compares runs of this command across time, so the visible output must be stable: the same PRD on two different runs should produce the same shape. The locked artifact is the findings table — render it, render the verdict prompt, and stop. No preamble before the mode line. No prose between the table and the verdict prompt. No closing summary after.

## How to Use

```
/forge-prd-check              # full run — writes audit, updates status, records risks
/forge-prd-check dry-run      # walk the checklist and print findings, write nothing
```

## Process

### 1. Announce mode

Print exactly one of these lines, followed by a blank line:

- Full: `🔒 Gate 1 — full mode. Audit will be appended to .forge/engagement-gate-runs.md, tracker.yaml will be updated, PRD Gate Status table will be refreshed.`
- Dry-run: `🧪 Gate 1 — dry-run mode. No files will be modified.`

### 2. Read inputs

Read `.forge/project-prd.md`, `.forge/project-prd-signals.md` (live OQs — load if present; absent is fine on a brand-new project before any OQs have surfaced), and `.forge/checklists/prd-readiness-checklist.md`. If `project-prd.md` or the checklist is missing, stop and surface the missing path. Do not proceed on partial inputs.

The signals file is loaded so that checklist items asking "are open questions captured and owned?" can be evaluated against the live OQ inventory rather than against the PRD body (which no longer carries `## Open Questions`). The history file (`project-prd-history.md`) is **not** loaded — it's audit trail, not input to this gate.

### 3. Classify each checklist item

Walk items in the order they appear in the checklist. Assign exactly one status — there is no partial / borderline / mixed status:

- **✅ Pass** — the item is *clearly and substantially* addressed.
- **❌ Fail** — missing, superficially addressed, or partially addressed. Partial = fail. This rule exists because borderline judgments cause cross-run drift; collapsing them into fail-with-a-specific-gap-statement keeps the assessment stable.
- **➖ N/A** — explicitly not applicable (checklist annotates it N/A, or out of project scope). Note why in the Reasoning column.

### 4. Render findings table

Output a single Markdown table, items in checklist order, exact columns:

| Section | Item | Status | Reasoning |
|---|---|---|---|

Conventions:
- Status cell holds ✅, ❌, or ➖ — nothing else.
- The Reasoning cell is filled for **every** row — developers reviewing the gate need to see why each item received its status, not just the failures. The reasoning depends on the status:
  - For ✅: state what in the PRD addresses the item. Reference the PRD section name when it helps (e.g., "§Scope > In Scope enumerates the V1 modules"). Keep it brief — one sentence, two at most.
  - For ❌: name the *specific* gap — what's missing or what would close it. Not "weak in this area"; e.g., "no Success Criteria section per CLAUDE.md §19" or "cardinality not stated for OrderItem↔Order/Product".
  - For ➖: state the N/A reason briefly (e.g., "Checklist marks N/A — all integrations deferred for this phase").
- The table is the complete findings output. Do not write a counts line, a status-breakdown list, or any other summary block — the status column already encodes the distribution. Anyone who wants a tally can scan the column.

### 5. Advisory section (conditional)

Include an Advisory section *only* if you observed a contradiction between two project documents (e.g., PRD vs `CLAUDE.md` vs `architecture.md`) that does not fit a checklist row. Other cross-artifact observations belong in the Reasoning column of the relevant row, not here.

Format:

```
## Advisory

- **<short label>:** <specific drift, with file references>
```

One bullet per drift item. If no contradictions, omit the section entirely.

### 6. Prompt for verdict

Output exactly this single line:

```
Verdict? (`pass` / `pass-with-risks` / `fail`)
```

Wait for the developer's reply. Do not add a header, an explanation of the options, or a closing line.

### 6.5. Capture new open questions surfaced by the audit

If the walk surfaced specific gaps that should be tracked as open questions (not as accepted risks — risks are addressed in step 7), append them to `.forge/project-prd-signals.md` under `## Open Questions`. **Never** add them to `.forge/project-prd.md` — the `guard-prd-shape.sh` hook will block that.

For each new OQ:

```
| OQ-N | <PRD section the gap maps to> | <topic> | <question> | ⏳ open | <owner, default lead> | <feature IDs if any are blocked, else —> |
```

Determine `N` by counting existing `| OQ-` rows in `project-prd-signals.md` and adding 1. If `project-prd-signals.md` doesn't exist yet, create it from the template shape (header + `## Open Questions` + schema table) before writing.

If no new OQs were surfaced by this run, skip this step.

### 7. Collect risks (only if verdict is `pass-with-risks`)

Send exactly this prompt:

```
List the accepted risks, one per line, format: `<id> | <owner> | <reasoning>`
Example: `R-PRD-001 | <owner> | will be added before sprint kickoff`
```

Parse the reply line by line. Echo back as a confirmation table:

| ID | Owner | Reasoning |
|---|---|---|

If the developer wants to revise, re-prompt and re-render the confirmation table.

### 8. Write outputs (full mode only)

In dry-run, stop after step 6 (or step 7 if risks were collected). In full mode, perform the three writes below, in order. If any write fails, surface the error and stop — do not produce a partial audit.

## Output (full mode only)

### Write 1 — `.forge/engagement-gate-runs.md`

Append a new block at the bottom of the file (newest at bottom — the file's header states the same convention). Determine `N` by counting existing `## Gate 1 Run` blocks and adding 1 (counter is per-gate, not global); headings inside HTML comments don't count. If the seeded example comment block (`<!-- Example entry shape … -->`) is still present, delete it as part of this write.

`<runner>` defaults to `git config user.name`. If unavailable, ask the developer once.
`<trigger>` is a one-line reason supplied by the developer. Ask if not given.

Template (table copied verbatim from step 4):

```markdown
## Gate 1 Run N — YYYY-MM-DD (<runner>)

**Mode:** full
**Outcome:** <pass | pass-with-risks | fail>
**Trigger:** <one-line reason>

| Section | Item | Status | Reasoning |
|---|---|---|---|
| ... |
```

If outcome is `pass-with-risks`, append:

```markdown
**Risks accepted:**

| ID | Owner | Reasoning |
|---|---|---|
| R-PRD-001 | <owner> | <reasoning> |
```

### Write 2 — `.forge/project-prd.md` `## Gate Status`

Update the Gate 1 row:

| Cell | Value |
|---|---|
| Status | `✅ passed` / `⚠️ passed-with-risks` / `❌ failed` |
| Last Run | ISO `YYYY-MM-DD` |
| Risks / Spikes | `<N> risks` if any, else `—` |
| Detail | `[Run N](engagement-gate-runs.md#gate-1-run-N--YYYY-MM-DD-<runner-slug>)` — GitHub-style heading anchor (lowercased, spaces → `-`, parentheses stripped) |

### Write 3 — `.forge/tracker.yaml` `setup.project_prd`

Set fields:

- `status`: `gate1-passed` / `gate1-passed-with-risks` / `gate1-failed`
- `last_gate_run`: ISO date
- `accepted_risks`: append (do not overwrite) entries using the schema in the file's example block:
  ```yaml
  - id: R-PRD-001
    description: "<gap statement, copied verbatim from the table>"
    accepted_by: "<owner>"
    accepted_date: "YYYY-MM-DD"
    notes: "<reasoning>"
  ```

## When to Run

- At the end of discovery, before committing to delivery.
- After significant PRD revisions (drift check).
- At phase boundaries.

## Related

- Gate 2: `/forge-arch-probe` — runs after this passes.
- Gate 3: `/forge-decompose` — runs after Gate 2 passes.
- Audit storage principle: see `.claude/rules/tracker.md` "Gate Audit Protocol" section.
- PRD trichotomy + OQ lifecycle: `.claude/rules/prd.md` (open questions surfaced by this gate go to `project-prd-signals.md`, not into the PRD body).
