# AI-Guided Post Ad Flow — Product & Engineering Specification

**Product:** LankaListings  
**Document status:** Ready for harness engineering  
**Scope:** Public Next.js Post Ad flow, FastAPI orchestration, `jev.dev` question-decision integration, content-generation and price-suggestion services  
**Companion documents:** `01-product-requirements.md`, `04-data-model.md`, `05-api-contract.md`, `08-decision-log.md`  
**Last updated:** 19 September 2026

## 1. Purpose

LankaListings is a Sri Lankan, broad classifieds marketplace. A standard advertisement is free, a featured placement is paid, and no ad can be publicly listed until an administrator approves it.

This specification defines the **AI-guided Post Ad flow** entered from the public site's **Post Your Ad** button. The flow must collect only the information needed for the selected category, allow `jev.dev` to decide whether additional follow-up questions are useful, and then produce an editable, accurate advertisement draft.

The feature must work across vehicles, property, land, jobs, electronics, services, home & garden, fashion, and other categories. It must not become a generic chatbot or allow an AI provider to control the marketplace's mandatory data, validation, pricing, or publication decisions.

## 2. Confirmed product decisions

| Area | Decision |
|---|---|
| Marketplace | Anyone with a LankaListings account may create an ad. |
| Authentication | Google sign-in and email/password are supported. The seller must be signed in before a draft is saved or submitted. |
| Market | Sri Lanka. Prices are LKR; location is Province → District → City. |
| Publication | An ad is never public on generation. Submission changes it to `PENDING_REVIEW`; a moderator must approve it before `PUBLISHED`. |
| Questions | A category schema defines the allowed, required, and conditional questions. `jev.dev` decides whether further eligible questions should be asked. |
| LLM output | The LLM may generate editable title and description drafts, suggest missing structured attributes from seller text, suggest a price range, and translate content into Sinhala and Tamil. |
| Seller control | Every AI result is a suggestion. The seller can edit, accept, reject, or ignore it. No AI result silently overwrites a seller answer. |
| UI language | The existing MVP user interface remains English. Sinhala and Tamil in this scope are advertisement-content translations, not full UI localisation. |

## 3. Goals and non-goals

### 3.1 Goals

- Let a first-time seller create a complete, high-quality ad without understanding every category-specific field upfront.
- Ask required questions deterministically, then use `jev.dev` to avoid unnecessary optional questions.
- Produce a useful title, a factual detailed description, and optional Sinhala/Tamil versions from the seller's confirmed details.
- Make price guidance evidence-based using comparable approved LankaListings ads; it is not a valuation guarantee.
- Preserve a structured data record so public filters such as vehicle make, year, district, and price work correctly.
- Give moderators visibility into seller-confirmed data and AI-assisted content without treating either as trusted publication approval.
- Keep the flow resilient: a `jev.dev`, LLM, translation, or price-service failure must not prevent a seller from completing and submitting an ordinary draft.

### 3.2 Non-goals

- A free-form chat agent that can ask arbitrary questions outside the category schema.
- Automatic advertisement publishing, automatic moderation approval, or automatic price selection.
- A claim that an AI-generated price is a certified valuation, a guarantee of sale, or financial advice.
- LLM processing of private contact information, account credentials, session tokens, exact private addresses, or unpublished image files.
- Replacing the separate admin image/OCR extraction feature.
- Full English/Sinhala/Tamil UI localisation in this release.
- Native mobile applications, buyer payments, escrow, auctions, or financing.

## 4. Definitions

| Term | Meaning |
|---|---|
| **Core question** | A marketplace-wide question required for every relevant ad, such as category, price, and location. |
| **Category schema** | Versioned, admin-managed configuration that defines fields, labels, validation, conditions, UI controls, and filter mapping for a category/subcategory. |
| **Eligible question** | A schema question whose condition is true, which is not yet answered, and which the seller is permitted to skip or must answer. |
| **Required question** | An eligible question that must be answered before the draft can advance or submit. `jev.dev` cannot omit it. |
| **Follow-up question** | An optional or conditional schema question selected after the required set. It may improve the ad, but is never invented outside the approved schema. |
| **Decision service** | The backend adapter around `jev.dev`. It returns whether the flow should ask zero or more eligible follow-up questions, or proceed to generation. |
| **Generation** | An LLM call that produces structured title/description candidates and optional attribute suggestions. |
| **Translation** | An LLM call that creates an editable Sinhala (`si`) or Tamil (`ta`) version of an already seller-approved source draft. |
| **Price recommendation** | A statistical range produced from comparable published ads. An LLM may explain it in plain language but must not invent the range. |
| **Draft version** | The optimistic-concurrency version and answer snapshot from which an AI result was made. |

