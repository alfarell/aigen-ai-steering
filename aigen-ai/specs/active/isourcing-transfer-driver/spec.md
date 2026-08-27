# iSourcing Transfer Driver (Database ↔ Public API)

## Status

- Phases 0-3 implemented and verified locally on 2026-08-23.
- **2026-08-24: iSourcing published API contract v1.0.** OI-1 is closed. Phase 4 was re-scoped
  accordingly — see "Contract v1.0 amendments".
- **Phase 4 implemented and unit-verified on 2026-08-24**, followed by the R-1/R-2/R-3 review
  fixes the same day.
- **Migration applied on local (2026-08-24)** after the blocking duplicate data was resolved.
  `isourcing_transfer_requests` is verified present with the post-fix schema. Other environments
  still need the same data decision before it can be applied there.
- Phase 5 is operational and not started. Its remaining gates are OI-5, OI-6, OI-7, OI-9, OI-10,
  and the iSourcing Public API configuration itself.
- Created: 2026-08-23 · Revised: 2026-08-23 (baseline moved to `develop-dot` as-is) ·
  Revised: 2026-08-24 (contract v1.0)
- Active driver in every environment: `database`. Nothing user-visible has changed.
- Contract source: `isourcing/isourcing-docs/public-api-contract-pr-transfer.md` v1.0
- Primary repository: `aigen-backend`
- Baseline: `develop-dot` at `4d30f82d`, unmodified.
- `feat/enhancement-on-cron` (`af3d9d50`) is **not adopted**. Its changes were reviewed and judged
  unnecessary. Its hardening is therefore not inherited — see "Not inherited".
- Production data mutation: Not performed.
- Related analysis: `aigen-reports/20260822-210020-aigen-cron-auto-manual-sourcing-to-isourcing.md`
- Related API requirements: `aigen-reports/20260822-234523-isourcing-public-api-requirements-for-insert.md`

## Problem

`aigen-backend` transfers PR items into iSourcing by writing directly to the `task_board` MySQL
schema. The target is moving to a new system (isourcing-vanilla) that exposes a public API, and
direct database writes must stop.

The cutover date is not fixed. Both mechanisms therefore have to coexist in the codebase for an
unbounded period, and switching between them must not require a code change, a rebuild, or a data
migration — only an environment value change.

## Confirmed decisions

| ID | Decision |
|---|---|
| D-1 | The API driver is built now as a complete skeleton. When the iSourcing contract arrives, only the path, payload shape, credentials, and error mapping are filled in. |
| D-2 | Authentication is Basic Auth, credentials held in `.env`, sent directly on the insert call. |
| D-3 | The API guarantees atomicity: one PR plus all of its items are created together through a single endpoint that accepts header + items. |
| D-4 | Category/CL auto-assignment becomes iSourcing's responsibility. Aigen no longer resolves it. |
| D-5 | `exports_data` does not exist in isourcing-vanilla. The API driver skips it. |
| D-6 | When the API fails, there is no fallback to the database driver. The transfer fails, the token stays active, and the next cron run retries. |
| D-7 | No shadow or dry-run mode. Exactly two driver values are valid. |
| D-8 | The switch is **global** — one value for every server group and every cron stage. The resolver still accepts an optional scope argument so per-group routing can be added later without touching callers. |
| ~~D-9~~ | ~~`reconcile:isourcing` is the post-cutover verification tool.~~ **Void.** That CLI exists only on the unadopted branch. Post-cutover verification falls back to BD-09's original answer: no automated reconciliation tool. |
| D-10 | The baseline is `develop-dot` as-is. `prosesToIsourcing` is extracted into a driver module by a pure move, with no logic change. |
| D-11 | The asynchronous contract is handled by a third outcome, `pending`, plus a new cron reconciliation stage. `202` never means stored: no Aigen status mutation and no token deactivation until the status endpoint reports `succeeded`. |
| D-12 | `409 PR_ALREADY_EXISTS` maps to an idempotent success, logged with its own marker so it stays distinguishable from a first-time transfer. |
| D-13 | Auto-assign fields come from `rfq_library`, verified present on 2026-08-24: `pr_material_group_number` → `material_group_code`, `external_material_group` → `extended_material_group_code`, `sap_material_number` → `material_number_code`. All three are nullable; a missing value is logged because iSourcing then skips assignment for that item. |
| D-14 | The absent upsert (contract I-3 → `501`) is covered by a manual procedure. Items that arrive after a PR already exists are not transferred by this path. |
| D-15 | `ISOURCING_API_BASE_URL` stays in `.env`. The path is a relative constant, `/api/public/isourcing/aigen-import-pr`, and `ISOURCING_API_TRANSFER_PATH` keeps it overridable per environment. |
| D-16 | A non-production base URL must exist before cutover. The first real call is never made against production. |
| D-17 | At most **2** automatic re-sends for transient terminal `errorCode`s, each with a fresh `Idempotency-Key`. After that the request stops and waits for a human. |
| D-18 | Post-cutover verification combines the Aigen-side transfer-request table with an agreed read-only query set on the iSourcing side. This closes OI-7. |

