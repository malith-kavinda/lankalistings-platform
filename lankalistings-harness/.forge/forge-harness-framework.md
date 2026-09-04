# Altrium Forge Harness — Framework Reference

> **Status:** Living document. This is the source of truth for what the Forge Harness is and how it works.
>
> **Version:** tracked in [`../CHANGELOG.yaml`](../CHANGELOG.yaml). The harness is currently in early operational use (v0.x) and will reach v1 once validated through the first real engagement end-to-end.
>
> **Origin:** This document evolved from the original v0 proposal. The frozen proposal is preserved at [`archive/v0-proposal.md`](archive/v0-proposal.md) for historical context — voice, rationale, and theory inputs (SDD, BMAD, Spec Kit, OpenSpec) live there.
>
> **Related:**
> - [`guide.md`](guide.md) — the practical day-to-day how-to. Start there if you want to *use* the harness rather than understand it.
> - [`INDEX.md`](INDEX.md) — map of the accumulated raw material (research deep dives, meeting notes, lessons learned).

---

## 1. What the Harness Is

The Altrium Forge Harness is a **manual-first delivery kit** for AI-assisted software work inside Claude Code. It is the set of guardrails, templates, conventions, and workflow definitions that keep AI-assisted development on track.

The engineer decides where to go. The AI does the heavy lifting. The harness makes sure the output is engineering, not guesswork.

### 1.1 The Core Idea

Forge optimizes for the dominant mode of work first:

- developers working interactively in Claude Code
- humans staying in the loop at every important gate
- context living in files instead of conversation memory
- task execution happening in a real project, not in an abstract platform

This means the CLI workflow is primary. Automation is secondary.

### 1.2 The Harness in One Sentence

**The harness is the set of guardrails, templates, conventions, and workflow definitions that keep AI-assisted development on track.**

Think of it like a parachute harness. The AI is in the parachute — it has the power and the reach. The engineer is the instructor — they show the path and make the calls. The harness is what keeps the AI on the right path. Without it, the AI free-falls into vibe coding: plausible-looking output with no structure, no traceability, and no quality assurance. With it, the same AI produces work that can be reviewed, resumed, and shipped with confidence.

The harness is not something you redesign every week. Once the structure is proven, it stabilizes. What evolves is the content inside it — the `CLAUDE.md` gets thicker as the team learns the codebase, rules get added when patterns emerge, templates get refined when gaps show up. **Stable structure, living content.**

### 1.3 What the Harness Is Made Of

The harness is not software. It is a reusable delivery method encoded in files:

| Component | What It Is | Where It Lives |
|-----------|-----------|----------------|
| **The Workflow** | The gated phases: Discovery → PRD → Architecture → Decompose → Spec → Plan → Dev → Check → Review → Ship | Defined in docs, executed by humans in Claude Code |
| **The Constitution** | `CLAUDE.md` — architecture decisions, patterns, conventions, prohibitions | `.claude/CLAUDE.md` |
| **The Rules** | Path-scoped conventions that activate for backend, frontend, testing | `.claude/rules/` |
| **The Templates** | PRD, architecture, spec, plan — structured artifacts for each phase | `.forge/project-prd.md`, `.forge/design/architecture.md`, `.forge/specs/`, `.forge/plans/` |
| **The Pre-Implementation Gates** | Three gates between "PRD lands" and "first feature spec written": PRD readiness, feasibility / architecture probe, decomposition. Each runs as an interactive slash command, supports `dry-run` mode for calibration, and writes to a shared engagement-level audit log. | Commands: `/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose`. Checklists: `.forge/checklists/prd-readiness-checklist.md`, `.forge/checklists/architecture-checklist.md`, `.forge/checklists/decomposition-checklist.md`. Audit: `.forge/engagement-gate-runs.md` (append-only). Status snapshot: `## Gate Status` table at top of `.forge/project-prd.md`. Structured state: `.forge/tracker.yaml` under `setup.*`. |
| **The Discovery Structure** | Where raw inputs live — screenshots, flows, meeting notes | `.forge/discovery/` |
| **The Quality Gates** | Explicit checklist of what "checked" means on this project | Quality checklist + the project's existing lint / test / build commands. A dedicated check command will be introduced when patterns stabilize. |
| **The Commands** | Claude Code slash commands that execute the engagement-level gates | `.claude/commands/` |
| **The Isolation Model** | Git worktrees for task isolation across repos | `worktrees/` (sibling to the project repos) |
| **The Tracker** | Structured project status file — leadership visibility, feature phases, blockers | `.forge/tracker.yaml` |
| **The Team Guide** | One-page reference for how the crew works on this project | `.forge/team-guide.md` |
| **Role Sub-Agents** | Read-only sensor roles that run independently of the main session via the Task tool. Currently wired: `harness-sync-reviewer` (validates upstream forge-harness sync application against the changelog), `spec-reviewer` (per-pass feature-spec audit, called by `/forge-spec-review`), `plan-reviewer` (per-pass plan audit, called by `/forge-plan-review`). Adversarial-code-reviewer (for committed-diff review) and security-reviewer slots are documented as deferred patterns awaiting real-engagement evidence to reintroduce — see `.claude/agents/README.md` in the template. | `.claude/agents/` |
| **Automated Gates (Hooks)** | Deterministic lifecycle checks. Two classes: (a) intrinsic — dangerous-command blocks, protected-path blocks, @spec/@plan injection, lint/typecheck after edits, test verification before stop; (b) gate-state-aware — engagement-gate state injection at session start, leapfrog blocks on feature spec writes before Gate 2 + foundation, accepted-risk + open-spike re-surfacing on spec/plan edits. Class (b) reads `.forge/tracker.yaml` `setup.*` — bridges the engagement-gate machinery to in-session enforcement. | `.claude/hooks/` + `.claude/settings.json` |

**Global-level skills** sit alongside the project harness. Not every skill is project-specific — some are thinking tools that improve the quality of any Forge conversation. The **Council skill** (`/council`) is the primary example: a multi-perspective review that runs three independent AI advisors against a question or decision, then synthesizes a verdict. It lives at the global Claude Code level (`~/.claude/skills/`) because it is useful across any project, not just within a single Forge workspace. See §2.5 for details.

### 1.4 What the Harness Is Not

The harness is not:

- a batch execution system
- a platform
- a dashboard
- a generalized orchestration engine
- a cost reporting product
- a complete skill ecosystem

Those may come later. They should be built on top of a framework already proven in real work.

### 1.5 Why It Matters

The difference between "AI writes code" and "AI-assisted engineering" is the harness. Without it:

- Every session starts from zero
- Decisions get reversed by the next conversation
- There is no way to verify what was built against what was intended
- A second developer cannot resume the work
- Quality depends on whoever happens to be prompting

With it:

- Context persists across sessions in files
- Architecture decisions are locked in the constitution
- Work is verifiable against specs and plans
- Any team member can pick up from the artifacts
- Quality is defined by explicit gates, not individual judgment

The harness is what makes Forge a delivery method instead of a collection of AI prompts.

### 1.6 The Four Pillars

The harness maps onto four pillars. Each pillar is a concept; the implementation is file-based and manual-first today, with room to automate later.

**1. Agent Workflows → The Forge Workflow**

The gated workflow executed through Claude Code skills and human gates. Not automated pipelines — human-driven phases with AI assistance at each step. The workflow is the same as any mature delivery method; the execution is interactive instead of batch.

For new projects, the workflow has two halves:

- **Pre-implementation (one-time per engagement):** Discovery → PRD (Gate 1) → Architecture & Feasibility (Gate 2) → Foundation (§4.10) → Decomposition (Gate 3). The three gates verify the engagement is committable before any feature work begins; Foundation is the scaffolding work between Gate 2 and Gate 3.
- **Per-feature (repeated):** Spec → Plan → Dev → Check → Review → Ship → Reflect.

**2. Playbooks & Templates → The Template Kit**

Markdown templates for specs, plans, project briefs, and `CLAUDE.md`. Institutional knowledge encoded in structured files. A new project starts with these templates. A new team member reads the team guide and `CLAUDE.md`. The playbook is the file structure plus the workflow, not a YAML-driven automation.

**3. Quality Gates → Explicit Checks**

A layered quality model — a checklist per project plus three enforcement tiers:

- **Guides** (PRD readiness, architecture probe, decomposition, spec, plan, implementation) stay interactive in the main session because their quality depends on dialogue with the developer. The three pre-implementation guides ship as slash commands — `/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose` — and verify the engagement is committable before per-feature work begins. Per-feature guides (spec, plan, implementation) currently run via direct conversation with Claude; dedicated commands will be introduced as patterns stabilize through real engagement experience.
- **Computational sensors** run deterministically: in-session hooks (`.claude/hooks/` wired in `.claude/settings.json`) for dangerous-command blocks, protected-path blocks, lint/typecheck on every edit, and test verification before Claude ends a turn. A second class of hooks reads `.forge/tracker.yaml` to bridge engagement gates to per-feature work — injecting current gate state at every session start, blocking feature spec writes before Gate 2 has passed and foundation is `done` (foundation specs at `.forge/specs/foundation/**` are exempt), and re-surfacing accepted risks and open spikes whenever a spec or plan is written or edited. A third class enforces review-evidence on approval transitions (`guard-spec-approval.sh`, `guard-plan-approval.sh`) — blocking any Edit/Write/MultiEdit that flips `Status: approved` without the matching `Reviewed-via: /forge-<name>` annotation that only the corresponding review skill writes. A `Stop`-time tracker-freshness hook warns when specs or plans were edited without a matching `tracker.yaml` update. These tracker-reading hooks fail open when `yq` is not installed. A dedicated on-demand check command (lint/test/build) will be introduced when the workflow stabilizes.
- **Inferential sensors** for per-feature review are now wired: `spec-reviewer` is dispatched per pass by `/forge-spec-review`, `plan-reviewer` is dispatched per pass by `/forge-plan-review`. Each runs with no inheritance from the authoring session, so adversarial reading is structurally independent of the session that produced the spec or plan. Adversarial code review (committed-diff) and security review are still deferred — they currently run via direct conversation with Claude or `/council`, and the sub-agent slots are documented for future reintroduction.

**Audit storage matches artifact scope.** Findings from each tier persist at the same scope as the artifact the gate serves — preventing one-size-fits-all audit storage from breaking under scale:

- **Engagement-level gates** (PRD / architecture / decomposition) → dedicated append-only log at `.forge/engagement-gate-runs.md`, with a compact snapshot table at the top of `project-prd.md` and structured state in `tracker.yaml`.
- **Per-feature gates** (spec review, plan review, adversarial review, security review) → reuse existing per-feature artifacts. Spec body + `## Revisions`. Plan `## Notes` + `## Progress`. No new files.
- **Tool-call-level gates** (hooks, lint, typecheck) → ephemeral. Stderr feedback only. The natural feedback loop is the audit.

This means high-frequency gates (hooks fire thousands of times) never bloat any file, mid-frequency gates (per-feature) stay decentralized in their own artifacts, and low-frequency engagement gates have a bounded shared log. See §5.8 for the locked decision.

Manual but explicit. Nothing ships without passing. (Reviewer sub-agents for the pre-implementation gates are deferred to a later release — see `research/engagement-phase-gates.md` for the design.)

**4. Toolchain & CI/CD → Workspace Conventions**

Git worktrees for task isolation, the project's existing CI/CD, Claude Code as the development environment. No custom toolchain — just conventions on top of what already exists. The value comes from consistent workspace structure and isolation, not from custom infrastructure.

### 1.7 Evolution Path

The harness is not static. It grows in versions tracked in `CHANGELOG.yaml`:

```
v0: The harness is a delivery kit (files + conventions + workflow)
    → Proven in real work. Manual. Human-driven gates.

v1: The harness is applied to a real engagement end-to-end
    → Templates refined. Skills built. Patterns extracted.

v2: The harness adds automation and extraction
    → Batch pipeline connected to spec/plan format.
    → Reusable patterns extracted from the engagement.
    → Cost tracking and basic reporting.

v3: The harness becomes a platform
    → Dashboard. API. Multi-tenant. The full vision.
```

Each version builds on the last. Nothing from earlier versions gets thrown away — later versions are built on top of a framework that has already been proven in real delivery.

