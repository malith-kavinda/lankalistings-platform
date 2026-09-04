#!/usr/bin/env bash
#
# Stop hook.
# Runs before Claude declares a turn complete. Exit 2 blocks the Stop with a
# message Claude reads and acts on.
#
# Contract:
#   - Exit 0 to allow the turn to end. Exit 2 to block.
#   - Check `stop_hook_active` and bail on the second firing — otherwise a
#     persistent failure creates an infinite Stop loop.
#   - Budget: up to 10 minutes. Prefer affected-file tests over full suite.
#
# THIS IS A TEMPLATE. Fill in the commands that must pass before a turn ends.

set -u

# Avoid infinite Stop loops: if we already blocked once this turn, don't again.
stop_hook_active=$(jq -r '.stop_hook_active // false')
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

# Only enforce if the working tree actually changed this session.
cd "$CLAUDE_PROJECT_DIR" || exit 0
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git diff --quiet && git diff --cached --quiet; then
    # Nothing to verify.
    exit 0
  fi
fi

# Fill in verification commands below. Examples:
#
#   pnpm test --run >&2 || {
#     echo "Stop blocked: failing tests. Fix them before ending the turn." >&2
#     exit 2
#   }
#
#   pnpm tsc --noEmit >&2 || {
#     echo "Stop blocked: typecheck failed." >&2
#     exit 2
#   }
#
#   uv run pytest -x >&2 || {
#     echo "Stop blocked: failing tests." >&2
#     exit 2
#   }

exit 0
