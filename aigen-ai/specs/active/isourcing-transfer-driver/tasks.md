# Tasks — iSourcing Transfer Driver (Database ↔ Public API)

Phases 0-3 implemented and verified on 2026-08-23. Phase 4 implemented against iSourcing API
contract v1.0 and verified on 2026-08-24, followed by the R-1/R-2/R-3 review fixes. The migration
is applied on local. Phase 5 not started.
Created: 2026-08-23 · Revised: 2026-08-23 (baseline changed from a branch merge to `develop-dot` as-is)
Specification: `spec.md` (same folder) · Executor document: `aigen-tasks/20260823-151149-feat-isourcing-transfer-driver/plan.md`

Repository boundaries are explicit per task. Every task names its exit criteria so a phase can be
declared done without re-reading the whole plan.

## Baseline

`develop-dot` at `4d30f82d`, unmodified. `feat/enhancement-on-cron` is **not adopted** — its
changes were reviewed and judged unnecessary. Nothing in this plan depends on that branch.

Because the branch is abandoned, its hardening (`SERIALIZABLE`, deadlock retry, postcondition
assertions) and its `reconcile:isourcing` CLI are not available. Decision D-9 is void; see
"Not inherited" in `spec.md`.

## Phase map

| Phase | Outcome | Owner | Blocked by |
|---|---|---|---|
| 0 | Transfer logic extracted into a driver module, behavior unchanged | Backend | — |
| 1 | Configuration seam exists, no behavior change | Backend | Phase 0 |
| 2 | Port in place, `database` is the only driver | Backend | Phase 1 |
| 3 | API driver skeleton, selectable but contract-stubbed | Backend | Phase 2 |
| 4 | Contract v1.0 implemented: payload, persistence, pending outcome, reconciliation stage | Backend | Phase 3 |
| 5 | Cutover and grant revocation | DevOps + Backend | Phase 4 + OI-5 + OI-6 + OI-9 |

Phases 0–3 can ship to production while the switch stays on `database`. Nothing user-visible
changes until Phase 5.

---

## Phase 0 — Extraction (backend)

A pure move. No logic change, no reordering, no renaming of internals.

- [x] Create `src/services/isourcing/drivers/database.driver.js` and move `prosesToIsourcing`
      (`qcfController.js:1103`, ±425 lines) into it verbatim, together with the helpers it owns:
      `hasHeaderValue`, `validateISourcingHeader`, `buildHeaderMetadata`,
      `failedISourcingTransfer`, and `ensureActiveAdminHeader`.
- [x] Keep the positional signature `(pr_number, server_groups, itemsToUpdate)` and the existing
      result shape exactly as they are.
- [x] Update the two call sites to import the moved function:
      `qcfController.js:256` (`sendActionToCS`) and `qcfController.js:3187`
      (`handleNineDayRfqFollowUp`).
- [x] Verify no other module referenced the removed helpers.

**Tests**

- [x] `tests/controllers/qcfController.manualSourcingHeader.test.js` and
      `tests/repository/qcfLibrary.isourcingTransaction.test.js` pass **unchanged**. They are the
      regression net for this move.

**Exit criteria**

1. `npm test` green with no edits to existing test expectations.
2. `git diff` for `qcfController.js` shows removal and re-import only — no altered logic inside the
      moved block.
3. The moved function is still the only writer to `task_board`.

**Note.** Any test edit required here means the move was not pure. Revert and redo rather than
adjusting the test.

---

## Phase 1 — Configuration seam (backend)

No behavior change. The switch exists and is readable, but nothing consumes it yet.

- [x] Add `src/const/isourcing-transfer.js`: frozen `TRANSFER_DRIVER` (`database`, `api`) and the
      canonical error-code set already produced by the database driver
      (`ISOURCING_SOURCE_HEADER_INCOMPLETE`, `ISOURCING_VALID_HEADER_NOT_FOUND`,
      `ISOURCING_HEADER_REPAIR_FAILED`, `ISOURCING_HEADER_VERIFICATION_FAILED`,
      `ISOURCING_TRANSFER_FAILED`).
- [x] Extend the Joi schema in `config.js`:
      `ISOURCING_TRANSFER_DRIVER` valid `database`/`api`, default `database`;
      `ISOURCING_API_BASE_URL`, `ISOURCING_API_TRANSFER_PATH`, `ISOURCING_API_USERNAME`,
      `ISOURCING_API_PASSWORD` required **only when** the driver is `api`;
      `ISOURCING_API_TIMEOUT_MS` default `10000`; `ISOURCING_API_MAX_RETRY` default `2`.
