#!/usr/bin/env bash
#
# PreToolUse hook — Edit/Write/MultiEdit matcher.
# Blocks creation/modification of feature specs (.forge/specs/<x>-spec.md)
# until Gate 2 has passed AND foundation is complete.
#
# Foundation specs (.forge/specs/foundation/**) are exempt — they are
# explicitly authored during the Gate 2 / pre-Gate 3 window per
# framework.md §4.10 and the team-guide foundation discipline.
#
# Contract:
#   - Exit 0 to allow. Exit 2 to block (stderr is shown to Claude).
#   - Fails open with a stderr note (exit 0) if yq is missing.
#   - Source of truth: .forge/tracker.yaml setup.architecture.status,
#                      .forge/tracker.yaml setup.foundation.status.

set -u

file=$(jq -r '.tool_input.file_path // ""')
[ -z "$file" ] && exit 0

# Only fire on writes inside .forge/specs/ — skip foundation/.
case "$file" in
  *"/.forge/specs/foundation/"*) exit 0 ;;
  *"/.forge/specs/"*) ;;
  *) exit 0 ;;
esac

tracker="$CLAUDE_PROJECT_DIR/.forge/tracker.yaml"
[ -f "$tracker" ] || exit 0

if ! command -v yq >/dev/null 2>&1; then
  echo "Forge guard-spec-leapfrog: yq not installed; skipping check. Install with 'brew install yq' to enable Gate 2 and foundation enforcement on spec writes." >&2
  exit 0
fi

arch_status=$(yq '.setup.architecture.status // "unknown"' "$tracker")
found_status=$(yq '.setup.foundation.status // "unknown"' "$tracker")

case "$arch_status" in
  gate2-passed*) ;;
  *)
    cat >&2 <<EOF
Blocked by Forge harness: cannot create or edit feature specs before
Gate 2 (architecture probe) has passed.

Current state (from .forge/tracker.yaml):
  setup.architecture.status: $arch_status

Resolve by one of:
  1. Run /forge-arch-probe and pass Gate 2 before authoring this spec.
  2. If this is a foundation slice (scaffolding work between Gate 2
     and Gate 3 per framework.md §4.10), place it under
     .forge/specs/foundation/ — that path is exempt from this check.
  3. If the gate has actually passed but the tracker is stale, update
     .forge/tracker.yaml setup.architecture.status to one of:
     gate2-passed, gate2-passed-with-risks, gate2-passed-with-spikes,
     then retry.
EOF
    exit 2
    ;;
esac

case "$found_status" in
  done) ;;
  *)
    cat >&2 <<EOF
Blocked by Forge harness: cannot create or edit feature specs before
foundation work is complete.

Current state (from .forge/tracker.yaml):
  setup.foundation.status: $found_status

Foundation = scaffolding work that runs between Gate 2 and Gate 3
(framework.md §4.10). Feature specs assume the foundation substrate
exists; authoring them before foundation is done invents requirements
the substrate doesn't support yet.

Resolve by one of:
  1. Complete the foundation slices listed in
     .forge/design/architecture.md > Foundation Backlog, then mark
     setup.foundation.status to "done" in .forge/tracker.yaml.
  2. If this file IS a foundation slice, place it under
     .forge/specs/foundation/ — that path is exempt from this check.
EOF
    exit 2
    ;;
esac

exit 0
