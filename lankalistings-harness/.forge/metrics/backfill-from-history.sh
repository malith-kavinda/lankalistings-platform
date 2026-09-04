#!/usr/bin/env bash
#
# One-time backfill of the delivery-metrics ledgers for a COMPLETED project.
#
# Reconstructs metrics history from data that already exists — so a project whose
# engineering finished before metrics were wired still shows cycle-time and
# throughput on the dashboard. Sources, in order of fidelity:
#
#   1. GitHub merged PRs (gh)      — datetime createdAt/mergedAt, matched by branch
#                                    name (feature/<id>-wave-<N>, feature/<id>-spec).
#                                    feature_started prefers the spec PR's createdAt
#                                    (a fixed point, immune to spec renames/reslices).
#   2. tracker.yaml waves[].merged_at — date-resolution fallback when a PR isn't found.
#   3. local git history          — only when no spec PR: first commit on
#                                    .forge/specs/<id>-*-spec.md via `git --follow`
#                                    (rename-aware). A start that post-dates the first
#                                    wave merge (reslice/rename artifact) is dropped.
#
# Emits forge-metrics/v1 rows tagged "source":"backfill" so reconstructed data is
# always distinguishable from live data. Run ONCE per project, from the project root:
#
#   bash .forge/metrics/backfill-from-history.sh            # dry-run: report only, write nothing
#   bash .forge/metrics/backfill-from-history.sh --write     # append backfill rows to the ledgers
#   bash .forge/metrics/backfill-from-history.sh --write --force   # add even if backfill rows already exist
#   bash .forge/metrics/backfill-from-history.sh --repo owner/be --repo owner/fe   # force the repo set
#
# CANNOT recover: agent-runs (never historically recorded — agent_runs left null,
# the agent-run tiles stay blank). Spec-authoring time is a first-commit proxy and
# undercounts the pre-commit authoring interview. All figures are wall-clock lead
# times — estimation signals, not active-effort or commitments.
#
# Posture: manual-first. Dry-run by default; never mutates tracker.yaml; never
# touches live (non-backfill) rows; idempotent unless --force.

set -u

WRITE=0; FORCE=0; REPOS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --write) WRITE=1 ;;
    --force) FORCE=1 ;;
    --repo)  shift; [ $# -gt 0 ] && REPOS+=("$1") ;;
    *) echo "backfill: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done

for c in jq yq git; do
  command -v "$c" >/dev/null 2>&1 || { echo "backfill: required tool '$c' not found." >&2; exit 1; }
done
HAVE_GH=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then HAVE_GH=1; fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TRACKER="$ROOT/.forge/tracker.yaml"
METRICS_DIR="$ROOT/.forge/metrics"
EVENTS="$METRICS_DIR/events.jsonl"
SNAPS="$METRICS_DIR/estimation-snapshots.jsonl"
SCHEMA="forge-metrics/v1"

[ -f "$TRACKER" ] || { echo "backfill: $TRACKER not found — run from a project root." >&2; exit 1; }
mkdir -p "$METRICS_DIR"

if [ "$WRITE" = 1 ] && [ "$FORCE" = 0 ] && [ -f "$EVENTS" ] && grep -q '"source":[ ]*"backfill"' "$EVENTS" 2>/dev/null; then
  echo "backfill: events.jsonl already contains backfill rows. Re-run with --force to add more, or remove them first." >&2
  exit 1
fi

# Convert the tracker to JSON once; do all structural reads in jq (predictable),
# keeping yq only for this conversion.
TJSON=$(yq -o=json '.' "$TRACKER" 2>/dev/null)
[ -z "$TJSON" ] && { echo "backfill: could not parse $TRACKER as YAML." >&2; exit 1; }

# ---- discover repos (for gh PR lookup) from tracker pr_url values, unless overridden ----
if [ "${#REPOS[@]}" -eq 0 ]; then
  while IFS= read -r r; do [ -n "$r" ] && REPOS+=("$r"); done < <(
    echo "$TJSON" | jq -r '[.. | objects | .pr_url? // empty] | .[]' 2>/dev/null \
      | sed -nE 's#https://github.com/([^/]+/[^/]+)/pull/.*#\1#p' | sort -u
  )
fi

