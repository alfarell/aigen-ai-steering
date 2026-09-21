# Design — QCF approval email link opens a blank page

## Current behavior

Verified by reading the source; every claim is cited.

1. Backend composes the approval email. The CL link is built by
   `generateApprovalQuotationSummaryLink`
   (`aigen-backend/src/helper/emailHelper.js:653-719`) and the Management link by
   `generateManagementApprovalLink` (`:722-790`). Both produce
   `${frontendUrl}/#/quotation-summary/token/${token}` (`:717`, `:788`). The
   anchor is rendered at
   `aigen-backend/src/helper/template/approval-for-quotation-summary.js:152`.
2. The JWT payload is `{ qcf_number, rfq_number, vendor_code, iat }`
   (`emailHelper.js:668-673`). `user_type` is persisted only to the
   `qcf_token_email.user_type` column (`:691`), never signed into the token.
3. Both token endpoints already exist and are correct:
   `aigen-backend/src/routes/purchaseRoutes.js:220` (`/cl/need_approval_qcf/token/:token`)
   and `:250` (`/management/need_approval_qcf/token/:token`). Each runs
   `authService.authenticateToken` first, then
   `tokenMiddleware.decodeTokenWithForbiddenException`, then the controller.
4. The frontend route is `QuotationSummaryCLToken`, path
   `quotation-summary/token/:token`, component `QuotationSummaryCL`
   (`aigen-frontend/src/router/index.js:364-377`), with
   `roles: [ADMIN, CL, MANAGEMENT, CS]` and `redirect401: 'page-expired'`. The
   router uses `createWebHashHistory` (`:476`), so the `/#/` link form is correct.
5. `QuotationSummaryCL.vue:50` reads `route.params.qcf_number`. On the token
   route that param does not exist, so `qcfNumber.value` is `undefined`. The
   component holds the token at `:103` (`routeToken`) but never uses it for the
   CL or Management branch, and never decodes the JWT.
6. `load()` (`:175-184`) branches three ways:
   - `isCsTokenReadOnly` → `getCSQuotationByToken(routeToken.value)` (`:179`) —
     correct, passes the token explicitly.
   - `isManagementRole` → `getManagementQuotation(qcfNumber.value)` (`:181`).
   - otherwise → `getQuotation(qcfNumber.value)` (`:183`).
7. `getQuotation` (`aigen-frontend/src/services/form/cl/QuotationSummaryCLService.js:123-143`)
   and `getManagementQuotation` (`:149-172`) each call `useRoute()` inside the
   async function body (`:125`, `:151`) to recover the token, then select
   `/pr/cl/need_approval_qcf/token/${token}` (`:129`) versus
   `/pr/cl/need_approval_qcf/${qcfNumber}` (`:130`), and the Management
   equivalents at `:155-156`.
8. `catch` handling (`QuotationSummaryCL.vue:195-222`) captures to Sentry, returns
   early on 401 (the interceptor already navigated), navigates to
   `/page-forbidden` on `NOT_AUTHORIZED`, and to `/page-expired` on
   `QCF_NOT_FOUND` or 404 and as the final fallback. Both destination routes
   exist (`aigen-frontend/src/router/index.js:129,134`).
9. The template (`:372-711`) renders unconditionally, and `summary.items`
   defaults to `[]` (`:67`), so an empty result renders an empty table rather
   than an empty page.

### Failure mechanism

`useRoute()` resolves through `inject()`, whose contract is synchronous
invocation inside `setup()`. Calling it inside a plain async service function
has no guaranteed active component instance. The `route?.params?.token` optional
chaining at `:126` and `:153` shows the original author already expected `route`
to be absent sometimes. When it is, `token` is `undefined` and the URL falls
back to the `qcfNumber` form.

That fallback is harmless on the dashboard route, where `qcfNumber` is
populated, and fatal on the token route, where step 5 guarantees it is
`undefined` — producing a request to `.../need_approval_qcf/undefined`. This is
precisely the reported asymmetry: the dashboard works, the email link does not.

Why the outcome is a fully blank page rather than one of the redirects in step 8
is not determinable from source. Step 9 rules out "the template renders nothing
when data is empty". The remaining candidates are recorded in `requirements.md`
under Dependencies and unknowns and require browser evidence.

## Proposed behavior

Three changes, all in `aigen-frontend`.

**1. Accept the token as an explicit parameter.** `getQuotation` and
`getManagementQuotation` take a second `token` argument and build the URL from
it. The internal `useRoute()` calls and the now-unused `vue-router` import are
removed. This deletes the failure mode rather than working around it, and makes
both functions pure with respect to their inputs — callable and testable without
a component instance. Satisfies FR-1, FR-2, FR-3, AC-5.

