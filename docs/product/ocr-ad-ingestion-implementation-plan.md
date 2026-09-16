# Implementation Plan: OCR and LLM Advertisement Ingestion

## Document Control

| Field | Value |
|---|---|
| Product | LankaListings |
| Implements | [ocr-ad-ingestion-prd.md](ocr-ad-ingestion-prd.md) Phases 0-4 |
| Status | Approved for execution |
| Version | 1.0 |
| Date | 2026-09-04 |
| Processing service | Media service (FastAPI) |
| Primary client | Management portal (Vite + React) |
| Database | PostgreSQL 17 (local, test, and production) |

This plan is the engineering counterpart to the PRD. The PRD states *what* the capability must do; this
document states *how* it will be built, in what order, and how each phase is verified. Where the two
disagree, Phase 0A below is the reconciliation pass and the PRD is corrected to match.

## Context

`media-service` today has a prototype at `POST /api/v1/newspaper-articles/extract` that accepts **one**
image, runs Tesseract, applies regex/keyword heuristics in
`services/advertisements.py:_extract_advertisement_fields`, and creates **exactly one** advertisement —
stored in a single JSON file with the source image inlined as a base64 data URL.

Operations staff need to upload a **batch** of Sinhala newspaper scans, where one page routinely holds
several unrelated classified ads. The prototype cannot express that: it merges a whole page into one
listing, fails the entire request if one image fails, blocks the HTTP call for the duration of OCR, and
corrupts its own state under concurrency.

This plan replaces the heuristic single-ad path with a durable, staged pipeline —
**upload → preprocess → structured OCR → LLM extraction → 0..N pending candidates → human review →
publish** — implementing PRD Phases 0–4
(`docs/product/ocr-ad-ingestion-prd.md` §19). Both the OCR engine and the LLM model are selectable by
environment variable so they can be swapped without touching pipeline logic.

The outcome: a moderator uploads 25 images, watches per-image progress, reviews each detected ad against
its OCR evidence and per-field confidence, corrects it, and approves it — and only then does it reach the
Next.js and Expo clients.

## Confirmed Decisions

| Decision | Choice |
|---|---|
| LLM providers | `openai_compatible` (OpenAI/OpenRouter/Groq/vLLM/LM Studio via base URL), `gemini`, `anthropic`, `fake` |
| OCR providers | `tesseract` (default), `paddle_tesseract` hybrid, `vision_llm` |
| OCR cross-validation | **Out of scope.** Interface stays open; no comparison logic now |
| Persistence | **PostgreSQL everywhere** (local, tests, production) via Docker Compose; SQLAlchemy 2.0 + Alembic. No SQLite |
| Image serving | Bytes on disk + asset URL endpoint; public `/api/v1/advertisements` keeps base64 `image_url` |
| Portal | Add `react-router-dom` + `@tanstack/react-query`; componentize `App.tsx` |
| Auth | `require_operator` dependency, `OPERATOR_AUTH_MODE=none` (local default) `\| static_token` |
| Scope | PRD Phases 0–4. Phase 5/6 recorded as rollout blockers |

## Phases at a Glance

Each phase ends green and independently reviewable. Phases 1–3 are strictly sequential; Phase 4 can start
once Phase 1's API contract is fixed. Phase numbering follows the PRD's own §19 delivery plan.

| Phase | Delivers | Key gate |
|---|---|---|
| **0A** PRD remediation ✅ | Resolve the 15 contradictions found during design; PRD → v1.1 | **Done** — PRD v1.1 committed, 35 `[RESOLVED-1.1]` markers, no remaining item blocks Phases 1–4 |
| **0B** Fixtures ✅ | Regression corpus, category catalog, v1 prompt, baseline pin | **Done** — 10 cases, 137 tests green, Sinhala round-trips NFC byte-exact, prompt checksum pinned |
| **1** Batch domain ✅ | 9 tables, Alembic, storage, job dispatch, `202` upload + progress + retry | **Done** — 352 tests green, `alembic check` clean, restart requeued 4 stranded items and the batch completed with no duplicate candidates; code and security review findings fixed |
| **2** Structured OCR ✅ | `OcrProvider` protocol + 3 env-switchable engines, blocks/bboxes/confidence, preprocessing | **Done** — 486 tests green; the provider reproduces all 10 corpus cases block for block; unknown `OCR_PROVIDER` dies at startup with the valid list |
| **3** LLM extraction | `LlmExtractionProvider` + 4 env-switchable providers, versioned prompts, 2-tier validation, retry/repair, 0..N candidates | AC-002/003/005/013; no live call in default suite |
| **4** Portal | react-router + TanStack Query, bulk intake, batch progress, multi-candidate review | Upload → progress → edit → approve → visible in `frontend-web` |

## Verified Environment

- Tesseract **5.4.0** at `C:\Program Files\Tesseract-OCR\tesseract.exe`; languages `eng`, `sin`;
  tessdata in `media-service/.tessdata`.
- `pytesseract.image_to_data(..., output_type=Output.DICT)` confirmed working on
  `.tools/sinhala-newspaper-sample.png` — returns `block_num`, `par_num`, `line_num`, `left/top/width/height`,
  `conf` per word, **93–96% confidence**, 4 blocks, Sinhala Unicode intact. Structured OCR is viable.
- Python 3.12, venv at `media-service/.venv`. Present: fastapi, pydantic v2, pillow, pytesseract, httpx,
  python-dotenv, pytest, ruff. Absent: sqlalchemy, alembic, paddleocr, any LLM SDK.
- Console note: Windows `cp1252` stdout breaks on Sinhala. Needs `PYTHONIOENCODING=utf-8` for scripts;
  FastAPI JSON responses are UTF-8 already.
- Pillow 11.3.0 — `ImageOps.exif_transpose` and `autocontrast` available; `MAX_IMAGE_PIXELS` already guards
  decompression bombs at ~89M px (make it configurable per PRD §15.3).
- Node v20.20.2 / npm 10.8.2 are available (the note in `docs/architecture.md` saying npm is missing is
  stale). `react-router-dom`, `@tanstack/react-query`, `vitest`, `msw` are not installed yet.
- **Baseline is green: 15/15 pass.** Two tests error only because pytest's `tmp_path` cannot create
  `%TEMP%\pytest-of-*` in this environment. Fix in `pyproject.toml` `[tool.pytest.ini_options] addopts` by
  adding `--basetemp=.pytest-tmp` — verified. This matters because the new phases add many `tmp_path` tests
  for on-disk assets.
- **Docker 28.3.2 + Compose v2.38.2 installed, daemon NOT running.** Start Docker Desktop before Phase 1.
  No local PostgreSQL is installed and port 5432 is free.

## Before Starting

All three prerequisites are met.

1. ~~**Write this plan to `docs/product/ocr-ad-ingestion-implementation-plan.md`**~~ — done; this is that
   document, beside the PRD it implements.
2. ~~**`git init` + baseline commit.**~~ — done. Each application is its own repository with its own
   history, so every phase is revertable on its own.
3. ~~**Start Docker Desktop.**~~ — done; PostgreSQL 17 runs on host port **5434** (5432 and 5433 were
   already taken on this machine), with a separate `lankalistings_test` database created by
   `scripts/init-databases.sql`.

## Phase 0A — PRD Remediation (no code)

The design review surfaced 15 places where the PRD contradicts itself or leaves a decision undefined that
Phases 1–3 cannot proceed past. Fix them in `docs/product/ocr-ad-ingestion-prd.md` first and bump it to
**v1.1** with a changelog entry, so the requirement stays the source of truth rather than drifting behind
the code.

### Mechanical corrections — apply directly

