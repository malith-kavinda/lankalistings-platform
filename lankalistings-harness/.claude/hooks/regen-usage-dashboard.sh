#!/usr/bin/env bash
#
# Stop hook (registered AFTER track-token-usage.sh) — derives two
# project-scoped artifacts from ~/.claude/forge-usage.jsonl:
#
#   <harness>/.forge/usage.jsonl          → primary developer interface
#                                            (raw filtered rows, deduped
#                                             by assistant_message_id)
#   <harness>/.forge/dashboard/usage.js   → window.USAGE = {...} for the
#                                            HTML dashboard panel
#
# Per spec FR-8 + FR-10:
#   - Both artifacts regenerate on every Stop event in a Forge project.
#   - Both are gitignored (per-developer-per-machine state, not shared).
#   - Outside a Forge project (no .forge/ in cwd ancestry) → exit 0.
#   - All errors swallowed → exit 0; details to ~/.claude/forge-usage.error.log.
#
# Performance: jq slurp (-s) is used for filter+dedup since project-
# scoped row count stays small even when the global file grows.

set -u

ERR_LOG="$HOME/.claude/forge-usage.error.log"
GLOBAL_USAGE="$HOME/.claude/forge-usage.jsonl"

mkdir -p "$HOME/.claude" 2>/dev/null || true

log_err() {
  printf '[%s] regen-usage-dashboard: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$ERR_LOG" 2>/dev/null || true
}

# --- 1. Read stdin (Stop event JSON) --------------------------------------

stdin_json=""
if [ ! -t 0 ]; then
  stdin_json=$(cat)
