#!/usr/bin/env bash
#
# SessionStart hook.
# Reads .forge/tracker.yaml and prints the current engagement-gate state
# (Gate 1 PRD, Gate 2 architecture, foundation, Gate 3 decomposition)
# plus open risks and spikes — injected into Claude's context at every
# session start so work is oriented from message one.
#
# Contract:
#   - For SessionStart, stdout is added as additionalContext.
#   - Exit 0 always; this hook never blocks.
#   - Fails open with a one-line note if yq is missing.
#
# Source of truth: .forge/tracker.yaml setup.* (status, last_gate_run,
# accepted_risks, spikes, foundation review_completed).

set -u

tracker="$CLAUDE_PROJECT_DIR/.forge/tracker.yaml"

[ -f "$tracker" ] || exit 0

if ! command -v yq >/dev/null 2>&1; then
  echo "Forge gate-state hook: yq not installed; skipping gate-state injection. Install with 'brew install yq' (macOS) or see https://github.com/mikefarah/yq."
  exit 0
fi

prd_status=$(yq '.setup.project_prd.status // "unknown"' "$tracker")
prd_last=$(yq '.setup.project_prd.last_gate_run // "n/a"' "$tracker")
prd_risks_n=$(yq '.setup.project_prd.accepted_risks | length' "$tracker")

arch_status=$(yq '.setup.architecture.status // "unknown"' "$tracker")
arch_last=$(yq '.setup.architecture.last_gate_run // "n/a"' "$tracker")
arch_risks_n=$(yq '.setup.architecture.accepted_risks | length' "$tracker")
arch_spikes_n=$(yq '.setup.architecture.spikes | length' "$tracker")

found_status=$(yq '.setup.foundation.status // "unknown"' "$tracker")
found_review=$(yq '.setup.foundation.review_completed // "n/a"' "$tracker")

decomp_status=$(yq '.setup.decomposition.status // "unknown"' "$tracker")
decomp_last=$(yq '.setup.decomposition.last_gate_run // "n/a"' "$tracker")

echo "=== Forge engagement-gate state (from .forge/tracker.yaml) ==="
echo ""
printf "  Gate 1 (PRD readiness)          : %-30s last run: %s   accepted risks: %s\n" "$prd_status" "$prd_last" "$prd_risks_n"
printf "  Gate 2 (Architecture probe)     : %-30s last run: %s   accepted risks: %s, spikes: %s\n" "$arch_status" "$arch_last" "$arch_risks_n" "$arch_spikes_n"
printf "  Foundation (between G2 and G3)  : %-30s review completed: %s\n" "$found_status" "$found_review"
printf "  Gate 3 (Decomposition)          : %-30s last run: %s\n" "$decomp_status" "$decomp_last"
echo ""

# Surface open risks and spikes inline so they're visible without grep.
total_open=$((prd_risks_n + arch_risks_n + arch_spikes_n))
if [ "$total_open" -gt 0 ]; then
  echo "Open risks and spikes:"
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
fi

echo "Full audit: .forge/engagement-gate-runs.md. If any gate is not yet passed, downstream work that depends on it should be flagged before proceeding."
echo ""

exit 0
