# Requirements — Vendor revision resubmission must include a newly uploaded quotation document

Status: Implemented (frontend, backend), not yet released  
Owner: Unknown  
Repositories: aigen-frontend, aigen-backend (no DB schema change, no route change, additive response field)  
Created: 2026-10-12  
Last updated: 2026-10-12

## Background and problem

Reported case: **RFQ0002018**, vendor **108175**, quotation **A009-002**.

Verified evidence:

- The original quotation PDF was uploaded on 2026-09-02 (`documents.id = 5190`, batch 2).
- DIC requested a revision on 2026-09-03 for items 260 and 270.
- The vendor resubmitted revised prices on 2026-09-03 23:51 (item 260: 106,250 -> 24,000; item 270:
  81,250 -> 20,000) **without uploading a new quotation document**.
- QCF0000827 was approved and PO 4910020970 was issued with the revised prices (the PO matches the QCF;
  verified via `prpo.search_library`). The approved prices are therefore not backed by the quotation
  document that is attached.
- Correction of that PO is done in SAP by the business. No AiGen data fix is part of this change.

Root cause: `validateHeader()` in
`aigen-frontend/src/features/form/vendor/quotation/hooks/useQuotationValidation.js` accepts
`form.existingDocumentUrl` (the document from the previous submission) as sufficient, also when the form is in
revision mode (`status_milestone = quotation reviewed` and `status_submilestone = dic request revise`).

## Goal

When a vendor resubmits a quotation after a DIC revision request, a newly selected quotation document is
mandatory, so revised prices are never approved against an outdated document.

## Scope

- Included:
  - Frontend validation on the vendor quotation form (`/#/vendor/quotation/:token`) in revision mode.
  - Backend enforcement in `bulkUpdateRfqStatusVendor` (`prController.js`,
    `PUT /pr/vendor/submit_penawaran`) using `log_quotation` (status 'request revision by dic') as the
    "revision requested at" timestamp.
  - QCF screens link the document that belongs to the approved quotation (not blindly `is_latest`) and expose
    an additive `documentOutdated` flag, with a warning on the CL/Management QCF screens
    (`qcfController.js`: `getApprovalQCFByCL`, `getApprovalQCFByManagement`,
    `getApprovalQCFByManagementToken`).
- Excluded (follow-ups):
  - `prController.getApprovalRFQByCl` (`GET /pr/cl/need_approval_items/:rfq_number/:vendor_batch`, ~3501):
    its document lookup is RFQ-wide (no vendor) and its items carry no quotation date; the frontend does not
    call it. Unchanged.
  - The vendor-side header lookups in `prController.js` (~282, ~430) that also use `is_latest`.
  - Persisting the price-out-of-band flag (`prController.js` ~1101-1117) - implemented separately.
  - SAP payload logging (spec `sap-auto-po-item-code-mismatch`, D2) - implemented separately.
  - The double upload on "Lanjutkan tanpa revisi".
  - Any change to `FileInput.vue` or `handleRemoveDocument` behaviour.

## Actors

| Actor/system | Need or responsibility |
|---|---|
| Vendor | Must attach the revised quotation document when resubmitting after a DIC revision request |
| DIC / CS / CL | Approve prices that are supported by the attached quotation document |

## Functional requirements

- **FR-1:** `useQuotationValidation(form, isRevision)` accepts an optional second argument (boolean or Vue
  ref, default `false`) and reads it at validation time (`unref`), not at setup time.
- **FR-2:** In revision mode, if no new file is selected (`form.document` empty), validation fails with
  `errors.header.document = 'Dokumen quotation revisi wajib di upload'`, even when
  `form.existingDocumentUrl` is set.
- **FR-3:** Outside revision mode, behaviour is unchanged: an existing document is sufficient; with neither a
  new nor an existing document the message stays `Dokumen wajib di upload`.
- **FR-4:** The 5 MB size check on a newly selected document is unchanged.
- **FR-5:** `VendorQuotation.vue` passes the `isRevision` ref itself (it is set asynchronously in
  `loadData()`), not its value.
- **FR-6:** The error is shown on the document field and in the "Data belum sesuai" dialog
  (`buildValidationErrors` / `renderValidationErrors` list all header errors generically).
- **FR-7 (backend helpers in `Document.repository.js`):**
  - `getLatestRevisionRequestAt(itemIds, { before })` returns MAX(`log_quotation.created_at`) where
    `status = 'request revision by dic'` and `item_id` (= `rfq_library.id`) is in `itemIds` (and
    `created_at <= before` when given); `null` for no ids or no match.
  - `getDocumentForQuotation({ rfqNumber, vendorCode, quotationDate })` returns the latest document for
    rfq + vendor with `createdAt <= quotationDate` (order `createdAt DESC, id DESC`); with a null
    `quotationDate` or no earlier document it falls back to `is_latest = true`.
  - `hasDocumentCreatedAfter` and `getQuotationDocumentInfo` build on these.
