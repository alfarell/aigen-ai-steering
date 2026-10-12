# Test plan — Token deadline valid until end of day, landing pages read-only for inactive tokens

## Acceptance-criteria mapping

| AC | Test/verification | Level | Location | Expected result | Status |
|---|---|---|---|---|---|
| AC-1 | Start 2026-09-29 08:04 WIB, SLA 3 | Unit | `aigen-backend/tests/helper/slaCalculator.test.js` | Deadline 2026-10-02 23:59:59.999 WIB, label "02 Oct 2026", `sla` seconds reach the deadline | Automated |
| AC-2 | Token active at 15:00 on the deadline date; submit | Unit + manual | `tests/middleware/tokenMiddleware.tokenState.test.js`; local browser | `isTokenRecordActive` true; submit succeeds | Unit automated, manual pending |
| AC-3 | Expiry query cut-off is `now` | Unit | `tests/repository/tokenEmail.expiryQuery.test.js` | `[Op.lte]` equals faked now for all three queries | Automated |
| AC-4 | Vendor landing with `is_active = 0` | Unit + manual UI | `tests/controllers/prController.tokenState.test.js`; local browser | `token_active:false`; read-only form, no buttons, no toast/dialog | Unit automated, manual pending |
| AC-5 | DIC landing with `is_active = 0`, items awaiting DIC | Unit + manual UI | same | `token_active:false`; read-only, no buttons | Unit automated, manual pending |
| AC-6 | RFQ0002356 stale tab: token closed while DIC page open | Unit + manual UI | `prController.tokenState.test.js` (`getTokenStatus`); local browser | Status endpoint 200 false; tab turns read-only on focus / before action; no `PUT konfirmasi_penawaran`, no "Gagal" dialog | Unit automated, manual pending |
| AC-7 | `date_expired` passed, `is_active = 1` | Unit | `tokenMiddleware.tokenState.test.js` | `isTokenRecordActive` false | Automated |
| AC-8 | Process `TZ=UTC` | Unit (child process) | `tests/helper/tzUtc.childProcess.test.js` (spawns Node with `TZ=UTC`; in-file `process.env.TZ` has no effect under Jest) | Same deadline, offset 0 asserted | Automated |
| AC-9 | Start 06:30 WIB (= previous day UTC) | Unit | `tests/helper/date.endOfDay.test.js` | Counts from the WIB date | Automated |
| BR-1 reminder | DIC reminder on the deadline date with 23:59:59 expiry | Unit | `tests/controllers/qcfController.dicReminder.test.js` | Sent on deadline day, `skipped_expired` after expiry | Automated |
| Route wiring | Landing chains + status route without auth | Unit | `tests/routes/purchaseRoutes.tokenState.test.js` | Handler order asserted | Automated |
| FR-7a | `generateTokenRFQ`, qcf DIC single-submission token | Unit | `prController.tokenState.test.js`, `qcfController.dicSingleSubmissionToken.test.js` | Numeric `expiresIn`, `date_expired` 23:59:59 WIB | Automated |

## Automated coverage

- Backend: Jest (`npm test`; focused `npx jest tests/helper tests/middleware tests/repository tests/controllers`).
- Frontend: no test harness; `eslint <changed files> --max-warnings=0` and `vite build` (temp out dir).

## Manual scenarios (local data only)

| Scenario | Steps | Expected |
|---|---|---|
| AC-4 vendor | Local vendor token `is_active=0`, open `/#/vendor/quotation/<token>` | Data shown, inputs disabled, no Kirim/Reset, no toast/dialog; image viewer and table scroll work |
| AC-5 DIC | Local DIC token `is_active=0`, items at WAITING_DIC_APPROVAL | Read-only, no buttons |
| AC-6 visibility | Open DIC page with active token; close token in DB/other tab; switch back | One `GET /pr/token/status`, page read-only, no dialog |
| AC-6 action | Same, keep tab visible, click Kirim (and via the confirmation popup) | Popup closes, read-only, no `PUT`, no Swal |
| Vendor actions | Same for Kirim, over-budget "lanjutkan", Reset, DECLINE with images | No `PUT` / `DELETE /upload/images` sent |
| Failure | Block status endpoint (500/offline) | Action proceeds; action endpoint decides |
| Old backend | Response without `token_active` | Page stays editable |
| New invitation | Send RFQ locally (SLA 3) | `date_expired` 23:59:59, email date matches |

## Commands and results

| Command | Date | Result | Notes |
|---|---|---|---|
| `npx jest` (aigen-backend) | 2026-10-13 | 58 suites / 390 tests passed | Implementer run |
| `npx jest`, `TZ=UTC npx jest`, `TZ=Asia/Jakarta npx jest` | 2026-10-13 | 58 / 390 passed each | Test-verifier |
| `eslint . --max-warnings=0` (aigen-frontend, repo-wide, no fix) | 2026-10-13 | Pass | Test-verifier |
| `npx jest` after review fixes (M1, M2, M4, N1) | 2026-10-13 | 60 suites / 396 tests passed | Re-run by orchestrator |
| `eslint <11 changed files> --max-warnings=0` (aigen-frontend) | 2026-10-13 | Pass | Implementer run |
| `vite build --outDir <temp>` (aigen-frontend) | 2026-10-13 | Pass | Implementer run |

## Unverified behavior

- Production cron schedule (≈ 08:00 WIB) and process timezone are inferred from data.
- Browser behaviour (AC-2, AC-4..AC-6) not yet exercised manually.
