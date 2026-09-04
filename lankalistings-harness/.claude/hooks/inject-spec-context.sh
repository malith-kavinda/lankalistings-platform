#!/usr/bin/env bash
#
# UserPromptSubmit hook.
# Auto-attaches Forge spec/plan files when the prompt uses explicit syntax.
#
# Syntax:
#   @spec:<name>   -> attaches .forge/specs/<name>.md
#   @plan:<name>   -> attaches .forge/plans/<name>.md
#
# <name> is matched exactly (case-sensitive) against the file stem. An
# optional .md suffix on <name> is tolerated and stripped, so
# @spec:auth-flow and @spec:auth-flow.md both resolve to auth-flow.md.
#
# Contract:
#   - For UserPromptSubmit, stdout is prepended to Claude's context.
#   - Exit 0 always (this hook never blocks prompts).
#   - Multiple references in one prompt all resolve; duplicates are de-duped.

set -u

prompt=$(jq -r '.prompt // ""')
[ -z "$prompt" ] && exit 0

# Only run inside a Forge project.
[ -d "$CLAUDE_PROJECT_DIR/.forge" ] || exit 0

# Extract unique @spec:<name> and @plan:<name> references from the prompt.
refs=$(echo "$prompt" \
  | grep -oE '@(spec|plan):[A-Za-z0-9._-]+' \
  | sort -u)

[ -z "$refs" ] && exit 0

for ref in $refs; do
  kind=${ref%%:*}       # @spec or @plan
  kind=${kind#@}        # spec or plan
  name=${ref#*:}        # <name>
  name=${name%.md}      # strip optional .md suffix

  case "$kind" in
    spec) dir="specs" ;;
    plan) dir="plans" ;;
    *)    continue     ;;
  esac

  file="$CLAUDE_PROJECT_DIR/.forge/$dir/$name.md"
  if [ -f "$file" ]; then
    echo ""
    echo "--- Auto-attached via @$kind:$name from .forge/$dir/$name.md ---"
    cat "$file"
    echo ""
    echo "--- End of auto-attached file ---"
  else
    # Reference exists in the prompt but the file doesn't. Tell Claude so
    # it doesn't silently proceed on a stale or mistyped reference.
    echo ""
    echo "--- Note: @$kind:$name referenced but .forge/$dir/$name.md does not exist ---"
  fi
done

exit 0
