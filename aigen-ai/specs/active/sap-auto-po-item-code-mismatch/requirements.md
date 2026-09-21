# Requirements — SAP Auto-PO: item_code format mismatch and missing request-payload persistence

Status: Planned
Owner: Unknown
Repositories: backend (`aigen-backend`)
Created: 2026-09-21
Last updated: 2026-09-21

## Background and problem

When a Category Leader approves a QCF, `qcfController.approveByCL`
(`aigen-backend/src/controllers/qcfController.js:1432`) calls
`rfqLibraryRepo.syncAutoPO` (`:1510`) to create the Purchase Order in SAP. If the
QCF is not marked synced afterwards, the controller rolls the approval back to
`STATUS_MILESTONE.QCF_WAITING_APPROVAL` (17) and returns HTTP 500 (`:1513-1525`).

A production incident (QCF0000891 / RFQ0002064 / PR 8100020706 item 60, plant
O302, server group GEMS, document type ZGEN, vendor redacted) ended with
`po_number` empty, `is_sync = 0`, `status_milestone = 17`, and a `sync_message`
of `", [E], No instance of object type PurchaseOrder has been created. External
reference:, [E], PO header data still faulty, [E], Materials of requisition
8100020706 item 00060 alr. ordered in full"`, while SAP was reported to show no
PO on that PR item. Two code-level defects were confirmed by tracing the path.

**D1 — item_code compared with format-sensitive string equality.** AiGen stores
`item_code` unpadded (`"60"`); SAP refers to the same PR item padded (`"00060"`).
The column is `STRING(10)` and is stored unpadded from ingestion onward
(`aigen-import-pr/services/aigen.js:194`), and the outbound payload sends it
unpadded (`aigen-backend/src/repository/rfqLibrary.repository.js:1825`). Two
comparisons therefore fail silently:

- Success branch: `qcfLibrary.update(...)` filters on `item_code: dt.PR_ITEM`
  (`rfqLibrary.repository.js:1894-1906`). If SAP returns a padded `PR_ITEM`, the
  update matches **zero rows without raising an error** — SAP has created the PO,
  but AiGen leaves `po_number` null and `is_sync` false, the approval is rolled
  back, the user re-approves, and SAP rejects the second attempt with "alr.
  ordered in full". This is the leading hypothesis for the incident.
- Classifier: `toKey` (`aigen-backend/src/helper/sapFailureClassifier.js:19-21`)
  builds `pr_number::item_code` for both the parsed SAP text (padded) and the
  QCF's own `requisitionLines` (unpadded, built at
  `rfqLibrary.repository.js:1816-1819`). The keys never match, so
  `compareOrderedInFullScope` (`:47-60`) returns `null` and `classifySapFailure`
  falls through to the generic `SAP_SYNC_FAILURE`. The
  `SAP_ALL_ITEMS_ALREADY_ORDERED` and `SAP_PARTIAL_ITEMS_ALREADY_ORDERED`
  branches are effectively unreachable in production.

**D2 — the SAP request payload is never persisted.** Both call sites only
`console.log` the request (`rfqLibrary.repository.js:1860`,
`PurchaseRequest.repository.js:2183-2185`). The only durable artefacts are
`qcf_library.sync_message` (SAP's *response* text), `is_sync`, `po_number`,
`status_milestone`, and a `logActivity` row that also stores only the response
message. The payload for this incident therefore cannot be handed to the SAP team
retrospectively.

## Goal

A padded/unpadded difference in the PR item number can no longer cause AiGen to
lose a PO that SAP actually created, no SAP sync outcome is ever recorded
silently, and the exact request and response of every SAP Auto-PO attempt is
retrievable from the database afterwards.

## Scope

- Included:
  - Tolerant, format-insensitive comparison of `item_code` in the SAP Auto-PO
    sync path.
  - Removing the format-sensitive row filter from the `syncAutoPO` success-branch
    update.
  - Detecting and loudly reporting an unmatched or zero-row SAP response line.
  - Durable storage of the SAP Auto-PO request payload, raw response, HTTP
    status, and timestamp for both `syncAutoPO` and `getSyncSAP`.
  - Regression tests for the classifier, the new helper, and both repository
    paths.
- Excluded:
  - Changing how `item_code` is stored or ingested. The column stays unpadded;
    many unrelated joins, filters, and `GROUP BY` clauses across
    `rfqLibrary.repository.js` and `PurchaseRequest.repository.js` depend on the
    current format.
  - Changing the outbound payload shape sent to SAP. `line_item` continues to be
    sent unpadded, because SAP accepts it today in non-incident cases.
  - The per-item matching logic of the cron path `getSyncSAP`
    (`PurchaseRequest.repository.js:2212-2226`), which updates every line of a QCF
    by `qcf_number` plus `status_milestone` with no per-item correspondence to the
    SAP response. That is a separate defect shape, not exercised by this incident;
    it receives payload logging here and a follow-up ticket for the matching
    itself.
  - A retention or pruning job for log tables. None exists for any `log_*` table
    in this repository today.
  - Any frontend, mobile, or `aigen-import-pr` change.

## Actors

| Actor/system | Need or responsibility |
|---|---|
| Category Leader | Approves a QCF and expects the PO to be issued, or a truthful, actionable failure reason. |
| AiGen backend (`syncAutoPO`) | Builds and sends the PO payload, records the outcome against the correct `qcf_library` row. |
| AiGen cron (`getSyncSAP`) | Retries PO creation outside the approval flow. |
| SAP Auto-PO service | Creates the PO and returns `SUCCESS`, `MESSAGE`, and `DATA[].{PO_NUMBER, PR_NUMBER, PR_ITEM}`. |
| SAP support team | Needs the exact payload AiGen sent in order to diagnose a rejection. |
| Support and engineering on-call | Needs to tell "SAP rejected it" apart from "AiGen failed to record a PO that SAP created". |

## Functional requirements

- **FR-1:** PR item numbers that differ only by leading zeros (for example `60`
  and `00060`) must be treated as the same item wherever the SAP Auto-PO path
  compares an AiGen `item_code` against a value originating from SAP.
- **FR-2:** The comparison must be tolerant in both directions and must not assume
  a fixed pad width, because SAP's `PR_ITEM` response format is not confirmed (see
  Dependencies and unknowns).
