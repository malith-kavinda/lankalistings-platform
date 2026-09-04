#!/usr/bin/env bash
#
# Stop hook — captures per-turn token usage from the active Claude Code
# session and appends one JSONL row to ~/.claude/forge-usage.jsonl.
#
# Per spec docs/specs/2026-05-14-token-usage-tracking.md (Subtask 2):
#   - Reads every assistant turn's `usage` block from the session JSONL
#     Claude Code writes to ~/.claude/projects/<cwd>/<sid>.jsonl, dedupes
#     against rows already written for this session, and appends one row
#     per new turn (multi-turn fix from validation in v0.18.0).
#   - Tags each row with: ts, session_id, assistant_message_id,
#     user_email, project_name, project_path, phase, model, input_tokens,
#     output_tokens, cache_read_tokens, cache_creation_tokens.
#   - `project_name` is the basename of harness_root (display label);
#     `project_path` is the full absolute path (unambiguous key — two
#     projects can share a basename, see v0.18.1 fix).
#   - Phase is derived via the shared helper at .claude/lib/derive-phase.sh
#     so this hook and phase-scope-skills.sh stay aligned.
#   - All errors are swallowed → exit 0; details go to
#     ~/.claude/forge-usage.error.log. The hook MUST NOT block a session.
#
# Contract (v0.18.1 — addresses PR #4 review findings):
#   - Exit 0 always.
#   - Append-only writes under a POSIX-portable mkdir-based lock
#     (NFR-2). Works on macOS, Linux, BSD without external `flock(1)`.
#   - < 200ms overhead target (NFR-1) — bounded by: (a) full session
#     JSONL scan with jq filter (typical session <200 lines); (b) a
#     grep-pre-filter over the global file scoped to this session_id
#     before jq parses the matches (O(n) byte scan, O(turns) JSON parse).
#     Profile if global file crosses ~50MB or sessions cross ~500 turns.
#   - Outside a Forge harness (no .forge/ in cwd ancestry): row is still
#     written with project_name="<non-forge>", project_path="<non-forge>",
#     phase="n/a" (FR-4, FR-5).
#
# Field-name mapping (Anthropic API → row schema):
#   - cache_read_input_tokens     → cache_read_tokens
#   - cache_creation_input_tokens → cache_creation_tokens

ERR_LOG="$HOME/.claude/forge-usage.error.log"
USAGE_FILE="$HOME/.claude/forge-usage.jsonl"
LOCK_DIR="$HOME/.claude/forge-usage.lockdir"

mkdir -p "$HOME/.claude" 2>/dev/null || true

log_err() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$ERR_LOG" 2>/dev/null || true
}

# --- 1. Read stdin (Stop event JSON) ---------------------------------------

stdin_json=""
if [ ! -t 0 ]; then
  stdin_json=$(cat)
fi

if [ -z "$stdin_json" ]; then
  log_err "no stdin received (hook called outside Claude Code?); skipping row"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  log_err "jq missing; cannot parse Stop event or build row. Install jq."
  exit 0
fi

session_id=$(printf '%s' "$stdin_json" | jq -r '.session_id // ""' 2>/dev/null)
cwd=$(printf '%s' "$stdin_json" | jq -r '.cwd // ""' 2>/dev/null)

if [ -z "$session_id" ] || [ -z "$cwd" ]; then
  log_err "Stop event missing session_id or cwd: $(printf '%s' "$stdin_json" | head -c 200)"
  exit 0
fi

# --- 2. Locate session JSONL ----------------------------------------------
#
# Claude Code writes per-session transcripts to:
#   ~/.claude/projects/<encoded-cwd>/<session_id>.jsonl
# where encoded-cwd is the cwd with `/` replaced by `-` (verified against
# ~/.claude/projects/ on a real machine, 2026-05-14).

encoded_cwd=$(printf '%s' "$cwd" | sed 's|/|-|g')
session_file="$HOME/.claude/projects/$encoded_cwd/$session_id.jsonl"

if [ ! -f "$session_file" ]; then
  log_err "session JSONL not found at $session_file (cwd=$cwd, session_id=$session_id)"
  exit 0
fi

# --- 3. Extract ALL assistant turns' usage --------------------------------
#
# Every API call within a Claude Code session — including a sub-agent's many
# internal Read/Grep/etc. tool round-trips — produces its own `usage` block
# in the session JSONL. A single Stop event can cover dozens of such turns
# (a single spec-reviewer invocation was empirically measured at 89 turns).
#
# Earlier versions of this hook captured only the LAST usage block per Stop,
# which silently dropped ~98% of sub-agent token data. The fix: extract every
# assistant message's usage block, then dedup against rows already written
# for this session_id (so each Stop only appends what's new since last fire).

