#!/usr/bin/env bash
#
# install-personal-statusline.sh
#
# One-time per-developer-machine setup for the Forge Heartbeat
# resting-pulse (status-line segment).
#
# Why this script exists:
#
#   The Heartbeat ships a segment provider inside every Forge harness at
#   .claude/lib/forge-statusline-segment.sh, but the spec (FR-3) deliberately
#   forbids putting `statusLine` in the project's settings.json — that slot
#   belongs to the developer's personal status-line script at
#   ~/.claude/statusline.sh, which is shared across all projects.
#
#   So each developer must wire the segment provider into their personal
#   status-line script ONCE per machine. From then on, every Forge harness
#   they ever open lights up automatically: the segment appears inside Forge
#   projects and is silent outside them.
#
#   This script performs that one-time wire-up idempotently. Safe to re-run.
#
# What it does:
#
#   1. Detects ~/.claude/statusline.sh.
#      - If missing, prints how to set one up + exits 1 (we won't create one
#        from scratch — that's the developer's choice; see OQ-3 in the spec).
#   2. Checks for the Forge marker line. If present → already wired, exits 0.
#   3. Otherwise: backs up the file to
#        ~/.claude/statusline.sh.bak.<timestamp>
#      …then prepends a wrapper-style block that:
#        - Reads stdin once.
#        - Computes the Forge segment via the provider in the project's
#          .claude/lib/ (silent outside a Forge harness).
#        - Calls the (renamed) personal status-line script with the same
#          stdin to produce the rest of the line.
#        - Prepends the Forge segment with a separator if non-empty.
#
# Why a wrapper, not a surgical edit:
#
#   Every personal status-line script has a different shape (different
#   segments, different separators, different field extraction). A wrapper
#   is robust to all of them — we don't need to understand the inner script,
#   just call it.
#
# Safe to re-run; idempotent.

set -euo pipefail

PERSONAL="$HOME/.claude/statusline.sh"
WRAPPER_PERSONAL="$HOME/.claude/statusline-personal.sh"
MARKER="# FORGE_HEARTBEAT_WIRED — managed by forge-harness/install-personal-statusline.sh"

# ---- Detect ----------------------------------------------------------------

if [ ! -f "$PERSONAL" ]; then
  cat >&2 <<EOF
No personal status-line script found at $PERSONAL.

Forge does not ship a personal status-line for you — that's deliberate
(see spec OQ-3 resolution: out of scope). To use the Heartbeat resting
pulse, first set up a personal status-line script. The simplest minimal
form:

  mkdir -p "$HOME/.claude"
  cat > "$PERSONAL" <<'SCRIPT'
  #!/usr/bin/env bash
  input=\$(cat)
  branch=\$(echo "\$input" | jq -r '.workspace.project_dir // .cwd // ""' \\
    | xargs -I{} git -C {} symbolic-ref --short HEAD 2>/dev/null)
  printf '\\xf0\\x9f\\x8c\\xbf %s' "\${branch:-no-git}"
  SCRIPT
  chmod +x "$PERSONAL"

Also point Claude Code at it in ~/.claude/settings.json:

  {
    "statusLine": { "type": "command", "command": "bash $PERSONAL" }
  }

Then re-run this script.
EOF
  exit 1
fi

# ---- Already wired? --------------------------------------------------------

if grep -qF "$MARKER" "$PERSONAL" 2>/dev/null; then
  echo "Already wired: $PERSONAL calls the Forge Heartbeat segment provider."
  echo "(Re-run is a no-op.)"
  exit 0
fi

# ---- Sanity: don't double-rename if the personal script was renamed already
if [ -f "$WRAPPER_PERSONAL" ]; then
  cat >&2 <<EOF
Refusing to install: $WRAPPER_PERSONAL already exists.

This usually means a partial install was interrupted. Inspect:
  - $PERSONAL              (should be the Forge wrapper)
  - $WRAPPER_PERSONAL  (should be your original status line)

If you want to start fresh, move $WRAPPER_PERSONAL back to $PERSONAL
and re-run this script.
EOF
  exit 1
fi

# ---- Back up ---------------------------------------------------------------

ts=$(date +%Y%m%d%H%M%S)
backup="$PERSONAL.bak.$ts"
cp "$PERSONAL" "$backup"
echo "Backed up existing personal status line to: $backup"

# ---- Move the personal script aside ---------------------------------------

mv "$PERSONAL" "$WRAPPER_PERSONAL"
chmod +x "$WRAPPER_PERSONAL"
echo "Moved your status-line script to: $WRAPPER_PERSONAL"

# ---- Install the Forge-aware wrapper at the original path -----------------

cat > "$PERSONAL" <<WRAPPER
#!/usr/bin/env bash
$MARKER
#
# Forge Heartbeat — status-line wrapper. Installed by
# forge-harness/install-personal-statusline.sh.
#
# This wrapper:
#   1. Reads the statusLine stdin JSON.
#   2. Computes the Forge segment from the project's segment provider at
#      <project>/.claude/lib/forge-statusline-segment.sh — silent outside
#      any Forge harness.
#   3. Calls your original personal status-line script
#      (now at ~/.claude/statusline-personal.sh) with the same JSON to
#      produce the rest of the line.
#   4. Prepends the Forge segment + a separator when present.
#
# To uninstall:
#   mv ~/.claude/statusline-personal.sh ~/.claude/statusline.sh
#
# The wrapper itself is regenerated each time you re-run
# install-personal-statusline.sh, so feel free to delete it and re-install.

input=\$(cat)

# Locate the Forge segment provider in the active project (if any).
project_dir=\$(printf '%s' "\$input" | jq -r '.workspace.project_dir // .cwd // ""' 2>/dev/null)
forge_seg=""
if [ -n "\$project_dir" ] && [ -x "\$project_dir/.claude/lib/forge-statusline-segment.sh" ]; then
  forge_seg=\$(printf '%s' "\$input" | "\$project_dir/.claude/lib/forge-statusline-segment.sh" 2>/dev/null)
fi

# Personal status line — feed the same stdin to your original script.
personal_line=\$(printf '%s' "\$input" | bash "$WRAPPER_PERSONAL")

# Compose. ANSI-dim separator matches common personal-script styles; if
# yours uses something different, edit the SEP value below.
if [ -n "\$forge_seg" ]; then
  printf '\\033[1;38;5;75m%s\\033[0m \\033[2m│\\033[0m %s' "\$forge_seg" "\$personal_line"
else
  printf '%s' "\$personal_line"
fi
WRAPPER

chmod +x "$PERSONAL"

cat <<EOF

Installed the Forge Heartbeat status-line wrapper.

Files:
  $PERSONAL        ← Forge wrapper (new)
  $WRAPPER_PERSONAL  ← your original status line (preserved)
  $backup  ← backup taken before changes

Inside any Forge harness, your status line will now lead with the
Heartbeat segment, e.g.:

  forge | P2 Auth (3/7) · active: PRJ-002 dev (+1) │ [Opus 4.7 1M] │ ctx ░░░░ 12% │ ...

Outside any Forge harness, your status line is unchanged.

To uninstall:
  mv $WRAPPER_PERSONAL $PERSONAL
EOF
