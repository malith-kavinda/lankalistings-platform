#!/usr/bin/env bash
#
# PreToolUse hook — Edit | Write | MultiEdit matcher.
# Enforces the PRD trichotomy shape: blocks attempts to insert open-question
# rows or revision entries into the live PRD contract file (project-prd.md).
#
# Open questions belong in project-prd-signals.md; revisions belong in
# project-prd-history.md. See .claude/rules/prd.md for the full lifecycle.
#
# Fires only on tool calls targeting **/.forge/project-prd.md — the contract
# file. The two sidecars (project-prd-signals.md, project-prd-history.md) are
# never inspected; that's where this content is supposed to live.
#
# Contract:
#   - Exit 0 to allow. Exit 2 to block (stderr is shown to Claude).
#   - Fails open (exit 0) on missing jq, non-contract paths, unrecognized
#     tools, missing stdin, or any parse error. Same posture as every other
#     harness hook — never blocks a session because of its own malfunction.
#   - Inspects only the *new* content (Edit.new_string / Write.content /
#     MultiEdit.edits[].new_string). Existing inline OQs / revisions in a
#     not-yet-migrated PRD continue to work — the hook scans inserts, not
#     the whole document.

set -u

# --- self-test mode ---------------------------------------------------------
#
# Usage: ./guard-prd-shape.sh --self-test
#
# Exercises the pattern-matching offline by piping crafted stdin into the hook
# itself and asserting the exit code. Prints PASS / FAIL per case.
if [ "${1:-}" = "--self-test" ]; then
  SELF="$0"
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  PRD="$TMPDIR/.forge/project-prd.md"
  SIGNALS="$TMPDIR/.forge/project-prd-signals.md"
  HISTORY="$TMPDIR/.forge/project-prd-history.md"
  OTHER="$TMPDIR/some-other-file.md"
  mkdir -p "$TMPDIR/.forge"
  touch "$PRD" "$SIGNALS" "$HISTORY" "$OTHER"

  pass=0
  fail=0

  assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
      echo "PASS: $name (exit $actual)"
      pass=$((pass+1))
    else
      echo "FAIL: $name (expected exit $expected, got $actual)"
      fail=$((fail+1))
    fi
  }

  run_case() {
    local input="$1"
    echo "$input" | "$SELF" >/dev/null 2>&1
    echo $?
  }

  # Case 1: insert OQ row into PRD → block.
  i=$(jq -n --arg f "$PRD" --arg s '| OQ-1 | Domain | Roles | Are supervisors a distinct role? | ⏳ open | lead | F-AUTH |' \
    '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "OQ row inserted into PRD blocks" 2 "$(run_case "$i")"

  # Case 2: insert ## Open Questions heading into PRD → block.
  i=$(jq -n --arg f "$PRD" --arg s '## Open Questions
foo' '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "## Open Questions heading blocks" 2 "$(run_case "$i")"

  # Case 3: insert ## Risks and Open Questions heading into PRD → block.
  i=$(jq -n --arg f "$PRD" --arg s '## Risks and Open Questions
foo' '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "## Risks and Open Questions heading blocks" 2 "$(run_case "$i")"

  # Case 4: insert ## Revisions heading into PRD → block.
  i=$(jq -n --arg f "$PRD" --arg s '## Revisions
foo' '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "## Revisions heading blocks" 2 "$(run_case "$i")"

  # Case 5: insert ### Rev 5 row into PRD → block.
  i=$(jq -n --arg f "$PRD" --arg s '### Rev 5 — 2026-05-22
- Changed: foo' '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "### Rev N row blocks" 2 "$(run_case "$i")"

  # Case 6: insert OQ row via Write into PRD → block.
  i=$(jq -n --arg f "$PRD" --arg c $'## Risks\n\n| OQ-2 | x | y | z | ⏳ open | a | b |\n' \
    '{tool_name:"Write", tool_input:{file_path:$f, content:$c}}')
  assert_exit "Write with OQ row blocks" 2 "$(run_case "$i")"

  # Case 7: insert OQ row via MultiEdit → block.
  i=$(jq -n --arg f "$PRD" \
    '{tool_name:"MultiEdit", tool_input:{file_path:$f, edits:[{old_string:"a", new_string:"safe"},{old_string:"b", new_string:"| OQ-3 | s | t | u | ⏳ open | o | — |"}]}}')
  assert_exit "MultiEdit with OQ row in any edit blocks" 2 "$(run_case "$i")"

  # Case 8: benign edit to PRD body → allow.
  i=$(jq -n --arg f "$PRD" --arg s '## Success Criteria
- All v1 features ship by Q3.' '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "benign PRD edit allows" 0 "$(run_case "$i")"

  # Case 9: same OQ row inserted into project-prd-signals.md → allow (sidecar is where they live).
  i=$(jq -n --arg f "$SIGNALS" --arg s '| OQ-1 | Domain | Roles | Are supervisors distinct? | ⏳ open | lead | F-AUTH |' \
    '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "OQ row in signals file allows" 0 "$(run_case "$i")"

  # Case 10: ### Rev N inserted into project-prd-history.md → allow (sidecar is where they live).
  i=$(jq -n --arg f "$HISTORY" --arg s '### Rev 1 — 2026-05-22
- Changed: PRD split into trichotomy.' '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "### Rev N in history file allows" 0 "$(run_case "$i")"

  # Case 11: edit unrelated file → allow.
  i=$(jq -n --arg f "$OTHER" --arg s '| OQ-99 | anything goes here |' \
    '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "non-PRD file allows even OQ-like content" 0 "$(run_case "$i")"

  # Case 12: unrecognized tool → allow.
  i=$(jq -n --arg f "$PRD" '{tool_name:"Bash", tool_input:{command:"ls"}}')
  assert_exit "unrecognized tool allows" 0 "$(run_case "$i")"

  # Case 13: empty / malformed stdin → allow.
  echo "not json" | "$SELF" >/dev/null 2>&1
  assert_exit "malformed stdin allows" 0 "$?"

  # Case 14: missing file_path → allow.
  i='{"tool_name":"Edit","tool_input":{}}'
  assert_exit "missing file_path allows" 0 "$(run_case "$i")"

  # Case 15: PRD edit with ## Risks (slim risks section is allowed — risks stay in PRD per OQ-A).
  i=$(jq -n --arg f "$PRD" --arg s '## Risks

| R-1 | something | owner | open |' \
    '{tool_name:"Edit", tool_input:{file_path:$f, new_string:$s}}')
  assert_exit "## Risks (slim section, no OQs) allows" 0 "$(run_case "$i")"

  echo
  echo "Self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi
# --- end self-test ---------------------------------------------------------

# Read stdin once — multiple jq invocations against stdin would each consume
# it, leaving every call after the first with empty input.
input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

# jq is required for parsing. Fail open if missing.
command -v jq >/dev/null 2>&1 || exit 0

tool=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
file=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
[ -z "$file" ] && exit 0

# Only fire on the live contract file. Sidecars (signals + history) are where
# OQ rows and revisions are supposed to live — never inspect them.
case "$file" in
  *"/.forge/project-prd.md") ;;
  *) exit 0 ;;
esac

# Extract the new content depending on the tool.
case "$tool" in
  Edit)
    new_content=$(echo "$input" | jq -r '.tool_input.new_string // ""' 2>/dev/null || echo "")
    ;;
  Write)
    new_content=$(echo "$input" | jq -r '.tool_input.content // ""' 2>/dev/null || echo "")
    ;;
  MultiEdit)
    new_content=$(echo "$input" | jq -r '[.tool_input.edits[].new_string] | join("\n")' 2>/dev/null || echo "")
    ;;
  *)
    exit 0
    ;;
esac

# Pattern-match the three forbidden shapes. Any match → block.
oq_row_pat='^\| *OQ-[0-9]+ *\|'
oq_heading_pat='^## (Risks and )?Open Questions *$'
revisions_heading_pat='^## Revisions *$'
rev_row_pat='^### Rev [0-9]+'

violation=""
target=""

if echo "$new_content" | grep -qE "$oq_row_pat"; then
  violation="open-question row (| OQ-N | ...)"
  target="project-prd-signals.md"
elif echo "$new_content" | grep -qE "$oq_heading_pat"; then
  violation="\"## Open Questions\" / \"## Risks and Open Questions\" heading"
  target="project-prd-signals.md"
elif echo "$new_content" | grep -qE "$revisions_heading_pat"; then
  violation="\"## Revisions\" heading"
  target="project-prd-history.md"
elif echo "$new_content" | grep -qE "$rev_row_pat"; then
  violation="\"### Rev N\" revision entry"
  target="project-prd-history.md"
fi

[ -z "$violation" ] && exit 0

cat >&2 <<MSG
Blocked by Forge harness: PRD shape violation in $file

The edit tries to insert: $violation

This content does not belong in the live PRD contract file. It belongs in:

  $(dirname "$file")/$target

The PRD is split into three files (the trichotomy):
  - project-prd.md          → live contract (problem, scope, NFRs, risks, success criteria)
  - project-prd-signals.md  → open + partial open questions (live signals)
  - project-prd-history.md  → resolved open questions + PRD revisions (audit trail)

If you're answering an open question, follow the three-step lift in
.claude/rules/prd.md:

  1. Fold the answer into the PRD body (or as a new AD in .claude/CLAUDE.md).
  2. Move the OQ row from project-prd-signals.md to project-prd-history.md
     "## Resolved Open Questions" with a "Resolved in Rev N: see §X" pointer.
  3. Append a "### Rev N — YYYY-MM-DD" entry to project-prd-history.md
     "## Revisions".

If you're adding a new open question, write directly to
project-prd-signals.md "## Open Questions".

If you're adding a PRD revision, write directly to project-prd-history.md
"## Revisions".

The hook scans inserts, not the whole document. Existing inline content in a
not-yet-migrated PRD continues to work — see docs/methodology/migration-playbook.md
for the per-project migration procedure.
MSG
exit 2