## Baseline (verified on `develop-dot` @ `4d30f82d`)

```
sendActionToCS                     (qcfController.js:256)   ← HTTP routes + 5 cron stages
handleNineDayRfqFollowUp           (qcfController.js:3187)  ← dormant, cron call commented out
        └──────────────┬───────────────┘
                       ▼
     prosesToIsourcing(pr_number, server_groups, itemsToUpdate)   (qcfController.js:1103)
                       ▼
              task_board (6 tables, one transaction)
```

| Aspect | Value |
|---|---|
| Definition | `const prosesToIsourcing` at `qcfController.js:1103`, ±425 lines, **module-private, not exported** |
| Call sites | **Two**: `qcfController.js:256` and `qcfController.js:3187` |
| Input | Positional: `(pr_number, server_groups, itemsToUpdate)` |
| Success result | `{ success: true, card_title, message }` |
| Success messages | New PR: `PR with number <card_title> success import`. Existing PR: `PR with number <card_title> already exists. Missing items added: <n>` |
| Failure result | `{ success: false, card_title, code, missing, message }` via `failedISourcingTransfer()` |
| Failure codes | `ISOURCING_SOURCE_HEADER_INCOMPLETE`, `ISOURCING_VALID_HEADER_NOT_FOUND`, `ISOURCING_HEADER_REPAIR_FAILED`, `ISOURCING_HEADER_VERIFICATION_FAILED`, plus the `ISOURCING_TRANSFER_FAILED` fallback applied in `sendActionToCS` |
| Transaction | One plain `database_isourcing` transaction. No `SERIALIZABLE` isolation, no deadlock retry |
| Idempotency | `COUNT`-based skips (`countByCardTitle`, `countItemCard`, `findExistingCard`). A fully repeated transfer returns success with `Missing items added: 0` |

This result shape is the **canonical contract**. Both drivers must produce exactly these fields,
because `sendActionToCS` reads `success`, `message`, `code`, and `missing`, and
`handleNineDayRfqFollowUp` reads `success` and `card_title`.

## Not inherited

`feat/enhancement-on-cron` contained hardening that is not adopted with this baseline:
`SERIALIZABLE` isolation, deadlock retry, postcondition assertions, terminal-PR guards, ambiguity
detection, a cron observability service, and the read-only `reconcile:isourcing` CLI.

Consequences, recorded so they are not mistaken for regressions introduced here:

1. KI-012 and KI-013 concurrency residual risks remain exactly as they are today. This work neither
   worsens nor improves them.
2. There is no automated post-cutover reconciliation tool.
3. `AGENTS.md` documents `reconcile:isourcing`, `review:isourcing-repair`, and
   `apply:isourcing-repair-local`, none of which exist on `develop-dot`. Correcting that document
   is a separate task, not part of this spec.

## Target architecture

The driver seam is the extracted transfer function. Callers keep one signature and one result
shape; only the implementation behind it varies.

```
qcfController.js:256 (sendActionToCS)
qcfController.js:3187 (handleNineDayRfqFollowUp)
        └──────────────┬───────────────┘
                       ▼
     isourcingTransfer.port.js              ← new: resolver + contract guard + logging
                       │  resolveDriver(config.isourcing.transferDriver [, scope])
        ┌──────────────┴───────────────┐
        ▼                              ▼
  database.driver.js              api.driver.js
  (the moved prosesToIsourcing)   (HTTP to the public API)
```

### File plan