- [x] Add the `isourcing` block to the `config.js` export, with a comment explaining that it must
      be set identically in the app and cron environments.
- [x] Add the single read point next to `src/helper/featureFlag.js`, following the
      `GEMS_MANUAL_PO_FLOW` precedent. No other module reads `process.env` for this value.
- [x] Document the seven variables in `.env.example` under a new section. Placeholder values only —
      no real credentials.
- [x] Log the active driver once at boot in `app.js` and `src/cron.js`, so an app/cron mismatch is
      visible in both logs.

**Tests**

- [x] Resolver unit tests: unset → `database`; `database`; `api`; unknown value → boot error;
      driver `api` with a missing required variable → boot error.

**Exit criteria.** `npm test` green. No runtime path consumes the value yet. Deployable with zero
behavioral effect.

---

## Phase 2 — Port (backend)

The seam is introduced with exactly one registered driver, so any regression here is a refactor
bug, not a driver bug.

- [x] Add `src/services/isourcing/isourcingTransfer.port.js`:
      validates the input and preserves the existing failure behavior; resolves the driver
      (accepting an optional `scope` argument that is currently ignored, per decision D-8); guards
      that the driver returned the canonical result shape; emits one structured log line (driver,
      `card_title`, item count, result or code, duration); tags Sentry with the driver on failure.
- [x] Point both call sites at the port instead of importing the driver directly.
- [x] Grep-verify that only the port imports a driver, and that no caller imports
      `drivers/database.driver.js`.

**Tests**

- [x] Port unit tests: delegation to the resolved driver, input validation, result-shape guard
      rejecting a malformed driver result, and log emission.
- [x] All pre-existing transfer and cron tests must pass **unchanged**.

**Exit criteria.** `npm test` green with no modifications to existing test expectations.
Production behavior equivalent to Phase 1.

---

## Phase 3 — API driver skeleton (backend)

Selectable and structurally complete, but the contract is stubbed. Safe to ship because the switch
stays on `database`.

- [x] Add `src/api/isourcing.api.js` — axios instance with base URL, timeout, and Basic Auth built
      from username and password at runtime. No credential value is ever logged; add an explicit
      redaction step for error serialization.
- [x] Add `src/services/isourcing/drivers/api.driver.js`:
      request builder for `header` + `items` following
      `aigen-reports/20260822-234523-isourcing-public-api-requirements-for-insert.md` §3.3 and §3.4;
      deterministic idempotency key from `card_title` + sorted `item_code` list;
      retry classification — timeout, network, 5xx, 429 retryable with bounded backoff, other 4xx
      not retryable, honoring `Retry-After`;
      response mapper to the canonical result shape, including the "already exists" message form;
      error mapping table with unresolved entries marked `TODO-CONTRACT` (OI-1).
- [x] Omit everything decisions D-4 and D-5 removed: no board placement fields, no split counter,
      no category/CL resolution, no `exports_data`, no `milestone_config` read.
- [x] Register the driver in the resolver.
- [x] Confirm that selecting `api` with incomplete configuration fails at boot, not at transfer
      time.

**Tests** (mocked HTTP layer — never a real endpoint)

- [x] Success → created message; existing PR with new items → "Missing items added: n";
      already-exists → `success: true` with "Missing items added: 0".
- [x] 400 → no retry; 401 → no retry plus alert path; 429 → retry honoring `Retry-After`;
      5xx and timeout → retry up to `ISOURCING_API_MAX_RETRY` then fail.
- [x] Partial success reported by the API → port returns failure (spec contract item 13).
- [x] Idempotency key is stable across two identical calls and changes when the item set changes.
- [x] Credential redaction: no credential material in thrown errors, logs, or Sentry payload.
- [x] Contract parity: a shared test asserting both drivers return the same result shape.

**Exit criteria.** `npm test` green. Driver `database` remains the default everywhere.

---

## Phase 4 — Contract v1.0 implementation (backend)

Unblocked 2026-08-24. Larger than originally planned: the contract is asynchronous, so this phase
adds persistence, a cron stage, and a migration. Split into four steps that can land separately
while the switch stays on `database`.

Executor plan with step-level detail:
`aigen-tasks/20260824-031739-feat-isourcing-api-contract-v1/plan.md`.

### 4a — Payload and mapping rewrite

