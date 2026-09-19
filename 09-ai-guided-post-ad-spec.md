# AI-Guided Post Ad Flow — Product & Engineering Specification

**Product:** LankaListings
**Document status:** Reconciled — ready for engineering
**Version:** 2.0
**Last updated:** 19 September 2026
**Scope:** Public Next.js Post Ad flow, `listing-service` orchestration, TypeSafe Jev decision integration, content generation and attribute suggestion
**Companion documents:** `.forge/project-prd.md`, `04-data-model.md`, `05-api-contract.md`, `08-decision-log.md`, `docs/product/ai-guided-post-ad-implementation-plan.md`

> **Revision 2.0 — what changed from the draft.** §7 is rewritten: the draft asked the decision engine to
> return a composite outcome object, which Jev cannot produce. The wire contract throughout now matches
> `05-api-contract.md` (snake_case, `{data, error, meta}`, `reference` in URLs, `amount_cents`) and the
> status vocabulary matches `04-data-model.md` (`draft`/`pending`/`active`). Ownership moves from FastAPI
> to `listing-service` per D-18. Five dropped commitments are restored (FR-3, FR-13, FR-14, FR-15, FR-33).
> Price guidance and Sinhala/Tamil content are deferred with explicit re-entry criteria.

## 1. Purpose

LankaListings is a Sri Lankan, broad classifieds marketplace. A standard advertisement is free, a
featured placement is paid, and no ad is publicly listed until an administrator approves it.

This specification defines the **AI-guided Post Ad flow** entered from the public site's **Post Your Ad**
button. The flow collects only the information the selected category needs, lets a decision model choose
whether follow-up questions are worth asking, and then produces an editable, accurate advertisement draft.

It must work across all nine categories. It must not become a generic chatbot, and no AI provider may
control the marketplace's mandatory data, validation, pricing, or publication decisions.

## 2. Confirmed product decisions

| Area | Decision |
|---|---|
| Marketplace | Anyone with a LankaListings account may create an ad. |
| Authentication | Google sign-in and email/password, both owned by `identity-service`. The seller must be signed in before a draft is saved or submitted. |
| Email verification | An ad cannot be submitted by a seller whose email is unverified (FR-3). |
| Market | Sri Lanka. Prices are LKR integer minor units; location is Province → District → City. |
| Publication | An ad is never public on generation. Submission moves it to `pending`; a moderator must approve it before `active`. |
| Moderator actions | **Approve and reject only** (FR-33). There is no "request changes" control. |
| Questions | A versioned category schema defines the allowed, required, and conditional questions. Jev scores which eligible follow-ups are worth asking. |
| LLM output | The LLM may generate editable title and description drafts and suggest missing structured attributes from seller text. |
| Seller control | Every AI result is a suggestion. The seller can edit, accept, reject, or ignore it. No AI result silently overwrites a seller answer. |
| Draft persistence | Autosave **and** an explicit *Save as Draft* / *Save as Draft & Exit* affordance (FR-13). |
| UI language | English. Sinhala and Tamil are deferred — see §8.4. |

## 3. Goals and non-goals

### 3.1 Goals

- Let a first-time seller create a complete, high-quality ad without knowing every category-specific field.
- Ask required questions deterministically, then use Jev to avoid unnecessary optional questions.
- Produce a useful title and a factual, scannable description from the seller's confirmed details.
- Preserve a structured data record so public filters — vehicle make, year, district, price — keep working.
- Give moderators visibility into seller-confirmed data and AI-assisted content, without treating either
  as trusted for publication.
- Keep the flow resilient: a decision-service, LLM, or network failure must never prevent a seller from
  completing and submitting an ordinary draft.

### 3.2 Non-goals

- A free-form chat agent that can ask questions outside the category schema.
- Automatic publishing, automatic moderation approval, or automatic price selection.
- LLM processing of private contact information, credentials, session tokens, exact private addresses, or
  unpublished image files.
- Replacing the shipped operator OCR/newspaper ingestion feature.
- Full English/Sinhala/Tamil UI localisation.
- Buyer payments, escrow, auctions, or financing.

**Deferred rather than rejected:** price guidance (§8.5) and Sinhala/Tamil ad content (§8.4). Mobile
posting parity ships after web; mobile remains an MVP *surface* per D-11/D-27, so this is a sequencing
decision, not a scope cut.

