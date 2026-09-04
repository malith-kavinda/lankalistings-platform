# Bugs

Post-ship defect descriptions. One section per bug, keyed by `id` (`BUG-NNN`).

This file is the **prose home** for bugs; the structured metadata (status, severity,
`affects`, `delivery_phase`, `fix_pr`) lives in `.forge/tracker.yaml` under the
top-level `bugs:` collection, joined to these sections by `id`. This mirrors the
feature↔spec and lesson patterns: structured state in `tracker.yaml`, prose here.

**Append-only.** `fixed` / `wontfix` bugs keep their section as a historical record —
the dashboard filters to open bugs by default. A heavy bug may graduate to its own
`.forge/bugs/BUG-NNN.md` via the optional `doc:` field in the tracker; the single
section below is the default so a batch of small bugs doesn't explode into a file each.

The bug-fix flow is **right-sized — NOT `forge-deliver`**: the section below *is* the
spec, a plan is optional and proportionate, and a regression test + a pre-merge diff
review (`/forge-review-pr` on the PR, or `/council`) are mandatory regardless of size.
See `.claude/rules/tracker.md` → "Bug Tracking" for
the full lifecycle, the phase-seal rule, and the fix flow.

## Section format

Each bug is an `h3` heading `### BUG-NNN — <short title>`, newest on top, followed by
the repro and fix detail:

```markdown
### BUG-001 — Sub-org Manage card: last child-link unlink must route to Archive
**Affects:** feature-a · **Found in:** feature-c · **Severity:** high · **Phase:** 1
**Repro:** open a record with exactly one linked child → Unlink is enabled.
**Expected:** last-link unlink is blocked / routed to Archive (FR-5, FR-10).
**Actual:** bare unlink attempted → backend rejects (or orphans the record).
**Fix:** disable Unlink on the sole remaining link; point to the Archive flow.
```

---

<!-- Bug sections go below, newest on top. -->
