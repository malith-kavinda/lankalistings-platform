#!/usr/bin/env bash
#
# Shared helper: harness-native delivery estimation.
#
# Estimation under Forge is NOT human-effort-days. What predicts delivery is the
# feature's *size vector* (waves x work-items) times *measured cycle medians* in
# fractional wall-clock days. This helper owns the deterministic arithmetic; the
# `forge-estimate` skill owns the judgement (predicting the size vector, presenting
# the range + caveats). See docs/engineering/specs/2026-07-16-portfolio-rollup-and-estimation.md.
#
# Invoked-mode (RECOMMENDED — deterministic bash interpreter, works from any
# interactive shell incl. zsh; this is the path Claude should use):
#     bash .claude/lib/forge-estimate.sh baselines
#     bash .claude/lib/forge-estimate.sh range --waves 3 --wis 7
#     bash .claude/lib/forge-estimate.sh range --waves 2 --wis 4 --include-spec false
#     bash .claude/lib/forge-estimate.sh --self-test
#
# Sourceable (BASH ONLY — for bash-shebang hooks/scripts; a zsh `source` will not
# error at the dispatch guard, but path resolution/functions are bash-oriented —
# prefer invoked-mode from an interactive shell):
#     . "<harness-root>/.claude/lib/forge-estimate.sh"
#     forge_estimate_baselines                            # effective per-metric baselines (JSON)
#     forge_estimate_range --waves 3 --wis 7              # deterministic day-range forecast (JSON)
#     forge_estimate_range --waves 2 --wis 4 --include-spec false
#
# --- forge_estimate_baselines --------------------------------------------------
#
# Resolves the EFFECTIVE per-metric baselines. For each of the six metrics: use the
# project's OWN local-ledger median when that metric has >= min_samples (5) own
# samples; otherwise fall back to the baked org-level value from baselines.json.
#
# Own metrics are derived (fractional wall-clock days) from:
#   .forge/metrics/events.jsonl              (forge-metrics/v1 lifecycle events)
#   .forge/metrics/estimation-snapshots.jsonl (forge-metrics/v1 completion rows)
# with these definitions:
#   spec_days         : per ticket, feature_started -> spec_approved
#   wave1_days        : per ticket, spec_approved -> first wave_merged
#   later_wave_days   : consecutive wave_merged deltas within a ticket
#   feature_days      : per ticket, feature_started -> feature_done
#   waves_per_feature : `waves` field from estimation-snapshots rows
#   wis_per_feature   : `workitems` field from estimation-snapshots rows
#
# Output (stdout, JSON): per metric {median, n, source: "project"|"org"}, plus
# baseline_version and generated_at passed through from the baked file. On any
# refusal condition it emits {"error": "..."} and NEVER a fabricated number:
#   - baked file missing / unparseable
#   - baked baseline_version == "uncalibrated" (a fresh template) or all baked n == 0
#
# --- forge_estimate_range ------------------------------------------------------
#
#     forge_estimate_range --waves <N> --wis <M> [--include-spec true|false]   (default true)
#
# Deterministic arithmetic on the effective baselines:
#   remaining(W) = (spec_days if include-spec) + wave1_days + (W-1)*later_wave_days + 1.0
#                                                                    (the +1.0 is ship wrap-up)
#   low_days  = remaining(max(1, waves-1))
#   high_days = remaining(waves+1)
# Output (stdout, JSON): {low_days, high_days, waves, wis, include_spec, basis}
# where basis is the effective baselines object (per-metric source + n +
# baseline_version). Values are rounded to one decimal place. If the baselines
# resolution returned {"error": ...} it is propagated unchanged.
#
# --- Failure posture (matches the other lib helpers) ---------------------------
#
#   - jq is REQUIRED. If it is missing: a clear message to stderr and EMPTY stdout,
#     return 0 (fail open — never abort the caller).
#   - Malformed ledger rows are dropped per-row (never abort the run).
#   - Missing / empty local ledgers -> baked baselines only.
#
# Path resolution (overridable for tests):
#   FORGE_ESTIMATE_BASELINES     baked baselines.json (default: ../skills/forge-estimate/baselines.json)
#   FORGE_ESTIMATE_METRICS_DIR   metrics dir          (default: ../../.forge/metrics)
#   FORGE_ESTIMATE_MIN_SAMPLES   own-override threshold (default: 5)

