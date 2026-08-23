# iSourcing Transfer Driver (Database ↔ Public API)

## Status

- Planned. No code has been changed.
- Created: 2026-08-23
- Primary repository: `aigen-backend`
- Baseline decision: build on `feat/enhancement-on-cron` **after** it is merged into
  `develop-dot`. See "Prerequisite".
- Production data mutation: Not performed.
- Related analysis: `aigen-reports/20260822-210020-aigen-cron-auto-manual-sourcing-to-isourcing.md`
- Related API requirements: `aigen-reports/20260822-234523-isourcing-public-api-requirements-for-insert.md`

## Problem

`aigen-backend` transfers PR items into iSourcing by writing directly to the `task_board`
MySQL schema. The target is moving to a new system (isourcing-vanilla) that exposes a public
API, and direct database writes must stop.

The cutover date is not fixed. Both mechanisms therefore have to coexist in the codebase for
an unbounded period, and switching between them must not require a code change, a rebuild, or
a data migration — only an environment value change.

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
| D-9 | `reconcile:isourcing` (read-only, arriving with the baseline merge) is the post-cutover verification tool. |

## Prerequisite: baseline merge

`feat/enhancement-on-cron` (commit `af3d9d50`) already extracts the transfer logic out of the
controller into a dedicated service. It is **1 commit ahead of and 11 commits behind**
`develop-dot`, and is not merged.

Files changed by both sides since the merge base `bca8e387`:

- `src/controllers/qcfController.js`
- `src/cron.js`
- `src/repository/qcfLibrary.repository.js`
- `src/services/prService.js`
- `src/services/qcfService.js`
- `tests/repository/qcfLibrary.isourcingTransaction.test.js`

The 11 `develop-dot` commits the branch is missing include `fd2b23af` (per-line-item PO Published
scope and stuck expiry tokens) and `6792c167` (QCF controller param checking / board card mapping),
both of which touch the same expiry and transfer paths.

**No driver work starts before the merge is completed and the existing test suite is green.**
Building the driver on `develop-dot` in parallel would duplicate ~1,362 lines of the branch's
transfer service and produce a far worse conflict later.

## Verified baseline (post-merge)

Call chain on `feat/enhancement-on-cron`:

```
prService / qcfService (5 cron stages)
  → manualSourcingInvocationService.executeSystemManualSourcing({...})
      → qcfController.sendActionToCS
          → prosesToIsourcing(pr_number, server_groups, items)   ← thin 3-line adapter
              → manualSourcingTransferService.transferToISourcing({ prNumber, serverGroups, items })
```

`transferToISourcing` is the single persistence path. Its contract, verified from source:

| Aspect | Value |
|---|---|
| Input | `{ prNumber, serverGroups, items }`. Throws `TypeError` for a missing PR number, missing server group, or an empty item array. |
| Success result | `{ success: true, status, code: null, card_title, message, inserted_items, repaired_cards }` |
| `status` vocabulary | `created` \| `repaired` \| `already_consistent` |
| Failure result | `{ success: false, status: 'failed', http_status, code, card_title, message, details }` |
| Failure codes | `SOURCE_ITEMS_NOT_FOUND`, `SOURCE_PR_NOT_FOUND`, `MISSING_SERVER_GROUP`, `UNMAPPED_CATEGORY`, `TERMINAL_PR_NEW_ITEM`, `TERMINAL_REPAIR_PROHIBITED`, `DUPLICATE_ITEM_CARD`, `AMBIGUOUS_CARD_METADATA`, `AMBIGUOUS_LIFECYCLE`, `AMBIGUOUS_REPAIR_SOURCE`, `AMBIGUOUS_REPAIR_ARTIFACTS`, `EXISTING_ASSIGNMENT_CONFLICT`, `REPAIR_ITEM_SCOPE_MISMATCH`, `TRANSFER_POSTCONDITION_FAILED` |
| Transaction | One managed `database_isourcing` `SERIALIZABLE` transaction, retried up to 3 attempts on `ER_LOCK_DEADLOCK` / `ER_LOCK_WAIT_TIMEOUT` |