- **FR-3:** On a successful SAP response, each returned `DATA` entry must update
  the `qcf_library` row it actually corresponds to, identified without relying on
  string equality of `item_code`.
- **FR-4:** If a returned `DATA` entry cannot be matched to a local row, or the
  resulting update affects zero rows, the sync must record an explicit error in
  both the application log and `logActivity`, naming the QCF number, PR number, PR
  item, and PO number, and must not fail silently.
- **FR-5:** Every SAP Auto-PO attempt — success, business rejection, and network
  or transport error — must persist the request payload, the raw response or error
  detail, the HTTP status when available, the originating QCF number, a success
  flag, and a timestamp.
- **FR-6:** FR-5 applies to both the approval-triggered path (`syncAutoPO`) and
  the cron path (`getSyncSAP`), and the stored record must distinguish which path
  produced it.
- **FR-7:** After FR-1, a SAP failure message containing "alr. ordered in full"
  for every line of the QCF must classify as `SAP_ALL_ITEMS_ALREADY_ORDERED`, and
  for a strict subset of lines as `SAP_PARTIAL_ITEMS_ALREADY_ORDERED`.
- **FR-8:** Persisted payloads must never contain the SAP Basic-auth credential.

## Business rules

- **BR-1:** An approval must not remain committed when the PO was not issued. The
  existing rollback to milestone 17 (`qcfController.js:1517-1525`) is correct and
  is retained. Source: existing implementation. **Confirmed.**
- **BR-2:** A QCF already marked `is_sync = true` must never be re-sent to SAP.
  Source: existing duplicate guard, `rfqLibrary.repository.js:1777-1786`.
  **Confirmed.**
- **BR-3:** "Materials of requisition &lt;pr&gt; item &lt;item&gt; alr. ordered in
  full" means SAP considers that PR item fully consumed by an existing PO.
  **Inferred** — not confirmed by the SAP team.
- **BR-4:** `item_code` is stored unpadded throughout AiGen and must remain so.
  Source: ingestion at `aigen-import-pr/services/aigen.js:194` plus existing
  consumers. **Confirmed** by code.
- **BR-5:** Whether SAP pads `PR_ITEM` in the `DATA` array of a success response
  is **Unknown**; only the padded form inside the error text has been observed.

## Security and permissions

- Authentication mechanism: HTTP Basic against the SAP Auto-PO endpoint;
  credentials resolved per `server_groups` by `getSapAutoPoConnection`
  (`aigen-backend/src/helper/sapAutoPo.js`).
- Required roles, permissions, token purpose: unchanged. The sync is reachable
  only from the existing Category Leader and management approval endpoints and the
  internal cron entry point.
- Sensitive data and logging constraints: the Basic-auth token is placed only in
  the HTTP `Authorization` header (`rfqLibrary.repository.js:1873-1876`) and is
  not part of `requestData` (`:1846-1859`). The new log must persist the request
  body only, never request headers. Vendor codes, prices, and PR numbers are
  business data and are acceptable in an internal log table; no personal data is
  involved.