| # | PRD location | Fix |
|---|---|---|
| 1 | §8.2 step 9 | "retries one time" → bounded retries. Lock **3 attempts + 1 schema repair**, aligning with FR-LLM-014/§11.6. |
| 2 | §10.1 | Add `partial_failed → processing` and `failed → processing`; a retry (FR-JOB-005) necessarily re-opens a batch. State that `completed_at` is cleared. |
| 3 | §10.2 | `retry` is drawn as a state; it is a **transition**. Redraw. |
| 4 | §10.2 / §13.1 | No `queued` item state exists, but FR-JOB-001 and the §13.1 example both require a `queued` count. Document that item `uploaded` maps to the counts key `queued`. |
| 5 | §13.1 | `counts` omits `needs_attention` and `completed`, both required by FR-JOB-001. Publish the 7-key superset (additive — no client breaks). |
| 6 | §12.2 | Stores both `status` and `current_stage` — one truth in two columns. Derive `current_stage`; keep only `failed_stage` as stored. |
| 7 | §12.7 | `ReviewEvent` is keyed on `advertisement_id` yet requires a `reprocessed` action, which is item-scoped and may have no ad. Add `subject_type` + nullable `advertisement_id`. |
| 8 | §13.4 | Add the missing codes the doc's own requirements imply: `UNAUTHENTICATED` 401, `FORBIDDEN` 403, `RATE_LIMITED` 429, `VERSION_CONFLICT` 409 (§13.2 asks for optimistic version checking), `IDEMPOTENCY_KEY_CONFLICT` 409, `MEDIA_BYTES_UNAVAILABLE` 410, plus `ADVERTISEMENT_NOT_FOUND` and `EXTRACTION_NOT_FOUND` **which the current code already returns**. Split the table in two — HTTP `error.code` and item-level `error_code` are different namespaces with different consumers. |
| 9 | §15.1 | 25 images × 10 MiB = 250 MiB contradicts the 100 MiB total cap. State that **the total is binding** and is checked first. |
| 10 | §6 invariant 12 vs FR-ING-008 | Reads as a contradiction ("stored once" vs "duplicates not discarded"). Add one sentence: dedup applies to **bytes**, flagging applies to **items**. |
| 11 | §11.6 | The rule-based extractor is restricted to tests/local-demo with no stated enforcement. Record env-gating as a requirement. |
| 12 | §11.5 | Split the validation list into **structural** (repair-triggering) and **semantic** (warning-only). Category mapping currently sits beside unknown-field rejection despite opposite handling. |
| 13 | FR-LLM-002 vs FR-LLM-015 | "One image ⇒ one primary request" contradicts "chunk oversized content". Record v1 as **truncate on block boundaries with a warning**; no chunking. |

### Product decisions needed — recommendation, then apply

| # | Question | Recommendation |
|---|---|---|
| 14 | **Category taxonomy.** §11 assumes a catalog; the code ships 6 categories missing `Other`; discovery §4 locks **9**. | Adopt the locked 9 (`vehicles, property, land, jobs, electronics, services, home_garden, fashion, other`). Fixes FR-LLM-011 and the `_detect_category` → `"Home"` fallback bug in one move. |
| 15 | **`pending_review` vs `pending`.** Invariant 2 says one, §10.3 says the other. | Store the **target** vocabulary (`pending`), map to `pending_review` at the wire edge behind `ADVERTISEMENT_STATUS_WIRE=legacy\|target`. The portal keeps working; the listing-service handover needs no data migration. |
| — | **`language` enum is never specified** despite FR-LLM-005. | Lock `si\|en\|ta\|mixed\|unknown`. It is a schema `Literal`, so any drift is a hard failure — it must be in the doc. |
| — | **Contacts shape.** §11.4 shows `phones` only; FR-REV-004 has reviewers editing "contact details". | v1 schema is `phones` only. Reviewer-only fields live on the candidate record, not the LLM schema — with `extra="forbid"`, adding `emails` later is a `schema_version` bump. |
| — | **Confidence type.** FR-OCR-009/§12.4 want numeric; `ExtractionResult.confidence` is a string bucket the portal already reads. | Add `mean_confidence: float` **additively**; do not repurpose the existing field. |

Left as `[OPEN]` deliberately — these are production concerns that do not block Phases 1–4: PRD §24 items 2,
4–7 and 10–12 (cost ceilings, accuracy thresholds, retention periods, phone visibility, per-category required
fields, infrastructure choices, listing-service timing).

**Gate**: PRD v1.1 committed; every item above either corrected or explicitly re-marked `[OPEN]` with a note
saying which phase it blocks.

## Phase 0B — Fixtures and Baseline

No production code. Establishes the contracts everything else is tested against.

**New files**
- `media-service/tests/fixtures/corpus/` — one directory per case, each holding `image.png`,
  `expected_ocr.json` (captured Tesseract blocks), and `expected.json` (ad count, key fields, acceptable
  alternatives, expected warning codes). Seed from the two images already on disk:
  `.tools/sinhala-newspaper-sample.png` (900×520, verified 4 blocks) and `.tools/sample-management-upload.png`.
  Cases required by PRD §18.3: `sinhala_only`, `english_only`, `mixed_language`, `multi_column_three_ads`,
  `no_ads`, `prompt_injection`, `duplicate_phone`, `price_ambiguous_O_for_zero`, `rotated_exif`,
  `low_resolution`.
- `media-service/tests/fixtures/capture_ocr.py` — dev script that regenerates `expected_ocr.json` from an
  image so the corpus stays reproducible. Must set `PYTHONIOENCODING=utf-8` (Windows `cp1252` stdout cannot
  print Sinhala) and write JSON with `ensure_ascii=False`.
- `media-service/src/media_service/domain/categories.py` — the category catalog. Use the nine **locked**
  top-level categories from `lankalistings-harness/.forge/discovery/docs/04-data-model.md:68`:
  `vehicles, property, land, jobs, electronics, services, home_garden, fashion, other`.
  This replaces the ad-hoc 6-item `CATEGORIES` tuple in `services/advertisements.py:13` and the hardcoded
  array in `management-portal/src/App.tsx` — both currently disagree with the locked taxonomy.
- `media-service/src/media_service/services/llm/prompts/v1.txt` — the versioned prompt from PRD §11.3.

**Baseline record**: a test that pins current single-ad behavior before it is replaced, so the regression is
visible rather than silent.

**Gate**: corpus loads, expected counts are asserted, `sinhala_only` round-trips Sinhala Unicode byte-exact.

## Phase 1 — Durable Batch Domain and API ✅

**Status: complete.** 352 tests green against PostgreSQL, `alembic check` reports no drift, `ruff` clean.

Delivered as five commits in `lankalistings-media-service`: the schema and test infrastructure, the item
and batch lifecycle rules, content-addressed storage, the unit of work and repositories, batch ingestion
with idempotent accept and retry, the pipeline and worker, the API surface, and the JSON→PostgreSQL
cutover.

Verified manually against the running service with real Tesseract: 3 images → `202` + `Location`; a
12-image batch converged to `awaiting_review`; a repeated `Idempotency-Key` replayed as `200` with the same
batch id; 4 rows left in flight by a simulated crash were requeued at startup (`Requeued 4 item(s) left in
flight by a previous run`) and finished with **12 candidates across 12 items and no duplicates**; 12
distinct checksums for 12 images; the 4 dangling `running` OCR rows closed out as `abandoned`; a reprocess
through the API produced generation 2 and superseded generation 1.

Two decisions differ from the plan as written, both recorded in the code:

- **The item state machine gained one edge.** An in-flight status may return to `uploaded`. That is
  *requeue after abnormal termination*, which the reaper and single-instance restart recovery both need;
  it is exposed as `requeue_abandoned` rather than as a general transition, and no other caller may take it.
- **Services return frozen view models, not ORM rows.** Closing a unit of work expires the rows it loaded,
  so returning one raises `DetachedInstanceError` in the route that reads it. `domain/views.py` holds the
  read models the API maps from.

Phase 1 ships the pipeline with a **rule-based extractor** that produces at most one candidate per page.
That is the limitation Phase 3 exists to remove; it is marked `origin='ocr_heuristic'` on every candidate
so its output is distinguishable from model output after the fact.

New deps: `sqlalchemy>=2.0.30`, `alembic`, `psycopg[binary]>=3.1`, `pydantic-settings`, `python-ulid`.
New packages `media_service/db/`, `storage/`, `jobs/`. New `docker-compose.yml` at the repo root.

### PostgreSQL everywhere — what this decision buys

