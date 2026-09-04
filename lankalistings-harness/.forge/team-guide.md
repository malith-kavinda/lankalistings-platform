# LankaListings — Team Guide

> **One-page reference for how this project's team operates.**
>
> For the **framework workflow itself** (phases, gates, session management, compounding engineering, troubleshooting), see the Altrium Forge Harness [Guide](https://github.com/[org]/forge-harness/blob/main/docs/methodology/guide.md). This document is the project-specific layer on top of that.

---

## The Team

<!-- Who's on the crew, who leads, who reviews what. -->

| Role | Person | Responsibilities |
|------|--------|------------------|
| Project lead | [Name] | Seeds bootstrap artifacts, reviews foundational specs/plans, final approval on architecture decisions |
| [Role] | [Name] | [Areas] |
| [Role] | [Name] | [Areas] |

## Review Pairings

- **Foundational features** (auth, data model, navigation): reviewed by [lead]
- **Standard features**: peer review — the developer who didn't write it reviews it
- **Security-sensitive** (auth, data handling, external APIs): security review mandatory (currently via direct conversation with Claude or `/council`; dedicated command TBD), plus [lead] review

## Where to Find Things

| What | Where |
|------|-------|
| Project constitution | `.claude/CLAUDE.md` |
| Workspace rules | `.claude/rules/` |
| Forge slash commands | `.claude/commands/` |
| Project PRD | `.forge/project-prd.md` |
| System architecture | `.forge/design/architecture.md` |
| Discovery artifacts | `.forge/discovery/` |
| Feature specs | `.forge/specs/` |
| Implementation plans | `.forge/plans/` |
| Project tracker | `.forge/tracker.yaml` |
| Quality checklist | `.forge/checklists/quality-checklist.md` |
| Data model, ER diagrams, API contracts | Backend repo (`[<project>-be]/docs/`) |
| Style spec, design tokens, component patterns | Frontend repo (`[<project>-fe]/docs/`) |

## Repos on This Project

```
[<project>]/                          # plain directory — NOT a git repo
├── [<project>]-harness/              # this repo
├── [<project>]-be/                   # backend — [stack: e.g. NestJS + Postgres]
├── [<project>]-fe/                   # frontend — [stack: e.g. React + Vite]
└── worktrees/                        # ephemeral task isolation
```

Remotes:
- Harness: `[remote URL]`
- Backend: `[remote URL]`
- Frontend: `[remote URL]`

## Cross-Repo Commands

<!-- Project-specific commands that span repos — dev server startup, shared migrations, etc. -->

```bash
# Example: start both dev servers for the dashboard feature worktree
cd worktrees/dashboard
(cd [<project>]-be && npm run dev) &
(cd [<project>]-fe && npm run dev)
```

## Ceremonies

<!-- How this specific team works — standup cadence, planning rhythm, retro cadence. -->

- **Standup:** [cadence, channel]
- **Planning:** [cadence, who attends]
- **Retro:** [cadence, format]
- **Demo:** [cadence, audience]

## Communication

- **Slack channel:** `[#channel]`
- **Design questions:** `[#channel]`
- **Blockers / escalation:** `[person / channel]`

## Environments

<!-- Where dev, staging, prod live. Who has access. How deploys work. -->

| Environment | URL | Deploys from | Notes |
|-------------|-----|--------------|-------|
| Local | — | — | `npm run dev` in each repo |
| Dev | [URL] | [branch] | [notes] |
| Staging | [URL] | [branch] | [notes] |
| Prod | [URL] | [branch] | [notes] |

## How We Use the Forge Workflow on This Project

<!-- Any deviations from the framework-level defaults, or project-specific conventions on top. -->

- **Tracker cadence:** [e.g. "lead reviews tracker.yaml daily at standup"]
- **Spec/plan reviewer assignment:** [e.g. "rotating, tracked in tracker.yaml `reviewer` field"]
- **Council invocation rule:** [e.g. "mandatory for any cross-service architecture decision"]
- **Any project-specific gates:** [e.g. "performance budget check on all FE PRs"]

If this section stays empty, the team uses the framework defaults as-is — that's fine.

---

## Framework Reference

For everything not covered above (workflow phases, gates, session management, compounding engineering, quality gates, troubleshooting):

- **[Altrium Forge Harness Guide](https://github.com/[org]/forge-harness/blob/main/docs/methodology/guide.md)** — day-to-day playbook
- **[Altrium Forge Harness Framework Reference](https://github.com/[org]/forge-harness/blob/main/docs/methodology/framework.md)** — model and rationale