---

## 2. The Workflow

The per-feature workflow is deliberately simple:

```
Spec → Plan → Implement → Check → Review → Ship → Reflect
```

For new projects, there is a pre-implementation phase before the first feature spec can be written. It runs once per engagement and produces the artifacts that everything downstream depends on:

```
Discovery → PRD (Gate 1) → Architecture & Feasibility (Gate 2) → Foundation (§4.10) → Decompose (Gate 3) → (then per-feature workflow begins)
```

The three gates exist because the realistic delivery situation is that a project-level PRD lands (either from the client or written by Forge from client resources), and the team is on the hook to deliver against it. Without explicit verification before commitment, gaps in the PRD become invented requirements during implementation, missing architecture decisions become walls hit at coding time, and a wrong decomposition becomes overlapping or oversized feature work. Each gate fails differently, so each gets its own checklist and its own pass / fail. See [`research/engagement-phase-gates.md`](research/engagement-phase-gates.md) for the rationale, the per-gate checklists, and the authoring-vs-checkpoint distinction (gates as checkpoints when Forge writes the PRD in parallel with architecture, vs. sequential review when the client provides it). Per-feature readiness gates (spec, plan) are designed in [`research/feature-phase-gates.md`](research/feature-phase-gates.md).

### 2.1 Project Bootstrap

The standard workflow assumes that a spec can be written — that the scope is defined enough to specify. For new projects starting from raw inputs (screenshots, mockups, client conversations, reference systems), there is a bootstrap phase that produces the first specs.

#### Discovery

Purpose:
- understand what exists (if rebuilding from a reference system) or what is needed (if greenfield)
- capture raw inputs in a durable, structured location before they scatter across Slack and email

Primary artifacts:
- `.forge/discovery/feature-inventory.md` — what the reference system does
- `.forge/discovery/flows/` — documented user flows (markdown + screenshots)
- `.forge/discovery/screenshots/` — raw captures of the reference system or mockups
- `.forge/discovery/meeting-notes/` — client meeting captures, verbal decisions

Discovery does not need to be exhaustive. Document enough to scope v1 and write the first specs. The rest is discovered as work proceeds.

#### Reference-System Analysis

When the project is built from a reference system, discovery needs more than screenshots and meeting notes. The team needs a systematic way to capture, compare, and decide on reference-system behaviors.

The feature inventory should explicitly classify each reference-system capability:

| Behavior | Classification | Notes |
|----------|---------------|-------|
| User login with SSO | **Replicate** — same behavior, new stack | Core requirement |
| Batch CSV export | **Defer** — not in v1 scope | Client confirmed low priority |
| Custom report builder | **Redesign** — behavior changes | Original UX has known issues |
| Legacy admin panel | **Discard** — not needed | Replaced by new admin flow |

This classification becomes the input for the project brief's scope decisions and drives which features get spec'd first. Without it, the team discovers mid-implementation that they never decided whether a behavior should be replicated or redesigned.

If Claude Code can access the reference system's codebase directly, that codebase should be available during spec and plan creation — not just screenshots. Reference code provides data models, business logic, and edge cases that screenshots cannot capture.

#### Project PRD (Gate 1: Readiness)

Purpose:
- consolidate everything discovery surfaced into the single source-of-truth product requirements document for the engagement
- make scope, domain model, users, NFRs, and constraints explicit enough that the team can commit to delivery against it

Primary artifact: `.forge/project-prd.md`.

