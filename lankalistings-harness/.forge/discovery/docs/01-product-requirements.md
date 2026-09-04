# 01 — Product Requirements

> Reconstructed 2026-08-24. Provenance tags per `README.md`.
> Downstream: this document is the primary input to `.forge/project-prd.md`.

## 1. Product outcome

LankaListings is a Sri Lankan general classifieds marketplace. Any registered user can list an item
for sale; every listing is human-moderated before it becomes publicly visible; standard publication is
free and the seller pays only to *feature* an already-approved ad. `[LOCKED]`

The product succeeds when a seller can go from "I have something to sell" to "my ad is live and buyers
are contacting me" without assistance, and when a buyer can find relevant local listings by category,
location and price without wading through spam. Moderation is the quality mechanism that makes the
second half of that sentence true, which is why it is a first-class product surface and not an
afterthought.

## 2. Locked MVP decisions

Restated in substance from the original pack index. These are the constraints every requirement below
must respect. `[LOCKED]`

| Decision | MVP rule |
|---|---|
| Marketplace model | Any user may create an advertisement. |
| Categories | Broad classifieds: vehicles, property, land, jobs, electronics, services, home & garden, fashion, and other. |
| Publication | An advertisement is public only after admin approval. |
| Revenue | Standard publication is free. A seller pays only to feature an approved ad. |
| Authentication | Google OAuth plus email/password accounts. |
| Market | Sri Lanka; prices in LKR; location hierarchy is Province → District → City. |
| Initial UI language | English. Sinhala and Tamil are future work unless added to the MVP scope. |

Added in the 2026-08-24 scoping conversation: `[LOCKED]`

| Decision | MVP rule |
|---|---|
| Client surfaces | Three: responsive public web (Next.js), management portal (Vite + React), and a mobile app (Expo React Native, Android + iOS). |
| Backend shape | Microservices. Both Spring Boot and FastAPI are used; FastAPI serves the management portal's CRUD surface. |

## 3. Roles and access

| Role | Description | Primary capabilities |
|------|-------------|----------------------|
| **Visitor** (unauthenticated) | Anyone browsing the public marketplace. | Browse categories, search and filter, view an approved ad, view seller contact per §6.4, begin sign-up. `[DERIVED]` — the Stitch public screens render a `SIGN IN` affordance, so browse and detail are reachable unauthenticated. |
| **Member** (authenticated) | A single account type that both sells and buys. There is no separate seller registration. | Everything a Visitor can do, plus: create/edit/delete own ads, save favourites, send and receive inquiries, view own ad performance, purchase featuring for an approved own ad, manage profile. `[DERIVED]` — `my_account_desktop` shows My Ads / Saved Ads / Messages / Profile & Verification / Settings under one identity. |
| **Moderator** | Operational staff who clear the moderation queue. | Review pending ads, approve, reject with reason, edit submitted fields before approval, action reported ads. `[DERIVED]` — `review_ad_admin_desktop`. |
| **Super Admin** | Full operator of the management portal. | Everything a Moderator can do, plus user administration, category taxonomy, promotion plans, reports, system settings. `[DERIVED]` — the admin sidebar is Dashboard / Advertisements / Moderation Queue / Users / Categories / Reports / Plans & Promotions / Settings, and the header renders "Super Administrator". |

**Open:** whether Moderator and Super Admin are the only operator roles, or whether finer roles
(content admin, finance admin) are needed. `[PROPOSED]` — start with exactly two and add a role only
when a real permission conflict appears.

## 4. Domain objects the requirements assume

Full modelling is in [04-data-model.md](04-data-model.md). The requirements below assume:

- An **Advertisement** owned by exactly one Member, filed under exactly one Category, located at
  exactly one City (which resolves to a District and Province), priced in LKR, carrying a set of
  category-specific attributes and an ordered set of photos.
- A **moderation decision** attached to each publication attempt.
- A **featuring purchase** attached to an already-approved Advertisement.

## 5. Advertisement lifecycle