# ---- build a merged-PR cache (branch -> {createdAt, mergedAt}) ----
PR_CACHE="$(mktemp)"; EV_TMP="$(mktemp)"; SN_TMP="$(mktemp)"
trap 'rm -f "$PR_CACHE" "$EV_TMP" "$SN_TMP"' EXIT
echo '[]' > "$PR_CACHE"
if [ "$HAVE_GH" = 1 ] && [ "${#REPOS[@]}" -gt 0 ]; then
  for repo in "${REPOS[@]}"; do
    prs=$(gh pr list --repo "$repo" --state merged --limit 1000 \
            --json number,headRefName,createdAt,mergedAt 2>/dev/null || echo '[]')
    jq -s 'add' "$PR_CACHE" <(echo "$prs") > "$PR_CACHE.tmp" && mv "$PR_CACHE.tmp" "$PR_CACHE"
  done
fi

# normalize a timestamp to ISO-8601 UTC with Z (the only form the metrics hook's
# fromdateiso8601 accepts): date-only -> midnight Z; already-Z passes through.
norm() {
  case "$1" in
    "" ) echo "" ;;
    *T*Z ) echo "$1" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] ) echo "${1}T00:00:00Z" ;;
    * ) echo "$1" ;;
  esac
}

# look up a PR by exact head branch; echoes "createdAt mergedAt" (ISO datetimes) or empty
pr_times() {
  jq -r --arg b "$1" '[.[] | select(.headRefName == $b)] | sort_by(.mergedAt) | last
                       | if . == null then empty else "\(.createdAt) \(.mergedAt)" end' "$PR_CACHE" 2>/dev/null
}

# ---- iterate features ----
feature_ids=$(echo "$TJSON" | jq -r '.features[]?.id // empty' 2>/dev/null)
[ -z "$feature_ids" ] && { echo "backfill: no features found in tracker.yaml." >&2; exit 1; }

fid_count=0; ev_count=0; report=""

emit_event() {  # $1=event $2=ticket $3=ts $4=wave(or null) $5=fidelity-tag
  { [ -z "$3" ] || [ "$3" = "null" ]; } && return 0
  jq -nc --arg s "$SCHEMA" --arg e "$1" --arg t "$2" --arg ts "$3" \
        --argjson w "${4:-null}" --arg src "$5" \
        '{schema:$s, event:$e, ticket:$t, ts:$ts, wave:$w, actor:"backfill", source:"backfill", fidelity:$src}' >> "$EV_TMP"
  ev_count=$((ev_count+1))
}

