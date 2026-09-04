# LankaListings — Design-Asset Inventory

> **Not a reference-system inventory.** LankaListings is greenfield — there is no legacy system to
> replicate. What exists instead is a **design asset set**: 17 Stitch screen exports, two design-system
> token files, and three partially-built app skeletons. This file classifies those assets so scope
> decisions are made against what we actually have, rather than against an assumption that "the designs
> are done".
>
> Assets live outside the harness at `../../../stitch_advertising/` and `../../../{frontend-web,
> management-portal,mobile}/`. Requirements derived from them are in
> [`docs/01-product-requirements.md`](docs/01-product-requirements.md); the UX reading is in
> [`docs/02-ux-scope.md`](docs/02-ux-scope.md).

## Classification key (adapted for a design-asset set)

| Classification | Meaning |
|---|---|
| **Build** | Design is sufficient. Port intent to the target stack as-is. |
| **Redesign** | An artefact exists but has a defect, a conflict, or a gap that must be resolved before build. |
| **Design** | Required by a requirement, but **no artefact exists**. Design work must be scheduled as work. |
| **Defer** | Artefact exists for a capability that is not in MVP scope (pending a Gate-1 decision). |
| **Discard** | Not needed. |

## Stitch screen exports

| # | Asset | Class | Notes |
|---|---|---|---|
| 1 | `visual_style_guide` | **Build** | Rendered token reference. Use as the design-system foundation acceptance target (F-006/F-007). |
| 2 | `home_desktop` + `home_mobile` | **Build** | Category grid with counts, featured rail. Both viewports covered. |
| 3 | `search_results_desktop` + `search_results_mobile` | **Build** | The richest export in the set — full filter rail, active-filter chips, sort, grid/list toggle, promoted cards. Directly sufficient for slices #21–#23. |
| 4 | `toyota_prius_s_touring_2016_details` + `toyota_prius_detail_mobile` | **Build** | Gallery, spec table, description, seller contact, `PROMOTED` ribbon, `LL-` reference. |
| 5 | `post_your_ad_category_selection_desktop` | **Build** | Wizard step 1. |
| 6 | `post_your_ad_ad_details_desktop` | **Redesign** | Carries the authoritative field constraints (title ≤70, description ≤4000, negotiable, Vehicles attribute set) — but its stepper (`… Photos → Preview → Publish`) **contradicts** the publish screen's (`… Photos → Price & Contact → Publish`), and it also holds a Pricing block that the other design moves to its own step. **OQ-03 must resolve which is correct.** |
| 7 | `post_your_ad_photos_location_mobile` | **Redesign** | Mobile-only. No desktop equivalent for the photos + location step, and no native camera/photo-library permission design for the mobile app. |
| 8 | `post_your_ad_contact_preview_desktop` | **Redesign** | A step-4 variant whose relationship to the two stepper versions is ambiguous. Same OQ-03. |
| 9 | `post_your_ad_final_step_desktop` | **Build** | Preview, T&C + Privacy gate, the 24-hour moderation promise, deferrable promotion upsell. Note the moderation copy is a **product commitment** (NFR-6), not decoration. |
| 10 | `my_account_desktop` + `my_account_mobile` | **Build** | Overview counters, status-tabbed My Ads, row actions. Source of the ad status vocabulary. |
| 11 | `admin_dashboard_overview` | **Build** | 4 KPI cards with trend, listings-by-category, regional distribution by province. |
| 12 | `advertisements_management_desktop` + `advertisements_management_mobile` | **Build** | Operator register with filters, flagged count, CSV export, operator ad creation. |
| 13 | `review_ad_admin_desktop` + `review_ad_admin_mobile` | **Defer (conditional)** | Fully designed **AI/OCR-assisted review**: source image, raw OCR text, per-field values with `High`/`Med` confidence and warning notes. A major capability that **no locked decision mentions** — pending **OQ-02**. If deferred, keep the field-level provenance model in the review UI so extraction can be switched on later without redesigning review; the plain approve/reject/edit review path is **Build** regardless. |

## Design-system token files

