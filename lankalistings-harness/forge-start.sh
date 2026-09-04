#!/usr/bin/env bash
#
# forge-start.sh — Open this Forge workspace in Claude Code with a
# gate-respecting session-start prompt.
#
# Usage:
#   Run from inside a <project>-harness/ directory after placing any
#   project materials (brief, screenshots, meeting notes, etc.) into
#   .forge/discovery/.
#
#     ./forge-start.sh
#
# What it does:
#   1. Validates that the current directory looks like a Forge workspace.
#   2. Inventories .forge/discovery/ so its contents are pre-listed in
#      the opening prompt (Claude won't have to scan).
#   3. Reads setup.* from .forge/tracker.yaml so the current engagement
#      phase is in the prompt.
#   4. Launches `claude` with a turn-1 read-only protocol: orient,
#      summarize, propose one next action, and stop. Authoring happens
#      in later turns through interactive flows (forge-prd-author,
#      /forge-arch-probe, /forge-decompose, etc.).
#
# What it deliberately does NOT do:
#   - Doesn't write to any file in the workspace
#   - Doesn't depend on yq, python, or any non-standard tool
#   - Doesn't try to enforce gate discipline after turn 1 — that's the
#     job of skills, hooks, and the rules in .claude/CLAUDE.md
#

set -euo pipefail

# ---- 1. Validate location ----------------------------------------------------

if [[ ! -d ".forge" || ! -d ".claude" ]]; then
  echo "Error: forge-start.sh must be run from inside a <project>-harness/ directory." >&2
  echo "  Expected ./.forge/ and ./.claude/ to exist here." >&2
  exit 1
fi

# ---- 2. Check claude CLI is installed ---------------------------------------

if ! command -v claude &>/dev/null; then
  echo "Error: 'claude' CLI not found on PATH. Install Claude Code first." >&2
  echo "  https://docs.claude.com/claude-code" >&2
  exit 1
fi

# ---- 3. Inventory .forge/discovery/ -----------------------------------------

DISCOVERY_LIST=""
if [[ -d ".forge/discovery" ]]; then
  DISCOVERY_LIST=$(find .forge/discovery -type f \
    ! -name 'README.md' \
    ! -name '.DS_Store' \
    ! -name '.gitkeep' \
    ! -path '*/.*' \
    2>/dev/null | sort || true)
fi

if [[ -z "$DISCOVERY_LIST" ]]; then
  DISCOVERY_BLOCK="  (empty — describe the engagement to me verbally)"
else
  DISCOVERY_BLOCK=$(printf '%s\n' "$DISCOVERY_LIST" | sed 's|^|  - |')
fi

# ---- 4. Read phase signal from tracker.yaml ---------------------------------

# Parses `setup.<section>.status` from .forge/tracker.yaml without yq.
# Finds the section header line then takes the first `status:` line after it.
# Always returns 0 (|| true) so set -e doesn't kill the script when a key
# is missing or the file is malformed.
get_section_status() {
  local section="$1"
  grep -A2 "^[[:space:]]*${section}:" .forge/tracker.yaml 2>/dev/null \
    | grep -m1 -E "^[[:space:]]+status:" \
    | awk '{print $2}' \
    | tr -d '"' \
    | tr -d "'" \
    || true
}

PHASE_BLOCK="  (tracker.yaml not readable — orient from CLAUDE.md only)"
if [[ -f ".forge/tracker.yaml" ]]; then
  PRD=$(get_section_status "project_prd");      PRD=${PRD:-unknown}
  ARCH=$(get_section_status "architecture");    ARCH=${ARCH:-unknown}
  DECOMP=$(get_section_status "decomposition"); DECOMP=${DECOMP:-unknown}
  PHASE_BLOCK=$(printf '  prd (Gate 1):        %s\n  architecture (Gate 2): %s\n  decomposition (Gate 3): %s' \
    "$PRD" "$ARCH" "$DECOMP")
fi

# ---- 5. Compose the opening prompt ------------------------------------------

read -r -d '' PROMPT <<EOF || true
I'm opening this Forge workspace. Follow this protocol on this FIRST TURN — no exceptions.

SESSION PROTOCOL
1. Read ONLY CLAUDE.md and .forge/tracker.yaml. Do not preemptively load framework.md, guide.md, skill internals, templates, design artifacts, specs, or plans. Pull those in later only if a specific turn requires it.
2. Read every file listed under "Discovery materials" below. That is the raw input for this engagement.
3. THIS FIRST TURN IS READ-ONLY. Do not write to any file in this workspace. Authoring happens in later turns through interactive flows (forge-prd-author, /forge-arch-probe, /forge-decompose, spec and plan authoring) — those flows write files, but only AFTER they've interviewed me or surfaced tradeoffs. If you find yourself about to write a file on this turn, that's the bug — stop and ask.
4. Respond in a short paragraph: current phase, what artifacts already exist, what's in discovery, what you understand about the engagement, and any obvious gaps you'd want clarified before starting an authoring flow.
5. End with ONE concrete proposed next action, then wait. Multi-step asks like "run discovery → write PRD → build it" are NOT authorization to chain — propose the first step (usually invoking /forge-prd-author or another authoring flow) and let me drive the rhythm from there.

CONTEXT (collected by forge-start.sh — do not re-derive)
Phase signal (from .forge/tracker.yaml):
$PHASE_BLOCK

Discovery materials in .forge/discovery/:
$DISCOVERY_BLOCK

Suggested next action if everything is fresh and no PRD exists: invoke /forge-prd-author so you can interview me on the discovery material before any PRD content is drafted.
EOF

# ---- 6. Echo what we collected, then hand off to claude ---------------------

echo "==> Forge session-start"
echo "==> Workspace: $(pwd)"
echo "==> Phase signal:"
printf '%s\n' "$PHASE_BLOCK"
echo "==> Discovery materials:"
printf '%s\n' "$DISCOVERY_BLOCK"
echo "==> Launching claude with session-start prompt..."
echo ""

exec claude "$PROMPT"