## 4. Definitions

| Term | Meaning |
|---|---|
| **Core question** | A marketplace-wide question required for every relevant ad — category, title, description, price, location, contact preference. |
| **Category schema** | Versioned, admin-managed configuration defining fields, labels, validation, conditions, UI controls, AI sensitivity, and filter mapping for a category/subcategory. |
| **Eligible question** | A schema question whose visibility condition is true and which is not yet answered. |
| **Required question** | An eligible question that must be answered before the draft can advance or submit. The decision service cannot omit it. |
| **Follow-up question** | An optional schema question, marked `follow_up_eligible`, that may be selected after the required set is complete. Never invented outside the schema. |
| **Decision service** | The adapter around TypeSafe Jev. It scores how useful each eligible follow-up would be; the server does the selecting. |
| **Generation** | An LLM call in `media-service` producing title/description **candidates**. |
| **Attribute suggestion** | A proposed value for an empty schema field, pending explicit seller acceptance. |
| **Draft version** | The optimistic-concurrency integer (`05` §12) and answer snapshot an AI result was produced from. |
| **Stale** | Derived AI output whose `source_version` is behind the draft's current `version`. |

## 5. User experience and flow

### 5.1 Entry and authentication

1. A visitor selects **Post Your Ad** from the header, mobile navigation, account area, or a category page.
2. If unauthenticated, the app opens the Google or email/password flow owned by `identity-service`. On
   success, the seller returns to the Post Ad flow without losing the intended action.
3. After the seller selects a category, `listing-service` creates a server-owned `draft` advertisement
   with an `LL-NNNNN` reference and an ad-creation session. A seller may abandon and resume later.
4. The draft **pins the category schema version** at creation. Later schema edits must not change the
   questions or validation partway through a seller's session.

### 5.2 Seller-facing stages

Six stages, one canonical stepper. Field questions within a stage are shown one at a time or in compact
groups on mobile — not one page per answer.

| Stage | Purpose | Minimum behaviour |
|---|---|---|
| 1. Choose category | Category and subcategory. | Active categories only. Changing category later requires confirmation, because category-specific answers can be removed. |
| 2. Essential details | Required core and category fields, **including price**. | Render the pinned schema, honour conditions, validate immediately, autosave completed answers. |
| 3. Smart follow-ups | Only eligible optional questions, selected through the decision service. | Show why a question helps when a reason is available; always permit skipping. |
| 4. Photos and location | Photos, Province/District/City. | Minimum 1, maximum 12 photos, 5 MB each, JPEG/PNG/WebP/HEIC. Exact address is never public. |
| 5. Generate and refine | Title and description drafts, attribute suggestions. | Clearly label AI output; the seller must review and may edit the final title and description. |
| 6. Contact, preview and submit | Contact preference, buyer-view preview, terms gate, submit. | Validate the whole draft server-side; transition only to `pending`. |

**Why six and not five.** The two prior Stitch variants disagreed on whether step 4 was Preview or
Price & Contact, and both carried a pricing block — the tell that price is a *required core field*. Price
therefore sits in stage 2 with the other essentials, contact/preview/submit merge into one final stage,
and the two genuinely new surfaces are added. This resolves OQ-03.

The seller may move back to a completed stage; doing so never discards saved answers. Any edit that
changes the answer snapshot marks dependent AI output **stale** until regenerated or manually confirmed.

Stage 6 states the moderation expectation to the seller, presents a hard Terms-of-Service and Privacy
acceptance gate (FR-14), and offers featuring as a **deferrable** upsell that never blocks submission
(FR-15).

### 5.3 Vehicle example

For **Vehicles → Cars**, the schema presents essentials in dependency order:

1. Manufacturer / make
2. Model (filtered by make where data exists; always supports `other`)
3. Model year
4. Registration status: `registered` or `unregistered`
5. District, then City where applicable
6. Asking price in LKR and negotiable flag

The schema may then conditionally reveal condition, mileage, fuel type, transmission, body type, engine
capacity, and registration details. After essentials are complete, Jev scores which eligible optional
follow-ups would materially improve the listing — for example mileage on a used registered Toyota.

It cannot ask an unregistered seller for a registration number (the visibility condition is false, so the
field is never offered), ask for a make outside the schema, or bypass required price/location fields.

### 5.4 Key UI states