| # | Asset | Class | Notes |
|---|---|---|---|
| 14 | `lankalistings/DESIGN.md` (consumer) | **Redesign** | Complete, usable token set + component rules. Two defects: its **prose hexes contradict its own front-matter tokens** (D-15 resolves in favour of front-matter), and `frontend-web/tailwind.config.ts` currently carries a **lossy** translation that renames semantic roles to colour names (`navy`, `emerald`), discarding the role layer. |
| 15 | `lankalistings_operational_interface/DESIGN.md` (operator) | **Build** | Complete and internally consistent. Specifies data table, metric card, status chip, bulk toolbar, sidebar dimensions, and mandatory tabular numerals. **Never merge with #14** — the two assign different values to the same token names (D-16). |

## App skeletons

| # | Asset | Class | Notes |
|---|---|---|---|
| 16 | `frontend-web` (Next.js 14.2) | **Redesign** | Boots; one page rendering hard-coded fixtures from `src/lib/listings.ts` (including live Unsplash URLs). `lint` is aliased to `tsc --noEmit` — **no linter is actually enforced** despite ESLint being a devDependency. No tests, no API client, no `.env.example`. |
| 17 | `management-portal` (Vite 5.3) | **Redesign** | Boots; single `App.tsx` rendering mock metrics and a review queue from `src/lib/data.ts`. Same `lint` aliasing. Its Tailwind config has **not** been checked against the operational token set. |
| 18 | `mobile` (Expo ~51, RN 0.74.7) | **Redesign** | `App.tsx`, one `ListingCard`, `theme/tokens.ts`. Native projects not generated (`expo prebuild` not run). Token parity started but unverified. |
| 19 | Workspace root (`advertising/`) | **Redesign** | npm workspaces over the three clients. **Not a git repository** — no version history exists for any of this code. No CI. |
| 20 | Backend | **Design** | Nothing exists. Five services across two runtimes (doc 03 §3) plus a gateway, all greenfield. |

## Surfaces requiring design work — no artefact exists

Each is required by a requirement and has no Stitch export. This is the design debt that Gate-3 sizing
must count as work.

| # | Surface | Required by | Class |
|---|---|---|---|
| 21 | Sign-up / sign-in / Google OAuth / password reset | FR-1, FR-5, AC-1, AC-2 | **Design** |
| 22 | Email-verification prompt + confirmation | FR-3 | **Design** |
| 23 | Rejection reason as the seller sees it, and the revise path | R-3, AC-7 | **Design** |
| 24 | Promotion plan selection → checkout → payment result | FR-44–FR-48, AC-8 | **Design** — this is the **only revenue flow in the product** and it has no design at all |
| 25 | Saved Ads list | FR-28 | **Design** |
| 26 | Profile & verification | FR-4, FR-28 | **Design** |
| 27 | Report-an-ad intake | FR-35 | **Design** — the operator flagged queue exists with nothing feeding it |
| 28 | Admin: Users, Categories, Reports, Settings, Plans & Promotions | FR-39–FR-43 | **Design** — five sidebar destinations, no screens |
| 29 | Empty / loading / error states across all surfaces | NFR-3, doc 02 §3 | **Design** — only `Expired (0)` hints at an empty state |
| 30 | Mobile-native chrome: navigation, permissions, deep links, push | D-11 (mobile in MVP) | **Design** — the `*_mobile` exports are responsive web, not native app design |
| 31 | Messages / inquiry threads | FR-27 | **Defer (conditional)** — pending **OQ-01**. If deferred, the `Messages` nav item and the per-ad inquiry counter must be removed from #10, or they become dead affordances |

## Headline finding

**Roughly as many surfaces need designing as have been designed** — 13 screen groups exist, 11 are
missing. The two most consequential gaps are the entire **payment flow** (the product's only revenue
path) and the entire **authentication flow** (the first thing every user touches).

Two designed capabilities — **AI/OCR intake** and **messaging** — are not in any locked decision and are
each large. Both need an explicit Gate-1 in/out call (OQ-01, OQ-02); neither should be discovered
mid-delivery.