Running the same engine in dev, test, and production **deletes an entire class of work** the SQLite plan
carried. Removed outright: the `TZDateTime` re-attach decorator, `BEGIN IMMEDIATE`, `isolation_level=None`,
`busy_timeout`, WAL configuration, the `foreign_keys=ON` pragma, `JSON().with_variant(...)`, dual
`sqlite_where=`/`postgresql_where=` on every partial index, `StaticPool` test juggling, Alembic
`batch_alter_table` rewrites, and the whole "what breaks first on PostgreSQL" risk register — because
nothing is discovered at a cutover any more.

Capabilities now usable directly rather than emulated:
- **`JSONB`** natively, with `GIN` indexes and a working `=` operator.
- **`SELECT … FOR UPDATE SKIP LOCKED`** — a real queue claim instead of a compare-and-swap workaround.
- **`text[]`** for `warning_codes` with a `GIN` index, replacing the `,A,B,` string and its unindexable
  `LIKE` filters. §14.2/FR-REV-002 filter on warnings, so this matters.
- **Partial indexes** (`postgresql_where=`) with no dialect guard.
- **Concurrent writers** — `MAX_WORKER_CONCURRENCY` is no longer capped at ~2 by a single-writer engine.
- `String(n)` and type strictness are enforced from day one, so a 300-char OCR title fails in dev, not in
  production.

Two things that do **not** go away, and one new cost:
- **Savepoints are still mandatory.** On PostgreSQL a failed statement aborts the *entire* transaction
  (`current transaction is aborted, commands ignored`). Every dedup/upsert path wraps
  `session.begin_nested()`, catches `IntegrityError`, rolls back the savepoint, and re-`SELECT`s. This was
  the top SQLite→PG risk and it is now simply the day-one pattern.
- **Naive datetimes still must be rejected at the boundary** — a `TypeDecorator` on bind only, since
  comparing naive to `timestamptz` raises. Much smaller than the two-way version.
- **New cost: Docker is required to run the test suite.** `docker compose up -d postgres` becomes a
  documented prerequisite in both READMEs and CI.

**Test isolation**: one session-scoped database, `alembic upgrade head` once, then
`TRUNCATE … RESTART IDENTITY CASCADE` in an autouse fixture. Not transaction-rollback isolation — the worker
thread pool uses its own connections and would not see an uncommitted test transaction. The **existing 15
tests need no database at all**; they inject `InMemoryMediaRepository` directly and keep passing untouched.

### Schema (9 tables)

`ingestion_batches`, `ingestion_items`, `media_assets`, `media_derivatives`, `ocr_extractions`,
`llm_extraction_runs`, `advertisements`, `advertisement_provenance`, `review_events`.

**`advertisements` is a shim table with no inbound or outbound foreign keys.** Every cross-reference to it
is a plain indexed string. That is what makes invariant 14 real: when the Spring Boot listing-service takes
ownership, you drop this one table and nothing else in the schema changes. All access goes through a
`ListingGateway` Protocol whose `create_candidates(...)` takes the **whole candidate list plus an
idempotency key** — that signature is the difference between a clean swap to an HTTP adapter and a rewrite.

**Candidate uniqueness lives on `advertisement_provenance`, not on `advertisements`** — the service that
performs the retry must own the constraint that makes the retry safe, and the ad row is the part that moves
away.

**Type and convention choices:**
- **IDs**: prefixed ULID strings in `String(40)` (`bat_`/`itm_`/`ast_`/`adv_`…). Matches the PRD's
  `batch_01K4…` wire example, k-sortable for keyset pagination, and makes "cross-service links are opaque
  ids" (§12.8) visible in the type. Chosen over native `uuid` precisely because the prefix is
  self-documenting at a service boundary.
- **`JSONB`** for `blocks`, `field_confidence`, `warnings`, `extracted_values`, `accepted_values`,
  `status_counts`. Still keep real columns for anything the **API filters on** (`confidence_overall`,
  `block_count`) — a JSONB GIN index is not a substitute for a btree on a hot predicate.
- **`text[]` + GIN** for `warning_codes`, since FR-REV-002 filters the review queue by warning.
- **Datetimes**: `DateTime(timezone=True)` with a bind-only `TypeDecorator` that **rejects naive
  datetimes** at the persistence boundary. Timestamps are Python-side `default=`/`onupdate=`, never
  `server_default=CURRENT_TIMESTAMP` (which is server-timezone, not UTC).
- **Enums**: `String(n)` + named `CheckConstraint`, not `sa.Enum`. Native PG enums need
  `ALTER TYPE … ADD VALUE` to extend, which is awkward inside migrations; a CHECK is a one-line alter.
- **Money is `BigInteger` cents; confidence is `Float`.** Never `Numeric` for confidence — `Decimal`
  round-trips change JSON serialization shape.
- **Naming convention** on `Base.metadata` (`ix_`/`uq_`/`ck_`/`fk_`/`pk_`). Any constraint over 3+ columns
  gets an explicit short `name=`, because the auto-generated name blows past PostgreSQL's **63-byte
  identifier limit**. Guard with a test walking `Base.metadata` asserting every name is ≤63 chars and
  globally unique (PG index names are schema-scoped, so two tables cannot share one).

### Idempotency — the hard part

| Layer | Key | Constraint | Requirement |
|---|---|---|---|
| Request | `(created_by, idempotency_key)` | `uq_ingestion_batches__created_by__idempotency_key` | FR-ING-006 |
| Bytes | `checksum_sha256` | `uq_media_assets__checksum_sha256` | FR-ING-007, invariant 12, AC-014 |
| Artifact | `(item, generation, attempt)` + partial-unique terminal states | `uq_ocr__*`, `uq_llm_runs__*`, `uq_prov__*` | FR-CAN-004, FR-JOB-006, AC-006 |

**Batch idempotency, including the concurrent-duplicate race.** Insert the batch row with
`committed_at = NULL` and **commit immediately** — the unique index, not application logic, arbitrates. On
`IntegrityError`, re-`SELECT` the winner and branch on a `request_fingerprint` (sha256 over
`created_by` + sorted item checksums + count): fingerprint differs → `409 IDEMPOTENCY_KEY_CONFLICT`;
matches and `committed_at IS NOT NULL` → replay the stored `response_snapshot`; matches and still NULL →
poll briefly, then `409 IDEMPOTENCY_IN_PROGRESS`. `committed_at` is why no extra `receiving` state is
needed — §10.1's vocabulary stays exactly as written.

**`generation` vs `attempt` — the distinction the PRD never makes.**
- `attempt` — one row per external call, monotonic per `(item, generation)`. Satisfies §11.6's "record every
  attempt as a separate run".
- `pipeline_generation` — the idempotency *scope* for candidates. Bumped only when prior artifacts are
  declared invalid.

That gives two retry modes, which resolves an ambiguity AC-006 leaves open:

| Mode | Trigger | Generation | Candidates |
|---|---|---|---|
| **Resume** (default) | item in `needs_attention`/`failed`, prior artifacts valid | unchanged | reuse the validated run's candidates; a re-run is a no-op |
| **Reprocess** | `?mode=reprocess`, or preprocessing/prompt version changed | `+1` | new candidates; prior generation's **undecided** candidates → `superseded` |

Reprocess is refused `409` if any prior candidate was **approved**, unless `force=true` — and even then
approved candidates are never superseded. Retrying a successfully completed item returns
`409 NOTHING_TO_RETRY` rather than silently doing nothing.

**Resume point (FR-JOB-006) is one pure function** over plain DB reads — no side effects, trivially
unit-testable: valid `ocr_input` derivative? → valid completed OCR row for this generation? → validated LLM
run? → candidate count matches? Return the first missing stage.

**Worker killed mid-item — the three kill points:**
1. *During Tesseract.* Lease expires; the reaper requeues the item and flips the dangling `running` OCR row
   to `abandoned`. The next attempt skips preprocessing for free because
   `uq_media_derivatives__…__params_hash` already holds the exact derivative. One wasted OCR run, zero
   duplicate artifacts.
2. *After the LLM validated, before candidates.* `uq_llm_runs__item_generation_validated` (partial unique
   `WHERE status='validated'`) means the resume plan jumps straight to candidate creation — **the paid LLM
   call is not repeated.** This is FR-JOB-006 paying for itself in provider cost.