all_messages=$(jq -c 'select(.type=="assistant" and .message.usage) | {
  uuid,
  model: (.message.model // "unknown"),
  input_tokens: (.message.usage.input_tokens // 0),
  output_tokens: (.message.usage.output_tokens // 0),
  cache_read_tokens: (.message.usage.cache_read_input_tokens // 0),
  cache_creation_tokens: (.message.usage.cache_creation_input_tokens // 0)
}' "$session_file" 2>/dev/null)

if [ -z "$all_messages" ]; then
  # No assistant turn with usage in the session yet — empty session or
  # tool-only stop. Not an error; just nothing to record.
  exit 0
fi

# Dedup against assistant_message_ids we've already written for this session.
# Re-reading the same uuid each Stop is the failure mode this prevents.
#
# Performance: grep -F pre-filter scopes the jq parse to lines matching this
# session_id. Without this, we'd jq-parse every row in the global file (which
# accumulates indefinitely across all projects). grep is a byte-level scan;
# jq is JSON-parsing — orders of magnitude faster pre-filter. (Addresses PR #4
# review comment "O(n) global file scan on every Stop event".)
existing_uuids_json='[]'
if [ -f "$USAGE_FILE" ]; then
  existing_uuids_json=$(grep -F "\"session_id\":\"$session_id\"" "$USAGE_FILE" 2>/dev/null \
    | jq -r '.assistant_message_id // empty' 2>/dev/null \
    | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null)
  [ -z "$existing_uuids_json" ] && existing_uuids_json='[]'
fi

new_messages=$(printf '%s' "$all_messages" \
  | jq -c --argjson existing "$existing_uuids_json" \
      'select(.uuid as $u | ($existing | index($u)) | not)' 2>/dev/null)

if [ -z "$new_messages" ]; then
  # All messages in the session already captured. Idempotent no-op.
  exit 0
fi

# --- 4. Find harness root (walk up looking for .forge/) -------------------

harness_root=""
dir="$cwd"
# Cap at 20 levels to bound the walk (deep nesting + safety against loops).
for _ in $(seq 20); do
  if [ -d "$dir/.forge" ]; then
    harness_root="$dir"
    break
  fi
  parent=$(dirname "$dir")
  [ "$parent" = "$dir" ] && break
  dir="$parent"
done

# --- 5. Resolve project_name + project_path + phase -----------------------
#
# `project_name` is basename (display label); `project_path` is the full
# absolute path (unambiguous key — two projects can share a basename, e.g.
# ~/client-a/myproject-harness and ~/client-b/myproject-harness both yield
# the same basename but are distinct projects). Filter logic in
# regen-usage-dashboard.sh uses `project_path` to avoid blending two
# projects' data. (Addresses PR #4 review comment "project_name key
# collision if two projects share a directory name".)

if [ -n "$harness_root" ]; then
  project_name=$(basename "$harness_root")
  project_path="$harness_root"
else
  project_name="<non-forge>"
  project_path="<non-forge>"
fi

phase="n/a"
derive_lib=""
if [ -n "$harness_root" ] && [ -f "$harness_root/.claude/lib/derive-phase.sh" ]; then
  derive_lib="$harness_root/.claude/lib/derive-phase.sh"
elif [ -f "$cwd/.claude/lib/derive-phase.sh" ]; then
  derive_lib="$cwd/.claude/lib/derive-phase.sh"
fi

if [ -n "$derive_lib" ]; then
  # shellcheck disable=SC1090
  . "$derive_lib"
  phase=$(derive_phase "$harness_root" 2>/dev/null || echo "n/a")
  [ -z "$phase" ] && phase="n/a"
fi

# --- 6. Resolve user_email ------------------------------------------------
#
# Priority: env override > git config > $USER fallback.

user_email="${FORGE_USAGE_USER_EMAIL:-}"
if [ -z "$user_email" ]; then
  user_email=$(git -C "$cwd" config user.email 2>/dev/null || true)
fi
if [ -z "$user_email" ]; then
  user_email="${USER:-unknown}"
fi

# --- 7. Build JSONL rows --------------------------------------------------
#
# One row per new assistant message. ts is the Stop-event time (shared across
# all rows in this batch — fine for daily/weekly rollups; the file order
# preserves the per-turn sequence within a session). session_id, user_email,
# project_name, phase are constant across the batch; model is per-message.

ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

rows=$(printf '%s' "$new_messages" \
  | jq -c \
      --arg ts "$ts" \
      --arg session_id "$session_id" \
      --arg user_email "$user_email" \
      --arg project_name "$project_name" \
      --arg project_path "$project_path" \
      --arg phase "$phase" \
      '{
        ts: $ts,
        session_id: $session_id,
        assistant_message_id: .uuid,
        user_email: $user_email,
        project_name: $project_name,
        project_path: $project_path,
        phase: $phase,
        model: .model,
        input_tokens: .input_tokens,
        output_tokens: .output_tokens,
        cache_read_tokens: .cache_read_tokens,
        cache_creation_tokens: .cache_creation_tokens
      }' 2>/dev/null)

if [ -z "$rows" ]; then
  log_err "failed to build JSON rows (jq error). new_messages_first_line=$(printf '%s' "$new_messages" | head -1)"
  exit 0
fi

# --- 8. Append all new rows under POSIX-portable mkdir lock ---------------
#
# Earlier versions used flock(1), but that's a Linux-only utility from the
# util-linux package — absent on macOS by default. On macOS the flock branch
# silently fell through to a bare append, dropping NFR-2's concurrent-write
# guarantee on the primary developer platform.
#
# mkdir is required by POSIX to be atomic: only one concurrent process can
# successfully create a given directory. Works on macOS, Linux, and BSD with
# no external dependencies. Each row is < PIPE_BUF (4096 bytes) so single-row
# appends are atomic regardless; multi-row batches need the lock to prevent
# interleaving across concurrent Stop events.
#
# (Addresses PR #4 review comment "flock is not available on macOS by
# default; atomic write guarantee is silently dropped".)

acquired=0
attempts=20
while [ $attempts -gt 0 ]; do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    acquired=1
    break
  fi
  sleep 0.05
  attempts=$((attempts - 1))
done

if [ $acquired -eq 1 ]; then
  printf '%s\n' "$rows" >>"$USAGE_FILE" 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null || true
else
  log_err "lock acquisition failed after 20 attempts (~1s); appending without lock"
  printf '%s\n' "$rows" >>"$USAGE_FILE" 2>/dev/null
fi

exit 0
