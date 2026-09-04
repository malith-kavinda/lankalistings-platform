#!/usr/bin/env bash
#
# Forge Heartbeat — status-line segment provider (resting pulse).
#
# Sourceable:
#     . "<harness-root>/.claude/lib/forge-statusline-segment.sh"
#     segment=$(forge_statusline_segment "$stdin_json")
#
# Executable (direct invoke — the mode the developer's personal status-line
# script uses):
#     echo '<statusLine-stdin-json>' \
#       | <harness-root>/.claude/lib/forge-statusline-segment.sh
#
# Self-test:
#     ./forge-statusline-segment.sh --self-test
#
# Contract (see docs/engineering/specs/2026-05-21-forge-heartbeat-spec.md
# FR-1..FR-4, NFR-1, NFR-2):
#   - Reads Claude Code statusLine stdin JSON. The fields used:
#       workspace.project_dir   — preferred root anchor
#       cwd                     — fallback when workspace is absent
#   - Walks up from project_dir (or cwd) looking for .forge/tracker.yaml.
#     If not found → prints nothing, exits 0.
#   - Prints exactly one line to stdout. Never prints to stderr from the
#     happy path (stderr would clutter the terminal status line).
#   - Fails open: any error → no output, exit 0. Missing yq/jq/git is a
#     silent no-op. The status line must never break the developer's
#     terminal.
#   - Zero model-context tokens — the statusLine mechanism is terminal UI
#     chrome and runs outside the conversation entirely.
#
# Output format:
#     forge | <phase-specific-context>[ · stale]
#
# The prefix is `forge | ` (pipe, not colon); the phase name is NOT
# repeated as a literal label — every context string is self-identifying:
#     discovery     → Gate 1: <status>[ (<relative-date>)][ · <N> risk[s]]
#     architecture  → Gate 2: <status>[ (<relative-date>)][ · <N> risk[s]]
#                                                            [ · <M> spike[s]]
#     foundation    → <done>/<total> slices[ · active: <id> <slice-phase>]
#                     (or `ready to seal` when every slice is done)
#     engineering   → P<id> <first-word-of-title> (<done>/<total>) ·
#                                 active: <ticket> <phase>[ (+N)]
#                     (or `ready to seal` when phase complete; `no features
#                      in flight` when nothing in flight; small-project mode —
#                      when delivery.phases is empty — drops the P-summary
#                      and shows only `active: …` or `no features in flight`)
#
# Section owners (project_prd.owner, architecture.owner) are NOT surfaced
# — for solo developers it's their own name (duplication) and the
# dashboard already carries ownership. The actionable signal in setup
# phases is `last_gate_run` staleness.
#
# Width budget: every segment combination ≤ ~58 chars in the widest
# realistic case (architecture with date + 1 risk + 2 spikes); typical
# 30–50 chars. Leaves room for the personal status line in 120-col
# terminals.
#
# The trailing `· stale` flag is the same condition tracker-freshness.sh
# checks: spec/plan files modified in working tree but tracker.yaml is not.

set -u

# --- Sourceable helper -----------------------------------------------------
#
# All output is buffered via echo into the caller; stderr is /dev/null'd at
# every shell-out so a misconfigured git/yq/jq cannot leak chatter.

