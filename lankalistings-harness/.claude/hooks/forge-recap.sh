#!/usr/bin/env bash
#
# Stop hook — Forge Heartbeat session recap (the beat).
#
# Contract (see docs/engineering/specs/2026-05-21-forge-heartbeat-spec.md
# FR-5..FR-8, NFR-1..NFR-3):
#   - Always exit 0. Never blocks a session.
#   - Emits a `{"systemMessage": "..."}` JSON object on stdout so Claude
#     Code renders the recap inline in the user's terminal at end-of-turn
#     (the documented user-visible channel for non-blocking Stop hooks —
#     plain stderr at exit 0 goes to the debug log only). Zero
#     model-context tokens (NFR-1) — systemMessage is user-facing UI, not
#     model context. See https://code.claude.com/docs/en/hooks.md.
#   - State-derived only: reads `git diff --name-only HEAD`, the project's
#     .forge/tracker.yaml, and .forge/usage.jsonl (filtered by session_id).
#     Wires up no new event capture in any other hook (FR-6).
#   - Interesting-or-silent: when no spec/plan/tracker files changed this
#     session, the recap is suppressed entirely (FR-8). Token totals alone
#     are not "interesting" — they live in the dashboard.
#   - Skip on `stop_hook_active = true` re-fires (OQ-4 resolution) to avoid
#     double-printing when an earlier Stop-hook blocked.
#   - < 200ms target (NFR-3). Every shell-out is short-circuit and fails
#     open: missing yq/jq/git is a silent no-op.

# Deliberately NOT `set -u`: the recap must never break a session. Empty
# arrays under bash 3 (macOS default) are treated as unset, which would
# fail the script under -u. Every variable in this script is guarded
# explicitly with `${var:-}` or array-existence checks below.

# --- 0. Bail on re-fires --------------------------------------------------

stdin_json=""
if [ ! -t 0 ]; then
  stdin_json=$(cat)
fi

if [ -n "$stdin_json" ] && command -v jq >/dev/null 2>&1; then
  stop_hook_active=$(printf '%s' "$stdin_json" | jq -r '.stop_hook_active // false' 2>/dev/null)
  if [ "$stop_hook_active" = "true" ]; then
    exit 0
  fi
fi

# --- 1. Locate harness root ----------------------------------------------

harness_root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$harness_root" ] || [ ! -d "$harness_root/.forge" ]; then
  # Fall back to walking up from cwd.
  dir="$PWD"
  for _ in $(seq 20); do
    if [ -d "$dir/.forge" ]; then
      harness_root="$dir"
      break
    fi
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
fi

if [ -z "$harness_root" ] || [ ! -f "$harness_root/.forge/tracker.yaml" ]; then
  exit 0
fi

# --- 2. Gather working-tree changes (the interesting-or-silent gate) -----

if ! command -v git >/dev/null 2>&1; then
  exit 0
fi

modified=$(git -C "$harness_root" diff --name-only HEAD 2>/dev/null) || exit 0