- **FR-8 (backend enforcement):** In `bulkUpdateRfqStatusVendor`, for items with
  `status_vendor = ACCEPTED` only, **and only ids that are items of the token's RFQ** (present in the
  `getPRDetails({ rfq_number })` map; foreign or stale payload ids are ignored for this check):
  - Revision signal: a `log_quotation` revision request exists for those ids, **or** any of those items'
    current DB row (read before any write) has `status_dic = REQUEST_REVISION (3)`. The log is written
    best-effort (`addLogQuotationByDataItems` inside `Promise.allSettled`) and can be missing: in the local
    DB 24 of 430 `rfq_library` rows with `status_dic = 3` have no such log row, hence the status fallback.
  - Threshold: the latest revision request when present. When any of those items is currently in
    `status_dic = 3`, it is the later of that request and the latest previous `quotation_date` among those
    items' pre-update rows (nulls ignored; with no log it is just the `quotation_date`). In the normal flow
    the order is quotation_date < revision log < new document, so the result is unchanged; the stricter rule
    closes a second-cycle revision whose log write failed (stale older log). Without any item in
    `status_dic = 3` the revision log alone is the threshold.
  - If a threshold exists and no `documents` row for (token `rfq_number`, `vendor_code`) has `createdAt`
    after it, respond `400` with `Dokumen quotation revisi wajib diupload ulang setelah permintaan revisi DIC.`
  - **Residual fail-open:** no revision log and either `status_dic` is not 3, or `status_dic = 3` but none of
    the items has a `quotation_date` (0 of 430 locally) - the check is skipped.
  The check runs after per-item validation and before any DB write (token deactivation, bulk update); the
  transaction is rolled back before returning. REJECTED and NEED_CONFIRMATION items never need a document.
  A DIC answer to a NEED_CONFIRMATION item sets `status_dic = 3` and writes a revision log, so when the
  vendor later submits that item as ACCEPTED, a document newer than the answer is required (the price is
  first offered after the answer). The backend 400 message tells the vendor to upload again.
- **FR-9 (QCF document link):** `getApprovalQCFByCL`, `getApprovalQCFByManagement` and
  `getApprovalQCFByManagementToken` resolve `documentLink` with `getDocumentForQuotation`, using
  quotationDate = MAX(`quotation_date`) over the QCF rows of the displayed vendor. The field name and shape
  of `documentLink` are unchanged.
- **FR-10 (outdated flag):** The same headers add the boolean `documentOutdated`: true when
  `getLatestRevisionRequestAt(<rfq item ids>, { before: quotationDate })` is not null and the chosen
  document's `createdAt` is earlier than it; otherwise false (also false without a document or quotation
  date).
- **FR-11 (frontend):** `mapQcfDetail` in `QuotationSummaryCLService.js` maps `documentOutdated`
  (default `false`); `QuotationSummaryCL.vue` and `PreviewQuotationSummaryCL.vue` show a `v-alert`
  (warning, tonal) next to "Dokumen Terkait" when it is true: "Dokumen quotation diunggah sebelum permintaan
  revisi DIC — harga pada QCF mungkin tidak sesuai dokumen."

## Business rules

- **BR-1:** Revision mode is defined as in the form today: `status_milestone = quotation reviewed` and
  `status_submilestone = dic request revise`.
- **BR-2:** In revision mode the previously uploaded document never satisfies the document requirement.
- **BR-3 (Inferred):** A vendor whose revised prices are unchanged still has to upload a document; the
  business accepts this to keep the rule simple.

## Security and permissions

- No new endpoint, role, request field, or schema change. The only response change is the additive
  `documentOutdated` boolean on the three QCF approval headers.
- The frontend check can be bypassed by calling the API directly; FR-8 enforces the rule server-side.

## Acceptance criteria

- **AC-1:** Revision mode and no new file selected, existing document present: submit is blocked, the field
  shows `Dokumen quotation revisi wajib di upload`, and the Swal summary lists it under "Informasi Quotation".
- **AC-2:** Revision mode and a new file (<= 5 MB) selected: validation passes, the document is uploaded and
  the submit proceeds as before.
- **AC-3:** Non-revision mode with an existing document and no new file: unchanged, validation passes.
- **AC-4:** Non-revision mode with no document at all: unchanged message `Dokumen wajib di upload`.
- **AC-5:** A new file larger than 5 MB: `Ukuran dokumen melebihi 5 MB` as before.
- **AC-6:** The requirement follows the `isRevision` flag after `loadData()` completes (ref passed, not a
  frozen value).
