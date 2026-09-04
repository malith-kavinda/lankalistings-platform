---
name: forge-plan-review
phases: [foundation, engineering]
description: "Single-pass review of a draft Forge plan by the `plan-reviewer` sub-agent, ending in a human approval gate that flips `Status: approved`. Use whenever a plan is at `Status: draft` or `in-review` and the user asks to review, self-review, or approve it. Plans only — for spec review, use `/forge-spec-review`."
---

# /forge-plan-review

Automated single-pass plan review. The `plan-reviewer` sub-agent audits in a fresh context; the main session applies Blocker/Important fixes; the human approves at the gate. No verification re-audit — the human approval gate is the check that applied fixes are sound. Enforcing structural independence on review (the sub-agent runs in a fresh context) while keeping the human in the loop for final approval.

## How to Use

```
/forge-plan-review <plan-path>                          # interactive — human approves at convergence
/forge-plan-review <plan-path> --auto-approve-on-clean  # auto-flip if the audit pass returns zero Blockers + zero Importants
```

`<plan-path>` is the path to the plan file relative to the harness root, e.g. `.forge/plans/foundation/003-be-data-layer-plan.md`.

`--auto-approve-on-clean` is the conservative-auto-flow mode used by `/forge-deliver`. It bypasses step 4.5's human prompt **only when the audit pass returns zero Blockers + zero Importants (no fixes needed)** — anything else, including a pass where fixes were applied, still asks. Nits do NOT block auto-approval; they're recorded in the final report for follow-up. See step 4.5 below for the exact gate.

If invoked without a `<plan-path>`, print usage and exit.

## When to Use

- A plan has just been drafted and is at `Status: draft`.
- A plan is at `Status: in-review` (mid-cycle) and needs to continue.
- The user says "review the F-XXX plan", "self-review the plan", "let's check plan X", "is this plan ready to approve?", or otherwise points at a plan and asks for review.

If the user wants spec review (not plan review), suggest `/forge-spec-review` — this skill is plan-only.

## Process

### 1. Validate inputs

```bash
PLAN_PATH="<plan-path>"      # as passed by the user
[ -f "$PLAN_PATH" ] || {
  echo "Plan not found: $PLAN_PATH"
  exit 1
}

STATUS=$(grep -m1 '^> Status:' "$PLAN_PATH" | sed 's/.*Status: //; s/[[:space:]]*$//')
case "$STATUS" in
  approved)
    echo "Plan is already at Status: approved. Re-running review on an approved plan is a no-op. Aborting."
    exit 0
    ;;
  draft|in-review)
    : # continue
    ;;
  *)
    echo "Plan status '$STATUS' is unrecognized (expected: draft | in-review). Aborting."
    exit 1
    ;;
esac
```

### 2. Resolve context

Parse the plan header for the spec reference. The `> Spec:` line points at the spec path relative to the harness root.

```bash
SPEC_REL=$(grep -m1 '^> Spec:' "$PLAN_PATH" | sed 's/.*Spec: //; s/`//g; s/[[:space:]]*$//')
SPEC_PATH="$(realpath "$SPEC_REL")"
[ -f "$SPEC_PATH" ] || {
  echo "Spec referenced in plan header not found: $SPEC_REL. Plan header may be malformed."
  exit 1
}
```

Identify relevant repo CLAUDE.md paths by grepping the plan body for repo CLAUDE.md references (e.g. `<backend-repo>/.claude/CLAUDE.md`, `<frontend-repo>/.claude/CLAUDE.md`). Substitute with the engagement's actual workspace paths. Resolve to absolute paths.

Detect whether the plan under review is a **sub-WI plan** (used for test-tier cross-reference — feeds the reviewer's TC-2 tier-match and TC-3 AC-coverage checks in audit dimension §10):

```bash
# A plan is a sub-WI plan if its header contains a "> Key Workitem:" line
KEY_WI_LINE=$(grep -m1 '^> Key Workitem:' "$PLAN_PATH")
if [ -n "$KEY_WI_LINE" ]; then
  # Extract the path — strip backticks and leading/trailing whitespace
  KEY_WI_REL=$(echo "$KEY_WI_LINE" | sed 's/.*Key Workitem: //; s/`//g; s/[[:space:]]*$//')
  KEY_WI_PATH="$(realpath "$KEY_WI_REL" 2>/dev/null)"
  [ -f "$KEY_WI_PATH" ] || KEY_WI_PATH=""  # clear if path doesn't resolve