| File | Change |
|---|---|
| `src/services/isourcing/drivers/database.driver.js` | New. Receives `prosesToIsourcing` by a pure move. No logic change. |
| `src/services/isourcing/isourcingTransfer.port.js` | New. Resolver, input validation, result-shape guard, structured logging. |
| `src/services/isourcing/drivers/api.driver.js` | New. Skeleton `api` driver. |
| `src/api/isourcing.api.js` | New. Axios instance (base URL, timeout, Basic Auth, redaction). |
| `src/const/isourcing-transfer.js` | New. `TRANSFER_DRIVER` and the canonical error-code set. |
| `src/controllers/qcfController.js` | Remove the moved function; both call sites go through the port. |
| `src/helper/featureFlag.js` | Single read point for the driver value, following `GEMS_MANUAL_PO_FLOW`. |
| `config.js`, `.env.example` | Joi schema plus an `isourcing` config block. |

## Behavioral contract

1. `ISOURCING_TRANSFER_DRIVER` selects the mechanism. Valid values: `database`, `api`.
2. An unset value resolves to `database`, preserving current production behavior.
3. An unrecognized value fails at boot with a configuration error. There is no silent fallback.
4. The value is validated by the Joi schema in `config.js` and read through one helper. No
   `process.env.ISOURCING_TRANSFER_DRIVER` appears in services, controllers, or repositories.
5. The value is read once per process at boot. Changing `.env` does not affect a running process.
6. The value must be identical in the HTTP application environment and the cron environment. Both
   processes log the active driver at boot so a mismatch is visible.
7. The port is the only route to iSourcing. Both call sites go through it, and no module outside
   `drivers/database.driver.js` retains a copy of the transfer logic.
8. Both drivers return the canonical result shape defined in "Baseline" — the same field names, the
   same success/failure discrimination, and the same error-code set.
9. The moved transfer logic is not modified. Any behavioral change to it is out of scope and is
   rejected at review.
10. The `api` driver sends one request per PR carrying header plus all items (D-3), with an
    idempotency key derived deterministically from `card_title` plus the sorted `item_code` list.
11. The `api` driver retries only transient failures — timeout, network error, HTTP 5xx, HTTP 429 —
    with bounded backoff. Other 4xx responses are not retried.
12. An API response indicating the PR already exists maps to `success: true` with a message in the
    established "already exists" form, so callers cannot distinguish it from the database driver's
    idempotent path.
13. Partial success is treated as failure. The port returns `success: false` and records what was
    reported as created.
14. There is no automatic fallback between drivers (D-6). A failed transfer leaves the Aigen-side
    status, milestone log, and token untouched, exactly as today.
15. In `api` mode, `aigen-backend` performs no write to `task_board` and does not read the
    `category_group`, `matrix_auto_assign`, or `board_list` master tables (D-4).
16. In `api` mode, `exports_data` and `milestone_config` are neither written nor read (D-5).
17. Credentials never appear in logs, error messages, Sentry payloads, or HTTP responses.
18. Every transfer emits one structured log line carrying driver, `card_title`, item count, result
    or code, and duration. Failures are reported to Sentry tagged with the driver.

## Configuration contract

| Variable | Type | Required | Default | Notes |
|---|---|---|---|---|
| `ISOURCING_TRANSFER_DRIVER` | `database` \| `api` | no | `database` | Global switch (D-8) |
| `ISOURCING_API_BASE_URL` | URL | when driver is `api` | — | |
| `ISOURCING_API_TRANSFER_PATH` | string | when driver is `api` | — | Kept separate from the base URL so the path can change without touching code |
| `ISOURCING_API_USERNAME` | string | when driver is `api` | — | Basic Auth (D-2) |
| `ISOURCING_API_PASSWORD` | string | when driver is `api` | — | Basic Auth (D-2) |
| `ISOURCING_API_TIMEOUT_MS` | integer | no | `10000` | Matches the existing SAP integration |
| `ISOURCING_API_MAX_RETRY` | integer | no | `2` | Transient failures only |

Conditional requirements are enforced by the Joi schema: when the driver is `api`, a missing base
URL, path, or credential is a boot failure.

Per D-15, `ISOURCING_API_TRANSFER_PATH` defaults to `/api/public/isourcing/aigen-import-pr` and
stays overridable. The status endpoint is derived from the same base URL and needs no credentials.

## Persistence (new in contract v1.0)

The two-step protocol cannot work without state. Aigen needs a table in the primary schema — the
first migration this work requires:

`isourcing_transfer_requests`: `id`, `request_id`, `pr_number`, `server_group`, `card_title`,
`idempotency_key`, `attempt`, `line_items`, `status` (`queued`/`succeeded`/`failed`), `error_code`,
`error_message`, `rfq_number`, `vendor_batch`, `submitted_at`, `last_checked_at`.

`idempotency_key` is derived from `pr_number` + `server_group` + the sorted line-item list plus
`attempt`. The deterministic part keeps network retries safe; `attempt` is what makes a genuine
re-send possible after a terminal failure, since replaying a key over a failed request only returns
the stored failure.

## Contract v1.0 amendments

The published contract invalidates four assumptions behind behavioral contract items 8, 10, 11,
and 12. Those items are superseded by A-1 to A-8 below; everything else in the contract list
stands unchanged.

**A-1 — The canonical result gains a third outcome.** `pending` means accepted and queued, nothing
more. It carries `request_id`, `pr_number`, `server_group`, `card_title`, and `idempotency_key`.
The `database` driver never produces it.

**A-2 — `pending` is not success.** Callers must not mutate Aigen status, must not write the
milestone log, and must not deactivate the token. Those effects move to the reconciliation stage.
This is the one place where the port change reaches the callers we otherwise left alone.

**A-3 — Terminal outcomes come from a second call.** `GET {BASE_URL}/api/public/isourcing/status/{requestId}`,
no authentication. `succeeded` completes the transfer, `failed` carries `errorCode`, `queued` means
check again next run.

**A-4 — The body has exactly two top-level properties**, `pr_library` and `pr_items`. Unknown
fields are rejected with `400`, not silently dropped, so `source`, `correlation_id`, `actor`,
`reason`, and `idempotency_key` are never sent. `Idempotency-Key` is a header.

**A-5 — Only `pr_number` and `server_group` are mandatory.** Aigen still applies its own header
completeness check so both drivers reject the same incomplete source data; this is deliberately
stricter than the API.

**A-6 — Field names are iSourcing's, not Aigen's.** `pr_number` is sent without a prefix and
iSourcing derives the prefix itself, so `card_title` is constructed locally for results and logs
only. `company_code` is a string, `line_item` an integer, and every item repeats `server_group`
identically to the header.

**A-7 — Auto-assign needs three item fields together** (D-13). When any is missing, iSourcing still
creates the PR but skips assignment, leaving it `NEW` with no Category Leader. That is not an error
and must be logged explicitly, because nothing else makes it visible.

**A-8 — There is no upsert.** A PR that already exists cannot receive later items through this
path (D-14). Contract I-3 returns `501`.

### Result mapping

| API condition | HTTP | Canonical result | Retry |
|---|---|---|---|
| Accepted and queued | 202 | `pending` with `request_id` | — |
| Same `Idempotency-Key` replayed while queued or succeeded | 202 | `pending` with the same `request_id` | — |
| PR already exists, new key | 409 `PR_ALREADY_EXISTS` | success, idempotent marker (D-12) | No |
| Replayed key over a failed request | 409 | failure carrying the original `errorCode` | New key only |
| Missing idempotency header | 400 `IDEMPOTENCY_KEY_MISSING` | `ISOURCING_TRANSFER_FAILED` | No |
| Invalid payload | 400 `PAYLOAD_INVALID` | `ISOURCING_SOURCE_HEADER_INCOMPLETE` | No |
| Bad credentials | 401 `INVALID_CREDENTIALS` | `ISOURCING_TRANSFER_FAILED` | No — alert |
| Group out of scope | 403 `GROUP_SCOPE_VIOLATION` | `ISOURCING_TRANSFER_FAILED` | No |
| Unknown path or request | 404 | `ISOURCING_TRANSFER_FAILED` | No |
| Payload too large | 413 `PAYLOAD_TOO_LARGE` | `ISOURCING_TRANSFER_FAILED` | No — reject before sending |
| Endpoint misconfigured | 500 `CONFIGURATION_INVALID` | `ISOURCING_TRANSFER_FAILED` | **No** — alert admin |
| Queue unreachable | 503 `KAFKA_UNAVAILABLE` | `ISOURCING_TRANSFER_FAILED` | **Yes** |
| Network error or timeout | — | `ISOURCING_TRANSFER_FAILED` | **Yes** |
| Terminal `succeeded` | status | success | — |
| Terminal `failed` with `KAFKA_PUBLISH_FAILED`, `ASSIGNMENT_ERROR`, `PERSIST_ERROR`, `REQUEST_FAILED` | status | failure | Re-send with a new key, max 2 (D-17) |

