# Tasks — Manual Sourcing leaves the RFQ on its old milestone

Primary repository: `aigen-backend`, branch `fix/manual-sourcing-milestone`, cut from
`fix/cs-not-submitted-header` (which is itself cut from `production` @ `a978fdbb`).
`aigen-frontend` and `aigen-import-pr` are not modified.

## Discovery

- [x] Reproduce from production data — done read-only 2026-09-04 against the local copy;
      evidence table in `requirements.md`.
- [x] Confirm the transfer to iSourcing actually succeeded (`board_card` #128386,
      `item_card` #73019) so the defect is isolated to the milestone write.
- [x] Confirm the API returned success and the activity log recorded success, which is
      why nothing surfaced to the user.
- [x] Measure the affected population — 11 `rfq_library` rows with
      `status_vendor IS NULL`, of which 0 have a `qcf_library` row.
- [x] Establish the milestone target with the owner — **6, decided 2026-09-04.**
- [x] Verify milestone 6 removes the button — `config_milestone` id 6 is
      `BID Submitted / Manual Sourcing`, matching none of the twelve
      `canShowManualSourcing` cases; `is_manual_sourcing` is false because it needs an
      active `WAITING_CS_EXPIRY` token and neither RFQ has one.
- [x] Check `git status` in each repository — all clean at spec time.

## Implementation

- [x] **I-1 (FR-1, FR-2, FR-3, FR-4):** `src/repository/qcfLibrary.repository.js:61` —
      `isManualSourcingFailed` tests `undefined` only. Comment records why `null` is not
      a failure.
- [x] **I-2 (FR-5):** `src/repository/qcfLibrary.repository.js:90` — the QCF branch tests
      `undefined` only, matching I-1.
- [ ] **API/OpenAPI/event contract:** N/A — no external contract change. Same route, same
      status codes, same response shape.
- [ ] **Data migration/backfill/rollback:** N/A. `RFQ0002051` and `RFQ0002052` are left as
      they are; remediating them needs a separate owner decision.

## Tests

- [x] **T-1 (AC-1):** null `status_vendor` yields milestone 6 and `tipe_rfq = isourcing`.
- [x] **T-2 (AC-1):** explicit regression guard against reintroducing `=== null`.
- [x] **T-3 (AC-3):** undefined leaves both columns absent from the update values.
- [x] **T-4 (AC-4):** accepted yields 12.
- [x] **T-5 (AC-5):** pending (`0`, falsy) yields 6.
- [x] **T-6 (AC-6):** mixed batch routes per item.
- [x] **T-7 (AC-2):** QCF row updated for null.
- [x] **T-8 (AC-3):** QCF row skipped for undefined.
- [x] **T-9, T-10 (AC-7):** `REVISI_OE` and `SURROGATE` unchanged.
- [x] Confirm the tests fail before the fix — 4 of 10 fail on the pre-fix condition; see
      `test-plan.md`.

Fixtures use synthetic ids and reasons. No real vendor code, PR number or email appears
in test data.

## Verification and handoff

- [x] `npx jest tests/repository/qcfLibrary.bulkUpdateStatusRFQ.test.js` — 10/10 passed.
- [x] `npx jest` — 163 passed, 20 failed, 183 total. The 20 are the pre-existing
      `dicReminder` suites; baseline was 153/20/173.
- [x] Frontend: N/A — untouched, working tree clean.
- [x] Import worker: N/A — untouched, working tree clean.
- [x] Review the final diff for unrelated changes and secrets.
- [ ] **AC-8:** owner to confirm end to end on the RFQ detail page that the button
      disappears after a successful Manual Sourcing.
- [ ] Decide whether the 9-day dual-vendor cron (`qcfController.js:2899`) should also
      advance milestones — see "Adjacent finding" in `test-plan.md`. It carries the same
      symptom from a different call site and is unchanged by this delivery.
- [ ] Decide whether `RFQ0002051` and `RFQ0002052` should be remediated in place.
- [ ] Update `aigen-ai/index/` and `aigen-ai/context/project-state.md`.
- [ ] Move this specification to `completed/` once AC-8 is confirmed.

## Open items at handoff

- **OI-1:** Nine historical rows carry `status_vendor IS NULL` together with
  `status_milestone = 12`. Neither the current nor the pre-regression code produces that
  combination from this path. Origin unknown; recorded, not blocking.
- **OI-2:** `RFQ0002052` produced no server-side trace at all when Manual Sourcing was
  submitted — no activity log, no writes. Every backend gate was ruled out
  (`canManualSource` allows with zero QCF rows, `getPRDetails` joins successfully for
  vendor 106412/GEMS, single vendor so the matrix branch is not entered). The abort is
  most likely client-side; confirming it needs a DevTools Network capture showing whether
  `POST /pr/cs/send_isourcing/...` is issued.
