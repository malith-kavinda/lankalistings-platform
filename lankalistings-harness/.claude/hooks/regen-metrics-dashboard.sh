#!/usr/bin/env bash
#
# PostToolUse hook — Edit/Write/MultiEdit matcher. Registered AFTER
# regen-tracker-dashboard.sh so metrics.js refreshes alongside tracker.js.
#
# Derives the dashboard's Delivery Metrics data file from the append-only
# estimation ledgers:
#
#   .forge/metrics/events.jsonl
#   .forge/metrics/agent-runs.jsonl
#   .forge/metrics/estimation-snapshots.jsonl
#        → .forge/dashboard/metrics.js   (window.METRICS = {...})
#
# Trigger: fires when EITHER .forge/tracker.yaml OR any .forge/metrics/*.jsonl
# is edited. Coupling to tracker.yaml (edited frequently during delivery) keeps
# metrics.js fresh even though ledger *appends* via Bash `>>` don't fire
# Edit/Write hooks.
#
# Contract (identical posture to regen-tracker-dashboard.sh):
#   - Exit 0 always; this hook never blocks.
#   - Fails open (one-line stderr note) if jq is missing.
#   - No-op if .forge/dashboard/ doesn't exist (dashboard not adopted).
#   - No/empty ledgers → explicit empty state ({ "empty": true }).
#   - A malformed ledger line is dropped, not fatal (fail-open per row).
#   - Silent on success.

set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "Forge metrics regen: jq missing; metrics.js not refreshed. Install jq." >&2
  exit 0
fi

file=$(jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -z "$file" ] && exit 0

# Only react to tracker edits or metrics-ledger edits.
case "$file" in
  *".forge/tracker.yaml")        ;;
  *".forge/metrics/"*".jsonl")   ;;
  *) exit 0 ;;
esac

metrics_dir="$CLAUDE_PROJECT_DIR/.forge/metrics"
dashboard_dir="$CLAUDE_PROJECT_DIR/.forge/dashboard"
out="$dashboard_dir/metrics.js"

[ -d "$dashboard_dir" ] || exit 0

# Parse a JSONL ledger into a JSON array, dropping unparseable lines
# (fail-open per row). Missing/empty file → [].
read_ledger() {
  local f="$1"
  [ -f "$f" ] || { printf '[]'; return; }
  jq -R 'fromjson? | select(type == "object") // empty' "$f" 2>/dev/null | jq -s '.' 2>/dev/null || printf '[]'
}

events=$(read_ledger "$metrics_dir/events.jsonl")
runs=$(read_ledger "$metrics_dir/agent-runs.jsonl")
snaps=$(read_ledger "$metrics_dir/estimation-snapshots.jsonl")

[ -z "$events" ] && events='[]'
[ -z "$runs" ]   && runs='[]'
[ -z "$snaps" ]  && snaps='[]'

ts_now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
window_days="${FORGE_METRICS_WINDOW_DAYS:-14}"   # rolling throughput window; override via env