- [x] Rewrite `buildHeaderPayload` into `pr_library` using contract §3.4 names: `pr_number`
      (no prefix), `server_group`, `company_code` (string), `release_date`, `src_value`,
      `src_currency`, `convert_value`, `convert_currency`, `description`, `requestor_user`,
      `requestor_email`, `creator_user`, `creator_email`, `purchase_group_code`,
      `purchase_group_name`, `risk`, `permit1`-`permit3`, `notes`.
- [x] Rewrite `buildItemsPayload` into `pr_items` using contract §3.5 names: `server_group`
      (identical to header), `line_item` (integer from `item_code`), `item_description`, `qty`,
      `unit`, `price_item_idr`, `material_group_code`, `material_group_name`,
      `extended_material_group_code`, `material_number_code`, `service_group_code`,
      `service_group_name`, `is_repeatorder`, `text_repeatorder`.
- [x] Source the three assignment fields from `rfq_library` per D-13. Log per item when any is
      missing, naming the missing fields.
- [x] Remove `source`, `idempotency_key`, `aigen_item_id`, and the `header`/`items` property names
      from the body. Move the key to the `Idempotency-Key` header. Never send `is_oa`,
      `partial_status`, or `acc_assign`.
- [x] Reject a payload above 512,000 bytes before sending.
- [x] Rewrite `classifyError` to the contract table: retry only network, timeout, and `503`;
      never retry `400`, `401`, `403`, `404`, `413`, or `500`. Drop the `429`/`Retry-After`
      assumption but leave the header handling harmless if infrastructure ever sends it.
- [x] Default `ISOURCING_API_TRANSFER_PATH` to `/api/public/isourcing/aigen-import-pr` (D-15).
- [x] Remove every `TODO-CONTRACT` marker touched by this step.

### 4b — Persistence

- [x] Migration for `isourcing_transfer_requests` on the primary schema, columns per the
      specification's Persistence section. Unique index on `idempotency_key`.
- [x] Repository for insert, lookup by status, and status update.
- [x] Derive `idempotency_key` from `pr_number` + `server_group` + sorted line items + `attempt`.

### 4c — Pending outcome and reconciliation stage

- [x] Add the `pending` outcome to the canonical contract and to the port's result-shape guard.
- [x] `202` returns `pending` and persists the request. No Aigen status mutation, no milestone log,
      no token deactivation at this point.
- [x] Teach `sendActionToCS` and the five cron handlers to treat `pending` as "not finished":
      leave the token active and stop before the Aigen transaction.
- [x] Add a reconciliation cron stage that polls `GET /status/{requestId}` for every stored
      `queued` request: `succeeded` performs the deferred Aigen mutation and token deactivation
      exactly once; `failed` records `errorCode` and re-sends with a fresh key when the code is
      transient, at most twice (D-17); `queued` is left for the next run.
- [x] Register the stage in `CRON_STAGES` and in `runCronTasks`, runnable via `--stage`.
- [x] Map `409 PR_ALREADY_EXISTS` to idempotent success with its own log marker (D-12).

### 4d — Tests

- [x] Rebuild `isourcingApiDriver.test.js` from the contract: payload shape, header-only
      idempotency key, `202` → `pending`, `409` variants, `400`/`401`/`403`/`413`/`500` without
      retry, `503` and network with retry, oversized payload rejected before sending, assignment-gap
      logging.
- [x] New tests for the reconciliation stage: `queued` stays, `succeeded` mutates exactly once and
      is not repeated on rerun, `failed` transient re-sends with an incremented `attempt` and stops
      after two.
- [x] Update `isourcingDriverParity.test.js`: shared shape for `success` and `failed`, `pending`
      asserted as api-only.
- [x] Repository tests for the new table.

**Exit criteria.** `npm test` green. No `TODO-CONTRACT` markers remain. `database` still default.
The migration has been run only against a local database.

---

## Phase 5 — Rollout and cutover (DevOps + backend)

Operational. No code change expected in this phase.

- [ ] Confirm OI-6 with the owners of the legacy iSourcing dashboard: PRs transferred through the
      API will have no `exports_data` row. Cutover does not proceed without this confirmation.
- [ ] Per D-18, pair the `isourcing_transfer_requests` table with an agreed read-only query set on
      the iSourcing side. Capture a pre-cutover snapshot with it. There is no reconciliation CLI,
      no health endpoint, and no lookup by PR number.
- [ ] Obtain the non-production base URL (OI-5). D-16 makes it a hard gate: the first real call is
      never made against production.
- [ ] Write the manual procedure for items arriving after a PR already exists (OI-9, D-14), and
      name its owner and trigger.