This contract is already driver-shaped. No caller needs to change to gain a driver layer.

## Target architecture

The driver seam sits exactly at `transferToISourcing`. Callers keep calling one function with one
signature and one result shape; only the implementation behind it varies.

```
qcfController.prosesToIsourcing()
        │
        ▼
isourcingTransfer.port.js          ← new: resolver + contract guard
        │  resolveDriver(config.isourcing.transferDriver [, scope])
        ├─► database driver → manualSourcingTransferService.transferToISourcing()   (unchanged)
        └─► api driver      → isourcingApiTransferService.transferToISourcing()     (new)
```

### File plan

| File | Change |
|---|---|
| `src/services/isourcing/isourcingTransfer.port.js` | New. Resolver, input validation, result-shape guard, structured logging. |
| `src/services/manualSourcingTransferService.js` | Unchanged. Becomes the `database` driver. |
| `src/services/isourcing/isourcingApiTransferService.js` | New. Skeleton `api` driver: request builder, Basic Auth, timeout, retry classification, error mapping. |
| `src/api/isourcing.api.js` | New. Axios instance (base URL, timeout, auth), following `src/api/api.js`. |
| `src/const/isourcing-transfer.js` | New. `TRANSFER_DRIVER`, canonical status and error-code constants. |
| `src/controllers/qcfController.js` | `prosesToIsourcing` points at the port instead of the concrete service. Expected diff: a few lines. |
| `src/helper/featureFlag.js` (or sibling) | Single read point for the driver value, following the `GEMS_MANUAL_PO_FLOW` pattern. |
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
7. The port is the only route to iSourcing. After the change, no caller reaches
   `manualSourcingTransferService` or any iSourcing repository insert directly.
8. Both drivers return the same result shape, the same `status` vocabulary
   (`created` / `repaired` / `already_consistent` / `failed`), and the same canonical error codes.
9. The `database` driver is not modified. Any behavioral change to it is out of scope and is
   rejected at review.
10. The `api` driver sends one request per PR carrying header plus all items (D-3), with an
    idempotency key derived deterministically from `card_title` plus the sorted `item_code` list.
11. The `api` driver retries only transient failures — timeout, network error, HTTP 5xx, HTTP 429 —
    with bounded backoff. Other 4xx responses are not retried.
12. An API response indicating the PR already exists maps to `status: 'already_consistent'` with
    `success: true`.
13. Partial success is treated as failure. The port returns `success: false` and records what was
    reported as created.
14. There is no automatic fallback between drivers (D-6). A failed transfer leaves the Aigen-side
    status, milestone log, and token untouched, exactly as today.
15. In `api` mode, `aigen-backend` performs no write to `task_board` and does not read the
    `category_group`, `matrix_auto_assign`, or `board_list` master tables (D-4).
16. In `api` mode, `exports_data` and `milestone_config` are neither written nor read (D-5).
17. Credentials never appear in logs, error messages, Sentry payloads, or HTTP responses.
18. Every transfer emits one structured log line carrying driver, `card_title`, item count,
    result status or code, and duration. Failures are reported to Sentry tagged with the driver.

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

## API driver result mapping

| API condition | HTTP | Canonical result |
|---|---|---|
| Created | 2xx | `success: true`, `status: 'created'` |
| Items added to an existing PR | 2xx | `success: true`, `status: 'repaired'` |
| Already exists | 2xx / 409 | `success: true`, `status: 'already_consistent'` |
| Header incomplete / validation error | 400 / 422 | `success: false`, `code: 'SOURCE_PR_NOT_FOUND'` or `'UNMAPPED_CATEGORY'` per the mapping table, otherwise `TRANSFER_POSTCONDITION_FAILED` |
| Unauthorized | 401 / 403 | `success: false`, non-retryable, alert |
| Rate limited | 429 | `success: false`, retryable, honor `Retry-After` |
| Server error / timeout / network | 5xx / — | `success: false`, retryable |

The concrete API-code-to-canonical-code table is filled in when the iSourcing contract is
published. Until then the driver ships with the mapping table stubbed and the path unset, so
selecting `api` without configuration fails at boot rather than at transfer time.

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
Given the five cron handlers and three HTTP routes, When the code is reviewed, Then no caller reads
the driver value or branches on driver type.

