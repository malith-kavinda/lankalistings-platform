# 02 — UX Scope

> Reconstructed 2026-08-24. Provenance tags per `README.md`.
> Primary evidence: the 17 Stitch exports under `stitch_advertising/`, and the two `DESIGN.md` token sets.

## 1. Two design systems, deliberately different

The Stitch exports carry **two** distinct design systems, and the split is intentional — a consumer
marketplace and an operator console have opposite priorities. Do not unify them.

| | Consumer (`lankalistings/DESIGN.md`) | Operational (`lankalistings_operational_interface/DESIGN.md`) |
|---|---|---|
| Applies to | `frontend-web`, `mobile` | `management-portal` |
| Direction | Corporate Modernism — "effortless efficiency", content is the hero | Functional minimalism — "objective clarity", data is the hero |
| Base radius | `0.5rem` / 8px | `0.25rem` / 4px |
| Type | Manrope headings + Inter small labels | Manrope throughout, **tabular numerals mandatory in tables and metric cards** |
| Secondary colour | Emerald `#006c49` (primary action) | Slate `#515f74` (subordinate metadata) |
| Density | Generous whitespace, 40px section rhythm | Compact — fixed 48px table rows, 24px container padding |
| Depth | Level 1 = 1px border, no shadow; shadow only on hover/modal | Same discipline; active state uses a left-accent border, never elevation |
| Layout | Fluid grid, 1280px max container | Fixed-fluid: 260px sidebar (72px collapsed) + fluid content |

**Shared discipline across both:** no heavy shadows, no skeuomorphism, 4px baseline spacing grid,
depth via tonal layering and low-contrast outlines (`#E2E8F0`-class borders) rather than elevation.

## 2. Token hand-off status

`frontend-web/tailwind.config.ts` already carries a **partial** translation of the consumer token set —
the surface ramp, `navy`, `emerald`, `mint`, `amber`, `danger`, the Manrope/Inter font stack, radii, and
a `maxWidth.content: 1280px`. `[DERIVED]`

Two gaps to close in the design-system foundation slice:

1. **The translation is lossy.** `DESIGN.md` defines the full Material-style role set (`primary`,
   `on-primary`, `primary-container`, `on-primary-container`, the `*-fixed` variants, `error-container`,
   `inverse-*`, `outline-variant`, …). The Tailwind config keeps roughly a third of it and renames some
   roles to literal colour names (`navy`, `emerald`). Renaming role tokens to colour names loses the
   semantic layer that makes a dark mode or a rebrand mechanical.
2. **`management-portal/tailwind.config.ts` has not been checked against the operational token set at
   all**, and the two systems have *different* values for the same token names (e.g. `secondary` is
   `#006c49` consumer vs `#515f74` operational; base radius 8px vs 4px). Sharing one token file across
   both apps would silently corrupt both.

**Prose-vs-token conflict to resolve at Gate 2.** The consumer `DESIGN.md` prose describes
"Deep Navy" as the anchor and quotes hexes (`#FFFFFF`, `#F8FAFC`, `#E2E8F0`, `#0F172A`, `#10B981`,
`#F59E0B`, `#EF4444`) that **do not match its own front-matter token values** (`primary: #000000`,
`surface: #f7f9fb`, `secondary: #006c49`, `tertiary-fixed-dim: #f9bd22`, `error: #ba1a1a`). The
front-matter is machine-readable and the Stitch screens compile from it, so **treat the front-matter as
authoritative and the prose hexes as illustrative.** `[PROPOSED]`

## 3. Screen inventory

17 Stitch screens exist. Coverage is uneven by design — the desktop consumer flow and the admin console
are well covered; several journeys have no screen at all.

### Consumer — public web and mobile

