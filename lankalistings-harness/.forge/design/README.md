# Forge Design

> Foundational design artifacts that the rest of the project builds on.

## What Lives Here

The harness-level `.forge/design/` folder contains **cross-cutting** design artifacts — the ones that describe how the project's repos fit together, not what lives inside any single repo.

- `architecture.md` — system architecture, component relationships, service boundaries, deployment topology, cross-service decisions

That is intentionally a very short list. Most design content is **not** cross-cutting and should live next to the code it describes.

## What Does NOT Live Here

The following are **not** harness-level artifacts. They live in the code repos they belong to:

| Artifact | Lives In | Why |
|----------|----------|-----|
| Data model, ER diagrams | Backend repo (e.g., `<backend>/docs/data-model.md`) | The schema code is the source of truth — docs drift if they live separately |
| API contracts (OpenAPI, GraphQL schema, etc.) | Backend repo | Owned by backend, versioned with the code that implements them |
| Style spec, design tokens, component patterns | Frontend repo (e.g., `<frontend>/docs/style-spec.md`) | The component library is the source of truth |
| Repo-specific patterns and conventions | Each repo's `CLAUDE.md` or `.claude/rules/` | Loaded as Claude Code context when working in that repo |

During planning, Claude Code explores the relevant code repo and finds both the code and its docs together — no manual cross-reference needed. Putting these artifacts at harness level would force two-commit updates every time a schema or style changes, which is exactly how documentation silently dies.

## When to Add a New File Here

Only add a new file to `.forge/design/` when it describes something that is genuinely cross-cutting and does not belong to any single code repo. Examples that *would* justify a new harness-level design file:

- A shared event schema for an event-driven system spanning multiple services
- A cross-service authorization or permission model
- A shared protocol, wire format, or inter-service contract

**Test:** if you can name the specific repo a doc would otherwise live in, put it there. If you genuinely cannot, it belongs here.

## Seeding at Project Start

At project start, `architecture.md` is typically the first design artifact. The project lead seeds it from the project brief and discovery findings.

Data model sketches, API thoughts, and style ideas that emerge during early conversations start life in `.forge/discovery/` as raw inputs. As soon as the backend and frontend repos are created (which should happen early — see Section 8 of the V0 proposal), these sketches get promoted into `<backend>/docs/` and `<frontend>/docs/` as the owning team's living documentation.

**Discovery is the staging area. Code repos are the permanent homes.**
