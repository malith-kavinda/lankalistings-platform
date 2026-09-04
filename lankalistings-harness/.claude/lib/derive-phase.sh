#!/usr/bin/env bash
#
# Shared helper: derive the current engagement phase from .forge/tracker.yaml.
#
# Sourceable:
#     . "<harness-root>/.claude/lib/derive-phase.sh"
#     phase=$(derive_phase "<harness-root>")
#
# Executable (self-test mode):
#     ./derive-phase.sh --self-test
#
# Returns one of: discovery | architecture | foundation | engineering | n/a
#
# "n/a" is returned when:
#   - <harness-root> argument is empty
#   - <harness-root>/.forge/tracker.yaml does not exist
#   - yq is not installed
#
# Callers can interpret "n/a" as "not in a Forge project" or
# "phase undeterminable; treat as out-of-band."
#
# Phase mapping (matches the original convention from phase-scope-skills.sh
# prior to the v0.17 refactor):
#   - discovery     : project_prd not gate1-passed*
#   - architecture  : gate1 passed, architecture not gate2-passed*
#   - foundation    : gate2 passed, foundation.status != "done"
#   - engineering   : foundation.status == "done"

derive_phase() {
  local harness_root="${1:-}"
  local tracker

  if [ -z "$harness_root" ]; then
    echo "n/a"
    return 0
  fi

  tracker="$harness_root/.forge/tracker.yaml"
  if [ ! -f "$tracker" ]; then
    echo "n/a"
    return 0
  fi

  if ! command -v yq >/dev/null 2>&1; then
    echo "n/a"
    return 0
  fi

  local prd_status arch_status foundation_status
  prd_status=$(yq -r '.setup.project_prd.status // "not-started"' "$tracker")
  arch_status=$(yq -r '.setup.architecture.status // "not-started"' "$tracker")
  foundation_status=$(yq -r '.setup.foundation.status // "not-started"' "$tracker")

  local phase="discovery"
  case "$prd_status" in
    gate1-passed*)
      phase="architecture"
      case "$arch_status" in
        gate2-passed*)
          if [ "$foundation_status" = "done" ]; then
            phase="engineering"
          else
            phase="foundation"
          fi
          ;;
      esac
      ;;
  esac

  echo "$phase"
}

# --- Self-test mode --------------------------------------------------------

_derive_phase_self_test() {
  local pass=0
  local fail=0
  local tmpdir
  tmpdir=$(mktemp -d)

  _check() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
      printf '  [PASS] %-50s -> %s\n' "$label" "$actual"
      pass=$((pass + 1))
    else
      printf '  [FAIL] %-50s expected %s, got %s\n' "$label" "$expected" "$actual"
      fail=$((fail + 1))
    fi
  }

  _fixture() {
    local name="$1"; shift
    local prd="$1"; shift
    local arch="$1"; shift
    local fnd="$1"; shift
    local dir="$tmpdir/$name"
    mkdir -p "$dir/.forge"
    cat > "$dir/.forge/tracker.yaml" <<EOF
setup:
  project_prd:
    status: "$prd"
  architecture:
    status: "$arch"
  foundation:
    status: "$fnd"
EOF
    echo "$dir"
  }

  echo "Running derive_phase self-tests..."
  echo

  # 1. No tracker file
  local nodir="$tmpdir/no-tracker"
  mkdir -p "$nodir"
  _check "no tracker file" "n/a" "$(derive_phase "$nodir")"

  # 2. Empty arg
  _check "empty harness arg" "n/a" "$(derive_phase "")"

  # 3. Discovery (nothing passed)
  local d
  d=$(_fixture "discovery" "not-started" "not-started" "not-started")
  _check "discovery (nothing passed)" "discovery" "$(derive_phase "$d")"

  # 4. Architecture (gate1 passed plain)
  d=$(_fixture "arch-plain" "gate1-passed" "not-started" "not-started")
  _check "architecture (gate1-passed)" "architecture" "$(derive_phase "$d")"

  # 5. Architecture (gate1-passed-with-risks — wildcard match)
  d=$(_fixture "arch-risks" "gate1-passed-with-risks" "not-started" "not-started")
  _check "architecture (gate1-passed-with-risks)" "architecture" "$(derive_phase "$d")"

  # 6. Foundation (gate2 passed, foundation not done)
  d=$(_fixture "foundation" "gate1-passed" "gate2-passed" "in-progress")
  _check "foundation (gate2-passed, not done)" "foundation" "$(derive_phase "$d")"

  # 7. Foundation (gate2-passed-with-spikes — wildcard match)
  d=$(_fixture "foundation-spikes" "gate1-passed" "gate2-passed-with-spikes" "not-started")
  _check "foundation (gate2-passed-with-spikes)" "foundation" "$(derive_phase "$d")"

  # 8. Engineering (foundation done)
  d=$(_fixture "engineering" "gate1-passed" "gate2-passed-with-spikes" "done")
  _check "engineering (foundation done)" "engineering" "$(derive_phase "$d")"

  # 9. Stays in discovery if PRD not gate1-passed even if foundation says done
  d=$(_fixture "discovery-still" "not-started" "gate2-passed" "done")
  _check "discovery even if downstream filled (gate not strictly passed)" "discovery" "$(derive_phase "$d")"

  rm -rf "$tmpdir"

  echo
  echo "Self-test summary: $pass passed, $fail failed"
  return "$fail"
}

# Run self-test if invoked directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    --self-test)
      _derive_phase_self_test
      exit $?
      ;;
    "")
      cat <<USAGE
derive-phase.sh — shared phase derivation helper

Usage:
  Source it:
      . "<harness-root>/.claude/lib/derive-phase.sh"
      phase=\$(derive_phase "<harness-root>")

  Or run self-test:
      ./derive-phase.sh --self-test

Returns one of: discovery | architecture | foundation | engineering | n/a
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Try: --self-test or no arguments for usage" >&2
      exit 1
      ;;
  esac
fi