## 5. User experience and flow

### 5.1 Entry and authentication

1. A visitor selects **Post Your Ad** from the header, mobile navigation, account area, or a category page.
2. If unauthenticated, the public app opens the existing Google or email/password authentication flow. On success, it returns the seller to the Post Ad flow without losing the intended action.
3. The system creates a server-owned `DRAFT` advertisement and an ad-creation session after the seller selects a category. A seller may abandon the flow and return to the saved draft later.
4. The flow identifies the selected category schema version and holds that version for the draft. Later schema edits must not change the questions or validation partway through a seller session.

### 5.2 Seller-facing stages

The UI must show a concise stepper. Field questions within a stage are displayed one at a time or in compact groups on mobile, without making every answer a separate full page.

| Stage | Purpose | Minimum behaviour |
|---|---|---|
| 1. Choose category | Select category and subcategory. | Show active categories only. Changing category later requires confirmation because category-specific answers can be removed. |
| 2. Essential details | Capture required core and category fields. | Render the category schema, honour conditions, validate immediately, and autosave completed answers. |
| 3. Smart follow-ups | Ask only eligible additional questions selected through the decision service. | Show why a question helps when available; always permit skipping optional questions. |
| 4. Photos and location | Add photos, set Province/District/City, and select approximate location where applicable. | Exact home address is never public by default. Images use the existing secure upload process. |
| 5. Generate and refine | Generate ad copy, suggestions, translations, and price guidance. | Clearly label AI output; seller must review/edit the final title and description. |
| 6. Contact, preview and submit | Confirm contact preferences, preview the listing, agree to terms, and submit. | Validate the whole draft server-side and transition only to `PENDING_REVIEW`. |

The user may move back to a completed stage. Moving back never discards saved answers. Any edit that changes the answer snapshot marks dependent AI output as **out of date** until it is regenerated or manually confirmed.

### 5.3 Vehicle example

For a seller choosing **Vehicles → Cars**, the schema must present the essential fields in a logical dependency order. A valid baseline sequence is:

1. Manufacturer / make
2. Model (filtered by make where data exists; support an `Other` value)
3. Model year
4. Registration status: `REGISTERED` or `UNREGISTERED`
5. District, then City where applicable
6. Asking price in LKR and `Negotiable` choice

The required schema may then require or conditionally reveal fields such as condition, mileage, fuel type, transmission, body type, engine capacity, and registration details. After essentials are complete, `jev.dev` can decide that zero, one, or several **eligible** optional follow-ups would materially improve the listing. For example, it may request mileage for a used registered Toyota or skip body type if a lower-quality entry would not benefit from it.

It may not ask an unregistered vehicle seller for a registration number, ask for a make that is not in the category schema, or bypass required price/location information.

### 5.4 Key UI states

- **Progress saved:** show a non-intrusive “Saved” status and the last saved time.
- **Validation issue:** explain the field problem next to the field, preserve the entered value, and move keyboard focus to the first invalid field on submit.
- **No more questions:** clearly explain that the system has enough information to create a draft; the seller can still add optional details manually.
- **AI in progress:** show a cancellable, non-blocking progress state. The seller can continue with photos or manually author an ad.
- **AI unavailable:** show “AI assistance is unavailable right now. You can still complete this ad manually.” Do not expose provider errors.
- **Stale result:** display “Details changed after this suggestion was created. Review or regenerate it.”
- **Draft resumed:** restore the latest saved stage, answers, and non-stale accepted content.
- **Schema changed:** retain the seller's draft against its original schema version. On a later edit, the API may offer a migration preview; it must never silently delete existing answers.

## 6. Category schema requirements

### 6.1 Principle

The category schema is the source of truth for all seller questions and all structured public filters. Neither the browser, `jev.dev`, nor the LLM is allowed to invent a persisted structured field.

The admin portal must support creating, reviewing, testing, publishing, deactivating, and versioning category schemas. Production schema changes require an audit event and optimistic-concurrency protection.

### 6.2 Field definition

Each field definition must include the following, even when its value is blank or inherited from the parent category:

| Property | Requirement |
|---|---|
| `key` | Stable machine key, e.g. `vehicle.modelYear`. It cannot be changed after it is used in a published schema. |
| `label` and `helpText` | English seller-facing text. Translation keys may be introduced later; do not use raw LLM-generated labels. |
| `inputType` | One of `SELECT`, `MULTI_SELECT`, `RADIO`, `CHECKBOX`, `TEXT`, `TEXTAREA`, `NUMBER`, `MONEY`, `YEAR`, `DATE`, or `BOOLEAN`. |
| `dataSource` | Static options, approved reference dataset, or API lookup. A dynamic data source must have an `Other`/manual fallback if its data may be incomplete. |
| `required` | Boolean plus an optional conditional expression. |
| `visibilityCondition` | Deterministic expression evaluated only from seller answers; e.g. show `registrationNumber` only when `registrationStatus = REGISTERED`. |
| `validation` | Type, range, precision, length, allowed values, normalisation, and server-side error code. |
| `step` and `displayOrder` | Where it appears in the seller experience. |
| `followUpEligibility` | Whether it can be selected by `jev.dev`, and its business priority. Required fields are not follow-ups. |
| `filterMapping` | Whether and how the value is exposed in public search/filtering. |
| `sensitivity` | `PUBLIC`, `SELLER_PRIVATE`, or `NEVER_SEND_TO_AI`. |
| `generationUse` | Whether it may be given to the copy generator and how it should be phrased. |
| `deprecatedAt` | Optional timestamp; deprecated fields remain readable for existing drafts and published ads. |

### 6.3 Core fields

The following are schema-controlled core fields:

- category and subcategory
- title (generated or entered; always seller-editable)
- description (generated or entered; always seller-editable)
- price amount, currency, and negotiability
- Province, District, and City
- seller contact preference
- at least one photo if the final category policy requires photos

`title`, `description`, price, location, status, images, and attributes remain part of the existing advertisement data model. Category answers are stored in `advertisement_attributes` and validated against the schema version attached to the draft.

### 6.4 Schema example: vehicle

```json
{
  "schemaVersion": 3,
  "category": "vehicles/cars",
  "fields": [
    {
      "key": "vehicle.make",
      "inputType": "SELECT",
      "required": true,
      "dataSource": "vehicle-makes",
      "followUpEligibility": false,
      "filterMapping": "make",
      "generationUse": "manufacturer"
    },
    {
      "key": "vehicle.modelYear",
      "inputType": "YEAR",
      "required": true,
      "validation": {"minimum": 1950, "maximum": "CURRENT_YEAR_PLUS_1"},
      "filterMapping": "year",
      "generationUse": "model year"
    },
    {
      "key": "vehicle.registrationStatus",
      "inputType": "RADIO",
      "options": ["REGISTERED", "UNREGISTERED"],
      "required": true,
      "generationUse": "registration status"
    },
    {
      "key": "vehicle.mileageKm",
      "inputType": "NUMBER",
      "required": false,
      "followUpEligibility": true,
      "followUpPriority": 90,
      "visibilityCondition": "vehicle.registrationStatus = 'REGISTERED'",
      "filterMapping": "mileage",
      "generationUse": "mileage"
    }
  ]
}
```

The database must validate the resolved numeric maximum for year at request time. The browser's validation is an accessibility and usability aid only; FastAPI remains authoritative.

## 7. `jev.dev` decision service

### 7.1 Responsibility and boundary

`jev.dev` is used as a **rule/schema decision engine**. Its task is to determine how many and which eligible follow-up questions should be asked after all currently required fields are complete.

The service is advisory within a strict server-enforced boundary:

- It may choose only question keys supplied by FastAPI as eligible candidates.
- It must never select a question whose condition is false, that is already answered, or that is not permitted as a follow-up.
- It must never return a title, description, price, category, status, validation rule, or moderation outcome.
- It must not receive account email, phone number, password data, session tokens, exact private address, raw uploaded photos, or unpublished ad contact details.
- It must not call the LLM directly from the browser or receive browser secrets.

The implementation must use a `QuestionDecisionProvider` adapter so the rest of the product depends on an internal contract rather than a `jev.dev` SDK or API shape. The adapter isolates future vendor changes and lets tests use a deterministic fake provider.

### 7.2 Request contract to the adapter

FastAPI constructs and validates the following minimum context. It sends only field values whose `sensitivity` permits decision use.