**2. Pass the token from the component.** `load()` passes `routeToken.value` as
the second argument at `:181` and `:183`. `routeToken` already exists at `:103`
and is already used this way by the CS branch at `:179`, so this makes all three
branches consistent. On the dashboard route `routeToken` is `null`
(`route.params.token || null`), so the non-token URL is selected exactly as
today. Satisfies FR-1, FR-2, FR-4, FR-5.

**3. Add explicit loading and error states.** A `loading` ref initialised `true`
and cleared in a `finally`, and an `error` ref set in the `catch` before each
navigation. The template body is guarded so the page shows readable loading text,
then either the summary or a readable error message. This is defence in depth: it
guarantees the blank-page *class* of symptom cannot occur on this route even if
the precise pre-fix trigger is never reproduced, and it closes the gap where a
`router.replace` resolves a microtask later than the render. Satisfies FR-6,
FR-7, AC-6 through AC-9.

**Deliberately unchanged:** the CL-versus-Management branch on
`authStore.userRole` (`:100`). The JWT carries no `user_type` claim
(`emailHelper.js:668-673`), so there is nothing in the token to branch on, and
the backend already serves the two roles from two separate, already-correct
endpoints.

### Resulting flow

1. Backend sends the email with the same link as today — unchanged.
2. The approver, signed in, clicks it. The guard
   (`aigen-frontend/src/router/index.js:480-538`) admits them because they are
   authenticated and their role is in `meta.roles`.
3. `QuotationSummaryCL` mounts. `routeToken.value` is the token;
   `qcfNumber.value` is `undefined` and now harmless.
4. `load()` renders the loading state, then calls
   `getQuotation(qcfNumber.value, routeToken.value)` or the Management
   equivalent.
5. The service builds the token URL from its argument — no `useRoute()` — and
   requests `/pr/cl/need_approval_qcf/token/<token>` or the Management form.
6. The backend chain is unchanged: `authenticateToken` →
   `decodeTokenWithForbiddenException` sets `req.decoded` → the controller reads
   `qcf_number` from it and returns the QCF.
7. The page renders the summary, or a visible error state followed by navigation
   to `/page-expired` or `/page-forbidden`. It is never empty.

## Affected components

| Repository/component | Current symbol/path | Proposed change |
|---|---|---|
| frontend / service | `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.js:123` `getQuotation` | Add `token` parameter; remove `useRoute()` (`:125-126`); build URL from the argument. |
| frontend / service | same file `:149` `getManagementQuotation` | Same change (`:151-152`, `:155-156`). |
| frontend / service | same file, `vue-router` import | Remove if no other use remains in the file. |
| frontend / component | `aigen-frontend/src/features/form/cl/action/QuotationSummaryCL.vue:181,183` | Pass `routeToken.value` as the second argument. |
| frontend / component | same file, `<script setup>` and template | Add `loading` and `error` refs and guard the template body. |
| frontend / component | same file `:50` `qcfNumber` | **No change.** Still correct for the dashboard route; harmless on the token route once the token is passed. |
| frontend / component | same file `:100` `isManagementRole` | **No change.** See BR-3. |
| frontend / router | `aigen-frontend/src/router/index.js` | **No change.** |
| backend | all | **No change.** Both token endpoints are already correct. |

## Interface changes

None externally. No HTTP route, request, response, status code, event, or
OpenAPI change. The two service functions gain a second parameter — an internal
frontend signature change only. Both call sites are updated in the same commit;
`grep` confirms no other caller exists.

## Data design

- Schemas, tables, models: no change. The `qcf_token_email` table
  (`aigen-backend/src/models/default/qcfTokenEmail.js`) is read by existing
  backend code only.
- Migration, seed, backfill: none.
- Transaction boundary: not applicable — the fixed path is an idempotent GET.
- Idempotency and concurrency: unchanged.
- Data retention and rollback: not applicable. No data is written.

## UI and state

- Routes and role metadata: unchanged. `QuotationSummaryCLToken` keeps
  `roles: [ADMIN, CL, MANAGEMENT, CS]` and `redirect401: 'page-expired'`
  (`aigen-frontend/src/router/index.js:364-377`).
- Feature components, hooks, services: `QuotationSummaryCL.vue` and
  `QuotationSummaryCLService.js` as described above.
- Loading, empty, error, success behavior: currently the template renders
  unconditionally with no loading or error affordance. After the change: a
  readable loading message while `load()` is in flight; a readable error message
  if it rejects, held until navigation completes; the summary on success. The
  empty-data case continues to render the existing empty tables.
- Accessibility: the loading and error states must be text, not a spinner or
  colour change alone, so the state is conveyed without relying on motion or
  colour.

## Security