for fid in $feature_ids; do
  fid_count=$((fid_count+1))
  # resolve the spec file: Forge convention is <id>-<desc>-spec.md; fall back to bare <id>-spec.md
  spec=$(ls "$ROOT"/.forge/specs/${fid}-*-spec.md 2>/dev/null | head -1)
  [ -z "$spec" ] && spec=$(ls "$ROOT"/.forge/specs/${fid}-spec.md 2>/dev/null | head -1)
  fline="$fid:"

  # spec PR (createdAt mergedAt) — a fixed anchor pair, immune to spec file renames/reslices
  spec_pr=$(pr_times "feature/${fid}-spec")
  spec_created=""; spec_merged=""
  if [ -n "$spec_pr" ]; then
    spec_created=$(norm "$(echo "$spec_pr" | awk '{print $1}')")
    spec_merged=$(norm "$(echo "$spec_pr" | awk '{print $2}')")
  fi

  # waves first — gh PR per wave branch (datetime), else tracker merged_at (date).
  # Track the EARLIEST merge too, for the feature_started plausibility guard below.
  first_merge=""; last_merge=""
  wnums=$(echo "$TJSON" | jq -r --arg f "$fid" '.features[]? | select(.id==$f) | .waves[]?.wave // empty' 2>/dev/null)
  if [ -n "$wnums" ]; then
    for wn in $wnums; do
      merged=""
      wpr=$(pr_times "feature/${fid}-wave-${wn}")
      if [ -n "$wpr" ]; then
        emit_event wave_pr_opened "$fid" "$(norm "$(echo "$wpr" | awk '{print $1}')")" "$wn" gh-pr
        merged=$(norm "$(echo "$wpr" | awk '{print $2}')")
        emit_event wave_merged "$fid" "$merged" "$wn" gh-pr
      else
        merged=$(norm "$(echo "$TJSON" | jq -r --arg f "$fid" --argjson w "$wn" '.features[]? | select(.id==$f) | .waves[]? | select(.wave==$w) | .merged_at // empty' 2>/dev/null)")
        [ -n "$merged" ] && emit_event wave_merged "$fid" "$merged" "$wn" tracker-date
      fi
      if [ -n "$merged" ]; then [ -z "$first_merge" ] && first_merge="$merged"; last_merge="$merged"; fi
    done
    fline="$fline waves($(echo "$wnums" | wc -w | tr -d ' '))"
  fi

  # feature_started — PREFER the spec PR's createdAt (immune to the spec renames/reslices
  # that corrupt git's first-commit); else fall back to the first spec-file commit via
  # `git --follow` (rename-aware). Plausibility guard: a start that post-dates the first
  # wave merge is a reslice/rename artifact (inflated or negative lead time) — DROP it
  # rather than poison the lead-time / spec-authoring medians.
  started=""; started_fid=""
  if [ -n "$spec_created" ]; then
    started="$spec_created"; started_fid="gh-pr"
  elif [ -n "$spec" ] && [ -f "$spec" ]; then
    # NB: --follow is incompatible with --reverse (the combination drops pre-rename
    # history), so take the oldest entry with tail -1 instead of --reverse | head -1.
    started=$(TZ=UTC git -C "$ROOT" log --follow --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%ad' -- "$spec" 2>/dev/null | tail -1)
    started_fid="git"
  fi
  if [ -n "$started" ] && [ -n "$first_merge" ]; then
    ok=$(jq -n --arg a "$started" --arg b "$first_merge" '(($a|fromdateiso8601?) <= ($b|fromdateiso8601?))' 2>/dev/null)
    if [ "$ok" != "true" ]; then started=""; fline="$fline started(SUSPECT-dropped:$started_fid)"; started_fid=""; fi
  fi
  if [ -n "$started" ]; then emit_event feature_started "$fid" "$started" null "$started_fid"; fline="$fline started($started_fid)"
  elif [ -z "$started_fid" ]; then fline="$fline started(MISSING)"; fi

  # spec_approved — spec PR merge time
  if [ -n "$spec_merged" ]; then emit_event spec_approved "$fid" "$spec_merged" null gh-pr; fline="$fline spec_approved(gh)"
  else fline="$fline spec_approved(none)"; fi

  # feature_done — last wave merge we saw
  if [ -n "$last_merge" ]; then emit_event feature_done "$fid" "$last_merge" null derived; fline="$fline done(derived)"; fi

  # estimation snapshot — emitted whenever the feature shipped (last_merge known), so the
  # complexity signal (workitems) survives even when feature_started was dropped. lead_time
  # is computed only from a valid start and clamped to null if negative.
  wi=$(echo "$TJSON" | jq -r --arg f "$fid" '[.features[]? | select(.id==$f) | (.waves[]?.workitems[]?, .workitems[]?)] | length' 2>/dev/null)
  [ -z "$wi" ] && wi=0
  nwaves=$(echo "${wnums:-}" | wc -w | tr -d ' ')
  if [ -n "$last_merge" ]; then
    days=null
    if [ -n "$started" ]; then
      days=$(jq -n --arg a "$started" --arg b "$last_merge" '(($b|fromdateiso8601?) - ($a|fromdateiso8601?)) / 86400 | (.*10|round)/10 | if . < 0 then null else . end' 2>/dev/null)
      [ -z "$days" ] && days=null
    fi
    jq -nc --arg s "$SCHEMA" --arg t "$fid" --arg ts "$last_merge" \
          --argjson waves "$nwaves" --argjson wi "$wi" --argjson lead "$days" \
          '{schema:$s, ts:$ts, ticket:$t, ship_unit:"wave", waves:$waves, workitems:$wi,
            agent_runs:null, lead_time_days:$lead, source:"backfill"}' >> "$SN_TMP"
  fi

  report="$report\n  $fline"
done

# ---- report ----
echo "backfill: scanned $fid_count features → reconstructed $ev_count events, $(wc -l < "$SN_TMP" | tr -d ' ') snapshots"
echo "          gh: $([ "$HAVE_GH" = 1 ] && echo "available (repos: ${REPOS[*]:-none found})" || echo "NOT available — using tracker dates only")"
echo "          fidelity per feature (gh-pr = datetime, tracker-date = day resolution, none/MISSING = unrecoverable):"
printf '%b\n' "$report"
echo "          NOTE: agent_runs is null for all rows (never historically recorded);"
echo "                spec-authoring (feature_started→spec_approved) undercounts pre-commit interview time."

if [ "$WRITE" = 1 ]; then
  cat "$EV_TMP" >> "$EVENTS"
  cat "$SN_TMP" >> "$SNAPS"
  echo "backfill: WROTE $ev_count events to $EVENTS and snapshots to $SNAPS (tagged source:\"backfill\")."
  echo "          Edit .forge/tracker.yaml or any ledger to trigger regen-metrics-dashboard.sh, then refresh the dashboard."
else
  echo "backfill: DRY RUN — nothing written. Re-run with --write to append the rows above."
fi
