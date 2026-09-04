# LankaListings — Harness Engineering Pack

**Product:** Sri Lankan responsive classified-advertising marketplace  
**Public application:** Next.js  
**Management portal:** Vite + React  
**API:** FastAPI  
**Status:** MVP definition, 24 August 2026

## Product decisions locked for MVP

| Decision | MVP rule |
|---|---|
| Marketplace model | Any user may create an advertisement. |
| Categories | Broad classifieds: vehicles, property, land, jobs, electronics, services, home & garden, fashion, and other. |
| Publication | An advertisement is public only after admin approval. |
| Revenue | Standard publication is free. A seller pays only to feature an approved ad. |
| Authentication | Google OAuth plus email/password accounts. |
| Market | Sri Lanka; prices in LKR; location hierarchy is Province → District → City. |
| Initial UI language | English. Sinhala and Tamil are future work unless added to the MVP scope. |

## Document map

> **The eight documents below were written on 2026-08-24 into the Forge harness, not into this folder.**
> Only this index had ever been authored; documents 01–08 did not exist. They were reconstructed from the
> artefacts that do exist — the locked-decision table above, the two `DESIGN.md` token sets, the 17 Stitch
> screen exports, and the three app skeletons — plus a product-owner scoping conversation.
>
> **They now live at [`../lankalistings-harness/.forge/discovery/docs/`](../lankalistings-harness/.forge/discovery/docs/README.md)**,
> which is Forge's designated home for raw project inputs and keeps the harness self-contained and
> committable. Read that folder's `README.md` first: every material statement in the pack is tagged
> `[LOCKED]` / `[DERIVED]` / `[PROPOSED]`, and the distinction matters.
>
> The links below are the original titles, retargeted to their real locations.

1. [Product requirements](../lankalistings-harness/.forge/discovery/docs/01-product-requirements.md) — outcomes, roles, journeys, rules and acceptance criteria.
2. [UX scope](../lankalistings-harness/.forge/discovery/docs/02-ux-scope.md) — screens, responsive behaviour and Stitch hand-off.
3. [Architecture](../lankalistings-harness/.forge/discovery/docs/03-architecture.md) — system boundaries, components, security and deployment shape.
4. [Data model](../lankalistings-harness/.forge/discovery/docs/04-data-model.md) — entities, statuses, ownership and indexes.
5. [API contract](../lankalistings-harness/.forge/discovery/docs/05-api-contract.md) — REST resources, request/response expectations and error contract.
6. [Delivery and quality plan](../lankalistings-harness/.forge/discovery/docs/06-delivery-quality.md) — milestones, test strategy, observability and release gates.
7. [Harness backlog](../lankalistings-harness/.forge/discovery/docs/07-harness-backlog.md) — thin vertical slices with definition of done.
8. [Decision log](../lankalistings-harness/.forge/discovery/docs/08-decision-log.md) — confirmed choices and open decisions.

## How to use this pack in a harness

Treat every backlog item as a small, independently reviewable change. Before implementation, copy its acceptance criteria into the task brief. A change is not complete until its automated tests, accessibility checks, API contract checks, and relevant observability are included.

Build in this order: platform foundation → accounts → ad creation/moderation → public discovery → featured-payment flow → hardening. Do not build payment capture before an approved ad can be promoted.
