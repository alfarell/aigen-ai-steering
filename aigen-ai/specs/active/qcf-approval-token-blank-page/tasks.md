# Tasks — QCF approval email link opens a blank page

All work is in `aigen-frontend`, which is a separate git repository from
`aigen-backend`. No backend change and no migration — see `requirements.md`
Scope.

## Discovery

- [x] Verify current behavior and reproduction evidence. Chain traced from the
      email link (`aigen-backend/src/helper/emailHelper.js:717,788`) through the
      route (`aigen-frontend/src/router/index.js:364-377`) to
      `QuotationSummaryCL.vue:50,175-184` and
      `QuotationSummaryCLService.js:123-172`.
- [x] Confirm requirements, actors, rules, and unknowns. See `requirements.md`.
- [ ] Check Git status in `aigen-frontend` and preserve any pre-existing work
      before starting. It is on branch `develop-dot`.
- [x] Identify interfaces, data, security, jobs, and integrations. No API
      contract change; backend token endpoints already correct
      (`aigen-backend/src/routes/purchaseRoutes.js:220,250`).
- [x] Rule out hash-routing mismatch (`router/index.js:476` uses
      `createWebHashHistory`) and the empty-template hypothesis
      (`QuotationSummaryCL.vue:67,372-711` render unconditionally).
- [x] Confirm `aigen-ai/specs/active/rfq-vendor-token-not-created/` is unrelated —
      vendor tokens (`rfq_token_email`) versus approver tokens
      (`qcf_token_email`), no shared helper, model, or controller.
- [ ] **Decision needed before closing the bug:** ask the reporter for browser
      console and Network output from the next recurrence, specifically the
      failing request URL. A URL containing `undefined` confirms the diagnosis; a
      redirect to `/login` means the approver was not signed in and Reading B in
      `requirements.md` becomes a real requirement. Does not block implementation.
- [ ] **Decision needed:** whether to add `@vue/test-utils` as a devDependency.
      It is not installed today, so component-mount tests are impossible without
      it. See `test-plan.md`. Blocks only the component-level tests, not the fix.

## Implementation

Execute in this order.

- [ ] **Frontend 1 — service signatures.** In
      `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.js`, add a
      second `token` parameter to `getQuotation` (`:123`) and
      `getManagementQuotation` (`:149`). Delete the internal `useRoute()` calls
      and the `route?.params?.token` lines (`:125-126`, `:151-152`) and build the
      URL from the parameter instead. Remove the `vue-router` import if nothing
      else in the file uses it. A falsy token must still select the existing
      `qcf_number` URL so dashboard behavior is byte-identical.
      Covers FR-1, FR-2, FR-3, FR-4.
- [ ] **Frontend 2 — component call sites.** In
      `aigen-frontend/src/features/form/cl/action/QuotationSummaryCL.vue`, pass
      `routeToken.value` as the second argument at `:181`
      (`getManagementQuotation`) and `:183` (`getQuotation`), mirroring the CS
      branch at `:179`. Do not change `qcfNumber` (`:50`) or `isManagementRole`
      (`:100`) — see BR-3. Depends on: Frontend 1.
      Covers FR-1, FR-2, FR-5.
- [ ] **Frontend 3 — visible loading and error states.** In the same component,
      add a `loading` ref initialised `true` and cleared in a `finally` around
      `load()`, and an `error` ref set in the `catch` (`:195-222`) before each
      navigation. Guard the template body (`:372-711`) so the page renders
      readable loading text, then either the summary or a readable error message.
      Keep the existing `Sentry.captureException` (`:196`) and all existing
      navigation targets. Use text, not colour or motion alone. Do not render the
      token or raw error internals. Depends on: Frontend 2.
      Covers FR-6, FR-7.
- [ ] Backend: N/A — both token endpoints are already correct
      (`aigen-backend/src/routes/purchaseRoutes.js:220,250`) and the JWT payload
      needs no change.
- [ ] Import worker: N/A — not involved in this path.
- [ ] API/OpenAPI/event contract: N/A — no interface change. The two service
      functions gain a parameter, which is internal to the frontend; `grep`
      confirms `QuotationSummaryCL.vue:181,183` are the only callers.
