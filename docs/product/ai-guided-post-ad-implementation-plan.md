# Implementation Plan: AI-Guided Post Ad Flow

## Document Control

| Field | Value |
|---|---|
| Product | LankaListings |
| Implements | [09-ai-guided-post-ad-spec.md](../../09-ai-guided-post-ad-spec.md) (draft → v2 in Phase 0) |
| Status | Approved for execution |
| Version | 1.0 |
| Date | 2026-09-19 |
| Decision engine | `jev-latest` via `api.typesafe.ai` (TypeSafe System One) |
| Content generation | Media service (FastAPI), existing LLM provider registry |
| Transactional owner | Listing service (Spring Boot) — new |
| Identity | Identity service (Spring Boot) — forked from an existing auth service |
| Edge | Gateway service (Spring Cloud Gateway) — new |
| Primary client | `frontend-web` (Next.js 14, App Router) |
| Database | PostgreSQL 17, database-per-service |

This plan is the engineering counterpart to the spec. The spec states *what* the capability must do; this
document states *how* it will be built, in what order, and how each phase is verified. Where the two
disagree, **Phase 0** is the reconciliation pass and the spec is corrected to match.

## Context

The public site's **Post Your Ad** button is decorative. `frontend-web` is four files — one static
homepage whose "Sign In" and "Post Your Ad" buttons have no handler and no route. There is no user, no
session, no ownership, and no consumer-facing write path anywhere in the platform.

What *does* exist is substantial and reusable:

- `media-service` (FastAPI) — an LLM provider registry (`openai_compatible` / `gemini` / `anthropic` /
  `fake`), a versioned on-disk prompt registry, a retry/repair runner with attempt and deadline budgets,
  two-tier JSON-schema validation, an OCR provider stack, a content-hash-deduplicated media store, a
  durable lease/heartbeat/reaper job queue, an `advertisements` table with the full status lifecycle, the
  nine-slug category catalog, and a pytest harness that runs against real PostgreSQL.
- `management-portal` (Vite + React) — a complete operator tool with a typed API client, TanStack Query,
  and MSW-backed tests.
- An existing Spring Boot **auth service** with RS256 JWT issuance, refresh-token rotation with reuse
  detection, HttpOnly cookie transport, CSRF, Flyway, and Testcontainers integration tests.

This plan turns the decorative button into a working AI-guided ad-creation flow: a seller signs in,
picks a category, answers the questions that category actually requires, is asked a *bounded* set of
follow-ups chosen by a decision model, gets an editable AI-written title and description, reviews every
suggestion, and submits into the existing moderation queue.

The core invariant is unchanged and non-negotiable: **only an `active` advertisement is publicly
readable, and no machine-generated advertisement becomes `active` without a human moderator approving
it.** AI produces candidates; people produce listings.

## Confirmed Decisions

| Decision | Choice |
|---|---|
| Transactional owner | **`listing-service` (Spring Boot)** owns the Advertisement aggregate, status machine, category schema, and submit transition — matches D-18 |
| Identity | **`identity-service`**, forked into the platform from the existing auth service; roles remapped to this project's |
| Edge | **`gateway-service`** (Spring Cloud Gateway) — single browser origin, authentication + coarse route-level role gates |
| Decision engine home | **`listing-service`** calls Jev directly (plain `RestClient`; no Java SDK exists) |
| Content generation home | **`media-service`** returns *candidates*; `listing-service` validates and persists — honours D-17 |
| v1 scope | **Core guided flow only.** Price intelligence and si/ta translations deferred with re-entry criteria |
| Category schemas | **All nine categories, full depth** — resolves OQ-04 |
| UI | **Full public flow regenerated, desktop + mobile**, one canonical stepper — resolves OQ-03 |
| Gate 1 | Bypassed; the blocking open questions are resolved inside Phase 0 and recorded as decisions |
| Java platform | Java 17, Spring Boot 3.5.16, Gradle, Flyway, Testcontainers — inherited from the auth service, previously undecided |
| Token distribution | RS256. `identity-service` signs with `private.pem`; gateway and services verify with `public.pem` only |

## Target Topology

```
  frontend-web (Next.js :3000)        management-portal (Vite :5173)
              │                                    │
              └──────────── gateway-service ───────┘
                          (single origin, CORS,
                           authn + route role gates)
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
 identity-service            listing-service              media-service
   (Spring Boot)              (Spring Boot)                 (FastAPI)
  accounts · roles         ads · status machine        LLM copy candidates
  Google OAuth             category schema             attribute extraction
  RS256 issuance           Jev decisions               images · derivatives
  sessions · CSRF          moderation state            OCR
        │                           │                           ▲
   identity DB                listing DB                        │
                                    └──── candidates ───────────┘
                                    │
                           api.typesafe.ai (jev-latest)
```

Authorization is enforced **twice by design**: the gateway performs authentication and coarse
route-level role gating; every service independently enforces resource-level authorization (ownership,
state preconditions). Gateway-only enforcement would leave any service reachable inside the network
unprotected.

## Phases at a Glance

Phases 0–3 are strictly sequential. Phase 4 (schema authoring) runs in parallel with Phase 5 once
Phase 3 fixes the schema contract. Phases 6–8 each require Phase 5's wizard shell.