3. *After candidates, before the status update.* **Impossible by construction** — candidate rows, item
   status, `candidate_count`, and the batch projection refresh are the same commit. FR-CAN-003 satisfied and
   kill point 3 eliminated in one stroke.

**Zombie worker** (lease expired, process still alive after a VM suspend): every worker write is a
compare-and-swap `… WHERE id = :id AND claim_token = :tok` with an asserted `rowcount == 1`. The zombie
CAS-misses, raises, and exits without committing. If it somehow lands a completed OCR insert first, the
winner hits the partial unique index, catches it, `SELECT`s the existing row, and *resumes from it* — the
constraint converts a race into a resume.

### Item state machine

Exactly the §10.2 vocabulary, plus nothing: `uploaded`, `preprocessing`, `ocr_processing`,
`llm_processing`, `awaiting_review`, `no_ads`, `needs_attention`, `failed`, `completed`.

Two deliberate rejections: **no `retry_scheduled` state** (derive it — `status='uploaded' AND attempt_count
> 0 AND run_after > now()`), and **no stored `current_stage`** despite §12.2 asking for it — two columns
encoding one truth drift. Derive `current_stage = STAGE_OF[status]`; keep `failed_stage` for the genuinely
non-derivable part.

Enforced in two layers, no triggers:
1. **Legality** — a pure `assert_transition(current, target)` raising
   `InvalidStatusTransitionError(ServiceError, 409, "INVALID_STATUS_TRANSITION")`, which drops straight into
   the existing `service_error_handler` so the envelope and correlation id come free.
2. **Concurrency** — `transition_item()` is the *only* writer of `ingestion_items.status`, issuing
   `UPDATE … WHERE id=:id AND status=:expected AND claim_token=:tok` and asserting `rowcount == 1`.

A CHECK constraint cannot see the old row and triggers are non-portable and invisible to Alembic
autogenerate; the pure function is unit-testable, and the CAS covers what it cannot see.

**Batch status derived (FR-JOB-003), with a cache readers never trust.** `GET /ingestion-batches/{id}`
*always* recomputes with one `GROUP BY` over ≤25 rows. The stored column exists only so the batch **list**
endpoint can filter and sort without a correlated subquery, and `transition_item()` refreshes it **in the
same transaction** — one door in, so it cannot drift. Note `awaiting_review` counts as batch-*terminal*: the
batch tracks extraction, not review, or the progress page never finishes and §14.2 is unusable.

### Job dispatch — thread pool, not asyncio

```python
class JobDispatcher(Protocol):
    def enqueue_item(self, item_id: str, *, generation: int, correlation_id: str) -> None: ...
    def enqueue_batch(self, batch_id: str, item_ids: Sequence[str], *, correlation_id: str) -> None: ...
    def start(self) -> None: ...
    def stop(self, *, timeout: float = 30.0) -> None: ...
```

`pytesseract` spawns a **blocking subprocess**, Pillow is blocking C, and the sync `Session` is blocking. An
asyncio dispatcher would need `run_in_executor` for all of it plus an async DB driver — two concurrency
models for zero benefit. So: `ThreadPoolExecutor` + one poller thread + one reaper thread.

**This resolves the one conflict between the two designs: the LLM adapters are sync (`httpx.Client`), not
async.** LLM calls happen only in the worker, never inside a request — that is the entire point of returning
`202`. With a thread pool as the concurrency unit, async buys nothing and would force an
`asyncio.run_coroutine_threadsafe` bridge. Everything else in the Phase 3 provider design is unchanged.

**`enqueue_*` is a latency hint, never the source of truth.** If the notification is lost, the poller finds
the row anyway — that single property gives AC-015 for free and removes any need for a transactional
outbox. Call it **only after commit**; publishing before commit is the classic dual-write bug where the
worker claims a row the publisher has not committed.

**Claim-on-free-slot, never claim-then-queue** — the poller acquires a semaphore *before* claiming, so
leases are never created for work that has not started (otherwise the reaper fights the pool). With
PostgreSQL this is a proper queue claim rather than a compare-and-swap workaround:
```sql
UPDATE ingestion_items
   SET claim_token=:tok, claimed_by=:worker, lease_expires_at=:now_plus_lease,
       attempt_count = attempt_count + 1, status='preprocessing'
 WHERE id = (SELECT id FROM ingestion_items
              WHERE status='uploaded' AND run_after <= :now AND claim_token IS NULL
              ORDER BY run_after, id
              LIMIT 1 FOR UPDATE SKIP LOCKED)
RETURNING id
```
`SKIP LOCKED` means concurrent workers never contend on the hot row — each takes the next free one instead
of serializing and losing a CAS. Keep the CAS (`AND claim_token IS NULL`) as a cheap invariant assertion,
and keep `rowcount == 1` checks on every subsequent worker write to defend against a zombie holding a stale
`claim_token`.

**Restart recovery** has two modes with genuinely different correctness envelopes:
`WORKER_SINGLE_INSTANCE=true` (local default) requeues every in-flight row on startup regardless of lease —
safe only because no other process holds those claims, and progress returns in milliseconds.
`WORKER_SINGLE_INSTANCE=false` (required in production) waits out lease expiry.

Delivery semantics are **at-least-once dispatch + DB-level artifact uniqueness = effectively-once
artifacts**. Put that in the docstring so nobody "fixes" it later.

Test adapters: `InlineDispatcher` (runs synchronously, no threads — deterministic `TestClient` integration
tests) and `ManualDispatcher` (records intent; the test calls `run_once()`).

**Set `OMP_THREAD_LIMIT=1` in the worker environment.** Tesseract's own OpenMP threading fights the pool and
costs 2–4× throughput on multi-core machines. Default `MAX_WORKER_CONCURRENCY = max(1, min(4, cpu-1))`.

### Sessions and transactions

A `UnitOfWork` context manager exposing per-aggregate repositories — the worker has no request scope, so
`Depends` alone cannot work. Rule: *session lifetime == the `with` block, on the thread that uses it.*
`expire_on_commit=False` (or post-commit attribute reads re-query a closed session) and `lazy="raise"` on
every relationship with explicit `selectinload`, which turns latent `DetachedInstanceError`/N+1 bugs into
loud development-time failures.

**One UoW per stage boundary, not per item.** An item takes 10–60 s. PostgreSQL tolerates concurrent
writers, but a transaction held open across Tesseract and a provider call still pins a connection, holds row
locks the reaper and the progress endpoint want, and inflates `idle in transaction`. Tesseract and the
provider call run with **no transaction open**.

Never pass a `Depends`-provided Session into `run_in_threadpool` — the session would be owned by one thread
and used by another, the classic silent-corruption bug here.

Keep the existing `MediaRepository` Protocol and add a `SqlAlchemyMediaRepository` façade over the new
repositories, so `create_app(repository=...)` and **all existing tests pass unchanged**. Delete the façade in
Phase 4.

### Local PostgreSQL

`docker-compose.yml` at the repo root — `postgres:17-alpine`, a named volume, `POSTGRES_DB=lankalistings`,
a `pg_isready` healthcheck, and a second `lankalistings_test` database created by an init script so the
suite never truncates the dev data.

```
DATABASE_URL=postgresql+psycopg://lankalistings:lankalistings@localhost:5432/lankalistings
TEST_DATABASE_URL=postgresql+psycopg://lankalistings:lankalistings@localhost:5432/lankalistings_test
```

Verified prerequisites: Docker 28.3.2 and Compose v2.38 are installed on this machine, **but the daemon is
not currently running** — start Docker Desktop before Phase 1. Nothing is listening on 5432 and no local
Postgres service exists, so the default port is free.

`engine = create_engine(url, pool_pre_ping=True, pool_size=10, max_overflow=5)`. `pool_pre_ping` matters
because the worker holds connections idle across long OCR and provider calls, and a container restart or an
idle-timeout kill would otherwise surface as a mid-transaction failure.

