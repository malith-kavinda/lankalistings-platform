# /forge-arch-probe

## What This Command Does

Walks `.forge/design/architecture.md` through the **architecture-readiness checklist**, confirming the foundational architecture decisions are made (or explicitly deferred with a trigger) before decomposition begins. This is **Gate 2** of the pre-implementation gates.

Interactive guide — surfaces missing decisions for the engagement architect to resolve.

## How to Use

```
/forge-arch-probe             # full run — writes audit, updates status, records risks/spikes
/forge-arch-probe dry-run     # walk the checklist and print findings, write nothing
```

**Always announce the mode at the start of the run:**

- Full mode: `🔒 Gate 2 — full mode. Audit will be appended to .forge/engagement-gate-runs.md, tracker.yaml will be updated, PRD Gate Status table will be refreshed.`
- Dry-run mode: `🧪 Gate 2 — dry-run mode. No files will be modified.`

## Process

1. **Parse arguments** — detect `dry-run`. Announce mode.

2. **Gate 1 precondition check.** Read `.forge/tracker.yaml` and look at `setup.project_prd.status`.
   - If status is `gate1-passed` or `gate1-passed-with-risks` → proceed silently.
   - Otherwise (status is `not-started`, `in-progress`, `in-review`, or `gate1-failed`) → print a warning and ask the architect:
     > Gate 1 (PRD readiness) hasn't passed yet (status: `<status>`). Architecture work can run in parallel with PRD authoring (see **When to Run** below), but the default expectation is that Gate 1 passes first. Continue anyway?
   - If `tracker.yaml` is missing or the field is missing, print "couldn't verify Gate 1 status — please confirm before continuing" and ask. Don't crash.
   - Don't hard-block in any case — there are legitimate parallel-authoring runs. Warn-and-confirm.

3. **Read the inputs.** The walk needs more than just `architecture.md` — settled decisions are spread across several files. Read each one and note its role:

   | File | Role |
   |------|------|
   | `.forge/project-prd.md` | What the system has to do — constraints, NFRs, scope, high-risk requirements |
   | `.forge/project-prd-signals.md` (if present) | Live open questions — load so the walk can flag any architectural OQ that's still unresolved. The history file is NOT loaded — it's audit trail, not input. |
   | `.forge/design/architecture.md` | The artifact being walked |
   | `.forge/checklists/architecture-checklist.md` | The checklist for this project |
   | `.claude/CLAUDE.md` "Architecture Decisions (DO NOT REVERSE)" table | Constitutional source of truth for settled decisions |
   | `.forge/design/README.md` | Ownership boundaries (what belongs in `architecture.md` vs. repo-level docs) |
   | `.forge/design/ui/` (if present) | UI/design system decisions that shape frontend architecture |
   | `<backend-repo>/docs/data-model.md` (if present) | Data model details that the architecture references |
   | `<frontend-repo>/docs/style-spec.md` (if present) | Design tokens and patterns the frontend architecture depends on |

   > **Substitute** `<backend-repo>` and `<frontend-repo>` with the relative path from `.forge/` to each repo's docs directory (e.g., `../acme-be/docs/...`, `../acme-fe/docs/...`). The exact depth depends on the workspace layout — whether the harness sits at the workspace root or one level down — so verify the path resolves before relying on it.

   For files marked "if present," check for existence first. If absent, note "skipped — not yet present" in the findings and proceed. Repo-level docs frequently don't exist yet during early-engagement Gate 2 runs.

   **If `.forge/checklists/architecture-checklist.md` still contains placeholder text (e.g., `# [Project Name]`)**, print a warning that the checklist hasn't been calibrated for this project. Don't block — Gate 2 still runs against the generic checklist.

4. **Sync-check.** Before walking the checklist, identify any architecture content that contradicts the PRD or `CLAUDE.md` "Architecture Decisions (DO NOT REVERSE)" table. For each contradiction, surface it in the findings *without picking a winner*:

   > **Contradiction:** Per `CLAUDE.md` decision #N: `<statement>`. Per `architecture.md` `<section>`: `<statement>`. Reconcile.

   This is a **soft check** — don't block the walk. Per-item findings during the walk should reference these contradictions as gap statements where applicable (e.g., "auth model item fails because architecture.md describes 3 roles while PRD describes 6"). The architect decides during the verdict step which side is correct and how to reconcile.