| Phase | Delivers | Key gate |
|---|---|---|
| **0** Spec reconciliation ✅ | Spec v2, API-contract amendment, eight OQ resolutions | **Done** — spec v2 committed; `05` gained §12/§13 and the creation-flow surface; 8 OQs resolved through the trichotomy (37 → 29 open); grep confirms zero `PENDING_REVIEW`/camelCase/`/me/advertisements`/`jev.dev` left in the spec |
| **1** UI generation | Canonical stepper, AI component vocabulary, versioned Stitch prompt library, full flow desktop + mobile | Every screen and state in the inventory has an exported design |
| **2A** `identity-service` ✅ | Fork, role remap, Google OAuth, email verification, response envelope | **Done** — `./gradlew test`: **73 tests**, 0 failures |
| **2B** `gateway-service` ✅ | Single origin, cookie-aware token resolution, route × role table | **Done** — `./gradlew test`: 11 tests, 0 failures. CORS consolidated; identity-service's own CORS now opt-in |
| **3** `listing-service` + schema engine | Service skeleton, Advertisement aggregate, `LL-NNNNN`, versioned schema resolver | Required/conditional resolution correct; invalid schema rejected at load |
| **4** Nine category schemas | Full-depth schemas + reference datasets for all nine categories | Every category is postable end to end; schemas pass the resolver's validator |
| **5** Resumable draft wizard | `frontend-web` bootstrap, sessions, autosave, Save as Draft, stages 1/2/4/6 | Create, abandon, resume on another device, submit — no answer lost |
| **6** Jev decision adapter | Provider interface, batched noul call, server-side ranking, fallback, stage 3 UI | Timeout, 429, 529 and malformed responses cannot block or corrupt a draft |
| **7** Copy generation | `ad_copy/v1` prompt family, async job, stale detection, stage 5 UI | No unsupported claim persists; seller edits always survive |
| **8** Attribute suggestions | Jev `choice` for enums, LLM for numeric/free text, accept/ignore, audit | A suggestion cannot satisfy a required field without explicit acceptance |
| **9** Policy, submit, moderation | Content-policy noul battery, submit transition, AI-assisted markers, `audit_events` | Submitted ads reach `pending` and never appear in public reads |
| **10** Admin question console | Schema versions, field editor, decision test panel, budget policy, kill switch | An admin changes follow-up eligibility without touching code |

---

## Phase 0 — Spec Reconciliation (no code)

The draft spec contradicts the discovery pack in eighteen places and contains one design that cannot be
implemented. Phase 0 fixes all of it before a line of code or a UI prompt is written.

### 0.1 Rewrite §7 around Jev's actual primitives — **blocking**

The draft asks the decision engine to return
`{"outcome": "ASK_FOLLOW_UPS", "questionKeys": [...], "reasonCodes": [...]}`. Jev cannot do this. It
"cannot generate prose, code, or arbitrary values" and "returns only values defined in your schema". It
answers typed questions against a state using exactly three primitives:

| Type | Returns |
|---|---|
| `noul` | probability 0–1 |
| `choice` | one schema-defined option + full distribution + confidence |
| `score` | weighted mean over 2–10 ordinal levels + distribution + confidence |

**Replacement design.** `listing-service` enumerates the eligible follow-up fields itself and asks one
`noul` per field in a single batched call — all questions evaluate in parallel, so latency is roughly
constant regardless of count (70–500 ms, typically ~100 ms):

```json
{
  "model": "jev-latest",
  "state": {
    "category": ["vehicles", "cars"],
    "answers": { "vehicle.make": "Toyota", "vehicle.model": "Prius",
                 "vehicle.model_year": 2016, "vehicle.registration_status": "registered",
                 "location.district": "Colombo", "price.amount_cents": 875000000 }
  },
  "questions": {
    "vehicle__mileage_km":   { "type": "noul",
      "instructions": "Would knowing the vehicle's mileage in km materially improve this listing for buyers, given `answers`?" },
    "vehicle__transmission": { "type": "noul", "instructions": "..." },
    "vehicle__fuel_type":    { "type": "noul", "instructions": "..." },
    "ready_for_generation":  { "type": "noul",
      "instructions": "Do `answers` already contain enough detail to write a strong, complete advertisement?" }
  }
}
```

The server then does the arithmetic — Jev explicitly "cannot count reliably", so **all math stays in
code**: rank by `noul × follow_up_priority`, drop anything below a configured threshold, truncate to
`remaining_question_budget`.

**What this deletes.** §7.3's entire validation list — unknown keys, ineligible keys, already-answered
keys, duplicates, over-budget results — becomes *structurally impossible*, because the server owns the
question set and performs the selection. The adapter validates only that each expected answer key
returned and each probability is in `[0, 1]`. §7.4's deterministic fallback survives unchanged.

**What must never be asked of Jev.** Validation ranges, visibility conditions, required-field
resolution, price comparisons, and date arithmetic all stay deterministic in the schema resolver. Jev is
documented as poor at dates, math comparisons, negations and indirection.

### 0.2 Reconcile the wire contract

`05-api-contract.md` §10 requires new conventions land in `05` *before* they are used. Amend `05` first,
then the spec.

