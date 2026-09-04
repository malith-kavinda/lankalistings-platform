#!/usr/bin/env bash
#
# Stop hook — tracker freshness soft warning.
#
# Contract:
#   - Always exit 0. This is a soft gate; the session ends regardless.
#   - Emits a `systemMessage` JSON object on stdout when spec/plan files
#     have been modified in the working tree but .forge/tracker.yaml has
#     not. Claude Code renders the message inline in the user's terminal
#     during normal session flow (zero model-context tokens consumed).
#
# Why JSON, not plain stderr:
#   Stop hooks at exit 0 send plain stderr to Claude Code's debug log
#   only — NOT to the user's terminal. The documented user-facing channel
#   for non-blocking Stop output is the `systemMessage` JSON field. See
#   https://code.claude.com/docs/en/hooks.md (Exit Code Behavior + JSON
#   Output Fields). Earlier revisions of this hook wrote to plain stderr
#   and were silently invisible to developers — fixed alongside the
#   Forge Heartbeat recap (v0.23.0).
#
# Trade-off: uses `git diff --name-only HEAD` (working-tree-vs-HEAD) rather
# than a per-session diff (Stop hooks don't have one). False-positive case:
# a prior session edited a spec/plan and didn't commit/push — the warning
# fires on this unrelated session. Acceptable: the warning is informational,
# easy to ignore, and prompts the user to think about whether the prior
# tracker update was forgotten.
#
# Fails open: if not in a git repo or git fails for any reason, exit 0 silently.

set -u

modified=$(git diff --name-only HEAD 2>/dev/null) || exit 0

spec_or_plan_modified=false
tracker_modified=false
while IFS= read -r f; do
  case "$f" in
    # In shell `case` patterns, `*` matches across `/`, so a single
    # `*-spec.md` covers both `.forge/specs/<x>-spec.md` and
    # `.forge/specs/foundation/<x>-spec.md`.
    .forge/specs/*-spec.md|.forge/plans/*-plan.md)
      spec_or_plan_modified=true ;;
    .forge/tracker.yaml)
      tracker_modified=true ;;
  esac
done <<< "$modified"

if [ "$spec_or_plan_modified" = true ] && [ "$tracker_modified" = false ]; then
  msg='Spec/plan files modified but .forge/tracker.yaml is unchanged.
Update last_updated and the relevant slice/feature notes before ending the session. (Soft warning — session ends regardless.)'
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$msg" '{systemMessage: $m}'
  else
    # jq missing — degrade to debug-log stderr write rather than silent drop.
    printf '%s\n' "$msg" >&2
  fi
fi

exit 0
