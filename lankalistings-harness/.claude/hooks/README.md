# Forge Harness — Claude Code Hooks

Hooks are deterministic shell commands that Claude Code runs automatically at specific lifecycle moments. They close the gap between `CLAUDE.md` guidance (which the model can forget under pressure) and runtime enforcement (which it cannot).

**`CLAUDE.md` is guidance. Hooks are laws.**

See `docs/claude-code-hooks-deepdive.md` in the harness repo for the full rationale. This README is the operator's guide.

## What's Installed

All sixteen hooks are wired in `../settings.json` and point at scripts in this directory.

| Script | Event | Ships working? | What it enforces |
|---|---|---|---|
| `block-dangerous-bash.sh` | `PreToolUse` Bash | generic | Blocks `rm -rf /`, `sudo rm`, `curl \| sh`, DROP TABLE, fork bombs, `git reset --hard`, force-push to main/master/develop/staging/production |
| `protected-paths.sh` | `PreToolUse` Edit/Write/MultiEdit | generic defaults | Blocks edits to CI/CD configs, infra, charts, migrations |
| `guard-spec-leapfrog.sh` | `PreToolUse` Edit/Write/MultiEdit | generic (requires `yq`) | Blocks creation/edit of feature specs (`.forge/specs/<x>-spec.md`) until Gate 2 has passed AND foundation is `done`. Foundation specs (`.forge/specs/foundation/**`) are exempt. Reads `.forge/tracker.yaml` `setup.architecture.status` + `setup.foundation.status`. |
| `guard-spec-approval.sh` | `PreToolUse` Edit/Write/MultiEdit | generic | Blocks transitions to `Status: approved` on **feature** spec files (`.forge/specs/<x>-spec.md`) unless the file carries a `Reviewed-via: /forge-spec-review` annotation in either the new edit or the existing file on disk. Enforces that `/forge-spec-review` (skill + `spec-reviewer` sub-agent) actually ran before approval. Foundation specs (`.forge/specs/foundation/**`) are exempt — they go through the manual review cycle alongside the foundation plans. |
| `guard-plan-approval.sh` | `PreToolUse` Edit/Write/MultiEdit | generic | Blocks transitions to `Status: approved` on plan files (`.forge/plans/**/*-plan.md`) unless the file carries a `Reviewed-via: /forge-plan-review` annotation in either the new edit or the existing file on disk. Enforces that `/forge-plan-review` (skill + `plan-reviewer` sub-agent) actually ran before approval. Foundation plans and feature plans both gated. |
| `inject-relevant-risks-spikes.sh` | `PreToolUse` Edit/Write/MultiEdit | generic (requires `yq`) | Advisory only: prints open accepted risks + spikes from `.forge/tracker.yaml` to stderr whenever a spec or plan is being written/edited. Visible in transcript; never blocks. |
| `inject-spec-context.sh` | `UserPromptSubmit` | generic | Auto-attaches `.forge/specs/<name>.md` or `.forge/plans/<name>.md` when the prompt contains `@spec:<name>` or `@plan:<name>` |
| `inject-gate-state.sh` | `SessionStart` | generic (requires `yq`) | Prints engagement-gate state (Gate 1 / Gate 2 / foundation / Gate 3 status, last-run dates, open risk + spike counts and contents) into Claude's context at every session start. Read-only; never blocks. |
| `regen-tracker-dashboard.sh` | `PostToolUse` Edit/Write/MultiEdit | generic (requires `yq`) | When `.forge/tracker.yaml` is edited, regenerates `.forge/dashboard/tracker.js` so the double-click HTML dashboard stays in sync. No-op if `.forge/dashboard/` doesn't exist. Fail-open if `yq` missing. |
| `phase-scope-skills.sh` | `PostToolUse` Edit/Write/MultiEdit + manual | generic (requires `yq` + `jq`) | When `.forge/tracker.yaml` is edited, derives the current engagement phase from `setup.*` gate statuses (via `.claude/lib/derive-phase.sh`) and rewrites `.claude/settings.local.json`'s `skillOverrides` so out-of-phase skills load as `"off"` (description hidden from session). Reads each `.claude/skills/*/SKILL.md` front-matter `phases:` field; skills without `phases:` stay always-on. Writes apply to the **next** session (Claude Code reads settings before hooks run) — prints a one-line restart nudge on change. Also runnable manually for bootstrapping projects whose tracker.yaml hasn't been edited since this hook landed: `./.claude/hooks/phase-scope-skills.sh`. Idempotent; silent on no-op. |
| `track-token-usage.sh` | `Stop` | generic (requires `jq`) | Captures the latest assistant turn's `usage` block from Claude Code's per-session JSONL and appends one row to `~/.claude/forge-usage.jsonl` (per-developer, per-machine, append-only). Tags every row with `ts`, `session_id`, `assistant_message_id`, `user_email`, `project_name`, `phase`, `model`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`. Phase resolves via the shared `.claude/lib/derive-phase.sh` helper. Outside a Forge harness (no `.forge/` in cwd ancestry): row written with `project_name: "<non-forge>"` and `phase: "n/a"`. Atomic append under `flock` for concurrent sessions. Failure-tolerant: all errors swallowed → exit 0; details logged to `~/.claude/forge-usage.error.log`. < 200ms target (NFR-1). See `docs/specs/2026-05-14-token-usage-tracking.md`. |
| `regen-usage-dashboard.sh` | `Stop` (after `track-token-usage.sh`) | generic (requires `jq`) | Derives two project-scoped artifacts from the global `~/.claude/forge-usage.jsonl`: (1) `<harness>/.forge/usage.jsonl` — raw filtered rows, deduped by `assistant_message_id`, the **primary developer-facing interface** for `grep`/`jq`/`tail -f` inspection; (2) `<harness>/.forge/dashboard/usage.js` — aggregated `window.USAGE = {...}` JSON consumed by Section 04 of the dashboard. Both files are gitignored (per-developer-per-machine state). Outside any Forge project: exits silently. Same failure-tolerance contract as `track-token-usage.sh`. |
| `tracker-freshness.sh` | `Stop` | generic (requires `jq` for user-visible output) | Soft-warning Stop hook: emits a `systemMessage` JSON object on stdout when `.forge/specs/**/*-spec.md` or `.forge/plans/**/*-plan.md` was modified in the working tree but `.forge/tracker.yaml` was not. Claude Code renders the message inline in the terminal. Always exits 0 — the session ends regardless. Fails open if not in a git repo, or degrades to debug-log stderr if `jq` is unavailable. |
| `forge-recap.sh` | `Stop` | generic (uses `git`, requires `jq` for user-visible output) | **Forge Heartbeat — the "beat".** State-derived session recap, emitted as a `systemMessage` JSON object on stdout so Claude Code renders it inline in the terminal (zero model-context tokens). Reads `git diff --name-only HEAD` for spec/plan/tracker changes, `.forge/tracker.yaml` for phase + active delivery phase, and `.forge/usage.jsonl` filtered by `session_id` for token totals. Interesting-or-silent: emits nothing when no spec/plan/tracker files changed this session. Skips on `stop_hook_active = true` re-fires to avoid double-printing. Always exit 0. < 200ms target. See `docs/engineering/specs/2026-05-21-forge-heartbeat-spec.md`. |
| `lint-and-typecheck.sh` | `PostToolUse` Edit/Write/MultiEdit | **template — fill in** | Runs lint + typecheck after every edit |
| `verify-before-stop.sh` | `Stop` | **template — fill in** | Runs tests before Claude ends a turn |

The fourteen generic scripts work immediately on a fresh project (the `yq`-dependent and `jq`-dependent hooks need those tools — see Dependencies below). The two marked **template — fill in** ship as no-op skeletons with commented-out examples; wire up your stack's commands during project bootstrap.

### Stop hook execution order

The `Stop` event runs five hooks in registration order — capture first, derive second, advisory nudges third, slow project checks last:

1. `track-token-usage.sh` — fast (<200ms); appends to the global usage file. Runs first so capture happens even if a later hook fails.
2. `regen-usage-dashboard.sh` — fast (<200ms); derives the project mirror + dashboard data. Reads what step 1 just wrote, so order matters.
3. `tracker-freshness.sh` — advisory `systemMessage` if specs/plans were edited without a tracker update.
4. `forge-recap.sh` — Heartbeat beat; emits the session recap as a `systemMessage` (reads what steps 1–2 wrote so the recap can quote session token totals). Interesting-or-silent.
5. `verify-before-stop.sh` — project tests; potentially slow (600s timeout). Last so it doesn't block the cheap capture.

**Why `systemMessage` JSON, not plain stderr:** Claude Code's Stop hooks at exit 0 send plain stderr to the debug log only, not the user's terminal. The documented user-facing channel for non-blocking Stop output is a `{"systemMessage": "..."}` JSON object on stdout (see [hooks docs — Exit Code Behavior + JSON Output Fields](https://code.claude.com/docs/en/hooks.md)). Earlier revisions of `tracker-freshness.sh` wrote to plain stderr and were silently invisible — fixed alongside the Heartbeat recap in v0.23.0.

## Dependencies

Two external tools, both common dev dependencies:

**`yq`** (Mike Farah's Go implementation, v4+) — required by `inject-gate-state.sh`, `guard-spec-leapfrog.sh`, `inject-relevant-risks-spikes.sh`, `regen-tracker-dashboard.sh`, `phase-scope-skills.sh`, and `.claude/lib/derive-phase.sh` (called by both `phase-scope-skills.sh` and `track-token-usage.sh`). Used to parse `.forge/tracker.yaml`. All fail open with a one-line note on stderr if `yq` is missing.

**`jq`** — required by `track-token-usage.sh`, `regen-usage-dashboard.sh`, and `phase-scope-skills.sh`. Used to parse Claude Code's session JSONL files, the global usage file, and to build settings.local.json. All fail open if `jq` is missing.

```bash
brew install yq jq        # macOS
# yq: see https://github.com/mikefarah/yq#install
# jq: see https://stedolan.github.io/jq/download/
```

Without these tools the affected hooks behave as no-ops; the rest of the hook stack is unaffected.

## Token usage tracking

Two of the Stop hooks (`track-token-usage.sh`, `regen-usage-dashboard.sh`) implement per-developer token capture per the v0.18 token-usage-tracking spec (`docs/specs/2026-05-14-token-usage-tracking.md`). Quick reference:

- **Global source:** `~/.claude/forge-usage.jsonl` (per-developer, per-machine, append-only, lives outside any repo).
- **Project mirror:** `<harness>/.forge/usage.jsonl` (raw filtered rows, deduped, **primary developer-facing interface**). Gitignored.
- **Dashboard data:** `<harness>/.forge/dashboard/usage.js` (`window.USAGE = {...}` aggregated). Gitignored. Visualized in Section 04 of `dashboard/index.html`.
- **Error log:** `~/.claude/forge-usage.error.log` — anything that goes wrong in the hooks goes here, never to Claude.
- **Disable:** comment out the two entries in `../settings.json` under `Stop`. No further cleanup needed.
- **Manual regen:** if the dashboard or mirror looks stale, run `echo '{"cwd":"'"$(pwd)"'"}' | ./.claude/hooks/regen-usage-dashboard.sh`.
- **Inspect raw data:** `cat ~/.claude/forge-usage.jsonl | jq` (global, all projects) or `cat .forge/usage.jsonl | jq` (current project only).
- **Ad-hoc rollups:** until a dedicated command lands, use the raw files directly:
  - Current project: `cat .forge/usage.jsonl | jq -c .`
  - Cross-project: `cat ~/.claude/forge-usage.jsonl | jq -c .`
  - Group by project: `cat ~/.claude/forge-usage.jsonl | jq -s 'group_by(.project_name) | map({project: .[0].project_name, turns: length, input: (map(.input_tokens) | add), output: (map(.output_tokens) | add)})'`

  *A `/forge-usage` slash command is in the spec but deferred from v1 — the dashboard panel + raw files cover ad-hoc needs for now.*

## Status line segment (the Forge Heartbeat "resting pulse")

The harness ships a status-line **segment provider** at `.claude/lib/forge-statusline-segment.sh`. It is not a hook — Claude Code invokes it via the *per-developer* `statusLine` setting, not via the project's `settings.json`. The harness deliberately does **not** register `statusLine` in `settings.json`, because the status line is the developer's personal real estate.

Each developer adds the segment to their own personal status-line script by including this snippet (or the equivalent) — three lines, runs the provider only when it exists, fails open if it does not:

```bash
# In your personal status-line script (the one wired into ~/.claude/settings.json
# `statusLine.command`). $stdin holds the statusLine JSON Claude Code piped in.
forge_segment_path="$(echo "$stdin" | jq -r '.workspace.project_dir // .cwd // ""')/.claude/lib/forge-statusline-segment.sh"
[ -x "$forge_segment_path" ] && forge_seg=$(echo "$stdin" | "$forge_segment_path") && [ -n "$forge_seg" ] && printf '%s | ' "$forge_seg"
```

Inside any Forge harness the snippet emits something like:

```
forge | P2 Auth (3/7) · active: PRJ-002 dev (+1) | <rest of your status line>
```

Outside any Forge harness it emits nothing — the provider exits 0 with no output, and the trailing `| ` is skipped because `forge_seg` is empty.

Notes:
- The `statusLine` mechanism is **terminal-only** (Claude Code CLI). The desktop app and VS Code extension do not render it. The Forge harness is operated from terminal Claude Code, so this is accepted.
- Zero model-context tokens: `statusLine` output is terminal UI chrome and never enters the conversation.
- The provider exposes a `--self-test` mode: `./.claude/lib/forge-statusline-segment.sh --self-test`.

## Why Hooks Exist

Rules in `CLAUDE.md` are probabilistic — the model knows them but may not honor them under context pressure. Hooks are deterministic:

1. **Tighten the feedback loop from minutes to seconds.** A lint error caught at `PostToolUse` is fixed on the next turn, not after CI finishes ten minutes later.
2. **Shrink the model's responsibility surface.** Every rule in a hook is one less rule the model must remember.
3. **Prevent cascading errors.** Bad edits caught immediately don't propagate into files that depend on them.
4. **Make quality non-optional.** A hook cannot be ignored under pressure. `CLAUDE.md` can.
5. **Teach the model in-session.** Claude reads the stderr from exit-2 hooks and self-corrects — by edit #20 it's writing project-conventional code on the first try.

## Customizing

- **Add protected paths** — edit `protected-paths.sh`, extend the `protected` array with project-specific directories (payment code, cryptographic material, production configs).
- **Adjust dangerous patterns** — edit `block-dangerous-bash.sh`. Keep the false-positive rate low; noisy gates get disabled.
- **Wire up lint/typecheck** — edit `lint-and-typecheck.sh` per file type. Keep each invocation under 3 seconds. Prefer incremental tools (Biome, Ruff, file-scoped TSC).
- **Wire up Stop verification** — edit `verify-before-stop.sh`. Prefer affected-file tests. Set a realistic timeout in `../settings.json` if you need more than 60s (the file already sets 600s for this hook).

## Principles

- **Fast beats thorough at PostToolUse.** Under 3 seconds or session latency suffers.
- **Exit 2 with stderr is the whole mechanism.** Claude reads stderr and self-corrects on the next turn. For `UserPromptSubmit`, stdout is prepended to Claude's context instead.
- **`stop_hook_active` prevents infinite loops.** Any `Stop` hook that blocks on conditions Claude can't fix will spiral — check the flag and bail on the second firing.
- **Hooks run unsandboxed with your credentials.** Review changes to `../settings.json` and every file in this directory like production code — a hostile hook can exfiltrate secrets.

## Debugging

1. Type `/hooks` in Claude Code — confirms Claude Code sees the hook.
2. Run a hook manually:
   ```bash
   echo '{"tool_input":{"file_path":"foo.ts"}}' | .claude/hooks/lint-and-typecheck.sh
   ```
3. Check matcher case. `Edit|Write` matches, `edit|write` does not.
4. Exit-2 messages must go to **stderr** (not stdout) to reach Claude. Exception: `UserPromptSubmit` where stdout *is* the injection channel.
5. Timeout expired? Default is 60s. `verify-before-stop.sh` is already set to 600s in `settings.json`.

See the hooks deep-dive doc in the harness repo for the longer version.

## Relationship to the Forge Quality Model

Hooks are the **in-session tier** of the quality ladder. They do not replace project-level lint/test/build, adversarial review, CI, or canary — they make those downstream gates hit far less often:

```
 T0  In-agent hooks            seconds    Claude never "ships" a broken edit
 T1  Project lint/test/build   seconds    Developer-invoked project validation (dedicated /forge-check command TBD)
 T2  Adversarial review        seconds    Adversarial review of the diff (dedicated command + sub-agent TBD; currently via direct conversation or /council)
 T3  PR CI                    minutes    Mutation tests, SAST, E2E
 T4  Canary / SLO             minutes+   Runtime regression catches
```

A well-engineered T0 means the PRs reaching T3 are already green.
