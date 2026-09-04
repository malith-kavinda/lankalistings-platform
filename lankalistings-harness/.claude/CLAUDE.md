# LankaListings

<!--
  Project constitution — the primary context file for Claude Code on this project.
  Loads every session. Keep this file focused on operational rules and locked decisions.

  Detail content has been moved to load-on-demand locations:
  - Spec lifecycle  → .claude/rules/specs.md   (loads when editing .forge/specs/**)
  - Plan lifecycle  → .claude/rules/plans.md   (loads when editing .forge/plans/**)
  - Tracker + gates → .claude/rules/tracker.md (loads when editing tracker.yaml et al.)
  - Git/PR/worktree → .claude/rules/git-conventions.md
  - Hook details    → .claude/hooks/README.md
  - Section schemas → .forge/specs/_TEMPLATE-spec.md, .forge/plans/_TEMPLATE-plan.md
  - Framework rationale → .forge/forge-harness-framework.md (read on demand)

  Bootstrap-time: fill in the placeholder sections with real project content.
-->

## Project Overview

LankaListings is a **greenfield** Sri Lankan general classifieds marketplace. Any registered user can
list an item for sale across nine broad categories (vehicles, property, land, jobs, electronics,
services, home & garden, fashion, other); **every listing is human-moderated before it becomes publicly
visible**; standard publication is free and a seller pays only to *feature* an already-approved ad.
Prices are LKR, locations are Province → District → City, and the MVP UI is English-only.

Three client surfaces are in MVP scope — a responsive public marketplace (`frontend-web`), an operator
management portal (`management-portal`), and a mobile app (`mobile`, Android + iOS) — served by a
**polyglot microservice backend** (Spring Boot + FastAPI) that does not exist yet.

**Project state as of 2026-08-24:** pre-Gate-1. Three client skeletons boot and render hard-coded
fixtures; no backend code exists; the workspace is not yet a git repository. The discovery input layer
is complete and lives in `.forge/discovery/` — read `.forge/discovery/docs/README.md` first, because
every statement in that pack is tagged `[LOCKED]` / `[DERIVED]` / `[PROPOSED]` and the distinction
matters.

**Read this before proposing anything:** the pack contains **34 open questions** (`.forge/project-prd-signals.md`).
Three of them change the plan's shape — whether in-app messaging is in scope (OQ-01), whether AI/OCR ad
intake is in scope (OQ-02), and the complete absence of any team size or delivery window (OQ-20). Do not
size, date, or plan around them; surface them.

## Stack

Nothing is committed on the backend yet — the service split below is the Gate-2 **proposal** from
`.forge/discovery/docs/03-architecture.md` §3, not a locked decision.

**Clients (committed, in `advertising/` as npm workspaces):**

- **`frontend-web`** — Next.js 14.2 (App Router), React 18.2, TypeScript 5.4, Tailwind 3.4, `lucide-react`
- **`management-portal`** — Vite 5.3, React 18.2, TypeScript 5.4, Tailwind 3.4, `lucide-react`
- **`mobile`** — Expo ~51, React Native 0.74.7, React 18.2, TypeScript 5.4, `@expo/vector-icons`

**Backend (proposed, greenfield):**

- **Spring Boot** — `identity-service` (auth, accounts, roles), `listing-service` (the Advertisement
  aggregate, taxonomy, moderation, search), `payment-service` (plans, purchases, settlement)
- **FastAPI** — `admin-service` (management-portal CRUD/BFF, KPIs, reports), `media-service` (image
  pipeline, and OCR/AI extraction if OQ-02 goes in scope)
- **API gateway** in front of all five
- **PostgreSQL** per service, S3-compatible object storage for ad imagery — both `[PROPOSED]`, Gate 2 decides

**Known gaps in the committed clients:** no test framework in any workspace; `lint` is aliased to
`tsc --noEmit` so **no linter is actually enforced**; no `.env.example`; no CI; no API client layer; no
git history.

## Architecture Decisions (DO NOT REVERSE)

Locked decisions only. The full decision log — including 16 `[PROPOSED]` engineering decisions awaiting
Gate 1/2 confirmation and 34 open questions — is `.forge/discovery/docs/08-decision-log.md`.
**Do not promote a row here until its gate confirms it.**

| # | Decision | Why | Date |
|---|----------|-----|------|
| 1 | An advertisement is public **only** after admin approval | Quality and spam control is the product's core promise. Enforced server-side on every read path, never in the UI | 2026-08-24 |
| 2 | Standard publication is free; a seller pays only to feature an **approved** ad | Supply-side growth first, monetise attention. Payment capture is never built before an approvable ad exists | 2026-08-24 |
| 3 | Any user may create an advertisement — one account type sells and buys | Open marketplace, no seller onboarding gate | 2026-08-24 |
| 4 | Nine broad categories, fixed for MVP | Generalist classifieds positioning | 2026-08-24 |
| 5 | Google OAuth **and** email/password | Low-friction sign-up without excluding non-Google users | 2026-08-24 |
| 6 | Sri Lanka only; LKR; Province → District → City | Single-market product | 2026-08-24 |
| 7 | English-only UI at MVP; Sinhala and Tamil are named future work | Scope control with the future need recorded, so copy is externalised from day one | 2026-08-24 |
| 8 | Build order: foundation → accounts → ad creation/moderation → discovery → featured payment → hardening | Each stage is the precondition of the next; payment last is a correctness constraint, not a priority call | 2026-08-24 |
| 9 | Three client surfaces in MVP: public web, management portal, **and mobile** | Product-owner decision. Mobile is a *surface*, not a trailing phase — parity is an acceptance criterion of every milestone (AC-11) | 2026-08-24 |
| 10 | The backend is **microservices**, using **both Spring Boot and FastAPI**; FastAPI serves the management portal's CRUD surface | Product-owner decision. See risk R-ARCH-01 — this is the largest single cost in the plan and it lands entirely before the first user-visible feature | 2026-08-24 |

## Reference Map

| What | Where |
|------|-------|
| Project PRD (live contract) | `.forge/project-prd.md` |
| PRD signals (live OQs) | `.forge/project-prd-signals.md` — open + partial open questions, anchored to PRD sections and (optionally) blocking-features. Selectively loaded by `spec-reviewer` via the `Blocks` column. |
| PRD history (audit trail) | `.forge/project-prd-history.md` — resolved open questions and PRD revisions. Append-only; rarely needs to be read. |
| Live feature index | `.forge/features.md` — regenerated by `/forge-decompose`, updated row-by-row through each feature's lifecycle |
| System architecture | `.forge/design/architecture.md` |
| Team daily playbook | `.forge/team-guide.md` |
| Tracker (live state) | `.forge/tracker.yaml` |
| Tracker dashboard | `.forge/dashboard/index.html` — double-click to open |
| Forge methodology (full) | `.forge/forge-harness-framework.md` — read on demand for *why* questions; not needed for routine work |
| Spec template + schema | `.forge/specs/_TEMPLATE-spec.md` |
| Plan template + schema | `.forge/plans/_TEMPLATE-plan.md` |
| Quality + gate checklists | `.forge/checklists/` |
| Engagement gate-run audit | `.forge/engagement-gate-runs.md` |
| Spec lifecycle rules | `.claude/rules/specs.md` (path-scoped) |
| Plan lifecycle rules | `.claude/rules/plans.md` (path-scoped) |
| Tracker + gate audit rules | `.claude/rules/tracker.md` (path-scoped) |
| PRD trichotomy + OQ lifecycle rules | `.claude/rules/prd.md` (path-scoped — loads on `project-prd*.md`) |
| Git / PR / worktree | `.claude/rules/git-conventions.md` |
| Hook operator guide | `.claude/hooks/README.md` |
| **Discovery pack (read first)** | `.forge/discovery/docs/README.md` — the 8-document engineering pack, with a `[LOCKED]`/`[DERIVED]`/`[PROPOSED]` provenance tag on every material statement |
| Design-asset inventory | `.forge/discovery/feature-inventory.md` — what is designed, what needs redesigning, and the 11 surfaces with no design at all |
| Critical flows | `.forge/discovery/flows/` — seller post-to-live, featuring payment |
| Design systems (source) | `../stitch_advertising/lankalistings/DESIGN.md` (consumer) · `../stitch_advertising/lankalistings_operational_interface/DESIGN.md` (operator). **Two separate token sets — never merge them; they assign different values to the same token names** |
| Stitch screen exports | `../stitch_advertising/<screen>/code.html` + `screen.png` — visual specifications, not shippable code |
| Public web repo | `../frontend-web/` — Next.js. `CLAUDE.md` + `## Frontend Stack` profile not yet authored |
| Management portal repo | `../management-portal/` — Vite + React. `CLAUDE.md` + `## Frontend Stack` profile not yet authored |
| Mobile repo | `../mobile/` — Expo RN. `CLAUDE.md` + `## Frontend Stack` profile not yet authored |
| Backend repos | Not created. Five services + gateway, proposed in `.forge/discovery/docs/03-architecture.md` §3 |
| Session starter | `./forge-start.sh` |
| Personal status-line installer (run once per developer machine) | `./install-personal-statusline.sh` — wires the Forge Heartbeat segment into your `~/.claude/statusline.sh`. Idempotent. After running once, every Forge harness on this machine automatically shows the `forge | …` segment on the left of your status line. |

## Session Start

Open a Claude Code session via `./forge-start.sh`. The script inventories `.forge/discovery/`, reads `setup.*` from `.forge/tracker.yaml`, and sends Claude an opening prompt with a **turn-1 read-only protocol**: read only this CLAUDE.md + `tracker.yaml` + the discovery materials, summarize what's understood, propose one concrete next action, and stop. Authoring happens in later turns through interactive flows (`forge-prd-author`, `/forge-arch-probe`, `/forge-decompose`, `/forge-spec-review`, `/forge-plan-review`).

## Workflow Phases

```
Spec → Plan → Implement → Check → Review → Ship → Reflect
```

For new projects: `Discovery → Project Brief → Decompose` runs once before the standard sequence begins.

**Front door:** to drive a feature through this whole sequence, invoke **`/forge-deliver <ticket>`** — the orchestrator that runs Spec → … → Reflect with the gates and human checkpoints. Do not hand-run the per-phase skills (`forge-spec-author`, `forge-wave-decompose`, …) individually; `/forge-deliver` sequences them. (Asking in plain language — "how do I start `<ticket>`?" — routes you there via the `forge-feature-flow` skill.)

| Phase | Output | Gate |
|-------|--------|------|
| **Spec** | `.forge/specs/<ticket>-spec.md` | Requirements approved before planning |
| **Plan** | `.forge/plans/<ticket>-plan.md` | Approach approved before coding |
| **Implement** | Code in worktree | — |
| **Check** | Lint, tests, build pass | All mandatory checks pass |
| **Review** | Diff verified against spec + plan | Implementation matches intention |
| **Ship** | PR with spec/plan context | — |
| **Reflect** | Updates to CLAUDE.md, rules, or templates; findings → lessons promotion | At least one artifact updated |

**No phase is skipped.** No implementation begins without an approved spec and plan. **Reflect is mandatory** after every shipped feature — answer (1) what worked, (2) what didn't, (3) what should change in the framework, and (4) walk `.forge/specs/<feature>-findings.md` to promote any generalizable findings to `.forge/lessons.md`. If no file changes, Reflect wasn't done.

## Quality Gates

### Mandatory (no exceptions)
- Spec reviewed and approved before planning starts
- Plan reviewed and approved before coding begins
- Lint, tests, and build (or type checks) pass
- Diff reviewed against spec and plan

### Recommended (skip with justification)
- Security/vulnerability scan (application code) — for auth, data handling, API endpoints
- Dependency-vulnerability CI gate (supply chain) — standing Build & CI gate, fails the build on dependency CVEs ≥ a configurable CVSS threshold; wired once in Foundation (see `.forge/security/` + framework §4.10), confirmed green per task rather than re-decided
- Adversarial code review — via direct conversation with Claude or `/council`
- Browser QA — for user-facing UI work

### Review Ownership

In AI-assisted delivery, specs and plans are where review effort matters most — a wrong plan produces wrong code that no amount of code review can efficiently fix.

| Artifact | Reviewer |
|----------|----------|
| Foundational specs/plans (auth, data model, navigation) | Lead |
| Standard specs/plans | Peer — the dev who didn't write it |
| Code diff | Verified against spec + plan (lighter — upstream gates did the hard work) |

## Compounding Engineering

Every time the AI makes a mistake that will recur, add a rule to prevent it.

1. Decide: one-off or recurring pattern?
2. If recurring: add a rule to this CLAUDE.md (project-wide) or `.claude/rules/` (path-scoped).
3. Rules must be actionable: "use X instead of Y" — not narrative explanations.

This is the primary mechanism by which the harness gets smarter over time.

## Boundaries

### ALWAYS DO
- Run lint and tests after every code change
- **No self-approval on gates. Show the receipts.** When claiming any gate or verification has passed (lint, tests, typecheck, build, spec/plan ready, diff-matches-spec, ready-to-ship), list the specific commands run and their output — not just "tests pass" or "looks good." For audited gates (`/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose`), the verdict always comes from the developer, never from Claude. *Why:* hand-waving claims let bugs through that the evidence would have caught; commands + output give the developer something to verify rather than trust.
- **At session start, reconcile the engagement-evolving sections of this CLAUDE.md against the injected gate-state.** The `inject-gate-state.sh` SessionStart hook prints the authoritative engagement status at the top of every session. Compare it against `## Active Context`, `## Stack`, `## Common Commands`, and `## Reference Map`'s app-repo rows. If any of those describe an engagement state earlier than what the tracker now reports, flag the drift as the first item of turn 1, propose the specific edits, and offer to apply them before continuing. Actual edits land on turn 2 once the user agrees. *Why:* the injected gate-state block is authoritative; the listed CLAUDE.md sections are derivatives that go stale at every gate passage.
- **At workflow phase boundaries, proactively deliver the next session's opening prompt.** Whenever you recommend, imply, or otherwise hand off to a fresh Claude Code session — drafting → review, review → next-phase authoring, gate-N → gate-N+1, plan approved → implementation, ship → next-feature spec — produce the full copy-pasteable opening prompt in the same turn. Don't wait for the user to ask. The prompt must be **self-contained**: read paths in order, the task, locked decisions made in the outgoing session, turn-1 discipline ("no writes on turn 1"). Format inside a fenced ```` ```markdown ``` ```` block so it copies in one click; usage notes go *outside* the fence. If the next phase has a skill, the prompt **invokes** the skill rather than duplicating its logic. Don't trigger on mid-phase pivots or trivial subtasks. *Why:* the outgoing session has full context; the next session starts cold. Without the prompt, framing falls on the user — who has *less* context than the session that just completed.
- Follow patterns referenced in the plan — if the plan says "follow UserService", follow it
- Update the plan's `## Progress` section before ending any implementation session
- Open a new Claude Code session at subtask boundaries when context feels heavy
- Ask `git status` before committing to avoid staging unintended files
- Update `.forge/tracker.yaml` when feature state changes
- Ask for explicit approval status when finishing work on a spec or plan
- When applying upstream forge-harness changes, invoke the `harness-sync-reviewer` sub-agent (in `.claude/agents/`) via the Task tool at the end of the sync, passing the upstream forge-harness path and the from/to version range. Read findings, fix blockers, decide on majors, then bump `tracker.yaml.harness_version`. *Why:* changelog application drifts silently — a step skipped, a customization clobbered, a path-rewrite missed — and divergence compounds across syncs if not caught at the application moment.
- When adding a new skill to `.claude/skills/`, declare its phase scope in `SKILL.md` front-matter `phases:` (e.g. `[discovery]`, `[foundation, engineering]`). Omit only for skills meant to be always-on. The `phase-scope-skills.sh` hook hides out-of-phase skills from session context — a missing field defaults to always-on.

### ASK FIRST
- Install a new dependency (any package manager)
- Change database schema or migrations
- Deviate from the approved plan's approach
- Add a new environment variable or configuration key
- Choose the authentication strategy or provider
- Make any change that affects another developer's in-progress worktree

### NEVER DO
- Commit secrets, keys, credentials, or `.env` files
- Commit directly to `main`
- Modify CI/CD pipeline configuration without lead approval
- Delete or overwrite another developer's in-progress work
- Silently change a spec after it has been approved — always add a revision entry (see `.claude/rules/specs.md`)
- Skip mandatory quality gates
- Start implementation without an approved spec and plan
- **Write to any file on turn 1 of a fresh session.** A session opens with the read-only `./forge-start.sh` protocol — orient, summarize, propose one next action, stop. Authoring happens in later turns via interactive flows that interview or surface tradeoffs *before* writing. Multi-step requests like *"run discovery → write PRD → build it"* are NOT authorization to chain — do the first step and stop. *Why:* on first contact Claude eagerly loads everything and starts drafting, which has historically burned ~150K context on turn 1 and silently leapfrogged the gates.

## Hooks

Hooks in `.claude/hooks/` are deterministic — they run on every relevant tool call and cannot be forgotten mid-session. Five hooks require [`yq`](https://github.com/mikefarah/yq) to parse `.forge/tracker.yaml`; two require `jq`. All fail open if their dependency is missing.

If a hook blocks, treat its stderr as authoritative. Don't work around it.

**Full operator guide and per-hook detail:** `.claude/hooks/README.md`.

## Role Delegation

Multi-pass reviewers are wired and enforced by hooks:

- **`/forge-spec-review <path>`** — `spec-reviewer` sub-agent across up to 2 passes (Pass 1 audits including input-side gaps as dimension §12; Pass 2 verifies fixes); applies Blocker/Important fixes between passes; asks human for final approval before flipping `Status: approved`. Feature specs only — foundation specs exempt.
- **`/forge-plan-review <path>`** — same shape for plans (foundation and feature plans both supported).
- **`/forge-review-pr <number>`** — framework-aware GitHub PR review across configured workspace repos. Pulls diff, classifies the PR, runs framework-specific quality checks + an adversarial pass, produces a Blocker/Important/Nit verdict. Optional `--comment` posts to the PR.

Adversarial code review and security review on uncommitted working diffs still run via direct conversation with Claude or `/council`.

## Common Commands

> ⚠️ **These are the commands that exist today, and they are not yet trustworthy as gates.**
> `lint` in all three client workspaces is aliased to `tsc --noEmit` — it is a typecheck, not a lint.
> There is **no test command anywhere**. Foundation slices F-008 and F-011 fix both. Until they land,
> "lint and tests pass" cannot be claimed for this project; say what actually ran.

### Workspace root (`../`)

```bash
npm install              # workspaces: frontend-web, management-portal, mobile
npm run dev:web          # Next.js dev server
npm run dev:portal       # Vite dev server
npm run dev:mobile       # Expo start
npm run lint             # ⚠️ tsc --noEmit across workspaces — NOT a linter
npm run typecheck        # tsc --noEmit across workspaces
```

### `../frontend-web` (Next.js)

```bash
npm run dev · npm run build · npm run start · npm run typecheck
```

### `../management-portal` (Vite + React)

```bash
npm run dev · npm run build · npm run preview · npm run typecheck
```

### `../mobile` (Expo)

```bash
npm run start · npm run android · npm run ios
npm run prebuild         # generates native projects — not yet run
```

### Backend

No commands. No backend code exists yet.

## Active Context

**Phase:** pre-Gate-1. Discovery complete; no gate has been run.

**What exists:**
- A complete discovery input layer at `.forge/discovery/` — the 8-document engineering pack
  (reconstructed 2026-08-24), a design-asset inventory, and two critical-flow walkthroughs
- Three client skeletons that boot and render hard-coded fixtures
- Two complete design-system token sets and 17 Stitch screen exports

**What does not exist:**
- Any backend code — five services and a gateway, all greenfield
- Git history for the client code (`advertising/` is not a repository)
- Any test, any enforced linter, any CI, any `.env.example`
- Designs for ~11 surfaces, including the **entire payment flow** and the **entire auth flow**
- Per-repo `CLAUDE.md` files and the `## Frontend Stack` / `## Backend Stack` profiles that the
  wave-mode implementer agents read on turn 1

**Immediate next action:** run `/forge-prd-check` (Gate 1) against `.forge/project-prd.md`. Its job here
is not a formality — it is to convert the `[PROPOSED]` set into `[LOCKED]` decisions or explicit
deferrals, and to answer OQ-01, OQ-02 and OQ-20 in particular.

**Blocked until Gate 1:** everything. Do not write specs, size features, or propose dates.
