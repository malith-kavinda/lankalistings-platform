# /forge-review-pr

Framework-aware PR review. Pulls the diff, walks the relevant Forge artifacts (PRD, spec, plan, tracker, companion PRs), and produces a verdict styled to be posted back to the PR.

## How to Use

```
/forge-review-pr <number>              # review and print verdict to session
/forge-review-pr <number> --comment    # also post the verdict as a PR comment
/forge-review-pr <number> --post       # alias for --comment
```

The `<number>` is a GitHub PR number. The skill auto-detects which workspace repo it belongs to.

## When to Use

- The user names a PR by number and asks for a review, second opinion, or merge readiness check.
- The user references a PR a teammate opened and wants a check before approving.
- A docs/spec/plan PR lands in the harness repo and needs a cross-artifact consistency review.
- A code PR lands in one of the code repos and needs to be cross-checked against its spec and plan.

If the user wants a review of *uncommitted* working changes, do that via direct conversation with Claude or `/council` — this skill is for committed PRs only.

## Configuration

Before first run, fill in the workspace repo paths for this engagement in the block below. The harness sits at one path; the code repos sit alongside it. Claude reads these values from this command file at invocation time.

```bash
# === Workspace configuration — fill in before first run ===
HARNESS="<absolute path to this harness>"      # e.g. /Users/you/Work/<workspace-root>/<project>-harness
CODE_REPOS=(
  # "<absolute path to backend repo>"          # e.g. /Users/you/Work/<workspace-root>/<project>-be
  # "<absolute path to frontend repo>"         # e.g. /Users/you/Work/<workspace-root>/<project>-fe
)
# === End workspace configuration ===
```

- `HARNESS` — absolute path to this harness repo. Required.
- `CODE_REPOS` — bash array of absolute paths to sibling code repos that this command should consider when resolving a PR. Leave empty for single-repo engagements (harness only) — the command resolves PRs against `$HARNESS` alone.

## Process

### 1. Resolve the PR

Try `gh pr view` against each configured repo until one succeeds:

```bash
for repo in "$HARNESS" "${CODE_REPOS[@]}"; do
  if (cd "$repo" && gh pr view <N> --json number,title,body,headRefName,baseRefName,author,mergeable,mergeStateStatus,isCrossRepository,headRepositoryOwner,headRepository,files,url,state 2>/dev/null); then
    TARGET="$repo"; break
  fi
done
```

Capture: `title`, `body`, `headRefName`, `baseRefName`, `author`, `state`, `mergeable`, `mergeStateStatus`, `isCrossRepository`, `files[].path`, `url`. The `--repo <owner>/<repo>` form for `gh pr comment` later uses the value from `gh repo view --json nameWithOwner`.

If `isCrossRepository` is true (the PR is from a fork), warn the user before continuing — fork PRs can leak secrets through CI and warrant a more careful posture before pulling and running anything.

**If `state == MERGED` or `state == CLOSED`, run in post-mortem mode**: still execute steps 2–5 against the merged state (or last head for a closed-without-merge PR) so the user gets a clean read on whether the merged content was sound, but skip step 6 (adversarial pass) and step 8 (posting). Frame the verdict as a post-mortem — no rebase suggestions, no "must fix before merge". The value of the review on a merged PR is descriptive, not actionable; running the adversarial pass and offering to post a comment both fight that frame.

### 2. Detect staleness

Force-fetch and compute the merge base:

```bash
(cd "$TARGET" && git fetch origin <headRefName> <baseRefName>)
BASE_SHA=$(cd "$TARGET" && git rev-parse "origin/<baseRefName>")
MERGE_BASE=$(cd "$TARGET" && git merge-base "origin/<headRefName>" "origin/<baseRefName>")
STALE_COMMITS=$(cd "$TARGET" && git log --oneline "$MERGE_BASE..origin/<baseRefName>" -- .)
```

If `STALE_COMMITS` is non-empty, the PR is branched off an older base. Flag this as a **Blocker** unless the changes on base are clearly unrelated to the PR's files — and even then, prefer asking for a rebase. Stale bases commonly produce numbering collisions (AD numbers, Revision indices) that surface as merge conflicts at the worst moment.

### 3. Classify the PR by file paths

Group the files-changed list into one of these classes (a PR can fall into more than one — review the most-impactful subset first, then the others):

| Class | Trigger | What to load |
|---|---|---|
| **Engagement-level docs** | only touches `.forge/project-prd.md`, `.claude/CLAUDE.md`, `.forge/tracker.yaml`, `.forge/discovery/**`, `.forge/checklists/**`, `.forge/team-guide.md` | `.forge/project-prd.md`, `.claude/CLAUDE.md`, `.forge/tracker.yaml` |
| **Spec** | touches `.forge/specs/<ticket>-spec.md` | The spec, the PRD (for scope alignment), `_TEMPLATE-spec.md` (required-sections schema), and harness CLAUDE.md (Architecture Decisions) |
| **Plan** | touches `.forge/plans/<ticket>-plan.md` | The plan, the spec it cites, `_TEMPLATE-plan.md` (required-sections schema), harness CLAUDE.md (Architecture Decisions) |
| **Code** | branch like `feature/<ticket>-*` in one of `${CODE_REPOS[@]}` | `<harness>/.forge/specs/<ticket>-spec.md` and `<harness>/.forge/plans/<ticket>-plan.md`, plus the repo's own CLAUDE.md |