forge_statusline_segment() {
  local stdin_json="${1:-}"
  [ -z "$stdin_json" ] && return 0

  # jq is required to read the statusLine stdin JSON; yq is required to
  # read tracker.yaml. Either missing → silent no-op.
  command -v jq >/dev/null 2>&1 || return 0
  command -v yq >/dev/null 2>&1 || return 0

  local project_dir cwd
  project_dir=$(printf '%s' "$stdin_json" | jq -r '.workspace.project_dir // ""' 2>/dev/null)
  cwd=$(printf '%s' "$stdin_json" | jq -r '.cwd // ""' 2>/dev/null)

  # Walk up from project_dir (preferred) then cwd looking for .forge/tracker.yaml.
  local harness_root="" anchor
  for anchor in "$project_dir" "$cwd"; do
    [ -z "$anchor" ] && continue
    local dir="$anchor"
    local i=0
    while [ "$i" -lt 20 ]; do
      if [ -f "$dir/.forge/tracker.yaml" ]; then
        harness_root="$dir"
        break 2
      fi
      local parent
      parent=$(dirname "$dir")
      [ "$parent" = "$dir" ] && break
      dir="$parent"
      i=$((i + 1))
    done
  done

  # Not a Forge harness → print nothing.
  [ -z "$harness_root" ] && return 0

  local tracker="$harness_root/.forge/tracker.yaml"

  # --- Phase via shared derive-phase helper ------------------------------
  local derive_lib="$harness_root/.claude/lib/derive-phase.sh"
  local phase="n/a"
  if [ -f "$derive_lib" ]; then
    # shellcheck disable=SC1090
    . "$derive_lib"
    phase=$(derive_phase "$harness_root" 2>/dev/null || echo "n/a")
    [ -z "$phase" ] && phase="n/a"
  fi

  # --- Phase-specific context --------------------------------------------
  #
  # Every phase surfaces real, phase-relevant signal. No phase falls back to
  # a useless string like `branch:main`. When a field is null/empty, the
  # phase helper omits it rather than print a blank.
  local context=""
  case "$phase" in
    discovery)
      context=$(_forge_segment_discovery_context "$tracker")
      ;;
    architecture)
      context=$(_forge_segment_architecture_context "$tracker")
      ;;
    foundation)
      context=$(_forge_segment_foundation_context "$tracker")
      ;;
    engineering)
      context=$(_forge_segment_engineering_context "$tracker")
      ;;
    *)
      context="phase n/a"
      ;;
  esac

  # --- Freshness flag (same condition tracker-freshness.sh uses) ---------
  local stale_flag=""
  if _forge_segment_tracker_stale "$harness_root"; then
    stale_flag=" · stale"
  fi

  # Prefix is `forge | ` (pipe, not colon) and we deliberately omit the
  # phase name — every phase's context string is self-identifying
  # (`Gate 1` ⇒ discovery, `Gate 2` ⇒ architecture, `X/Y slices` ⇒
  # foundation, `P<N>` or `active:` ⇒ engineering). Repeating the phase
  # label was duplication and ate into the width budget.
  printf 'forge | %s%s\n' "$context" "$stale_flag"
}

# Discovery-phase context: Gate 1 status + how-long-since-last-gate-run + risks.
#
# `setup.project_prd.owner` is intentionally NOT surfaced — for solo
# developers it's their own name (duplication), and the dashboard already
# carries ownership. The actionable signal is "how stale is this gate?"
# (i.e. `last_gate_run`), not "whose desk is this on?"
#
# Output examples:
#   Gate 1: not-started
#   Gate 1: in-progress · 2 risks
#   Gate 1: in-progress (today) · 2 risks
#   Gate 1: gate1-failed (5d ago)
_forge_segment_discovery_context() {
  local tracker="$1"
  local status risks last_run rel
  status=$(yq -r '.setup.project_prd.status // "not-started"' "$tracker" 2>/dev/null)
  risks=$(yq -r '.setup.project_prd.accepted_risks | length' "$tracker" 2>/dev/null)
  last_run=$(yq -r '.setup.project_prd.last_gate_run // ""' "$tracker" 2>/dev/null)
  [ -z "$risks" ] && risks=0
  rel=$(_forge_segment_relative_date "$last_run")

  local parts="Gate 1: ${status}"
  [ -n "$rel" ] && parts="${parts} (${rel})"
  if [ "$risks" != "0" ]; then
    parts="${parts} · ${risks} $(_forge_segment_plural "$risks" risk)"
  fi
  printf '%s' "$parts"
}

# Architecture-phase context: Gate 2 status + how-long-since-last-gate-run
# + open risks + scoped spikes.
#
# Output examples:
#   Gate 2: in-progress
#   Gate 2: in-progress (1d ago)
#   Gate 2: in-progress (1d ago) · 1 risk · 2 spikes
#   Gate 2: gate2-failed (3d ago)
_forge_segment_architecture_context() {
  local tracker="$1"
  local status risks spikes last_run rel
  status=$(yq -r '.setup.architecture.status // "not-started"' "$tracker" 2>/dev/null)
  risks=$(yq -r '.setup.architecture.accepted_risks | length' "$tracker" 2>/dev/null)
  spikes=$(yq -r '.setup.architecture.spikes | length' "$tracker" 2>/dev/null)
  last_run=$(yq -r '.setup.architecture.last_gate_run // ""' "$tracker" 2>/dev/null)
  [ -z "$risks" ] && risks=0
  [ -z "$spikes" ] && spikes=0
  rel=$(_forge_segment_relative_date "$last_run")

  local parts="Gate 2: ${status}"
  [ -n "$rel" ] && parts="${parts} (${rel})"
  if [ "$risks" != "0" ]; then
    parts="${parts} · ${risks} $(_forge_segment_plural "$risks" risk)"
  fi
  if [ "$spikes" != "0" ]; then
    parts="${parts} · ${spikes} $(_forge_segment_plural "$spikes" spike)"
  fi
  printf '%s' "$parts"
}