**Every upsert goes through a savepoint helper:**
```python
nested = session.begin_nested()   # catch IntegrityError, rollback nested, re-SELECT
```
Non-negotiable on PostgreSQL — a failed statement aborts the whole transaction, so a bare
`except IntegrityError: pass` leaves the session dead for every subsequent statement. Add a test that
asserts recovery *after* an IntegrityError within the same UnitOfWork.

### Storage

```
<root>/tmp/<uuid4>.part                                        # staging, same filesystem
<root>/originals/<c0c1>/<c2c3>/<sha256>.<ext>                  # content-addressed
<root>/derivatives/<a0a1>/<asset_id>/<purpose>/<params_hash>.<ext>
```
Content-addressing satisfies invariant 12 and FR-ING-009 for free. The extension comes from the **detected**
format (Pillow `img.format`), never the upload name; `original_filename` is stored sanitized for display
only — and needs RFC 5987 `filename*=UTF-8''…` encoding in `Content-Disposition`, since Sinhala filenames
break the plain parameter.

Derivatives hang off the **asset**, not the item, keyed by a `params_hash` — so re-running preprocessing
with identical params rewrites an identical file (idempotent under retry for free), while a params change
creates a new file instead of corrupting a referenced one.

Write protocol: stream chunks to `tmp/` while hashing → `fsync` → if the target key exists, drop the temp
(dedup hit, **no bytes written**) → else `os.replace` (**atomic over an existing destination on Windows;
`os.rename` is not**). Files land before rows commit, so a crash leaves a GC-able orphan, never a row
pointing at nothing. Add `cli.py storage-gc` for the orphans — §15.2's durability rule implies them and the
PRD never mentions cleanup.

**Duplicates within a batch** (FR-ING-008): group staged files by checksum; occurrences after the first get
`is_duplicate_in_batch=true` + `duplicate_of_item_id` + a `DUPLICATE_IMAGE_IN_BATCH` warning. Both items
remain independently visible and retryable — flagged, never discarded. Cross-batch dedup is automatic and
global, which has one consequence to plan for: **retention cannot delete an asset by item**; it needs a
`NOT EXISTS` guard, and purging sets `bytes_state='purged'` rather than deleting rows.

**Upload must stream.** `await file.read()` (the current pattern at `routes.py:41`) on 25 files peaks at
~250 MB RSS. Order of operations matters for FR-ING-004 vs §15.2: stage + checksum + validate **all** →
reject the whole request on any batch-level breach → move blobs → one transaction → commit → dispatch.
Three limits replace today's single `max_upload_bytes`: `MAX_IMAGES_PER_BATCH=25`,
`MAX_IMAGE_BYTES=10485760`, `MAX_BATCH_BYTES=104857600` (the total is binding — 25 × 10 MiB = 250 MiB
exceeds it, which is a genuine inconsistency in §15.1).

**Serving**: `GET /api/v1/media/assets/{asset_id}/{purpose}` behind `require_operator`, `ETag` = checksum,
key always from the DB plus a defence-in-depth `resolved.is_relative_to(root)` assertion.

**Backward-compatible `image_url`**: an `ImageUrlResolver` picks `advertisement_crop` → `thumbnail` →
`original`. **Always source the base64 from the `thumbnail` derivative** (max edge 320 px, ~15–30 KB) —
sourcing from originals makes a 25-ad feed a ~7 MB response. `PUBLIC_IMAGE_URL_MODE=data_url|http_url`,
default `data_url`, so `frontend-web` and `mobile` need no change until they are ready.

### Migration from JSON

`python -m media_service.cli import-legacy-json [--dry-run] [--include-extractions]`. The current file holds
**5 advertisements, 3 assets, 3 extractions** — ads carry full base64 images (recoverable), assets are
metadata-only (bytes unrecoverable, imported with `bytes_state='absent'` behind an opt-in flag). Idempotent
via `uq_advertisements__legacy_json_id` + checksum dedup. The two identical PNGs in the current file
collapse to one asset, which is a free invariant-12 smoke test. Cutover behind `MEDIA_REPOSITORY=json|sql`;
the JSON file is never written and never deleted, so rollback is one env var.

**Gate**: upload 3 images → `202` + ids; `kill -9` mid-batch and restart → items resume, batch completes;
retry a failed item → no duplicate candidates; existing test suite passes unchanged.

## Phase 2 — Structured OCR (env-switchable) ✅

**Status: complete.** 486 tests green, `ruff` clean. Verified end to end against the running service:
`/health` names the provider, a two-image batch converged, and the stored `ocr_extractions` rows carry
block geometry, `box_source`, `source_ref`, `max_block_id`, `low_confidence` and `preprocess_version`.
Sinhala survived into the database — 39 codepoints, NFC-stable — and each candidate's
`source_block_ids` cites only blocks that exist (`[1..6]` and `[1..3]`).

### Three findings that changed the design

**`--tessdata-dir` cannot be passed through `pytesseract` on Windows.** Its config string is split with
`shlex.split(config, posix=False)`, so a quoted path keeps its quote characters and an unquoted one
splits at the space. Verified both forms fail. The Sinhala traineddata lives under a path containing a
space, and the system Tesseract install ships `eng` but **not** `sin` — so this was the difference
between the service reading Sinhala and not. The provider drives the binary directly and passes the
directory through the *child process's* environment, which also removed `pytesseract` as a dependency
and let `OCR_TIMEOUT_SECONDS` actually kill a run.

**The `tsv` configfile fails silently.** Tesseract resolves configfiles relative to `TESSDATA_PREFIX`;
pointed at a directory holding only traineddata, `tsv` is not found and Tesseract prints **plain text
and exits zero**. A caller parsing that as TSV gets a confident answer built from nonsense.
`-c tessedit_create_tsv=1` needs no configfile and cannot fail that way.

**Preprocessing defaults were measured, not chosen.** Running the corpus under each option:

| Variant | Mean confidence | Blocks |
|---|---|---|
| orientation only | 0.8932 | 36 |
| + greyscale | 0.8932 | 36 |
| + autocontrast | 0.8932 | 36 |
| + denoise | 0.8713 | 36 |
| threshold 128 | 0.8662 | 36 |

Greyscale and autocontrast are exact no-ops on this corpus; denoising and thresholding measurably
*hurt* clean scans. So orientation and greyscale are on by default and the rest are switches.

### Corpus re-capture

`capture_ocr.py` now runs the production preprocessor and provider instead of its own copy of the
block algorithm, so the corpus and the provider cannot drift apart. The re-capture diff is
**confidence precision plus two additive fields** (`box_source`, `detector`): block ids, boxes, texts,
`source_ref`s and page transcripts are byte-identical, so no `evidence_within_blocks` citation in any
`expected.json` was invalidated. Confidences rose slightly because `pytesseract` truncated them to
integers; the raw TSV carries six decimal places. Every authored `min_mean_confidence` floor and the
`expect_low_confidence` flag still hold.

### Deviation from the plan

**`vision_llm` is a seam, not an implementation.** The plan lists it under Phase 2, but its design
builds on the schema-agnostic LLM adapters Phase 3 introduces — the plan says so itself in §Phase 3.
Writing a second HTTP client here would guarantee the two drift apart before they were merged. The
name is therefore *recognised and refused with a reason* ("arrives in Phase 3"), so a deployment that
selects it fails at startup rather than on the first page. `BoxSource` exists from day one precisely
because this provider cannot produce engine geometry.

**PaddleOCR is not installed here**, so the hybrid's detection path is exercised through a detector
double rather than the real one; the merge heuristics are pure functions and are tested exhaustively.
The degraded path — which is what runs without the package — is verified live: identical output to
plain Tesseract, `degraded=True`, `DETECTOR_UNAVAILABLE`.

New package `media_service/ocr/` — `types.py`, `protocol.py`, `blocks.py`, `quality.py`, `compat.py`,
`registry.py`, `providers/{tesseract,paddle_tesseract,vision_llm}.py`.

**`OcrProvider` is a `Protocol`, and it is sync.** Two of three implementations are CPU/subprocess bound;
making the protocol async would force every adapter to carry its own thread plumbing. Concurrency lives in
exactly one place in the pipeline:
```python
async with ocr_semaphore:                       # OCR_CONCURRENCY
    return await anyio.to_thread.run_sync(partial(provider.extract, image_bytes, ...))
```
`Protocol` matches `domain/repository.py:16`; the current `raise NotImplementedError` base class in
`services/ocr.py:29` gives no static checking.