If the branch name does not match `feature/<ticket>-*` for a code PR, ask the user which spec/plan to use rather than guessing — the spec/plan binding is the framework's load-bearing handoff, not something to fabricate.

### 4. Detect companion PRs

Same branch name across repos = a companion set. Check **all states** so a merged-here-but-open-there mismatch surfaces:

```bash
for repo in "$HARNESS" "${CODE_REPOS[@]}"; do
  (cd "$repo" && gh pr list --state all --head <headRefName> --json number,url,title,state)
done
```

When companions exist, review consistency between them: env-var names, AD references, Mermaid diagram syntax, and any framework-locked invariants captured in `.claude/CLAUDE.md` (e.g. config-only environment differences, no env-branching code).

If the companion set has **mixed states** — e.g. harness MERGED but a code-repo companion still OPEN — flag this as Important. The PR body usually says "should be reviewed and merged together"; landing one solo creates a window where the merged repo references decisions that haven't propagated to the others. For implementation sessions this is load-bearing because per-repo CLAUDE.mds are *the* implementation-time context.

### 5. Run framework-specific quality checks

Run all that apply to the PR's class.

#### For engagement-level docs PRs

- **AD numbering collision (PRD).** Compare the new AD numbers in `.forge/project-prd.md` to the numbers already on `origin/<baseRefName>`. If a number on the PR head is already used on base, flag it.
- **AD numbering collision (CLAUDE.md).** Same for `.claude/CLAUDE.md` Architecture Decisions section.
- **Revision number collision.** Compare `### Rev N` headings under `## Revisions` in `.forge/project-prd.md`. The PR's new entry must use a number not already on base.
- **Locked-decision integrity.** If `.claude/CLAUDE.md` or `.forge/project-prd.md` has a locked-decisions table (typically marked DO NOT REVERSE or equivalent), confirm any new AD that contradicts a locked AD edits the original in place rather than appending a contradictory new entry.
- **Tracker truthfulness.** Cross-check `.forge/tracker.yaml` claims against actual artifact state. Always check the *touched* `setup.<gate>.notes` fields — those are the PR's responsibility. *Also* scan untouched `setup.*.notes` for claims that contradict the new state of the artifacts the PR is editing: a sibling note can become stale without being touched. Surface those as housekeeping follow-ups (Important, not Blocker) — the PR didn't introduce them but the user may want a one-line cleanup.
- **Security & Compliance overlap.** If the PR adds a new constraints subsection (regulatory, security, compliance), confirm it does not contradict the existing `## Security & Compliance` section. Cross-references are fine; restatements that differ in substance are not.

#### For spec PRs

- Spec contains all required sections per `_TEMPLATE-spec.md` (Context, Requirements, Acceptance Criteria, Scope Boundaries, Constraints & Dependencies, Open Questions, Input Sources, Revisions).
- If the spec is being edited rather than created, and the spec is in `approved` state per `.forge/tracker.yaml`, a new `### Rev N — YYYY-MM-DD` entry must accompany the change.
- Acceptance criteria are testable (each has a verification path stated or inferable).
- Scope boundaries are explicit ("out of scope" listed, not implied).

#### For plan PRs

- Plan contains all required sections per `_TEMPLATE-plan.md` (Approach, Decisions, Subtasks, Files to modify, Risks, Progress, Notes).
- Plan cites a real spec; the cited spec is `approved` in the tracker.
- Subtasks are session-sized (small enough to be a Claude Code session boundary).
- Pattern references ("follow `<file>`") point to files that exist.

#### For code PRs

- Each acceptance criterion in the spec has a corresponding implementation surface in the diff.
- Files modified intersect with the plan's "Files to modify" list. Extra files touched without a plan note are a finding.
- Walk the engagement's locked invariants from `.claude/CLAUDE.md` against the diff. Common categories to check (calibrate per engagement):
  - **No env-branching code** if the engagement locks "config differs between dev and prod, code does not". Grep the diff for `process.env.NODE_ENV ===`, `if (env ===`, `@Profile("dev")` / `@Profile("prod")`, `System.getenv("ENV")`-style switches.
  - **Auth boundaries** — backend or frontend constraints on auth providers, token storage, RLS usage, etc.
  - **Persistence boundaries** — direct SQL vs. ORM, raw client SDK imports the architecture forbids, etc.
- Walk harness CLAUDE.md NEVER DO list against the diff.