The status vocabulary is read directly off the seller's My Ads tab strip and the admin status filters:
`Draft`, `Pending`, `Active`, `Rejected`, `Expired`, `Sold`. `[DERIVED]` — `my_account_desktop` tabs
read `All (14) / Active (12) / Pending (2) / Rejected / Expired (0) / Sold (5) / Drafts (1)`;
`advertisements_management_desktop` filters read `All Statuses / Active / Pending / Rejected`.

```
                 ┌──────────── seller edits ─────────────┐
                 ▼                                       │
 (create) ──> DRAFT ──submit──> PENDING ──approve──> ACTIVE ──sold──> SOLD
                                  │                    │
                                  │ reject             │ ttl elapses
                                  ▼                    ▼
                              REJECTED              EXPIRED
                                  │                    │
                                  └── seller revises ──┴──> PENDING
```

Rules:

- **R-1** A newly submitted ad enters `PENDING`. It is not publicly readable in any surface while
  `PENDING`. `[LOCKED]` — "public only after admin approval".
- **R-2** Only an `ACTIVE` ad is publicly readable, searchable, and eligible for featuring. `[LOCKED]`
- **R-3** Rejection carries a reason visible to the owning seller. `[PROPOSED]` — the screens show a
  `Rejected` tab for the seller but no reason surface; rejection without a reason guarantees a support
  ticket.
- **R-4** An edit to an `ACTIVE` ad returns it to `PENDING` if it touches a moderated field (title,
  description, price, photos, category, location); it stays `ACTIVE` for non-moderated fields.
  `[PROPOSED]` — the alternative (edits go live immediately) reopens the spam hole moderation exists to
  close. The exact moderated-field set is open.
- **R-5** An ad expires after a fixed live duration and moves to `EXPIRED`, from which the seller may
  relist. `[PROPOSED]` — `Expired (0)` exists as a seller tab so expiry is intended; the duration is
  unspecified. Open.
- **R-6** `SOLD` is a seller-initiated terminal state. `[DERIVED]` — the My Ads row menu offers
  `Mark as Sold`.
- **R-7** Featuring never bypasses moderation. Payment is only offered against an `ACTIVE` ad.
  `[LOCKED]` — restated from the pack's build-order instruction: "Do not build payment capture before an
  approved ad can be promoted."

## 6. Functional requirements

### 6.1 Accounts and authentication

- **FR-1** A visitor can register with email + password, or with Google OAuth. `[LOCKED]`
- **FR-2** Both methods resolve to one account identity; signing in with Google against an existing
  email-registered address links rather than duplicates. `[PROPOSED]` — unspecified, and the
  duplicate-account failure mode is expensive to unwind later.
- **FR-3** Email addresses are verified before an account may publish an ad. `[PROPOSED]` — moderation
  catches bad content but not disposable identities.
- **FR-4** A member has a "Verified Seller" state, displayed as a badge on the account surface and on ad
  cards. `[DERIVED]` — `my_account_desktop` renders `verified / Verified Seller`; `search_results_desktop`
  offers a `Verified Sellers Only` filter and a per-card `verified` marker. **What earns the badge is
  unspecified.** Open — phone verification is the obvious candidate, since the detail screen renders
  `077 123 4567 (Verified)` against the contact number.
- **FR-5** Password reset by emailed token. `[PROPOSED]` — table stakes, absent from inputs.

### 6.2 Posting an advertisement

- **FR-6** Ad creation is a five-step wizard. `[DERIVED]` — the `post_your_ad_*` screens render a
  numbered stepper.

  **The two Stitch stepper variants disagree and this must be resolved at Gate 1:**
  `post_your_ad_ad_details_desktop` shows `Category → Details → Photos → Preview → Publish`, while
  `post_your_ad_final_step_desktop` shows `Category → Details → Photos → Price & Contact → Publish`.
  The second appears later in the flow (it renders "Step 5 of 5" with all prior steps checked) and moves
  pricing out of Details into its own step — but `post_your_ad_ad_details_desktop` also carries a
  `Pricing` block with `Price (Rs) *` and a `Negotiable` toggle. One of the two is stale.