**Result types** (frozen slotted dataclasses): `BoundingBox`, `OcrLine`, `OcrBlock(id, text, box,
confidence, box_source, lines, source_ref, detector)`, `OcrResult(text, blocks, provider, engine,
model_version, languages, mean_confidence, width, height, preprocess_version, duration_ms, warnings,
degraded)`. `box: BoundingBox | None` plus a `box_source` enum (`engine|model_estimate|synthetic`) from day
one — `vision_llm` cannot produce engine geometry, and FR-CAN-006's `crop_needs_review` path is exactly the
designed fallback when `box_source != engine`.

**Do not break the 25 existing call sites.** `services/ocr.py` keeps `OcrEngine`/`OcrOutput` as deprecated
re-exports, and `ocr/compat.py` provides `as_provider()` / `as_legacy_engine()`. That shim is what lets the
new pipeline be tested with the existing `FakeOcrEngine` without editing `tests/test_media_service.py`.

**Registry**: explicit builder table with function-local imports, not a decorator registry — a decorator
registry only populates if every adapter module is imported, which is precisely what must not happen for
`paddleocr`. `OCR_PROVIDER` is typed as a `StrEnum` on `Settings`, so a typo dies at startup with the valid
list rather than silently falling back to Tesseract.

**PaddleOCR stays optional**, in `[project.optional-dependencies] paddle`, with three-stage laziness:
`__init__` does no imports; `availability_reason()` uses `importlib.util.find_spec`; `extract()` builds the
detector on first use. With `paddleocr` absent and `OCR_PADDLE_FALLBACK_TO_TESSERACT=true` (default), the
service boots healthy and every result carries `degraded=True` + a `DETECTOR_UNAVAILABLE` warning.
The hybrid **composes** the same `TesseractOcrProvider` instance rather than constructing its own.

**Existing bugs to fix here** (all verified in the current code):
- `services/ocr.py:131` mutates `os.environ["TESSDATA_PREFIX"]` and `pytesseract.tesseract_cmd` — process
  globals — from inside `availability_reason()`, which `/health` calls on **every request**. Replace with
  `--tessdata-dir` in the per-call config string; set `tesseract_cmd` once at container build.
- `/health` shells out to `tesseract --list-langs` per request (`ocr.py:68`). Add a TTL availability cache.
- `conf` rows of `-1` and blank `text` are layout artifacts; averaging them produces a garbage
  `mean_confidence`. Filter before aggregating; `mean_confidence = None` when nothing survives, not `0.0`.
- Tesseract's `block_num` restarts per page and can be `0`. Assign our own sequential 1-based ids in
  deterministic reading order (column band → top → left) and keep the native value in `source_ref`.
  **Persisted ids are authoritative** — evidence validation compares against the stored OCR record, never a
  recomputed one.

**Preprocessing** (`FR-OCR-004/005/006`): `ImageOps.exif_transpose` first, then configurable
grayscale/contrast/denoise/threshold/deskew producing an `ocr_input` derivative. The original is never
modified. `preprocess_version` is recorded on every extraction.

## Phase 3 — LLM Extraction (env-switchable)

New package `media_service/llm/` — `types.py`, `protocol.py`, `schema.py`, `dialects.py`, `validation.py`,
`runner.py`, `service.py`, `registry.py`, `prompts/`, `providers/`.

**`LlmExtractionProvider` is sync (`httpx.Client`) and deliberately schema-agnostic** — it takes a JSON
schema, not `AdExtractionEnvelope`. Schema-agnosticism is what actually satisfies FR-LLM-003, and it lets
the `vision_llm` OCR provider reuse the same three adapters with a different schema. Sync because the
worker is a thread pool and LLM calls never happen inside a request (see Phase 1) — async would only add an
`asyncio.run_coroutine_threadsafe` bridge for no gain.

**One Pydantic model, three provider dialects.** `schema.py` holds `AdExtractionEnvelope` with
`extra="forbid"` and `allow_inf_nan=False` (that flag *is* §11.5's "confidence values are finite" —
providers do emit `NaN`). `dialects.py` derives each wire format from it:

| Provider | Mechanism |
|---|---|
| `openai_compatible` | `response_format: {type: json_schema, strict: true}`. Strict mode forbids `minimum`/`maxLength`/`$ref` and requires every property in `required` — so `to_openai_strict()` strips bounds for the wire while Pydantic keeps enforcing them app-side. `auto` mode degrades to `json_object` by base-URL host (Groq, Together, LM Studio). |
| `gemini` | `responseMimeType: application/json` + `responseSchema`. Needs the OpenAPI-3.0 subset: uppercase types, `nullable: true` instead of null-unions, `$defs` fully inlined, `propertyOrdering`. Key in the `x-goog-api-key` **header**, never `?key=` — URLs land in proxy logs. |
| `anthropic` | No `response_format` exists. Forced tool call: `tools: [emit_advertisements]` + `tool_choice: {type: tool, name: ...}`. The `tool_use.input` **is** the payload dict — no string parsing, no markdown fences. |
| `fake` | No HTTP client is constructed at all. Modes: `fixture` (corpus-keyed), `rule_based`, `empty` (AC-003), `always_invalid` (AC-005). |

**Validation splits into two tiers — this is the load-bearing decision.** §11.5 lumps them together, but they
have opposite failure semantics:
- **Tier 1, structural** (`AdExtractionEnvelope.model_validate`): unknown fields, types, ranges,
  finiteness. Runs on **every** provider including schema-enforced ones. Failure ⇒ **repairable**.
- **Tier 2, semantic** (`validate_extraction`): candidate cap, `source_block_ids ⊆ ocr.block_ids()`
  (the concrete hallucination detector), category mapping, phone normalization, control-char/bidi
  stripping, NFC. Failure ⇒ **warning or candidate drop, never a retry**.

This is why `category` is typed `str`, not `Literal`: as a `Literal`, an unknown category becomes a Tier-1
structural failure and burns a **paid repair call** for something FR-LLM-011 explicitly says to map to
`Other` with a warning.

**Retry/repair lives in a provider-agnostic `LlmExtractionRunner`, not in the adapters.** The split that
matters: *classification is the adapter's job, policy is the runner's job.* Only the Gemini adapter knows
`RESOURCE_EXHAUSTED` is a rate limit; only Anthropic knows `529 overloaded_error`. Each adapter maps its
native failure into one typed `LlmProviderError(code, retryable, retry_after_seconds, detail)` and the
runner never sees a provider-specific string. Two **independent** budgets: `attempts_used` (transport,
`LLM_MAX_ATTEMPTS=3`) and `repairs_used` (schema, `LLM_MAX_REPAIRS=1`). A transport retry must never consume
the repair budget.

The repair message carries **field paths and error messages only — never field values**. An OCR-derived
phone number must not be echoed into a second prompt (§15.4).

**One `LlmExtractionRun` record per attempt**, written with `status="in_flight"` *before* the HTTP call so a
hung provider is visible in the store rather than invisible (FR-JOB-007). A `request_hash` over
provider+model+prompt_version+prompt_checksum+schema_version+catalog_version+inputs is the cost lever for
AC-006: retrying an item that already has a `succeeded` run with an identical hash reuses its
`validated_response` instead of re-billing.

**Prompt versioning**: `llm/prompts/ad_extraction/v1/{manifest.json,system.txt,user.txt,repair.txt}`, loaded
through `importlib.resources` (not `Path(__file__).parent` — see gotcha below). Each run records both
`prompt_version` and a `prompt_checksum`, and a test pins the checksums:
```python
FROZEN_PROMPT_CHECKSUMS = {"ad-extraction/v1": "..."}
```
so editing `system.txt` without bumping the version fails CI. That is what makes FR-LLM-004 enforceable
rather than aspirational — a silent prompt edit otherwise invalidates the whole §18.3 eval corpus.

