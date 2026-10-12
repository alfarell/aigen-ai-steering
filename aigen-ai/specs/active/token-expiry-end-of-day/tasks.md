# Tasks — Token deadline valid until end of day, landing pages read-only for inactive tokens

## Discovery

- [x] Verify current behavior and evidence (RFQ0002356 tokens 9099, 9184; 07:00 expiry on 4 133 + 529 rows).
- [x] Confirm with business: end of day (2026-10-12, re-confirmed 2026-10-13), all token types, messages unchanged.
- [x] Confirm the reporter was the DIC with a stale tab (BA, 2026-10-13); landing read-only without message.
- [ ] Confirm BR-4 (follow-up actions move to the next morning's cron run).
- [ ] Confirm production `TZ` env and that no back-fill is wanted.
- [x] Check Git status before implementation (aigen-backend, aigen-frontend clean on `develop-dot-clone`).

## Implementation

- [x] Backend: `addBusinessDaysEndOfDay` + `BUSINESS_TIMEZONE` in `src/helper/date.js`.
- [x] Backend: `calculateSubmissionDeadlineAndSla` end of day WIB, `sla` in seconds.
- [x] Backend: `prController.generateTokenRFQ` and qcf DIC single-submission token via `calculateSubmissionDeadlineAndSla`.
- [x] Backend: expiry queries `date_expired <= now` (rfq ×2, qcf ×1).
- [x] Backend: `isTokenRecordActive`, `getTokenActive`, `attachTokenState`; landing routes chained; `token_active` in both landing responses.
- [x] Backend: `GET /pr/token/status/:token` (`prController.getTokenStatus`).
- [x] API/OpenAPI: two landing paths, new status path, `openapi.yaml`, `openapi.bundle.yaml`.
- [x] Frontend: `TokenStatusService`, `useTokenActiveGuard`, service mappings (+ `dic/index.ts` type).
- [x] Frontend: vendor and DIC pages + tables read-only; pre-action and visibility re-checks; popup `close`; `FileInput` readonly picker guard.
- [ ] Frontend (optional): pre-check inside user-triggered image upload/delete of shared child components.
- [x] Import worker: N/A. Data migration/backfill: N/A.

## Tests

- [x] Unit: `tests/helper/date.endOfDay.test.js`, `tests/helper/slaCalculator.test.js`.
- [x] Unit: `tests/repository/tokenEmail.expiryQuery.test.js`.
- [x] Unit: `tests/middleware/tokenMiddleware.tokenState.test.js`.
- [x] Unit/API: `tests/controllers/prController.tokenState.test.js`, `tests/controllers/qcfController.dicSingleSubmissionToken.test.js`; adjusted `qcfController.dicReminder.test.js`.
- [x] `npm test` in aigen-backend (implementer run: 58 suites / 390 tests passed).
- [x] Independent verification (test-verifier: PASS) and code review (approve with notes; M1, M2, M4, N1 fixed; M3 excluded).
- [x] Review fix: DIC reminder (`sendDicConfirmationReminders`) compares instants, so the deadline day is not skipped.
- [ ] Manual browser checks AC-4..AC-7 on local data (see `test-plan.md`).

## Verification and handoff

- [x] Run `graphify update .` after code changes.
- [ ] Update `aigen-ai/index/` and `context/project-state.md`.
- [ ] Review final diffs for unrelated changes and secrets.
- [ ] Move this specification to `completed/` only after acceptance criteria are met.
