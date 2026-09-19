# AI-Guided Post Ad — UI Generation Brief & Prompt Library

## Document Control

| Field | Value |
|---|---|
| Product | LankaListings |
| Implements | [ai-guided-post-ad-implementation-plan.md](ai-guided-post-ad-implementation-plan.md) Phase 1 |
| Spec | [09-ai-guided-post-ad-spec.md](../../09-ai-guided-post-ad-spec.md) v2 §5 |
| Status | Phase 1A/1B complete — prompts authored, generation in progress |
| Version | 1.0 |
| Date | 2026-09-19 |
| Stitch project | `14253969128473213455` ("advertising") |
| Design system | `assets/da83d34188364f7da095902cb850087c` — "LankaListings" (public) |
| Admin design system | `assets/c2cef0c71ff64a189816cb03bf394c84` — "LankaListings Operational Interface" (Phase 10) |
| Export target | `stitch_advertising/<screen_name>/` |

Prompts are committed so screens are **reproducible**. Regenerating a screen means re-running its prompt,
not reinventing it. When a screen needs to change, the prompt changes first.

---

## 1A — Canonical decisions

### 1A.1 The stepper (resolves OQ-03)

**Six stages. One component. Identical on every screen and every breakpoint.**

| # | Label | Stage |
|---|---|---|
| 1 | Category | Choose category and subcategory |
| 2 | Details | Required core and category fields, **including price** |
| 3 | Questions | Decision-service-selected follow-ups |
| 4 | Photos | Photos and Province → District → City |
| 5 | Description | AI-drafted title and description, attribute suggestions |
| 6 | Submit | Contact preference, preview, terms gate, submit |

The five existing `post_your_ad_*` exports are **superseded**. They carried three different steppers
(5 steps vs 4, three label sets, `w-4`/`w-8`/`w-10` dot sizes), two competing mobile progress bars on one
screen, and only one mobile variant across five screens. None of that is carried forward.

**Stepper rules, binding on every screen:**

- Desktop: numbered `w-10 h-10 rounded-full` dots on a `h-1 bg-surface-variant` track, filled
  `bg-secondary`. Completed steps show a `check` icon; the current step carries
  `ring-4 ring-secondary/20`. Labels below the dots, `hidden md:block`.
- Mobile: one compact header — step label plus "Step N of 6" — and **one** `h-1` progress bar. Never two.
- Fill width is always `(N-1)/5` of the track. Step 1 = `w-0`, step 6 = `w-full`.
- A step is only clickable if it has been completed.

### 1A.2 AI component vocabulary

Nothing AI-related exists in the current design system. These are the new primitives, expressed in
existing tokens — no new colours are introduced.

| Component | Treatment |
|---|---|
| **AI disclosure** | Reuses the existing info block verbatim: `bg-primary-fixed/30 rounded-lg p-3` + `auto_awesome` icon + bold title + `font-metadata` body. Copy: "AI-generated draft — review all details before submitting." |
| **Suggestion card** | `bg-surface-container-low rounded-lg border border-outline-variant/30 p-sm`, sitting directly beneath its field. Holds the proposed value, an evidence line in `font-metadata text-on-surface-variant`, a confidence chip, and the two actions. |
| **Accept / Ignore** | Always a pair. **Accept** = `bg-secondary text-on-secondary rounded-lg h-9`. **Ignore** = text button, `text-on-surface-variant`. Never a single commit-style button — the seller must be able to decline in one click. |
| **Confidence chip** | `rounded-full px-xs py-base font-label-caps uppercase`. High = `bg-secondary/10 text-secondary`; Medium = `bg-tertiary-fixed-dim/20 text-on-tertiary-container`; Low = `bg-surface-container-high text-on-surface-variant`. |
| **Stale badge** | Amber, on the tertiary family: `bg-tertiary-fixed-dim/20 text-on-tertiary-container rounded-full font-label-caps uppercase` + `history` icon. Copy: "Out of date". |
| **Generation skeleton** | Three stacked `animate-pulse bg-surface-container rounded` bars at 100%/92%/64% width, with a `auto_awesome` + "Writing your ad…" line and a text **Cancel**. |
| **Follow-up question card** | `bg-surface-container-lowest rounded-xl border border-outline-variant/30 p-md`, with a sub-progress line ("Question 2 of 3") in `font-label-caps uppercase`, a "why this helps" line, and a visible **Skip** beside Continue. |
| **AI unavailable / retry** | `bg-surface-container-low border border-outline-variant rounded-lg p-sm` + `cloud_off` icon. Copy: "AI assistance is unavailable right now. You can still complete this ad manually." Plus **Try again** and **Write it myself**. Never surfaces a provider error. |