- Backend authorization: unchanged. No endpoint is added and no guard relaxed.
- Token lifetime, purpose, revocation: unchanged. The approval JWT's lifetime is
  set from the SLA at signing time (`aigen-backend/src/helper/emailHelper.js:674-676`).
- Validation: the service functions must treat a missing token as "no token" and
  fall through to the `qcf_number` URL, preserving dashboard behavior exactly.
- Logging and redaction: the approval JWT is already exposed in the URL, browser
  history, and any referrer — pre-existing and unchanged here. Do not add the
  token to logs, Sentry breadcrumbs, or test fixtures; use a placeholder in
  tests. The new error state must not render the token or raw error internals to
  the user.

## Integrations and failure handling

- Backend API: the existing interceptor
  (`aigen-frontend/src/router/interceptor.js`) continues to own 401 handling; the
  component's `catch` explicitly defers to it (`QuotationSummaryCL.vue:200-203`)
  and that behavior is preserved.
- Sentry: `Sentry.captureException` at `:196` is retained. Note that no
  `app.config.errorHandler` fallback UI exists, which is why change 3 puts the
  guarantee in the component rather than relying on a global boundary.
- Email: unchanged.
- Timeout and partial failure: a rejected or slow fetch now leaves the page in a
  visible loading or error state instead of an empty shell.

## Alternatives considered

| Alternative | Reason accepted/rejected |
|---|---|
| Pass the token explicitly and delete `useRoute()` from the service | **Accepted.** Removes the failure mode at its source, matches the already-correct CS branch three lines away, and makes both functions testable without a component instance. |
| Decode the JWT in the component to recover `qcf_number` | **Rejected.** Adds a JWT-decode dependency to the frontend and keeps the fragile `useRoute()` call. The backend token endpoints already read `qcf_number` from the verified token, so decoding it client-side duplicates that for no gain. |
| Both of the above | **Rejected.** The second adds surface without closing any gap the first leaves open. |
| Fix the six other `useRoute()`-in-service call sites in the same change | **Rejected here.** None is implicated in a reported symptom; including them multiplies the diff and test surface of a production bug fix. Named in Scope as a follow-up. |
| Add a global `app.config.errorHandler` fallback UI instead of per-component state | **Rejected for this fix.** Broader blast radius across every route, and it would not cover the slow-load case. Reasonable as a separate hardening task. |
| Branch CL versus Management on the token's `user_type` | **Rejected — not possible.** The JWT carries no `user_type` claim (`emailHelper.js:668-673`); it exists only as a database column (`:691`). |
| Make the link work without a dashboard login | **Deferred — product decision.** See `requirements.md`. Requires backend middleware reordering, DB-backed token validation, and a frontend guard change. Its own spec. |

## Risks and mitigations

| Risk | Likelihood/impact | Mitigation |
|---|---|---|
| The blank page has a cause this fix does not address | Medium / High | Change 3 guarantees a visible state regardless of cause. Ask the reporter to capture the failing request URL on the next recurrence — `undefined` in it confirms the diagnosis. |
| The approver was never signed in, so the real symptom was the `/login` redirect | Medium / High | Recorded as an unresolved question in `requirements.md`. If confirmed, this fix is still necessary but not sufficient, and Reading B becomes a real requirement. |
| A caller of the two service functions is missed | Low / High | `grep` confirms `QuotationSummaryCL.vue:181,183` are the only callers; both change in the same commit, and the dashboard-route regression test pins the old behavior. |
| The dashboard route regresses | Low / High | `routeToken` is `null` there (`:103`), selecting the unchanged URL. Pinned by an explicit regression test (AC-3). |
| The CS read-only path regresses | Low / Medium | That branch is untouched; pinned by AC-4. |
| Template guard hides content in an edge case | Low / Medium | The guard wraps only on `loading`/`error`; the success path renders exactly the current template. |

## Rollout and rollback

Feature flags: none. This is a corrective bug fix; a flag would keep the broken
path alive.

Deploy order:

1. `aigen-frontend` only. It is a separate git repository from `aigen-backend`
   (each has its own `.git` under the workspace directory).
2. No backend deploy, no migration, no coordination — there is no contract change.
3. Build runs ESLint with `--max-warnings=0` (`aigen-frontend/package.json:7`),
   so lint must be clean before the build will succeed.

Monitoring after release:

- Confirm on staging that the token route issues a request containing the token
  and not `undefined`.
- Watch Sentry for exceptions from `QuotationSummaryCL` — the `catch` already
  reports them, and they should drop to zero for this route.
- Ask the approver from the incident to retry the link and confirm the page
  renders.

Rollback: revert the frontend commit and redeploy the previous build. No data,
schema, or backend state is touched, so nothing else has to be undone.
