#!/usr/bin/env bash
#
# Dual-purpose script: (a) PostToolUse hook on Edit|Write|MultiEdit, and
# (b) manually-invokable bootstrap. Either way, derives the current
# engagement phase from .forge/tracker.yaml and rewrites the
# `skillOverrides` field in .claude/settings.local.json so that skills
# whose `phases:` front-matter excludes the current phase load as "off"
# (their description is hidden from session context) and in-phase skills
# load as "on".
#
# Each skill declares phase membership via a `phases:` field in its
# SKILL.md front-matter, e.g.:
#
#     ---
#     name: forge-prd-author
#     phases: [discovery]
#     description: ...
#     ---
#
# Skills with no `phases:` field are treated as always-on (no override
# written) — back-compat default.
#
# Phases (derived from tracker.yaml setup.*):
#   - discovery     : project_prd not gate1-passed*
#   - architecture  : gate1 passed, architecture not gate2-passed*
#   - foundation    : gate2 passed, foundation.status != "done"
#   - engineering   : foundation.status == "done"
#
# settings.local.json writes apply to the NEXT Claude Code session
# (settings are loaded before hooks run). On change, the hook prints a
# one-line stderr nudge asking the developer to restart.
#
# Contract:
#   - Exit 0 always. Never blocks.
#   - When invoked as a PostToolUse hook (stdin contains tool_input
#     JSON), acts only if the edited file ends in .forge/tracker.yaml.
#   - When invoked manually (no stdin / no file_path), acts unconditionally.
#     This is the bootstrap path for projects syncing this hook for the
#     first time when tracker.yaml is already in its current state.
#   - Silent on no-op (overrides unchanged).
#   - Fails open (one-line stderr note) if yq or jq is missing.

set -u

# --- 1. Detect invocation mode ---------------------------------------------

# Read stdin (if any). When invoked by Claude Code, stdin is a JSON blob
# with `tool_input.file_path`. When invoked manually, stdin is empty.
stdin_json=""
if [ ! -t 0 ]; then
  stdin_json=$(cat)
fi

if [ -n "$stdin_json" ]; then
  file=$(echo "$stdin_json" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
  # Hook-mode: only act on tracker.yaml edits.
  case "$file" in
    *".forge/tracker.yaml") ;;
    *) exit 0 ;;
  esac
fi
# Manual-mode (empty stdin) falls through unconditionally.

# --- 2. Resolve paths ------------------------------------------------------

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
settings_local="$PROJECT_DIR/.claude/settings.local.json"
skills_dir="$PROJECT_DIR/.claude/skills"
derive_phase_lib="$PROJECT_DIR/.claude/lib/derive-phase.sh"

[ -d "$skills_dir" ]      || exit 0
[ -f "$derive_phase_lib" ] || exit 0

if ! command -v yq >/dev/null 2>&1; then
  echo "Forge phase-scope-skills: yq missing; skillOverrides not refreshed. Install with 'brew install yq'." >&2
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Forge phase-scope-skills: jq missing; skillOverrides not refreshed." >&2
  exit 0
fi

# --- 3. Derive current phase via shared helper -----------------------------
#
# Phase derivation lives in .claude/lib/derive-phase.sh so both this hook
# and .claude/hooks/track-token-usage.sh use the same mapping (avoids
# silent drift between two implementations). See lib/README.md.

# shellcheck source=../lib/derive-phase.sh
. "$derive_phase_lib"

phase=$(derive_phase "$PROJECT_DIR")

# "n/a" means no tracker (or yq unavailable, already guarded above) —
# nothing to scope. Preserves the original silent-exit-on-no-tracker
# behavior from prior to the v0.17 refactor.
[ "$phase" = "n/a" ] && exit 0

# --- 4. Walk SKILL.md files and build skillOverrides JSON ------------------

overrides_json="{}"
shopt -s nullglob
for skill_md in "$skills_dir"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  # Extract front-matter (between the first pair of `---` lines).
  fm=$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++; if(c==2) exit; next} c==1 {print}' "$skill_md")
  [ -z "$fm" ] && continue

  # Parse the `phases:` line directly. We do NOT pipe the full front-matter
  # through yq because SKILL.md descriptions are typically long unquoted
  # strings with embedded colons (`Use whenever...: ...`), which yq parses
  # as nested mapping keys and rejects. Parsing one line with grep+sed is
  # both more robust and faster.
  #
  # Only the inline-list form is supported: `phases: [a, b]`. Block form
  # (`phases:` followed by `  - a` lines) is intentionally not supported —
  # the project convention is inline form (see CLAUDE.md skill convention).
  phases_line=$(echo "$fm" | grep -E '^[[:space:]]*phases:[[:space:]]*\[' | head -1)

  # Absent → always-on (skip — no override written).
  [ -z "$phases_line" ] && continue

  # Extract comma-separated list from inside the brackets.
  phases_inner=$(echo "$phases_line" \
    | sed -E 's/^[[:space:]]*phases:[[:space:]]*\[//; s/\][[:space:]]*$//')

  setting="off"
  IFS=','
  for p in $phases_inner; do
    p_trimmed=$(echo "$p" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    if [ "$p_trimmed" = "$phase" ]; then
      setting="on"
      break
    fi
  done
  unset IFS

  overrides_json=$(echo "$overrides_json" \
    | jq --arg name "$skill_name" --arg val "$setting" '. + {($name): $val}')
done
shopt -u nullglob

# No skills declare phases → exit silently (nothing to override).
if [ "$overrides_json" = "{}" ]; then
  exit 0
fi

# --- 5. Merge into settings.local.json (preserve other keys) ---------------

mkdir -p "$(dirname "$settings_local")"
if [ -f "$settings_local" ]; then
  current=$(cat "$settings_local")
else
  current='{}'
fi

new_content=$(echo "$current" \
  | jq --argjson o "$overrides_json" '. + {skillOverrides: $o}')

# Idempotent: only write if something changed.
if [ "$new_content" = "$current" ]; then
  exit 0
fi

echo "$new_content" | jq '.' > "$settings_local"

echo "Forge phase-scope-skills: phase=$phase, settings.local.json updated. Restart Claude Code to apply the new skill set." >&2

exit 0