| Screen | Export | Viewport(s) | Notes |
|---|---|---|---|
| Home | `home_desktop`, `home_mobile` | both | Category grid with counts, featured rail |
| Search results | `search_results_desktop`, `search_results_mobile` | both | Filter rail, active-filter chips, sort, grid/list toggle |
| Ad detail | `toyota_prius_s_touring_2016_details`, `toyota_prius_detail_mobile` | both | Gallery `1 / 12`, spec table, description, seller contact, `PROMOTED` ribbon |
| Post ad — category select | `post_your_ad_category_selection_desktop` | desktop only | Step 1 |
| Post ad — details | `post_your_ad_ad_details_desktop` | desktop only | Step 2; carries the field constraints in FR-8/FR-9/FR-10 |
| Post ad — photos + location | `post_your_ad_photos_location_mobile` | **mobile only** | Step 3 |
| Post ad — contact preview | `post_your_ad_contact_preview_desktop` | desktop only | Step 4 variant |
| Post ad — publish | `post_your_ad_final_step_desktop` | desktop only | Step 5; T&C gate, moderation notice, promotion upsell |
| My account | `my_account_desktop`, `my_account_mobile` | both | Overview counters, tabbed My Ads, row actions |
| Visual style guide | `visual_style_guide` | — | Rendered token reference |

### Operator — management portal

| Screen | Export | Notes |
|---|---|---|
| Dashboard overview | `admin_dashboard_overview` | 4 KPI cards with trend, listings-by-category, regional distribution by province |
| Advertisements register | `advertisements_management_desktop`, `advertisements_management_mobile` | Filters, flagged count, CSV export, operator ad creation |
| Ad review | `review_ad_admin_desktop`, `review_ad_admin_mobile` | Source image + raw OCR + AI-extracted fields with confidence |

### Screens that do not exist and are needed

`[DERIVED]` by absence — every item below is required by a requirement in
[01-product-requirements.md](01-product-requirements.md) but has no design artefact.

| Missing surface | Required by | Consequence if not designed |
|---|---|---|
| Sign-up / sign-in / Google OAuth / password reset | FR-1, FR-5 | The first screen every user sees is undesigned |
| Email-verification prompt and confirmation | FR-3 | — |
| Rejection reason, as the seller sees it | R-3, AC-7 | Seller has no path to fix a rejected ad |
| Promotion plan selection + checkout + payment result | FR-44…FR-48, AC-8 | The **only revenue flow in the product** has no design |
| Messages / inquiry thread | FR-27 | Blocked on the messaging in/out decision |
| Saved ads list | FR-28 | Nav item exists, destination does not |
| Profile & verification | FR-4, FR-28 | Verified-seller journey undesigned |
| Report-an-ad intake | FR-35 | Operator queue exists with nothing feeding it |
| Admin: Users, Categories, Reports, Settings, Plans & Promotions | FR-39…FR-43 | Four sidebar destinations with no screens |
| Empty, loading, and error states across all surfaces | NFR-3 | Only `Expired (0)` hints at an empty state |
| Mobile-app-specific chrome (native nav, permissions, deep links) | mobile in scope | The `*_mobile` exports are responsive web, not native app design |

**Design-debt total: roughly as many screens missing as exist.** Gate 3 decomposition must not assume
UI is a thin layer over ready designs.

## 4. Responsive behaviour

### Consumer `[DERIVED]` — consumer `DESIGN.md`

| Breakpoint | Grid | Margins | Notes |
|---|---|---|---|
| ≤767px | 4-col | 16px | Fixed bottom nav, 5 slots, blurred background ("glassmorphism lite"), 24px icons, centre `Post Ad` slot in Emerald |
| 768–1023px | 8-col | 24px | — |
| ≥1024px | 12-col, 20px gutters | 32px | Centred, 1280px max container |

Type scales down on mobile: top-level headlines drop ~25% (`headline-lg` 32/40 → `headline-lg-mobile`
24/32).

### Operator `[DERIVED]` — operational `DESIGN.md`

| Breakpoint | Behaviour |
|---|---|
| ≥1440px | Full multi-column dashboard |
| 1024–1439px | Sidebar stays expanded (260px), content fluid |
| <1024px | Sidebar auto-collapses to 72px; tables scroll horizontally |

### Mobile app

The `*_mobile` exports are **responsive-web layouts, not native designs.** `mobile/src/theme/tokens.ts`
exists in the skeleton, so token parity is started, but native navigation, platform permission prompts
(camera/photo library for FR-11), deep linking into an ad, and push notification surfaces are entirely
undesigned. `[DERIVED]`

## 5. Component contract (foundation-slice scope)

The design systems specify these concretely enough to build as shared primitives before feature work.

**Consumer:**
- Buttons — Primary (Emerald fill, white text), Secondary (Deep Navy fill), Outline (1px border, Navy
  text). `Post Ad` is pill-shaped for prominence; all others 8px radius.
