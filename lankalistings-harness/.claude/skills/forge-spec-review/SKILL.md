---
name: forge-spec-review
phases: [engineering]
description: "Multi-pass review of a draft Forge feature spec with fix cycles, ending in a human approval gate that flips `Status: approved`. Use whenever a feature spec is at `Status: draft` or `in-review` and the user asks to review, self-review, or approve it. Feature specs only — for plans use `/forge-plan-review`."
---

# /forge-spec-review

Automated multi-pass feature-spec review with fix cycles. Replaces the manual review-fix-review-fix-review loop, enforcing structural independence on review (sub-agent runs in fresh context per pass) while keeping the human in the loop for final approval.

## How to Use

```
/forge-spec-review <spec-path>                          # interactive — human approves at convergence
/forge-spec-review <spec-path> --auto-approve-on-clean  # auto-flip if the verification pass returns zero Blockers + zero Importants
```

`<spec-path>` is the path to the spec file relative to the harness root, e.g. `.forge/specs/<feature>-spec.md`.

`--auto-approve-on-clean` is the conservative-auto-flow mode used by `/forge-deliver`. It bypasses step 4.5's human prompt **only when the spec is already pristine on the verification pass** — anything else still asks. Nits do NOT block auto-approval; they're recorded in the final report for follow-up. See step 4.5 below for the exact gate. Auto-flow orchestrators that want to keep a human spec gate simply do NOT pass the flag.

If invoked without a `<spec-path>`, print usage and exit.

## When to Use

- A feature spec has just been drafted and is at `Status: draft`.
- A feature spec is at `Status: in-review` (mid-cycle) and needs to continue.
- The user says "review the X spec", "self-review the spec", "is this spec ready to approve?", or otherwise points at a spec and asks for review.

## When NOT to Use

- **Foundation specs** (`.forge/specs/foundation/**`) — those went through the manual foundation review pre-Gate 3 and are governed by `.forge/plans/foundation/README.md` instead. The skill aborts if pointed at a foundation spec.
- **Plans** — use `/forge-plan-review` instead.
- **PRDs** — use `/forge-prd-check` for engagement-level PRD audit.
- **Pre-spec-body gap-checking only** — use `/forge-gap-check` directly. This skill's `spec-reviewer` sub-agent absorbs the same input-side-gap audit as Pass 1's dimension §12, but if the spec body isn't drafted yet, standalone gap-check is the right tool (it writes to `## Open Questions` for the spec author to address before drafting).

## Process

### 1. Validate inputs

```bash
SPEC_PATH="<spec-path>"     # as passed by the user
[ -f "$SPEC_PATH" ] || {
  echo "Spec not found: $SPEC_PATH"
  exit 1
}

# Foundation-spec exclusion — feature specs only.
case "$SPEC_PATH" in
  *.forge/specs/foundation/*)
    cat <<MSG
$SPEC_PATH is a foundation spec.
/forge-spec-review covers feature specs only. Foundation specs went through
the manual foundation review pre-Gate 3 (see .forge/plans/foundation/README.md).
Aborting.
MSG
    exit 1
    ;;
esac

STATUS=$(grep -m1 '^> Status:' "$SPEC_PATH" | sed 's/.*Status: //; s/[[:space:]]*$//')
case "$STATUS" in
  approved)
    echo "Spec is already at Status: approved. Re-running review on an approved spec is a no-op. Aborting."
    exit 0
    ;;
  draft|in-review)
    : # continue
    ;;
  *)
    echo "Spec status '$STATUS' is unrecognized (expected: draft | in-review). Aborting."
    exit 1
    ;;
esac
```

### 2. Resolve context

Locate the supporting paths for the sub-agent:

- `PRD_PATH` = `<harness-root>/.forge/project-prd.md` (live contract — always passed)
- `PRD_SIGNALS_PATH` = `<harness-root>/.forge/project-prd-signals.md` (live OQs — pass if the file exists; empty string otherwise)
- `TEMPLATE_PATH` = `<harness-root>/.forge/specs/_TEMPLATE-spec.md`
- `ARCHITECTURE_PATH` = `<harness-root>/.forge/design/architecture.md`
- `CLAUDEMD_PATH` = `<harness-root>/.claude/CLAUDE.md`

Confirm `PRD_PATH`, `TEMPLATE_PATH`, `ARCHITECTURE_PATH`, `CLAUDEMD_PATH` exist; if any is missing, abort with a clear message. `PRD_SIGNALS_PATH` is optional — its absence is a valid pre-trichotomy / no-OQs-yet state.