```json
{
  "requestId": "req_01...",
  "draftId": "ad_01...",
  "schemaVersion": 3,
  "categoryPath": ["vehicles", "cars"],
  "currentAnswers": {
    "vehicle.make": "Toyota",
    "vehicle.model": "Prius",
    "vehicle.modelYear": 2016,
    "vehicle.registrationStatus": "REGISTERED",
    "location.district": "Colombo",
    "price.amount": "8750000"
  },
  "eligibleFollowUpQuestionKeys": [
    "vehicle.mileageKm",
    "vehicle.transmission",
    "vehicle.fuelType",
    "vehicle.bodyType"
  ],
  "remainingQuestionBudget": 4,
  "previouslySkippedQuestionKeys": [],
  "decisionPolicyVersion": "post-ad-v1"
}
```

`remainingQuestionBudget` is a server configuration. It must be finite, category-aware, and visible in admin configuration; this prevents an external decision engine from creating a never-ending interview. The value is intentionally not hard-coded into the Next.js app.

### 7.3 Required response contract

```json
{
  "outcome": "ASK_FOLLOW_UPS",
  "questionKeys": ["vehicle.mileageKm", "vehicle.transmission"],
  "reasonCodes": ["IMPROVES_VEHICLE_DISCOVERY", "IMPROVES_DESCRIPTION"],
  "decisionReference": "jev_..."
}
```

Allowed outcomes are:

| Outcome | Meaning |
|---|---|
| `ASK_FOLLOW_UPS` | Ask the ordered, validated subset of eligible question keys. |
| `READY_FOR_GENERATION` | No useful follow-up is needed; proceed to photos/content generation. |
| `NEED_REQUIRED_FIELDS` | The backend has identified missing required questions. This outcome is recorded but the UI follows the local schema, not the returned field list. |

The FastAPI adapter must reject and log a safe diagnostic for a malformed outcome, duplicate key, ineligible key, over-budget result, unknown key, or attempted control value. It then uses the deterministic fallback.

### 7.4 Decision algorithm and fallback

The backend evaluates the category schema first on every answer change:

1. Resolve visibility and required conditions deterministically.
2. If a required field is unanswered or invalid, return that field to the UI. Do not call `jev.dev` yet.
3. Build the eligible optional-question set and calculate the remaining budget.
4. Call the `QuestionDecisionProvider` with the bounded context above.
5. Validate the response against the server's resolved schema.
6. Present its selected questions or continue to generation.

If `jev.dev` times out, returns an invalid response, exceeds its retry policy, or is disabled, the flow must continue using this fallback:

1. Ask any schema-defined essential recommended follow-ups that are still eligible and within the local budget.
2. If none are configured, proceed to generation with the answers already collected.
3. Record `decisionSource = FALLBACK` for observability, but do not show internal vendor information to the seller.

The seller can skip an optional question. The backend records the skip and prevents the same session from re-asking it unless the seller explicitly selects **Add more details**.

### 7.5 Admin controls

The Vite React admin portal requires a **Post Ad Question Configuration** area with:

- category/subcategory schema version list and change history
- field editor with validation, conditions, `followUpEligibility`, business priority, AI sensitivity, and filter mapping
- a visual test panel: select a category, enter sample answers, inspect resolved required and eligible follow-ups, and test a decision-provider response without modifying a seller draft
- published/draft schema states and a mandatory change note on publication
- configurable per-category question-budget policy and fallback priorities
- provider enable/disable control restricted to administrators
- audit events for schema, policy, and provider-setting changes

## 8. LLM-assisted content requirements

### 8.1 General rules

The LLM is a writing and suggestion service, not a system of record. It may receive only a server-created whitelist of confirmed seller inputs that are allowed by `generationUse` and `sensitivity`.

The LLM must return JSON that validates against a strict response schema. Free-form prose responses, tool calls that can modify data, and direct writes to the database are prohibited.

Every generated result must carry:

- `generationId`
- `sourceDraftVersion`
- `sourceAnswersHash`
- `promptTemplateVersion`
- provider/model identifier retained internally for audit and troubleshooting
- status: `PROPOSED`, `ACCEPTED`, `REJECTED`, `STALE`, or `FAILED`

### 8.2 Title and description generation

The service accepts seller-confirmed category data and optional seller notes, then generates:

- one concise title candidate
- one detailed, scannable description candidate
- an optional short list of missing-attribute suggestions, separately from the copy

The prompt and response validator must enforce the following content rules:

- Use only facts present in the approved input. Omit an unknown fact; never guess it.
- Do not state that an item is “verified,” “accident-free,” “original,” “warrantied,” “brand new,” “urgent,” or “best price” unless the schema supplies that confirmed fact and policy permits the claim.
- Do not invent mileage, condition, ownership history, registration details, amenities, salary, land extent, dimensions, location, seller identity, delivery, contact details, or offers.
- Do not include phone numbers, email addresses, URLs, passwords, payment instructions, discriminatory language, prohibited-content claims, or instruction-like text from untrusted seller inputs.
- Follow the category copy template. For example, a vehicle description should favour make/model/year, registration, mileage, transmission, fuel, condition, location, price/negotiability, and photos where confirmed.
- Generate Unicode-safe text. It must support English, Sinhala, and Tamil scripts without transliteration unless the seller asks for transliteration in a future feature.
- Respect server-configured maximum lengths for title and description. The server truncates nothing silently; an invalid generation is discarded and retried or shown as unavailable.

The preview must visibly state: **“AI-generated draft — review all details before submitting.”**

The seller can edit the title and description directly. Editing generated copy does not require another LLM call. Accepting a generated draft writes it into the normal `advertisements.title` and `advertisements.description` fields only after server validation.

### 8.3 Missing-attribute suggestions

The LLM may inspect seller-provided free text and propose values for schema fields that are still empty. It must return each suggestion as a separate object:

```json
{
  "fieldKey": "vehicle.transmission",
  "proposedValue": "AUTOMATIC",
  "evidence": "Seller note mentions automatic transmission.",
  "confidence": "MEDIUM"
}
```

Rules:

- `fieldKey` must exist in the draft's category schema and be eligible under its condition.
- The backend validates and normalises `proposedValue` exactly as if the seller typed it.
- The UI displays suggestions beside the relevant field with **Accept** and **Ignore** actions; it never auto-populates a confirmed answer.
- `confidence` is a review hint, not a permission to write data.
- If a field is required, an LLM suggestion cannot satisfy it until the seller explicitly accepts it or enters a value.
- Suggestions based only on ambiguous text must be excluded rather than guessed.

### 8.4 Content translations

After the seller approves or edits the source content, the UI offers **Create Sinhala version** and **Create Tamil version**. Translation is optional; the seller may publish only the base-language version.

- `en`, `si`, and `ta` are stored as explicit BCP-47-style content codes in the domain model.
- A translation uses the currently approved source title/description and the structured facts, never an earlier stale draft.
- The translated title and description are editable before the seller includes them in the submission.
- The UI identifies the source language and target language. It must not represent a translated draft as reviewed or moderator-approved.
- A source-content edit marks dependent translations stale. The seller must regenerate, edit/confirm, or remove them before submission.
- Search may index approved public translations where product policy permits. The primary published content remains deterministic and must meet the same moderation rules in every language.

### 8.5 Price recommendation

Price guidance must be grounded in LankaListings data, not a model's general knowledge.

1. A **Price Intelligence** service retrieves comparable, currently or recently published marketplace ads using a category-specific matching strategy: category/subcategory, location granularity, relevant attributes, and time window.
2. It removes invalid/outlier records according to a documented, versioned statistical method.
3. If the configurable minimum number and quality of comparable records is not met, the service returns `INSUFFICIENT_DATA`; no numeric range is shown.
4. If sufficient data exists, it returns a lower range, typical range, upper range, comparator count, comparison factors, and a data-as-of date. Currency is LKR.
5. The LLM may produce a short explanation from those calculated results. It must not calculate, change, or add any number to the range.

The seller sees the range as guidance, e.g. **“Comparable approved ads suggest Rs. X–Y. Your final price remains your choice.”** They can keep their entered price, change it, or ignore the recommendation. A recommendation never updates `price_amount` automatically.

The first implementation must be able to turn price guidance off per category until sufficient marketplace data exists.

### 8.6 Failure and safety handling

- Generation, translation, and price calls run through FastAPI; API keys remain server-only.
- Use per-seller and per-draft rate limits, an idempotency key, timeout, retry/backoff, and circuit-breaker policy.
- Store redacted request/response metadata for troubleshooting. Do not log seller notes, generated copy, PII, or provider credentials at info level.
- If an LLM safety filter blocks a request or output, present a neutral manual-entry fallback and retain the seller's saved answers.
- The system must record enough audit metadata to explain a moderation issue without retaining secrets or private raw-provider payloads longer than the configured retention policy.

## 9. Data model additions

The existing `advertisements`, `advertisement_attributes`, `categories`, and `audit_events` records remain the source of truth. Add the following entities or equivalent relational structures.

