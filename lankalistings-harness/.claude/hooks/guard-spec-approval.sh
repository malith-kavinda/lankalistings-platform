#!/usr/bin/env bash
#
# PreToolUse hook — Edit/Write/MultiEdit matcher.
# Blocks transitions to "Status: approved" on FEATURE spec files
# (.forge/specs/<x>-spec.md, top-level — NOT foundation/) unless the
# file carries a "Reviewed-via: /forge-spec-review" annotation in
# either the new edit content or the existing file on disk.
#
# Foundation specs (.forge/specs/foundation/**) are exempt by design
# — they go through the manual foundation review cycle alongside the
# foundation plans. Retroactively blocking them would invalidate
# already-approved work.
#
# Why: enforces that /forge-spec-review has produced the convergence
# annotation before any human (or future Claude session) flips a feature
# spec from draft/in-review to approved. Manual or shortcut approvals
# that skip the review cycle are blocked.
#
# Contract:
#   - Exit 0 to allow. Exit 2 to block (stderr is shown to Claude).
#   - Fails open (exit 0) for non-spec-file edits, non-status-flipping
#     edits, foundation specs, and unrecognized tools.

set -u

# Read stdin once — multiple jq invocations against stdin would each consume
# it, leaving every call after the first with empty input.
input=$(cat)

tool=$(echo "$input" | jq -r '.tool_name // ""')
file=$(echo "$input" | jq -r '.tool_input.file_path // ""')
[ -z "$file" ] && exit 0

# Only fire on writes to feature spec files (.forge/specs/<x>-spec.md, NOT foundation/).
case "$file" in
  *"/.forge/specs/foundation/"*)
    # Foundation specs are exempt — manual-review cycle predates this hook.
    exit 0
    ;;
  *"/.forge/specs/"*-spec.md) ;;
  *)
    exit 0
    ;;
esac

# Extract the new content depending on the tool.
case "$tool" in
  Edit)
    new_content=$(echo "$input" | jq -r '.tool_input.new_string // ""')
    ;;
  Write)
    new_content=$(echo "$input" | jq -r '.tool_input.content // ""')
    ;;
  MultiEdit)
    new_content=$(echo "$input" | jq -r '[.tool_input.edits[].new_string] | join("\n")')
    ;;
  *)
    exit 0
    ;;
esac

# Does the edit set "> Status: approved" anywhere in the new content?
if ! echo "$new_content" | grep -qE '^>[[:space:]]*Status:[[:space:]]*approved[[:space:]]*$'; then
  exit 0
fi

# Annotation acceptable from either the new edit OR the existing file.
existing_content=""
[ -f "$file" ] && existing_content=$(cat "$file")

if echo "$new_content" | grep -qE 'Reviewed-via:[[:space:]]*/forge-spec-review' || \
   echo "$existing_content" | grep -qE 'Reviewed-via:[[:space:]]*/forge-spec-review'; then
  exit 0
fi

cat >&2 <<MSG
Blocked by Forge harness: cannot flip feature spec status to "approved" without
review evidence.

The /forge-spec-review skill must have run on this spec and written a
"> Reviewed-via: /forge-spec-review (<N>-pass, <YYYY-MM-DD>)" line into
the header. Neither the current edit nor the existing file at:

  $file

contains this annotation.

Resolve by:
  1. Run /forge-spec-review <spec-path>
  2. Walk the cycle to convergence (Pass 1 audits including input-side gaps; Pass 2 verifies fixes — max 2 passes)
  3. Approve via the skill's prompt — it'll write the annotation and
     flip status atomically in a single Edit, which this hook lets
     through.

If you're certain the skill has already run and the annotation is
present, double-check spelling: it must literally be
"Reviewed-via: /forge-spec-review" (case-sensitive).

Foundation specs (.forge/specs/foundation/**) are exempt from this
hook — they were approved via the manual review cycle pre-Gate 3.
This hook only fires on feature specs at .forge/specs/<x>-spec.md.
MSG
exit 2