**Not needed in v1:** translation tabs and price-guidance panels. Both capabilities are deferred
(spec §8.4, §8.5), and designing surfaces for them now would be speculative.

### 1A.3 Screen inventory

12 core screens — six stages at two breakpoints. States ship as variants within their stage screen rather
than as separate screens, except the two that change the whole page.

| # | Screen | Device |
|---|---|---|
| 1 | `post_ad_01_category_desktop` | DESKTOP |
| 2 | `post_ad_01_category_mobile` | MOBILE |
| 3 | `post_ad_02_details_desktop` | DESKTOP |
| 4 | `post_ad_02_details_mobile` | MOBILE |
| 5 | `post_ad_03_questions_desktop` | DESKTOP |
| 6 | `post_ad_03_questions_mobile` | MOBILE |
| 7 | `post_ad_04_photos_desktop` | DESKTOP |
| 8 | `post_ad_04_photos_mobile` | MOBILE |
| 9 | `post_ad_05_description_desktop` | DESKTOP |
| 10 | `post_ad_05_description_mobile` | MOBILE |
| 11 | `post_ad_06_submit_desktop` | DESKTOP |
| 12 | `post_ad_06_submit_mobile` | MOBILE |
| 13 | `post_ad_05_generating_desktop` | DESKTOP — whole-page generation state |
| 14 | `post_ad_ai_unavailable_desktop` | DESKTOP — whole-page degraded state |
| 15 | `post_ad_submitted_desktop` | DESKTOP — post-submit confirmation |
| 16 | `post_ad_submitted_mobile` | MOBILE |

### 1A.4 Shared prompt preamble

Every prompt below is prefixed with this block. It encodes the decisions above so no screen can drift.

> **LankaListings — Post Your Ad wizard.** Sri Lankan classifieds marketplace, English UI, light mode
> only. Prices in LKR formatted `Rs. 8,750,000` with thousands separators.
>
> **Persistent flow header** (`h-20` desktop, `h-16` mobile): LankaListings logo left; "Save as Draft" and
> a `text-error` "Cancel" on the right; a "Saved 2 minutes ago" status in `font-metadata`.
>
> **Stepper, identical on every screen:** six steps — Category, Details, Questions, Photos, Description,
> Submit. Desktop: numbered circles on a track, completed steps show a check, current step has a focus
> ring, labels beneath. Mobile: a compact "Step N of 6" header with exactly one thin progress bar.
>
> **Buttons:** primary actions use the emerald secondary token; Back is an outlined button. Desktop places
> them inline at the foot of the form; mobile uses a sticky bottom bar respecting the safe area.
>
> Material Symbols Outlined for all icons. Max content width 1280px. Do not use placeholder lorem text —
> use realistic Sri Lankan marketplace content.
>
> **Sample AI copy must obey the content rules in spec §8.2.** Any generated title or description shown in
> a mockup may state only facts the seller actually entered. It must never say an item is *verified*,
> *accident-free*, *original*, *warrantied*, *genuine*, *brand new*, *urgent* or *best price*, and must
> never invent inspection records, service history, battery-health figures, ownership history, or test
> results. A mockup is the visual specification engineers build to — sample copy that breaks the content
> policy teaches the wrong behaviour.

---

## 1B — Prompt library

### P1 · Category — desktop

> [preamble] Stage 1 of 6, "Category" active, progress bar empty.
>
> Page heading "What are you selling?" with a one-line subheading. A responsive grid of nine category
> cards — Vehicles, Property, Land, Jobs, Electronics, Services, Home & Garden, Fashion, Other — each a
> large outlined tile with a 48px Material Symbol, a label, and a live ad count in `font-metadata`.
> Hovering a tile shifts its border to emerald and washes the surface faintly.
>
> Selecting a tile slides in a 400px right-hand subcategory panel listing that category's subcategories as
> selectable rows with a trailing chevron — show it open on Vehicles with Cars selected.
>
> A fixed bottom action bar holds a ghost "Save Draft" and an emerald "Continue" with a trailing
> `arrow_forward`. Continue is enabled because a subcategory is selected.

### P2 · Category — mobile