| Spec draft | Resolution |
|---|---|
| camelCase fields, `SCREAMING_ENUMS` | **snake_case fields, lower snake_case enums** — `05` §4 calls this "the single most likely FE↔BE drift point" |
| Bare response bodies | **`{data, error, meta}` envelope**, mandatory |
| `422` with `fieldErrors` | `422 VALIDATION_FAILED` with `details: [{field, code, message}]` |
| `/me/advertisements/{id}`, `ad_123` | `/me/ads`, `/ads/{reference}` — **`LL-NNNNN` reference in URLs** (D-23) |
| `"price.amount": "8750000"` string rupees | **`amount_cents` integer minor units** (D-21) |
| `DRAFT` / `PENDING_REVIEW` / `PUBLISHED` | **`draft` / `pending` / `active` / `rejected` / `expired` / `sold`** |
| `If-Match` / `Idempotency-Key` / `draftVersion` | Add to `05` as platform conventions, then use |

### 0.3 Restore the dropped commitments

The draft silently drops five existing requirements. All are restored:

- **FR-3** — email verified before an ad can be published.
- **FR-13** — explicit *Save as Draft* and *Save as Draft & Exit*, alongside autosave.
- **FR-14** — terms gate and the locked 24-hour moderation copy at submit.
- **FR-15** — deferrable featuring upsell.
- **FR-33 / R-3** — moderators have **approve and reject only**. The draft's "request changes" control
  does not exist and is removed.

### 0.4 Resolve the blocking open questions

These are live `⏳ open` rows in `.forge/project-prd-signals.md`, **not** in the reconstructed
`08-decision-log.md`. Each is resolved through the three-write procedure in `.claude/rules/prd.md`:
fold the answer into `project-prd.md`'s body, move the row from `project-prd-signals.md` to
`project-prd-history.md` `## Resolved Open Questions`, and append a `### Rev N` block to
`project-prd-history.md` `## Revisions`.

Because Gate 1 was bypassed by product-owner decision, each resolution is annotated
**"resolved by product-owner decision, 2026-09-19, outside the Gate 1 ritual"** rather than being
promoted into `CLAUDE.md § Architecture Decisions`, whose own rule is "do not promote a row here until
its gate confirms it".

| OQ | Question | Resolution |
|---|---|---|
| **OQ-02** | Is AI ad intake in MVP scope? | **Yes** for seller-guided creation. Newspaper OCR intake stays separate and already shipped |
| **OQ-03** | Which post-ad stepper is correct? | **One canonical stepper, fixed in Phase 1A.** Blocks every UI prompt |
| **OQ-04** | Attribute schemas for the eight non-Vehicle categories | Authored in full in Phase 4 |
| **OQ-12** | Photo count, size cap, formats | Fixed here; consumed by Phase 5 |
| **OQ-13** | Rejection reason codes | Reuse the set `media-service` already serves at `/advertisements/rejection-reasons` |
| **OQ-14** | Which fields trigger re-moderation on edit | Marked per field in the category schema (`triggers_remoderation`) |
| **OQ-21** | Confirm the five-service split | Confirmed, **plus `gateway-service`** as edge infrastructure, not a sixth business service |
| **OQ-23** | Database engine | **PostgreSQL 17**, database-per-service |
| **OQ-25** | Async transport | Reuse `media-service`'s proven DB-backed lease queue rather than introducing a broker |
| **OQ-30** | Attribute modelling | **Versioned schema document** is the source of truth; values project into typed, filterable attribute rows |

### 0.5 Record the deferrals

Removed from v1 with explicit re-entry criteria, not silently dropped:

- **Price intelligence** — a greenfield marketplace has no comparable published ads. Re-enters per
  category when that category holds enough recently-published ads to meet the configured threshold.
- **Sinhala / Tamil ad content** — contradicts **D-07 (LOCKED: English-only MVP)**. Re-enters only via a
  formal D-07 reversal, which must also cover Noto Sans Sinhala/Tamil loading and si/ta-capable
  moderator staffing against the 24-hour promise (NFR-6).
- **Mobile (Expo) parity** — D-11/D-27 make mobile an MVP surface, but the posting flow ships web-first.
  Recorded as a known gap, not a cancellation.

### 0.6 Outputs

`09-ai-guided-post-ad-spec.md` v2 · `05-api-contract.md` amendment (§12 concurrency, §13 idempotency,
creation-flow resource surface) · seven OQ resolutions through the PRD trichotomy · a `### Rev` entry in
`project-prd-history.md`. **Gate:** no contradiction remains between the spec and `04`/`05`/`08`.

> **Harness note.** The enforcement hooks (`guard-prd-shape`, `guard-spec-approval`,
> `guard-plan-approval`, `guard-spec-leapfrog`) are wired in `lankalistings-harness/.claude/settings.json`
> and do not load for a session rooted at the repository root. The rules they enforce are followed by
> hand; nothing blocks a violation mechanically.

### 0.7 Phase 0 outcome ✅

| Deliverable | Evidence |
|---|---|
| `05` §12 optimistic concurrency, §13 idempotency, creation-flow surface | `73a539e` |
| Eight OQs resolved through the trichotomy | `40b509c` — signals 37 → **29** open rows; 8 rows in history; Rev 1 appended |
| Spec v2 | `2c88b35` |
| Contract compliance | `grep` for `PENDING_REVIEW`, `PUBLISHED`, `/me/advertisements`, `ad_123`, camelCase JSON keys, SCREAMING enums and `jev.dev` across the spec: **0 matches each** |