fi
# KEY_WI_PATH is now set (sub-WI plan) or empty (single-plan / Key Workitem itself)
```

Compute the **`ship_unit`** for the feature this plan belongs to — `wave` or `feature`. This gates the reviewer's audit dimension §11 (Wave Vertical-Shipping Audit), which runs only when `ship_unit == "wave"`. Read the engagement default from `.forge/tracker.yaml` `delivery.ship_unit`, then apply the per-feature override `features[<id>].ship_unit` if present (immutable once set). Default to `feature` when absent.

```bash
# Engagement default (wave | feature), then per-feature override if the plan
# maps to a known feature id. Falls back to `feature` if the field is absent.
SHIP_UNIT=$(yq -r '.delivery.ship_unit // "feature"' .forge/tracker.yaml 2>/dev/null || echo feature)
# If the plan's feature id is known (e.g. from the Decomposition Plan / Key
# Workitem header), prefer features[<id>].ship_unit when set:
#   yq -r '.features["<feature-id>"].ship_unit // ""' .forge/tracker.yaml
# Use that value if non-empty; otherwise keep the engagement default.
[ -z "$SHIP_UNIT" ] && SHIP_UNIT=feature
```

Capture the lead's name from `git config user.name` for use later when filling the `Reviewed by:` line.

### 3. Run the review

This is a **single audit pass** — no verification re-audit and no loop. The sub-agent audits once; the main session applies Blocker/Important fixes; the human approval gate (step 4.5) is the check that the fixes are sound.

#### a. Invoke the `plan-reviewer` sub-agent via the Task tool

Dispatch prompt template:

```
Review this Forge plan. Inputs:

- plan_path: <abs PLAN_PATH>
- spec_path: <abs SPEC_PATH>
- repo_claudemd_paths: <comma-separated abs paths>
- pass_number: 1
- key_workitem_path: <abs KEY_WI_PATH, or omit this line if KEY_WI_PATH is empty>
- ship_unit: <SHIP_UNIT — "wave" or "feature">

Read the files. Audit per the dimensions in your sub-agent definition. Produce the Verdict + Findings table.
```

The `key_workitem_path` (when present) lets the reviewer run TC-2 (tier matches Key Workitem assignment) and TC-3 (every owned AC has a mapped test) against the Decomposition Plan's `## Test Strategy Map`. The `ship_unit` value gates audit dimension §11 — when it is `wave`, the reviewer re-validates the plan against the Decomposition Plan's `## Wave Ship Plan` (verify-WI awareness, vertical-slice shipping). The reviewer's §12 design-conformance checks (DC-1 … DC-8, including DC-6/7/8 — prototype anatomy transcription, primitive conformance, reference-screen structural transcription) run for any user-visible WI **only if the project has a design reference**; they are skipped for backend-only WIs and for projects with no design system.

Wait for the sub-agent's response. Parse:
- The verdict line (`pass` | `pass-with-nits` | `fail-with-issues`)
- The Blockers, Important, Nits tables

Record the findings for the final report (`all_findings`).

#### b. Apply fixes

If the verdict is `fail-with-issues`, apply each Blocker and Important fix using Edit (or MultiEdit when multiple edits are clustered). If the verdict is `pass` or `pass-with-nits`, there is nothing to apply — proceed to step 4.

Be judicious — the sub-agent's "Suggested fix" is directional:
- If the suggestion is a wording change ("change X to Y"), apply directly.
- If the suggestion is "rewrite the rationale to mention X", craft the rewrite with judgment. The sub-agent doesn't see the conversation history; you (main session) have full context — use it.
- If two suggestions conflict (rare but possible), prefer the more conservative; document in the report.

**Skip Nits.** They're surfaced for human review at the approval gate.

Record which findings were fixed (`applied_fixes = "Fixed B1, B2, I1, I3"`) for the final report, then proceed to step 4. Because there is no second pass, the applied fixes are **not** re-audited — the human approval gate is where any surviving issue is caught.

### 4. Review reporting

After the audit pass (and any fixes), present the summary to the user. Format:

```markdown
## Plan review complete (single pass)

| Blockers | Important | Nits | Action |
|---|---|---|---|
| 3 | 6 | 4 | Fixed B1–B3, I1–I6; 4 nits left for your call |

## Remaining nits (your call at approval)

| # | Where | Issue | Suggested fix |
|---|---|---|---|
| N1 | … | … | … |
| N2 | … | … | … |
```

If zero nits remain, omit the Remaining nits table — say "No remaining nits."

### 4.5. Approval gate

**If `--auto-approve-on-clean` was passed AND the audit pass returned zero Blockers AND zero Importants** (Nits permitted, no fixes were needed), skip the human prompt and proceed directly to step 5 (option 1 — approve as-is). The Reviewed-via annotation in step 5b is amended to mark the auto-approval (see 5b for exact text). Any remaining nits are listed in the final report so the human can land them in a follow-up.

**Otherwise** present three options:

```
What would you like to do?

1. **Approve as-is** — flip status to `approved`. Nits left unaddressed.
2. **Apply nits then approve** — fix the listed nits, then flip status. (Skip if no nits.)
3. **Reject** — keep at Status: draft. Skill exits without changes; you can revise manually or re-run later.
```

**Rendering rule when zero nits remain:** omit option 2 from the prompt and renumber Reject as option 2 — present only two options. The "Apply nits then approve" path has nothing to do.

Wait for the human to pick.

The auto-approve gate is intentionally strict: **zero Blockers + zero Importants only**. If `--auto-approve-on-clean` was passed but the audit surfaced any Blocker or Important — even one that was then fixed — fall back to the human prompt. With no verification re-audit, a human confirms the applied fixes are sound before approval. This is the conservative-auto-flow's contract (per `/forge-deliver` docs).

### 5. On approval (option 1 or 2)

#### a. Apply remaining nits if option 2

For each Nit, apply the suggested fix via Edit.

#### b. Flip plan header (atomic — single Edit with annotation + status)

Use Edit to replace the existing header block with the approved version, **including the `Reviewed-via:` annotation in the same edit**. The `guard-plan-approval.sh` PreToolUse hook gates the `Status: approved` transition: it requires the `Reviewed-via: /forge-plan-review` line to be present in either the new edit content or the existing file. Bundling annotation + status flip into ONE Edit is the canonical idempotent path:

```markdown
> Status: approved
> Reviewed by: <lead-name> (lead)
> Date: <drafted-date> (drafted) · <today> (approved after single-pass review)
> Reviewed-via: /forge-plan-review (single-pass, <today>)
```