- **Progress saved:** non-intrusive "Saved" status with the last saved time, alongside the explicit
  *Save as Draft* control.
- **Validation issue:** explain the problem next to the field, preserve the entered value, and move focus
  to the first invalid field on submit.
- **No more questions:** explain that there is enough information to draft the ad; the seller can still
  add optional details manually.
- **AI in progress:** cancellable, non-blocking. The seller can continue with photos or write manually.
- **AI unavailable:** "AI assistance is unavailable right now. You can still complete this ad manually."
  Never expose provider errors.
- **Stale result:** "Details changed after this suggestion was created. Review or regenerate it."
- **Draft resumed:** restore the latest saved stage, answers, and non-stale accepted content.
- **Schema changed:** the draft stays on its pinned version. A later edit may offer a migration preview;
  it must never silently delete existing answers.

## 6. Category schema requirements

### 6.1 Principle

The category schema is the source of truth for all seller questions and all structured public filters.
Neither the browser, nor Jev, nor the LLM may invent a persisted structured field.

The admin portal supports creating, reviewing, testing, publishing, deactivating, and versioning schemas.
Production schema changes require an audit event, a mandatory change note, and optimistic-concurrency
protection.

### 6.2 Field definition

| Property | Requirement |
|---|---|
| `key` | Stable machine key, e.g. `vehicle.model_year`. Immutable once used in a published schema. |
| `label`, `help_text` | English seller-facing text. Never raw LLM-generated labels. |
| `input_type` | One of `select`, `multi_select`, `radio`, `checkbox`, `text`, `textarea`, `number`, `money`, `year`, `date`, `boolean`. |
| `data_source` | Static options, approved reference dataset, or API lookup. A dynamic source must carry an `other` manual fallback if its data may be incomplete. |
| `required` | Boolean plus an optional conditional expression. |
| `visibility_condition` | Deterministic expression over seller answers only, e.g. show `registration_number` only when `registration_status = 'registered'`. |
| `validation` | Type, range, precision, length, allowed values, normalisation, and a server-side error code. |
| `step`, `display_order` | Where it appears in the seller experience. |
| `follow_up_eligible`, `follow_up_priority` | Whether the decision service may score it, and its business weight. Required fields are never follow-ups. |
| `filter_mapping` | Whether and how the value is exposed in public search. |
| `sensitivity` | `public`, `seller_private`, or `never_send_to_ai`. |
| `generation_use` | Whether it may be given to the copy generator, and how it should be phrased. |
| `triggers_remoderation` | Whether editing this field after approval sends the ad back to `pending` (R-4, OQ-14). |
| `deprecated_at` | Optional. Deprecated fields stay readable for existing drafts and published ads. |

### 6.3 Core fields

Category and subcategory · title · description · price amount, currency and negotiability · Province,
District and City · seller contact preference · at least one photo.

`title`, `description`, price, location, status, images, and attributes remain part of the existing
advertisement model. Accepted category answers are projected into typed `advertisement_attributes` rows
and validated against the schema version pinned to the draft.

### 6.4 Schema example: vehicle

```json
{
  "schema_version": 3,
  "category": "vehicles/cars",
  "fields": [
    {
      "key": "vehicle.make",
      "input_type": "select",
      "required": true,
      "data_source": "vehicle-makes",
      "follow_up_eligible": false,
      "filter_mapping": "make",
      "generation_use": "manufacturer"
    },
    {
      "key": "vehicle.model_year",
      "input_type": "year",
      "required": true,
      "validation": { "minimum": 1950, "maximum": "current_year_plus_1" },
      "filter_mapping": "year",
      "generation_use": "model year"
    },
    {
      "key": "vehicle.registration_status",
      "input_type": "radio",
      "options": ["registered", "unregistered"],
      "required": true,
      "generation_use": "registration status"
    },
    {
      "key": "vehicle.mileage_km",
      "input_type": "number",
      "required": false,
      "follow_up_eligible": true,
      "follow_up_priority": 90,
      "visibility_condition": "vehicle.registration_status = 'registered'",
      "filter_mapping": "mileage",
      "generation_use": "mileage"
    }
  ]
}
```

The server resolves `current_year_plus_1` at request time. Browser validation is a usability and
accessibility aid only; `listing-service` remains authoritative.

## 7. Decision service — TypeSafe Jev

### 7.1 What Jev is, and what that means for the design