| Entity | Key fields | Purpose |
|---|---|---|
| `category_schema_versions` | id, category_id, version, schema_json, status, created_by, change_note, published_at | Immutable, versioned seller-question configuration. |
| `ad_creation_sessions` | id, advertisement_id, schema_version_id, current_stage, question_budget_state, last_decision_source, started_at, completed_at | Resumable Post Ad state. |
| `ad_creation_answer_events` | id, session_id, field_key, action, value_hash, source, created_at | Audit of answer, clear, skip, and accepted-suggestion actions. Raw answer duplication is not required. |
| `content_generations` | id, advertisement_id, source_version, source_answers_hash, type, language, output_json, status, prompt_version, created_at | Title/description and translation candidate history. |
| `attribute_suggestions` | id, generation_id, field_key, proposed_value_json, evidence, confidence, status, resolved_at | Seller-reviewed LLM attribute proposals. |
| `price_recommendations` | id, advertisement_id, source_version, status, range_low, range_typical, range_high, comparator_count, methodology_version, data_as_of, created_at | Auditable, evidence-based market guidance. |
| `question_decisions` | id, session_id, provider_reference, decision_source, request_fingerprint, result_json_redacted, policy_version, created_at | Decision-provider trace with safe retention. |
| `advertisement_content_locales` | advertisement_id, language_code, title, description, source_generation_id, status, version | Seller-confirmed content variants. |

Required constraints:

- unique `(category_id, version)` for a schema version
- unique active/published schema selection per category
- unique `(advertisement_id, language_code)` for current content locale
- foreign-key or equivalent ownership checks from every session/result to the seller-owned advertisement
- optimistic version checks on advertisement, schema configuration, and content-locale updates
- immutable audit events for decisions, AI suggestion acceptance/rejection, submission, moderation, and publication

## 10. API contract additions