**Deviations from the plan as written:**

1. **OQ resolution targeted the wrong file.** The plan said "amend `08-decision-log.md`". `08` is a
   *reconstructed* discovery document; the live OQ register is `.forge/project-prd-signals.md`, and
   `.claude/rules/prd.md` mandates a three-write procedure across the PRD trichotomy. Corrected before
   execution — `08` was left untouched.
2. **Work moved onto a feature branch.** `git-conventions.md` forbids committing to `main`; the plan's
   first commit (`73e2c90`) had already landed there, matching the repo's actual practice across all ten
   prior commits. Left in place; everything from `a9d4f18` onward is on `feature/ai-guided-post-ad`.
3. **OQ-23 was resolved too**, beyond the seven the plan listed — PostgreSQL 17 was already the de-facto
   answer in `media-service`, and leaving it open while confirming database-per-service was incoherent.
4. **Two product values were set, not merely recorded**: the six-stage stepper (OQ-03) and the photo
   limits (OQ-12). Both were blocking Phase 1. The photo limits are flagged in the PRD as *"set to unblock
   delivery — cheap to change, worth a product-owner confirmation"*.

---

## Phase 1 — UI Generation

The five existing `post_your_ad_*` Stitch exports are unusable as a baseline: three different steppers
(5 steps vs 4, three label sets, `w-4`/`w-8`/`w-10` dots), two competing mobile progress bars on one
screen, and only one screen has a mobile variant at all. Nothing AI-related exists anywhere.

### 1A — Canonical decisions

1. **Lock one stepper** (resolves OQ-03). Every screen uses the same component, the same step count, and
   the same labels.
2. **Screen × breakpoint × state inventory** — the complete list before any prompt is written.
3. **Extend the design system with the AI vocabulary** that does not exist today:

| Component | Notes |
|---|---|
| Suggestion card | Proposed value beside its field, with evidence line and confidence indicator |
| Accept / Ignore | Dual action; nothing auto-populates. Accept is reversible |
| Stale badge | New amber variant on the `tertiary` family — `bg-tertiary/10 text-on-tertiary-container` |
| AI disclosure | Reuses the existing `bg-primary-fixed/30` info block verbatim |
| Generation skeleton | No loading state exists anywhere in the exports today |
| Follow-up question card | With sub-progress ("2 of 3") and a visible Skip |
| AI error / retry | The `error` token is currently only used for form validation |

Existing tokens are unchanged: Manrope + Inter, emerald `#006c49` CTA, 8px radius, Material Symbols
Outlined, `max-w-[1280px]`. Noto Sans Sinhala/Tamil is **not** needed in v1 — translations are deferred.

### 1B — Prompt library

One versioned prompt per screen, committed to the repo so designs are reproducible. Each pins
project `14253969128473213455` and design system `assets/da83d34188364f7da095902cb850087c` (public) —
`assets/c2cef0c71ff64a189816cb03bf394c84` for Phase 10's admin screens.

### 1C — Generate

Desktop and mobile for each stage:

| Stage | Status |
|---|---|
| 1. Choose category | Regenerate — fixes stepper drift |
| 2. Essential details | Regenerate |
| 3. **Smart follow-ups** | **New** |
| 4. Photos & location | Regenerate — only existing mobile screen |
| 5. **Generate & refine** | **New** |
| 6. Contact, preview & submit | Regenerate — merges two conflicting existing designs |

Plus state variants: AI in progress · AI unavailable · stale result · suggestion accept/ignore · draft
resumed · validation error · submitted confirmation.

### 1D — Export and review

Export, review against the design-quality checklist, iterate, commit to `stitch_advertising/`.

---

## Phase 2A — `identity-service`

Forked into the platform as a new repo. The original stays untouched as a reusable starter.

**Inherited as-is:** Java 17 / Spring Boot 3.5.16 / Gradle, RS256 JWT with `RsaKeyLoader`, refresh-token
rotation with SHA-256 + pepper hashing and **reuse detection with family revocation**, HttpOnly cookie
transport, CSRF (`XSRF-TOKEN` / `X-XSRF-TOKEN`), BCrypt strength 12, account lock/disable, session list
and revoke, `GlobalExceptionHandler`, Flyway, Testcontainers. The `users` table already carries
`email_verified` and an optimistic-locking `version` column.

**Role remap** — the fork carries education-domain roles that must become this project's:

| Was | Becomes | Grants |
|---|---|---|
| `STUDENT` *(default)* | **`member`** *(default)* | Create and own drafts, submit ads |
| `TEACHER` | **`moderator`** | Moderation queue, approve/reject |
| `ADMIN` | **`super_admin`** | Schema config, provider kill switch, user and category admin |

Touch points: `RoleName`, `RoleJwtAuthenticationConverter`, `AuthService` default-role assignment, and
the role migrations. Because the fork is a new repo with **no production data**, the `V2`/`V4` baseline
migrations are rewritten rather than patched by a forward remap — otherwise `TEACHER` lives in the schema
history permanently.

**To build:**

- `oauth_identities` + **Google OAuth exchange** (entirely absent from the fork; required by D-18 and
  spec §2).
