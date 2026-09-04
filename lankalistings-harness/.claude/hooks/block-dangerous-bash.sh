#!/usr/bin/env bash
#
# PreToolUse hook — Bash matcher.
# Blocks obviously destructive Bash invocations.
# See docs/claude-code-hooks-deepdive.md in the harness repo for rationale.
#
# Contract:
#   - stdin is JSON; read with jq.
#   - Exit 0 to allow. Exit 2 to block (stderr is shown to Claude).
#   - Keep the false-positive rate low; noisy gates get disabled.

set -u

cmd=$(jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && exit 0

# Destructive patterns that should never run without explicit human action.
patterns=(
  'rm +-rf +/($| )'
  'rm +-rf +~($| )'
  'rm +-rf +\$HOME'
  'sudo +rm'
  'sudo +dd'
  'curl [^|]* \| *sh'
  'curl [^|]* \| *bash'
  'wget [^|]* \| *sh'
  'DROP +TABLE'
  'TRUNCATE +TABLE'
  ':\(\) *\{'
  'mkfs\.'
  'dd +if=.*of=/dev/'
)

for p in "${patterns[@]}"; do
  if echo "$cmd" | grep -qE "$p"; then
    echo "Blocked by Forge harness: command matched dangerous pattern /$p/." >&2
    echo "If this is genuinely required, stop and ask the developer to run it." >&2
    exit 2
  fi
done

# Force-push to protected branches.
if echo "$cmd" | grep -qE 'git +push +(-f|--force|--force-with-lease)\b.*\b(main|master|develop|staging|production)\b'; then
  echo "Blocked by Forge harness: force-push to a protected branch." >&2
  echo "Forge never force-pushes main, master, develop, staging, or production." >&2
  exit 2
fi

# Hard reset — destructive; ask the developer to run it directly if needed.
if echo "$cmd" | grep -qE 'git +reset +--hard'; then
  echo "Blocked by Forge harness: 'git reset --hard' is destructive." >&2
  echo "If you genuinely need this, stop and ask the developer to run it." >&2
  exit 2
fi

exit 0