- Inputs — 1px border, 8px radius; **focus = Emerald border + 2px outer glow**.
- Ad card — white, 1px border, 8px radius; thumbnail matches card radius; metadata row at the bottom in
  `metadata` type with a leading icon (map-pin, clock).
- Chips — Light-Grey fill, Navy text, used for categories and active filters.
- Price — always `price-xl` at weight 800; `Rs.` prefix; mandatory thousands separators.
- Category icons — line art, consistent 1.5px stroke.
- Loading — skeleton pulses that mirror the card layout.
- Mobile bottom nav — fixed, blurred, 5 slots.

**Operator:**
- Data table — sticky headers, zebra striping **on hover only**, fixed-width status and action columns,
  inline quick actions revealed on row hover, fixed 48px row height.
- Metric card — large `data-mono` value, percentage trend indicator (Emerald up / Red down), 2px-stroke
  sparkline.
- Status chip — pill; Approved = Emerald @10% fill + Emerald text; Pending = Amber @10% + Amber text;
  Rejected = Red @10% + Red text.
- Bulk action toolbar — slides in from the bottom on row selection; Deep Navy fill, white content.
- Search — leading Slate icon plus a `Cmd/Ctrl + K` shortcut hint.
- Sidebar — collapsible 260px ↔ 72px; active item marked by a left accent border, never elevation.

## 6. Semantic-colour contract

Both systems assign colour meaning, not decoration. This mapping is a cross-cutting acceptance rule, not
a per-feature choice. `[DERIVED]`

| Meaning | Consumer | Operator |
|---|---|---|
| Primary action / active / success | Emerald | Emerald |
| Pending / needs attention / premium highlight | Warm Yellow / Amber | Amber |
| Flagged / destructive / error | `error #ba1a1a` | Red |
| Structural chrome, navigation | Deep Navy | Deep Navy |
| Subordinate metadata, inactive | `on-surface-variant` | Slate |

## 7. Stitch hand-off rules

1. **Stitch exports are visual specifications, not shippable code.** Each `code.html` is a single-file
   Tailwind CDN page with an inlined config and Material Symbols icon names. Port intent — layout,
   spacing, hierarchy, state, copy — not markup.
2. **Front-matter tokens beat prose hexes and beat the exports' inlined configs** where they disagree
   (§2).
3. **Two token files, never one.** Consumer tokens serve `frontend-web` + `mobile`; operational tokens
   serve `management-portal`.
4. **The exports' content is placeholder data**, including the Unsplash image URLs already committed in
   `frontend-web/src/lib/listings.ts` and the mock arrays in `management-portal/src/lib/data.ts`. Every
   one of those is a real-API replacement site, and each should be treated as a known removal in the
   relevant feature's definition of done.
5. **Icons:** exports reference Material Symbols; the skeletons already depend on `lucide-react`.
   Pick one and record it — mixed icon sets break the 1.5px stroke-weight rule the consumer system sets.
   `[PROPOSED]` — standardise on `lucide-react`, since it is already a committed dependency in both web
   apps, and map the Material Symbols names used in the exports to Lucide equivalents once, centrally.
6. **Copy in the exports is product copy** and some of it is a commitment — most notably the 24-hour
   moderation promise (NFR-6) and the T&C/Privacy gate (FR-14). Do not paraphrase it away without a
   product decision.

## 8. Accessibility scope

`[PROPOSED]` — WCAG 2.1 AA, verified per-surface rather than at the end:

- Semantic landmarks and heading order on every page; the exports use generic containers throughout and
  will not produce this by default.
- Keyboard operability for the filter rail, the wizard stepper, the data tables' inline row actions, and
  the bulk-action toolbar — all are hover-revealed or pointer-first in the exports.
- Visible focus states everywhere. The consumer system's Emerald focus glow is specified; the operator
  system's focus border is specified; neither export renders them.
- Contrast verification on the @10%-opacity status chips and on `metadata`-size 12px text — the two most
  likely AA failures in the current palettes.
- Reduced-motion honoured by the skeleton pulses and the slide-in bulk toolbar.
- An automated scan on every page visited during E2E, per [06-delivery-quality.md](06-delivery-quality.md).