> [preamble] Stage 1 of 6. Single column. Compact header "Choose a category", one progress bar at 0%.
>
> Nine category tiles in a two-column grid, each with a 32px icon, label and ad count. Vehicles is
> selected and shows its subcategory list expanded inline beneath it as full-width rows, Cars checked.
> Sticky bottom bar with a full-width emerald Continue.

### P3 · Details — desktop

> [preamble] Stage 2 of 6, "Details" active, steps 1 complete, progress bar 20%.
>
> Twelve-column layout. Left eight columns: a white rounded card titled "Tell us about your Toyota Prius"
> containing, in order — Title (text, `Toyota Prius S Touring 2016`, live `28/70` counter); Condition
> (three segmented radio options: Brand New, Used, Reconditioned — Used selected); Make (select, Toyota);
> Model (select, Prius); Model Year (select, 2016); Registration Status (two radio cards: Registered
> selected, Unregistered); Registration Number (text — visibly present *because* Registered is selected);
> Price (money input with a leading `Rs.` prefix, value `8,750,000`, large `h-16`) and a "Negotiable"
> toggle beneath it; Description (textarea, 4 rows, `0/4000` counter, helper text saying AI can draft this
> for you at step 5).
>
> Right four columns: a sticky sidebar with a "Why these fields matter" tips card — three icon-and-text
> pairs about buyer search, and a small stat card reading "Cars in Colombo sell 40% faster with a photo".
>
> Field labels are uppercase `font-label-caps` in muted grey above each input. Inputs are `h-12`,
> `rounded-lg`, 1px outline-variant border, emerald focus ring. Inline Back and "Continue" at the foot of
> the form card.

### P4 · Details — mobile

> [preamble] Stage 2 of 6, progress 20%. Single column, generous vertical rhythm, `pb-32` so the sticky
> bar never covers the last field.
>
> Same field sequence as desktop — Title with counter, Condition segmented control, Make, Model, Year,
> Registration Status radio cards, Registration Number, Price with `Rs.` prefix, Negotiable toggle,
> Description textarea. Selects use a trailing `expand_more` icon. No sidebar. Sticky bottom bar with
> Back and a wide emerald Continue.

### P5 · Questions — desktop  ★ new surface

> [preamble] Stage 3 of 6, "Questions" active, steps 1–2 complete, progress 40%.
>
> Centred single-column layout, roughly 720px wide — narrower than the other stages, because this stage
> asks one thing at a time.
>
> Heading "A few more details" and a subheading "These are optional, but they help buyers find your ad."
> Below it, a small AI disclosure chip reading "Suggested for your listing" with an `auto_awesome` icon.
>
> A large white question card with a rounded-xl border showing: an uppercase sub-progress label "Question
> 1 of 2"; the question "What is the mileage?"; a number input with a `km` suffix; and a muted "Why this
> helps" line reading "Buyers filter used vehicles by mileage more than any other spec."
>
> Beneath the card, a row with a text "Skip this question" on the left and an emerald "Continue" on the
> right. Below that, a faint preview strip listing the upcoming question as a disabled pill:
> "Next: Transmission".
>
> At the very bottom, a muted text link "Add more details" for volunteering extra optional fields.

### P6 · Questions — mobile  ★ new surface

> [preamble] Stage 3 of 6, progress 40%. Single column.
>
> Heading "A few more details", one question card filling most of the viewport: uppercase "Question 1 of
> 2", the question "What is the mileage?", a large number input with a `km` suffix, and a muted
> "Why this helps" line. Sticky bottom bar with a text "Skip" on the left and a wide emerald "Continue"
> on the right.

### P7 · Photos — desktop

> [preamble] Stage 4 of 6, "Photos" active, steps 1–3 complete, progress 60%.
>
> Twelve columns. Left eight: an upload dropzone — dashed outline-variant border, `rounded-xl`, a circular
> emerald-container icon puck with `add_a_photo`, "Drag photos here or browse", and helper text
> "1 to 12 photos · up to 5 MB each · JPG, PNG, WebP or HEIC". Beneath it a four-column grid of five
> uploaded car thumbnails, each `aspect-square rounded-lg` with a `bg-black/50` remove button; the first
> carries a 2px emerald border and a "Cover" pill with a filled star.
>
> Below the photos, a location group: three cascading selects — Province (Western), District (Colombo),
> City (Dehiwala) — followed by a small map preview with a location pin and a privacy note in an info
> block: "Only your city is shown publicly. Your exact address is never published."
>
> Right four columns: a sticky "Photo tips" card with three icon-and-text pairs.