specs_changed=()
plans_changed=()
tracker_changed=false
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    .forge/specs/*-spec.md|.forge/specs/foundation/*-spec.md)
      specs_changed+=("$f") ;;
    .forge/plans/*-plan.md|.forge/plans/foundation/*-plan.md)
      plans_changed+=("$f") ;;
    .forge/tracker.yaml)
      tracker_changed=true ;;
  esac
done <<<"$modified"

# Interesting-or-silent: nothing relevant changed → no recap (FR-8).
if [ "${#specs_changed[@]}" -eq 0 ] \
   && [ "${#plans_changed[@]}" -eq 0 ] \
   && [ "$tracker_changed" = false ]; then
  exit 0
fi

# --- 3. Derive phase + gate / next-gate context --------------------------

phase="n/a"
if [ -f "$harness_root/.claude/lib/derive-phase.sh" ]; then
  # shellcheck disable=SC1091
  . "$harness_root/.claude/lib/derive-phase.sh"
  phase=$(derive_phase "$harness_root" 2>/dev/null || echo "n/a")
  [ -z "$phase" ] && phase="n/a"
fi

# Header line — phase + delivery context (used as the first line of the
# systemMessage so Claude Code's `Stop says:` prefix lands on something
# meaningful rather than the redundant "Forge recap" label).
#
# No markdown — Claude Code's systemMessage renderer doesn't interpret
# `**bold**` or backtick code spans (verified in v0.23.0 dev cycle); it
# shows them as literal characters. Plain text + Unicode separators +
# bullet markers carry all the visual structure we need.
header_line="${phase}"
if command -v yq >/dev/null 2>&1; then
  tracker="$harness_root/.forge/tracker.yaml"
  case "$phase" in
    discovery)
      g=$(yq -r '.setup.project_prd.status // "not-started"' "$tracker" 2>/dev/null)
      header_line="discovery · next gate: Gate 1 (${g})"
      ;;
    architecture)
      g=$(yq -r '.setup.architecture.status // "not-started"' "$tracker" 2>/dev/null)
      header_line="architecture · next gate: Gate 2 (${g})"
      ;;
    foundation)
      total=$(yq -r '.setup.foundation.slices | length' "$tracker" 2>/dev/null)
      done=$(yq -r '[.setup.foundation.slices[] | select(.status == "done")] | length' "$tracker" 2>/dev/null)
      [ -z "$total" ] && total=0
      [ -z "$done" ] && done=0
      header_line="foundation · ${done}/${total} slices · next gate: Gate 3"
      ;;
    engineering)
      cur=$(yq -r '.delivery.current_phase // "null"' "$tracker" 2>/dev/null)
      if [ "$cur" != "null" ] && [ -n "$cur" ]; then
        title=$(FORGE_PID="$cur" yq -r '[.delivery.phases[] | select(.id == (strenv(FORGE_PID) | tonumber)) | .title] | .[0] // ""' "$tracker" 2>/dev/null)
        if [ -n "$title" ]; then
          header_line="engineering · P${cur} ${title}"
        else
          header_line="engineering · P${cur}"
        fi
      fi
      ;;
  esac
fi

# --- 4. Session token totals (if usage.jsonl exists) ---------------------

token_line=""
usage_file="$harness_root/.forge/usage.jsonl"
if [ -f "$usage_file" ] && command -v jq >/dev/null 2>&1 && [ -n "$stdin_json" ]; then
  session_id=$(printf '%s' "$stdin_json" | jq -r '.session_id // ""' 2>/dev/null)
  if [ -n "$session_id" ]; then
    # Pre-filter with grep (byte scan) before jq parses, mirroring
    # track-token-usage.sh's performance pattern.
    totals=$(grep -F "\"session_id\":\"$session_id\"" "$usage_file" 2>/dev/null \
      | jq -s '{
          input:  (map(.input_tokens // 0) | add // 0),
          output: (map(.output_tokens // 0) | add // 0),
          turns: length
        }' 2>/dev/null)
    if [ -n "$totals" ]; then
      turns=$(printf '%s' "$totals" | jq -r '.turns')
      if [ -n "$turns" ] && [ "$turns" != "0" ] && [ "$turns" != "null" ]; then
        in_t=$(printf '%s' "$totals" | jq -r '.input')
        out_t=$(printf '%s' "$totals" | jq -r '.output')
        # Humanize counts: 12400 → 12.4k, 1500000 → 1.5M
        in_h=$(awk -v n="$in_t" 'BEGIN {
          if (n >= 1000000) printf "%.1fM", n/1000000
          else if (n >= 1000) printf "%.1fk", n/1000
          else printf "%d", n
        }')
        out_h=$(awk -v n="$out_t" 'BEGIN {
          if (n >= 1000000) printf "%.1fM", n/1000000
          else if (n >= 1000) printf "%.1fk", n/1000
          else printf "%d", n
        }')
        token_line=$(printf 'tokens: %s in · %s out · %s turns' "$in_h" "$out_h" "$turns")
      fi
    fi
  fi
fi

# --- 5. Tracker-staleness warning (same condition as tracker-freshness) --

stale_warn=""
if { [ "${#specs_changed[@]}" -gt 0 ] || [ "${#plans_changed[@]}" -gt 0 ]; } \
   && [ "$tracker_changed" = false ]; then
  stale_warn="warning: spec/plan files modified but tracker.yaml is unchanged."
fi

# --- 6. Emit recap via systemMessage JSON ---------------------------------
#
# Claude Code Stop hooks at exit 0: plain stderr goes to the debug log
# only — NOT visible in the user's terminal during normal session flow.
# To surface a human-readable message, emit a JSON object on stdout with a
# `systemMessage` field. Claude Code renders it as an inline user-facing
# warning (no model-context tokens consumed; satisfies NFR-1).
#
# Verified against the documented Stop-hook exit-code contract — see
# https://code.claude.com/docs/en/hooks.md (Exit Code Behavior + JSON
# Output Fields).

recap_body=$(
  printf '%s\n' "$header_line"
  printf '─────────────────────────────────────────────\n'
  printf 'changed:\n'
  # `${arr[@]+"${arr[@]}"}` expands to nothing when the array is empty/unset,
  # avoiding the "unbound variable" trip on macOS's bash 3.
  for f in ${specs_changed[@]+"${specs_changed[@]}"}; do printf '  • spec    %s\n' "$f"; done
  for f in ${plans_changed[@]+"${plans_changed[@]}"}; do printf '  • plan    %s\n' "$f"; done
  if [ "$tracker_changed" = true ]; then
    printf '  • tracker .forge/tracker.yaml\n'
  fi

  [ -n "$token_line" ] && printf '%s\n' "$token_line"
  [ -n "$stale_warn" ] && printf '\n%s\n' "$stale_warn"
)

# If jq is missing for any reason, fall back to a debug-log write — at
# least the data is captured somewhere. (Should not happen in practice;
# jq is a hard dependency of several other Stop hooks already.)
if command -v jq >/dev/null 2>&1; then
  jq -n --arg msg "$recap_body" '{systemMessage: $msg}'
else
  printf '%s\n' "$recap_body" >&2
fi

exit 0
