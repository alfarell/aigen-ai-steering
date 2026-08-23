# Product

## Purpose

- **Verified:** Aigen supports procurement sourcing from released Purchase Requests (PR) through Request for Quotation (RFQ), vendor quotation, internal review, Quotation Comparison Form (QCF), and eventual purchase-order handling.
- **Verified:** The solution has three runtimes: the import worker, the backend API/cron processes, and the frontend web application.
- **Inferred:** The business goal is to automate eligible low-value sourcing while preserving manual sourcing and multi-role approval paths.

Evidence: `aigen-import-pr/services/aigen.js`, `aigen-backend/src/routes/purchaseRoutes.js`, `aigen-frontend/src/router/index.js`.

## Actors

| Actor | Verified capability | Evidence |
|---|---|---|
| Vendor | Opens an emailed token link, reviews an RFQ, submits/declines quotation data and attachments | `aigen-frontend/src/features/form/vendor/`, `aigen-backend/src/routes/purchaseRoutes.js` |
| CS | Monitors RFQ work, handles missing/declined/mismatched quotations, surrogate entry, and manual-sourcing transitions | `aigen-frontend/src/features/dashboard/cs/`, `aigen-frontend/src/features/form/cs/` |
| DIC/User | Confirms quotation items, requests revision, or continues sourcing | `aigen-frontend/src/features/form/dic/` |
| CL | Reviews and approves QCF summaries | `aigen-frontend/src/features/form/cl/`, `aigen-backend/src/services/qcfService.js` |
| Management | Reviews QCFs when approval configuration requires it | `aigen-backend/src/routes/purchaseRoutes.js`, `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.js` |
| Admin | Maintains users, roles, divisions, categories, hierarchy, material assignment, and category matrices | `aigen-backend/src/routes/aclRoutes.js`, `aigen-backend/src/routes/masterDataRoutes.js` |
| System/worker | Imports PRs, assigns vendor/CS/CL, creates RFQs, sends notifications, expires workflow stages, and syncs SAP PO state | `aigen-import-pr/services/aigen.js`, `aigen-backend/src/cron.js`, `aigen-backend/src/sync.js` |

The expansions and exact organizational ownership of CS, DIC, and CL are **Unknown**.

## Main journeys

1. **PR import and eligibility**
   - **Verified:** The importer reads released PR rows from the iSearch `search_library`.
   - **Verified:** It rejects already-imported/boarded rows, applies `config_auto_po`, resolves assignment, and stages eligible rows in `aigen.pr_library`.
2. **RFQ creation**
   - **Verified:** Staged rows are grouped by PR, vendor, and CS. Groups below the configured threshold receive an RFQ number and rows in `rfq_library`.
   - **Verified:** The importer calls backend email endpoints for vendor and PR-recipient notifications.
3. **Quotation and review**
   - **Verified:** Vendor responses move through DIC, CS/OE handling, CL, and optional Management review, driven by milestone/status/config data.
4. **QCF and PO**
   - **Verified:** QCF views and approval routes exist; SAP Auto PO sync is started by `aigen-backend/src/sync.js`.
   - **Verified:** A feature flag gates a GEMS manual-PO pilot and changes CL/Management/manual-sourcing policy.
5. **Administration**
   - **Verified:** Authenticated admin interfaces manage ACL and procurement master data.

## Business rules visible in code

- **Verified:** Material assignment resolution is most-specific existing row: material number → extended material group → material group. If a matched row exists without a valid vendor configuration, it intentionally routes to manual sourcing instead of falling back.
- **Verified:** RFQ numbering uses `RFQ` plus a seven-digit counter in the import worker.
- **Verified:** Multiple workflow deadlines use business-day utilities, excluding weekends. Holiday behavior is **Unknown**.
- **Verified:** Frontend access combines authenticated role metadata with public token-based Vendor/DIC routes; backend authorization remains the security boundary.
- **Verified:** Approval behavior can vary by server group (`BCG`, `GEMS`), configuration, and feature flags.
- **Unknown:** Formal SLA values, approval monetary thresholds, holiday calendars, vendor-selection policy, and authoritative status-transition matrix are database/configuration-owned and are not fully recoverable from source.

## Scope boundaries

- Aigen reads SAP-derived PR data from iSearch; the ownership and refresh mechanism of the upstream SAP snapshot are **Unknown** in these repositories.
- The import worker reads iSourcing/task-board data but current code does not intentionally write to that schema.
- Email delivery, Google OAuth, Sentry, SAP APIs, Kafka, and database infrastructure are external dependencies.

