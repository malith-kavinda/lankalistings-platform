#!/usr/bin/env bash
#
# PreToolUse hook — Edit/Write/MultiEdit matcher.
# Re-surfaces open risks and spikes from .forge/tracker.yaml whenever
# Claude is about to write/edit a feature spec or plan, so the
# authoring step is reminded of constraints the architecture probe
# already flagged.
#
# Contract:
#   - Exit 0 always; this hook does NOT block writes (use
#     guard-spec-leapfrog.sh for blocking concerns).
#   - Output goes to stderr — visible in the transcript and in
#     Claude's view of stderr-from-exit-0 hooks where supported.
#     Claude already sees the same content at session start via
#     inject-gate-state.sh; this hook is a contextual reminder at
#     the actual edit moment.
#   - Fails open silently if yq is missing.
#
# Source of truth: .forge/tracker.yaml setup.project_prd.accepted_risks,
#                  setup.architecture.accepted_risks, setup.architecture.spikes.

set -u

file=$(jq -r '.tool_input.file_path // ""')
[ -z "$file" ] && exit 0

# Only fire on writes inside .forge/specs/ or .forge/plans/.
case "$file" in
  *"/.forge/specs/"*|*"/.forge/plans/"*) ;;
  *) exit 0 ;;
esac

tracker="$CLAUDE_PROJECT_DIR/.forge/tracker.yaml"
[ -f "$tracker" ] || exit 0

command -v yq >/dev/null 2>&1 || exit 0

prd_risks_n=$(yq '.setup.project_prd.accepted_risks | length' "$tracker")
arch_risks_n=$(yq '.setup.architecture.accepted_risks | length' "$tracker")
arch_spikes_n=$(yq '.setup.architecture.spikes | length' "$tracker")

total=$((prd_risks_n + arch_risks_n + arch_spikes_n))
[ "$total" -eq 0 ] && exit 0

{
  echo ""
  echo "FORGE ADVISORY: open risks and spikes that may bear on this spec/plan."
  echo "(Editing $file — surfaced from .forge/tracker.yaml setup.*)"
  echo ""
  if [ "$prd_risks_n" -gt 0 ]; then
    yq '.setup.project_prd.accepted_risks[] | "  [PRD risk] " + .id + " — " + .description' "$tracker"
  fi
  if [ "$arch_risks_n" -gt 0 ]; then
    yq '.setup.architecture.accepted_risks[] | "  [ARCH risk] " + .id + " — " + .description' "$tracker"
  fi
  if [ "$arch_spikes_n" -gt 0 ]; then
    yq '.setup.architecture.spikes[] | "  [ARCH spike] " + .id + " — " + .description + " (trigger: " + .trigger + ")"' "$tracker"
  fi
  echo ""
  echo "If any of these affect the artifact you are about to write, capture them"
  echo "in the spec's Constraints/Open Questions or the plan's Risks section."
  echo ""
} >&2

exit 0