- **Email verification flow** — the column exists, nothing writes it. FR-3 depends on it.
- `{data, error, meta}` response envelope — the fork returns bare bodies and would drift from the other
  four services.
- Remove per-service CORS; the gateway owns it (see 2B).

### 2A outcome so far

| Delivered | Evidence |
|---|---|
| Fork into its own repo, gitignored by the root like the other four services | `identity-service` @ `89d6ecd`, 95 files, no `*.pem` tracked |
| Package `com.al.authservice` → `lk.lankalistings.identity` | `89d6ecd` |
| Roles remapped, `MEMBER` default, wire form single-sourced in `RoleName.toWire` | `89d6ecd` |
| Real Dockerfile replacing the IntelliJ stub that ran `top` on `ubuntu:latest` | `89d6ecd` |
| Context-load test given its own container | `65a34b3` |
| Google sign-in: `oauth_identities`, ID-token verification, link-or-create | `9d7b0df` |
| **Suite green** | `./gradlew test` → **64 tests, 0 failures, 0 errors, 0 skipped** |

**Two findings worth carrying forward.**

1. *The inherited context test was fragile.* `IdentityServiceApplicationTests` had no Testcontainers, so
   it connected to whatever PostgreSQL the developer happened to be running. It passed on machine state,
   not on code. The port change surfaced it; it now owns a container like every other test here. Worth
   checking for the same shape when `listing-service` is scaffolded from this template.
2. *A piped exit code hid a real failure.* The first run reported exit 0 while Gradle had actually
   printed `BUILD FAILED` — `tail` was swallowing the status. Test commands in this plan capture
   `PIPESTATUS` explicitly so a green claim means the build was green.
3. *A second bean of a framework type breaks injection everywhere.* Publishing Google's decoder as a
   `JwtDecoder` made the security filter chain's by-type injection ambiguous and took down every
   context-loading test at once. Framework types with existing beans get their own wrapper type, not
   a qualifier. `listing-service` will hit the same trap when it adds its own decoder for verifying
   identity's tokens.
4. *Test seams beat bean overriding.* `spring.main.allow-bean-definition-overriding` supplied through
   `@DynamicPropertySource` is read too late in the bootstrap. A distinct bean name marked
   `@Primary` needs no flag and no ordering assumption.
5. *Repeated Gradle runs exhaust memory.* One full-suite run was killed for low memory after several
   daemons accumulated. `--no-daemon --max-workers=1` is the safe form for repeated verification on
   this machine.

### The envelope, done once across both services ✅

| Delivered | Evidence |
|---|---|
| `{data, error, meta}` on every identity-service response; snake_case wire; `SCREAMING_SNAKE` error codes | identity `298bc1d` — **64 tests** |
| Same envelope on gateway 401/403, wired into *both* `exceptionHandling` and `oauth2ResourceServer` | gateway `b888c61` — **14 tests** |

**Three contract corrections fell out of the migration**, none of which were the shape change itself:

1. *Field validation is 422, not 400.* `05` §3 reserves 400 for `MALFORMED_REQUEST` — a body that
   could not be parsed — and 422 for one that parsed but failed validation. The service had
   conflated them, so an unreadable body and an invalid email returned the same code.
2. *`fieldErrors` map → `details` array* of `{field, code, message}`, which is what lets a client
   attach each error to the input that caused it.
3. *Detail field names are converted to the wire form.* Bean validation reports `firstName`; the
   client sent `first_name`. Reporting the Java spelling would leave a client unable to match an
   error to its field — the entire purpose of per-field details.

**Finding: snake_case turned several assertions vacuous.** Five `findValues("passwordHash")`-style
lookups across two test classes were searching for keys that can no longer exist. Four of them
asserted *emptiness*, so they went on reporting green while verifying nothing — and what they
assert is that no password hash or raw token leaks in a response. Only the one asserting a positive
count failed loudly. **A renaming change makes every "assert absent" test a candidate for silent
rot**; `listing-service` should sweep for this when it adopts the envelope.

### Email verification ✅ — 2A complete

| Delivered | Evidence |
|---|---|
| `email_verification_tokens`, digest-only storage, purpose-separated hash | identity `03d02a3` |
| Link issued at registration; Google-created accounts skip it (Google vouched) | `03d02a3` |
| `email_verified` claim in the access token, so `listing-service` enforces FR-3 without calling back | `03d02a3` |
| **Suite green** | **73 tests**, 0 failures, 0 errors |

**Three decisions to preserve.**

1. *Resend always answers 204* — whatever the address. Reporting "no such account" would make the
   endpoint an account-enumeration oracle against the marketplace. The cost is silence for a seller
   who mistypes their address; the alternative is handing out a membership list.
2. *Expired is distinguished from invalid* (410 vs 400), which is the **opposite** of the login path.
   On a login, distinguishing causes confirms an address exists. On a verification link the holder
   already proved they received our email, so "this expired, request a new one" leaks nothing and is
   the difference between a seller retrying and giving up.
3. *Issuing a new link retires outstanding ones*, so a forwarded earlier email stops working at once.

Delivery sits behind `VerificationEmailSender` because the transactional email provider is still
**OQ-29**. The logging stand-in is loud by design: a service that silently fails to send looks, to an
operator, exactly like one where nobody clicks the links.

