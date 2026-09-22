# Requirements — QCF approval email link opens a blank page

Status: Planned
Owner: Unknown
Repositories: frontend (`aigen-frontend`)
Created: 2026-09-21
Last updated: 2026-09-21

## Background and problem

The QCF "Quotation Summary" approval email contains a "Link Tautan" anchor
(`aigen-backend/src/helper/template/approval-for-quotation-summary.js:152`)
pointing at `${frontendUrl}/#/quotation-summary/token/${token}`, built by
`generateApprovalQuotationSummaryLink` for Category Leader
(`aigen-backend/src/helper/emailHelper.js:717`) and
`generateManagementApprovalLink` for Management (`:788`). Approvers report that
clicking it opens a completely blank page, while opening the same QCF from the
dashboard works normally.

Incident reference: QCF0000914 / RFQ0002259, server group BCG, email sent
2026-09-18. The identical symptom was reported roughly six weeks earlier for
QCF0000799 / RFQ0002057 with a different approver whose role was Category
Leader, so the defect survived a previous report. Approver identities, the PR
number, and item descriptions are omitted here per
`aigen-ai/workflows/bug-fix.md`.

### Confirmed defect

Two faults compound, and together they explain exactly why the dashboard route
works while the email route does not.

**F1 — `qcf_number` is always `undefined` on the token route.**
`aigen-frontend/src/features/form/cl/action/QuotationSummaryCL.vue:50` reads
`route.params.qcf_number`, but the token route
(`aigen-frontend/src/router/index.js:365`) only supplies `:token`. The component
never decodes the JWT to recover `qcf_number`. `load()` (`:175-184`) then passes
that `undefined` into `getManagementQuotation(qcfNumber.value)` (`:181`) or
`getQuotation(qcfNumber.value)` (`:183`).

**F2 — the token is recovered by calling `useRoute()` inside the service layer.**
`aigen-frontend/src/services/form/cl/QuotationSummaryCLService.js:125` and
`:152` each call `useRoute()` inside a plain async service function to recover
the token, then choose between
`/pr/cl/need_approval_qcf/token/${token}` (`:129`) and
`/pr/cl/need_approval_qcf/${qcfNumber}` (`:130`). `useRoute()` resolves through
`inject()`, whose contract is synchronous use inside `setup()`. The existing
`route?.params?.token` optional chaining at `:126` and `:153` shows the author
already anticipated `route` being `undefined`. When it is, `token` is
`undefined` and the URL falls back to the second form — which on the token route
is `/pr/cl/need_approval_qcf/undefined`.

On the dashboard route `qcf_number` is populated, so the F2 fallback still
produces a valid URL and the defect stays invisible. On the token route it does
not. The CS branch in the same `load()` is already correct
(`QuotationSummaryCL.vue:179` passes `routeToken.value` explicitly to
`getCSQuotationByToken`), which is the pattern the CL and Management branches
should follow.

### What is not yet explained

Why the page is **fully blank** rather than redirecting. Every `catch` branch in
`QuotationSummaryCL.vue:206-221` routes to `/page-expired` or `/page-forbidden`,
and both routes exist (`aigen-frontend/src/router/index.js:129,134`). The
template (`:372-711`) renders unconditionally and `summary.items` defaults to
`[]` (`:67`), so an empty result would render an empty table, not an empty page.
Two candidate mechanisms remain, neither provable from source — see Dependencies
and unknowns. The fix must therefore be correct regardless of which is true, and
must make this class of failure visible rather than blank.

### Ruled out

- Hash-routing mismatch. The router uses `createWebHashHistory`
  (`aigen-frontend/src/router/index.js:476`), so the `/#/` link format is correct.
- A missing backend endpoint. Both token endpoints already exist and are already
  correct: `aigen-backend/src/routes/purchaseRoutes.js:220` and `:250`.
- Token expiry or deactivation as the cause of *blankness*. An expired token
  yields a 403 that `QuotationSummaryCL.vue:206-218` handles explicitly by
  navigating to `/page-expired`, which would be visible, not blank.
- Any relationship to `aigen-ai/specs/active/rfq-vendor-token-not-created/`.
  That defect concerns **vendor** tokens (`rfq_token_email`, the RFQ submission
  path); this one concerns **approver** tokens (`qcf_token_email`,
  `emailHelper.generateApprovalQuotationSummaryLink` /
  `generateManagementApprovalLink`). They share no helper, model, or controller.

## Goal

An approver who clicks the approval link in the Quotation Summary email reaches
the Quotation Summary page for that QCF and can approve it, and no failure on
that route ever renders an empty page.

## Scope