- **FR-7** Step 1 selects a category from the nine locked top-level categories, then a subcategory.
  `[DERIVED]` — the ad detail breadcrumb reads `Home > Vehicles > Cars > Toyota`, implying at least
  category → subcategory, with make/brand carried as an attribute rather than a taxonomy level.
- **FR-8** Step 2 collects, for every category: ad title (required, **max 70 characters**, live
  counter), condition (`Brand New` / `Used`; `Reconditioned` also appears as a search facet), and a
  detailed description (required, **max 4000 characters**, live counter). `[DERIVED]` — these field
  attributes are literal in `post_your_ad_ad_details_desktop`.
- **FR-9** Step 2 additionally collects a **category-specific attribute set**. For Vehicles the observed
  set is Make, Model, Year of Manufacture, Mileage (km), Transmission (`Automatic`/`Manual`/`Tiptronic`),
  Fuel Type (`Hybrid`/`Petrol`/`Diesel`/`Electric`); the detail page additionally renders Engine
  Capacity and Registration. `[DERIVED]`. **The attribute sets for the other eight categories are not
  specified anywhere in the inputs — this is the single largest content gap in the pack.** Open.
- **FR-10** Pricing collects a LKR amount and an optional `Negotiable` flag ("I'm open to offers").
  `[DERIVED]`
- **FR-11** Photos: multiple images per ad, ordered, with one designated main photo. `[DERIVED]` — the
  detail gallery reads `1 / 12` and `+8 photos`; the publish preview labels a `Main Photo` and shows `+3`.
  Minimum/maximum count, per-file size cap and accepted formats are unspecified. Open.
- **FR-12** Location is captured as Province → District → City. `[LOCKED]`
- **FR-13** The wizard supports `Save as Draft` at any step, and `Save as Draft & Exit` from the final
  step. `[DERIVED]`
- **FR-14** The final step renders a full preview of the ad as buyers will see it, requires explicit
  acceptance of Terms of Service and Privacy Policy, and states the moderation expectation before
  submission. `[DERIVED]` — the screen's own copy: *"Your ad will be reviewed by our team to ensure it
  meets our quality guidelines. It will typically be live within 24 hours."*
- **FR-15** The final step offers featuring as a **deferrable** upsell, not a blocking step: *"You can
  add promotions later from your dashboard."* `[DERIVED]` — consistent with R-7.

### 6.3 Discovery — browse, search, filter

- **FR-16** A category-led home surface with per-category ad counts and a featured-ads rail. `[DERIVED]`
  — `home_desktop`, plus `frontend-web/src/lib/listings.ts`, which already hard-codes a `categories`
  array with counts and a `featuredListings` array with `Verified` / `Premium` / `Urgent` badges.
- **FR-17** Free-text search scoped by category and location from the header. `[DERIVED]` — the
  search-results header renders a three-part control: query, `category` select, `location_on` select.
- **FR-18** A filter rail supporting Category, Location, Price Range (LKR), Condition
  (`New`/`Used`/`Reconditioned`), a category-specific block (for Vehicles: Make, Model, Transmission),
  and a `Verified Sellers Only` toggle — with `Clear All` and individually dismissible active-filter
  chips. `[DERIVED]` — all literal from `search_results_desktop`.
- **FR-19** Sort by `Newest First`, `Price: Low to High`, `Price: High to Low`. `[DERIVED]`
- **FR-20** Grid and list view toggle on results. `[DERIVED]` — `grid_view` / `view_list`.
- **FR-21** Result count is shown ("Showing 1,245 ads matching your criteria") and results are paginated
  or incrementally loaded. `[DERIVED]` for the count; the mechanism is unspecified. `[PROPOSED]` —
  cursor pagination, since an offset scan over a growing corpus degrades and the mobile surface wants
  append-style loading.