# NOTE: no `set -u` / `set -e` at top level. This file is sourceable and must
# NOT leak shell options into the caller's interactive shell. Strict mode is
# enabled only in invoked-mode (the dispatch branch), never here. The functions
# are written to be safe with or without `nounset` (every expansion is guarded).

# Absolute path to THIS file, captured at source/exec time. Under bash this is
# BASH_SOURCE[0]; under a zsh `source` BASH_SOURCE is unset and $0 is the sourced
# file path at top level — so the fallback keeps path resolution working in both.
_FORGE_ESTIMATE_SELF="${BASH_SOURCE[0]:-$0}"

# --- Path resolution -------------------------------------------------------

_forge_estimate_lib_dir() {
  cd -- "$(dirname -- "${_FORGE_ESTIMATE_SELF:-$0}")" 2>/dev/null && pwd
}

_forge_estimate_baked_path() {
  if [ -n "${FORGE_ESTIMATE_BASELINES:-}" ]; then
    printf '%s' "$FORGE_ESTIMATE_BASELINES"
    return 0
  fi
  printf '%s' "$(_forge_estimate_lib_dir)/../skills/forge-estimate/baselines.json"
}

_forge_estimate_metrics_dir() {
  if [ -n "${FORGE_ESTIMATE_METRICS_DIR:-}" ]; then
    printf '%s' "$FORGE_ESTIMATE_METRICS_DIR"
    return 0
  fi
  printf '%s' "$(_forge_estimate_lib_dir)/../../.forge/metrics"
}

# --- Ledger reading (fail-open per row) ------------------------------------
#
# Reads a JSONL file into a JSON array, dropping any line that is not valid JSON
# (the same discipline the regen-metrics-dashboard hook uses). Missing/unreadable
# file -> []. Never aborts.
_forge_estimate_read_jsonl() {
  local f="${1:-}"
  [ -n "$f" ] && [ -f "$f" ] || { printf '[]'; return 0; }
  jq -R -s 'split("\n") | map(select(length > 0)) | map(fromjson? // empty)' "$f" 2>/dev/null \
    || printf '[]'
}