### P8 · Photos — mobile

> [preamble] Stage 4 of 6, progress 60%. Single column, `pb-32`.
>
> A compact `h-32` dashed dropzone with a circular emerald icon puck and the text
> "1 to 12 photos · up to 5 MB each". A three-column thumbnail grid with five car photos, the first marked
> Cover with an emerald border and star pill. Then the three cascading location selects and the privacy
> info block. Sticky bottom bar with Back and a wide emerald Continue.

### P9 · Description — desktop  ★ new surface

> [preamble] Stage 5 of 6, "Description" active, steps 1–4 complete, progress 80%.
>
> Twelve columns. Left seven: an AI disclosure block at the top —
> `bg-primary-fixed/30 rounded-lg`, an `auto_awesome` icon, bold "AI-generated draft", and the line
> "Review all details before submitting." Below it a "Title" field containing the generated
> `Toyota Prius S Touring 2016 — Registered, Low Mileage` with a `44/70` counter, and a "Description"
> textarea holding four short factual paragraphs about the car with a `612/4000` counter. Both are plainly
> editable. Under them a row of three controls: an outlined "Regenerate" with a `refresh` icon, a text
> "Write it myself", and an emerald "Looks good — continue".
>
> Right five columns, sticky: a "Suggestions" panel titled "We found 2 details in your notes". Two
> suggestion cards, each `bg-surface-container-low rounded-lg border`:
> — "Transmission → **Automatic**", evidence line "Your note mentions 'auto gearbox'", a `MEDIUM`
> confidence chip, and an emerald **Accept** with a text **Ignore**.
> — "Fuel type → **Hybrid**", evidence "Prius 2016 models in your notes", a `HIGH` chip, same actions.
> Beneath the cards, a muted line: "Suggestions are never added to your ad until you accept them."

### P10 · Description — mobile  ★ new surface

> [preamble] Stage 5 of 6, progress 80%. Single column, `pb-32`.
>
> AI disclosure block at the top. Editable Title field with counter, editable Description textarea with
> counter. Then a "Suggestions" section header and two stacked suggestion cards — Transmission →
> Automatic (MEDIUM), Fuel type → Hybrid (HIGH) — each with evidence text and an Accept / Ignore pair.
> Below them an outlined full-width "Regenerate" with a `refresh` icon. Sticky bottom bar with Back and a
> wide emerald "Continue".

### P11 · Submit — desktop

> [preamble] Stage 6 of 6, "Submit" active, steps 1–5 complete, progress 100%.
>
> Twelve columns. Left seven: a "How buyers reach you" card with two radio options — "Show my phone
> number" (selected, with the number `077 123 4567` and a "Verified" emerald chip) and "Chat only". Below
> it a full ad preview card rendered exactly as a buyer sees it: a photo mosaic with a `1/5` counter, the
> title, `Rs. 8,750,000` in the large price style, a `Negotiable` chip, a specification chip row (2016 ·
> Automatic · Hybrid · Registered), the description, and a Dehiwala, Colombo location line with a
> `location_on` icon.
>
> Right five columns, sticky: an action card containing a moderation notice in an info block —
> `shield_lock` icon, "Your ad will be reviewed before it goes live", "Most ads are reviewed within 24
> hours" — then a required checkbox reading "I agree to the Terms of Service and Privacy Policy", then a
> full-width emerald "Submit for Review" button, **disabled and at 50% opacity because the checkbox is
> unchecked**. Beneath it a text "Save as Draft & Exit".
>
> Below the action card, a collapsed, clearly optional "Feature this ad" upsell showing three plan tiles
> with a "You can do this later" note — it must not look like a required step.

### P12 · Submit — mobile

> [preamble] Stage 6 of 6, progress 100%. Single column, `pb-40`.
>
> Contact preference radio cards, then the full buyer-view ad preview card, then the moderation info block
> with the 24-hour line, then the Terms checkbox, then the optional featuring upsell collapsed behind a
> "Feature this ad — optional" disclosure row. Sticky bottom bar with a full-width emerald "Submit for
> Review", disabled at 50% opacity because the checkbox is unchecked.

### P13 · Generating — desktop