- Included:
  - Passing the route token explicitly from the component into the CL and
    Management fetch functions, and removing `useRoute()` from those two service
    functions.
  - A visible loading and error state on the Quotation Summary page so a failed
    or slow load never renders an empty shell.
  - Tests covering the token route, the dashboard route, and the failure paths.
- Excluded:
  - Making the approval link work **without** an existing dashboard login. The
    backend already requires it (see BR-2); changing that is a separate product
    decision and a materially larger change. See Dependencies and unknowns.
  - The same `useRoute()`-inside-a-service pattern at six other call sites:
    `aigen-frontend/src/services/form/cs/DeclinedItemsCSService.js:6`,
    `NotSubmittedItemsCSService.js:7`, `PriceNotMatchCSService.js:21`,
    `OERevisionCSService.js:6`, and `SurrogateItemsCSService.js:25,38`. None is
    implicated in a reported symptom. Named here as a follow-up so the pattern is
    on record, not actioned.
  - Two pre-existing backend authorization gaps found during investigation and
    recorded in Dependencies and unknowns. Neither causes the blank page.
  - Any backend or database change. No migration.

## Actors

| Actor/system | Need or responsibility |
|---|---|
| Category Leader approver | Opens the emailed link and approves the Quotation Summary. |
| Management approver | Same, through the Management branch and endpoint. |
| CS user | Already reaches this route read-only via the GEMS Manual PO notification; must not regress. |
| AiGen backend | Issues the token, sends the email, serves the QCF by token. Unchanged. |
| Support engineer | Needs a visible failure state instead of a blank page in order to triage. |

## Functional requirements

- **FR-1:** On the token route, the CL fetch must request
  `/pr/cl/need_approval_qcf/token/<token>` using the token from the route.
- **FR-2:** On the token route, the Management fetch must request
  `/pr/management/need_approval_qcf/token/<token>` using the token from the route.
- **FR-3:** Neither fetch may depend on `useRoute()` or any other composable
  resolved from inside the service function. The token must be supplied by the
  caller.
- **FR-4:** On the dashboard route, where a `qcf_number` param is present and no
  token is, both fetches must continue to request the existing
  `/pr/{cl,management}/need_approval_qcf/<qcf_number>` URLs unchanged.
- **FR-5:** The CS read-only branch (`QuotationSummaryCL.vue:179`) must keep
  working unchanged.
- **FR-6:** While the QCF is loading, the page must render a visible loading
  state rather than an empty shell.
- **FR-7:** If loading fails for any reason, the page must render a visible error
  state until navigation away completes, so no code path can leave the page
  blank.

## Business rules

- **BR-1:** The approval link is single-purpose: it opens one QCF's Quotation
  Summary for the approver named on that token. **Confirmed** by
  `emailHelper.js:664-676`.
- **BR-2:** Today the approval link requires an active dashboard session. Both
  token routes place `authService.authenticateToken` **before**
  `tokenMiddleware.decodeTokenWithForbiddenException`
  (`aigen-backend/src/routes/purchaseRoutes.js:220-223` and `:249-253`), and the
  frontend guard sends unauthenticated visitors to `/login` because
  `QuotationSummaryCLToken` is absent from `publicPages`
  (`aigen-frontend/src/router/index.js:80-91`, guard at `:503-506`).
  **Confirmed** by code — and in direct tension with the reported expectation
  (see Dependencies and unknowns).
- **BR-3:** The JWT carries only `{ qcf_number, rfq_number, vendor_code, iat }`
  (`aigen-backend/src/helper/emailHelper.js:668-673`). `user_type` is written
  only to the `qcf_token_email.user_type` **column** (`:691`), never into the
  token. **Confirmed.** Consequence: CL-versus-Management branching cannot key
  off the token, so the current branch on `authStore.userRole`
  (`QuotationSummaryCL.vue:100`) stays as designed.
- **BR-4:** The token table is `qcf_token_email`
  (`aigen-backend/src/models/default/qcfTokenEmail.js`), not `rfq_token_email`.
  The original report named the wrong table. **Confirmed.**

## Security and permissions

- Authentication mechanism: dashboard Bearer JWT via
  `authService.authenticateToken`, then the emailed approval JWT verified by
  `tokenMiddleware.decodeTokenWithForbiddenException`
  (`aigen-backend/src/middleware/tokenMiddleware.js:82-106`).
- Required roles: the frontend route allows `ADMIN`, `CL`, `MANAGEMENT`, `CS`
  (`aigen-frontend/src/router/index.js:373`). The Management token endpoint
  additionally checks the role in the controller
  (`aigen-backend/src/controllers/qcfController.js:1833-1840`).