agg=$(jq -n \
  --argjson events "$events" \
  --argjson runs "$runs" \
  --argjson snaps "$snaps" \
  --arg now "$ts_now" \
  --argjson win "$window_days" '
  def med: map(select(. != null)) | sort
    | if length == 0 then null
      elif (length % 2) == 1 then .[(length/2)|floor]
      else ((.[length/2 - 1] + .[length/2]) / 2) end;
  def round1: if . == null then null else (. * 10 | round) / 10 end;

  # All date parsing uses fromdateiso8601? so a malformed/missing ts drops that
  # row rather than erroring the whole aggregation (fail-open per row).
  ($now | fromdateiso8601) as $nowS |
  ($nowS - ($win * 86400)) as $cut |

  # feature_started (first /forge-deliver invocation) + spec_approved, per ticket
  ([ $events[] | select(.event == "feature_started") | {t: .ticket, s: (.ts | fromdateiso8601?)} | select(.s != null) ]) as $starts |
  def startOf($t): ([ $starts[] | select(.t == $t) | .s ])[0];
  ([ $events[] | select(.event == "spec_approved") | {t: .ticket, s: (.ts | fromdateiso8601?)} | select(.s != null) ]) as $specs |
  def specOf($t): ([ $specs[] | select(.t == $t) | .s ])[0];

  # wave merges grouped by ticket, ordered by wave number
  ([ $events[] | select(.event == "wave_merged") | {t: .ticket, w: .wave, m: (.ts | fromdateiso8601?)} | select(.m != null) ]
    | group_by(.t) | map(sort_by(.w))) as $byticket |

  # incremental per-wave cycle hours: wave 1 from spec_approved (decomp+build ramp),
  # later waves from the previous wave merge (build only)
  ([ $byticket[] | . as $arr | specOf($arr[0].t) as $spec | select($spec != null)
     | range(0; ($arr | length)) as $i
     | { first: ($i == 0),
         hours: ((if $i == 0 then ($arr[0].m - $spec) else ($arr[$i].m - $arr[$i-1].m) end) / 3600) } ]
  ) as $wavecycles |

  # spec authoring hours: feature_started -> spec_approved
  ([ $specs[] | startOf(.t) as $st | select($st != null) | (.s - $st) / 3600 ]) as $spec_hours |

  # feature cycle days: feature_started -> feature_done (full lead time, incl. authoring)
  ([ $events[] | select(.event == "feature_done") | {t: .ticket, f: (.ts | fromdateiso8601?)} | select(.f != null)
     | startOf(.t) as $st | select($st != null) | (.f - $st) / 86400 ]) as $feat_days |

  ($events | length) as $ec |
  ($runs | length) as $rc |
  ($snaps | length) as $sc |
  ($events | map(select(.event == "feature_done"))) as $fdone |
  ($events | map(select(.event == "wave_merged")))  as $wmerged |
  {
    schema: "forge-metrics/v1",
    generated_at: $now,
    window_days: $win,
    empty: (($ec + $rc + $sc) == 0),
    events: {
      total: $ec,
      features_done: ($fdone | length),
      waves_merged:  ($wmerged | length),
      wave_prs_opened: ($events | map(select(.event == "wave_pr_opened")) | length),
      wi_dispatched: ($events | map(select(.event == "wi_dispatched")) | length)
    },
    agent_runs: {
      total: $rc,
      repairs: ($runs | map(select((.repair_of != null) or (.dispatch_mode == "test-fix") or ((.attempt // 1) > 1))) | length),
      by_role: ($runs | group_by(.agent_role)
        | map({ role: (.[0].agent_role // "unknown"), count: length })
        | sort_by(-.count))
    },
    snapshots: {
      count: $sc,
      median_workitems:  ($snaps | map(.workitems) | med),
      median_agent_runs: ($snaps | map(.agent_runs) | med)
    },
    cycle: {
      median_spec_hours:       ($spec_hours | med | round1),
      median_wave1_hours:      ([ $wavecycles[] | select(.first)       | .hours ] | med | round1),
      median_later_wave_hours: ([ $wavecycles[] | select(.first | not) | .hours ] | med | round1),
      median_feature_days:     ($feat_days | med | round1),
      later_wave_count:        ([ $wavecycles[] | select(.first | not) ] | length)
    },
    throughput: {
      window_days: $win,
      features_in_window: ($fdone | map(select((.ts | fromdateiso8601?) >= $cut)) | length),
      waves_in_window:    ($wmerged | map(select((.ts | fromdateiso8601?) >= $cut)) | length),
      features_per_day: (($fdone | map(select((.ts | fromdateiso8601?) >= $cut)) | length) / $win | round1),
      waves_per_day:    (($wmerged | map(select((.ts | fromdateiso8601?) >= $cut)) | length) / $win | round1)
    }
  }' 2>/dev/null)

if [ -z "$agg" ]; then
  # jq aggregation failed for some reason — emit a safe empty state rather
  # than leaving a stale or broken file.
  printf 'window.METRICS = { "schema": "forge-metrics/v1", "empty": true, "reason": "aggregation failed" };\n' > "$out" 2>/dev/null || true
  echo "Forge metrics regen: jq aggregation failed; metrics.js set to empty state." >&2
  exit 0
fi

out_tmp="$out.tmp.$$"
if printf '/* Generated from ../metrics/*.jsonl by hooks/regen-metrics-dashboard.sh. Do not edit. */\nwindow.METRICS = %s;\n' "$agg" > "$out_tmp" 2>/dev/null; then
  mv "$out_tmp" "$out"
else
  rm -f "$out_tmp" 2>/dev/null
  echo "Forge metrics regen: failed to write metrics.js." >&2
fi

exit 0