- [ ] Switch a non-production environment to `api` and exercise the five cron stages, the
      reconciliation stage, and the HTTP route.
- [ ] Production switch: change `ISOURCING_TRANSFER_DRIVER` in **both** the app and cron
      environments, then restart both. A partial switch puts the two processes on different
      mechanisms.
- [ ] Post-cutover verification against the pre-cutover snapshot.
- [ ] After a stabilization period, revoke `INSERT`/`UPDATE` grants on `task_board` for the
      `aigen-backend` database account. **Preserve read access for `aigen-import-pr`**, which still
      selects from `item_card`, `category_group`, and `users`.

**Rollback.** Set `ISOURCING_TRANSFER_DRIVER=database` and restart both processes. No deploy, no
migration, no data repair. Rollback stops being one step once write grants are revoked — so keep
grants in place until confidence is established.

---

## Explicit exclusions

| Item | Reason |
|---|---|
| Adopting `feat/enhancement-on-cron` | Reviewed and judged unnecessary. Its hardening is not inherited; KI-012 and KI-013 stay open |
| Behavior of the moved transfer logic | Spec contract item 9. It becomes the `database` driver unchanged |
| `AGENTS.md` command list correction | Real but separate; it documents CLIs that exist only on the abandoned branch |
| `task_board` schema, unique constraints | The KI-012 / KI-013 concurrency residual risk is unchanged by this work |
| `aigen-frontend` | The `sendActionToCS` HTTP contract does not change |
| `aigen-import-pr` | Verified read-only against `task_board` |

---

## Acceptance-criteria coverage

| AC | Phase | Verification |
|---|---|---|
| AC-1 backward-compatible default | 0, 1, 2 | Unchanged existing transfer tests plus the resolver unit test |
| AC-2 switch without code change | 3 | Driver selection test; confirmed operationally in Phase 5 |
| AC-3 invalid value fails fast | 1 | Resolver unit test |
| AC-4 missing API config fails at boot | 1, 3 | Config unit test |
| AC-5 callers are driver-agnostic | 2 | Grep verification + code review |
| AC-6 identical contract across drivers | 3 | Contract parity test |
| AC-7 no Aigen mutation on failure | 3 | Cron handler tests with a failing driver |
| AC-8 idempotency | 3, 4 | Idempotency key test; confirmed against the real contract in Phase 4 |
| AC-9 retry classification | 3 | Mocked HTTP tests |
| AC-10 timeout honored | 3 | Mocked HTTP test |
| AC-11 no dual write | 5 | Code review plus a database-side privilege check (no CLI available) |
| AC-12 rollback to database mode | 5 | Rehearsed in non-production |
| AC-13 credential confidentiality | 3 | Redaction test + diff review |
| AC-14 traceability | 2 | Port log emission test |

`test-plan.md` is filled in during implementation (workflow step 9), mapping each criterion to a
concrete test file.

---

## Risks

| Risk | Mitigation |
|---|---|
| The Phase 0 move silently alters behavior | Pure move only; the two existing test files must pass unchanged, and the diff is reviewed for logic changes inside the moved block |
| `feat/enhancement-on-cron` is merged later and clobbers the extraction | Close or delete the branch now that it is judged unnecessary |
| No automated post-cutover reconciliation | OI-7: agree a read-only DBA query set before Phase 5 |
| Concurrency residual risk stays open | Unchanged by this work; KI-012 and KI-013 remain recorded as-is |
| The published API contract does not support single-request atomicity | Decision D-3 states it does. If it turns out otherwise, Phase 4 stops and the atomicity decision is reopened — a compensation strategy is a design change, not an implementation detail |
| App and cron environments drift to different driver values | Boot logging in Phase 1; both restarts in one step in Phase 5 |
| Data non-parity between modes (`exports_data`, assignment) | OI-6 confirmation is a hard gate before Phase 5 |
| Rollback becomes multi-step after grants are revoked | Grant revocation is the last task, deliberately after a stabilization period |

---

## Commands

Run from `aigen-backend`. Node pinned to `v22.14.0`.

| Command | Purpose |
|---|---|
| `npm test` | The only automated verification available; there is no lint or build script |
| `git diff --check` | Required at final review |

Do not run cron, sync, migrations, or seeds as verification. `reconcile:isourcing` does not exist on
this baseline.

## Unverified at planning time

- The exact diff size of the Phase 0 move.
- Everything behind OI-1 through OI-7 in `spec.md`.