- **FR-22** Featured ads are visually distinguished in results and rank above non-featured ads within
  the same result set. `[DERIVED]` — result cards carry a `Promoted` badge, the detail page a `PROMOTED`
  ribbon, and the publish screen's copy states featuring makes an ad *"appear at the top of search
  results"*. The exact interleave (all featured first vs. a capped featured allocation per page) is
  unspecified. Open.

### 6.4 Advertisement detail

- **FR-23** The detail page renders photo gallery with count, title, LKR price, location, posted-at
  relative time, a human-readable reference ID, the category-specific specification table, the full
  description, and seller contact. `[DERIVED]` — `toyota_prius_s_touring_2016_details`.
- **FR-24** Reference IDs are human-quotable and formatted `LL-NNNNN`. `[DERIVED]` — `Ref ID: LL-49210`
  on the detail page, `LL-48291` in the admin table. This is a user-facing identifier distinct from the
  internal primary key.
- **FR-25** Save-to-favourites and share actions on the detail page. `[DERIVED]`
- **FR-26** Seller phone number is displayed with a verification marker. `[DERIVED]` —
  `077 123 4567 (Verified)`. Whether the number is visible to unauthenticated visitors or gated behind
  sign-in to deter scraping is unspecified. Open.

### 6.5 Buyer ↔ seller contact

- **FR-27** A buyer can send an inquiry against an ad, and both parties have a Messages surface with an
  unread count. `[DERIVED]` — `my_account_desktop` renders `Messages / 5` and per-ad `12 Inquiries`; the
  consumer design system specifies a `Chat` button as a primary action.
- **Scope alarm:** in-app messaging is **entirely absent from the pack index's locked decisions**, yet
  the UI assumes it. Messaging is a large feature (threads, notifications, abuse handling, read state,
  content moderation). It must be either explicitly scoped into MVP or explicitly deferred with the UI
  affordances removed. `[PROPOSED]` — defer messaging past MVP and ship phone contact only; revisit once
  moderation load is understood. **This is the highest-impact open question in the pack.**

### 6.6 Seller account surface

- **FR-28** A dashboard greeting, a primary `Post New Ad` action, and navigation to My Ads, Saved Ads,
  Messages, Profile & Verification, Settings. `[DERIVED]`
- **FR-29** Overview counters: Active, Pending, Saved, Unread. `[DERIVED]`
- **FR-30** My Ads is tabbed by status per §5, and each row exposes Edit Ad, Promote, Mark as Sold,
  Delete. `[DERIVED]`
- **FR-31** Each ad row shows performance: view count and inquiry count. `[DERIVED]` — `1,240 Views` /
  `12 Inquiries`. View counting needs a definition (unique vs. raw, bot filtering). Open.

### 6.7 Moderation

- **FR-32** A moderation queue lists pending ads oldest-first with an age indicator, seller, category,
  and any automated flags. `[DERIVED]` — `management-portal/src/lib/data.ts` already encodes exactly
  this shape: `{ title, seller, category, status, flags, age }` with flag values `Price anomaly`,
  `Duplicate images`, `Warranty claim`, and ages in minutes/hours.
- **FR-33** A moderator opens an ad and can approve or reject it, editing fields before approval.
  `[DERIVED]`
- **FR-34** **AI/OCR-assisted intake.** The review screen presents a *source image*, the *raw OCR text*
  extracted from it, and a set of *AI-extracted field values* — each carrying a confidence level
  (`High` / `Med`) and, where confidence is low, an explanatory warning. The observed example flags
  `Price (LKR)` with *"OCR extracted '8,75O,000/=' (contains letter 'O')"* and flags the location
  `Nugeg0da` as a digit-for-letter OCR error. The screen's own instruction: *"Review all AI-extracted
  content before publishing to the marketplace."* `[DERIVED]` — `review_ad_admin_desktop`, including
  image tools (`zoom_in`, `rotate_right`, `crop`) and a collapsible `View Raw OCR Text` panel.

  **Scope alarm:** this is a second major capability with **no mention in the locked decisions**. It
  implies an ingestion path where an ad originates as a photograph of a paper or WhatsApp advert and is
  machine-transcribed into structured fields. It is also the clearest justification for FastAPI being in
  the stack. It needs an explicit in/out decision: it is a differentiator, and it is not small.
  `[PROPOSED]` — treat OCR/AI extraction as **post-MVP** but *keep the moderation review UI's
  field-level provenance model*, so adding extraction later does not require redesigning review.