**Auto-approve variant** (when step 4.5's `--auto-approve-on-clean` gate triggered):

```markdown
> Status: approved
> Reviewed by: <lead-name> (auto-approved on clean audit pass)
> Date: <drafted-date> (drafted) · <today> (auto-approved after single-pass review)
> Reviewed-via: /forge-plan-review (auto-approved, single-pass, <today>)
```

The `Reviewed-via:` annotation still matches `guard-plan-approval.sh`'s regex (`/forge-plan-review`), so the hook lets the edit through. The `(auto-approved, …)` suffix is the audit trail — anyone reading the plan or grep'ing the tracker can distinguish human-approved from auto-approved plans.

Where:
- `<lead-name>` = `git config user.name`
- `<drafted-date>` = preserve from existing header (parse the existing Date line — usually `YYYY-MM-DD` only)
- `<today>` = current date in `YYYY-MM-DD` form

**Without the `Reviewed-via:` line, `guard-plan-approval.sh` will block the Edit and the skill will fail at this step.** The line is the evidence the hook checks for. The skill writes it; manual approvals trying to skip the cycle don't have it and get blocked.

#### c. Update tracker

Open `.forge/tracker.yaml`. Locate the entry whose `plan` field matches the plan path. **Two locations to check** — the skill is plan-type-agnostic:

| Plan type | Tracker location | Status enum |
|---|---|---|
| Foundation plan (`.forge/plans/foundation/<id>-plan.md`) | `setup.foundation.slices[]` | `not-started \| spec \| plan \| dev \| review \| done` |
| Feature plan (`.forge/plans/<id>-plan.md`, post-Gate 3) | `features.<id>` | `backlog \| spec \| plan \| dev \| review \| ship \| done` |

In both cases, update:

- `status: plan` → `status: dev`
- `last_updated: "<today>"`
- `notes: "<refresh — note the plan was approved today, summarize key locked decisions, mention pass count>"`

Bump the global top-level `last_updated` to `"<today>T<HH:MM:00>"` using the current local time.

Use `yq` if available, otherwise plain Edit on the YAML.

#### d. Final report

```
## Plan approved

- Plan: `<PLAN_PATH>` at `Status: approved`, reviewed by <lead-name>
- Tracker: slice `<ID>` at `status: dev`, last_updated `<today>`
- Single review pass; <X> Blockers + <Y> Important fixed; <Z> Nits <addressed | left>

Working tree shows the changes uncommitted. Commit + PR per the standard
workflow (e.g. `docs/<id>-plan-approved` branch).

Next: <slice ID>'s implementation can start now if upstream deps are merged,
or wait for <upstream slice> per the spec's Slice dependencies section.
```

### 6. On rejection (option 3)

```
## Plan rejected, kept at Status: draft

Captured findings:
<print the all_findings[] summary table again>

Re-run /forge-plan-review when ready, or rewrite manually if the issues are
structural. The plan file was modified during the cycle — revert with
`git checkout -- <plan-path>` if you want a clean slate.
```

The skill exits without flipping status or touching the tracker.

## Notes

- **Idempotent.** Running on an already-approved plan aborts cleanly. Running on `in-review` continues from there. The skill only flips status on explicit human approval.
- **Single pass.** The sub-agent audits once; the main session applies Blocker/Important fixes; the human approval gate is the check that the fixes are sound. There is no verification re-audit and no `manual-rewrite-needed` outcome — if the audit surfaces deep structural problems, the human rejects at the gate (option 3) and the plan is rewritten before re-running. Trade-off: lower token spend and faster turnaround; the cost is that applied fixes are not machine-verified, so the human gate carries more weight.
- **Auto-approval is opt-in.** Without `--auto-approve-on-clean`, the human is always asked — even on a Pass 1 `pass`. With the flag, only zero-Blockers + zero-Importants converging passes auto-approve; everything else still asks. Auto-approved plans are explicitly marked in the `Reviewed-via:` annotation (`(auto-approved, …)` suffix) so the audit trail distinguishes them.
- **Wave-mode audit is gated by `ship_unit`.** The reviewer's §11 Wave Vertical-Shipping Audit runs only when the dispatch passes `ship_unit: wave` (engagement default from `delivery.ship_unit`, overridden by `features[<id>].ship_unit`). For `ship_unit: feature` plans the reviewer skips §11 entirely. The skill computes the value; the reviewer never reads the tracker itself (it has no Edit/Write/yq surface).
- **Sub-WI plans get extra checks.** When the plan header carries `> Key Workitem:` and `> WI ID:`, the skill resolves and passes `key_workitem_path` so the reviewer can run TC-2 (tier matches the Decomposition Plan's Test Strategy Map) and TC-3 (every owned AC has a mapped test). Plans without those header fields are reviewed as single-plan specs.
- **Sub-agent independence.** The audit pass invokes a fresh `plan-reviewer` context. The reviewer doesn't see the main session's history — it judges the plan as written, which is the point of the structural-independence design.
- **Nit threshold.** The sub-agent is instructed to keep nits to ≤3 per pass. Floods of nits signal the reviewer is being too pedantic — re-tune `plan-reviewer.md` if observed across multiple runs.
- **Working tree assumption.** Skill operates on the working copy of the plan + tracker. Changes are uncommitted at exit; user commits + PRs separately. Skill does NOT push or open PRs on its own.
- **Read-only fallback.** If invoked on a plan whose spec is missing or unreadable, abort with a clear message rather than running review on incomplete context.
- **Enforced via `guard-plan-approval.sh`.** A PreToolUse hook (`.claude/hooks/guard-plan-approval.sh`) blocks any Edit/Write/MultiEdit that flips a plan's `Status:` to `approved` unless the file carries a `Reviewed-via: /forge-plan-review` annotation. The skill writes this annotation in the same atomic Edit as the status flip (per step 5b), so the hook lets the skill's own approval pass through. **Manual or shortcut approvals that bypass the skill cycle will fail the hook** — the only way to get a plan to `Status: approved` is via this skill (or by manually adding the `Reviewed-via:` line, which counts as honor-system bypass and would be caught at PR review).
