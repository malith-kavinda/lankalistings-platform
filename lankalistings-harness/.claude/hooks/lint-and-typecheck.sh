#!/usr/bin/env bash
#
# PostToolUse hook — Edit/Write/MultiEdit matcher.
# Runs project lint and typecheck after every edit.
#
# Contract:
#   - Exit 0 to allow. Exit 2 to block (stderr is shown to Claude, which
#     then fixes the issue on the next turn).
#   - Budget: under 3 seconds total. Slower = session latency suffers.
#
# THIS IS A TEMPLATE. Fill in the commands for each file type your project
# uses. The examples below are commented out — uncomment and adapt them, or
# replace entirely with your stack's tooling.

set -u

file=$(jq -r '.tool_input.file_path // empty')
[ -z "$file" ] && exit 0

# Only run on files inside the project.
case "$file" in
  "$CLAUDE_PROJECT_DIR"/*) ;;
  /*) exit 0 ;;
  *) ;;
esac

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    # Example (uncomment and adapt):
    #   pnpm biome check --reporter=summary "$file" >&2 || exit 2
    #   pnpm tsc --noEmit >&2 || exit 2
    :
    ;;
  *.py)
    # Example:
    #   uv run ruff check "$file" >&2 || exit 2
    #   uv run pyright "$file" >&2 || exit 2
    :
    ;;
  *.go)
    # Example:
    #   gofmt -l "$file" >&2 | (! grep .) >&2 || exit 2
    #   go vet ./... >&2 || exit 2
    :
    ;;
  *.rs)
    # Example:
    #   cargo clippy --quiet -- -D warnings >&2 || exit 2
    :
    ;;
  *.java|*.kt)
    # Example:
    #   ./gradlew --quiet checkstyleMain >&2 || exit 2
    :
    ;;
esac

exit 0