- **FR-35** Reported/flagged ads are a distinct operator work queue. `[DERIVED]` — admin KPI
  `Reported Ads / 34 / Action required`, a `Reported` status in the queue data, and a `flag Flagged (12)`
  filter on the advertisements table. The reporting *intake* (who reports, what reasons) is not designed
  anywhere in the inputs. Open.
- **FR-36** Bulk actions on selected ads, surfaced via a slide-in bottom toolbar. `[DERIVED]` — specified
  in the operational design system's component section.

### 6.8 Management portal — administration

- **FR-37** A dashboard of operational KPIs with trend deltas: Ads Awaiting Review, Active Ads, Reported
  Ads, New Users Today; plus Listings-by-Category and Regional-Distribution-by-Province breakdowns.
  `[DERIVED]` — `admin_dashboard_overview`, mirrored in `management-portal/src/lib/data.ts`.
- **FR-38** An advertisements register: searchable and filterable by status, category and location;
  tabular with image, ad ID, listing details, LKR price, seller, status, date; supporting CSV export and
  operator-side ad creation. `[DERIVED]` — `advertisements_management_desktop`, including `Export CSV`
  and `Create Advertisement`.
- **FR-39** User administration. `[DERIVED]` — sidebar `Users`.
- **FR-40** Category taxonomy administration, including the per-category attribute schemas of FR-9.
  `[DERIVED]` — sidebar `Categories`; the schemas have to be editable somewhere.
- **FR-41** Promotion plan administration — the featuring products, their prices and durations.
  `[DERIVED]` — sidebar `Plans & Promotions`.
- **FR-42** Reports. `[DERIVED]` — sidebar `Reports`. Contents unspecified. Open.
- **FR-43** System settings. `[DERIVED]` — sidebar `Settings`. Contents unspecified. Open.

### 6.9 Featuring and payment

- **FR-44** A seller may purchase featuring for an `ACTIVE` ad they own, from the ad's row menu
  (`Promote`) or from the publish confirmation (`Explore Promotions`). `[DERIVED]`
- **FR-45** Featuring is sold as one or more named plans with a price and a duration. `[DERIVED]` from
  `Plans & Promotions`; the plan catalogue, prices and durations are unspecified. Open.
- **FR-46** Payment is captured through a payment gateway; on successful settlement the ad's featured
  window starts. `[PROPOSED]` — **no gateway is named anywhere in the inputs.** PayHere is the leading
  candidate for an LKR-denominated Sri Lankan consumer product. Open.
- **FR-47** Featuring expiry returns the ad to ordinary ranking without changing its `ACTIVE` status.
  `[PROPOSED]`
- **FR-48** A seller can see what they paid for and when it expires; the operator can reconcile
  payments. `[PROPOSED]` — no receipt or reconciliation surface exists in the screens.

## 7. Non-functional requirements

- **NFR-1 — Responsive.** Every public surface works on mobile and desktop. Consumer breakpoints:
  mobile ≤767px (4-col, 16px margins), tablet 768–1023px (8-col, 24px margins), desktop ≥1024px (12-col,
  20px gutters, 1280px max container). `[DERIVED]` — consumer `DESIGN.md`.
- **NFR-2 — Operator density.** The management portal is desktop-first: full dashboard ≥1440px, sidebar
  expanded 1024–1439px, and below 1024px the sidebar auto-collapses with horizontal table scrolling.
  `[DERIVED]` — operational `DESIGN.md`.
- **NFR-3 — Accessibility.** WCAG 2.1 AA. `[PROPOSED]` — no standard is stated in the inputs, but the
  pack's own instruction requires accessibility checks in every change's definition of done, which needs
  a named target to be testable.
