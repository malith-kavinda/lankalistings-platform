---
description: PRD trichotomy + open-question lifecycle — which content lives in which of the three PRD files, the three-step OQ resolution procedure, the revisions convention, the hook contract. Loads when reading or editing any project-prd*.md file.
globs: .forge/project-prd*.md
---

# PRD Trichotomy & Open-Question Lifecycle

The project PRD is split across **three files** with distinct content classes. This split exists because mixing live contract, live signals, and audit trail into one document bloated every read of the PRD and made selective context-loading impossible on the consumer side (`spec-reviewer`, etc.). The trichotomy mirrors the harness's existing live-vs-frozen separation pattern (`features.md` live vs PRD `§Feature Decomposition` frozen).

## The Trichotomy

| File | Class | Contents | When read |
|------|-------|----------|-----------|
| [`project-prd.md`](../../.forge/project-prd.md) | **Live contract** | Problem, domain, scope, in-scope features, NFRs, constraints, **§Risks**, success criteria. The frozen-at-Gate-1 statement of what we are building. | Always — full body — by anyone reading the PRD. |
| [`project-prd-signals.md`](../../.forge/project-prd-signals.md) | **Live signals** | Open and partial open questions only (`⏳ open`, `◐ partial`). Each row anchored to a PRD section and (optionally) to feature IDs it blocks. | Selectively — `spec-reviewer` loads only rows whose `Blocks` column contains the feature ID under review. Humans browse this file when answering or grooming OQs. |
| [`project-prd-history.md`](../../.forge/project-prd-history.md) | **Audit trail** | Resolved open questions (`## Resolved Open Questions`) and PRD revisions (`## Revisions`). | Rarely — humans tracing a past decision. Not auto-loaded by any skill or sub-agent. |

**Risks stay in `project-prd.md`** (not in signals). Risks are part of the engagement contract, the section is small, and per-spec risk injection is already handled by `tracker.yaml setup.*` + the `inject-relevant-risks-spikes.sh` hook. Only OQs and Revisions move.

## The OQ Resolution Procedure

When an open question in `project-prd-signals.md` is answered, **three writes happen together**:

1. **Fold the answer into the PRD body.** Find the relevant section in `project-prd.md` (use the OQ row's `Section` column as the anchor) and update the body so the decision is part of the live contract. If the resolution is an architectural decision, add it as a new row to `.claude/CLAUDE.md § Architecture Decisions (DO NOT REVERSE)` instead.
2. **Move the OQ row from signals to history.** Delete the row from `project-prd-signals.md` `## Open Questions`. Append a row to `project-prd-history.md` `## Resolved Open Questions` preserving the original question and recording the resolution. The `Resolved in` column holds a pointer of the form `Rev N: see §X` or `Rev N: see AD #Y`.
3. **Append a revision entry.** Add a `### Rev N — YYYY-MM-DD` block to `project-prd-history.md` `## Revisions` describing what changed and naming the OQ (`Resolves: OQ-7`).

Do not skip step 3 — the `Resolved in: Rev N` pointer in step 2 must point at a real revision entry. The three writes together preserve the audit trail and let a future reader trace any current PRD statement back to the question it answered.

## Conventions

- **New open questions** (from `forge-prd-author`, `/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose`, or mid-engagement) → write to `project-prd-signals.md`. **Never** add an `## Open Questions` or `## Risks and Open Questions` heading to `project-prd.md`. The shape-guard hook will block it.
- **New PRD revisions** (any meaningful change to the PRD body after first sign-off, per the standard revisions convention) → append a `### Rev N` block to `project-prd-history.md` `## Revisions`. **Never** add a `## Revisions` heading or `### Rev N` row to `project-prd.md`. The shape-guard hook will block it.
- **Risks** → `project-prd.md § Risks` (per the trichotomy table above). The per-spec risk-context injection mechanism (`tracker.yaml setup.*` + `inject-relevant-risks-spikes.sh`) is unchanged.
- **The `Blocks` column on signal rows** is load-bearing — `spec-reviewer` filters signals by feature ID using it. When recording an OQ that blocks one or more features, list the feature IDs comma-separated. If the OQ is engagement-level and doesn't block any specific feature, use `—`.

## Hook Contract

The `guard-prd-shape.sh` PreToolUse hook (Edit | Write | MultiEdit) inspects writes targeting `project-prd.md`. It exits non-zero with a stderr pointer message when the proposed new content tries to insert:

- An `^| OQ-\d+ |` row → pointer to `project-prd-signals.md`.
- An `^## Open Questions$` or `^## Risks and Open Questions$` heading → same pointer.
- An `^## Revisions$` heading or `^### Rev \d+` row → pointer to `project-prd-history.md`.

The hook is path-scoped — it only fires on `project-prd.md` (the contract file). Edits to `project-prd-signals.md` and `project-prd-history.md` are not inspected; those files are where this content belongs.

**If blocked, follow the resolution procedure above** — do not try to work around the hook. The error message points at the correct destination file and at this rule.

The hook fails open on missing `jq`, paths that don't match, and malformed stdin — same posture as every other harness hook (`guard-spec-approval.sh`, `guard-plan-approval.sh`). It will not block a session because of its own malfunction.

## Why this rule exists

Without enforcement, projects rot back into the inline pattern under deadline pressure — a single engagement can accumulate dozens of inline open questions over a few weeks, and once the majority are answered (`✅`) they become pure bookkeeping bloating every PRD read. The shape-guard hook + this rule are the same enforcement triangle already used for spec/plan approvals (skill writes the right shape, hook enforces it, annotation/structure is the evidence). Without both halves, the discipline doesn't survive contact with a busy engagement.

See `docs/methodology/framework.md § 4. Required Artifacts` for the doctrine-level statement and `docs/migrations/v0.24-prd-trichotomy.md` for the procedure when migrating an existing pre-trichotomy PRD.