**AC-6 — Identical contract across drivers**
Given a PR that already exists in iSourcing, When it is transferred in `database` mode and then in
`api` mode, Then both return `success: true` with `status: 'already_consistent'`.

**AC-7 — No Aigen mutation on failure**
Given `api` mode and the API returns HTTP 500, When the `cs` stage processes a token, Then
`rfq_library` is unchanged, the token stays active, the failure is reported to Sentry tagged
`api`, and the next run retries the same token.

**AC-8 — Idempotency**
Given a transfer for `B1200027667` succeeded on a previous run, When cron transfers the same PR and
items again, Then no duplicate card or item is created and the port returns
`status: 'already_consistent'`.

**AC-9 — Retry classification**
Given `ISOURCING_API_MAX_RETRY=2` and the API returns HTTP 400, When the transfer runs, Then no
retry is attempted and the failure is returned immediately.

**AC-10 — Timeout is honored**
Given `ISOURCING_API_TIMEOUT_MS=10000` and the API does not respond, When the transfer runs, Then
the request is aborted at approximately 10 seconds, classified as transient, and the cron process
is not left hanging.

**AC-11 — No dual write**
Given `api` mode, When a full cron cycle runs, Then `aigen-backend` issues no INSERT or UPDATE
against the `task_board` schema.

**AC-12 — Rollback to database mode**
Given `api` mode is live, When the value is set back to `database` and the processes are restarted,
Then transfers resume through the database driver with no deploy and no migration.

**AC-13 — Credential confidentiality**
Given an `api` transfer fails with HTTP 401, When logs, the Sentry payload, and the HTTP response
are inspected, Then no credential material appears in any form.

**AC-14 — Traceability**
Given any completed transfer, When the logs are inspected, Then one structured line records driver,
`card_title`, item count, result status or code, and duration.

## Out of scope

- Any behavioral change to the `database` driver.
- Historical data migration or backfill in `task_board`.
- `task_board` schema changes and unique constraints — the concurrency residual risk recorded in
  KI-012 and KI-013 is unchanged by this work.
- `aigen-frontend`: the HTTP contract of `sendActionToCS` does not change.
- `aigen-import-pr`: verified read-only against `task_board`; unaffected. Its read access must be
  preserved when write grants for the `aigen-backend` account are revoked after cutover.
- Building the iSourcing endpoint itself.

## Verification plan

| Item | Method |
|---|---|
| Baseline merge | Existing suite green after merge, before driver work begins |
| Resolver | Unit tests for default, both valid values, invalid value, and missing conditional configuration |
| Database driver | Existing branch tests must keep passing unchanged |
| API driver | Unit tests with a mocked HTTP layer: success, already-exists, 4xx, 5xx, 429, timeout, retry bounds, credential redaction |
| Contract parity | A shared test asserting both drivers return the same result shape and status vocabulary |
| Post-cutover | `reconcile:isourcing` (read-only), available after the baseline merge (D-9) |
| Command | `npm test` from `aigen-backend` |

No cron run, migration, or database-mutating integration test is authorized by this spec.

## Open items

| ID | Item |
|---|---|
| OI-1 | The iSourcing API contract is not published. Path, payload shape, and error codes remain stubbed (D-1). |
| OI-2 | Whether `pr_logs` becomes iSourcing's internal responsibility or Aigen must still supply initial lifecycle data. |
| OI-3 | Behavior when `pr_material_group_number` has no category mapping. The database driver currently fails with `UNMAPPED_CATEGORY`; the API equivalent is undefined. |
| OI-4 | Rate limit and maximum payload size on the iSourcing side. |
| OI-5 | Availability of a non-production iSourcing environment for pre-cutover testing. |
| OI-6 | The two modes are not data-identical: `database` writes `exports_data` and resolves assignment locally, `api` does neither (D-4, D-5). A PR transferred through the API will have no `exports_data` row. Confirm this is acceptable for any consumer of the legacy iSourcing dashboard. |