Gate: **`/forge-prd-check`** walks the PRD against `.forge/checklists/prd-readiness-checklist.md` (scope and boundaries, domain model, users and access, functional surface, non-functional, constraints, honesty). Each item is pass / fail / N/A; failures are logged with a *specific gap statement*, not a vague "weak in this area." The command is interactive — it does not autonomously approve. The developer either fills the gaps and re-runs, or accepts specific gaps as risks. In **full mode** the skill writes three places (audit log, PRD snapshot table, tracker structured state — see §5.8 and the project's `.claude/rules/tracker.md` "Gate Audit Protocol"); a `dry-run` mode prints findings without writing anything (used for checklist calibration and testing).

Who runs it: the Forge engagement lead drives the interactive walk; the project lead reviews. Reviewer sub-agents are deferred to a later release.

The PRD is not a feature spec. It is allowed to be rough, have gaps, and evolve — but those gaps must be *visible*, not silent. The gate exists to make the visibility happen.

**Where open questions live.** Gaps surfaced by Gate 1 (and by Gates 2 and 3 below) are recorded as rows in `.forge/project-prd-signals.md`, not in the PRD body. The live contract (`project-prd.md`) stays small enough to load cheaply; the signals file accumulates open questions anchored to PRD sections, and is selectively loaded by `spec-reviewer` later (filtered by feature ID via the `Blocks` column). When an OQ is answered, the three-step lift defined in `.claude/rules/prd.md` folds the answer into the live contract and moves the row to `project-prd-history.md`. See §4.7 for the full trichotomy.

#### Architecture & Feasibility (Gate 2: Probe)

After the PRD exists, the project needs foundational design artifacts. These describe *how the pieces fit together* structurally, which individual feature specs will then reference. Gate 2 verifies that the foundational architecture decisions are made (or explicitly deferred with a trigger) and that the PRD can actually be built — that the highest-risk requirements have at least a paper sketch, the in-house-first audit is done, and the team / stack / timeline reality has been checked against the scope.

Design artifacts split by ownership:

- **Cross-cutting (harness level)** — system architecture, component relationships, service boundaries, deployment topology. Lives at `.forge/design/architecture.md`. Produced during early design work by the engagement architect, evolves as the system takes shape. **This is what Gate 2 fills.**
- **Backend-owned (code repo level)** — data model, ER diagrams, API contracts. Lives in the backend repo (e.g., `<backend>/docs/data-model.md`). The schema code is the source of truth; the doc lives next to it so they stay in sync through the same PRs.
- **Frontend-owned (code repo level)** — style spec, design tokens, component patterns. Lives in the frontend repo (e.g., `<frontend>/docs/style-spec.md`). The component library is the source of truth.

Gate: **`/forge-arch-probe`** walks `architecture.md` against `.forge/checklists/architecture-checklist.md` (tech stack viability, foundational decisions, build feasibility, resource and timeline reality, in-house-first audit, honesty). The skill reads more than just `architecture.md` — settled decisions are spread across the PRD, the `CLAUDE.md` "Architecture Decisions (DO NOT REVERSE)" table, `design/README.md` (ownership boundaries), the UI design folder if present, and repo-level docs (`<repo>/docs/data-model.md`, `<repo>/docs/style-spec.md`) when those repos exist. Before the walk, the skill checks that Gate 1 has passed (warns and asks to continue otherwise) and runs a sync-check that surfaces any architecture content contradicting the PRD or `CLAUDE.md` — stale-vs-truth is a distinct failure class from "decision not made," so the gate flags it explicitly without picking a winner. Per-item verdicts are pass / pass-with-spike / fail / N/A; the run-level verdict is pass / pass-with-risks / pass-with-spikes / fail (both risks and spikes can apply to the same run). Failures are logged with a *specific missing decision*, not "we should think about this more." Same audit pattern as Gate 1 — full mode writes the audit log, PRD snapshot table, and tracker structured state (with both `accepted_risks` and `spikes`); `dry-run` mode prints findings without writing.

Who runs it: the engagement architect drives, with project-lead supervision. Reviewer sub-agent deferred to a later release.

**Authoring vs. checkpoint.** When the client provides the PRD, Gate 2 is net-new architecture work that runs sequentially after Gate 1. When Forge writes the PRD using client resources, PRD authoring and architecture thinking happen *in parallel* — by the time the PRD is ready, many architecture decisions are already baked in. The gates fire at the end as formal checkpoints rather than producing the work from scratch. Either way, the gates themselves are identical; what changes is the cadence of the underlying work.

**Early repo creation.** Because data model and style spec need to live in code repos, the code repos should be created early — even as empty stubs with just a `CLAUDE.md` and `docs/` folder — so these artifacts have a home from day one. Sketches that emerge during discovery get promoted into the code repos as soon as they exist.

See `.forge/design/README.md` in the project-harness template for the full ownership breakdown and the "what does NOT live here" list.

#### Foundation (between Gate 2 and Gate 3)

Once Gate 2 settles the architecture, the **foundation backlog** — the enumerated list of scaffolding slices implied by the architecture decisions, captured in `architecture.md` — is built before Gate 3 runs. Foundation is *scaffolding only*: the minimum substrate needed to run the app and write a user-story feature spec against it. User-visible behavior with its own flows and edge cases (auth, specific entity data models, business flows) is a *feature*, not foundation — features develop against a stub or open auth surface during dev.

Foundation slices run through the same per-feature pipeline (spec → plan → implementation → check → review) under a namespaced subdirectory: `.forge/specs/foundation/` and `.forge/plans/foundation/`. Per-step tooling will be introduced as patterns stabilize through real engagement experience; for now these steps run via direct conversation with Claude. There is no dedicated foundation-check command — one-time engagement work doesn't justify automation (per §5.1). The foundation review is a manual Claude Code session (optionally invoking `/council`), captured in `.forge/engagement-gate-runs.md` as a precondition note inside Gate 3's entry.

Foundation specs *can* draft in parallel with late Gate 2 polish (extending the authoring-vs-checkpoint pattern), but foundation plans and code wait for full Gate 2 pass — specs are cheap to revise; migrations and base classes are not.

Gate 3 has foundation as a precondition: the substrate must be in the repo and reviewed before decomposition runs, so feature specs reference real patterns rather than vapor.

See §4.10 for the full doctrine — discipline rule, tooling-vs-instance test, slice list, location, timing.

#### Decomposition (Gate 3)

Once Gate 1 and Gate 2 pass, the PRD is broken into agent-sized feature specs. Each feature enters the standard Spec → Plan → Implement flow. **This is the moment features enter the tracker** — each gets an entry in `.forge/tracker.yaml` with `phase: backlog`, an assignee, and a priority.

Gate: **`/forge-decompose`** proposes a slicing principle (by module / journey / capability / phase), generates stub feature specs at `.forge/specs/<feature>-spec.md`, regenerates `.forge/features.md` (the live feature index) with the slicing rationale and a mermaid dependency graph, and walks `.forge/checklists/decomposition-checklist.md` (slicing, coverage, separation, dependencies, sizing, per-feature spec readiness). Failures (overlaps, coverage gaps, sizing concerns, dependency cycles) are surfaced for human resolution — Gate 3 has no risk-acceptance path; failures must be fixed by re-slicing. Full mode creates the spec stubs, regenerates `.forge/features.md`, populates `tracker.yaml` features, and appends to the engagement audit log; **`dry-run` is especially important here** because full mode creates many files at once — use dry-run to preview the proposed shape before committing.

The split between `.forge/features.md` (live human/agent-readable index), `tracker.yaml` `features:` (structured-state mirror), and PRD §Feature Decomposition (Gate-1 frozen snapshot) is deliberate: live operational state must not be co-located with frozen audit artifacts — every status update would otherwise look like a contract revision (or vice versa). `features.md` lives at `.forge/` top level for discoverability; an agent starting a feature session opens it without spelunking under `specs/`.

Who runs it: the Forge engagement lead drives, project lead reviews.

By the time Gate 3 runs, the foundation slices from `architecture.md`'s foundation backlog are already implemented (see §4.10) — feature decomposition slices on top of an existing substrate, not against a bare repo. Auth, specific entity data models, and business flows are *features* and get their own specs through this gate; they are not part of foundation.

#### Ownership Model

The project lead seeds initial versions of the bootstrap artifacts — `CLAUDE.md`, project PRD, architecture sketch. The engagement architect leads Gate 2. The development team fills in gaps and evolves the artifacts through real work.

The framework improves as work happens, not before it. A lead should not spend weeks perfecting templates while the team waits. The minimum viable starting point is:

- `CLAUDE.md` with stack decisions and architecture direction
- project PRD with v1 scope, domain model, users, and constraints (Gate 1)
- a thin `.forge/design/architecture.md` with the high-level system shape, the foundational architecture decisions (Gate 2), and the foundation backlog the decisions imply (§4.10)
- code repo stubs created early, each with a `docs/` folder for repo-level design (data model, style spec) to land in
- foundation slices implemented (§4.10) before Gate 3 — specs and plans live under `.forge/specs/foundation/` and `.forge/plans/foundation/`
- a feature spec backlog produced by `/forge-decompose` (Gate 3) against the populated substrate
- a one-page team guide on how the workflow operates

### 2.2 Status Tracking

The workflow needs visibility — leadership needs to know where each feature stands without opening a Claude Code session or reading individual spec/plan files.

#### The Problem

Status information is scattered across artifacts: spec files have their own status (draft/approved), plan files have progress checkboxes, and workflow phase (which step a feature is in) exists only in the developer's head. There is no single place to answer "where is everything?"

#### The Solution: `.forge/tracker.yaml`

A structured YAML file that tracks what the individual artifact files cannot:

- **Which features exist** — including ones in backlog with no artifacts yet
- **What phase each is in** — the workflow position (backlog → spec → plan → dev → review → ship → done)
- **Who owns it, priority, blockers** — metadata that has no other home
- **Project setup status** — pre-development readiness (brief, tech decisions, environment)

The tracker does not duplicate state that lives in spec/plan files. Artifact-level status (draft/in-review/approved) stays in those files. The tracker records the field that the files individually cannot: overall phase, ownership, and cross-feature dependencies.

#### How It Stays Updated

The tracker must not depend on skills existing — skills are built incrementally and some may never exist. Instead, the update mechanism is a **`CLAUDE.md` rule**: Claude is instructed to update the tracker after any action that changes feature state, regardless of whether a skill was used.

This works because every meaningful action in Forge happens with Claude present. The developer creates a spec — Claude updates the tracker. The developer approves a plan — Claude updates the tracker. The mechanism is the AI assistant that is already in every session, not a platform feature that needs to be built.

The critical behavioral rule: **Claude never assumes approval.** When a developer finishes working on a spec or plan, Claude asks for the status before updating. If the developer says "let's start planning" but the spec isn't marked approved, Claude asks first. This encodes the human gates from the workflow into Claude's behavior — the "gate" is Claude asking the question and recording the answer.

#### Why YAML

YAML over JSON — easier to hand-edit when someone needs a quick update without opening a session. Structured enough to be parsed programmatically for future dashboard rendering (Confluence table, web view, Slack digest). Human-readable enough for leadership to scan directly.

### 2.3 Spec

Purpose:
- define what is being built
- remove ambiguity
- establish acceptance criteria

Primary artifact: `.forge/specs/<ticket>-spec.md`.

Gate: requirements approved before planning starts.

### 2.4 Plan

Purpose:
- define how the approved spec will be implemented in this codebase
- break the work into clear, resume-friendly steps

Primary artifact: `.forge/plans/<ticket>-plan.md`.

Gate: implementation approach approved before coding begins.

### 2.5 Decision Quality — The Council Pattern

Spec and plan creation are the highest-leverage conversations in the Forge workflow. A spec that misses a requirement compounds into a plan that misses steps, which compounds into code that misses the point. A plan that over-engineers compounds into wasted effort and unnecessary complexity.

The problem: these conversations happen between one developer and one AI. The AI builds on its own momentum — it rarely stops mid-conversation to say "actually, this whole approach is wrong." This is not a hallucination problem. It is a **single-perspective bias** problem. One thinking style produces one thread of reasoning, and that thread tends to reinforce itself.

The Council pattern addresses this by forcing structured disagreement at decision points. Instead of one AI perspective, three independent advisors with different thinking styles evaluate the same question:

| Advisor | Thinking Style | What They Ask |
|---------|---------------|---------------|
| **The Critic** | Find what's wrong, missing, or risky | "What could fail? What's missing? What assumption will break?" |
| **The Pragmatist** | Evaluate feasibility, effort, simplicity | "Is this over-engineered? What's the simplest version that works?" |
| **The Advocate** | Steelman the proposal, strengthen it | "What's genuinely good here? What second-order benefits are being overlooked?" |

These three create a natural tension: the Critic pulls toward caution, the Advocate pulls toward action, and the Pragmatist anchors in reality.

The key mechanic is **anonymous cross-review**. After the three advisors independently analyze the question, each reviews the other two responses without knowing who wrote them. This removes attribution bias and forces evaluation of arguments on merit rather than persona expectation.

A chairman synthesis then distills the verdict: where the council agrees (high-confidence findings), where it disagrees (tensions the developer needs to resolve), and what remains open.

#### When to invoke it

The council is not automatic. It is invoked by the developer at decision points during spec or plan conversations:

- **During spec creation**: "Is this spec complete? Are we scoping this right?"
- **During plan creation**: "Is this approach sound? Are we over-engineering?"
- **At architecture decisions**: "Should we use X or Y? What are we not seeing?"
- **When something feels off**: "I'm not sure about this direction — challenge it."

The invocation is a single command: `/council "Is this auth spec complete enough to plan against?"` Claude Code runs the three advisors, the cross-review, and returns a synthesized verdict.

#### Why it's framework-appropriate

The council is a Claude Code skill — a prompt file, not infrastructure. It requires no platform, no dashboard, no automation. It costs tokens, not engineering time. And it directly improves the quality of the two most important artifacts (specs and plans) during the conversations that create them.

It also lives at the **global level** (`~/.claude/skills/council/`), not inside a project workspace. This means it is available for any design conversation — Forge projects, architecture discussions, even framework design sessions.

### 2.6 Where Review Effort Belongs

In traditional development, code review is the primary quality gate. In AI-assisted development, this inverts. **The spec and plan are where review effort matters most.**

The reason is structural: when AI generates code from a plan, the plan determines the code quality. A good plan with clear patterns, correct file references, and sound architecture decisions produces good code reliably. A bad plan — wrong approach, missing edge cases, patterns that contradict the codebase — produces bad code that no amount of code review can efficiently fix. The error compounds: fixing a plan gap at the code level means reverse-engineering what the plan should have said, then rewriting the implementation. Fixing it at the plan level means changing a paragraph and regenerating.

This means:

- **Spec review by peers is critical.** The developer who wrote the spec should not be the only one who reviews it. A second pair of eyes catches requirements gaps, scope ambiguity, and wrong assumptions before they propagate. For foundation specs and plans (§4.10) and for high-risk features touching auth or core data models, the lead should review. For standard features, peer review between developers is sufficient.
- **Plan review is the highest-leverage quality gate.** The plan contains the architecture decisions, file references, implementation patterns, and subtask decomposition that the AI will follow literally. If the plan says "follow the pattern in `UserService.java`" and that pattern is wrong for this use case, the AI will produce code that follows the wrong pattern perfectly. Peer review of plans — especially the approach, decisions, and pattern references — catches this.
- **Code review becomes verification, not discovery.** With a reviewed spec and plan, code review shifts from "is this the right approach?" to "did the AI follow the plan correctly?" This is a faster, more focused review. The hard thinking already happened upstream.

For a 3-person team, this means:
- Foundational specs and plans: lead reviews
- Standard specs and plans: peer reviews (the developer who didn't write it reviews it)
- Code: verified against spec + plan (can be lighter because the upstream gates did the heavy lifting)

This is not more process — it is the **same review effort redistributed to where it has the highest impact.** In AI-assisted delivery, reviewing the instructions matters more than reviewing the output.

### 2.7 Implement

Purpose:
- execute against the plan
- update progress in files, not only in chat

Primary output: code changes in the worktree.

#### Context Management During Implementation

Long Claude Code sessions degrade in quality. After ~60% of the context window fills with tool results, file reads, build output, and error traces, the signal-to-noise ratio drops and reasoning becomes less sharp. This is not a model limitation — it is a context pollution problem.

The plan's subtask structure is the natural mitigation. Treat subtasks as **session boundaries**, not just logical divisions:

- Aim for 2-4 subtasks per session, depending on complexity. When the session feels heavy or Claude's responses become repetitive, start fresh.
- **Update the plan's progress section before ending a session.** Mark completed subtasks, note anything discovered, flag what is in progress. **Record failed approaches** — what was tried and why it didn't work, so the next session doesn't repeat dead ends. The next session (or a different developer) reads the plan and picks up exactly where the last one stopped.
- Claude Code already delegates exploration work (codebase searches, multi-file reads) to sub-agents automatically, keeping the main context cleaner. Let it.
- For complex subtasks that require deep codebase analysis, the developer can explicitly delegate to a sub-agent: "explore how the auth middleware works and summarize the pattern" keeps the investigation out of the main context and returns only the result.
- The role-based **sensor sub-agent pattern** has now materialized for per-feature review (`spec-reviewer`, `plan-reviewer` — each dispatched in fresh context per pass by the matching `/forge-*-review` skill, with no inheritance from the authoring session). Adversarial committed-diff review and security review remain deferred slots — they currently run via direct conversation with Claude or `/council`, and the agent files for those will return when the pattern stabilizes.

The Forge principle — **context in files, not conversations** — applies here too. A fresh session with a good plan and updated progress section is better than a stale session with 200 tool calls in its history. Multiple focused sessions will outperform one marathon session.

### 2.8 Check

Purpose: run the basic project validation steps.

Minimum expectation:
- lint
- tests
- type checks or build validation where applicable

### 2.9 Review

Purpose: verify the diff against both the spec and the plan.

Review question: *did we build the right thing, and did we build it in the intended way?*

### 2.10 Ship

Purpose: create a PR or equivalent delivery artifact with enough context for review.

### 2.11 Reflect

Purpose: capture what worked, what didn't, and what should change — then act on it immediately.

After a feature is shipped, the developer answers three questions:

1. **What worked that we should keep doing?** — patterns, approaches, or decisions that paid off
2. **What didn't work that we should change?** — friction, mistakes, wasted effort, wrong assumptions
3. **What should be updated?** — specific updates to `CLAUDE.md` rules, templates, workflow, or project brief

Reflect is not a retrospective document. It produces **direct updates to existing artifacts:**

- A mistake that will recur → add a rule to `CLAUDE.md` or `.claude/rules/` (compounding engineering)
- A template gap → update the spec or plan template
- A workflow friction → update the team guide
- A pattern discovery → add to repo-level `CLAUDE.md`

The goal is that the framework gets better with every feature shipped. If Reflect does not change any file, it was not done properly.

Reflect should take 5-10 minutes. It is the lightest phase in the workflow and the one most likely to be skipped — which is why it is explicit rather than implied.

### 2.12 Rework and Feedback Loops

The workflow is presented as a linear sequence, but real delivery is not linear. Phases produce feedback that sends work backward. The framework must handle this without breaking artifact integrity.

**When Check fails:**
- The developer fixes the issues in the same worktree and re-runs Check. No process change needed — this is a normal development loop. The plan's progress section tracks what was fixed.

**When Review rejects implementation:**
- Review feedback is recorded in the plan under `## Notes` (what was wrong, what needs to change).
- The developer fixes the issues and re-submits for Review.
- If the fix requires a change to the plan's approach (not just a bug fix), update the plan with the new approach and note what changed and why.

**When a spec is wrong mid-implementation:**
- This is the most disruptive rework scenario. The developer has discovered that an approved spec has a gap, a wrong assumption, or a missing requirement.
- **Do not silently adjust.** Follow the spec revision convention (see §5.7): add a revision entry, update the spec body, note the impact on the plan.
- If the spec change is large enough to invalidate the current plan, pause implementation and revise the plan before continuing. This is better than building on a known-wrong foundation.

**When discovery reveals scope change:**
- During a reference-system project, it is common to discover mid-implementation that the reference system does something unexpected. If this changes the feature's scope, it flows back to the spec as a revision. If it is a new feature entirely, it goes back to the project brief as a new item for decomposition.

The key principle: **every backward loop must leave a trace in the artifacts.** If the spec changed, the revision log shows it. If the plan changed, the notes section records why. If scope changed, the project brief reflects it. Without traces, the artifacts become unreliable and the "resume from files" promise breaks.

### 2.13 Wave-Mode Delivery (the build-and-ship subsystem)

The Spec → Plan bookends above are mode-agnostic. The **shipping** half — how an approved feature becomes merged code — runs in **wave mode**: a feature is decomposed into **waves**, and each wave ships to `main` as its own PR. The engagement opts in via `delivery.ship_unit: wave` in `tracker.yaml` (the default); a per-feature `features[<id>].ship_unit` overrides it, immutable once set at decomposition time. Two commands drive it — `/forge-wave-decompose` (spec → Decomposition Plan) and `/forge-deliver` (the 15-stage orchestrator) — and they dispatch a set of stack-specialist agents and inline skills. The design rationale lives in `docs/working/research/` (the wave-mode corpus).

**The wave is the unit of shipment.** A wave is a *vertical capability slice* (DB-through-UI for one user-facing capability), not a layer (schema wave, then API wave, then UI wave). Each wave must satisfy a four-item ship-unit checklist — C1 main stays green, C2 no orphan scaffolding, C3 unfinished surfaces are flagged-or-inert, C4 the wave is a verifiable increment on `main` — or be explicitly declared `monolithic` with a legitimate reason. This is what keeps `main` always-deployable while a large feature lands incrementally.

Five elements are **framework-level doctrine**, generic across any stack:

- **The test-tier model — T1 / T2 / T3 / T-E2E.** T1 unit, T2 unit+integration, T3 unit+integration+WI-scope browser-E2E, T-E2E the full spec suite (its own final wave). Every work item declares a tier; `.forge/test-strategy.md` is the spine the agents, `forge-test-verify`, and each Decomposition Plan's Test Strategy Map hang on. The per-tier *toolchain* is project fill-in; the tier *vocabulary* is fixed.

- **Contract-first integration.** Before any plan authoring, a wave with a BE↔FE seam freezes a validated, read-only **contract** (`forge-contract-author` → `Status: frozen`). Both sides then build against one fixed interface, so most "broke once wired" drift is gone before integration. The seam marker is the auto-proposed `type: verify` work item — contracts fire on exactly the seams decomposition flagged.

- **The Dispatch Invariants (load-bearing execution limits, not style).** A dispatched sub-agent (1) cannot dispatch another sub-agent (no recursion), and (2) is torn down when it returns, so it cannot keep dev servers booted or drive a live browser across a run. Therefore the **verify/e2e agents AUTHOR + static-check tests only**, and the **persistent main orchestrator runs the live suites** and owns the run → classify → fix → re-run **auto-repair loop** (the "D11" loop): an in-wave test bug routes to the test specialist, an in-wave code bug to the owning implementer (bounded retries), and a pre-existing-code regression or contract defect escalates to a human. The three finalize-path skills (`forge-pr-open`, `forge-test-verify`, `forge-pre-pr-review`) must stay **non-dispatching** — implementer agents run them inline, and recursion would deadlock the finalize path.

- **The within-wave coupling rule (L-027).** "All sub-work-items in a wave branch from `main` in parallel" holds only for a **cross-repo seam** (the sides compile independently and integrate over a serialized contract). A **same-repo compile-time** consumer→owner dependency must instead **stack** (the consumer's branch bases on the owner's) or **split across waves** — it cannot compile parallel-from-`main`. Decomposition classifies every shared contract as `seam` vs `compile` accordingly.

- **The design vision pass (L-022).** For a wave that ships user-facing UI against a project design reference, the orchestrator screenshots each new/changed route and compares it to the design-of-record **before the wave PR opens** — a runtime backstop to spec-time prototype transcription that catches visual drift green tests mask.

**Shipping shape.** Sub-work-items open transient per-WI review PRs; a two-pass integration merges them into a `feature/<ticket>-wave-<N>` branch; the **wave PR** (one per touched repo, base `main`) is the real ship surface and auto-closes the per-WI PRs as "superseded." Wave merge is a **human checkpoint** — the orchestrator halts after opening the wave PR and resumes on re-invocation after the human merges. `impl_status` runs `pending → dispatched → pr-open → wave-closed`; the orchestrator reconciles its tracker against GitHub + git ground truth on every invocation (Stage 0), so the flow is resumable from any stage.

> **Feature mode is legacy and not part of this harness.** An earlier `/forge-feature-run` shipped a whole feature as one integration PR. Wave mode is its go-forward successor; the upstream workflow is self-contained on wave mode. `ship_unit: feature` remains a documented tracker value, but no feature-mode orchestrator ships here.

---

## 3. Workspace Structure

### 3.1 Design Principles

The workspace structure must solve three problems:

1. **Multi-repo coordination** — a single project may span multiple repos (e.g., backend + frontend). The developer needs to work across them without friction.
2. **Task isolation** — multiple features can be in-flight simultaneously. Working on one must not pollute another.
3. **Clean git boundaries** — each repo should track only what it owns. No nested repos, no `.gitignore` tricks to hide child repos, no tool confusion about which repo a file belongs to.

### 3.2 The Flat Sibling Model

The workspace is a **plain directory** that contains several independent git repos as siblings. The parent directory itself is not a git repo — it is just an organizational container on disk.

This is a deliberate change from earlier drafts that used nested repos (a workspace repo containing project repos). Nesting created two problems:

1. **`.gitignore` blocks Claude Code searches.** Claude Code's Grep and Glob tools use ripgrep, which respects `.gitignore` by default. When the workspace repo gitignored the project repos, cross-repo searches from the workspace root silently returned nothing.
2. **Conceptual confusion.** Developers were never sure which repo they were committing to. Tooling sometimes picked up the wrong `.git/` directory.

The flat model avoids both. Each repo is independent and flat; there is no ambiguity about what is tracked where.

### 3.3 Full Directory Structure

Example layout for a project called `ACME-CRM`:

```
ACME-CRM/                                      # Plain directory (NOT a git repo)
│
├── acme-harness/                              # Git repo #1 — the forge instance
│   ├── .claude/                              #   (framework context and skills)
│   │   ├── CLAUDE.md                         # Project constitution — architecture, decisions,
│   │   │                                       #   boundaries, cross-repo naming, commands
│   │   ├── rules/                            # Workspace-level rules
│   │   │   └── git-conventions.md
│   │   ├── commands/                         # Forge workflow slash commands (engagement-level gates + per-PR review + diagnostic)
│   │   │   ├── forge-prd-check.md            # Gate 1
│   │   │   ├── forge-arch-probe.md           # Gate 2
│   │   │   ├── forge-decompose.md            # Gate 3 — regenerates .forge/features.md
│   │   │   ├── forge-doctor.md               # Read-only state-drift diagnostic
│   │   │   └── forge-review-pr.md            # Framework-aware GitHub PR review across configured workspace repos
│   │   ├── skills/                           # Conversational, auto-triggered authoring + review primitives
│   │   │   ├── forge-gap-check/SKILL.md      # Per-feature pre-spec sensor (advisory)
│   │   │   ├── forge-prd-author/SKILL.md     # Engagement-level PRD interview (pre-Gate-1)
│   │   │   ├── forge-spec-review/SKILL.md    # Multi-pass feature-spec review (dispatches spec-reviewer per pass)
│   │   │   └── forge-plan-review/SKILL.md    # Multi-pass plan review (dispatches plan-reviewer per pass)
│   │   └── agents/                           # Read-only sensor sub-agents invoked via Task tool
│   │       ├── harness-sync-reviewer.md      # Validates upstream forge-harness sync application
│   │       ├── spec-reviewer.md              # Per-pass feature-spec audit (called by /forge-spec-review)
│   │       └── plan-reviewer.md              # Per-pass plan audit (called by /forge-plan-review)
│   └── .forge/                               # Forge artifacts
│       ├── project-prd.md                    # Source-of-truth PRD (verified by Gate 1)
│       ├── checklists/                       # Gate checklists + quality reference
│       │   ├── prd-readiness-checklist.md    # Used by /forge-prd-check (Gate 1)
│       │   ├── architecture-checklist.md     # Used by /forge-arch-probe (Gate 2)
│       │   ├── decomposition-checklist.md    # Used by /forge-decompose (Gate 3)
│       │   └── quality-checklist.md          # What "checked" means
│       ├── tracker.yaml                      # Project status — phases, ownership, blockers
│       ├── team-guide.md                     # One-page workflow reference
│       ├── discovery/                        # Raw inputs
│       │   ├── README.md
│       │   ├── feature-inventory.md
│       │   ├── screenshots/
│       │   ├── flows/
│       │   └── meeting-notes/
│       ├── specs/                            # Feature specs — WHAT
│       │   ├── auth-spec.md
│       │   └── dashboard-spec.md
│       └── plans/                            # Implementation plans — HOW
│           ├── auth-plan.md
│           └── dashboard-plan.md
│
├── acme-be/                                   # Git repo #2 — backend
│   ├── CLAUDE.md                             # Repo-level: stack, patterns, commands,
│   │                                         #   boundaries (copy of harness boundaries)
│   ├── .claude/
│   │   └── rules/
│   │       ├── api-patterns.md
│   │       └── testing.md
│   └── src/
│
├── acme-fe/                                   # Git repo #3 — frontend
│   ├── CLAUDE.md
│   ├── .claude/
│   │   └── rules/
│   │       ├── component-patterns.md
│   │       └── testing.md
│   └── src/
│
└── worktrees/                                # Task isolation (ephemeral, not tracked)
    └── dashboard/                            # One directory per feature/task
        ├── acme-be/                           # Worktree of acme-be (feature/dashboard branch)
        │   ├── CLAUDE.md                     # ✓ From git — appears automatically
        │   ├── .claude/rules/                # ✓ From git — appears automatically
        │   └── src/
        └── acme-fe/                           # Worktree of acme-fe (feature/dashboard branch)
            ├── CLAUDE.md
            ├── .claude/rules/
            └── src/
```

A fourth repo — `forge-harness` (this repo) — lives outside the workspace. It holds the reusable framework (skills, templates, methodology docs) that new projects bootstrap from. The project-specific `<project>-harness` is an instantiation of that template.

### 3.4 Four Git Repos, Four Concerns

| Repo | Tracks | Scope |
|------|--------|-------|
| `forge-harness` | Reusable framework: skills, templates, docs, `CLAUDE.md` template, quality checklist template | Global — used to bootstrap every new project |
| `<project>-harness` | Project's instantiated forge: filled-in `CLAUDE.md`, project brief, specs, plans, discovery, team guide | Project — everything that describes and guides the work |
| `<project>-be` | Backend application code + repo-level `CLAUDE.md` and rules | Backend — the actual product code |
| `<project>-fe` | Frontend application code + repo-level `CLAUDE.md` and rules | Frontend — the actual product code |

Each repo has its own remote, its own branches, its own PRs. None of them are linked at the git level. They just share a parent directory on disk.

### 3.5 Context Loading by Phase

Claude Code discovers context by walking up from the current working directory looking for `CLAUDE.md` files. The sibling model changes where each phase of work runs from, so that the right context is available automatically.

| Phase | Run Claude Code from | Auto-loaded context | Why |
|-------|---------------------|---------------------|-----|
| Discovery, Spec, Plan | `<project>-harness/` | Harness `CLAUDE.md`, `.forge/` artifacts | Orchestration needs the full project constitution, project brief, existing specs/plans, and skills |
| Codebase exploration during planning | `<project>-be/` or `<project>-fe/` (main checkout) | Repo-level `CLAUDE.md` | Need to search and read code freely. Cross-repo search works because nothing is gitignored. |
| Implementation | `worktrees/<feature>/<project>-be/` or `.../<project>-fe/` | Repo-level `CLAUDE.md` (from the worktree) + the plan file (read explicitly by path) | The plan is self-contained — it carries the architecture decisions, patterns, and subtask breakdown needed for this feature. Harness `CLAUDE.md` is intentionally not in scope here. |
| Cross-repo implementation | `worktrees/<feature>/` | None auto-loaded (parent walking finds nothing) | Cd into the specific repo worktree to pick up its `CLAUDE.md`. The feature root is useful for running dev servers and cross-repo commands, not for code sessions. |

### 3.6 Why Harness CLAUDE.md Is Not Auto-Loaded During Implementation

This is a deliberate design choice, not a gap. The Forge principle is **"each task should carry enough context to be executed independently."** If the plan is doing its job, the implementation session does not need to re-derive architecture decisions from the harness. It needs:

- The plan file (architecture decisions, subtasks, patterns to follow)
- The spec file (requirements and acceptance criteria)
- The repo-level `CLAUDE.md` (stack, commands, patterns)

If an implementation session feels like it needs more context than the plan provides, the right fix is to improve the plan — not to paper over the gap by auto-loading workspace context everywhere.

The one genuinely cross-cutting concern — **boundaries** (ALWAYS DO / ASK FIRST / NEVER DO) — is duplicated into each repo-level `CLAUDE.md`. Boundaries are short, rarely change, and apply to any work in the repo regardless of the current feature. Small duplication, large payoff in safety.

### 3.7 Worktrees

Worktrees are cheap — they share git objects with the main checkout (~1 second to create, no re-clone).

```bash
# From the workspace parent directory
cd ~/Work/Altrium/ACME-CRM

# Create worktrees for a new task — both repos, under a shared feature root
git -C acme-be worktree add ../worktrees/dashboard/acme-be feature/dashboard
git -C acme-fe worktree add ../worktrees/dashboard/acme-fe feature/dashboard

# Developer switches to the task (or directly to a specific repo worktree)
cd worktrees/dashboard/acme-be    # run Claude Code here for backend work
```

Main checkouts stay clean on `develop`. Multiple tasks can be in-flight simultaneously — each gets its own directory under `worktrees/`.

After a feature is merged:

```bash
# Remove worktrees
git -C acme-be worktree remove ../worktrees/dashboard/acme-be
git -C acme-fe worktree remove ../worktrees/dashboard/acme-fe
rmdir worktrees/dashboard
```

Worktree cleanup is currently manual — a `/forge-cleanup` command will be introduced when patterns stabilize.

### 3.8 What Gets Committed Where

| Artifact | Committed To | Why |
|----------|-------------|-----|
| Harness `CLAUDE.md` | `<project>-harness` | Project constitution — changes are project-level decisions |
| Workspace rules (git conventions, etc.) | `<project>-harness` | Cross-repo conventions |
| Skills | `<project>-harness` | Workflow tools, evolve with the framework |
| Project brief | `<project>-harness` | Scoping artifact, tracks project evolution |
| Discovery artifacts | `<project>-harness` | Raw inputs, reference system documentation |
| Specs | `<project>-harness` | Requirements contracts, cross-repo |
| Plans | `<project>-harness` | Implementation blueprints, cross-repo |
| Team guide | `<project>-harness` | Crew workflow reference |
| Tracker | `<project>-harness` | Project status, feature phases, blockers |
| Quality checklist | `<project>-harness` | What "checked" means |
| Repo `CLAUDE.md` (including boundaries copy) | Each project repo | Repo-specific context, travels with worktrees |
| Repo rules | Each project repo | Repo-specific conventions, travels with worktrees |
| Application code | Each project repo | The actual product |
| Worktrees | Nothing — ephemeral | Task-isolated working copies, removed after merge |

### 3.9 Authoring Primitives — Skills, Not Commands

The engagement-level gates (`/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose`) are explicit slash commands because their job is auditing — running a checklist against an existing artifact and producing a stable-shape report. Authoring is different: it is conversational, multi-turn, and benefits from auto-triggering when context indicates the work is needed.

Two **skills** under `<project>-harness/.claude/skills/` cover authoring:

| Skill | Scope | Triggers | Output |
|-------|-------|----------|--------|
| `forge-prd-author` | Engagement-level (pre-Gate-1) | Session start with sparse / missing PRD; Gate 1 failed with major gaps; explicit user request | Section-by-section writes to `.forge/project-prd.md` with user approval |
| `forge-gap-check` | Per-feature (post-Gate-3, pre-spec-body) | About to flesh out a feature spec body beyond `## Context` | Appends Blockers (`B-N`) / Warnings (`W-N`) to the spec's `## Open Questions` section; idempotent across re-runs |

Both are **advisory**. They surface gaps; they never decide. They produce no new files (`forge-gap-check` writes into the existing spec; `forge-prd-author` writes into the existing PRD). Promotion to enforcement (e.g., a blocking hook that prevents spec-body writes without a `forge-gap-check` marker) is reserved for if and when real engagements show drift.

The skill / command distinction is documented in `forge-harness/CLAUDE.md`: skill when Claude should auto-trigger from context, command when invocation is always explicit.

**Review skills are separate.** `forge-spec-review` and `forge-plan-review` are also skills (under the same `.claude/skills/` directory) but they live in the *quality* surface, not the authoring surface. They dispatch fresh-context sub-agents per pass (`spec-reviewer`, `plan-reviewer`), apply Blocker/Important fixes between passes, and gate `Status: approved` transitions through evidence hooks (`guard-spec-approval.sh`, `guard-plan-approval.sh`). See §3.4 (sensor classes) and §2.6 (review effort) for the wiring; the cheat sheet in `guide.md` §10 lists every active skill in one place.

### 3.10 Phase-Aware Skill Loading

Skills load their `description` field into every Claude Code session regardless of whether the skill can fire in the current phase. A handful of authoring skills is fine, but the skill set grows over time, and a project in *engineering* phase doesn't benefit from carrying the PRD-authoring skill's description — it just costs context.

Each `SKILL.md` declares phase membership via a `phases:` field in its front-matter:

```yaml
---
name: forge-prd-author
phases: [discovery]
description: ...
---
```

The `phase-scope-skills.sh` hook (PostToolUse, fires on every `.forge/tracker.yaml` edit) derives the current engagement phase from `setup.*` gate statuses (`discovery` → `architecture` → `foundation` → `engineering`), walks each `SKILL.md`, and rewrites `.claude/settings.local.json` `skillOverrides` so out-of-phase skills load as `"off"` (description suppressed from session context). Skills with no `phases:` field stay always-on — the back-compat default for genuinely universal primitives.

Claude Code reads settings *before* `SessionStart` hooks fire, so writes apply to the **next** session, not the current one. At phase transitions the hook prints a one-line stderr nudge asking the developer to restart. In steady state this means zero waste — every session in a phase reads the override map written by the prior transition.

The script is dual-purpose — PostToolUse trigger for normal workflow, plus manually invokable (`./.claude/hooks/phase-scope-skills.sh`) for projects syncing this mechanism into a `tracker.yaml` that's already at its current state. `/forge-doctor` Tier 5 surfaces drift between the current phase and the actual override map.

The convention is documented as a Boundary in the template `.claude/CLAUDE.md` — every new skill should declare `phases:`. Omit only when the skill is genuinely always-on.

---

## 4. Required Artifacts

These are the minimum durable artifacts for a Forge project. Each has a home in the directory structure and a role in the workflow.

### 4.1 CLAUDE.md — The Project Constitution

Thick enough to prevent context drift. Required sections:

- project overview
- architecture overview
- settled technical decisions
- coding patterns with file examples
- naming and branch conventions
- boundaries (three-tier: ALWAYS DO, ASK FIRST, NEVER DO)
- build, test, lint, and run commands
- active context and known risks

#### Minimum Viable CLAUDE.md

A new project does not need a perfect `CLAUDE.md` on day one. It needs one that is good enough to prevent the first few Claude Code sessions from making conflicting decisions. The lead seeds it; the team thickens it through real work.

**Day-one minimum (workspace-level):**

```markdown
# [Project Name]

## Project Overview
<!-- What is this system? Who uses it? One paragraph. -->

## Stack
<!-- Languages, frameworks, databases, key libraries. -->

## Architecture Decisions (DO NOT REVERSE)
<!-- Settled decisions with reasoning. Add to this as decisions are made. -->
| # | Decision | Why | Date |
|---|----------|-----|------|
| 1 | e.g. NestJS for backend API | Team experience, TypeScript ecosystem | 2026-04-01 |

## Naming Conventions
- Branches: `feature/<ticket>-<short-description>`
- Commits: `<type>: <description>` (feat, fix, refactor, docs, test)

## Boundaries

### ALWAYS DO
- Run lint and tests after code changes
- Follow patterns referenced in the plan
- Update plan progress before ending a session

### ASK FIRST
- Install new dependencies
- Change database schema
- Deviate from the approved plan

### NEVER DO
- Do not modify CI/CD pipeline configuration
- Do not commit secrets, keys, or credentials
- Do not delete or overwrite another developer's in-progress work

## Common Commands
<!-- Build, test, lint, dev server. Per-repo if multi-repo. -->
```

**Day-one minimum (repo-level):**

```markdown
# [Repo Name]

## What This Repo Is
<!-- One-line description. -->

## Stack
<!-- Repo-specific stack details. -->

## Patterns to Follow
<!-- Reference specific files as examples when they exist. -->
<!-- e.g. "Follow the pattern in src/modules/users/users.service.ts" -->

## Build & Run
<!-- Exact commands. -->
```

The `CLAUDE.md` is a living document. It starts thin and grows as the team discovers patterns, makes decisions, and encounters edge cases. The critical thing is that it **exists from the start** — even a thin one prevents the first session from making decisions in a vacuum.

#### Compounding Engineering

The `CLAUDE.md` grows deliberately. **Every time AI makes a mistake that will recur, add a rule to prevent it.** This is compounding engineering — each correction becomes permanent context, so the same mistake never happens twice.

The process:
1. AI makes a mistake or produces suboptimal output
2. Identify whether this is a one-off or a pattern
3. If it is a pattern: add a rule to `CLAUDE.md` (if project-wide) or `.claude/rules/` (if scoped to a path)
4. The rule should be actionable, not narrative — "use X instead of Y" rather than "we learned that Y is bad"

This is the primary mechanism by which the harness gets smarter over time. It happens during implementation (when mistakes are caught) and during Reflect (when patterns are reviewed).

### 4.2 Path-Scoped Rules

These keep specialized conventions out of the global context while still making them available when needed. Minimum set:

- backend rules
- frontend rules
- testing rules

### 4.3 Spec Template

The spec must include:

- context
- requirements
- acceptance criteria
- scope boundaries
- constraints and dependencies
- open questions
- input sources

### 4.4 Plan Template

The plan must include:

- approach
- decisions
- ordered subtasks
- files to modify
- risks
- progress (including failed approaches — what was tried and why it didn't work)
- notes

### 4.5 Worktree Convention

Each ticket should have an isolated working directory with the affected repos checked out to feature branches. See §3.7 for commands.

### 4.6 Quality Checklist

There must be a small explicit checklist defining what "checked" means on this project.

**Mandatory gates** (every task, no exceptions):

- Spec review — requirements approved before planning starts
- Plan review — implementation approach approved before coding begins
- Check — lint, tests, and build pass (run via project's existing commands; dedicated `/forge-check` TBD)
- Diff review — implementation verified against spec and plan

**Recommended gates** (use when applicable, skip with justification):

- Security/vulnerability scan (dedicated command TBD) — recommended for auth, data handling, API endpoints. The supply-chain side of security — failing the build on vulnerable dependencies — is a *standing* Build & CI gate, not a per-feature judgment call; see §4.10.
- Adversarial code review (dedicated command TBD) — recommended for complex features, architectural patterns
- Browser QA (dedicated command TBD) — recommended for user-facing UI work

The mandatory gates are non-negotiable. The recommended gates are judgment calls — the developer decides based on the feature's risk profile. Skipping a recommended gate is fine; skipping it without thinking about it is not.

**How the gates are enforced:**

- **Before a gate can fail** — in-session hooks (`.claude/hooks/`) block the lowest-level mistakes automatically: dangerous Bash, protected-path edits, lint and typecheck errors on every edit, and test failures before Claude ends a turn. Hook stderr feeds back to Claude as context so the agent self-corrects on the next turn. Gate-state-aware hooks extend this tier into engagement-level discipline: session-start injection of `tracker.yaml setup.*` orients every session, and pre-write blocks on `.forge/specs/` enforce Gate 2 pass + foundation completion before feature authoring begins.
- **Mechanical check** — runs lint, tests, and build via the project's existing commands; reports pass/fail. A dedicated `/forge-check` command will be introduced when patterns stabilize.
- **Semantic review** — per-feature spec and plan review delegate to read-only sub-agents (`spec-reviewer`, `plan-reviewer`) dispatched per pass by the matching review skill, for adversarial independence from the session that wrote the spec or plan. Adversarial committed-diff review and security review still delegate to direct conversation with Claude or `/council`; the sub-agent slots for those remain documented for future reintroduction (see §3.6).

The checklist items describe *what* must pass. Hooks, skills, and sub-agents are *how*. All three layers are files in the project harness — no platform, no engine.

### 4.7 Project PRD (new projects)

The project-level PRD is the source-of-truth product requirements document for an engagement. It replaces the lighter "project brief" concept from earlier versions of the harness — the realistic delivery situation requires more substance than a brief, since the team commits to delivering against it.

**The PRD is split into three files** (the trichotomy), to keep the live contract small enough to load cheaply and to enable selective context-loading on the consumer side:

| File | Class | Contents |
|------|-------|----------|
| `.forge/project-prd.md` | **Live contract** | Problem, domain, scope, in-scope features, NFRs, constraints, risks, success criteria. Frozen at Gate 1. Verified by `/forge-prd-check`. |
| `.forge/project-prd-signals.md` | **Live signals** | Open and partial open questions only (`⏳ open`, `◐ partial`). Each row anchored to a PRD section and (optionally) to feature IDs it blocks. `spec-reviewer` selectively loads rows whose `Blocks` column matches the feature under review. |
| `.forge/project-prd-history.md` | **Audit trail** | Resolved open questions + PRD revisions. Append-only. Never auto-loaded. |

Risks stay in the live contract (`project-prd.md`), not in signals — they are part of the engagement contract and per-spec risk injection is already handled by `tracker.yaml setup.*`. Only open questions and revisions move to sidecars.

Required sections of `project-prd.md` (the live contract):

- problem statement
- industry / domain context
- business specifics (org structure, current pains, legacy systems being replaced)
- scope and boundaries (in / out / deferred / phasing)
- domain model (entities, relationships, lifecycle states, glossary)
- users and access (roles, capabilities, multi-tenancy)
- functional surface (per-feature description, journeys, integrations)
- non-functional requirements (performance, security, accessibility, observability)
- constraints (tech, regulatory, deployment)
- input sources
- risks
- success criteria
- sidecar files (pointer block to signals + history)

**Open questions are never in the PRD body** — they belong in `project-prd-signals.md`. **Revisions are never in the PRD body** — they belong in `project-prd-history.md`. The `guard-prd-shape.sh` PreToolUse hook enforces this on `project-prd.md`; the path-scoped rule `.claude/rules/prd.md` documents the three-step OQ resolution procedure (fold answer into PRD body, move OQ row to history, append revision entry).

Per-section depth is calibrated to the engagement — an enterprise system with regulatory constraints needs more in some sections than a greenfield internal tool. The PRD-readiness checklist (`.forge/checklists/prd-readiness-checklist.md`) defines the minimum bar; teams customize it per project.

Existing pre-trichotomy projects migrate via the conversation-driven note at `docs/migrations/v0.24-prd-trichotomy.md` — opt-in, no automation.

### 4.8 Discovery Structure (new projects)

A structured location for raw project inputs:

- screenshots and mockups
- documented user flows
- meeting notes and verbal decisions
- feature inventory (if rebuilding from a reference system)

This is a filing convention, not a template. Its purpose is to prevent raw context from scattering across channels where it becomes unfindable.

### 4.9 Design Artifacts

Design artifacts describe **settled** foundational decisions that specs and plans reference. They are distinct from discovery (which captures raw inputs) and from specs (which describe per-feature requirements).

Design artifacts split by ownership, and the split determines where each one lives:

**Harness-level (cross-cutting only):**

- `.forge/design/architecture.md` — system architecture, components, service boundaries, deployment topology, cross-service decisions

Required sections for `architecture.md`:

- overview
- system context (diagram)
- components (what each owns, which repo it lives in)
- data flow
- deployment topology
- cross-cutting concerns (auth, logging, observability)
- build feasibility & high-risk requirements (the requirements that, if they don't work, sink the engagement — each with a paper sketch or a scoped spike)
- in-house-first audit (every external dependency enumerated and justified vs. an in-house alternative)
- resource & timeline reality (team capacity, skills gaps, critical-path estimate vs. delivery window)
- key technical decisions (pointer to `CLAUDE.md` "Architecture Decisions (DO NOT REVERSE)" table — not a duplicate)
- foundation backlog (the enumerated list of scaffolding slices the architecture decisions imply — built between Gate 2 and Gate 3, see §4.10)
- links to repo-level design docs
- open questions

**Code-repo-level (not harness-level):**

| Artifact | Lives In | Why |
|----------|----------|-----|
| Data model, ER diagrams | Backend repo (e.g., `<backend>/docs/data-model.md`) | Schema code is the source of truth; docs drift if separated |
| API contracts (OpenAPI, GraphQL) | Backend repo | Owned by backend, versioned with implementation |
| Style spec, design tokens, component patterns | Frontend repo (e.g., `<frontend>/docs/style-spec.md`) | Component library is the source of truth |

Putting data model or style spec at harness level would force two-commit updates (repo + harness) every time a schema or design token changes. That friction kills documentation maintenance. Repo-level ownership lets the same PR update code and docs together.

**The test:** if you can name the specific repo a design doc would otherwise live in, put it there. Only put it in `.forge/design/` if it is genuinely cross-cutting and belongs to no single repo.

### 4.10 Foundation

Foundation is the **scaffolding code** that has to exist before per-feature work begins — the minimum substrate that lets a developer run the app, write the first user-story feature spec, and have it land on real patterns rather than vapor.

#### Discipline rule

> **Foundation is anything required to run the app and write a user-story feature spec against it. If it has user-visible behavior with its own flows and edge cases, it is a feature, not foundation.**

This rule keeps foundation tight. Auth, specific entity data models, and business flows have flows and edge cases of their own — they are *features*, even though every feature spec eventually depends on them. Features are developed against a stub or open auth surface during dev; auth itself ships as a feature spec like any other.

#### The tooling-vs-instance test

When a slice is borderline, apply this split:

| Foundation | Feature |
|---|---|
| Migration tooling configured (alembic / drizzle / knex / etc.) | The `users` table migration ships with the user feature |
| ORM base classes, repository pattern, transaction primitives | Specific entity models |
| Design tokens + atomic components (Button, Input, Layout primitives) | Feature components (UserCard, Dashboard) |
| Logger and tracing wired into the app | Specific instrumented business flows |
| App shell, routing skeleton, env config | Actual screens |

The *substrate* is foundation; the *first instance* ships with the feature that needs it.

#### Typical foundation slice list

Most engagements have roughly six foundation slices, derived from the architecture:

1. **App shell** — framework boots, routing skeleton, env config, dev server runs
2. **Data layer scaffolding** — DB connection, migration tooling, repository pattern (no entity migrations yet)
3. **Design system primitives** — design tokens + atomic components
4. **Build & CI** — lint, typecheck, tests, build all green on a hello-world commit; a **dependency-vulnerability gate** that fails the build on any dependency CVE at or above a configurable CVSS threshold
5. **Observability stubs** — logger, error reporter, request tracing wired into the app
6. **Developer onramp** — README + "how to add a feature" guide

Architecture decides which apply to a given engagement. The enumerated list is captured in `architecture.md` under "Foundation Backlog" (see §4.9).

**Dependency-vulnerability gate (recommended).** The Build & CI slice should wire a supply-chain scan (e.g. OWASP Dependency-Check) that *fails the build* when a resolved dependency carries a CVE at or above a configurable CVSS threshold — a sensible default is ≥ 7.0. The threshold is read from config, never hardcoded, so CI and per-environment overrides work. Each scanned repo carries a `dependency-check-suppressions.xml` to triage false positives: every entry is justified, suppressed by CVE *and* dependency coordinate, and ideally carries an expiry. Pick one tool and apply it uniformly across every repo in the engagement — a scan wired into one repo but not its sibling is a gap, not a gate. This is distinct from the per-feature application-security review (§ recommended gates): the supply-chain gate is *standing and automated* (it runs on every build), the application review is *per-feature and human*. A generic suppressions-file stub and governance note ship in the template under `.forge/security/`.

#### Where foundation specs and plans live

Foundation slices are real coding work — each gets a spec and a plan and runs through the standard spec → plan → implementation → check → review pipeline (per-step tooling will be introduced as patterns stabilize through real engagement experience). Artifacts live under namespaced subdirectories alongside feature artifacts:

```
.forge/
├── specs/
│   ├── foundation/                    ← foundation specs (numeric prefix enforces build order)
│   │   ├── 001-app-shell-spec.md
│   │   ├── 002-data-layer-spec.md
│   │   └── 003-design-primitives-spec.md
│   ├── auth-spec.md                   ← feature specs (top level)
│   └── dashboard-spec.md
└── plans/
    ├── foundation/
    │   ├── 001-app-shell-plan.md
    │   └── ...
    ├── auth-plan.md
    └── dashboard-plan.md
```

Same template, same lifecycle, same review rigor as features. The subdirectory exists for visual separation only — once dedicated per-step commands are introduced, they will work against `.forge/specs/foundation/...` and `.forge/plans/foundation/...` paths unchanged. Numeric prefixes within `foundation/` enforce the typical build sequence (data layer scaffolding before app screens render data, etc.).

Code-repo-level artifacts still follow §4.9 ownership: ORM base classes live in the backend repo, design tokens live in the frontend repo. The spec under `.forge/specs/foundation/` carries the *requirement*; the repo carries the *truth*.

#### Timing relative to the gates

Foundation work runs **between Gate 2 and Gate 3**:

- **Gate 2 (architecture) produces the foundation backlog** as part of `architecture.md`. Foundation specs *can* draft in parallel with late Gate 2 polish (extending the existing authoring-vs-checkpoint pattern from §2.1) — once architectural decisions are mostly settled, slicing the scaffolding is straightforward.
- **Foundation plans and code wait for full Gate 2 pass.** Specs are cheap to revise; migrations and base classes are not.
- **Gate 3 (decomposition) has foundation as a precondition.** By the time decomposition runs, the substrate is in the repo and reviewed — feature specs can reference real patterns and dependencies rather than vapor.

#### No dedicated skill — manual review

Foundation runs once per engagement, so a dedicated `forge-foundation-check` skill would be amortized over a single use. Per §5.1 (Manual-First Before Automation), the foundation review is a **manual session**: pull all foundation specs and plans into one Claude Code session and walk them critically, optionally invoking `/council` for cross-perspective critique. Capture the review outcome in `.forge/engagement-gate-runs.md` as a precondition note inside Gate 3's entry — no new audit file, no new gate ceremony.

If a pattern emerges across multiple engagements, the skill can grow later. Until then, the manual session is the path.

#### Tracker visibility

Foundation status surfaces in `.forge/tracker.yaml` under `setup.foundation` (status, last_updated, slices). Each slice is listed with its current phase (`not-started` / `in-progress` / `done`) so leadership can see "foundation 4/6 done" at a glance without opening individual artifacts.

### 4.11 Project Tracker

A structured YAML file (`.forge/tracker.yaml`) that provides leadership visibility into project status without requiring access to Claude Code sessions or individual artifact files.

The tracker has three layers:

- **Setup checklist** — pre-development readiness items (project brief, technical decisions, `CLAUDE.md`, environment, feature breakdown). Tracks whether the project is ready to begin feature work.
- **Delivery phases** — stakeholder-facing milestones grouping features into demonstrable slices (see §4.11.1).
- **Feature registry** — each feature's phase, assignee, priority, blockers, `delivery_phase`, and artifact statuses. Populated at decomposition, updated throughout the workflow.

The update mechanism is a `CLAUDE.md` behavioral rule, not a skill or platform feature. Claude updates the tracker as part of any workflow action. Claude never assumes approval — it asks the developer to confirm status before recording it.

Phase gates are encoded as Claude behavior:
- Cannot advance to `plan` unless spec is approved
- Cannot advance to `dev` unless plan is approved
- If the developer wants to skip a gate, Claude asks and records the override

This gives the project gated phases enforced by the AI assistant — the same human gates from the workflow, just encoded as conversation behavior instead of platform features.

#### 4.11.1 Delivery Phases

A `delivery:` block in `tracker.yaml` groups features into stakeholder-facing milestones. Each phase is a demonstrable slice — sealing a phase produces something the team can show stakeholders. Phases are layered *on top of* the dependency graph: `blocked_by` still drives sequencing within a phase; phases drive the narrative across phases.

*Why this exists:* generalized from a bespoke phasing pattern observed in early multi-engagement use — stakeholders and delivery managers wanted a "where are the project now and what ships next?" answer that the dependency graph and feature backlog alone could not give them in a glance.

```yaml
delivery:
  current_phase: 1
  phases:
    - id: 1
      title: "Platform Core"
      theme: "Auth, org structure, navigation, shared schema"
      status: in-progress
      sealed: null
    - id: 2
      title: "Primary Workflow"
      theme: "The core end-to-end user journey on top of the platform"
      status: locked
      sealed: null

features:
  feat-a:
    delivery_phase: 1
    phase: dev
    ...
```

**Locked principles:**

- **Phases are stakeholder narrative, not workflow gates.** They do not introduce a new gate; they re-group features that are already gated by spec → plan → implement → check → review → ship. The only enforcement is the *invariant* that exactly one phase is `in-progress` at a time.
- **Phases are optional.** Projects under ~10 features can leave `delivery.phases: []`. The dashboard hides the delivery view in that case.
- **Phases are project-defined.** Number, names, and themes are chosen at Gate 3. There is no canonical "Phase 1 / 2 / 3" — a project may pick MVP/V1.1/V2, or four phases, or one.
- **Foundation is not a delivery phase.** Foundation slices (F-001..) live under `setup.foundation`. They are pre-feature scaffolding and ship before any delivery phase opens.
- **Phase ordering respects dependencies.** Features in Phase N may only depend on features in Phase ≤ N. Gate 3 verifies this.

**Lifecycle:** phases are populated by `/forge-decompose` (Gate 3). The first phase opens at `in-progress`; subsequent phases start `locked`. When every feature in the active phase is `done` or `dropped`, the developer confirms the seal — the phase flips to `complete` with `sealed: <date>`, the next phase flips to `in-progress`, and `current_phase` advances. The phase-sealing decision is always the developer's; Claude does not auto-seal.

**Why phases.** The dependency graph answers *what blocks what*; the feature table answers *what exists*. Neither answers the delivery-head question *where is the project now and what ships next?* Phases are the layer that answers that — one line in the tracker (`current_phase: 2`) and a phase table in `features.md` are enough for stakeholders, delivery managers, and the team to share a common picture without reading specs.

#### 4.11.2 Bugs & Rework Lineage

The feature registry models work flowing *forward* (`spec → … → done`). Two things that happen *after* a feature ships have their own first-class home in the tracker, because neither fits the feature lifecycle:

**Bugs.** Post-ship defects live in a top-level `bugs:` collection (a sibling of `features:`, **not** nested under a feature). A bug is genuinely M:N — a shared-primitive defect breaks several features at once — so a single-feature home is a false fit; "what open bugs exist?" must be a flat query, not a walk over every feature; and a bug's lifecycle (`open → in-progress → fixed`/`wontfix`) is independent of any feature's phase.

- **A bug does not reopen its feature.** The feature stays `done`; the bug carries its own `status`. The shipped record stays intact while the defect stays visible ("feature-a · done · 1 open bug").
- **The feature↔bug link is single-sourced from `bug.affects`** — features store no duplicate bug list; the per-feature view is derived.
- **A bug's `delivery_phase` is the *scheduled-fix* milestone**, distinct from the affected feature's (frozen history — where it shipped). It defaults to the active phase at discovery; bumping it forward to defer is an auditable action. **A phase cannot be sealed while an open or in-progress bug targets it** — each such bug must be fixed, marked `wontfix`, or explicitly reassigned to a later phase. This is the one extension to the phase-seal rule, ASK-enforced like the rest.
- **Structured metadata in the tracker, prose in `.forge/bugs.md`** (the `lessons.md` pattern — one section per bug, joined by `id`). The bug-fix flow is right-sized, **not** `forge-deliver`: the `bugs.md` entry is the spec, a plan is optional, a regression test + a pre-merge diff review (`/forge-review-pr` on the PR, or `/council`) are mandatory, and the branch is `fix/BUG-NNN-<desc>`.

**Rework lineage.** A feature may carry an optional `follow_up_of: [feature-id…]` naming the feature(s) it reworks or continues ("this is a later pass over those"). It is distinct from `blocked_by` (dependency / sequencing) and from a spec `## Revisions` entry (which also covers typos and clarifications, so a Rev is *not* a rework signal). `follow_up_of` is authoritative; the reciprocal "reworked by" is derived.

*Why this exists:* surfaced live in multi-feature engagement use — a post-ship functional bug and a multi-feature UI-conformance rework both had nowhere structural to live but free-text `notes` and spec Revs, neither queryable nor surfaced. Green unit suites plus a `done` phase masked both. The dashboard surfaces an **Open bugs** signal (grouped by scheduled-fix phase) and a **Rework** signal (rework features → the features they rework), both derived from this tracker data.

#### 4.11.3 Release & UAT Lifecycle

The feature registry ends at `done`; delivery phases end when sealed. But **sealing the last delivery phase is not the end of the engagement.** Once every promised feature has shipped (V1 feature-complete), a real engagement enters a **stabilization-and-acceptance lifecycle** the feature/phase model can't represent: pre-UAT regression of the *assembled* product → handover to UAT → UAT execution by the client → post-UAT stabilization → formal sign-off → go-live to production. A top-level **`release:`** track models exactly this, paired with a triaged **`uat_issues:`** collection for what comes back from UAT.

The `release:` track is a **distinct top-level concept** — it groups *delivery phases* the way a delivery phase groups *features*. It is deliberately **not** a fourth delivery-phase status and **not** a feature-level `phase: testing` (per-feature testing already lives in wave `verify`/`e2e` work items — a feature testing phase would double-count it and collide with wave mode). The genuine gap is one level up: release-level validation of the assembled product before final delivery.

**Lifecycle:** `build-complete → regression → uat → stabilize → signed-off → live` (`uat` and `stabilize` alternate across multiple UAT rounds; `live` is a go-live marker — the signed-off build deployed to production, *not* a production-support subsystem; post-go-live defects use the normal bug-fix flow). Each transition is ASK-enforced — the developer/lead confirms, Forge never auto-advances — the same posture as the phase-seal and bug-fix gates.

**Three gates, all ASK-enforced:**

- **Entry gate** — the release track opens only when every delivery phase in its `scope_phases` is `complete`. Opening earlier is ASK FIRST, recorded in `release.notes`.
- **Handover gate** (`regression → uat`) — at least one internal `regression` cycle must be `passed`/`passed-with-risks`: the team's certification that the assembled product is ready for the client.
- **Sign-off gate** (`stabilize → signed-off`) — the release may not be signed off while any *blocking* `kind: defect` UAT issue is unresolved, and the latest UAT cycle must be `passed`/`passed-with-risks`. Sign-off requires a recorded `signoff_by` + `signed_off` date.

**The parallel-gate insight.** A defect raised during UAT routes into the **existing `bugs:` collection + right-sized bug-fix flow** (it keeps a `bug_ref` link; change-requests, by contrast, are kept *out* of the bug ledger — they become backlog features or defer to a future release). But a UAT defect is found when no delivery phase is active (all sealed), so it carries `delivery_phase: null` and does not drive a phase seal. The **release sign-off gate is the analogous gate** — the phase-seal rule and the sign-off gate are the same shape at two lifecycle stages: a defect found during phase delivery blocks a *phase seal*; a defect found during UAT blocks a *release sign-off*.

**Evidence-backed, driven by `/forge-release`.** Cycles (`RC-n` regression, `UC-n` UAT) carry a compact summary in the tracker — status, a critical-flow checklist, blocking issues, accepted risks — and point at detailed plan/report/evidence files under `.forge/release/<id>/`; no `passed` cycle or manual flow without a linked evidence file. The lifecycle is driven by the **`/forge-release`** command — a state-aware orchestrator that detects the current stage and proposes the next step (open → regression → uat → triage → sign-off → go-live), scaffolding cycle plans and deriving candidate critical flows from feature ACs. It is **manual-first in posture** (§5.1): it proposes, the human confirms each gate, and it writes nothing on its own — and every step remains hand-editable. There is no enforcing hook (gates are ASK, not blocked). v1 models a single active release; sequential releases (V1.1, …) graduate to a list later.

*Why this exists:* the harness modeled delivery as ending at the last phase seal, but engagements continue through a regression → UAT → stabilization → sign-off arc that leadership needs visibility into ("are all flows validated before final delivery?"). Spawned by a lead-meeting ask for "a testing phase in the tracker"; reframed up a level to release validation so the feature lifecycle stays undistorted. The dashboard surfaces a **Release / UAT** section (status, cycle flow pass-counts, blocking issues, triage breakdown), hidden until a release opens.

#### 4.11.4 Delivery Metrics / Estimation Signals

Delivery metrics are the observability layer for future estimation. They answer a different question than `tracker.yaml`: not "what can proceed right now?" but "what actually happened across Forge delivery runs, and what baselines should inform the next estimate?" The source of truth is append-only ledgers under `.forge/metrics/`, not tracker fields.

The default ledgers are:

- `events.jsonl` — delivery lifecycle events: `feature_started` (first `/forge-deliver` invocation per ticket — the start of the feature clock), `spec_approved`, `wi_dispatched`, `wi_pr_opened`, `wave_pr_opened`, `wave_merged`, and `feature_done`.
- `agent-runs.jsonl` — dispatched-agent lifecycle rows: ticket, wave, WI, role, dispatch mode, attempt, outcome, and repair lineage.
- `estimation-snapshots.jsonl` — one feature-completion row summarizing complexity vs actuals: wave/workitem counts, test-tier mix, touched repos, agent runs, repair loops, bugs found, lead time, and test counts.

**Control plane / data plane split.** `tracker.yaml` stays compact and current-state oriented. Metrics rows are immutable history, appended by `/forge-deliver` on a best-effort basis and regenerated into `.forge/dashboard/metrics.js` by `regen-metrics-dashboard.sh`. Malformed rows are dropped per-row; missing ledgers produce an empty dashboard state; failed appends never block delivery.

**Privacy line.** The base metrics ledgers are committable because they carry role/project-level facts only. They do not store `user_email` or per-machine token data. Existing token usage remains local (`.forge/usage.jsonl`, `usage.js`, both gitignored); any future token-joined metrics variant writes to `*.local.jsonl`, also gitignored, unless a separate explicit shared-sink design is approved.

The dashboard surfaces a **Delivery Metrics** section as three grouped panels plus a baseline-volume footnote. **Cycle time** decomposes the feature lead time: spec authoring (`feature_started → spec_approved`), wave-1 cycle (`spec_approved → wave-1 merged` — decomposition plus first build), and later-wave cycle (`prev-wave merged → this-wave merged` — build only); splitting wave-1 from later waves shows how much faster waves run once the spec is paid for. **Throughput** reports features and waves merged per day over a rolling window (default 14 days). **Complexity signals** carry median workitems and agent runs per feature. The feature clock starts at `feature_started` so spec-authoring time is captured rather than lost — all cycle figures are **wall-clock lead times** (idle/blocked time counts toward its segment), labelled as **estimate signals**, not commitments. The metrics are derived in `regen-metrics-dashboard.sh` from ledger timestamps with no change to the row schemas.

#### 4.11.5 Harness-Native Estimation (Baked Baselines + `forge-estimate`)

Estimation in Forge is never human-effort-days. A feature's forecast is its **size vector** (waves × work items) multiplied by **measured cycle medians** (fractional wall-clock days) from the delivery-metrics ledgers (§4.11.4).

The org-level medians ship in the template as a **baked, versioned baseline** (`.claude/skills/forge-estimate/baselines.json`, schema `forge-baselines/v1`) — generated by `forge-rollup --emit-baselines` in the meta repo from completed engagements, frozen per harness version, refreshed only by a deliberate recalibration released through `/forge-harness-sync`. Projects never fetch baselines at runtime.

The always-on `forge-estimate` skill predicts the size vector (anchored on the Gate-3 sizing signals), delegates all arithmetic to the deterministic `.claude/lib/forge-estimate.sh` helper (a project's own ledger medians outrank the baked values once a metric has ≥5 own samples), and answers only in **ranges** with a mandatory basis line (source, `n`, baseline version) and the queue-time caveat — *at measured cadence, once picked up*; calendar delivery adds human queue time. An uncalibrated baseline yields a refusal, never a fabricated number. `/forge-decompose` step 10 and `/forge-set-dates` surface the same forecast as advisory annotation only — `/forge-set-dates` remains the single date-writer.

### 4.12 Engagement Gate Runs Log

For projects that go through the pre-implementation gates (Gate 1 / 2 / 3), the engagement maintains a shared append-only audit log at `.forge/engagement-gate-runs.md`.

Why it exists: the engagement-level artifacts (PRD, architecture, feature backlog) don't have built-in lifecycle-metadata sections like specs do (`## Revisions`). The audit log is their shared narrative trail — what was found on each gate run, what was accepted as risk or scoped as a spike, who decided.

Format: chronological, newest entry at the bottom (blocks are appended). One `## Gate N Run M` block per run, written automatically by `/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose` in full mode (skipped in `dry-run` mode).

Required content per entry:

- gate number, run number, ISO date, runner name
- mode (`full`)
- outcome verdict (`pass` / `pass-with-risks` / `pass-with-spikes` / `fail`)
- trigger (why the gate ran — initial checkpoint, after PRD revision, etc.)
- per-checklist-item findings (pass / fail / N/A with gap statements where applicable)
- list of risks accepted or spikes scoped (each with id, owner, brief reasoning)

This file is read alongside `.forge/project-prd.md` `## Gate Status` (compact snapshot) and `.forge/tracker.yaml` `setup.*` (structured machine-readable state) — three layers, each at its right scope. See §5.8 for the locked principle and the project's `.claude/rules/tracker.md` "Gate Audit Protocol" for the per-skill write contract.

Per-feature gates (spec review, plan review, adversarial review, security review) do **not** appear in this file — their findings live in the per-feature spec / plan artifacts. Tool-call-level gates (hooks) do **not** appear here — they're ephemeral.

### 4.13 Team Guide

A short (one-page) document that tells the development crew how the workflow operates on this project. Not a process manual — a practical reference for daily work. Covers:

- where to find things (`CLAUDE.md`, specs, plans, discovery)
- the workflow phases and gates
- what artifacts to produce
- how to update shared context
- how to manage long sessions (use subtasks as session boundaries, update plan progress before ending a session, prefer multiple focused sessions over marathon sessions)

The per-project team guide complements the framework-level [`guide.md`](guide.md): the framework guide covers *how the harness works*; the per-project team guide covers *how this specific project's team uses it* (stack, repos, people, ceremonies).

### 4.14 Findings (Per-Feature Tactical Learnings)

Each feature has an optional `<feature>-findings.md` at `.forge/specs/<feature>-findings.md`, sibling to the spec and parallel to the plan. It captures tactical learnings during/after the feature's development — debugging insights, API quirks, "next time do X first." One entry per coherent finding, ID format `F-NNN`, append-only.

Findings are scoped *to the feature*. Engagement-wide strategic lessons live in `.forge/lessons.md`. Promotion from findings to lessons happens during the **Reflect** phase — walk the feature's findings, decide which ones generalize beyond this feature, abstract them into `lessons.md` entries (`L-NNN`), and annotate the source finding with `Promoted: L-NNN` (bare lesson ID, regex-parseable as `Promoted: L-\d+`). Findings that don't generalize stay scoped (annotated `Promoted: scoped`).

The boundary against other artifacts:

- Plan `## Notes` — decisions made *during planning*, before code starts
- Plan `## Progress` — what got done; failed approaches and why
- **`<feature>-findings.md`** — tactical learnings during/after the feature, specific to it
- `.forge/lessons.md` — engagement-wide strategic lessons that should flow upstream or apply to future features

The shape lives in `_TEMPLATE-findings.md`. The promotion ritual is documented in the project `CLAUDE.md` Workflow Phases (Reflect row).

---

## 5. Framework Decisions

These are the locked decisions. Each has been validated enough in real work to be treated as doctrine. Reversing one requires an explicit framework-level conversation, not a silent drift.

### 5.1 Manual-First Before Automation

If the framework does not work in plain manual execution, automation will only hide the defects. Automation comes later, built on top of a framework already proven in real work.

### 5.2 Spec and Plan Remain Separate

This is one of the highest-value process boundaries in the whole system. The spec is *what*; the plan is *how*. Merging them collapses the gate between requirements review and implementation review — exactly the gate where most compounding errors get caught.

### 5.3 CLAUDE.md Is Mandatory and Thick

This is not optional documentation. It is operating context. A thin `CLAUDE.md` means every session re-derives decisions from scratch.

### 5.4 Context Must Live in Files

Conversation memory is helpful, but it cannot be the system of record. Anything a second developer needs to resume the work must exist in a file.

### 5.5 Worktree-Based Task Isolation Is the Default

This fits the multi-repo reality and preserves developer flow. Main checkouts stay clean; features live in isolated directories under `worktrees/`.

### 5.6 Guides Stay Interactive; Sensors Run Independently

Feedforward roles — spec, plan, implementation — remain in the main session because their quality depends on dialogue with the developer. Feedback roles — review, security review — run as read-only sub-agents so adversarial reading is structurally independent of the session that produced the code.

This is the rule that decides when a new role becomes a sub-agent. Without it, sub-agents proliferate until the workflow becomes pipeline orchestration — exactly the agent-manager vision the framework defers to later phases.

### 5.7 Spec Revisions Use a Changelog Section

Approved specs are contracts. Revisions are allowed, but they must be explicit.

When a spec needs to change after approval:

1. **Add a revision entry** to the spec's `## Revisions` section (added at the bottom of every spec):

```markdown
## Revisions

### Rev 1 — 2026-04-05
- **Changed:** Requirement 3 updated — bulk assignment now limited to 20 groups (was unlimited)
- **Why:** Core API has a batch size limit of 20. Discovered during plan creation.
- **Impact on plan:** Subtask 4 needs pagination logic added
- **Approved by:** Thilina
```

2. **Update the affected requirements and acceptance criteria** in the spec body to reflect the change. The revision log records what changed; the spec body stays current.

3. **If a plan already exists**, note the impact in the revision entry. The developer updates the plan accordingly.

**When is a revision required vs. just updating?**

- **Revision required:** any change to requirements, acceptance criteria, or scope boundaries after the spec has been approved.
- **No revision needed:** fixing typos, adding clarifying detail that does not change the requirement, updating open questions.

The goal is lightweight traceability — not bureaucracy. A one-line revision entry takes 30 seconds. Undoing silent drift takes hours.

### 5.8 Audit Storage Matches Artifact Scope

Findings from each quality gate persist at the same scope as the artifact the gate serves. This prevents one-size-fits-all audit storage from breaking under scale (high-frequency gates would otherwise bloat shared files; low-frequency gates would otherwise have no durable home).

Three classes of gates, three audit patterns:

| Gate scope | Examples | Where audit lives |
|---|---|---|
| Engagement-level | PRD readiness, architecture probe, decomposition | Dedicated append-only log at `.forge/engagement-gate-runs.md`, plus snapshot table at top of `project-prd.md`, plus structured state in `tracker.yaml` `setup.*` |
| Per-feature | Spec review, plan review, adversarial review, security review | Reuse existing per-feature artifacts: spec body and `## Revisions`, plan `## Notes` and `## Progress`. No new files |
| Tool-call-level | Hooks, lint, typecheck on every edit | Ephemeral. Stderr feedback to Claude in-session. No persistent audit |

This is what allows the gate model to grow without each new gate forcing a doctrine question about where its findings go — the answer is determined by the gate's scope. New engagement-level gate? Append to `engagement-gate-runs.md`. New per-feature gate? Use the existing per-feature artifacts. New hook? Ephemeral.

The corollary: skills implementing engagement-level gates support a `dry-run` mode for calibration and testing. Real runs always audit; dry-runs print findings to the session and write nothing.

### 5.9 Authoring Assistance Is Advisory by Default

Skills that *help author* artifacts (`forge-prd-author`, `forge-gap-check`) are advisory primitives. They surface gaps and propose drafts; they never decide, and they are not enforced by blocking hooks. Promotion to enforcement (e.g., a hook that blocks spec-body writes without a `forge-gap-check` marker) is reserved for if and when real engagements show drift in practice.

This sits under §5.1 (manual-first): authoring discipline is a workflow concern, not a gating concern. Gates audit *after* authoring is done. See §3.9 for the current authoring primitives.

### 5.10 No Self-Approval on Gates; Evidence Required for Pass Claims

When claiming any gate or verification has passed, the agent must list the specific commands run and their output. The verdict on audited gates (`/forge-prd-check`, `/forge-arch-probe`, `/forge-decompose`) always comes from the developer; the agent surfaces findings, never grants its own pass.

This sits under §5.1 (manual-first): trust at the gate boundary is built on receipts, not on the agent's self-assessment. The deterministic checks (`verify-before-stop`, `lint-and-typecheck`) cover the testing side automatically; this rule covers the agent's verbal claims mid-conversation. See the project `CLAUDE.md` `ALWAYS DO` rule for the operational form.

---

## 6. Tool Coupling & Portability

Forge is intentionally optimized for Claude Code today without making Forge itself conceptually dependent on Claude forever. That distinction matters.

### 6.1 Two Layers

Forge has two layers:

**Core Forge layer — tool-agnostic in principle:**
- workflow
- specs
- plans
- quality gates
- worktree model
- review process
- project constitution as a concept

**Tool adapter layer — tool-specific implementation:**
- `.claude/CLAUDE.md`
- `.claude/rules/*`
- `.claude/skills/*`
- `.claude/agents/*`
- `.claude/hooks/*`

If another team later works primarily in Cursor or another environment, Forge should not need to be reinvented. It should only need a different adapter.

### 6.2 Claude-First in Practice

Right now, Claude Code is the primary working environment. That makes a Claude-first implementation reasonable — the adapter layer is Claude-shaped because that is where most work actually happens.

This is a practical choice, not a permanent constraint. Forge does not need to support every tool equally today. It needs to:

- be Claude-first in execution
- be clear that Claude-specific files are an adapter, not the whole theory of the framework
- avoid embedding Claude-only assumptions into the core spec/plan/process model

### 6.3 Keeping Durable Artifacts Tool-Neutral

When possible, keep the durable delivery artifacts tool-neutral:

- `.forge/specs/...`
- `.forge/plans/...`
- project conventions and workflow definitions

Treat `.claude/*` as the current operational interface for those artifacts.

That gives the right tradeoff:

- optimized for the tool actually used today
- not forced into fake genericity
- still portable later if the team mix changes

---

## Appendix A — Versioning and Evolution

The harness evolves deliberately, not continuously. Changes to this framework are tracked in [`../CHANGELOG.yaml`](../CHANGELOG.yaml) using semantic versioning:

- **Patch** (0.x.Y): small fixes, clarifications, template polish
- **Minor** (0.X.0): new concepts or artifacts (a new skill, a new required section, a new agent type)
- **Major** (X.0.0): breaking changes — restructured workflow phases, renamed core concepts, incompatible template changes

Every change to a template file or framework doc requires a changelog entry in the same commit. One commit, one version bump. When a project bootstraps from this harness, its `CHANGELOG.yaml` compatibility marker records which version of the framework it was seeded from — enabling future `/forge-harness-sync` to apply deltas deliberately.

The harness is currently in the v0.x series (validating in first real engagement). It will bump to v1.0 once the first project ships end-to-end using the framework without requiring doctrine-level changes.

## Appendix B — Where to Go Next

- **Using the harness on a project:** [`guide.md`](guide.md) — phase-by-phase playbook, worktree commands, skills cheat sheet, troubleshooting.
- **Understanding the accumulated raw material:** [`INDEX.md`](INDEX.md) — research deep dives, meeting notes, lessons learned.
- **Framework archaeology (origin story, theory inputs, original rationale):** [`archive/v0-proposal.md`](archive/v0-proposal.md) — the frozen v0 proposal.
- **Bootstrapping a new project:** run `./bootstrap.sh <project-name> [target-parent-dir]` from the repo root. See [`guide.md`](guide.md#2-bootstrapping-a-new-project) for what to do next.