Jev is a **System One** model: it evaluates typed questions against a state and returns calibrated,
machine-readable answers. It has exactly three primitives:

| Type | Returns |
|---|---|
| `noul` | a probability, 0–1 |
| `choice` | one option defined in the question's `criteria`, plus a full distribution and confidence |
| `score` | a weighted mean over 2–10 ordinal levels, plus a distribution and confidence |

It **cannot generate prose, code, or arbitrary values**, and it returns **only values defined in the
question schema**. Documented limits: ~64,000 token budget for state plus questions, 255 `choice` options,
2–10 `score` levels, 70–500 ms latency (typically ~100 ms), 1,200 requests/minute.

Two consequences drive this design:

1. **Jev cannot return "which questions to ask" as a list.** The server must enumerate the candidate
   questions itself and ask Jev to judge each one.
2. **Jev cannot count or do arithmetic.** All ranking, thresholding, and budget maths happens in
   `listing-service`.

### 7.2 Responsibility and boundary

Jev's job is to judge **how useful each eligible follow-up question would be**, given the answers so far.
It is advisory within a server-enforced boundary:

- It only ever sees questions `listing-service` chose to ask about.
- It never sees a question whose visibility condition is false, that is already answered, or that is not
  `follow_up_eligible` — such fields are never put in the request.
- It never returns a title, description, price, category, status, validation rule, or moderation outcome.
- It never receives account email, phone number, credentials, session tokens, exact private address, raw
  uploaded photos, or unpublished contact details.
- It is never called from the browser, and its API key never leaves the server.

The implementation uses a `QuestionDecisionProvider` interface so the product depends on an internal
contract rather than a vendor SDK, with a deterministic fake for tests. **TypeSafe ships Python and
JavaScript SDKs only**, so the Java implementation is a plain `RestClient` call against the documented
JSON API.

### 7.3 Request

`listing-service` builds the state from answers whose `sensitivity` permits decision use, and one `noul`
per eligible follow-up field plus one readiness question:

```json
{
  "model": "jev-latest",
  "state": {
    "category": ["vehicles", "cars"],
    "answers": {
      "vehicle.make": "Toyota",
      "vehicle.model": "Prius",
      "vehicle.model_year": 2016,
      "vehicle.registration_status": "registered",
      "location.district": "Colombo",
      "price.amount_cents": 875000000
    },
    "previously_skipped": []
  },
  "questions": {
    "vehicle__mileage_km": {
      "type": "noul",
      "instructions": "Would knowing the vehicle's mileage in km materially improve this listing for buyers, given `answers`?"
    },
    "vehicle__transmission": {
      "type": "noul",
      "instructions": "Would knowing the transmission type materially improve this listing, given `answers`?"
    },
    "vehicle__fuel_type": {
      "type": "noul",
      "instructions": "Would knowing the fuel type materially improve this listing, given `answers`?"
    },
    "ready_for_generation": {
      "type": "noul",
      "instructions": "Do `answers` already contain enough detail to write a strong, complete advertisement?"
    }
  }
}
```

Question ids replace `.` with `__` because the wire key must be a plain identifier; the adapter maps back
to field keys. All questions evaluate in parallel, so adding candidates barely changes latency.