**Block rendering** puts the id first so the model can cite it, geometry so it can resolve columns, and
confidence so it can warn:
```
[4] (x=112,y=880,w=430,h=64) conf=0.94
ටොයොටා ප්‍රියස් 2016
```
Any literal `</ocr_blocks>` inside OCR text must be escaped — otherwise a crafted newspaper image closes the
delimiter early, and AC-013 is a prompt-injection acceptance criterion.

**`fake` is not enough on its own for AC-016** ("tests must not require a live paid call") — a fake is a
convention. Add a hard guarantee in `conftest.py`: an autouse fixture that monkeypatches `httpx.Client.send`
and `httpx.AsyncClient.send` to raise unless the test carries a `live` marker, plus
`addopts = [..., "-m", "not live"]`. A second autouse fixture must clear provider env vars — otherwise a
developer with `LLM_PROVIDER=anthropic` exported in their shell silently changes test behavior.

**Production guard for the heuristic path** (§11.6 forbids silent heuristic fallback in production, but says
nothing about enforcing it): `MEDIA_SERVICE_ENV` + `MEDIA_SERVICE_ALLOW_FAKE_PROVIDERS` make constructing
`fake`/`rule_based` a startup error outside local/test. The existing regexes in
`AdvertisementService._extract_advertisement_fields` move into `RuleBasedLlmProvider` — off the production
path, still available for local demo.

## Config Surface (~55 new env vars)

Move to **`pydantic-settings`**. The current `config.py` hand-codes 6 vars and already contains the pattern
that breaks at scale — `int(getenv(...))` with no error handling, and `bool(getenv("X", "false"))` is `True`
for any non-empty string. `SecretStr` also gives free `repr` redaction, which matters with five API keys, a
`/health` that returns internal reasons, and FastAPI `/docs` exposed.

Convention kept from the existing code: `MEDIA_SERVICE_*` for our own policy, bare conventional names for
third-party credentials (matches the existing `TESSERACT_*` and what secret managers inject).

```bash
# Database, storage, jobs, auth
DATABASE_URL=postgresql+psycopg://lankalistings:lankalistings@localhost:5432/lankalistings
TEST_DATABASE_URL=                                # ...lankalistings_test
MEDIA_STORAGE_ROOT=.data/media                    MEDIA_SERVICE_DATA_DIR=
MAX_IMAGES_PER_BATCH=25   MAX_IMAGE_BYTES=10485760   MAX_BATCH_BYTES=104857600
JOB_DISPATCH_MODE=local_pool|inline|manual        MAX_WORKER_CONCURRENCY=4
LEASE_SECONDS=300   HEARTBEAT_SECONDS=30   REAPER_INTERVAL_MS=15000   POLL_INTERVAL_MS=2000
WORKER_SINGLE_INSTANCE=true                       OMP_THREAD_LIMIT=1
OPERATOR_AUTH_MODE=none|static_token              OPERATOR_API_TOKEN=
PUBLIC_IMAGE_URL_MODE=data_url|http_url           ADVERTISEMENT_STATUS_WIRE=legacy|target
MEDIA_REPOSITORY=json|sql

# Selection
MEDIA_SERVICE_ENV=local|test|staging|production   # default local
MEDIA_SERVICE_STRICT_STARTUP=                     # default true iff production
MEDIA_SERVICE_ALLOW_FAKE_PROVIDERS=               # default true iff local|test
OCR_PROVIDER=tesseract|paddle_tesseract|vision_llm
LLM_PROVIDER=openai_compatible|gemini|anthropic|fake

# OCR shared
OCR_LANGUAGES=sin+eng            OCR_CONCURRENCY=2        OCR_TIMEOUT_SECONDS=60
OCR_MAX_PIXELS=40000000          OCR_EMPTY_TEXT_MIN_CHARS=8
OCR_LOW_CONFIDENCE_THRESHOLD=0.60                 OCR_PREPROCESS_VERSION=preprocess/v1
# Tesseract: TESSERACT_CMD, TESSERACT_TESSDATA_DIR (existing) + OCR_TESSERACT_{PSM,OEM,REGION_PSM}
# Paddle:    OCR_PADDLE_{MODEL_NAME,MODEL_DIR,DEVICE,BOX_THRESH,MERGE_IOU,MAX_REGIONS,FALLBACK_TO_TESSERACT}
# Vision:    OCR_VISION_{PROVIDER,MODEL,MAX_IMAGE_EDGE_PX,IMAGE_FORMAT,PROMPT_VERSION}

# LLM shared policy
LLM_TEMPERATURE=0.0              LLM_MAX_OUTPUT_TOKENS=8000
LLM_MAX_ATTEMPTS=3               LLM_MAX_REPAIRS=1
LLM_BACKOFF_{BASE,MAX}_SECONDS=1.0/20.0           LLM_TOTAL_DEADLINE_SECONDS=240
LLM_CONCURRENCY=4                LLM_STRUCTURED_MODE=auto
LLM_MAX_OCR_CHARS=24000          LLM_MAX_CANDIDATES_PER_IMAGE=20
LLM_PROMPT_VERSION=              LLM_COST_{INPUT,OUTPUT}_USD_PER_MTOK=0.0

# Per provider
OPENAI_{BASE_URL,API_KEY,MODEL,AUTH_HEADER,EXTRA_HEADERS,TOKEN_PARAM}
GEMINI_{API_KEY,BASE_URL,MODEL,THINKING_BUDGET}
ANTHROPIC_{API_KEY,BASE_URL,MODEL,VERSION,TOOL_NAME}
LLM_FAKE_{MODE,FIXTURE_DIR}
```

Two structural fixes while touching `config.py`, both existing latent bugs:
1. **`Settings` model defaults disagree with `get_settings()` env defaults.** `Settings.tesseract_lang`
   defaults to `"eng"` (`config.py:21`) while `get_settings()` reads `TESSERACT_LANG` defaulting to
   `"sin+eng"` (`config.py:63`). Every test doing `Settings(max_upload_bytes=1024)` — which is all of them —
   silently runs **English-only OCR**, violating FR-OCR-001 with no test noticing. Defaults must live in the
   model only.
2. **`get_settings()` is `lru_cache`d with no invalidation**, so `monkeypatch.setenv` is invisible to it.
   Add `reset_settings_cache()`.

Also: `media-service/.env.example` exists and **nothing loads a `.env` file** — verified, zero references to
`dotenv` in `src/`. Every documented var currently only works if exported in the shell. That trap gets far
worse with 55 more vars.

And `pyproject.toml` has `[tool.setuptools.packages.find]` but **no `package-data`**, so
`llm/prompts/**/*.txt`, `manifest.json`, and `categories.v1.json` would be missing from a built wheel —
works in editable dev, fails in a deployed container. Add the globs and load via `importlib.resources`.

## Phase 4 — Management Portal Workflow

The portal is a single 488-line `App.tsx` with no router, no data layer, and no tests. This phase is its
first real componentization.

**New dependencies**: `react-router-dom`, `@tanstack/react-query`. Test infra is greenfield — add `vitest`,
`@testing-library/react`, `msw`.

**Restructure** (`management-portal/src/`)
```
lib/
  api/client.ts          # shared envelope unwrap + correlation_id surfacing + AbortController
  api/ingestion.ts       # batch create/get/items/retry
  api/review.ts          # queue/detail/patch/approve/reject
  api/types.ts           # single source of truth for wire types; status as unions, not `string`
routes/
  IntakeRoute.tsx        # §14.1 multi-select + drag-drop + client validation
  BatchProgressRoute.tsx # §14.2 per-item stage, elapsed, retry
  ReviewRoute.tsx        # §14.3 review workspace
components/
  intake/FileDropZone.tsx, SelectedFileList.tsx
  batch/BatchCountsBar.tsx, ItemStageRow.tsx
  review/SourceImageViewer.tsx   # zoom/rotate/crop + OCR block overlay
  review/OcrTextPanel.tsx        # <pre> preserving Sinhala Unicode
  review/FieldEditor.tsx         # per-field confidence + warnings
  review/ConfidenceBadge.tsx     # icon + text, never color alone (§14.4)
  review/CandidatePager.tsx      # "Ad 2 of 5 from page-3.png", guards unsaved edits
  ui/StatusChip.tsx              # extracted from App.tsx:44
```

