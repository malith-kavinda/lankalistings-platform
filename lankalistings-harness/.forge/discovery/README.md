# Forge Discovery

> The structured location for raw project inputs that will eventually become specs.

---

## 📍 LankaListings — where this project's inputs actually are

Discovery for this engagement is **complete**. Start here, in this order:

| Read | What it is |
|---|---|
| **[`docs/README.md`](docs/README.md)** | **Start here.** Index of the 8-document engineering pack, plus the provenance convention: every material statement is tagged `[LOCKED]` (a real decision), `[DERIVED]` (read off a real artefact, cited inline), or `[PROPOSED]` (an engineering proposal filling a gap). **The distinction is load-bearing — do not treat a `[PROPOSED]` line as settled.** |
| [`docs/01-product-requirements.md`](docs/01-product-requirements.md) | Outcomes, roles, ad lifecycle, FR-1…FR-48, NFRs, acceptance criteria |
| [`docs/02-ux-scope.md`](docs/02-ux-scope.md) | Two design systems, screen inventory, responsive behaviour, Stitch hand-off rules |
| [`docs/03-architecture.md`](docs/03-architecture.md) | Service boundaries, the polyglot split, cross-cutting concerns, high-risk requirements |
| [`docs/04-data-model.md`](docs/04-data-model.md) | Entities by owning service, status machines, index plan, retention |
| [`docs/05-api-contract.md`](docs/05-api-contract.md) | Envelope, error contract, money/date/enum conventions, the full resource surface |
| [`docs/06-delivery-quality.md`](docs/06-delivery-quality.md) | Milestones, test tiers, definition of done, release gates |
| [`docs/07-harness-backlog.md`](docs/07-harness-backlog.md) | 13 foundation slices + 42 feature slices with a definition of done each |
| [`docs/08-decision-log.md`](docs/08-decision-log.md) | 30 confirmed/proposed decisions + all 34 open questions with their blast radius |
| [`feature-inventory.md`](feature-inventory.md) | Design-asset inventory — what is designed, what needs redesigning, and the ~11 surfaces with **no design at all** |
| [`flows/`](flows/) | Seller post-to-live, and the featuring-payment revenue flow |

**Why the pack was reconstructed.** The original engineering pack at `../../../discovery/README.md`
published a document map of eight documents, but **only its index was ever written** — the seven
substantive documents did not exist on disk anywhere. They were rebuilt on 2026-08-24 from the artefacts
that *do* exist (the locked-decision table, two `DESIGN.md` token sets, 17 Stitch screen exports, three
app skeletons) plus a product-owner scoping conversation. That original index remains the authority for
the seven locked MVP product decisions and the locked build order.

**Inputs that live outside this harness** (referenced, not copied, so there is one source of truth):

- `../../../stitch_advertising/` — 17 screen exports (`code.html` + `screen.png`) and the two `DESIGN.md`
  token sets. `screenshots/` in this folder is deliberately empty for that reason.
- `../../../frontend-web/`, `../../../management-portal/`, `../../../mobile/` — the three client skeletons.

**The three open questions to answer first** — each changes the shape of the plan rather than a detail
within it: **OQ-01** (is in-app messaging in scope?), **OQ-02** (is AI/OCR ad intake in scope?),
**OQ-20** (team size and delivery window). All 34 are tracked live in
[`../project-prd-signals.md`](../project-prd-signals.md).

---

## What "Discovery" Means in Forge

Discovery is the **first phase** of the Forge workflow for new projects. It exists because the standard workflow (Spec → Plan → Implement → ...) assumes you already have enough understanding to write a spec. For a brand-new project — or one being rebuilt from a reference system — that assumption does not yet hold.

Discovery is where raw inputs live before they get structured into specs:

- What the reference system does (and how), if rebuilding
- Client conversations and verbal decisions
- Mockups and visual references
- Documented user flows
- Open questions and uncertainties

The output of discovery feeds the **project PRD** (`.forge/project-prd.md`), which is then verified by Gate 1 (`/forge-prd-check`) before the team commits to delivering against it.

## What Discovery Is Not

- **Not exhaustive** — document enough to scope v1 and write the first 2-3 specs. The rest emerges as work proceeds.
- **Not a spec** — discovery captures observations, not requirements. Specs come later.
- **Not a wiki** — keep it focused on inputs that drive scoping decisions.
- **Not a one-time activity** — discovery continues throughout the project as new questions emerge.

## Folder Structure

| Folder / File | Purpose |
|---------------|---------|
| `feature-inventory.md` | What the reference system does (if any), classified as Replicate / Redesign / Defer / Discard |
| `screenshots/` | Raw captures of the reference system, mockups, design references |
| `flows/` | Documented user flows (markdown + linked images) |
| `meeting-notes/` | Client meeting captures, verbal decisions, things said in passing |

## Reference-System Classification (When Rebuilding)

If the project is being built from a reference system, every behavior in it should be classified in `feature-inventory.md`:

| Classification | Meaning |
|---------------|---------|
| **Replicate** | Same behavior, new stack |
| **Redesign** | Behavior changes from reference (UX issues, new requirements) |
| **Defer** | Not in v1 scope |
| **Discard** | Not needed |

This classification is the input to the project brief's scope decisions. Without it, the team discovers mid-implementation that they never decided whether a behavior should be replicated or redesigned.

For greenfield projects with no reference system, skip the feature inventory and use the other discovery folders for mockups, meeting notes, and user flows.

## How to Work Here

1. **Capture aggressively** — when you see something on the reference system or hear something in a meeting, drop it here immediately. Better to over-capture than lose context.
2. **Classify the inventory** — every reference-system behavior should land in one of the four classifications above.
3. **Link, do not duplicate** — flows reference screenshots, meeting notes reference flows. Cross-link rather than copy-paste.
4. **Date meeting notes** — filename format: `YYYY-MM-DD-<topic>.md`
5. **Promote findings** — when a discovery item becomes settled, move it where it belongs:
   - Scope decisions → `.forge/project-prd.md`
   - Settled functional requirements → `.forge/specs/`
   - Architecture decisions (the "why") → `.claude/CLAUDE.md`
   - System architecture (the "what") → `.forge/design/architecture.md`
   - Data model sketches → backend repo's `docs/data-model.md` (create the repo early if needed)
   - Style ideas / design tokens → frontend repo's `docs/style-spec.md` (create the repo early if needed)

   Discovery is the staging area, not the final home.

## When Discovery Is "Done Enough"

Discovery is done enough for v1 when:

- The feature inventory has every major reference-system behavior classified (if applicable)
- The project brief can be written with confidence
- The first 2-3 foundational features can be specified
- Open questions are documented (even if not yet answered)

It is **not** done when:

- Every screen has been documented (overkill)
- Every edge case has been captured (impossible)
- The team feels "ready" (this never happens)

The bias is toward **moving forward with gaps documented**, not toward exhaustive upfront capture. The Forge workflow handles unknowns through revisions, not through perfect initial discovery.