5. **Walk each checklist item.** For each item, classify:
   - **Pass** — decision is captured (in `architecture.md`, or in `CLAUDE.md` "DO NOT REVERSE" table — cross-references count).
   - **Pass with spike** — decision deferred but with explicit spike work scoped (id, description, trigger).
   - **Fail** — log a specific missing decision or gap statement. If a sync-check contradiction applies, reference it.
   - **N/A** — explicitly note why.

6. **Summarize findings.** Counts of pass / pass-with-spike / fail / N/A, plus the contradictions list from step 4 and the per-item specifics.

7. **Ask the developer for the verdict** at the run level: `pass` / `pass-with-risks` / `pass-with-spikes` / `fail`.
   - `pass-with-risks` — items failed but the architect accepts the gap as a risk to be tracked.
   - `pass-with-spikes` — items deferred with explicit spike work scoped.
   - Both can apply (run can be `pass-with-risks-and-spikes`-shaped — capture both lists below).
   - Per-item verdicts (`pass / pass-with-spike / fail / N/A`) are not the same as the run-level verdict. Keep the distinction clear.

8. **For each accepted risk**, ask: id (e.g., `R-ARCH-001`), owner, brief reasoning. Where the risk maps to a specific checklist failure, suggest including `(checklist: <item-name>)` in the description so the audit traces back.

9. **For each scoped spike**, ask: id (e.g., `SP-ARCH-001`), description, trigger ("revisit when X").

10. **Capture architectural open questions surfaced by the walk.** Architecture decisions that the team can't make yet (typically because a discovery item or product question is unresolved) are tracked as OQs in `.forge/project-prd-signals.md`, not as risks and not in the PRD body. For each surfaced OQ append a row:

    ```
    | OQ-N | §Architecture / §<sub-area> | <topic> | <question> | ⏳ open | <owner, default architect> | <feature IDs if blocked, else —> |
    ```

    Determine `N` by counting existing `| OQ-` rows in `project-prd-signals.md` and adding 1. If `project-prd-signals.md` doesn't exist yet, create it from the template shape (header + `## Open Questions` + schema table) before writing. The `guard-prd-shape.sh` hook will block any attempt to add OQ rows to `project-prd.md` directly.

    Skip this step if no new OQs were surfaced.

11. **(skipped in dry-run)** Write outputs per the next section.

## Output

In **full mode**, three writes happen atomically at the end of a run:

| Where | What | Format |
|-------|------|--------|
| `.forge/engagement-gate-runs.md` | Append `## Gate 2 Run N` block at the bottom of the file | Narrative — date, runner, outcome, full per-item findings, risks/spikes recorded |
| `.forge/project-prd.md` `## Gate Status` | Update the Gate 2 row | Status + Last Run date + Risks/Spikes counts + link to the audit entry |
| `.forge/tracker.yaml` `setup.architecture` | Update `status`, `last_gate_run`; append `accepted_risks` and `spikes` entries | Structured YAML |

In **dry-run mode**, nothing is written — the summary is only printed to the session.

Architecture decisions discovered or refined during the walk should be applied to `architecture.md` interactively as part of the conversation — that's content, not audit.

## When to Run

- After Gate 1 passes. The work behind this gate runs **in parallel** with PRD authoring when Forge writes the PRD — architecture decisions get made along the way; this gate is a formal checkpoint at the end. When the client provides the PRD, this gate runs **sequentially** after Gate 1. Either way, the gate itself is the same — only the cadence of the underlying work changes.
- Before decomposition begins.
- When architecturally-relevant PRD changes happen.

## Related

- Gate 1: `/forge-prd-check` — must pass first.
- Gate 3: `/forge-decompose` — runs after this passes.
- Audit storage principle: see `.claude/rules/tracker.md` "Gate Audit Protocol" section.
- PRD trichotomy + OQ lifecycle: `.claude/rules/prd.md` (architectural OQs surfaced by this gate go to `project-prd-signals.md`, not into the PRD body).