- [ ] Data migration/backfill/rollback: N/A — nothing is written.
- [ ] Observability/security: covered by Frontend 3. Confirm no test fixture or
      log line contains a real token.

## Tests

- [ ] Create
      `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.test.js`
      following the existing Vitest precedent in
      `aigen-frontend/src/services/form/cs/manual-sourcing/ManualSourcingService.test.js`
      (`vi.mock` on the http client). Assert the token URL is used when a token
      is passed and the `qcf_number` URL when it is not, for both `getQuotation`
      and `getManagementQuotation`. Covers AC-1, AC-2, AC-3.
- [ ] In the same file, assert that calling either function with no active
      component instance neither invokes `useRoute()` nor throws. Covers AC-5.
- [ ] **If `@vue/test-utils` is approved** (see Discovery), create
      `aigen-frontend/src/features/form/cl/action/QuotationSummaryCL.test.js`
      asserting: CL token route calls `getQuotation` with
      `(undefined, '<placeholder-token>')`; Management token route calls
      `getManagementQuotation` likewise; dashboard route calls with
      `('QCF0009999', null)`; the CS branch still calls `getCSQuotationByToken`;
      loading and error states render and the DOM is never empty on rejection.
      Covers AC-4, AC-6, AC-7, AC-8, AC-9.
- [ ] **If it is not approved**, record in `test-plan.md` that AC-4 and AC-6
      through AC-9 are covered by manual staging verification only, and state
      plainly that no automated test then guards the component's argument
      passing — the exact line the fix changes.
- [ ] Use a placeholder token such as `'test-token'` in every fixture. Never a
      real token, QCF number, RFQ number, or approver email.
- [ ] Complete the acceptance-criteria mapping in `test-plan.md` with actual
      results.

## Verification and handoff

- [ ] Run `pnpm run lint` in `aigen-frontend` and record the result. The build
      runs ESLint with `--max-warnings=0` (`package.json:7`), so warnings block
      the release.
- [ ] Run `pnpm run test` in `aigen-frontend` and record the result.
- [ ] Run `pnpm run build` to confirm the lint-gated build passes.
- [ ] Backend commands: N/A — no backend change.
- [ ] Import-worker commands: N/A.
- [ ] Manual staging verification: open a token link as CL and as Management,
      confirm the page renders and approval works; open the same QCF from the
      dashboard and confirm no regression; confirm the CS read-only token path is
      unchanged. Record results in `test-plan.md`.
- [ ] Confirm in the browser Network tab that the request carries the token and
      contains no `undefined`.
- [ ] Update `aigen-ai/index/` and `aigen-ai/context/project-state.md`.
- [ ] Review the final diff for unrelated changes and for any leaked token.
- [ ] Record unverified behavior, rollout order, and rollback in `test-plan.md`.
- [ ] Open a follow-up ticket for the six other `useRoute()`-inside-a-service
      call sites: `aigen-frontend/src/services/form/cs/DeclinedItemsCSService.js:6`,
      `NotSubmittedItemsCSService.js:7`, `PriceNotMatchCSService.js:21`,
      `OERevisionCSService.js:6`, `SurrogateItemsCSService.js:25,38`.
- [ ] Open a follow-up ticket for the missing role guard on
      `getApprovalQCFByCL` (`aigen-backend/src/controllers/qcfController.js:1562-1691`),
      which has no equivalent to the Management check at `:1833-1840`.
- [ ] Open a follow-up ticket for approver tokens not being validated against the
      database: `decodeTokenWithForbiddenException`
      (`aigen-backend/src/middleware/tokenMiddleware.js:82-106`) never checks
      `qcf_token_email.is_active` or `date_expired`, unlike the vendor path at
      `:13-54`.
- [ ] Resolve the login-required product decision (Reading A versus Reading B in
      `requirements.md`). If Reading B is chosen, open a separate spec — do not
      extend this one.
- [ ] Move this specification to `aigen-ai/specs/completed/` only after the
      acceptance criteria are met and the reporter confirms the link works in
      production.