**`project-prd-history.md` is NOT passed to the reviewer.** It's the audit trail; loading it re-introduces the bloat the trichotomy split eliminated. The reviewer's brief explicitly omits it.

Resolve the feature ID for the spec under review (used by `spec-reviewer` to selectively load `project-prd-signals.md` rows whose `Blocks` column contains this ID — see the sub-agent definition for the filter shape):

```bash
# Look up the feature ID from .forge/tracker.yaml by matching the spec path.
# Use yq if available; otherwise grep the file manually.
FEATURE_ID=$(yq -r ".features | to_entries | map(select(.value.spec == \"$SPEC_PATH\")) | .[0].key" \
  "<harness-root>/.forge/tracker.yaml" 2>/dev/null || true)
```

If `FEATURE_ID` resolves to empty / null, that's a recoverable state — pass the empty string to the sub-agent and let it flag the missing tracker entry as a Blocker in dimension §1 / §2 (the reviewer will also skip signals loading in that case). Don't abort the skill — the audit itself is still valuable.

Parse the spec's `## Constraints and Dependencies` section for references to other specs (lines matching `.forge/specs/.*-spec.md`). Build `DEPENDENT_SPECS` as the comma-separated list of absolute paths. Empty list is fine — most specs depend on nothing.

Capture the lead's name from `git config user.name` for use later when filling the `Reviewed by:` line.

### 3. Run review cycle

Maintain:
- `pass_counter` (starts at 1)
- `all_findings[]` — append each pass's findings for the final report
- `applied_fixes[]` — track what was changed each pass, to feed forward as `previous_findings` in the next pass

Loop:

#### a. Invoke the `spec-reviewer` sub-agent via the Task tool

Dispatch prompt template:

```
Review this Forge feature spec. Inputs:

- spec_path: <abs SPEC_PATH>
- feature_id: <FEATURE_ID, or empty if the spec is not yet in tracker>
- prd_path: <abs PRD_PATH>
- prd_signals_path: <abs PRD_SIGNALS_PATH, or empty if the file doesn't exist>
- template_path: <abs TEMPLATE_PATH>
- architecture_path: <abs ARCHITECTURE_PATH>
- claudemd_path: <abs CLAUDEMD_PATH>
- dependent_specs: <comma-separated abs paths, or empty>
- pass_number: <pass_counter>
- previous_findings: <on pass ≥ 2 only — short summary of prior-pass findings + what fixes were applied>

Read the files. For project-prd-signals.md, load ONLY the rows whose Blocks column
contains feature_id (filter per your sub-agent definition). Do NOT load
project-prd-history.md — it is audit trail, not input. Audit per the dimensions
in your sub-agent definition. Produce the Verdict + Findings table.
```

Wait for the sub-agent's response. Parse:
- The verdict line (`pass` | `pass-with-nits` | `fail-with-issues`)
- The Blockers, Important, Nits tables

Append to `all_findings[]`.

#### b. Convergence check

- **Verdict `pass` or `pass-with-nits`** → exit loop. Proceed to step 4.
- **`pass_counter ≥ 2` AND verdict `fail-with-issues`** → exit loop with verdict `manual-rewrite-needed`. Pass 1 audited, fixes were applied, Pass 2 verified — and issues still remain. Tell the human the spec likely needs structural rewrite, not further patches. Skip the auto-approval step (4.5); skill exits. (When `--auto-approve-on-clean` was passed, this still does NOT auto-approve — `manual-rewrite-needed` never auto-flips.)
- **Verdict `fail-with-issues`** (and `pass_counter < 2`) → apply fixes (next sub-step), increment `pass_counter`, loop back.

#### c. Apply fixes

For each Blocker and Important finding, apply the suggested fix using Edit (or MultiEdit when multiple edits are clustered).

Be judicious — the sub-agent's "Suggested fix" is directional:
- If the suggestion is a wording change ("change X to Y"), apply directly.
- If the suggestion is "rewrite the rationale to mention X", craft the rewrite with judgment. The sub-agent doesn't see the conversation history; you (main session) have full context — use it.
- If the suggestion targets a section the spec is missing entirely (e.g., empty Out-of-Scope), draft the section content based on what's already in the spec + PRD context.
- If two suggestions conflict (rare but possible), prefer the more conservative; document in `applied_fixes[]`.

**Skip Nits.** They're surfaced for human review at convergence.

After applying fixes, record `applied_fixes[pass_counter] = "Fixed B1, B2, I1, I3"` (or similar). Increment `pass_counter`. Loop back to (a).

