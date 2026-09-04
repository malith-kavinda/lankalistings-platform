#!/usr/bin/env bash
#
# PreToolUse hook — Edit/Write/MultiEdit matcher.
# Blocks transitions to "Status: approved" on plan files
# (.forge/plans/**/*-plan.md) unless the file carries a
# "Reviewed-via: /forge-plan-review" annotation in either the new
# edit content or the existing file on disk.
#
# Why: enforces that /forge-plan-review has produced the convergence
# annotation before any human (or future Claude session) flips a plan
# from draft/in-review to approved. Manual or shortcut approvals that
# skip the review cycle are blocked.
#
# Contract:
#   - Exit 0 to allow. Exit 2 to block (stderr is shown to Claude).
#   - Fails open (exit 0) for non-plan-file edits, non-status-flipping
#     edits, and unrecognized tools.

set -u

# Read stdin once — multiple jq invocations against stdin would each consume
# it, leaving every call after the first with empty input.
input=$(cat)

tool=$(echo "$input" | jq -r '.tool_name // ""')
file=$(echo "$input" | jq -r '.tool_input.file_path // ""')
[ -z "$file" ] && exit 0

# Only fire on writes to plan files (.forge/plans/.../*-plan.md).
case "$file" in
  *"/.forge/plans/"*-plan.md) ;;
  *) exit 0 ;;
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

if echo "$new_content" | grep -qE 'Reviewed-via:[[:space:]]*/forge-plan-review' || \
   echo "$existing_content" | grep -qE 'Reviewed-via:[[:space:]]*/forge-plan-review'; then
  exit 0
fi

cat >&2 <<MSG
Blocked by Forge harness: cannot flip plan status to "approved" without
review evidence.

The /forge-plan-review skill must have run on this plan and written a
"> Reviewed-via: /forge-plan-review (<N>-pass, <YYYY-MM-DD>)" line into
the header. Neither the current edit nor the existing file at:

  $file

contains this annotation.

Resolve by:
  1. Run /forge-plan-review <plan-path>
  2. Walk the cycle to convergence
  3. Approve via the skill's prompt — it'll write the annotation and
     flip status atomically in a single Edit, which this hook lets
     through.

If you're certain the skill has already run and the annotation is
present, double-check spelling: it must literally be
"Reviewed-via: /forge-plan-review" (case-sensitive).
MSG
exit 2
