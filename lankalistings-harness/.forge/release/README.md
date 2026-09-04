# Release & UAT Evidence

Detailed evidence for the post-delivery **release lifecycle** — the
stabilization-and-acceptance stage that begins once every delivery phase has
sealed (V1 feature-complete). The compact summary state lives in
`.forge/tracker.yaml` under the top-level `release:` track and `uat_issues:`
collection; **this directory holds the detail** the tracker points at.

This mirrors the established split: tracker is the control plane (status, gates,
what's blocking), evidence files are the data plane (what was tested, what came
back, the proof). See `.claude/rules/tracker.md` → "Release & UAT Lifecycle"
for the lifecycle vocabulary, the three ASK-enforced gates (entry / handover /
sign-off), and the UAT-issue triage routing.

## Per-release layout

Every release's evidence lives under `.forge/release/<id>/` (`<id>` = the
`release.id`, e.g. `V1`):

```
.forge/release/
├── README.md                      # this file
├── _TEMPLATE-cycle-plan.md        # copy → <id>/RC-n-plan.md  / <id>/UC-n-plan.md
├── _TEMPLATE-cycle-report.md      # copy → <id>/RC-n-report.md / <id>/UC-n-report.md
├── _TEMPLATE-uat-issues.md        # copy → <id>/uat-issues.md  (one per release)
└── V1/                            # one directory per release id
    ├── RC-1-plan.md               # regression cycle plan
    ├── RC-1-report.md             # regression cycle report
    ├── UC-1-plan.md               # UAT cycle plan
    ├── UC-1-report.md             # UAT cycle report (written when the cycle completes)
    ├── uat-issues.md              # prose home for this release's UAT issues (UAT-NNN sections)
    └── evidence/
        ├── RC-1/
        │   ├── FLOW-001.md        # per-flow evidence (operator, env, steps, result)
        │   └── FLOW-002.md
        └── UC-1/
            └── FLOW-003.md
```

## Conventions

- **Cycle ids:** `RC-n` (regression, internal) and `UC-n` (UAT, client-executed)
  — distinct from `UAT-NNN` issue ids to avoid visual collision. The tracker's
  `release.cycles[].plan` / `.report` fields point at the matching files here.
- **One `uat-issues.md` per release**, joined to the tracker's `uat_issues:`
  collection by `id` (the `bugs.md` prose-home pattern). Structured metadata
  (kind, status, bug_ref, blocking, …) stays in the tracker; prose lives here.
- **Evidence is mandatory for claims.** Every cycle marked `passed` and every
  `manual` / `exploratory` flow marked `passed` must point at an evidence file
  under `evidence/<cycle-id>/`. No self-approved "all flows validated" — same
  doctrine as the gate-evidence rule. Automated `e2e` flows may cite the test
  run / report instead of a hand-written evidence file.
- **Archive on sign-off.** When a release is `signed-off`, its `<id>/` directory
  is retained as the historical record (it does not get deleted); a sequential
  release opens its own `<id>/` directory.

## What does NOT live here

- Structured release/cycle/issue state → `.forge/tracker.yaml` (`release:`,
  `uat_issues:`).
- Routed defects → the `bugs:` collection + `.forge/bugs.md` (a UAT defect keeps
  a `bug_ref` link; its fix detail lives in `bugs.md`, not here).
- Per-feature/per-wave test counts → the existing `.forge/plans/<ticket>/<ticket>-test-stats.jsonl`
  and `*-test-report.md` (regression cycles *reference* these, they do not
  regenerate them).