- **AC-7:** Submit with an ACCEPTED item that has a DIC revision request later than every uploaded document:
  HTTP 400 with the Indonesian message, transaction rolled back, `rfqTokenEmail` not deactivated,
  `bulkUpdateRfqItemsVendor` not called.
- **AC-8:** Same submit but a document with `createdAt` after the revision request exists: proceeds as before.
- **AC-9:** No revision request for the accepted items: proceeds as before; no document lookup is made.
- **AC-10:** Only REJECTED (or NEED_CONFIRMATION) items: no document requirement, no revision lookup.
  Submitting as ACCEPTED an item whose NEED_CONFIRMATION was answered by DIC requires a document newer than
  the answer (see FR-8); otherwise HTTP 400.
- **AC-10a:** No revision log but an accepted item has `status_dic = 3`: HTTP 400 unless a document newer than
  the items' previous `quotation_date` exists. With a log and `status_dic = 3` the threshold is
  max(log, previous `quotation_date`): a log older than `quotation_date` and a document only between the two
  gives 400; a document after `quotation_date` proceeds.
- **AC-10b:** An accepted payload id that is not an item of the token's RFQ is ignored by the check (no
  spurious 400); with only such ids no revision lookup is made.
- **AC-11:** QCF0000811 returns `documentOutdated = false`; QCF0000827 returns `documentOutdated = true`
  (document 5190 at 2026-09-02 23:22:18 earlier than the revision request at 2026-09-03 08:23:45) and the
  warning is displayed on the CL/Management QCF screen.
- **AC-12:** `documentLink` and every other existing response field keep their names and shape.

### Data validation (local DB snapshot)

- 1011 QCFs evaluated: 73 resolve to a different (earlier) document than `is_latest`; 5 need the
  `is_latest` fallback; 36 would be flagged `documentOutdated`.
- RFQ0002018 / vendor 108175: revision request logged 2026-09-03 08:23:45 for rfq_library ids 5746 and 5747;
  documents 5189 and 5190 are both from 2026-09-02, so a resubmission without a new document is rejected by FR-8.
  The helpers were also smoke-tested against the local DB (latest revision request, document 5190, outdated = true).
- `documents.createdAt` and `log_quotation.created_at` are both written in the application's local time and
  are directly comparable (same submit: document 23:22:18 vs log 23:22:19).

- `rfq_library.status_dic = 3`: 430 rows; 406 have a revision log, 24 do not (status fallback applies); all 430
  have a `quotation_date`. Of the 406, 336 have `quotation_date` < latest revision log (expected, e.g. ids
  7308/7309: 2026-10-09 16:29:31 vs 2026-10-12 12:57:24) and 70 have `quotation_date` >= the latest log (the
  vendor resubmitted and DIC requested another revision without a new log, or older data). For those 70 the
  threshold is the previous `quotation_date` (not the stale log), so a document older than it no longer
  satisfies the check (51 of them have a document newer than the stale log but none newer than
  `quotation_date`).
- Of the 24 rows without a log, 15 have no `documents` row at all for (rfq, vendor): such vendors can only
  resubmit after uploading a document.

### Related, tracked separately

- Price-out-of-band flag persistence and SAP payload logging are implemented in separate changes and are
  outside this spec's scope.

## Non-functional requirements

- Performance/concurrency: none.
- Reliability/idempotency: validation is pure; no new network calls.
- Observability: none.

## Verification notes

- No frontend test runner exists; verification is `eslint` plus manual check on a revision-mode token.
- Backend: `tests/controllers/prController.bulkUpdateRfqStatusVendor.revisionDocument.test.js` (AC-7..AC-10) and
  `tests/repository/Document.repository.revision.test.js` (FR-7, FR-9, FR-10). The `getApprovalQCFBy*`
  handlers have no dedicated header test; the flag is covered at helper level.
- Known UI behaviour (not changed): `FileInput.vue` shows `initFileName` (the old file name) in preference to
  the newly selected file name while an existing document is present, so after choosing a new file the field
  still displays the old name. The new file is nevertheless emitted into `form.document`, uploaded on submit,
  and clears the error.

## Open questions

- Resolved: `log_quotation` status 'request revision by dic' (`item_id` = `rfq_library.id`) marks the
  revision request.
- Follow-up: `getApprovalRFQByCl` (RFQ-level CL approval, no frontend caller) still uses `is_latest`.
- Follow-up: the read-time price-out-of-band flag on the DIC and CL/Management screens is specified in
  `../qcf-price-out-of-range-flag/requirements.md`.
- Should `FileInput` display the newly selected file name instead of the old one in revision mode?
