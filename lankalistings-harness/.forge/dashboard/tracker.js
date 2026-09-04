/* Generated from ../tracker.yaml by hooks/regen-tracker-dashboard.sh. Do not edit. */
window.TRACKER = {
  "project": "LankaListings",
  "harness_version": "0.36.1",
  "last_updated": "2026-08-24T16:00:00",
  "github_org": "",
  "setup": {
    "status": "in-progress",
    "project_prd": {
      "status": "in-progress",
      "last_gate_run": null,
      "owner": null,
      "notes": "Drafted 2026-08-24 from a RECONSTRUCTED discovery pack — the original engineering pack published a map of 8 documents but only its index existed; the other 7 were rebuilt from real artefacts (locked decision table, 2 design systems, 17 Stitch screens, 3 app skeletons) plus a product-owner scoping conversation. 34 open questions live in project-prd-signals.md. Gate 1 must answer OQ-01 (is in-app messaging in scope?), OQ-02 (is AI/OCR ad intake in scope?) and OQ-20 (team size + delivery window) before anything can be sized — each changes the shape of the plan, not a detail within it.",
      "accepted_risks": []
    },
    "architecture": {
      "status": "in-progress",
      "last_gate_run": null,
      "owner": null,
      "notes": "Drafted 2026-08-24. LOCKED: microservices using both Spring Boot and FastAPI, with FastAPI serving the management portal's CRUD surface; three client surfaces including mobile. PROPOSED and awaiting Gate 2: a five-service split (identity/listing/payment on Spring Boot; admin/media on FastAPI), the capability-based language boundary, PostgreSQL per service, and the whole deployment shape. 13 architecture open questions (OQ-21..OQ-33). Two spikes are pre-identified: F-002 two-service gateway/auth/observability spike (gates all of foundation, with a documented fallback to two deployables), and the category attribute-schema mechanism (shapes four surfaces at once). §Resource & Timeline Reality CANNOT be completed until OQ-20 lands.",
      "accepted_risks": [],
      "spikes": []
    },
    "foundation": {
      "status": "not-started",
      "last_updated": null,
      "owner": null,
      "backlog_source": ".forge/design/architecture.md → Foundation Backlog section",
      "review_completed": null,
      "review_audit_ref": null,
      "notes": "Blocked until architecture (Gate 2) passes. A 13-slice draft backlog (F-001..F-013) is already enumerated in .forge/design/architecture.md → Foundation Backlog; Gate 2 confirms or replaces it. This is the largest single block in the plan — the direct consequence of the polyglot-microservice decision — and all of it lands before the first user-visible feature. F-002 (gateway + one service per runtime, shared JWT validation, correlated logging, one-command local boot) gates everything else; if it overruns its time box, the two-deployable fallback triggers before feature work starts.",
      "slices": []
    },
    "decomposition": {
      "status": "not-started",
      "last_gate_run": null,
      "owner": null,
      "notes": "Blocked until PRD (Gate 1), architecture (Gate 2), and foundation (§4.10) all complete. Additionally blocked on OQ-01, OQ-02 and OQ-20 — two undecided large capabilities and the complete absence of any team size or delivery window. Nothing sized before those three land is trustworthy. A proposed slicing principle (vertical by journey step, all affected clients per slice) and its rejected alternatives are recorded in .forge/features.md for Gate 3 to accept or replace."
    },
    "technical_decisions": {
      "status": "in-progress",
      "owner": null,
      "notes": "10 locked decisions recorded in .claude/CLAUDE.md → \"Architecture Decisions (DO NOT REVERSE)\". 16 further engineering decisions are PROPOSED and awaiting gate confirmation — see .forge/discovery/docs/08-decision-log.md Part A. Do not promote a proposed row into CLAUDE.md until its gate confirms it."
    },
    "claude_md": {
      "status": "done",
      "owner": null,
      "notes": "Authored 2026-08-24 — project overview, stack (clients committed / backend proposed), the 10 locked decisions, reference map including the discovery pack and the three client repos, real command list with its caveats, and active context. Per-repo CLAUDE.md files and the '## Backend Stack' / '## Frontend Stack' profiles that the wave-mode implementer agents read on turn 1 are NOT yet authored in any repo — needed before the first wave-mode feature."
    },
    "environment": {
      "status": "not-started",
      "owner": null,
      "notes": "Client skeletons boot (npm workspaces at ../). Gaps: `advertising/` is not a git repository; no test framework in any workspace; `lint` is aliased to `tsc --noEmit` so no linter is enforced; no .env.example anywhere; no CI; no API client layer; mobile native projects not generated. No backend code exists. All of this lands in foundation (F-001, F-008, F-011)."
    },
    "feature_breakdown": {
      "status": "in-progress",
      "owner": null,
      "notes": "Produced by /forge-decompose (Gate 3). A PRE-GATE-3 HAND SEED of 42 provisional rows exists in .forge/features.md so early planning conversations have something concrete — IDs are not stable and no specs should be written against them. tracker `features:` below stays empty until Gate 3."
    }
  },
  "delivery": {
    "ship_unit": "wave",
    "current_phase": null,
    "phases": []
  },
  "features": {},
  "bugs": [],
  "release": {},
  "uat_issues": []
}
;