fi
if [ -z "$stdin_json" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  log_err "jq missing; cannot regen mirror or dashboard"
  exit 0
fi

cwd=$(printf '%s' "$stdin_json" | jq -r '.cwd // ""' 2>/dev/null)
if [ -z "$cwd" ]; then
  log_err "Stop event missing cwd; cannot determine project"
  exit 0
fi

# --- 2. Find harness root (walk up looking for .forge/) --------------------
#
# Mirrors the walk in track-token-usage.sh. Inlined (not extracted to
# .claude/lib/) because the logic is ~10 lines and only two consumers exist.

harness_root=""
dir="$cwd"
for _ in $(seq 20); do
  if [ -d "$dir/.forge" ]; then
    harness_root="$dir"
    break
  fi
  parent=$(dirname "$dir")
  [ "$parent" = "$dir" ] && break
  dir="$parent"
done

# Outside any Forge project — nothing to regen
if [ -z "$harness_root" ]; then
  exit 0
fi

project_name=$(basename "$harness_root")
mirror="$harness_root/.forge/usage.jsonl"
dashboard_dir="$harness_root/.forge/dashboard"
dashboard_js="$dashboard_dir/usage.js"

# --- 3. Handle missing global file ----------------------------------------
#
# First-ever Stop event before track-token-usage.sh has written anything.
# Write empty mirror + empty dashboard so callers don't see staleness.

if [ ! -f "$GLOBAL_USAGE" ]; then
  : > "$mirror" 2>/dev/null || true
  if [ -d "$dashboard_dir" ]; then
    printf 'window.USAGE = { "empty": true, "reason": "no global usage file yet" };\n' > "$dashboard_js" 2>/dev/null || true
  fi
  exit 0
fi

# --- 4. Filter + dedup ----------------------------------------------------
#
# Filter rows where project_path matches the full harness root path (not
# project_name basename — two projects can share a basename, see PR #4
# review comment). Dedup by assistant_message_id per NFR-4.
#
# Performance: grep -F pre-filter scopes the jq -s slurp to lines matching
# this project path. Without it, jq slurps the whole global file into
# memory before filtering — pause grows linearly with global file size.
# grep is a byte scan (O(n) cheap); jq parses only the matched lines
# (O(project rows) — bounded and small). (Addresses PR #4 review comment
# "full global file loaded into memory on every Stop event".)
#
# Legacy v0.18.0 rows lack project_path — they fall through this filter
# silently. Acceptable: v0.18.0 was live for hours before v0.18.1; the
# dropped data is per-developer local. New rows from v0.18.1+ all carry
# project_path.

filtered=$(grep -F "\"project_path\":\"$harness_root\"" "$GLOBAL_USAGE" 2>/dev/null \
  | jq -s 'unique_by(.assistant_message_id)' 2>/dev/null)

if [ -z "$filtered" ] || [ "$filtered" = "null" ]; then
  # Empty filter result is normal on first run for a fresh project.
  # Write empty mirror + sentinel dashboard so downstream consumers see "no data."
  : > "$mirror" 2>/dev/null || true
  if [ -d "$dashboard_dir" ]; then
    printf 'window.USAGE = { "empty": true, "reason": "no rows yet for project_path %s" };\n' \
      "$harness_root" > "$dashboard_js" 2>/dev/null || true
  fi
  exit 0
fi

# --- 5. Write raw mirror (JSONL, one row per line) ------------------------

mirror_tmp="$mirror.tmp.$$"
if printf '%s' "$filtered" | jq -c '.[]' > "$mirror_tmp" 2>/dev/null; then
  mv "$mirror_tmp" "$mirror"
else
  rm -f "$mirror_tmp" 2>/dev/null
  log_err "jq -c .[] failed; mirror not updated"
fi

# --- 6. Write dashboard usage.js (aggregated) -----------------------------
#
# Only if the dashboard directory exists. Some projects may not have it
# (e.g., templates not yet synced); skip gracefully.

if [ ! -d "$dashboard_dir" ]; then
  exit 0
fi

ts_now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

agg=$(printf '%s' "$filtered" | jq --arg p "$project_name" --arg now "$ts_now" '
  . as $rows |
  {
    project: $p,
    last_updated: $now,
    total_rows: ($rows | length),
    totals: {
      input_tokens: ($rows | map(.input_tokens // 0) | add // 0),
      output_tokens: ($rows | map(.output_tokens // 0) | add // 0),
      cache_read_tokens: ($rows | map(.cache_read_tokens // 0) | add // 0),
      cache_creation_tokens: ($rows | map(.cache_creation_tokens // 0) | add // 0),
      turns: ($rows | length)
    },
    by_phase: ($rows | group_by(.phase) | map({
      phase: (.[0].phase // "unknown"),
      input_tokens: (map(.input_tokens // 0) | add),
      output_tokens: (map(.output_tokens // 0) | add),
      cache_read_tokens: (map(.cache_read_tokens // 0) | add),
      cache_creation_tokens: (map(.cache_creation_tokens // 0) | add),
      turns: length
    }) | sort_by(-.input_tokens - .output_tokens)),
    by_day: ($rows | group_by(.ts | .[0:10]) | map({
      day: (.[0].ts | .[0:10]),
      input_tokens: (map(.input_tokens // 0) | add),
      output_tokens: (map(.output_tokens // 0) | add),
      cache_read_tokens: (map(.cache_read_tokens // 0) | add),
      cache_creation_tokens: (map(.cache_creation_tokens // 0) | add),
      turns: length
    }) | sort_by(.day)),
    by_user: ($rows | group_by(.user_email) | map({
      user_email: (.[0].user_email // "unknown"),
      input_tokens: (map(.input_tokens // 0) | add),
      output_tokens: (map(.output_tokens // 0) | add),
      cache_read_tokens: (map(.cache_read_tokens // 0) | add),
      cache_creation_tokens: (map(.cache_creation_tokens // 0) | add),
      turns: length
    }) | sort_by(-.input_tokens - .output_tokens)),
    by_model: ($rows | group_by(.model) | map({
      model: (.[0].model // "unknown"),
      input_tokens: (map(.input_tokens // 0) | add),
      output_tokens: (map(.output_tokens // 0) | add),
      cache_read_tokens: (map(.cache_read_tokens // 0) | add),
      cache_creation_tokens: (map(.cache_creation_tokens // 0) | add),
      turns: length
    }) | sort_by(-.input_tokens - .output_tokens))
  }' 2>/dev/null)

if [ -z "$agg" ]; then
  log_err "jq aggregation failed; dashboard not updated"
  exit 0
fi

dashboard_tmp="$dashboard_js.tmp.$$"
if printf 'window.USAGE = %s;\n' "$agg" > "$dashboard_tmp" 2>/dev/null; then
  mv "$dashboard_tmp" "$dashboard_js"
else
  rm -f "$dashboard_tmp" 2>/dev/null
  log_err "failed to write dashboard usage.js"
fi

exit 0