### 7.4 Response and server-side selection

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "vehicle__mileage_km":   { "type": "noul", "noul": 0.94 },
    "vehicle__transmission": { "type": "noul", "noul": 0.71 },
    "vehicle__fuel_type":    { "type": "noul", "noul": 0.22 },
    "ready_for_generation":  { "type": "noul", "noul": 0.38 }
  },
  "usage": { "input_tokens": 210, "output_tokens": 31 }
}
```

`listing-service` then, entirely in code:

1. Discards any answer key it did not send.
2. Drops fields whose `noul` is below `decision_noul_threshold`.
3. Ranks the survivors by `noul × follow_up_priority`.
4. Truncates to `remaining_question_budget` — a finite, category-aware server configuration, visible in
   admin config and never hard-coded into the Next.js app.
5. If nothing survives, or `ready_for_generation` is high, proceeds to generation.

**What this design eliminates.** The draft specification required validation against unknown keys,
ineligible keys, already-answered keys, duplicate keys, over-budget results, and attempted control
values. None of those are possible here, because the server owns the question set and performs the
selection. The adapter validates only that each expected key returned with a probability in `[0, 1]`.

### 7.5 Decision algorithm and fallback

On every answer change, `listing-service`:

1. Resolves visibility and required conditions deterministically.
2. If a required field is unanswered or invalid, returns it to the UI. **Jev is not called.**
3. Builds the eligible optional set and computes the remaining budget.
4. Calls the `QuestionDecisionProvider`.
5. Applies §7.4's selection.
6. Presents the selected questions, or continues to generation.

If Jev times out, exceeds its retry policy, returns a malformed body, trips the circuit breaker, or is
disabled, the flow continues on this fallback:

1. Ask schema-defined essential recommended follow-ups still eligible and within the local budget.
2. If none are configured, proceed to generation with the answers already collected.
3. Record `decision_source = "fallback"` for observability. Never show vendor detail to the seller.

Documented Jev error codes handled explicitly: `401` (bad key — alarm, treat as disabled), `422`
(validation — log the shape, fall back), `429` (rate limited — backoff), `529` (overloaded — backoff).

A seller may skip any optional question. The skip is recorded and the question is not re-asked in the same
session unless the seller chooses **Add more details**.

### 7.6 Other uses of Jev in this flow

Because Jev returns only schema-defined values, it is also the right tool for two jobs the draft routed
through the LLM:

- **Enum and boolean attribute suggestions (§8.3)** — a `choice` question can only return a value listed
  in its `criteria`, making an out-of-schema value structurally impossible.
- **Content policy checks (§9)** — a battery of `noul` questions over seller and generated text produces a
  gate that code consumes, which is exactly what a System One model is for.

### 7.7 Admin controls

The management portal requires a **Post Ad Question Configuration** area with:

- category/subcategory schema version list and change history
- a field editor covering validation, conditions, `follow_up_eligible` and priority, AI sensitivity,
  filter mapping, and re-moderation triggers
- a visual test panel: pick a category, enter sample answers, inspect the resolved required set and
  eligible follow-ups, and test a decision response without touching a seller draft
- published/draft schema states with a mandatory change note on publication
- configurable per-category question budget, noul threshold, and fallback priorities
- a provider enable/disable kill switch, restricted to `super_admin`
- audit events for schema, policy, and provider-setting changes

## 8. LLM-assisted content

### 8.1 General rules

The LLM is a writing and suggestion service, not a system of record. It runs in `media-service`, reusing
the existing provider registry, versioned prompt registry, retry/repair runner, and two-tier JSON-schema
validation. It receives only a server-built whitelist of confirmed seller inputs permitted by
`generation_use` and `sensitivity`.

`media-service` returns **candidates**. `listing-service` validates and persists. `media-service` never
writes ad state — the same invariant the shipped OCR pipeline already obeys.

The LLM must return JSON validating against a strict schema. Free-form prose responses, tool calls that
modify data, and direct database writes are prohibited.

Every generated result carries `generation_id`, `source_version`, `source_answers_hash`, `prompt_version`,
an internally-retained provider/model identifier, and a status of `proposed`, `accepted`, `rejected`,
`stale`, or `failed`.

### 8.2 Title and description generation

From seller-confirmed category data plus optional seller notes, the service generates one concise title
candidate, one detailed scannable description candidate, and optionally a short list of missing-attribute
suggestions kept separate from the copy.

The prompt and the response validator enforce:

- Use only facts present in the approved input. Omit an unknown fact; never guess it.
- Never claim an item is "verified", "accident-free", "original", "warrantied", "brand new", "urgent", or
  "best price" unless the schema supplies that confirmed fact and policy permits the claim.
- Never invent mileage, condition, ownership history, registration details, amenities, salary, land
  extent, dimensions, location, seller identity, delivery, contact details, or offers.
- Never include phone numbers, email addresses, URLs, passwords, payment instructions, discriminatory
  language, prohibited-content claims, or instruction-like text drawn from untrusted seller input.
- Follow the category copy template. A vehicle description favours make/model/year, registration,
  mileage, transmission, fuel, condition, location, price and negotiability where confirmed.
- Generate Unicode-safe text.
- Respect server-configured maximum lengths (title ≤70, description ≤4000). **Nothing is silently
  truncated** — an invalid generation is discarded and retried, or shown as unavailable.

The preview states visibly: **"AI-generated draft — review all details before submitting."**

The seller may edit title and description directly; editing does not trigger another LLM call. Accepting a
draft writes into `advertisements.title` and `advertisements.description` only after server validation.

### 8.3 Attribute suggestions

Split by field type, which is stricter than a single LLM path:

| Field type | Route | Why |
|---|---|---|
| Enum, boolean | **Jev `choice`** | Can only return a value defined in the question's `criteria`. Out-of-schema values are impossible. Cap: 255 options |
| Number, text | LLM in `media-service`, then server validation | Free-form values cannot be enumerated in advance |

Each suggestion is a separate object:

```json
{
  "field_key": "vehicle.transmission",
  "proposed_value": "automatic",
  "evidence": "Seller note mentions automatic transmission.",
  "confidence": "medium"
}
```

Rules:

- `field_key` must exist in the draft's pinned schema and be eligible under its condition.
- The server validates and normalises `proposed_value` exactly as if the seller had typed it.
- The UI shows suggestions beside the relevant field with **Accept** and **Ignore**. It never
  auto-populates a confirmed answer.
- `confidence` is a review hint, never permission to write data.
- An LLM or Jev suggestion cannot satisfy a required field until the seller accepts it or enters a value.
- Suggestions resting on ambiguous text are excluded rather than guessed.
- Accept and ignore are both audited.

### 8.4 Content translations — **deferred**

Sinhala and Tamil advertisement content is **out of scope for this release**. It contradicts the locked
English-only MVP decision, and the draft's carve-out was not sufficient to override it.

Re-entry requires all of: a formal reversal of the English-only decision; Noto Sans Sinhala and Tamil font
loading in every client; and Sinhala/Tamil-capable moderators staffed against the 24-hour review promise
(NFR-6) — a translated ad must meet the same moderation standard in every language.

The data model leaves room for it: content locale variants are designed for but not built, so enabling
translation later adds rows rather than reshaping the advertisement aggregate.

### 8.5 Price recommendation — **deferred**

Evidence-based price guidance is **out of scope for this release** for a structural reason: a greenfield
marketplace has no corpus of comparable published ads, and guidance that is not grounded in real
comparables is exactly the thing this specification refuses to ship.

Re-entry is per category, once that category holds enough recently-published ads to meet a configured
comparator threshold. When it re-enters, the binding constraints are already settled: the range is
computed statistically from comparable ads by a versioned methodology, an insufficient-data state is
returned rather than a guessed range, the LLM may explain the numbers but may never compute or alter one,
and a recommendation never updates `price_amount_cents` automatically.

### 8.6 Failure and safety handling

- All generation runs through `listing-service` → `media-service`. Provider keys are server-only and never
  appear in a Next.js bundle.
- Per-seller and per-draft rate limits, idempotency keys, timeouts, retry with backoff, and a circuit
  breaker.
- Redacted request/response metadata is stored for troubleshooting. Seller notes, generated copy, PII, and
  provider credentials are never logged at info level.
- If a safety filter blocks a request or output, present a neutral manual-entry fallback and retain the
  seller's saved answers.
- Audit metadata must be sufficient to explain a moderation issue without retaining secrets or raw
  provider payloads beyond the configured retention period.

## 9. Content policy, submission and moderation

**Content policy.** Before submission, and again during moderation, seller-entered and generated text pass
a Jev `noul` battery: contact details, URLs, prohibited-content claims, discriminatory language, and
warranty or condition claims unsupported by the confirmed facts. A block preserves the draft and offers
correction guidance — it never discards work.

**Submission.** `POST /ads/{reference}/submit` performs full server-side validation against the draft's
pinned schema version, enforces the terms gate and the verified-email check (FR-3), and transitions
`draft → pending`. Nothing else may reach `pending`.

**Moderation.** The queue shows seller-confirmed content, structured attributes, photos, public location,
a clear AI-assisted marker with generation timestamp and source draft version, and accepted AI suggestions
distinguishable from direct seller entry in an audit view. Moderators have **approve and reject with a
reason code** — approval remains an independent human state transition, and no AI-assisted content is
exempt from it.

## 10. Data model additions

`advertisements`, `advertisement_attributes`, `categories` and the existing records remain the source of
truth. Added:

| Entity | Key fields | Purpose |
|---|---|---|
| `category_schema_versions` | id, category_id, version, schema_json, status, created_by, change_note, published_at | Immutable, versioned seller-question configuration |
| `ad_creation_sessions` | id, advertisement_id, schema_version_id, current_stage, question_budget_state, last_decision_source, started_at, completed_at | Resumable Post Ad state |
| `ad_creation_answer_events` | id, session_id, field_key, action, value_hash, source, created_at | Audit of answer, clear, skip, and accepted-suggestion actions |
| `content_generations` | id, advertisement_id, source_version, source_answers_hash, type, output_json, status, prompt_version, created_at | Title/description candidate history |
| `attribute_suggestions` | id, generation_id, field_key, proposed_value_json, evidence, confidence, source, status, resolved_at | Seller-reviewed attribute proposals. `source` distinguishes Jev from LLM |
| `question_decisions` | id, session_id, decision_source, request_fingerprint, result_json_redacted, policy_version, created_at | Decision trace with safe retention |
| `audit_events` | id, advertisement_id, actor, event_type, payload_redacted, created_at | Append-only. **New** — the draft assumed this existed; it did not |

Required constraints:

- unique `(category_id, version)` per schema version
- one published schema version per category
- ownership checks from every session and result to the seller-owned advertisement
- optimistic version checks on advertisement and schema updates (`05` §12)
- immutable audit events for decisions, suggestion acceptance/rejection, submission, moderation, publication

## 11. API contract

All endpoints follow `05-api-contract.md`: `/api/v1`, **snake_case fields and lower snake_case enums**, the
mandatory `{data, error, meta}` envelope, ads addressed by **`reference`** (`LL-NNNNN`), money as
`amount_cents`, version preconditions per §12, and idempotency keys per §13.

The creation-flow resource surface is specified in `05-api-contract.md` §8 under
*`listing-service` — AI-guided creation flow*, and the service-to-service generation endpoints under
*`media-service`*. `POST /ads`, `PATCH /ads/{reference}` and `POST /ads/{reference}/submit` are unchanged.

### 11.1 Example answer update

```http
PATCH /api/v1/ads/LL-49210/creation-flow/answers
If-Match: "7"
Idempotency-Key: 4be3...
Content-Type: application/json
```

```json
{
  "updates": [
    { "field_key": "vehicle.model_year", "value": 2016 },
    { "field_key": "vehicle.registration_status", "value": "registered" }
  ]
}
```

The response carries the new `version`, the updated resolved schema state, stale-result flags, and
`next_action`. It returns `409 VERSION_CONFLICT` on a stale precondition and `422 VALIDATION_FAILED` with
per-field `details` on validation failure.

### 11.2 Example next-question response

```json
{
  "data": {
    "reference": "LL-49210",
    "version": 8,
    "next_action": "ask_follow_ups",
    "questions": [
      {
        "key": "vehicle.mileage_km",
        "label": "Mileage (km)",
        "input_type": "number",
        "required": false,
        "help_text": "Helps buyers compare used vehicles."
      }
    ],
    "decision_source": "jev"
  },
  "error": null
}
```

The browser receives rendered field metadata only. It never receives internal prompts, provider
credentials, raw provider responses, safety policies, or unvalidated schema.

## 12. Security, privacy, and abuse controls

- Authenticate every seller mutation at the gateway and enforce advertisement ownership in the service.
- Keep Jev and LLM credentials in server-side secret storage; never in a Next.js bundle.
- Validate every client input against schema-version-aware models. **Treat AI output and decision output
  as untrusted input.**
- Rate limit draft creation, answer mutations, generation, and suggestion acceptance; return `429`.
- Use idempotency keys wherever an action creates a job or durable record.
- Correlation IDs, immutable audit events, provider-timeout metrics, and error alarms throughout.
- Separate public field data from seller-private data. Email, phone, exact address, login data and raw
  image bytes never enter an AI prompt or decision context.
- Sanitize free-text input, escape on output, and prevent prompt injection from seller notes altering
  generation system instructions.
- Define retention and deletion rules for generation metadata and decision records before production.

## 13. Accessibility, responsiveness, and performance

### 13.1 Accessibility

Semantic headings, labelled controls, keyboard-operable option lists, visible focus states, and announced
errors. Progress communicates current and completed stages without relying on colour alone. Conditional
questions announce themselves when revealed, and removed questions explain why their answers are no longer
used. AI labels, confidence indicators, and status badges all have textual equivalents. Mobile controls
meet touch-target minimums and never require drag-only interaction for question selection or photo
reordering.

### 13.2 Responsive behaviour

Desktop may show the stepper and a live ad preview side by side. Tablet keeps a persistent step indicator
with the preview below the form. Mobile uses a compact step header, one-hand-friendly controls, sticky
Continue/Back, and a preview sheet — and must not lose an entered answer when the keyboard opens or the
device rotates.

### 13.3 Service targets

- Schema resolution and answer persistence are responsive without any dependence on external AI services.
- Jev calls use a bounded timeout; a timeout falls back rather than blocking the stage.
- Generation is asynchronous and reports status without holding a request open.
- A seller can complete core draft creation with every optional AI integration disabled.
- Image upload is independent of generation, so a slow provider never interrupts photo handling.

## 14. Acceptance criteria

### 14.1 Core flow

- An unauthenticated visitor selecting Post Your Ad completes sign-in and returns to a new or resumed draft.
- Selecting Vehicles → Cars shows required vehicle questions from the pinned schema — make, model year,
  registration status, district, LKR price — in dependency order.
- A registered/unregistered selection reveals only fields whose schema condition is true.
- Changing category warns the seller, removes only incompatible answers after confirmation, retains valid
  core data, and marks prior AI results stale.
- Autosave persists valid answers, the explicit *Save as Draft* control works, and the seller can resume
  on another device session.

### 14.2 Decision service

- Jev is never called while a required resolved field is missing or invalid.
- A valid response asks a bounded subset of eligible optional questions in the configured order.
- A response containing an unexpected key, or a probability outside `[0, 1]`, is rejected and the local
  fallback is used.
- A timeout, `429`, `529`, malformed body, or disabled provider does not stop the seller reaching
  generation, preview, or submission — and does not corrupt a draft.
- A skipped optional question is not re-asked in the same session unless the seller selects
  *Add more details*.

### 14.3 AI content

- Given confirmed Toyota, Prius, 2016, registered, Colombo and Rs. 8,750,000, the generation service
  returns an editable title and description containing no unsupported claim.
- Generated copy is visibly labelled as AI-generated and cannot be submitted without seller review and
  server-side validation.
- A proposed attribute is not persisted until the seller selects Accept; invalid proposals are rejected by
  server validation; an enum suggestion out of schema range is structurally impossible.
- Any change to a source answer records a new draft version and marks dependent output stale rather than
  silently reusing it.

### 14.4 Moderation and security

- Submitted ads move to `pending` and do not appear in public search or detail endpoints until approved.
  A non-owner fetching one receives `404`, not `403`.
- An unverified-email seller cannot submit.
- The moderator sees AI-assisted markers and audit history, and performs the same approve/reject decision
  as for manually written ads.
- Browser network inspection confirms no provider key, raw prompt, private contact field, or exact address
  reaches client-side code.
- Repeated requests with the same idempotency key do not duplicate state changes.
- Ownership, schema validation, rate limit, version-conflict, and content-policy tests run in CI.

## 15. Delivery

Implementation sequencing, phase gates, risks and configuration surface are specified in
[`docs/product/ai-guided-post-ad-implementation-plan.md`](docs/product/ai-guided-post-ad-implementation-plan.md).

## 16. Remaining configuration decisions

To be set by the product owner before production; never baked into the frontend:

- per-category question budget, noul threshold, and which optional fields are fallback essentials
- ad expiry and renewal policy (OQ-07)
- whether phone verification is required before a seller's first submission
- final prohibited-category and content policy, and legal copy for Sri Lanka
- featured placement durations, prices, and payment gateway
- retention periods for AI and decision metadata, and any provider data-processing agreement
- confirmation of the photo limits set in §5.2

## 17. Design principles to preserve

1. **Schema before AI.** Required information, validation, and public filters come from the controlled
   category schema.
2. **AI is assistive.** Jev reduces unnecessary questions; the LLM improves copy and suggests data.
   Neither decides truth or publication.
3. **The server selects; the model only judges.** Enumerating candidates server-side is what makes an
   out-of-bounds decision structurally impossible rather than merely validated against.
4. **Seller owns the final ad.** Suggestions are explicitly reviewed and editable.
5. **Moderator owns publication.** Every new or materially edited ad follows the approval workflow.
6. **Graceful degradation.** A seller can always create a normal manual advertisement when any AI
   integration fails.