**Routing**: the sidebar `<button>`s in `App.tsx:204-214` have no `onClick` and `active: true` is hardcoded
on Dashboard (`App.tsx:26-32`) — they are decorative. Replace with `NavLink`s to
`/intake`, `/batches/:batchId`, `/review`, `/review/:candidateId`.

**Data layer**: TanStack Query supplies exactly the primitives §13.1/§14.2 need — `refetchInterval` for
batch progress (stop polling once the batch reaches a terminal state), `invalidateQueries` on
approve/reject/retry, and mutation state for save-vs-approve. The current
`setReviewQueue(current => current.filter(...))` hand-rolled cache mutations in `App.tsx:102-197` go away.

**Behavior to fix while here**
- `handleApprove` (`App.tsx:170`) issues update-then-approve as two unguarded calls; a failed approve leaves
  edits saved with no feedback. Approve must send edits and transition atomically server-side.
- No Reject button exists anywhere. §13.2 requires one with a reason code.
- No client-side size/count validation. Mirror the server's three limits.
- `correlation_id` is returned by the server on every error (`api/schemas.py:13-18`) and read by no client.
  Surface it in error toasts — it is the only handle for diagnosing a failed batch.

**Design**: reuse existing tokens from `management-portal/tailwind.config.ts` — `frame #131b2e` sidebar,
`emerald` primary action, `amber` pending, `danger` reject, `line` borders, Manrope. No new design system.

**Gate**: upload 3 fixtures → watch progress to completion → open a multi-candidate image → edit → approve
→ candidate appears in `frontend-web` and disappears from the queue.

## Verification

Each phase has a gate; these are the end-to-end checks.

**Backend**
```bash
docker compose up -d postgres            # required; start Docker Desktop first
cd media-service
alembic upgrade head && alembic downgrade base && alembic upgrade head
alembic check                            # no drift between migrations and models
.venv/Scripts/python.exe -m pytest -q --basetemp=.pytest-tmp     # all phases, offline
.venv/Scripts/python.exe -m pytest -q -m live                    # only with real API keys set
.venv/Scripts/python.exe -m ruff check src tests
```

**Provider switching is the headline requirement — prove it explicitly.** One parametrized test asserts the
pipeline produces identical validated candidates from the same fixture across every `LLM_PROVIDER` (using
recorded response fixtures) and every `OCR_PROVIDER`, and that an unknown provider name fails at startup with
the valid list:
```bash
OCR_PROVIDER=tesseract        LLM_PROVIDER=fake   pytest tests/test_provider_matrix.py
OCR_PROVIDER=paddle_tesseract LLM_PROVIDER=fake   pytest tests/test_provider_matrix.py   # degraded path
OCR_PROVIDER=nonsense uvicorn media_service.main:app   # must die with the valid-name list
```

**Manual end-to-end** (the PRD's Definition of Done):
```bash
uvicorn media_service.main:app --reload --port 8001
curl -X POST http://localhost:8001/api/v1/ingestion-batches \
  -F "images=@.tools/sinhala-newspaper-sample.png" \
  -F "images=@tests/fixtures/corpus/multi_column_three_ads/image.png" \
  -F "images=@tests/fixtures/corpus/no_ads/image.png"
# -> 202 + Location header + 3 item ids
curl http://localhost:8001/api/v1/ingestion-batches/{id}          # counts converge, partial_failed if one fails
curl http://localhost:8001/api/v1/advertisements/review           # 3 candidates from the multi-ad image
```
Then in the portal (`npm run dev:portal`, `npm run dev:web`): upload → progress → open the 3-candidate
image → confirm "Ad 2 of 3" → edit → approve → verify it appears in `frontend-web` and is gone from the queue.

**Acceptance criteria mapped to tests** — AC-002 (3 ads → 3 candidates, one asset), AC-003 (`no_ads`),
AC-004 (one OCR failure doesn't stop the batch), AC-005 (invalid JSON after repair → visible error, no ad),
AC-006 (retry creates no duplicate), AC-010 (pending never public), **AC-012 (Sinhala survives OCR → record →
prompt → response → DB → API → render as byte-exact NFC Unicode)**, AC-013 (injection fixture cannot change
the schema), AC-014 (bytes stored once), AC-016 (no live call in the default suite).

## Risks

| Risk | Mitigation |
|---|---|
| **No version control.** This rewrites every media-service layer and all of `App.tsx`. | `git init` + baseline commit before Phase 1. Listed as a pre-step. |
| Docker is now a hard prerequisite for running the test suite, and the daemon is currently stopped on this machine. | `docker compose up -d postgres` documented in both READMEs and as the first CI step; `pytest` fails fast with a clear "start the database" message rather than a connection traceback. The existing 15 tests need no database and still run without it. |
| PostgreSQL aborts the entire transaction on a failed statement, so a bare `except IntegrityError` leaves the session dead for everything after it. | `session.begin_nested()` savepoint wrapper on every dedup/upsert path from day one, plus a test asserting recovery after an IntegrityError inside the same UnitOfWork. |
| PaddleOCR is a heavy native dep that often fails to install on Windows, and first use downloads ~100 MB of weights inside a request. | Optional extra, lazy import, memoized detector behind a lock, `OCR_PADDLE_MODEL_DIR` for pre-baked weights, and default fallback to whole-page Tesseract with a `DETECTOR_UNAVAILABLE` warning. Never blocks startup. |
| PaddleOCR has **no Sinhala recognition model** — only its detector is language-agnostic. | The hybrid uses Paddle for detection only; Tesseract does all recognition. Full PaddleOCR was explicitly rejected for this reason. |
| Paddle emits one box per text *line*, not per ad. Feeding hundreds of line crops to Tesseract destroys ad boundaries and makes `source_block_ids` meaningless. | Merge boxes into regions by IoU + vertical-gap/column heuristics before recognition, capped at `OCR_PADDLE_MAX_REGIONS`. Cross-check block counts against the verified plain-Tesseract baseline (4 blocks on the sample) in the corpus. |
| Sinhala corruption at any layer fails AC-012 silently. | **NFC only, never NFKC** — NFKC mangles ZWJ conjuncts. `ensure_ascii=False` in every writer, explicit `encoding="utf-8"`, `PYTHONIOENCODING=utf-8` for scripts, and a single round-trip test through all seven layers. |
| LLM cost runs away during development. | `fake` is the default provider; network is hard-blocked in the test suite; `request_hash` reuse prevents re-billing on retry; per-run token/cost recorded from day one. |
| Anthropic forced-tool truncation looks like a schema error, burning the single repair budget on an unfixable problem and permanently failing the item. | Adapter checks `stop_reason == "max_tokens"` **before** parsing and raises retryable `LLM_TRUNCATED_OUTPUT`; the runner bumps `max_output_tokens` 1.5× on that retry. Same for OpenAI `finish_reason=="length"` and Gemini `MAX_TOKENS`. |
| Secrets leaking through `/health`, `/docs`, or an unmapped provider error body. | `SecretStr` everywhere; `availability_reason()` returns "GEMINI_API_KEY is not set", never a value; provider error bodies allowlisted to type/code/status; a test asserts no secret field appears in any response body. |
| The existing synchronous `/newspaper-articles/extract` would put a 30–240 s paid call inside one HTTP request if naively wired to the LLM — and a client retry double-bills. | Keep it on `RuleBasedLlmProvider` with unchanged behavior (§13.3 compatibility). Real extraction goes through the new `202 Accepted` batch endpoints only. |

## PRD Issues Found

All 15 contradictions and undefined decisions are listed with their resolutions in **Phase 0A** above,
which is the actionable remediation pass against `docs/product/ocr-ad-ingestion-prd.md`.

## Deferred (recorded, not built)

- **OCR cross-validation** — running a second engine as a validator. Interface stays open; no comparison
  logic in this scope.
- **PRD Phase 5** — PostgreSQL, S3, durable broker, rate limiting, metrics dashboards, retention jobs.
- **PRD Phase 6** — controlled rollout and accuracy measurement.
- PRD §24 open decisions 2, 4–7, 10–12 remain unresolved and are production blockers, not local ones.

_(Phases 1–3 filled in from design review)_
