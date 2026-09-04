#!/usr/bin/env bash
#
# Dashboard regen hook — keeps .forge/dashboard/{tracker.js, signals.js} in sync
# with the source of truth. Runs in TWO modes (issue #32):
#
#   1. PostToolUse (Edit|Write|MultiEdit) — reacts to the edited file:
#        .forge/tracker.yaml  → tracker.js  (verbatim mirror of the YAML)
#        .forge/lessons.md     → signals.js  (lessons cadence, S6)
#   2. Stop (no tool_input.file_path) — a STALENESS check: regenerate whichever
#      output is older than its source. This catches writes that never fire an
#      Edit/Write hook — Bash `yq -i` tracker mutations (wave-mode / bug delivery)
#      and worktree-session edits — so the dashboard can't silently drift.
#      Wire this script into BOTH the PostToolUse Edit matcher AND the Stop event.
#
# Note: the dashboard's Bugs and Rework signals are computed BROWSER-SIDE from
# window.TRACKER — they need no precomputation here. The only signal that must be
# precomputed is lessons cadence, because the browser can't read sibling markdown
# under file://.
#
# Contract:
#   - Exit 0 always; this hook never blocks.
#   - Fails open (one-line stderr note) if yq / Python 3 is missing.
#   - No-op if .forge/dashboard/ doesn't exist (dashboard not adopted — also the
#     app-repo-worktree-session case, where CLAUDE_PROJECT_DIR has no dashboard).
#   - Silent on success.
#
# Source: .forge/tracker.yaml + .forge/lessons.md
# Output: .forge/dashboard/tracker.js + .forge/dashboard/signals.js

set -u

# CLAUDE_PROJECT_DIR is set for real tool/Stop invocations; default to cwd so an
# ad-hoc/manual run doesn't abort under `set -u`.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
tracker="$PROJECT_DIR/.forge/tracker.yaml"
lessons="$PROJECT_DIR/.forge/lessons.md"
dashboard_dir="$PROJECT_DIR/.forge/dashboard"

# No dashboard adopted (or an app-repo worktree session) → nothing to do.
[ -d "$dashboard_dir" ] || exit 0

# Support both yq variants:
#   mikefarah/yq (brew install yq)  — needs `-o=json` to emit JSON
#   kislyuk/yq  (pip install yq)    — jq wrapper; outputs JSON natively with identity filter
if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q "mikefarah"; then
  yq_json() { yq -o=json . "$1"; }
else
  yq_json() { yq '.' "$1"; }
fi

do_regen_tracker() {
  [ -f "$tracker" ] || return 0
  if ! command -v yq >/dev/null 2>&1; then
    echo "Forge dashboard regen: yq missing; tracker.js not refreshed. Install mikefarah/yq ('brew install yq') or kislyuk/yq ('pip install yq')." >&2
    return 0
  fi
  {
    printf '/* Generated from ../tracker.yaml by hooks/regen-tracker-dashboard.sh. Do not edit. */\n'
    printf 'window.TRACKER = '
    yq_json "$tracker"
    printf ';\n'
  } > "$dashboard_dir/tracker.js"
}