# --- Own-metric derivation from the ledgers --------------------------------
#
# Emits {spec_days:{median,n}, wave1_days:{...}, ...} computed purely from the
# project's own ledgers. Fail-open: on any jq error -> {} (degrades to baked-only).
_forge_estimate_own_metrics() {
  local events_json="${1:-[]}" snaps_json="${2:-[]}"
  jq -n \
    --argjson events "$events_json" \
    --argjson snaps "$snaps_json" '
    def epoch($t): ($t | fromdateiso8601?) // null;
    def days_between($a; $b):
      epoch($a) as $ea | epoch($b) as $eb
      | if ($ea == null) or ($eb == null) then null
        else ($eb - $ea) / 86400 end;
    def median:
      (map(select(. != null)) | sort) as $s
      | ($s | length) as $n
      | if $n == 0 then null
        elif ($n % 2 == 1) then $s[(($n - 1) / 2) | floor]
        else (($s[($n / 2 - 1) | floor]) + ($s[($n / 2) | floor])) / 2
        end;
    def stat($arr):
      { median: ($arr | median), n: ($arr | map(select(. != null)) | length) };

    # Per-ticket rollup of lifecycle events.
    ( $events
      | map(select(((.ticket // null) != null) and ((.event // null) != null)))
      | group_by(.ticket)
      | map({
          ticket: .[0].ticket,
          started:       (map(select(.event == "feature_started") | .ts) | map(select(. != null)) | sort | (.[0] // null)),
          spec_approved: (map(select(.event == "spec_approved")   | .ts) | map(select(. != null)) | sort | (.[0] // null)),
          feature_done:  (map(select(.event == "feature_done")    | .ts) | map(select(. != null)) | sort | (.[0] // null)),
          wave_merges:   (map(select(.event == "wave_merged")     | .ts) | map(select(. != null)) | sort)
        })
    ) as $tix

    | ([ $tix[] | days_between(.started; .spec_approved) ]) as $spec_days
    | ([ $tix[]
          | if ((.spec_approved != null) and ((.wave_merges | length) > 0))
            then days_between(.spec_approved; .wave_merges[0]) else null end
       ]) as $wave1_days
    | ([ $tix[]
          | .wave_merges as $w
          | [ range(1; ($w | length)) as $i | days_between($w[$i - 1]; $w[$i]) ]
       ] | add // []) as $later_wave_days
    | ([ $tix[] | days_between(.started; .feature_done) ]) as $feature_days
    | ([ $snaps[] | .waves     | select(type == "number") ]) as $waves_pf
    | ([ $snaps[] | .workitems | select(type == "number") ]) as $wis_pf

    | {
        spec_days:         stat($spec_days),
        wave1_days:        stat($wave1_days),
        later_wave_days:   stat($later_wave_days),
        feature_days:      stat($feature_days),
        waves_per_feature: stat($waves_pf),
        wis_per_feature:   stat($wis_pf)
      }
  ' 2>/dev/null || printf '{}'
}

# --- Public: effective baselines -------------------------------------------

forge_estimate_baselines() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "forge-estimate: jq not found on PATH; cannot compute baselines" >&2
    return 0
  fi

  local baked_path metrics_dir min
  baked_path=$(_forge_estimate_baked_path)
  metrics_dir=$(_forge_estimate_metrics_dir)
  min="${FORGE_ESTIMATE_MIN_SAMPLES:-5}"

  # --- baked file must exist, parse, and be calibrated ---
  if [ ! -f "$baked_path" ]; then
    jq -n --arg p "$baked_path" \
      '{error: ("baked baselines.json not found at " + $p)}'
    return 0
  fi

  local baked_json
  if ! baked_json=$(jq -c '.' "$baked_path" 2>/dev/null); then
    jq -n --arg p "$baked_path" \
      '{error: ("baked baselines.json is not valid JSON at " + $p)}'
    return 0
  fi

  local uncalibrated
  uncalibrated=$(printf '%s' "$baked_json" | jq -r '
    ((.baseline_version // "uncalibrated") == "uncalibrated")
    or ([.baselines[]?.n // 0] | all(. == 0))
  ' 2>/dev/null)
  if [ "$uncalibrated" = "true" ]; then
    jq -n '{error: "baked baselines.json is uncalibrated (baseline_version=uncalibrated / all n=0); refusing to quote numbers. Run forge-rollup --emit-baselines to calibrate."}'
    return 0
  fi

  # --- own metrics from the local ledgers (fail-open) ---
  local events_json snaps_json own_json
  events_json=$(_forge_estimate_read_jsonl "$metrics_dir/events.jsonl")
  snaps_json=$(_forge_estimate_read_jsonl "$metrics_dir/estimation-snapshots.jsonl")
  own_json=$(_forge_estimate_own_metrics "$events_json" "$snaps_json")
  [ -n "$own_json" ] || own_json='{}'

  # --- merge: own >= min_samples wins per metric, else baked ---
  jq -n \
    --argjson own "$own_json" \
    --argjson baked "$baked_json" \
    --argjson min "$min" '
    def pick($m):
      ($own[$m])            as $o
      | ($baked.baselines[$m]) as $b
      | if (($o.n // 0) >= $min)
        then { median: $o.median, n: $o.n, source: "project" }
        else { median: ($b.median // 0), n: ($b.n // 0), source: "org" }
        end;
    {
      spec_days:         pick("spec_days"),
      wave1_days:        pick("wave1_days"),
      later_wave_days:   pick("later_wave_days"),
      feature_days:      pick("feature_days"),
      waves_per_feature: pick("waves_per_feature"),
      wis_per_feature:   pick("wis_per_feature"),
      baseline_version:  ($baked.baseline_version // null),
      generated_at:      ($baked.generated_at // null)
    }
  '
}

# --- Public: day-range forecast --------------------------------------------

forge_estimate_range() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "forge-estimate: jq not found on PATH; cannot compute a range" >&2
    return 0
  fi

  local waves="" wis="" include_spec="true"
  while [ $# -gt 0 ]; do
    case "$1" in
      --waves)        waves="${2:-}"; shift 2 ;;
      --wis)          wis="${2:-}"; shift 2 ;;
      --include-spec) include_spec="${2:-}"; shift 2 ;;
      *)              shift ;;
    esac
  done

  case "$waves" in ''|*[!0-9]*)
    echo "forge-estimate: --waves must be a positive integer (got '${waves}')" >&2
    return 0 ;;
  esac
  [ "$waves" -ge 1 ] || { echo "forge-estimate: --waves must be >= 1" >&2; return 0; }
  case "$wis" in ''|*[!0-9]*)
    echo "forge-estimate: --wis must be a non-negative integer (got '${wis}')" >&2
    return 0 ;;
  esac
  case "$include_spec" in
    true|false) ;;
    *) echo "forge-estimate: --include-spec must be 'true' or 'false' (got '${include_spec}')" >&2
       return 0 ;;
  esac

  local baselines
  baselines=$(forge_estimate_baselines)
  if [ -z "$baselines" ]; then
    echo "forge-estimate: baselines unavailable; cannot compute a range" >&2
    return 0
  fi
  # Propagate a refusal ({"error": ...}) unchanged.
  if printf '%s' "$baselines" | jq -e 'has("error")' >/dev/null 2>&1; then
    printf '%s\n' "$baselines"
    return 0
  fi

  jq -n \
    --argjson b "$baselines" \
    --argjson waves "$waves" \
    --argjson wis "$wis" \
    --arg include_spec "$include_spec" '
    def remaining($W):
      (if ($include_spec == "true") then ($b.spec_days.median) else 0 end)
      + ($b.wave1_days.median)
      + (($W - 1) * ($b.later_wave_days.median))
      + 1.0;
    def r1($x): (($x * 10) | round) / 10;
    {
      low_days:     r1(remaining([1, ($waves - 1)] | max)),
      high_days:    r1(remaining($waves + 1)),
      waves:        $waves,
      wis:          $wis,
      include_spec: ($include_spec == "true"),
      basis:        $b
    }
  '
}

# --- Self-test -------------------------------------------------------------

_forge_estimate_self_test() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "forge-estimate self-test: jq not found — cannot run" >&2
    return 1
  fi

  local pass=0 fail=0 tmpdir
  tmpdir=$(mktemp -d)

  _check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
      printf '  [PASS] %-56s -> %s\n' "$label" "$actual"
      pass=$((pass + 1))
    else
      printf '  [FAIL] %-56s expected %s, got %s\n' "$label" "$expected" "$actual"
      fail=$((fail + 1))
    fi
  }
  # Extract a field from a JSON blob.
  _f() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

  # --- Fixture: a calibrated baked baselines.json ---
  cat >"$tmpdir/baselines-calibrated.json" <<'JSON'
{
  "schema": "forge-baselines/v1",
  "baseline_version": "test-2026-01",
  "generated_at": "2026-01-01T00:00:00Z",
  "generated_by": "forge-rollup --emit-baselines",
  "projects": 3,
  "baselines": {
    "spec_days":         {"median": 1,   "n": 15},
    "wave1_days":        {"median": 2,   "n": 12},
    "later_wave_days":   {"median": 1.5, "n": 29},
    "feature_days":      {"median": 4,   "n": 13},
    "waves_per_feature": {"median": 3,   "n": 13},
    "wis_per_feature":   {"median": 7,   "n": 13}
  },
  "notes": "test fixture"
}
JSON

  # --- Fixture: the shipped uncalibrated shape ---
  cat >"$tmpdir/baselines-uncalibrated.json" <<'JSON'
{
  "schema": "forge-baselines/v1",
  "baseline_version": "uncalibrated",
  "generated_at": null,
  "generated_by": "forge-rollup --emit-baselines",
  "projects": 0,
  "baselines": {
    "spec_days":         {"median": 0, "n": 0},
    "wave1_days":        {"median": 0, "n": 0},
    "later_wave_days":   {"median": 0, "n": 0},
    "feature_days":      {"median": 0, "n": 0},
    "waves_per_feature": {"median": 0, "n": 0},
    "wis_per_feature":   {"median": 0, "n": 0}
  },
  "notes": "uncalibrated"
}
JSON

  # --- Fixture: a versioned-but-all-zero-n baked file (still a refusal) ---
  cat >"$tmpdir/baselines-allzero.json" <<'JSON'
{
  "schema": "forge-baselines/v1",
  "baseline_version": "vX",
  "generated_at": "2026-01-01T00:00:00Z",
  "baselines": {
    "spec_days":         {"median": 0, "n": 0},
    "wave1_days":        {"median": 0, "n": 0},
    "later_wave_days":   {"median": 0, "n": 0},
    "feature_days":      {"median": 0, "n": 0},
    "waves_per_feature": {"median": 0, "n": 0},
    "wis_per_feature":   {"median": 0, "n": 0}
  }
}
JSON

  # --- Fixture: empty ledgers ---
  mkdir -p "$tmpdir/metrics-empty"
  : >"$tmpdir/metrics-empty/events.jsonl"
  : >"$tmpdir/metrics-empty/estimation-snapshots.jsonl"

  # Helper: append a ticket with a fixed spec_days delta of 3.0 wall-clock days.
  _spec3_ticket() {
    local dir="$1" t="$2"
    printf '%s\n' "{\"schema\":\"forge-metrics/v1\",\"event\":\"feature_started\",\"ticket\":\"$t\",\"ts\":\"2026-01-01T00:00:00Z\"}" >>"$dir/events.jsonl"
    printf '%s\n' "{\"schema\":\"forge-metrics/v1\",\"event\":\"spec_approved\",\"ticket\":\"$t\",\"ts\":\"2026-01-04T00:00:00Z\"}" >>"$dir/events.jsonl"
  }

  # --- Fixture: 4 tickets (own spec_days n=4 -> below threshold) ---
  mkdir -p "$tmpdir/metrics-4"
  : >"$tmpdir/metrics-4/events.jsonl"
  _spec3_ticket "$tmpdir/metrics-4" "T1"
  _spec3_ticket "$tmpdir/metrics-4" "T2"
  _spec3_ticket "$tmpdir/metrics-4" "T3"
  _spec3_ticket "$tmpdir/metrics-4" "T4"

  # --- Fixture: 5 tickets (own spec_days n=5 -> at threshold, override) ---
  mkdir -p "$tmpdir/metrics-5"
  : >"$tmpdir/metrics-5/events.jsonl"
  _spec3_ticket "$tmpdir/metrics-5" "T1"
  _spec3_ticket "$tmpdir/metrics-5" "T2"
  _spec3_ticket "$tmpdir/metrics-5" "T3"
  _spec3_ticket "$tmpdir/metrics-5" "T4"
  _spec3_ticket "$tmpdir/metrics-5" "T5"

  # --- Fixture: 5 good tickets + malformed + irrelevant lines interleaved ---
  mkdir -p "$tmpdir/metrics-malformed"
  : >"$tmpdir/metrics-malformed/events.jsonl"
  _spec3_ticket "$tmpdir/metrics-malformed" "T1"
  _spec3_ticket "$tmpdir/metrics-malformed" "T2"
  printf '%s\n' 'this is not json {{{' >>"$tmpdir/metrics-malformed/events.jsonl"
  _spec3_ticket "$tmpdir/metrics-malformed" "T3"
  printf '%s\n' '{"schema":"forge-metrics/v1","event":"bug_opened","ticket":"T9","ts":"garbage-timestamp"}' >>"$tmpdir/metrics-malformed/events.jsonl"
  _spec3_ticket "$tmpdir/metrics-malformed" "T4"
  _spec3_ticket "$tmpdir/metrics-malformed" "T5"

  echo "Running forge-estimate self-tests..."
  echo

  local out

  # === 1. Baked-only path (empty ledgers -> everything is org) ===
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-calibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_baselines)
  _check "baked-only: spec_days source"     "org"          "$(_f "$out" '.spec_days.source')"
  _check "baked-only: spec_days median"     "1"            "$(_f "$out" '.spec_days.median')"
  _check "baked-only: spec_days n (baked)"  "15"           "$(_f "$out" '.spec_days.n')"
  _check "baked-only: wave1_days median"    "2"            "$(_f "$out" '.wave1_days.median')"
  _check "baked-only: later_wave median"    "1.5"          "$(_f "$out" '.later_wave_days.median')"
  _check "baked-only: baseline_version"     "test-2026-01" "$(_f "$out" '.baseline_version')"
  _check "baked-only: generated_at"         "2026-01-01T00:00:00Z" "$(_f "$out" '.generated_at')"

  # === 2. Own-override boundary: 4 samples -> org, 5 samples -> project ===
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-calibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-4" \
    out=$(forge_estimate_baselines)
  _check "n=4 (below threshold): spec_days source" "org" "$(_f "$out" '.spec_days.source')"
  _check "n=4 (below threshold): spec_days median" "1"   "$(_f "$out" '.spec_days.median')"

  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-calibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-5" \
    out=$(forge_estimate_baselines)
  _check "n=5 (at threshold): spec_days source"  "project" "$(_f "$out" '.spec_days.source')"
  _check "n=5 (at threshold): spec_days median"  "3"       "$(_f "$out" '.spec_days.median')"
  _check "n=5 (at threshold): spec_days n (own)" "5"       "$(_f "$out" '.spec_days.n')"
  # metrics with no own samples still fall back to baked
  _check "n=5: wave1_days stays org"             "org"     "$(_f "$out" '.wave1_days.source')"

  # === 3. Range formula on known inputs (baked-only, calibrated) ===
  # remaining(W) = spec(1.0) + wave1(2.0) + (W-1)*later(1.5) + 1.0
  #   waves=3, include-spec=true:  low=remaining(2)=5.5  high=remaining(4)=8.5
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-calibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_range --waves 3 --wis 7)
  _check "range w3: low_days"     "5.5"  "$(_f "$out" '.low_days')"
  _check "range w3: high_days"    "8.5"  "$(_f "$out" '.high_days')"
  _check "range w3: waves"        "3"    "$(_f "$out" '.waves')"
  _check "range w3: wis"          "7"    "$(_f "$out" '.wis')"
  _check "range w3: include_spec" "true" "$(_f "$out" '.include_spec')"
  _check "range w3: basis version" "test-2026-01" "$(_f "$out" '.basis.baseline_version')"

  # waves=3, include-spec=false: remaining(W)=2.0+(W-1)*1.5+1.0
  #   low=remaining(2)=4.5  high=remaining(4)=7.5
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-calibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_range --waves 3 --wis 7 --include-spec false)
  _check "range w3 no-spec: low_days"     "4.5"   "$(_f "$out" '.low_days')"
  _check "range w3 no-spec: high_days"    "7.5"   "$(_f "$out" '.high_days')"
  _check "range w3 no-spec: include_spec" "false" "$(_f "$out" '.include_spec')"

  # waves=1: low=remaining(max(1,0)=1)=4.0  high=remaining(2)=5.5
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-calibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_range --waves 1 --wis 2)
  _check "range w1: low_days"  "4"   "$(_f "$out" '.low_days')"
  _check "range w1: high_days" "5.5" "$(_f "$out" '.high_days')"

  # === 4. Malformed-row skip (result equals the clean 5-ticket result) ===
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-calibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-malformed" \
    out=$(forge_estimate_baselines)
  _check "malformed skip: spec_days source" "project" "$(_f "$out" '.spec_days.source')"
  _check "malformed skip: spec_days median" "3"       "$(_f "$out" '.spec_days.median')"
  _check "malformed skip: spec_days n"      "5"       "$(_f "$out" '.spec_days.n')"

  # === 5. Uncalibrated-file refusal (never a fabricated number) ===
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-uncalibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_baselines)
  _check "uncalibrated: baselines has error" "true" "$(_f "$out" 'has("error")')"

  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-uncalibrated.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_range --waves 3 --wis 7)
  _check "uncalibrated: range propagates error" "true" "$(_f "$out" 'has("error")')"

  # versioned but all n=0 -> still a refusal
  FORGE_ESTIMATE_BASELINES="$tmpdir/baselines-allzero.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_baselines)
  _check "all-n-zero: baselines has error" "true" "$(_f "$out" 'has("error")')"

  # missing baked file -> refusal
  FORGE_ESTIMATE_BASELINES="$tmpdir/does-not-exist.json" \
  FORGE_ESTIMATE_METRICS_DIR="$tmpdir/metrics-empty" \
    out=$(forge_estimate_baselines)
  _check "missing baked: baselines has error" "true" "$(_f "$out" 'has("error")')"

  rm -rf "$tmpdir"

  echo
  echo "Self-test summary: $pass passed, $fail failed"
  return "$fail"
}

# --- Dispatch --------------------------------------------------------------

# Invoked-mode dispatch. Runs ONLY when the file is executed under bash — never
# when sourced (bash: BASH_SOURCE[0] != $0), and never under zsh (the BASH_VERSION
# guard is empty there, so a zsh `source` skips this block instead of exploding on
# the unset BASH_SOURCE or running `exit` in the caller's shell). The
# `${BASH_SOURCE[0]:-$0}` fallback keeps the comparison safe under `set -u` too.
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  # Strict mode scoped to invoked-mode only — cannot leak into a sourcing caller.
  set -u
  case "${1:-}" in
    --self-test)
      _forge_estimate_self_test
      exit $?
      ;;
    baselines)
      shift
      forge_estimate_baselines "$@"
      exit $?
      ;;
    range)
      shift
      forge_estimate_range "$@"
      exit $?
      ;;
    -h|--help|"")
      cat <<USAGE
forge-estimate.sh — harness-native delivery estimation helper

Invoked-mode (RECOMMENDED — deterministic, works from any shell incl. zsh):
    bash .claude/lib/forge-estimate.sh baselines
    bash .claude/lib/forge-estimate.sh range --waves <N> --wis <M> [--include-spec true|false]
    bash .claude/lib/forge-estimate.sh --self-test

Sourceable (BASH ONLY — bash-shebang hooks/scripts):
    . "<harness-root>/.claude/lib/forge-estimate.sh"
    forge_estimate_baselines
    forge_estimate_range --waves <N> --wis <M> [--include-spec true|false]

baselines / forge_estimate_baselines : resolve effective per-metric baselines
    (project own median when >= ${FORGE_ESTIMATE_MIN_SAMPLES:-5} own samples, else baked org value).
range / forge_estimate_range         : deterministic low/high day range.

Both emit JSON to stdout. An uncalibrated / missing baked baselines.json yields
{"error": ...} — never a fabricated number.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown subcommand/option: ${1:-}" >&2
      echo "Try: baselines | range --waves <N> --wis <M> | --self-test | --help" >&2
      exit 1
      ;;
  esac
fi