- Abuse or replay considerations: the new log table is append-only and is not
  exposed through any API by this change. BR-2's duplicate guard remains the
  protection against replayed PO creation.

## Acceptance criteria

- **AC-1:** Given a `qcf_library` row with `item_code = "60"`, when SAP returns a
  success response whose `DATA[].PR_ITEM` is `"00060"` for the matching
  `PR_NUMBER`, then that row is updated with the returned `po_number`,
  `is_sync = 1`, and `status_milestone = SAP_SYNC_COMPLETE` (20).
- **AC-2:** Given AC-1's conditions, when the approval controller re-reads the
  sync status, then the approval is **not** rolled back and the endpoint does not
  return `SAP_SYNC_FAILED`.
- **AC-3:** Given a success response containing a `DATA` entry that matches no
  local row, when the sync processes it, then an explicit error is logged in both
  the application log and `logActivity`, naming the QCF number, PR number, PR
  item, and PO number, and the function completes without throwing.
- **AC-4:** Given a matched row whose `status_milestone` no longer satisfies the
  update guard, when the update affects zero rows, then the same explicit error
  reporting as AC-3 occurs.
- **AC-5:** Given a failure message of the incident's shape and a QCF whose local
  lines are unpadded, when `classifySapFailure` runs, then it returns
  `error_reason_code = SAP_ALL_ITEMS_ALREADY_ORDERED`.
- **AC-6:** Given a multi-line QCF where the message names only some lines as
  already ordered, and padding differs between the message and the local lines,
  when `classifySapFailure` runs, then it returns
  `SAP_PARTIAL_ITEMS_ALREADY_ORDERED`.
- **AC-7:** Given an already-padded message and already-padded local lines (the
  existing test fixtures), when `classifySapFailure` runs, then the result is
  unchanged from current behavior.
- **AC-8:** Given a non-numeric `item_code`, when it is normalized, then it is
  compared by strict string equality and no false match is produced.
- **AC-9:** Given any SAP Auto-PO attempt from `syncAutoPO` — success, business
  rejection, or thrown transport error — when it completes, then exactly one log
  row is written containing the request payload, the response or error detail, the
  HTTP status when available, the QCF number, the success flag, a source of
  `cl_approval_sync`, and a timestamp.
- **AC-10:** Given the same three outcomes from `getSyncSAP`, then the equivalent
  row is written with a source of `cron_sync`.
- **AC-11:** Given any persisted log row, when it is inspected, then it contains
  no `Authorization` header, no Basic-auth token, and no other credential.
- **AC-12:** Given the new migration, when it is applied and then rolled back on a
  scratch database, then both directions succeed and no other table is affected.

## Non-functional requirements

- Performance and concurrency: one additional INSERT per SAP attempt. SAP Auto-PO
  calls are low-volume and are already bounded by a 10 s axios timeout
  (`rfqLibrary.repository.js:1878`); the added write is negligible.
- Reliability and idempotency: BR-2's duplicate guard is unchanged. The log table
  is append-only with no uniqueness constraint — repeated attempts for one QCF are
  expected and are exactly what the SAP team needs to see.
- Observability: the payload log plus the FR-4 error reporting are the deliverable.
  A previously invisible failure mode becomes attributable.
- Accessibility and UX: no UI change. Approvers may now see the more specific
  "PO sudah terbuat di luar sistem AIGEN." message where the generic failure
  message was shown before, via the existing `error_reason_code` and
  `user_message` response fields (`qcfController.js:1533-1534`).
- Compatibility: no API contract, payload shape, or stored-data format changes.

## Dependencies and unknowns

| Item | Status | Owner/evidence |
|---|---|---|
| Exact format of `PR_ITEM` in SAP's success `DATA` array — padded or not | Unknown | SAP team. Only the padded form in the error text has been observed; the fix is deliberately format-tolerant rather than assuming a width. |
| Whether PR 8100020706 item 00060 ever had a PO that was later deleted in SAP | Unknown | SAP team — EBAN/EKPO history. Determines whether D1 caused the incident or merely hid it. |
| Whether the quantity AiGen sent exceeded the PR's open quantity | Unknown | SAP team. AiGen performs no open-quantity validation before sending (`rfqLibrary.repository.js:1820-1858`); out of scope here. |
| Whether any production `item_code` value is non-numeric | Unknown | The column is free-form `STRING(10)`. The normalizer falls back to strict equality for these, so current behavior cannot regress. |
| Precise line structure of SAP's "alr. ordered in full" message | Inferred | `sapFailureClassifier.js:7-10` already records that no real SAP sample was available when the regex was written. |
| Whether `getSyncSAP`'s unmatched per-item update is causing separate incidents | Unknown | Follow-up ticket; excluded from this spec. |