do_regen_signals() {
  # signals.js carries the one signal the browser can't compute under file://
  # (it can't fetch sibling markdown): the lessons cadence. Schema:
  #
  #   window.SIGNALS = {
  #     generated_at: "<ISO>",
  #     lessons: {
  #       weekly: [ { week_start: "YYYY-MM-DD", count: N }, ... ],  // last 4 ISO weeks, newest last
  #       undated_total: N                                          // legacy/undated fallback
  #     }
  #   }
  #
  # Prefer `python3`; fall back to a `python` that IS Python 3 (many hosts, e.g.
  # Windows, ship only `python`). A Python-2 `python` must NOT be used — it would
  # error and truncate signals.js — so the fallback is version-gated.
  local py=""
  if command -v python3 >/dev/null 2>&1; then
    py=python3
  elif command -v python >/dev/null 2>&1 && python -c 'import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
    py=python
  fi

  if [ -n "$py" ]; then
    PROJECT_DIR="$PROJECT_DIR" "$py" - <<'PY' > "$dashboard_dir/signals.js"
import json, os, re, sys
from datetime import datetime, timedelta, timezone

root = os.environ["PROJECT_DIR"]
forge = os.path.join(root, ".forge")
lessons_path = os.path.join(forge, "lessons.md")

# Lessons cadence (S6): weekly count over the last 4 ISO weeks. A lesson's date
# comes from a dated heading `### YYYY-MM-DD — title` OR, for the reflect/template
# shape `## L-NNN — title`, from the entry's body `**Date:** YYYY-MM-DD` line
# (issue #32 — the emitter wrote `## L-NNN` + body Date while the parser only read
# dated `###` headings, so cadence always read zero). An entry whose date is
# missing or unparseable falls back to undated_total so it never silently vanishes.
dated_re    = re.compile(r"^###\s+(\d{4}-\d{2}-\d{2})\b")
heading_re  = re.compile(r"^#{2,}\s+[A-Za-z][\w-]*\s+[—–-]\s")  # lesson heading: `## L-001 — ...`
bodydate_re = re.compile(r"^\s*[-*]?\s*\*\*Date:\*\*\s*(\d{4}-\d{2}-\d{2})\b")

now = datetime.now(timezone.utc).date()
monday = now - timedelta(days=now.weekday())
weeks = [{"week_start": (monday - timedelta(weeks=(3 - i))).isoformat(), "count": 0} for i in range(4)]
undated_total = 0


def place(dstr):
    # True = placed in a week bucket; False = valid date but out of the window;
    # None = unparseable.
    try:
        d = datetime.strptime(dstr, "%Y-%m-%d").date()
    except ValueError:
        return None
    wk = (d - timedelta(days=d.weekday())).isoformat()
    for w in weeks:
        if w["week_start"] == wk:
            w["count"] += 1
            return True
    return False


if os.path.isfile(lessons_path):
    with open(lessons_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    n = len(lines)
    i = 0
    while i < n:
        line = lines[i]
        dm = dated_re.match(line)
        if dm:
            if place(dm.group(1)) is None:
                undated_total += 1
            i += 1
            continue
        if heading_re.match(line):
            # a `## L-NNN — title` lesson heading: find its body `**Date:**` before
            # the next lesson heading.
            date_str = None
            j = i + 1
            while j < n and not dated_re.match(lines[j]) and not heading_re.match(lines[j]):
                bm = bodydate_re.match(lines[j])
                if bm:
                    date_str = bm.group(1)
                    break
                j += 1
            if date_str is None or place(date_str) is None:
                undated_total += 1
            i += 1
            continue
        i += 1

payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "lessons": {"weekly": weeks, "undated_total": undated_total},
}

sys.stdout.write("/* Generated by hooks/regen-tracker-dashboard.sh. Do not edit. */\n")
sys.stdout.write("window.SIGNALS = ")
json.dump(payload, sys.stdout, indent=2)
sys.stdout.write(";\n")
PY
  else
    # No Python 3 — emit a minimal placeholder so the dashboard renders S6
    # as "no data" instead of erroring.
    {
      printf '/* Generated by hooks/regen-tracker-dashboard.sh. Do not edit. */\n'
      printf 'window.SIGNALS = { "generated_at": null, "lessons": { "weekly": [], "undated_total": 0 } };\n'
    } > "$dashboard_dir/signals.js"
    echo "Forge dashboard regen: no Python 3 (python3/python) found; signals.js emitted as empty placeholder." >&2
  fi
}

# --- dispatch ----------------------------------------------------------------

regen_tracker=0
regen_signals=0

file=$(jq -r '.tool_input.file_path // ""' 2>/dev/null || printf '')
file=${file//\\//}   # normalize Windows backslash paths so the globs match (issue #32)

if [ -n "$file" ]; then
  # PostToolUse mode — react to the specific edited file.
  case "$file" in
    *".forge/tracker.yaml") regen_tracker=1 ;;
    *".forge/lessons.md")   regen_signals=1 ;;
    *) exit 0 ;;
  esac
else
  # Stop mode (no file_path) — self-heal on staleness: regenerate any output older
  # than its source. Catches Bash `yq -i` / worktree writes that fire no Edit hook.
  if [ -f "$tracker" ] && { [ ! -e "$dashboard_dir/tracker.js" ] || [ "$tracker" -nt "$dashboard_dir/tracker.js" ]; }; then
    regen_tracker=1
  fi
  if [ -f "$lessons" ] && { [ ! -e "$dashboard_dir/signals.js" ] || [ "$lessons" -nt "$dashboard_dir/signals.js" ]; }; then
    regen_signals=1
  fi
  [ "$regen_tracker" = 0 ] && [ "$regen_signals" = 0 ] && exit 0
fi

[ "$regen_tracker" = 1 ] && do_regen_tracker
[ "$regen_signals" = 1 ] && do_regen_signals
exit 0