**Two findings.**

- *`@ConditionalOnMissingBean` does not work on a scanned `@Component`.* It is only reliable inside
  auto-configuration; on a component it evaluates before other beans are known and excludes itself.
  This was made **twice** in one session — first on the Google decoder, then on the email sender —
  so the reason is now written into the class doc. A default implementation is displaced by
  registering a `@Primary` one, not by a conditional.
- *`ddl-auto: validate` earns its keep.* A `CHAR(64)` column reports as `bpchar` and fails validation
  against a `String` mapping, taking the whole suite down at context start rather than surfacing as
  a subtle oddity in production. Use `VARCHAR` for hash columns, matching
  `authentication_sessions.refresh_token_hash`.

**Phase 2 is complete.** Next is Phase 3, `listing-service` and the schema engine.
The envelope is the largest — a new wrapper, a rewritten exception handler, a correlation-ID filter,
Jackson snake_case, and roughly 35 `jsonPath` assertions — and the gateway must emit the same shape for
its own 401/403 rejections, so there is a case for doing it once across both services after 2B.

---

## Phase 2B — `gateway-service`

**Spring Cloud Gateway** on the same Java 17 / Boot 3.5.16 / Gradle template. It verifies tokens with
`identity-service`'s `public.pem` via `oauth2-resource-server`, so no new auth mechanism is introduced.

| Route | Target | Requires |
|---|---|---|
| `/api/v1/auth/**` | identity | anonymous |
| `/api/v1/ads/**`, `/api/v1/categories/**` | listing | anonymous (read) |
| `/api/v1/me/**` | listing | `member` |
| `/api/v1/media/**` | media | `member` |
| `/api/v1/admin/moderation/**` | admin | `moderator` \| `super_admin` |
| `/api/v1/admin/schemas/**`, `/admin/providers/**` | admin | `super_admin` |

**Two constraints that shape the implementation:**

1. **Cookie path preservation.** Tokens travel as HttpOnly cookies, not `Authorization` headers, and the
   `refresh_token` cookie is scoped to path `/api/v1/auth`. The gateway must resolve bearer tokens from
   the cookie and **must not rewrite that path prefix** — doing so silently breaks refresh.
2. **CORS consolidates here.** Per-service CORS is removed, or browsers receive duplicated and
   conflicting headers. This also fixes the cross-origin cookie problem that host-only cookies would
   otherwise create across four ports.

Gateway does authentication and coarse role gating only. Ownership and state preconditions remain the
services' responsibility.

### 2B outcome ✅

| Delivered | Evidence |
|---|---|
| `gateway-service` on Spring Cloud **2025.0.0** (the Boot 3.5 train), starter `spring-cloud-starter-gateway-server-webflux` | `gateway-service` @ `163bab5` |
| Cookie-first bearer resolution, falling back to the header for service-to-service callers | `163bab5` |
| Route × role table with the narrow `super_admin` rules above `/admin/**` | `163bab5` |
| Correlation-ID filter at the edge (05 §7) | `163bab5` |
| CORS consolidated; identity-service's own CORS now opt-in via `CORS_ENABLED` | `b1b1558` |
| **Suites green** | gateway **11 tests**, identity **64 tests**, 0 failures across both |

**Both silent-failure constraints are encoded in code, not just in this plan.**

- *No `StripPrefix` on any route.* The `refresh_token` cookie is scoped to `/api/v1/auth`; rewriting
  the prefix would stop the browser sending it, and refresh would fail looking like an expired
  session rather than a misconfiguration.
- *CORS in exactly one place.* Duplicate `Access-Control-Allow-Origin` headers are rejected outright
  by browsers, so identity-service registers no CORS configuration unless explicitly switched on.

**The ordering guard is the test that matters most.** Spring evaluates authorisation matchers in
declaration order, so `/api/v1/admin/**` sits *below* the three narrower `super_admin` rules. Moving
it up would silently hand schema and provider control to every moderator;
`aModeratorReachesModerationButNotSchemaOrProviderControl` is what fails if anyone does.

**Note on the starter name.** Spring Cloud renamed `spring-cloud-starter-gateway` when the WebMVC
variant landed; the WebFlux suffix is required on this train. Worth checking before scaffolding any
further Spring Cloud component.

---

## Phase 3 — `listing-service` and the Schema Engine

New Spring Boot service on the auth-service template.

- **Advertisement aggregate** and status machine `draft → pending → active | rejected`, plus `expired`
  and `sold`. Public `LL-NNNNN` reference (D-23). Hidden ads return **404, not 403** (D-24).
- **`category_schema_versions`** — immutable, versioned. A draft pins its schema version at creation, so
  a later schema edit cannot change the questions or validation mid-session.
- **Deterministic resolver** — visibility conditions, required conditions, validation (type, range,
  precision, length, allowed values, normalisation), `follow_up_eligibility` + priority, `sensitivity`
  (`public` / `seller_private` / `never_send_to_ai`), `generation_use`, `filter_mapping`,
  `triggers_remoderation`.
- **Attribute projection** (resolves OQ-30) — the schema document is the source of truth; accepted
  values project into typed attribute rows so public filters keep working.

**Gate:** unit and integration tests cover required/conditional resolution and invalid-schema rejection
at load time.