> [preamble] Stage 5 of 6, progress 80%. Same twelve-column frame as the Description screen, but mid-generation.
>
> The left seven columns show a generation skeleton in place of the fields: an `auto_awesome` icon with
> "Writing your ad…" and a muted "This usually takes a few seconds", above three stacked `animate-pulse`
> placeholder bars at 100%, 92% and 64% width, then a gap, then four more shorter bars. A text "Cancel"
> sits below them.
>
> The right five columns show the Suggestions panel in its empty loading state with two pulsing card
> outlines. Crucially, the Back and "Skip for now — write it myself" controls remain enabled, so the
> seller is never trapped waiting.

### P14 · AI unavailable — desktop

> [preamble] Stage 5 of 6, progress 80%. The degraded state.
>
> In place of the generated copy, a calm notice block — `bg-surface-container-low`, 1px outline-variant
> border, `rounded-lg`, a muted `cloud_off` icon — reading "AI assistance is unavailable right now" with
> the line "You can still write and publish your ad normally." Two actions: an outlined "Try again" with a
> `refresh` icon, and an emerald "Write it myself".
>
> Below the notice, the ordinary empty Title and Description fields are present and fully usable, with
> their character counters at `0/70` and `0/4000`. Nothing about this screen is an error state — no red,
> no warning triangle, no provider detail. The seller's path forward is obvious.

### P15 · Submitted — desktop

> [preamble] No stepper — the wizard is complete.
>
> A centred confirmation card, roughly 640px wide. A large emerald circular `check_circle` badge, the
> heading "Your ad has been submitted", and the line "Reference **LL-49210**" in a monospace-feeling
> style. A muted paragraph: "Our team reviews every ad before it goes live. Most are reviewed within 24
> hours, and we'll email you as soon as yours is approved."
>
> A small status row showing the ad title, its thumbnail, and an amber `Pending review` status pill.
> Then two actions — an emerald "View my ads" and an outlined "Post another ad". At the bottom, a muted
> line: "You can edit this ad while it is pending review."

### P16 · Submitted — mobile

> [preamble] No stepper. Single column, centred.
>
> Large emerald `check_circle` badge, "Your ad has been submitted", the `LL-49210` reference, the 24-hour
> review paragraph, a compact status row with the thumbnail and an amber `Pending review` pill, then a
> full-width emerald "View my ads" and an outlined "Post another ad".

---

## 1C — Generation log

| Prompt | Screen | Device | Status |
|---|---|---|---|
| P1 | `post_ad_01_category_desktop` | DESKTOP | generated ✅ · `e245bd9ff271` |
| P2 | `post_ad_01_category_mobile` | MOBILE | pending |
| P3 | `post_ad_02_details_desktop` | DESKTOP | generated ✅ · `616d32b53220` |
| P4 | `post_ad_02_details_mobile` | MOBILE | pending |
| P5 | `post_ad_03_questions_desktop` | DESKTOP | generated ✅ · `beb9a320157f` |
| P6 | `post_ad_03_questions_mobile` | MOBILE | pending |
| P7 | `post_ad_04_photos_desktop` | DESKTOP | pending |
| P8 | `post_ad_04_photos_mobile` | MOBILE | pending |
| P9 | `post_ad_05_description_desktop` | DESKTOP | regenerate — §8.2 · `9f6cf28d985a` |
| P10 | `post_ad_05_description_mobile` | MOBILE | pending |
| P11 | `post_ad_06_submit_desktop` | DESKTOP | pending |
| P12 | `post_ad_06_submit_mobile` | MOBILE | pending |
| P13 | `post_ad_05_generating_desktop` | DESKTOP | pending |
| P14 | `post_ad_ai_unavailable_desktop` | DESKTOP | pending |
| P15 | `post_ad_submitted_desktop` | DESKTOP | pending |
| P16 | `post_ad_submitted_mobile` | MOBILE | pending |

## 1D — Review checklist

Each generated screen is checked against:

- [ ] Stepper matches 1A.1 exactly — six steps, correct labels, correct fill, one mobile progress bar
- [ ] Emerald is the CTA colour; navy is structural; amber appears only on stale and pending states
- [ ] Manrope for headings and body, Inter for labels and metadata
- [ ] Field labels are uppercase `font-label-caps` in muted grey
- [ ] Every AI element is visibly labelled as AI, and every suggestion has both Accept and Ignore
- [ ] No red used for an AI-unavailable state — it is a calm notice, not an error
- [ ] Realistic Sri Lankan content; prices formatted `Rs. 8,750,000`
- [ ] Mobile: sticky bottom bar respects the safe area; no field hidden behind it