`429` and `Retry-After` are not produced by the application. Any rate limiting would live in
infrastructure and be communicated separately.

### Limits

Payload stays under the 512,000-byte default; the hard ceiling is 4 MB. Aigen rejects an oversized
payload before sending rather than waiting for `413`. The path carries no version segment, there is
no health endpoint, and there is no lookup by PR number.

## Acceptance criteria

**AC-1 — Backward-compatible default**
Given `ISOURCING_TRANSFER_DRIVER` is unset, When the `dic` cron stage processes an expired token,
Then the transfer runs through the `database` driver and produces the same rows as before the
change.

**AC-2 — Switching without code change**
Given the application runs with `database`, When the value is changed to `api` and the app and cron
processes are restarted, Then every subsequent transfer goes through the public API with no file
change and no rebuild.

**AC-3 — Invalid value fails fast**
Given `ISOURCING_TRANSFER_DRIVER=mysql`, When cron starts, Then the process exits at boot with a
configuration error naming the valid values, and nothing is written to iSourcing.

**AC-4 — Missing API configuration fails at boot**
Given the driver is `api` and `ISOURCING_API_TRANSFER_PATH` is unset, When the process starts,
Then it exits at boot rather than failing during a transfer.

**AC-5 — Callers are driver-agnostic**
Given both call sites and the five cron handlers, When the code is reviewed, Then no caller reads
the driver value or branches on driver type.

**AC-6 — Identical contract across drivers**
Given a PR already present in iSourcing, When it is transferred in `database` mode and then in
`api` mode, Then both return `success: true` with the same field set and an "already exists"
message, and neither returns a field the other does not.

**AC-7 — No Aigen mutation on failure**
Given `api` mode and the API returns HTTP 500, When the `cs` stage processes a token, Then
`rfq_library` is unchanged, the token stays active, the failure is reported to Sentry tagged
`api`, and the next run retries the same token.

**AC-8 — Idempotency**
Given a transfer for `B1200027667` succeeded on a previous run, When cron transfers the same PR and
items again, Then no duplicate card or item is created and the result is success with
`Missing items added: 0`.

**AC-9 — Retry classification**
Given `ISOURCING_API_MAX_RETRY=2` and the API returns HTTP 400, When the transfer runs, Then no
retry is attempted and the failure is returned immediately.

**AC-10 — Timeout is honored**
Given `ISOURCING_API_TIMEOUT_MS=10000` and the API does not respond, When the transfer runs, Then
the request is aborted at approximately 10 seconds, classified as transient, and the cron process
is not left hanging.

**AC-11 — No dual write**
Given `api` mode, When a full cron cycle runs, Then `aigen-backend` issues no INSERT or UPDATE
against the `task_board` schema. Verified by code review plus a database-side privilege check,
since no reconciliation CLI is available (D-9 void).

**AC-12 — Rollback to database mode**
Given `api` mode is live, When the value is set back to `database` and the processes are restarted,
Then transfers resume through the database driver with no deploy and no migration.

**AC-13 — Credential confidentiality**
Given an `api` transfer fails with HTTP 401, When logs, the Sentry payload, and the HTTP response
are inspected, Then no credential material appears in any form.

**AC-14 — Traceability**
Given any completed transfer, When the logs are inspected, Then one structured line records driver,
`card_title`, item count, result or code, and duration.

**AC-15 — Contract-shaped payload**
Given driver `api`, When a transfer is sent, Then the body has exactly `pr_library` and `pr_items`,
`Idempotency-Key` travels as a header, `pr_number` carries no prefix, `company_code` is a string,
every `line_item` is an integer, and each item repeats the header's `server_group`.

**AC-16 — `202` is not success**
Given the API returns `202`, When the transfer completes, Then the port returns `pending` with a
`request_id`, `rfq_library` is unchanged, no milestone log is written, and the token stays active.

**AC-17 — Reconciliation completes the transfer**
Given a stored request whose status becomes `succeeded`, When the reconciliation stage runs, Then
the Aigen status mutation and token deactivation happen exactly once, and a rerun does not repeat
them.