- Sensitive data and logging constraints: the approval JWT appears in the URL and
  therefore in browser history and any referrer. This is pre-existing and
  unchanged by this fix. Do not add the token to application logs, Sentry breadcrumbs,
  or test fixtures. Use a placeholder token in all tests.
- Abuse or replay considerations: unchanged. This fix adds no new endpoint and
  relaxes no guard. Note the two pre-existing gaps recorded below — this change
  neither widens nor narrows them.

## Acceptance criteria

- **AC-1:** Given the token route with `params.token = "<token>"` and a signed-in
  CL, when the page loads, then the request goes to
  `/pr/cl/need_approval_qcf/<token>`-form URL carrying the real token, and not to
  any URL containing `undefined`.
- **AC-2:** Given the same with a signed-in Management user, then the request goes
  to the Management token URL carrying the real token.
- **AC-3:** Given the dashboard route with `params.qcf_number` set and no token,
  when the page loads, then the request URL is the existing non-token form and is
  unchanged from current behavior.
- **AC-4:** Given the CS read-only token path, when the page loads, then
  `getCSQuotationByToken` is still called with the route token and behavior is
  unchanged.
- **AC-5:** Given `getQuotation` or `getManagementQuotation` called directly with
  no active component instance, when it runs, then it does not call `useRoute()`
  and does not throw or emit a Vue injection warning.
- **AC-6:** Given a load that has not yet resolved, when the page renders, then a
  visible loading state is present and the page is not empty.
- **AC-7:** Given a load that rejects with a 403 and `error_code`
  `NOT_AUTHORIZED`, then a visible error state renders and navigation to
  `/page-forbidden` still occurs.
- **AC-8:** Given a load that rejects with a 404 or `error_code`
  `QCF_NOT_FOUND`, then a visible error state renders and navigation to
  `/page-expired` still occurs.
- **AC-9:** Given any rejection at all, when the page settles, then the rendered
  DOM is never empty.

## Non-functional requirements

- Performance and concurrency: no change. One GET per page load, as today.
- Reliability and idempotency: the fetch is an idempotent GET. No new writes.
- Observability: the existing `Sentry.captureException` in the `catch`
  (`QuotationSummaryCL.vue:196`) is retained. The new error state makes the
  failure visible to the user as well as to Sentry.
- Accessibility and UX: the loading and error states must be readable text, not
  a spinner alone, so the page communicates its state without color or motion.
- Compatibility: no API contract change. Frontend deploys independently of the
  backend.

## Dependencies and unknowns

| Item | Status | Owner/evidence |
|---|---|---|
| Why the page is blank rather than redirected | Unknown | Needs browser console and Network output from the next recurrence. Candidate A: an exception during `<script setup>` or the pre-`await` portion of the service call crashes the component before any `catch` runs — no `app.config.errorHandler` fallback UI was found. Candidate B: the approver was not signed in, the guard redirected to `/login`, and what was reported as "blank" was that page. Ask the reporter to capture the failing request URL — if it contains `undefined`, Candidate A is confirmed. |
| Should the link work without a dashboard login? | **Unresolved product decision** | The report's Expected Result says "tanpa perlu login ke dashboard", but BR-2 shows the backend requires login today. Reading A (recommended, and what this spec implements): the link is a deep link into the authenticated dashboard; fix the broken link and treat the expectation text as inaccurate. Reading B: passwordless approval is a real requirement — that needs new middleware ordering on both token routes, DB-backed token validation, and a frontend guard change, and belongs in its own spec. |
| Role of the approver in the incident | Unknown | Does **not** affect the diagnosis: `QuotationSummaryCL.vue:181` and `:183` both pass `undefined` on the token route, so CL and Management are equally broken. |
| Whether to add `@vue/test-utils` as a devDependency | **Unresolved** | It is not currently installed (`aigen-frontend/package.json`), so component-mount tests are not possible without adding it. See `test-plan.md` — service-level tests need no new dependency but cannot catch a regression in the component's argument passing, which is exactly where the fix lives. |
| Backend gap: `getApprovalQCFByCL` has no role guard | Unknown impact, **out of scope** | `aigen-backend/src/controllers/qcfController.js:1562-1691` has no equivalent to the Management variant's role check at `:1833-1840`. Any authenticated user with a valid-signature token can read CL QCF data. Candidate follow-up spec. |
| Backend gap: approver tokens are not validated against the database | Unknown impact, **out of scope** | `decodeTokenWithForbiddenException` (`aigen-backend/src/middleware/tokenMiddleware.js:82-106`) only runs `jwt.verify` and never checks `qcf_token_email.is_active` or `date_expired`, unlike the vendor path `decodeTokenFromParams` (`:13-54`). A token revoked in the database still authorizes a read until the JWT itself expires. Candidate follow-up spec. |
