# Foundation Plans

Implementation plans for foundation slices. Same template, same lifecycle, same review rigor as feature plans (`_TEMPLATE-plan.md`, one level up) — the subdirectory exists for visual separation.

See `docs/methodology/framework.md` §4.10 in the harness repo for the full doctrine. See `.forge/specs/foundation/README.md` for the discipline rule and slice list.

## Naming Convention

Match the matching foundation spec's numeric prefix:

```
001-app-shell-plan.md           ← plan for 001-app-shell-spec.md
002-data-layer-plan.md          ← plan for 002-data-layer-spec.md
...
```

## Relationship to Feature Plans

Foundation plans and feature plans use the same template and the same workflow. The only difference is namespace — foundation under `foundation/`, features at the top level. Per-step tooling (e.g., `/forge-plan`, `/forge-check`, `/forge-pr`) will be introduced as patterns stabilize through real engagement experience; for now these steps run via direct conversation with Claude.

Each foundation plan should:

- Reference its foundation spec
- Identify which code repo(s) the work lands in
- Explicitly call out *what is NOT in scope* — e.g., for the data-layer scaffolding plan: "no entity migrations in this plan; the `users` table migration ships with the user feature"
- Follow the standard plan structure: Approach, Decisions, Ordered Subtasks, Files to Modify, Risks, Progress, Notes

## Wait for Full Gate 2 Pass

Foundation specs *can* draft in parallel with late Gate 2 polish, but **plans and code wait for full Gate 2 pass**. Specs are cheap to revise; migrations and base classes are not.

## Gate 3 Precondition

Once all foundation plans are implemented, merged, and the manual foundation review (a single Claude Code session walking all foundation specs/plans together, optionally `/council`) is captured in `.forge/engagement-gate-runs.md`, Gate 3 (`/forge-decompose`) can run.
