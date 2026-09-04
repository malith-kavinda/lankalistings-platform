# UAT Issues — [release id, e.g. V1]

Prose home for this release's UAT issues. One section per issue, keyed by `id`
(`UAT-NNN`). The structured metadata (`kind`, `status`, `severity`, `bug_ref`,
`blocking`, `resolution`) lives in `.forge/tracker.yaml` under the top-level
`uat_issues:` collection, joined to these sections by `id` — the same prose-home
pattern as `.forge/bugs.md`.

**Triage routing** (full rule in `.claude/rules/tracker.md` → "Release & UAT
Lifecycle"):

- `defect` → routes into the existing `bugs:` collection + bug-fix flow; keeps a
  `bug_ref: BUG-NNN` link. **Change-requests never enter the bug ledger.**
- `change-request` → becomes a backlog feature (`feature_ref`) or is deferred to
  a future release; tracked via `resolution`. Never a bug.
- `query` → answered and `closed`. No code change.

A blocking `defect` (`blocking: true`) blocks the **release sign-off gate** the
way an in-phase defect blocks a phase seal — see the parallel-gate note in
"Bug Tracking".

**Append-only.** `closed` / `rejected` / `deferred` issues keep their section as
a historical record.

## Section format

Each issue is an `h3` heading `### UAT-NNN — <short title>`, newest on top:

```markdown
### UAT-001 — Conversion confirmation email never sends
**Kind:** defect · **Cycle:** UC-1 · **Severity:** high · **Blocking:** true · **Bug:** BUG-014
**Raised by:** Client UAT team · **Raised:** YYYY-MM-DD
**Steps:** convert a lead to a student → expect a confirmation email → none arrives.
**Expected:** confirmation email sent on conversion (feature-d AC-4).
**Actual:** no email; no error surfaced to the user.
**Resolution:** routed to BUG-014; fixed in `<repo>#62`; awaiting UC-1 round 2 verification.

### UAT-002 — Add bulk CSV import for leads
**Kind:** change-request · **Cycle:** UC-1 · **Blocking:** false · **Feature:** FEAT-030
**Raised by:** Client sponsor · **Raised:** YYYY-MM-DD
**Request:** import leads in bulk from a CSV rather than one at a time.
**Resolution:** deferred to V1.1 — backlog FEAT-030. Not a defect; does not block sign-off.
```

---

<!-- UAT issue sections go below, newest on top. -->
