# Test plan — QCF approval email link opens a blank page

## Acceptance-criteria mapping

| Acceptance criterion | Test/verification | Level | Repository/file | Expected result | Status |
|---|---|---|---|---|---|
| AC-1 | `getQuotation('QCF0009999', 'test-token')` builds the CL token URL | Unit | `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.test.js` (new) | Requests `/pr/cl/need_approval_qcf/token/test-token`; URL contains no `undefined` | Planned |
| AC-2 | `getManagementQuotation('QCF0009999', 'test-token')` builds the Management token URL | Unit | same file | Requests `/pr/management/need_approval_qcf/token/test-token` | Planned |
| AC-3 | Both functions with a falsy token build the `qcf_number` URL | Unit | same file | Requests `/pr/cl/need_approval_qcf/QCF0009999` and the Management equivalent, unchanged from current behavior | Planned |
| AC-4 | CS read-only branch still calls `getCSQuotationByToken` with the route token | Component | `aigen-frontend/src/features/form/cl/action/QuotationSummaryCL.test.js` (new, **conditional**) | Called once with `'test-token'` | Blocked — see Automated coverage |
| AC-5 | Neither function calls `useRoute()`; both run with no active component instance | Unit | `QuotationSummaryCLService.test.js` | No Vue injection warning; no throw; resolves normally | Planned |
| AC-6 | Loading state renders before the fetch resolves | Component | `QuotationSummaryCL.test.js` (**conditional**) | A visible loading node is present; rendered DOM is non-empty | Blocked |
| AC-7 | 403 with `error_code` `NOT_AUTHORIZED` | Component (**conditional**) | same file | Error state renders; `router.replace('/page-forbidden')` called | Blocked |
| AC-8 | 404 or `error_code` `QCF_NOT_FOUND` | Component (**conditional**) | same file | Error state renders; `router.replace('/page-expired')` called | Blocked |
| AC-9 | Any rejection leaves a non-empty DOM | Component (**conditional**) | same file | Rendered DOM is never empty at any point | Blocked |
| AC-1..AC-4, AC-6..AC-9 | Manual staging walkthrough | Manual | Manual scenarios below | Page renders; no blank page; dashboard and CS paths unregressed | Planned |

Every acceptance criterion appears at least once. AC-4 and AC-6 through AC-9
have **no automated coverage** unless the `@vue/test-utils` decision below is
approved; they fall back to the manual scenarios.

## Automated coverage

### Frontend

- Harness: Vitest (`aigen-frontend/package.json:9`, `"test": "vitest run"`).
  Package manager is pnpm (`package.json:55`).
- Existing precedent: `aigen-frontend/src/services/form/cs/manual-sourcing/ManualSourcingService.test.js`
  (service-level, `vi.mock` on the http client) and
  `aigen-frontend/src/features/form/shared/hooks/useManualSourcing.test.js`
  (composable). There is **no existing component-mount test** in this repository.
- **Blocking dependency decision:** `@vue/test-utils` is **not installed**. The
  service-level tests (AC-1, AC-2, AC-3, AC-5) need no new dependency and should
  be written regardless. The component-level tests (AC-4, AC-6 through AC-9)
  cannot be written without adding `@vue/test-utils` as a devDependency.
  - Recommendation: **add it.** The defect lives precisely in the component's
    argument passing (`QuotationSummaryCL.vue:181,183`), and a service-only test
    suite cannot catch a regression where a future edit drops the second
    argument. It is dev-only, standard for Vue 3 + Vitest, and does not ship.
  - If it is declined, the approved manual substitute is the staging walkthrough
    below, and this plan records plainly that the changed lines have no automated
    guard.
- Test files:
  - `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.test.js` (new)
  - `aigen-frontend/src/features/form/cl/action/QuotationSummaryCL.test.js`
    (new, conditional on the decision above)
- Mocks and fixtures: `vi.mock` the http client; stub the router with
  `params: { token: 'test-token' }` or `params: { qcf_number: 'QCF0009999' }`;
  stub the auth store's `userRole`. Use only synthetic values — placeholder token
  `'test-token'`, QCF `QCF0009999`, RFQ `RFQ0009999`. Never a real token, QCF
  number, RFQ number, PR number, or approver email address.
- Command: `pnpm run test` from `aigen-frontend`.

### Backend

- Test files: none. No backend change is in scope — both token endpoints are
  already correct (`aigen-backend/src/routes/purchaseRoutes.js:220,250`).
- Command: N/A.

### Import worker

- Not involved in this path. N/A.

## Contract and integration checks

- HTTP/OpenAPI: no change. The request URL for the token route changes from the
  malformed `.../need_approval_qcf/undefined` to the already-documented
  `.../need_approval_qcf/token/:token`; the dashboard URL is unchanged.
- Kafka/command: none.
- Database migration/rollback: none.
- Cross-repository compatibility: none affected. `aigen-frontend` deploys
  independently; no backend contract changes.
- Internal signature change: `getQuotation` and `getManagementQuotation` gain a
  second parameter. Confirm by `grep` that `QuotationSummaryCL.vue:181,183` are
  the only callers and that both are updated in the same commit.

## Manual scenarios