---

## Phase 4 — Nine Category Schemas ⚠️ critical path

Full-depth schemas for **Vehicles** (cars, motorcycles, three-wheelers, vans/buses/lorries),
**Property**, **Land**, **Jobs**, **Electronics**, **Services**, **Home & Garden**, **Fashion**, and
**Other** — matching the nine locked slugs already in `media-service`'s category catalog.

Includes the reference datasets the schemas depend on: vehicle makes and models (with an `Other` manual
fallback wherever the data may be incomplete), property types, land extent units, job families.

This is a **content-authoring project, not an engineering one**, and Phases 5–9 all consume its output.
It is the single largest schedule risk in this plan. Mitigation: author in a reviewable format against
the Phase 3 validator from day one, and build Phase 10's preview console early enough to review schemas
visually rather than as raw documents.

---

## Phase 5 — Resumable Draft Wizard

Bootstraps `frontend-web` from four files. This phase is closer to "build the public site" than "add a
wizard" — size it accordingly.

- Routing, an envelope-aware API client with a typed `ApiError`, cookie + CSRF auth integration
  (`credentials: "include"`), and TanStack Query — mirroring the pattern already proven in
  `management-portal`.
- `ad_creation_sessions`: resolved stage, answer snapshot, question-budget state, last decision source.
- Answer save / clear / skip with optimistic version preconditions; autosave **and** explicit
  *Save as Draft* (FR-13).
- Photo upload against `media-service`, independent of any AI request so a slow provider never blocks
  photo handling.
- Implements Phase 1 stages **1, 2, 4, 6** (the non-AI stages) at both breakpoints.

**Gate:** create a draft, abandon it, resume on a different device session, and submit — with no answer
lost and no silent overwrite.

---

## Phase 6 — Jev Decision Adapter

- `QuestionDecisionProvider` interface with three implementations: `JevDecisionProvider` (plain
  `RestClient` — **TypeSafe ships Python and JavaScript SDKs only**), a deterministic
  `FakeDecisionProvider` for tests, and `FallbackDecisionProvider`.
- Batched `noul`-per-eligible-field plus `ready_for_generation`, as designed in 0.1.
- State filtered by `sensitivity` — never account email, phone, password data, session tokens, exact
  address, or raw image bytes.
- Server-side ranking, thresholding and budget truncation.
- Redacted `question_decisions` trace with `decision_source` (`jev` | `fallback`) for observability.
- Bounded timeout, retry with backoff, circuit breaker. Documented Jev error codes: `401`, `422`, `429`,
  `529`.
- Skipped questions are recorded and not re-asked in the same session unless the seller chooses
  *Add more details*.
- Implements Phase 1 stage **3**.

**Gate:** contract tests prove that a timeout, a `429`, a `529`, a malformed body, or a disabled provider
cannot block the seller from reaching generation, preview, or submission — and cannot corrupt a draft.

---

## Phase 7 — Copy Generation

- New prompt family **`ad_copy/v1`** in `media-service`, distinct from the newspaper `ad_extraction/v1`
  family (that one is page → many candidates; this is one seller → one ad). Reuses the existing runner,
  repair loop, two-tier validation, and prompt-version registry.
- Cross-service contract: `listing-service` → `media-service` returns **candidates only**;
  `listing-service` validates and persists. Async job with status polling, on the existing DB-backed
  lease queue.
- `content_generations` carries `source_version`, `source_answers_hash`, `prompt_version`, provider and
  model identifiers, and status `proposed` / `accepted` / `rejected` / `stale` / `failed`.
- **Stale detection**: any edit that changes the answer snapshot marks dependent output stale rather than
  silently reusing it.
- Implements Phase 1 stage **5**: AI label, inline edit, accept, regenerate, in-progress, unavailable,
  stale.

**Gate:** fixtures prove no unsupported field is persisted and seller edits are always retained. An
invalid generation is discarded and retried or shown as unavailable — never silently truncated.

> **Evidence from Phase 1.** Both mockup generations that had to write listing copy invented banned
> claims — service history, inspection records, import provenance, a "94% battery health" figure, and the
> words *genuine*, *verified* and *well-maintained* — and the second did so **in a prompt that explicitly
> named the rule**. Writing plausible trust signals is the model's default for this genre.
>
> Two consequences for this phase: the §8.2 response validator is **load-bearing rather than
> defence-in-depth**, and prompt wording alone cannot be relied on. The banned-claims check runs as a Jev
> `noul` battery against the confirmed facts (§7.6) — a gate code consumes. The two real failures above
> become the seed fixtures for its test set.

---

## Phase 8 — Attribute Suggestions

Split by field type, which is stricter than the draft spec's single LLM path:

- **Enum and boolean fields** → Jev **`choice`**. The model can only return a value defined in the
  question's `criteria`, so an out-of-schema value is structurally impossible. (Cap: 255 options.)
- **Numeric and free-text fields** → LLM in `media-service`, then normalised and validated server-side
  exactly as if the seller had typed it.

Rules enforced server-side: nothing auto-populates; `confidence` is a review hint, never a permission to
write; a suggestion cannot satisfy a required field until the seller explicitly accepts it or types a
value; ambiguous evidence is excluded rather than guessed. Accept and ignore are both audited.

