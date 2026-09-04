# Foundation Specs

Foundation specs describe the **scaffolding code** that has to exist before per-feature work begins — the minimum substrate that lets a developer run the app, write a user-story feature spec, and have it land on real patterns rather than vapor.

See `docs/methodology/framework.md` §4.10 in the harness repo for the full doctrine.

## Discipline Rule

> **Foundation = anything required to run the app and write a user-story feature spec against it. If it has user-visible behavior with its own flows and edge cases, it is a feature, not foundation.**

This rule keeps foundation tight. Auth, specific entity data models, and business flows have flows and edge cases of their own — they are *features*, even though every feature spec eventually depends on them.

## The Tooling-vs-Instance Test

When a slice is borderline, the *substrate* is foundation; the *first instance* ships with the feature that needs it.

| Foundation | Feature |
|---|---|
| Migration tooling configured (alembic / drizzle / knex / etc.) | The `users` table migration ships with the user feature |
| ORM base classes, repository pattern, transaction primitives | Specific entity models |
| Design tokens + atomic components (Button, Input, Layout primitives) | Feature components (UserCard, Dashboard) |
| Logger and tracing wired into the app | Specific instrumented business flows |
| App shell, routing skeleton, env config | Actual screens |

## Typical Slice List

Most engagements have roughly six foundation slices, derived from `architecture.md`'s Foundation Backlog section:

1. **App shell** — framework boots, routing skeleton, env config, dev server runs
2. **Data layer scaffolding** — DB connection, migration tooling, repository pattern (no entity migrations yet)
3. **Design system primitives** — design tokens + atomic components
4. **Build & CI** — lint, typecheck, tests, build all green on a hello-world commit
5. **Observability stubs** — logger, error reporter, request tracing wired into the app
6. **Developer onramp** — README + "how to add a feature" guide

## Naming Convention

Numeric prefix to enforce build order:

```
001-app-shell-spec.md
002-data-layer-spec.md
003-design-primitives-spec.md
004-build-and-ci-spec.md
005-observability-stubs-spec.md
006-developer-onramp-spec.md
```

Use the same `_TEMPLATE-spec.md` template as feature specs (one level up). Same lifecycle, same review rigor — the subdirectory exists for visual separation only.

## How Foundation Work Happens

1. **Gate 2 enumerates the foundation backlog** in `architecture.md` (Foundation Backlog section).
2. **Foundation specs draft** — can run in parallel with late Gate 2 polish.
3. **Foundation plans + implementation** — wait for full Gate 2 pass. Each slice runs through the standard spec → plan → implementation → check → review → PR pipeline. Per-step tooling will be introduced as patterns stabilize through real engagement experience; for now these steps run via direct conversation with Claude.
4. **Manual foundation review** — pull all foundation specs and plans into one Claude Code session, walk them critically (optionally `/council`). No dedicated `forge-foundation-check` command — one-time engagement work doesn't justify automation.
5. **Capture review outcome** in `.forge/engagement-gate-runs.md` as a precondition note for Gate 3.
6. **Gate 3 runs** with foundation as a precondition — feature decomposition slices on top of an existing substrate.

## Tracker Visibility

Each slice has an entry under `setup.foundation.slices` in `.forge/tracker.yaml`. Status moves through `not-started` → `in-progress` → `done`. Leadership can see "foundation 4/6 done" without opening individual artifacts.

## Where Code Lives

Spec under `.forge/specs/foundation/` carries the *requirement*. Code lives in the appropriate code repo:

- ORM base classes → backend repo
- Design tokens + atomic components → frontend repo
- App shell → frontend repo (or backend if API-only)
- CI/build config → wherever the build runs

The harness owns the spec; the repo owns the truth. Same ownership rule as feature work (see `framework.md` §4.9).