### 4. Convergence reporting

Once the loop exits with `pass` or `pass-with-nits`, present the summary to the user. Format:

```markdown
## Spec review converged after <N> pass(es)

| Pass | Blockers | Important | Nits | Action |
|---|---|---|---|---|
| 1 | 3 | 6 | 4 | Fixed B1–B3, I1–I6 |
| 2 | 0 | 0 | 2 | Converged |

## Remaining nits (your call at approval)

| # | Where | Issue | Suggested fix |
|---|---|---|---|
| N1 | … | … | … |
| N2 | … | … | … |
```

If zero nits remain, omit the Remaining nits table — say "No remaining nits."

Input-side findings (from Pass 1's dimension §12 audit) appear inline in the Pass 1 Blockers/Important rows tagged `(input-gap)`; no separate section.

### 4.5. Approval gate

**If `--auto-approve-on-clean` was passed AND the final converging pass returned zero Blockers AND zero Importants** (Nits permitted), skip the human prompt and proceed directly to step 5 (option 1 — approve as-is). The Reviewed-via annotation in step 5b is amended to mark the auto-approval (see 5b for exact text). Any remaining nits are listed in the final report so the human can land them in a follow-up.

**Otherwise** present the options below. **Without the flag, never auto-approve** — even a Pass 1 `pass` (zero of everything) asks the human.

```
What would you like to do?

1. **Approve as-is** — flip status to `approved`. Nits left unaddressed.
2. **Apply nits then approve** — fix the listed nits, then flip status. (Skip if no nits.)
3. **Reject** — keep at Status: draft. Skill exits without changes; you can revise manually or re-run later.
```

**Rendering rule when zero nits remain:** omit option 2 from the prompt and renumber Reject as option 2 — present only two options. The "Apply nits then approve" path has nothing to do.

Wait for the human to pick.

The auto-approve gate is intentionally strict: **zero Blockers + zero Importants only**. If `--auto-approve-on-clean` was passed but the final pass surfaced an Important, fall back to the human prompt — auto-approve never decides on Important findings. This is the conservative-auto-flow's contract (per `/forge-deliver` docs).

### 5. On approval (option 1 or 2)

#### a. Apply remaining nits if option 2

For each Nit, apply the suggested fix via Edit.

#### b. Flip spec header (atomic — single Edit with annotation + status)

Use Edit to replace the existing header block with the approved version, **including the `Reviewed-via:` annotation in the same edit**. The `guard-spec-approval.sh` PreToolUse hook gates the `Status: approved` transition: it requires the `Reviewed-via: /forge-spec-review` line to be present in either the new edit content or the existing file. Bundling annotation + status flip into ONE Edit is the canonical idempotent path:

```markdown
> Status: approved
> Author: <existing author>
> Reviewed by: <lead-name> (lead)
> Date: <drafted-date> (drafted) · <today> (approved after <N>-pass review)
> Reviewed-via: /forge-spec-review (<N>-pass, <today>)
```

**Auto-approve variant** (when step 4.5's `--auto-approve-on-clean` gate triggered):

```markdown
> Status: approved
> Author: <existing author>
> Reviewed by: <lead-name> (auto-approved on clean Pass <N>)
> Date: <drafted-date> (drafted) · <today> (auto-approved after <N>-pass review)
> Reviewed-via: /forge-spec-review (auto-approved, <N>-pass, <today>)
```

The `Reviewed-via:` annotation still matches `guard-spec-approval.sh`'s regex (`/forge-spec-review`), so the hook lets the edit through. The `(auto-approved, …)` suffix is the audit trail — anyone reading the spec or grep'ing the tracker can distinguish human-approved from auto-approved specs.

Where:
- `<lead-name>` = `git config user.name`
- `<drafted-date>` = preserve from existing header (parse the existing Date line — usually `YYYY-MM-DD` only)
- `<today>` = current date in `YYYY-MM-DD` form
- `<N>` = pass count

**Without the `Reviewed-via:` line, `guard-spec-approval.sh` will block the Edit and the skill will fail at this step.** The line is the evidence the hook checks for. The skill writes it; manual approvals trying to skip the cycle don't have it and get blocked.

#### c. Update tracker

Open `.forge/tracker.yaml`. Locate the entry whose `spec` field matches the spec path under `features.<id>` (feature specs only — this skill never operates on foundation slices, so the foundation map is not searched).

Update:
- `status: spec` → `status: plan`
- `last_updated: "<today>"`
- `notes: "<refresh — note the spec was approved today, summarize key locked decisions / FR-NFR counts, mention pass count>"`

Bump the global top-level `last_updated` to `"<today>T<HH:MM:00>"` using the current local time.

Use `yq` if available, otherwise plain Edit on the YAML.

If the spec path is not found under `features.<id>`, abort with: *"Spec path `$SPEC_PATH` not found in `tracker.yaml` `features.<id>`. Either the tracker is out of sync (run `/forge-decompose` if Gate 3 hasn't created the entry yet) or this is a non-tracker spec — surface to the human and stop."*

#### d. Final report

```
## Spec approved

- Spec: `<SPEC_PATH>` at `Status: approved`, reviewed by <lead-name>
- Tracker: feature `<id>` at `status: plan`, last_updated `<today>`
- <N> review pass(es) total; <X> Blockers + <Y> Important fixed; <Z> Nits <addressed | left>

Working tree shows the changes uncommitted. Commit + PR per the standard
workflow (e.g. `docs/<feature>-spec-approved` branch).

Next: plan authoring for `<feature>` can begin. Run /forge-plan-review
once the plan is drafted.
```

### 6. On rejection (option 3)

```
## Spec rejected, kept at Status: draft

Captured findings:
<print the all_findings[] summary table again>

Re-run /forge-spec-review when ready, or rewrite manually if the issues are
structural. The spec file was modified during the cycle — revert with
`git checkout -- <spec-path>` if you want a clean slate.
```

The skill exits without flipping status or touching the tracker.

## Notes

- **Idempotent.** Running on an already-approved spec aborts cleanly. Running on `in-review` continues from there. The skill only flips status on explicit human approval.
- **Max 2 passes.** Pass 1 audits (including input-side gaps as dimension §12); main session applies fixes; Pass 2 verifies. If Pass 2 still returns `fail-with-issues`, the skill exits with `manual-rewrite-needed` — escalates to human judgment rather than continuing to iterate. The cap reflects what each pass actually buys: Pass 1 carries unique signal (the audit), Pass 2 carries unique signal (verify the fixes); Pass 3+ would be diminishing-returns cascade-detection and is better handled by the human at that point.
- **Auto-approval is opt-in.** Without `--auto-approve-on-clean`, the human is always asked — even on a Pass 1 `pass`. With the flag, only zero-Blockers + zero-Importants converging passes auto-approve; everything else still asks (Important findings never auto-decide). Auto-approved specs are explicitly marked in the `Reviewed-via:` annotation (`(auto-approved, …)` suffix) so the audit trail distinguishes them. `/forge-deliver` keeps its human spec gate by simply not passing the flag.
- **Sub-agent independence.** Each pass invokes a fresh `spec-reviewer` context. The reviewer doesn't see the main session's history — it judges the spec as written, which is the point of the structural-independence design.
- **Nit threshold.** The sub-agent is instructed to keep nits to ≤3 per pass. Floods of nits signal the reviewer is being too pedantic — re-tune `spec-reviewer.md` if observed across multiple runs.
- **Input-side gaps audited inside Pass 1.** The `spec-reviewer` sub-agent's dimension §12 covers the same input-side audit `/forge-gap-check` performs standalone (PRD vagueness, conflicting meeting notes, draft-status dependencies). Bundling avoids the double-ingestion cost of a separate Pass 0 sub-agent invocation — sub-agent boundaries erase context, so chaining costs full file re-ingestion on each fresh-context call. Input-gap findings land in Pass 1's Blocker/Important tables tagged `(input-gap)`; standalone `/forge-gap-check` remains the right tool for pre-spec-body use (writes `B-N`/`W-N` to `## Open Questions`).
- **Working tree assumption.** Skill operates on the working copy of the spec + tracker. Changes are uncommitted at exit; user commits + PRs separately. Skill does NOT push or open PRs on its own.
- **Foundation-spec exemption.** Hard-coded check at step 1 + sub-agent step. Foundation specs are out of scope by design — they go through the manual review cycle alongside the foundation plans.
- **Enforced via `guard-spec-approval.sh`.** A PreToolUse hook (`.claude/hooks/guard-spec-approval.sh`) blocks any Edit/Write/MultiEdit that flips a feature spec's `Status:` to `approved` unless the file carries a `Reviewed-via: /forge-spec-review` annotation. The hook exempts `.forge/specs/foundation/**` so foundation specs already approved are not retroactively blocked. The skill writes this annotation in the same atomic Edit as the status flip (per step 5b), so the hook lets the skill's own approval pass through. Manual or shortcut approvals that bypass the skill cycle will fail the hook.
