#!/usr/bin/env bash
#
# PreToolUse hook — Edit/Write/MultiEdit matcher.
# Blocks modifications to paths that must only change via human-reviewed commits.
#
# Contract:
#   - Exit 0 to allow. Exit 2 to block (stderr is shown to Claude).
#   - Teams: extend the `protected` array with project-specific paths.

set -u

file=$(jq -r '.tool_input.file_path // ""')
[ -z "$file" ] && exit 0

# Default protected paths. Extend per project.
protected=(
  ".github/workflows/"
  ".gitlab-ci.yml"
  ".circleci/"
  "Jenkinsfile"
  "infra/"
  "terraform/"
  ".tf"
  "charts/"
  "helm/"
  "db/migrations/"
  "migrations/"
)

for p in "${protected[@]}"; do
  case "$file" in
    *"$p"*)
      cat >&2 <<EOF
Blocked by Forge harness: $file is a protected path (matched '$p').
Protected paths must be modified via a dedicated spec and human review.
If this is genuinely required, stop editing and tell the developer.
EOF
      exit 2
      ;;
  esac
done

exit 0