All endpoints live under `/api/v1`, use camelCase JSON, return the latest draft version after a mutation, and require the authenticated seller to own the draft. Existing `/me/advertisements` draft and submission endpoints remain valid.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/me/advertisements` | Create a `DRAFT` ad after category selection; response includes `creationSession`. |
| `GET` | `/me/advertisements/{id}/creation-flow` | Return resolved stage, schema snapshot, saved answers, pending/stale AI results, and next required or follow-up questions. |
| `PATCH` | `/me/advertisements/{id}/creation-flow/answers` | Validate, persist, clear, or skip answers using an `If-Match`/version precondition. |
| `POST` | `/me/advertisements/{id}/creation-flow/next-questions` | Resolve required fields and invoke the decision service when eligible. No client-supplied question keys are trusted. |
| `POST` | `/me/advertisements/{id}/content-generations` | Start an asynchronous title/description generation request. |
| `GET` | `/me/advertisements/{id}/content-generations/{generationId}` | Read the seller's own generation status/result. |
| `POST` | `/me/advertisements/{id}/attribute-suggestions/{suggestionId}/accept` | Validate and explicitly apply a proposed field value. |
| `POST` | `/me/advertisements/{id}/attribute-suggestions/{suggestionId}/ignore` | Record seller rejection/ignore. |
| `POST` | `/me/advertisements/{id}/translations` | Start an asynchronous `si` or `ta` translation from the current source content. |
| `PATCH` | `/me/advertisements/{id}/content-locales/{languageCode}` | Seller edits/accepts a translated content variant. |
| `POST` | `/me/advertisements/{id}/price-recommendations` | Calculate or retrieve current grounded price guidance for an eligible category. |
| `POST` | `/me/advertisements/{id}/submit` | Perform complete server-side schema/content validation and move draft to `PENDING_REVIEW`. |

### 10.1 Example answer update

```http
PATCH /api/v1/me/advertisements/ad_123/creation-flow/answers
If-Match: "7"
Idempotency-Key: 4be3...
```

```json
{
  "updates": [
    {"fieldKey": "vehicle.modelYear", "value": 2016},
    {"fieldKey": "vehicle.registrationStatus", "value": "REGISTERED"}
  ]
}
```

The response includes `draftVersion`, the updated resolved schema state, stale-result flags, and `nextAction`. It returns `409` on an out-of-date version and `422` with `fieldErrors` for validation failures.

### 10.2 Example next-question response

```json
{
  "draftId": "ad_123",
  "draftVersion": 8,
  "nextAction": "ASK_FOLLOW_UPS",
  "questions": [
    {
      "key": "vehicle.mileageKm",
      "label": "Mileage (km)",
      "inputType": "NUMBER",
      "required": false,
      "helpText": "Helps buyers compare used vehicles."
    }
  ],
  "decisionSource": "JEV"
}
```

The browser receives the rendered field metadata only. It never receives internal prompts, provider credentials, full provider responses, private safety policies, or unvalidated schema data.

## 11. Administration and moderation requirements

### 11.1 Admin configuration

Administrators must be able to:

- manage category-schema versions and preview the seller flow
- configure required/conditional fields and `jev.dev` follow-up eligibility
- configure field sensitivity so private fields are excluded from AI/decision payloads
- configure per-category AI-copy availability, translation availability, and price-guidance availability
- set content templates, banned claims/terms, lengths, and current prompt-template version through controlled configuration
- manage approved vehicle make/model reference data and static select options
- view aggregate usage, failure rate, fallback rate, stale-generation rate, and price-insufficient-data rate without exposing seller content by default

### 11.2 Moderator review

The moderation queue must show:

- seller-confirmed primary content and language variants
- structured attributes, photos, and public location
- a clear marker that content was AI-assisted, with generation timestamp and source draft version
- accepted AI attribute suggestions distinguishable from direct seller entry in an audit view
- price guidance only as historical seller assistance; it must not bias the moderator into treating the suggested price as verified value
- all normal reject/request-change/remove controls and mandatory reasons

Moderators cannot publish automatically generated content without normal review. A moderator's approval remains an independent state transition.

## 12. Security, privacy, and abuse controls

- Authenticate every seller mutation and enforce advertisement ownership at the service layer.
- Keep LLM, `jev.dev`, and pricing-provider credentials in server-side secret storage; never include them in Next.js bundles.
- Validate every client input in FastAPI using schema-version-aware models. Treat AI output and decision-provider output as untrusted input.
- Use rate limits for draft creation, answer mutations, generation, translation, and price requests; return `429` with a safe retry message.
- Use idempotency keys for actions that can create jobs or modify state. A retry must not create duplicate generation or recommendation records.
- Support request correlation IDs, immutable audit events, provider-timeout metrics, and error alarms.
- Separate public field data from seller-private data. Do not include email, phone, exact address, login data, or raw image bytes in AI prompts or decision contexts.
- Apply a content-policy check on seller-entered and AI-generated content before submission and again during moderation. A block must preserve the draft and offer manual correction guidance.
- Sanitize rich/free-text input, escape it on output, and prevent prompt injection from seller notes from changing the generation system instructions.
- Define retention and deletion rules for generation metadata, decision records, and price comparator snapshots before production launch. The live service must honour account/deletion obligations.

## 13. Accessibility, responsiveness, and performance

### 13.1 Accessibility

- The wizard uses semantic headings, labelled controls, keyboard-operable option lists, visible focus states, and error announcements.
- Progress communicates current stage and completed stages without relying on colour alone.
- Conditional questions announce themselves when revealed; removed questions explain why their answers are no longer used.
- AI labels, price guidance disclaimers, confidence indicators, and status badges have textual equivalents.
- Mobile controls meet appropriate touch targets and do not require drag-only interaction for question selection or photo reordering.

### 13.2 Responsive behaviour

- Desktop may show the stage stepper and a live ad preview side-by-side.
- Tablet retains a clear persistent step indicator while placing preview below forms as needed.
- Mobile uses a compact step header, one-hand-friendly controls, sticky Continue/Back controls, and a preview sheet. It must not lose an entered answer when the keyboard opens or the device rotates.

### 13.3 Initial service targets

Targets must be verified under realistic load before launch and monitored after release:

- local schema resolution and answer persistence are responsive without dependence on external AI services
- `jev.dev` calls use a bounded timeout; timeout falls back instead of blocking the stage
- generation, translation, and price work can be asynchronous and report status without holding the request open indefinitely
- a seller can continue core draft creation when every optional AI integration is disabled
- image upload remains independent from the generation request so a slow provider does not interrupt photo handling

## 14. Acceptance criteria

### 14.1 Core flow

- An unauthenticated visitor selecting Post Your Ad completes Google or email/password sign-in and returns to a new or resumed draft flow.
- Selecting Vehicles → Cars shows required vehicle questions from the active schema, including make, model year, registration status, district, and LKR price in an appropriate dependency order.
- A registered/unregistered selection correctly reveals only fields whose schema condition is true.
- Changing the category warns the seller, removes only incompatible answers after confirmation, retains valid core data, and marks prior AI results stale.
- Autosave persists valid entered answers, and a seller can resume the draft on another supported device/account session.

### 14.2 Decision service

- The API never calls `jev.dev` while a required resolved schema field is missing or invalid.
- A valid `jev.dev` result can ask a bounded subset of eligible optional questions and shows them in the configured order.
- A result that includes an unknown, already answered, ineligible, duplicate, or over-budget key is rejected by FastAPI and the local fallback is used.
- A `jev.dev` timeout or outage does not stop the seller from reaching generation, preview, or submission.
- An optional skipped question is not asked again in the same normal flow unless the seller selects Add more details.

### 14.3 AI content and price guidance

- Given confirmed Toyota, Prius, 2016, registered, Colombo, and Rs. 8,750,000 data, the generation service returns an editable title and description that contain no unsupported claim.
- Generated title/description is visibly labelled as AI-generated and cannot be submitted without normal seller review and server-side validation.
- A proposed attribute from seller text is not persisted until the seller selects Accept; invalid proposals are rejected by server validation.
- The seller can create, edit, accept, remove, or regenerate Sinhala and Tamil content variants. A base-content change marks them stale.
- Price guidance is shown only when the comparable-data threshold is met. It shows comparator information and date, never overwrites seller price, and provides an insufficient-data state when data is inadequate.
- Any change to a source answer or content records a new draft version and marks dependent output stale rather than silently reusing it.

### 14.4 Moderation and security

- Submitted ads move to `PENDING_REVIEW`; they do not appear in public search or detail endpoints until approved.
- The moderator can see AI-assisted markers and audit history but must perform the same approval/rejection/request-changes decision as for manually written ads.
- Browser network inspection confirms that no provider key, raw prompt, private contact field, or exact private address is sent to client-side code or external AI services.
- Repeated create/generate/accept requests with the same idempotency key do not duplicate state changes.
- Ownership, schema validation, rate limit, version-conflict, and content-policy tests run in CI.

## 15. Harness implementation slices

Build and review these as small vertical slices. No later slice may assume an unvalidated AI output is trusted.

| Slice | Deliverable | Definition of done |
|---|---|---|
| 1. Versioned schema foundation | Category schema version entity, admin read path, FastAPI resolver, public field renderer. | Unit/integration tests cover required/conditional field resolution and invalid schema rejection. |
| 2. Resumable draft wizard | Auth return path, DRAFT creation, answer save/skip, optimistic versioning, mobile flow. | Seller can create/resume a vehicle draft with server-side validation and autosave. |
| 3. `jev.dev` adapter | Internal provider contract, request/response validation, policy/budget, deterministic fake, fallback. | Contract tests prove invalid/timeout provider results cannot block or corrupt a draft. |
| 4. Copy generation | Async job, strict structured output, preview/edit/accept states, stale detection. | Test fixtures prove no unsupported fields are persisted and seller edits are retained. |
| 5. Attribute suggestions | Field-specific suggestions, accept/ignore actions, audit entries. | Suggestions cannot satisfy a required field or bypass schema validation without explicit seller acceptance. |
| 6. Price intelligence | Comparable-ad query, methodology/version, range/insufficient-data response, disclaimer UI. | Tests cover no-data, outlier, category mismatch, and no automatic price replacement. |
| 7. Translations | Content locale store, `si`/`ta` generation, edit/confirm/stale behaviour. | Unicode/script, source-version, and moderation visibility tests pass. |
| 8. Admin, moderation, hardening | Schema test console, metrics, audit view, rate limits, privacy/content controls. | E2E covers draft → pending review → moderator approval and public visibility. |

## 16. Remaining configuration decisions before production

These values should be configured by the product owner and recorded in the decision log before production launch; the implementation must not bake them permanently into the frontend:

- question budget per category and which optional fields count as fallback essentials
- photo/file limits and ad expiry/renewal policy
- whether phone verification is required before a seller's first submission
- final prohibited-category/content policy and legal copy for Sri Lanka
- featured placement durations/prices and payment gateway
- price-comparator eligibility window, minimum-comparator threshold, and outlier methodology
- retention periods for AI/decision metadata and any provider-specific data-processing agreement
- whether approved public translation variants should be indexed and shown in search by default

## 17. Design principles to preserve

1. **Schema before AI:** required information, validation, and public filters come from the controlled category schema.
2. **AI is assistive:** `jev.dev` reduces unnecessary questions; the LLM improves copy and suggests data; neither decides truth or publication.
3. **Seller owns the final ad:** suggestions are explicitly reviewed and editable.
4. **Moderator owns publication:** every new or materially edited ad still follows the existing approval workflow.
5. **Graceful degradation:** a seller can always create a normal manual advertisement when any AI integration fails.