**AC-18 — Re-send uses a fresh key**
Given a stored request that ended `failed` with a transient `errorCode`, When Aigen re-sends, Then
the `Idempotency-Key` differs from the previous attempt and `attempt` is incremented, stopping
after 2 automatic re-sends.

**AC-19 — Retry classification matches the contract**
Given `503` or a network error, Then the request is retried within the configured bound; given
`500 CONFIGURATION_INVALID`, `400`, `401`, `403`, or `413`, Then no retry is attempted.

**AC-20 — Assignment gaps are visible**
Given an item missing any of `material_group_code`, `extended_material_group_code`, or
`material_number_code`, When the transfer is sent, Then Aigen logs that assignment will be skipped
for that item, naming the missing fields.

## Out of scope

- Any behavioral change to the moved transfer logic.
- Adopting the hardening on `feat/enhancement-on-cron`. If that hardening is wanted later, it is a
  separate piece of work against the extracted driver.
- Correcting the `AGENTS.md` command list.
- Historical data migration or backfill in `task_board`.
- `task_board` schema changes and unique constraints — KI-012 and KI-013 remain open.
- `cli/apply-isourcing-repair-local.js` — not present on this baseline.
- `aigen-frontend`: the HTTP contract of `sendActionToCS` does not change.
- `aigen-import-pr`: verified read-only against `task_board`; unaffected. Its read access must be
  preserved when write grants for the `aigen-backend` account are revoked after cutover.
- Building the iSourcing endpoint itself.

## Verification plan

| Item | Method |
|---|---|
| Extraction | `tests/controllers/qcfController.manualSourcingHeader.test.js` and `tests/repository/qcfLibrary.isourcingTransaction.test.js` must pass unchanged |
| Resolver | Unit tests for default, both valid values, invalid value, and missing conditional configuration |
| Port | Unit tests for delegation, input validation, result-shape guard, and log emission |
| API driver | Unit tests with a mocked HTTP layer: success, already-exists, 4xx, 5xx, 429, timeout, retry bounds, credential redaction |
| Contract parity | A shared test asserting both drivers return the same result shape |
| Post-cutover | Code review plus a database-side privilege check. No automated reconciliation available |
| Command | `npm test` from `aigen-backend` |

No cron run, migration, or database-mutating integration test is authorized by this spec.

## Open items

| ID | Item |
|---|---|
| ~~OI-1~~ | **Closed 2026-08-24** by contract v1.0. |
| ~~OI-2~~ | **Closed.** `pr_logs` is iSourcing's internal responsibility; Aigen sends no lifecycle data (contract Q-4). |
| ~~OI-3~~ | **Closed.** Missing category mapping is not an error: the PR is created `NEW` without a Category Leader and waits for manual assignment (contract Q-5). Aigen logs it (A-7). |
| ~~OI-4~~ | **Closed.** Payload default 512,000 bytes, hard limit 4 MB. No application-level rate limit (contract Q-7). |
| ~~OI-5~~ | **Closed 2026-08-24.** A non-production base URL is configured and reachable. Verified by two read-only probes: the status endpoint answered `404 REQUEST_NOT_FOUND`, and a deliberately invalid `POST` answered `400 PAYLOAD_INVALID` — proving the credentials and transfer path are correct while writing nothing (contract §1 rejects at the gate). The live error body shape matched what the driver parses. |
| OI-8 | Per-item completeness of `external_material_group` and `sap_material_number` in real data is unmeasured. The columns exist and are populated enough to serve as a join key elsewhere, but the share of transfer-path items carrying all three is unknown. Low completeness means PRs arriving without a Category Leader. |
| OI-9 | The manual procedure for items that arrive after a PR exists (D-14) is not written. Owner and trigger are undefined. |
| ~~OI-10~~ | **Closed 2026-08-24.** §13 governs, not §3.1. iSourcing configured `/api/public/isourcing/aigen-import-pr` for the transfer and `/api/public/isourcing/status` for the status endpoint — both differ from the contract's illustrative paths. Code defaults and `.env.example` now carry the configured values, and both remain overridable per environment. |
| OI-6 | The two modes are not data-identical: `database` writes `exports_data` and resolves assignment locally, `api` does neither (D-4, D-5). A PR transferred through the API will have no `exports_data` row. Confirm this is acceptable for any consumer of the legacy iSourcing dashboard. |
| OI-7 | Post-cutover verification method, now that no reconciliation CLI exists. A read-only DBA query set is the minimum. |