# Convert an ISO date (YYYY-MM-DD, optionally with time) to a relative
# label: "today", "1d ago", "<N>d ago", or "<N>d from now" for the rare
# future-date case. Returns empty string on null/empty/invalid input.
#
# Cross-platform: tries BSD `date -j -f` first (macOS), falls back to
# GNU `date -d` (Linux). Both forms run with `-u` to avoid timezone drift.
_forge_segment_relative_date() {
  local iso="${1:-}"
  [ -z "$iso" ] || [ "$iso" = "null" ] && return 0

  # Strip any time portion — we only care about day granularity.
  local d="${iso%%T*}"

  local epoch today_epoch diff_days
  epoch=$(date -u -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null) \
    || epoch=$(date -u -d "$d" +%s 2>/dev/null) \
    || return 0

  today_epoch=$(date -u +%s)
  diff_days=$(( (today_epoch - epoch) / 86400 ))

  if [ "$diff_days" -lt 0 ]; then
    printf '%dd from now' "$((-diff_days))"
  elif [ "$diff_days" -eq 0 ]; then
    printf 'today'
  elif [ "$diff_days" -eq 1 ]; then
    printf '1d ago'
  else
    printf '%dd ago' "$diff_days"
  fi
}

# Foundation-phase context: slice progress + the active (non-done, non-not-started) slice.
#
# Output examples:
#   1/3 slices · active: F-002 dev
#   0/3 slices
#   3/3 slices · ready to seal
_forge_segment_foundation_context() {
  local tracker="$1"
  local total done active_id active_phase
  total=$(yq -r '.setup.foundation.slices | length' "$tracker" 2>/dev/null)
  done=$(yq -r '[.setup.foundation.slices[] | select(.status == "done")] | length' "$tracker" 2>/dev/null)
  [ -z "$total" ] && total=0
  [ -z "$done" ] && done=0

  local parts="${done}/${total} slices"

  if [ "$total" -gt 0 ] && [ "$done" = "$total" ]; then
    parts="${parts} · ready to seal"
    printf '%s' "$parts"
    return 0
  fi

  # Active slice = first slice where status is neither "done" nor "not-started".
  # If none, fall back to the first not-started slice.
  active_id=$(yq -r '[.setup.foundation.slices[] | select(.status != "done" and .status != "not-started")] | .[0].id // ""' "$tracker" 2>/dev/null)
  active_phase=$(yq -r '[.setup.foundation.slices[] | select(.status != "done" and .status != "not-started")] | .[0].status // ""' "$tracker" 2>/dev/null)

  if [ -z "$active_id" ]; then
    active_id=$(yq -r '[.setup.foundation.slices[] | select(.status == "not-started")] | .[0].id // ""' "$tracker" 2>/dev/null)
    active_phase=$(yq -r '[.setup.foundation.slices[] | select(.status == "not-started")] | .[0].status // ""' "$tracker" 2>/dev/null)
  fi

  if [ -n "$active_id" ] && [ "$active_id" != "null" ]; then
    parts="${parts} · active: ${active_id} ${active_phase}"
  fi

  printf '%s' "$parts"
}