| Scenario | Preconditions/test data | Steps | Expected result |
|---|---|---|---|
| CL approver, token route | Staging QCF awaiting CL approval; approver signed into the dashboard in the same browser | Open the emailed approval link | Quotation Summary renders for that QCF; approval can be submitted; Network shows the CL token URL with no `undefined` |
| Management approver, token route | Staging QCF awaiting Management approval; approver signed in | Open the emailed approval link | Renders and approves via the Management token URL |
| Dashboard route regression | Any staging QCF | Open the QCF from the dashboard | Renders exactly as before; Network shows the `qcf_number` URL, unchanged |
| CS read-only token path | Staging GEMS Manual PO notification link | Open the link as CS | Renders read-only, unchanged |
| Not signed in | Sign out, then open a token link | Click the link | Redirected to `/login` — **not** a blank page. Record what is actually observed: this is the check that distinguishes the two candidate causes in `requirements.md` |
| Expired or revoked token | Staging token past `date_expired` | Open the link while signed in | `/page-expired` renders with a visible message; never blank |
| Slow network | Throttle to slow 3G | Open a token link | Visible loading text throughout; never an empty page |

Use staging only. Do not re-run the production incident or reuse a production
token.

## Security and failure cases

- Unauthorized/forbidden role: a role outside `meta.roles`
  (`aigen-frontend/src/router/index.js:373`) is sent to `/page-forbidden` by the
  guard. Unchanged by this fix; confirm no regression.
- Missing/expired/revoked token: the backend returns 403; the component navigates
  to `/page-expired` (`QuotationSummaryCL.vue:206-218`). Confirm a visible error
  state renders first.
- Invalid input: a falsy token must select the `qcf_number` URL rather than
  producing a URL containing `undefined` or `null`.
- Dependency timeout/failure: a rejected fetch must leave a visible error state,
  never an empty DOM (AC-9).
- Duplicate/retry/concurrent request: not applicable — the fixed path is an
  idempotent GET.
- Partial database/integration failure: not applicable; nothing is written.
- Token leakage: confirm the token does not appear in any test fixture, log line,
  Sentry breadcrumb, or the rendered error message. The token is already exposed
  in the URL and browser history — pre-existing and unchanged, but do not widen it.

## Commands and results

| Command | Date | Result | Notes |
|---|---|---|---|
| `pnpm run lint` (in `aigen-frontend`) | | Planned | Build gates on `--max-warnings=0` |
| `pnpm run test` | | Planned | Full Vitest suite |
| `pnpm vitest run src/services/form/cl/QuotationSummaryCLService.test.js` | | Planned | AC-1, AC-2, AC-3, AC-5 |
| `pnpm vitest run src/features/form/cl/action/QuotationSummaryCL.test.js` | | Blocked | AC-4, AC-6..AC-9; conditional on `@vue/test-utils` |
| `pnpm run build` | | Planned | Confirms the lint-gated build passes |

## Unverified behavior

- **The blank page itself is not explained.** The confirmed defect explains why
  the request fails; it does not explain why the result is an empty page rather
  than one of the redirects in `QuotationSummaryCL.vue:206-221`, both of whose
  destination routes exist. The template renders unconditionally and
  `summary.items` defaults to `[]` (`:67,372-711`), so "empty template" is ruled
  out. Two candidates remain and need browser evidence: an exception during
  `<script setup>` or the pre-`await` portion of the service call, with no
  `app.config.errorHandler` fallback UI to catch it; or the approver was not
  signed in and what was reported as blank was the `/login` redirect. Ask the
  reporter to capture the failing request URL — `undefined` in it confirms the
  first.
- **Whether the link is meant to work without a dashboard login is unresolved.**
  The report expects it; the backend requires login today
  (`aigen-backend/src/routes/purchaseRoutes.js:220-223,249-253`). This spec
  implements Reading A. If Reading B is chosen, this fix remains necessary but
  is not sufficient.
- **The approver's role in the incident was never confirmed.** It does not change
  the diagnosis — `QuotationSummaryCL.vue:181` and `:183` both pass `undefined`
  on the token route — but it is unverified.
- **`useRoute()` behavior inside an async service function is environment- and
  version-dependent.** Whether it returns `undefined`, throws, or happens to work
  depends on Vue and vue-router internals and call timing. The fix removes the
  call entirely rather than characterising it, so the exact pre-fix behavior is
  deliberately left unverified.
- **Six other `useRoute()`-in-service call sites are untested and unfixed** (listed
  in `tasks.md`). None is implicated in a reported symptom; none was verified as
  safe either.
- **Two pre-existing backend authorization gaps are unverified and out of scope:**
  the missing role guard on `getApprovalQCFByCL`
  (`aigen-backend/src/controllers/qcfController.js:1562-1691`) and the absence of
  any `qcf_token_email.is_active` / `date_expired` check in
  `decodeTokenWithForbiddenException`
  (`aigen-backend/src/middleware/tokenMiddleware.js:82-106`).
- **AC-4 and AC-6 through AC-9 have no automated coverage** unless
  `@vue/test-utils` is added. Until then the component's argument passing — the
  exact lines this fix changes — is guarded only by manual verification.