- **NFR-4 — Money.** All amounts are LKR, stored as exact integer minor units (never floating point),
  formatted `Rs. 250,000` with mandatory thousands separators. `[LOCKED]` for currency, `Rs.` prefix and
  separators (consumer `DESIGN.md`); `[PROPOSED]` for the integer-minor-unit storage rule.
- **NFR-5 — Localisation readiness.** English-only UI at MVP, but Sinhala and Tamil are named as future
  work — so user-facing copy is externalised from day one rather than retrofitted. `[LOCKED]` for the
  English-only scope; `[PROPOSED]` for the externalisation discipline.
- **NFR-6 — Moderation latency.** The product promises sellers "typically live within 24 hours". That
  promise is a requirement on operator staffing and on queue tooling. `[DERIVED]` — literal UI copy.
  Whether 24h is a target or an SLA is open.
- **NFR-7 — Data protection.** The system stores personal contact details and user-uploaded imagery.
  Sri Lanka's Personal Data Protection Act applies. `[PROPOSED]` — no compliance regime is named in the
  inputs; this needs a decision because it shapes retention, export and deletion work.
- **NFR-8 — Observability.** Every change ships with relevant observability, per the pack's definition of
  done. `[LOCKED]` in principle; the stack is unspecified. Open.
- **NFR-9 — Performance.** Order-of-magnitude targets are unspecified. `[PROPOSED]` — the admin
  dashboard's own mock numbers (24,150 active ads, 482 pending, 156 new users/day) are the only volume
  signal in the inputs and are a reasonable planning basis for MVP capacity.

## 8. Acceptance criteria — MVP definition of done

The MVP is accepted when all of the following are demonstrable end-to-end across the public web,
management portal, and mobile app.

| # | Criterion |
|---|-----------|
| AC-1 | A visitor registers with email/password, verifies the address, and signs in. |
| AC-2 | A visitor registers and signs in with Google, and a second sign-in via the other method resolves to the same account. |
| AC-3 | A signed-in member completes the post-ad wizard for a Vehicles ad and the ad lands in `PENDING`, not public. |
| AC-4 | The ad is invisible to an unauthenticated visitor in browse, in search, and by direct URL while `PENDING`. |
| AC-5 | A moderator sees the ad in the queue with its age, opens it, edits a field, and approves it. |
| AC-6 | The approved ad is immediately findable by category, by location, by price range, and by free-text search, and renders fully on the detail page with its `LL-NNNNN` reference. |
| AC-7 | A moderator rejects a different ad with a reason, and the owning seller sees both the rejected state and the reason. |
| AC-8 | The seller purchases a featuring plan for the approved ad, payment settles, and the ad thereafter renders with the promoted treatment and ranks above non-featured ads in the same result set. |
| AC-9 | Featuring cannot be purchased for an ad that is not `ACTIVE`. |
| AC-10 | The seller marks the ad sold and it leaves public discovery. |
| AC-11 | Every one of AC-1…AC-10 is completable on the mobile app and on a 375px-wide browser viewport. |
| AC-12 | The admin dashboard's Awaiting Review / Active / Reported / New Users counters agree with the underlying data. |
| AC-13 | An automated accessibility scan passes at the committed level on every page visited in AC-1…AC-11. |
| AC-14 | Every public and operator API endpoint rejects unauthenticated and cross-owner access with the documented error contract. |

## 9. Explicit non-goals for MVP

- Sinhala and Tamil UI. `[LOCKED]`
- Any seller charge other than featuring an approved ad. `[LOCKED]`
- Auto-publication without moderation. `[LOCKED]`
- In-app messaging, pending the §6.5 decision. `[PROPOSED]`
- OCR/AI ad intake, pending the FR-34 decision. `[PROPOSED]`
- Ratings and reviews, saved searches with alerts, seller storefronts, escrow or in-platform settlement
  between buyer and seller. `[PROPOSED]` — none appear in any input; naming them out-of-scope keeps the
  boundary explicit.