**Dispatch the `backend-reviewer` sub-agent for backend diffs.** When the code PR touches files under `<backend-repo>/`, dispatch the `backend-reviewer` agent (in `.claude/agents/`) via the Task tool to get a framework-specific second opinion on the backend surface — layering / dependency direction, transaction & atomicity boundaries, ORM pitfalls (N+1, lazy-loading, cascade traps), auth coverage on new endpoints, exception swallowing, DI hygiene, concurrency, and migration safety. The agent is stack-neutral by construction: it reads the repo's **Stack Profile** (`<backend-repo>/.claude/CLAUDE.md` `## Backend Stack`) on turn 1 to calibrate its checks to the actual framework / ORM / language in play, rather than assuming a stack. It is **read-only** — it returns a findings table + verdict; you fold its findings into the verdict below (mapping its Blocker/Important/Nit severities onto this command's verdict buckets). Pass it the diff and changed-file paths in the dispatch prompt — each invocation is fresh-context with no memory of this session.

Dispatch the agent **once per backend-touching PR**, after the inline checks above, before the adversarial pass in step 6 — its findings are inputs the adversarial pass should hold in mind (don't re-derive them). If the PR has no backend surface, skip the dispatch. (There is no equivalent frontend-reviewer dispatch — the frontend surface is reviewed inline plus the adversarial pass.)

### 6. Adversarial pass

Run an adversarial pass over the PR. The framework checks in step 5 are pattern-matched against known defects; the adversarial pass is the open-ended "what else could be wrong here" sweep.

**When to skip the adversarial pass:**
- The PR is merged or closed (per step 1's post-mortem rule).
- The PR is a trivial docs change — under ~20 lines, no AD/Revision/tracker edits, no env-var or config changes — *and* the framework checks in step 5 returned clean.

If skipping, say so explicitly in the verdict (one line, e.g. *"Adversarial pass skipped: PR is merged."*) so the reader knows the verdict came from the framework checks alone.

Otherwise, work through this checklist with the inputs already gathered (don't re-fetch):

- Read the full diff (compute from `<merge-base>..origin/<headRefName>` if not already loaded).
- Re-read the Forge artifacts identified in step 3 with the diff in mind.
- Hold the staleness, companion, and quality-check findings from steps 2, 4, 5 (including any `backend-reviewer` dispatch findings) in mind so you don't re-derive them — focus on what's left.
- Engagement-specific anti-patterns to watch for: numbering collisions (AD numbers, Revision indices), env-branching code, tracker.yaml truthfulness drift, terminology drift between docs.
- Beyond the engagement-specific anti-patterns, look for: logic errors, off-by-one issues, missing edge cases, missing tests for new code paths, security issues (input validation, injection, auth bypass), performance regressions, breaking changes to public contracts, and wording / terminology drift in docs.

Output is terse, file:line specific, concrete fixes, no preamble — same format as step 7.

### 7. Produce the verdict

Format:

```markdown
# PR #<N> review — <title>

**Verdict: <block | approve-with-fixes | approve>.**
<!-- For merged/closed PRs, change the verdict line to: -->
<!-- **Status: MERGED** (commit `<sha>`, <merged-at>). **Post-mortem verdict: <clean | drift-found>.** -->

<one-paragraph framing — what's working, what's not, scope of issues>

## Blockers (must fix before merge)

**1. <one-line title>.** <why it matters, file:line>. → <concrete fix>.

<repeat>

## Important (should fix)

<repeat>

## Nits

<repeat>

## Companion PRs (if any)

<list of companion PRs with their own status — clean / has-issues>

## Recommendation

<2-3 sentences: what unblocks this, what can land separately>
```

The tone is: terse, fix-forward, no padding. Each finding cites a file path and (where applicable) a line number, names what is wrong in one sentence, and gives a concrete fix in another sentence. Avoid the language of judgment ("this is sloppy", "you forgot to..."); use the language of state ("AD #9 still reads X but the new AD #14 introduces Y — edit AD #9 in place").

### 8. Post or print

If `--comment` or `--post` was passed:

```bash
gh pr comment <N> --repo <owner>/<repo> --body "$(cat <<'EOF'
<verdict markdown>
EOF
)"
```

Always use a HEREDOC for the body to keep markdown formatting intact. Print the URL of the posted comment so the user can open it.

If neither flag is present, print the verdict to the session for the user to copy or edit. Do not post on their behalf without the flag.

## Must Not

- **Post a comment without an explicit `--comment` / `--post` flag.** PR comments are visible to the team and persistent. The user should opt in each time, even if they did the previous time.
- **Use `gh pr review --approve` or `gh pr review --request-changes`.** Those are heavier verbs that mark the PR's review state. This skill only posts comments. If the user wants the PR formally approved, ask them to do that themselves.
- **Run on a fork PR without warning.** Fork PRs can carry workflow changes that exfiltrate secrets if run blindly. If `isCrossRepository` is true, surface that to the user and confirm before pulling the head ref.
- **Fabricate spec/plan paths.** If a code PR's branch name doesn't match `feature/<ticket>-*` or the named spec/plan is missing, ask the user. The framework's strength is the spec/plan binding — guessing breaks it.
- **Re-derive staleness, companion, or check findings during the adversarial pass.** They were already computed in steps 2, 4, 5 — focus the adversarial pass on what's left.

## Output

- Structured verdict with Blockers / Important / Nits, file:line citations, concrete fixes.
- Final verdict line: `block` | `approve-with-fixes` | `approve`.
- If posted: the comment URL.
- If companion PRs exist: a one-line status per companion (`clean` / `has-issues — see <url>`).
