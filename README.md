# LankaListings Platform

Product documentation, architecture, and design source for **LankaListings** — a Sri Lankan classified
advertising marketplace with Sinhala/English newspaper ingestion.

This repository holds no application code. It is the authoritative home for the requirements and plans that
the four application repositories implement.

## Repositories

| Repository | Stack | Role |
|---|---|---|
| [`lankalistings-platform`](https://github.com/malith-kavinda/lankalistings-platform) | Markdown | **This repo** — PRD, implementation plan, architecture, design exports |
| [`lankalistings-media-service`](https://github.com/malith-kavinda/lankalistings-media-service) | FastAPI, Python 3.12 | Image ingestion, Sinhala OCR, LLM extraction, provenance |
| [`lankalistings-portal`](https://github.com/malith-kavinda/lankalistings-portal) | Vite + React | Operator portal: bulk intake and human review |
| [`lankalistings-web`](https://github.com/malith-kavinda/lankalistings-web) | Next.js 14 | Public marketplace |
| [`lankalistings-mobile`](https://github.com/malith-kavinda/lankalistings-mobile) | Expo React Native | Public mobile app |

Each application repository is installed and run independently. They were previously npm workspaces in a
single tree; that coupling no longer exists, so each has its own `package-lock.json` and its own setup
instructions.

## Documents

| Document | Purpose |
|---|---|
| [`docs/product/ocr-ad-ingestion-prd.md`](docs/product/ocr-ad-ingestion-prd.md) | **What** the newspaper ingestion capability must do — requirements, invariants, acceptance criteria |
| [`docs/product/ocr-ad-ingestion-implementation-plan.md`](docs/product/ocr-ad-ingestion-implementation-plan.md) | **How** it is built — phase-by-phase execution plan with schema, provider design, and verification |
| [`docs/architecture.md`](docs/architecture.md) | Platform architecture blueprint and service boundaries |
| `lankalistings-harness/.forge/discovery/docs/` | Original discovery pack: product requirements, UX scope, data model, API contract, decision log |
| `stitch_advertising/` | Stitch UI/UX exports for public, mobile, and operator surfaces |

## The core product invariant

> Only an `active` advertisement is publicly readable, and no machine-generated advertisement becomes
> `active` without a human moderator approving it.

OCR and LLM output are treated as untrusted input throughout. The pipeline produces *candidates*; people
produce *listings*.

## Current work

Newspaper batch ingestion — upload many scans, extract zero-to-many independent advertisements per image
with Sinhala + English OCR and an LLM, and route every candidate through human review.

Both the OCR engine and the LLM provider are selectable by environment variable so they can be swapped
without touching pipeline logic. See the implementation plan for the phase breakdown and the current status
of each phase.