---

## Phase 9 — Policy, Submit, Moderation

- **Content policy** — a Jev `noul` battery over seller-entered *and* generated text: contact details,
  URLs, prohibited-content claims, discriminatory language, and warranty/condition claims unsupported by
  the confirmed facts. This is a gate that code consumes, which is exactly what a System One model is
  for. A block preserves the draft and offers correction guidance.
- **Submit** — full server-side schema validation against the draft's pinned schema version, terms gate
  and the 24-hour copy (FR-14), verified-email check (FR-3), transition to `pending` only.
- **Moderation** — seller-confirmed content, structured attributes, photos, public location, an
  AI-assisted marker with generation timestamp and source draft version, and accepted AI suggestions
  distinguishable from direct seller entry in the audit view. Approve and reject only.
- **`audit_events`** — the spec calls this existing; it is not. Built here as an immutable append-only
  record of decisions, suggestion acceptance/rejection, submission, moderation, and publication.
- Rate limits, idempotency keys, and correlation-ID propagation across all mutation paths.

**Gate:** submitted ads reach `pending` and never appear in public search or detail endpoints. Browser
network inspection confirms no provider key, raw prompt, private contact field, or exact address reaches
client-side code.

---

## Phase 10 — Admin Question Console

In `management-portal`, behind the `super_admin` gate:

- Category schema version list and change history, with mandatory change notes on publication.
- Field editor: validation, conditions, `follow_up_eligibility` and priority, AI sensitivity, filter
  mapping, re-moderation trigger.
- **Visual decision test panel** — pick a category, enter sample answers, inspect the resolved required
  set and eligible follow-ups, and test a decision-provider response without touching a seller draft.
- Per-category question-budget policy and fallback priorities.
- Provider enable/disable kill switch.
- Metrics: usage, failure rate, fallback rate, stale-generation rate — without exposing seller content
  by default.

---

## Config Surface

```
# Gateway
GATEWAY_PORT, JWT_PUBLIC_KEY_LOCATION, CORS_ALLOWED_ORIGINS
ROUTE_IDENTITY_URI, ROUTE_LISTING_URI, ROUTE_MEDIA_URI, ROUTE_ADMIN_URI

# Identity (inherited + new)
DB_*, JWT_PRIVATE_KEY_LOCATION, JWT_PUBLIC_KEY_LOCATION, REFRESH_TOKEN_PEPPER
COOKIE_SECURE, COOKIE_DOMAIN
GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET, GOOGLE_OAUTH_REDIRECT_URI
EMAIL_VERIFICATION_TTL, MAIL_*

# Listing
DB_*, JWT_PUBLIC_KEY_LOCATION
JEV_API_KEY, JEV_BASE_URL, JEV_MODEL, JEV_ENABLED
JEV_TIMEOUT_MS, JEV_MAX_RETRIES, JEV_CIRCUIT_BREAKER_*
DECISION_NOUL_THRESHOLD, DECISION_BUDGET_DEFAULT, DECISION_BUDGET_PER_CATEGORY
MEDIA_SERVICE_BASE_URL, MEDIA_SERVICE_TIMEOUT_MS

# Media (existing + new)
AD_COPY_PROMPT_VERSION, AD_COPY_MAX_TITLE_LEN, AD_COPY_MAX_DESCRIPTION_LEN
```

Provider credentials are server-side only and never reach a Next.js bundle.

---

## Risks

| Severity | Risk | Mitigation |
|---|---|---|
| **HIGH** | Phase 4 is a nine-category content project with no product input yet, and Phases 5–9 all consume it | Author against the Phase 3 validator from day one; pull Phase 10's preview console forward |
| **HIGH** | `frontend-web` is four files — Phase 5 is effectively building the public site | Size it as a bootstrap, not a feature; reuse `management-portal`'s proven client patterns |
| **MEDIUM** | Gateway route config becomes a single point of failure for access control | Integration test every route × role × anonymous combination; keep service-level authz independent |
| **MEDIUM** | New cross-service seam (listing ↔ media) | T3 cross-runtime contract tests; media returns candidates only and never writes ad state |
| **MEDIUM** | Identity fork carries education-domain roles | Rewrite the baseline migrations; no production data exists to strand |
| **MEDIUM** | Jev caps `choice` at 255 options | Only affects Phase 8 enum suggestions; large enums fall back to the LLM path |
| **MEDIUM** | Cookie path and CORS behaviour changes when the gateway lands | Explicit refresh-flow test through the gateway before Phase 5 starts |
| **LOW** | Stitch iteration count is unpredictable | Prompt library is versioned, so regeneration is cheap and reproducible |

---

## Deferred (recorded, not built)

| Item | Re-entry criterion |
|---|---|
| Price intelligence (spec §8.5, slice 6) | Per category, when enough recently-published ads meet the comparator threshold |
| Sinhala / Tamil ad content (spec §8.4, slice 7) | A formal D-07 reversal, covering fonts and si/ta moderator staffing against NFR-6 |
| Mobile (Expo) posting parity | After web ships; D-11/D-27 keep mobile an MVP surface |
| Featured placement purchase flow | `payment-service`, out of this plan's scope |
| Full English/Sinhala/Tamil UI localisation | Explicit non-goal in this release |