# Engineering-phase context: delivery-phase progress + active feature.
#
# Output examples (delivery.phases populated):
#   P2 Auth (3/7) · active: PRJ-002 dev (+1)     ← 1 in flight + 1 more
#   P2 Auth (3/7) · active: PRJ-002 dev          ← exactly 1 in flight
#   P2 Auth (3/7) · no features in flight
#   P2 Auth (7/7) · ready to seal
#
# Output examples (delivery.phases empty — small-project mode):
#   active: PRJ-002 dev (+1)
#   no features in flight
#
# Design notes:
#   - Phase title is rendered as the *first word only* (typically the most
#     informative; e.g. "Auth & navigation" → "Auth", "Platform core" →
#     "Platform"). Predictable width, no ellipsis dance.
#   - We show 1 active feature plus a `(+N)` overflow when more are in
#     flight. The most-recently-updated feature is the most relevant
#     "what am I working on right now" signal; the count conveys breadth.
#   - Vocabulary is `active:` (matches foundation phase) — consistent.
_forge_segment_engineering_context() {
  local tracker="$1"

  # ---- Delivery-phase summary -------------------------------------------
  local phase_summary=""
  local current_id phase_title phase_total phase_done
  current_id=$(yq -r '.delivery.current_phase // ""' "$tracker" 2>/dev/null)
  if [ -n "$current_id" ] && [ "$current_id" != "null" ] && [ "$current_id" != "" ]; then
    phase_title=$(FORGE_PID="$current_id" yq -r \
      '[.delivery.phases[] | select(.id == (strenv(FORGE_PID) | tonumber)) | .title] | .[0] // ""' \
      "$tracker" 2>/dev/null)
    phase_total=$(FORGE_PID="$current_id" yq -r \
      '[.features | to_entries[] | select(.value.delivery_phase == (strenv(FORGE_PID) | tonumber))] | length' \
      "$tracker" 2>/dev/null)
    phase_done=$(FORGE_PID="$current_id" yq -r \
      '[.features | to_entries[] | select(.value.delivery_phase == (strenv(FORGE_PID) | tonumber) and .value.phase == "done")] | length' \
      "$tracker" 2>/dev/null)
    [ -z "$phase_total" ] && phase_total=0
    [ -z "$phase_done" ] && phase_done=0

    phase_summary="P${current_id}"
    if [ -n "$phase_title" ] && [ "$phase_title" != "null" ]; then
      # First word only — predictable width, no ellipsis. Cut at first
      # whitespace; if the first word itself is huge (>15 chars), truncate.
      local first_word="${phase_title%% *}"
      first_word=$(_forge_segment_truncate "$first_word" 15)
      phase_summary="${phase_summary} ${first_word}"
    fi
    phase_summary="${phase_summary} (${phase_done}/${phase_total})"

    # Sealable phase — flag it instead of listing actives.
    if [ "$phase_total" -gt 0 ] && [ "$phase_done" = "$phase_total" ]; then
      printf '%s · ready to seal' "$phase_summary"
      return 0
    fi
  fi

  # ---- Active feature + overflow count ----------------------------------
  #
  # In-flight = phase in {spec, plan, dev, review}. `done` and `ship` are
  # terminal; `backlog` is not active. paused/dropped are exit states.
  # We surface only the most-recently-updated one; the rest are summarized
  # as `(+N)`.
  local inflight_count first_inflight
  inflight_count=$(yq -r '
    [.features | to_entries[]
      | select(.value.phase == "spec" or .value.phase == "plan"
            or .value.phase == "dev"  or .value.phase == "review")]
    | length' "$tracker" 2>/dev/null)
  [ -z "$inflight_count" ] && inflight_count=0

  first_inflight=$(yq -r '
    [.features | to_entries[]
      | select(.value.phase == "spec" or .value.phase == "plan"
            or .value.phase == "dev"  or .value.phase == "review")]
    | sort_by(.value.last_updated // "")
    | reverse
    | .[0]
    | ((.value.jira // .key) + " " + .value.phase)' \
    "$tracker" 2>/dev/null)
  [ "$first_inflight" = "null" ] && first_inflight=""

  local active_part=""
  if [ "$inflight_count" -gt 0 ] && [ -n "$first_inflight" ]; then
    if [ "$inflight_count" -gt 1 ]; then
      active_part=$(printf 'active: %s (+%d)' "$first_inflight" "$((inflight_count - 1))")
    else
      active_part=$(printf 'active: %s' "$first_inflight")
    fi
  else
    active_part="no features in flight"
  fi

  if [ -n "$phase_summary" ]; then
    printf '%s · %s' "$phase_summary" "$active_part"
  else
    printf '%s' "$active_part"
  fi
}

# Pluralizer: prints "<word>" or "<word>s" based on count.
_forge_segment_plural() {
  local count="$1" word="$2"
  if [ "$count" = "1" ]; then
    printf '%s' "$word"
  else
    printf '%ss' "$word"
  fi
}

# Truncate a string to N chars, appending "…" when truncated.
_forge_segment_truncate() {
  local s="$1" max="$2"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:$((max - 1))}"
  fi
}

# Mirrors tracker-freshness.sh: spec/plan files modified but tracker.yaml not.
# Returns 0 (truthy) when stale; 1 otherwise.
_forge_segment_tracker_stale() {
  local harness_root="$1"
  local modified
  modified=$(git -C "$harness_root" diff --name-only HEAD 2>/dev/null) || return 1

  local spec_or_plan=false tracker_changed=false f
  while IFS= read -r f; do
    case "$f" in
      .forge/specs/*-spec.md|.forge/plans/*-plan.md) spec_or_plan=true ;;
      .forge/tracker.yaml) tracker_changed=true ;;
    esac
  done <<<"$modified"

  if [ "$spec_or_plan" = true ] && [ "$tracker_changed" = false ]; then
    return 0
  fi
  return 1
}

# --- Direct-invoke mode ----------------------------------------------------

_forge_statusline_main() {
  local stdin_json=""
  if [ ! -t 0 ]; then
    stdin_json=$(cat)
  fi
  forge_statusline_segment "$stdin_json"
  return 0
}

# --- Self-test -------------------------------------------------------------

_forge_statusline_self_test() {
  local pass=0 fail=0
  local tmpdir
  tmpdir=$(mktemp -d)

  _check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
      printf '  [PASS] %-58s -> %q\n' "$label" "$actual"
      pass=$((pass + 1))
    else
      printf '  [FAIL] %-58s expected %q\n                                                                   got %q\n' \
        "$label" "$expected" "$actual"
      fail=$((fail + 1))
    fi
  }

  # Fixture: a fake harness with a writable tracker and a co-located
  # derive-phase.sh so the engineering branch can be tested end-to-end.
  local h="$tmpdir/proj"
  mkdir -p "$h/.forge" "$h/.claude/lib"
  cp "$(dirname "${BASH_SOURCE[0]}")/derive-phase.sh" "$h/.claude/lib/derive-phase.sh"

  # ---- Discovery: fresh tracker, no owner, no risks ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "not-started", owner: null, accepted_risks: [] }
  architecture: { status: "not-started", accepted_risks: [], spikes: [] }
  foundation: { status: "not-started", slices: [] }
features: {}
YAML
  local stdin
  stdin=$(printf '{"workspace":{"project_dir":"%s"},"cwd":"%s"}' "$h" "$h")
  _check "discovery / fresh tracker, no owner, no risks" \
    "forge | Gate 1: not-started" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Discovery: two accepted risks, no gate run yet ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd:
    status: "in-progress"
    last_gate_run: null
    accepted_risks:
      - { id: "R-PRD-001" }
      - { id: "R-PRD-002" }
  architecture: { status: "not-started", accepted_risks: [], spikes: [] }
  foundation: { status: "not-started", slices: [] }
features: {}
YAML
  _check "discovery / 2 risks, no gate run yet" \
    "forge | Gate 1: in-progress · 2 risks" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Discovery: single risk + gate ran today (dynamic date) ----
  local today
  today=$(date -u +%Y-%m-%d)
  cat >"$h/.forge/tracker.yaml" <<YAML
setup:
  project_prd:
    status: "in-progress"
    last_gate_run: "$today"
    accepted_risks: [ { id: "R-PRD-001" } ]
  architecture: { status: "not-started", accepted_risks: [], spikes: [] }
  foundation: { status: "not-started", slices: [] }
features: {}
YAML
  _check "discovery / ran today + 1 risk" \
    "forge | Gate 1: in-progress (today) · 1 risk" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Discovery: gate ran 3 days ago (dynamic date) ----
  local three_days_ago
  three_days_ago=$(date -u -j -v-3d +%Y-%m-%d 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%d)
  cat >"$h/.forge/tracker.yaml" <<YAML
setup:
  project_prd:
    status: "gate1-failed"
    last_gate_run: "$three_days_ago"
    accepted_risks: []
  architecture: { status: "not-started", accepted_risks: [], spikes: [] }
  foundation: { status: "not-started", slices: [] }
features: {}
YAML
  _check "discovery / gate1-failed 3d ago" \
    "forge | Gate 1: gate1-failed (3d ago)" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Architecture: in-progress, no risks/spikes yet ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed", accepted_risks: [] }
  architecture: { status: "in-progress", accepted_risks: [], spikes: [] }
  foundation: { status: "not-started", slices: [] }
features: {}
YAML
  _check "architecture / in-progress, no risks/spikes" \
    "forge | Gate 2: in-progress" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Architecture: mid-Gate-2 with risks + spikes, no gate run yet ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed", accepted_risks: [] }
  architecture:
    status: "in-progress"
    last_gate_run: null
    accepted_risks: [ { id: "R-ARCH-001" } ]
    spikes:
      - { id: "SP-ARCH-001" }
      - { id: "SP-ARCH-002" }
  foundation: { status: "not-started", slices: [] }
features: {}
YAML
  _check "architecture / 1 risk + 2 spikes, no gate run yet" \
    "forge | Gate 2: in-progress · 1 risk · 2 spikes" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Architecture: gate ran 1 day ago, with risks + spikes ----
  local yesterday
  yesterday=$(date -u -j -v-1d +%Y-%m-%d 2>/dev/null || date -u -d '1 day ago' +%Y-%m-%d)
  cat >"$h/.forge/tracker.yaml" <<YAML
setup:
  project_prd: { status: "gate1-passed", accepted_risks: [] }
  architecture:
    status: "in-progress"
    last_gate_run: "$yesterday"
    accepted_risks: [ { id: "R-ARCH-001" } ]
    spikes:
      - { id: "SP-ARCH-001" }
      - { id: "SP-ARCH-002" }
  foundation: { status: "not-started", slices: [] }
features: {}
YAML
  _check "architecture / ran 1d ago + 1 risk + 2 spikes" \
    "forge | Gate 2: in-progress (1d ago) · 1 risk · 2 spikes" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Foundation: 1/3 slices done, F-002 in dev ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation:
    status: "in-progress"
    slices:
      - { id: "F-001", status: "done" }
      - { id: "F-002", status: "dev" }
      - { id: "F-003", status: "not-started" }
features: {}
YAML
  _check "foundation / 1/3 done, active F-002 dev" \
    "forge | 1/3 slices · active: F-002 dev" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Foundation: 0/3, no active slice → falls back to first not-started ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation:
    status: "in-progress"
    slices:
      - { id: "F-001", status: "not-started" }
      - { id: "F-002", status: "not-started" }
      - { id: "F-003", status: "not-started" }
features: {}
YAML
  _check "foundation / 0/3, falls back to first not-started" \
    "forge | 0/3 slices · active: F-001 not-started" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Foundation: all done → ready to seal ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation:
    status: "in-progress"
    slices:
      - { id: "F-001", status: "done" }
      - { id: "F-002", status: "done" }
features: {}
YAML
  _check "foundation / all done → ready to seal" \
    "forge | 2/2 slices · ready to seal" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Engineering: delivery phase + in-flight features ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation: { status: "done", slices: [] }
delivery:
  current_phase: 2
  phases:
    - { id: 1, title: "Platform core", status: "complete" }
    - { id: 2, title: "Auth & navigation", status: "in-progress" }
features:
  done-1:    { jira: "PRJ-001", phase: "done",   delivery_phase: 2, last_updated: "2026-05-10" }
  in-dev:    { jira: "PRJ-002", phase: "dev",    delivery_phase: 2, last_updated: "2026-05-20" }
  in-plan:   { jira: "PRJ-003", phase: "plan",   delivery_phase: 2, last_updated: "2026-05-19" }
  in-spec:   { jira: "PRJ-004", phase: "spec",   delivery_phase: 2, last_updated: "2026-05-18" }
  in-back:   { jira: "PRJ-005", phase: "backlog", delivery_phase: 2, last_updated: "2026-05-05" }
YAML
  # Init a git repo so the stale check can run cleanly.
  (
    cd "$h" || exit 1
    [ -d .git ] || { git init -q; git config user.email t@t; git config user.name t; }
    git add -A >/dev/null 2>&1
    git commit -q -m engineering >/dev/null 2>&1
  )
  _check "engineering / phase 2 with done+in-flight" \
    "forge | P2 Auth (1/5) · active: PRJ-002 dev (+2)" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Engineering: phase ready to seal (every feature done) ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation: { status: "done", slices: [] }
delivery:
  current_phase: 2
  phases:
    - { id: 2, title: "Auth & navigation", status: "in-progress" }
features:
  done-1: { jira: "PRJ-001", phase: "done", delivery_phase: 2 }
  done-2: { jira: "PRJ-002", phase: "done", delivery_phase: 2 }
YAML
  (cd "$h" && git add -A >/dev/null 2>&1 && git commit -q -m e2 >/dev/null 2>&1)
  _check "engineering / phase ready to seal" \
    "forge | P2 Auth (2/2) · ready to seal" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Engineering: no delivery.phases (small project mode) + in-flight ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation: { status: "done", slices: [] }
delivery: { current_phase: null, phases: [] }
features:
  in-dev:  { jira: "PRJ-002", phase: "dev",  last_updated: "2026-05-20" }
  in-plan: { jira: "PRJ-003", phase: "plan", last_updated: "2026-05-19" }
YAML
  (cd "$h" && git add -A >/dev/null 2>&1 && git commit -q -m e3 >/dev/null 2>&1)
  _check "engineering / small project, in-flight only" \
    "forge | active: PRJ-002 dev (+1)" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Engineering: no delivery.phases, no in-flight ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation: { status: "done", slices: [] }
delivery: { current_phase: null, phases: [] }
features:
  done-1: { jira: "PRJ-001", phase: "done" }
YAML
  (cd "$h" && git add -A >/dev/null 2>&1 && git commit -q -m e4 >/dev/null 2>&1)
  _check "engineering / nothing in flight" \
    "forge | no features in flight" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Engineering: delivery phase populated, nothing in flight ----
  cat >"$h/.forge/tracker.yaml" <<'YAML'
setup:
  project_prd: { status: "gate1-passed" }
  architecture: { status: "gate2-passed" }
  foundation: { status: "done", slices: [] }
delivery:
  current_phase: 1
  phases:
    - { id: 1, title: "Platform core", status: "in-progress" }
features:
  done-1: { jira: "PRJ-001", phase: "done",    delivery_phase: 1 }
  back-1: { jira: "PRJ-002", phase: "backlog", delivery_phase: 1 }
YAML
  (cd "$h" && git add -A >/dev/null 2>&1 && git commit -q -m e5 >/dev/null 2>&1)
  _check "engineering / phase set, no in-flight" \
    "forge | P1 Platform (1/2) · no features in flight" \
    "$(forge_statusline_segment "$stdin")"

  # ---- Outside a Forge harness ----
  local outside="$tmpdir/outside"
  mkdir -p "$outside"
  local stdin2
  stdin2=$(printf '{"workspace":{"project_dir":"%s"},"cwd":"%s"}' "$outside" "$outside")
  _check "outside Forge harness → empty" "" "$(forge_statusline_segment "$stdin2")"

  # ---- Empty stdin ----
  _check "empty stdin → empty"          ""    "$(forge_statusline_segment "")"

  # ---- Malformed JSON → empty (jq fails silently, project_dir empties) ----
  _check "malformed stdin → empty"      ""    "$(forge_statusline_segment "{not json")"

  rm -rf "$tmpdir"

  echo
  echo "Self-test summary: $pass passed, $fail failed"
  return "$fail"
}

# --- Dispatch --------------------------------------------------------------

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    --self-test)
      _forge_statusline_self_test
      exit $?
      ;;
    -h|--help)
      cat <<USAGE
forge-statusline-segment.sh — Forge Heartbeat status-line segment provider

Read Claude Code statusLine stdin JSON and print a single-line Forge segment
to stdout. Prints nothing outside a Forge harness; never exits non-zero.

Usage:
  echo '<statusLine-stdin-json>' | $(basename "$0")
  $(basename "$0") --self-test
USAGE
      exit 0
      ;;
    "")
      _forge_statusline_main
      exit 0
      ;;
    *)
      # Unknown flags are silently ignored — the contract is "never break
      # the developer's status line." Print nothing, exit 0.
      exit 0
      ;;
  esac
fi
