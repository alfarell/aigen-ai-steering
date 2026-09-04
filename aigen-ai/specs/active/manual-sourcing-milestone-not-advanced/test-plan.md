# Test plan — Manual Sourcing leaves the RFQ on its old milestone

## Change surface

| File | Change |
| --- | --- |
| `aigen-backend/src/repository/qcfLibrary.repository.js` | Two one-line conditions: only `undefined` is the failed-transfer marker |
| `aigen-backend/tests/repository/qcfLibrary.bulkUpdateStatusRFQ.test.js` | New, 10 tests |

No other file is touched. The frontend and the import worker are untouched and clean.

## Automated tests

`npx jest tests/repository/qcfLibrary.bulkUpdateStatusRFQ.test.js` — **10 passed** (2026-09-04).

| Test | AC |
| --- | --- |
| advances an item whose vendor never responded to BID Manual Sourcing | AC-1 |
| does not treat null as the failed-transfer marker | AC-1 (regression guard) |
| leaves milestone and rfq type untouched when the transfer failed | AC-3 |
| advances an accepted item to iSourcing | AC-4 |
| advances a pending item to BID Manual Sourcing despite status 0 being falsy | AC-5 |
| routes a mixed batch per item | AC-6 |
| marks the QCF row manually sourced when the vendor never responded | AC-2 |
| skips the QCF row when the transfer failed | AC-3 |
| keeps OE revision on its own milestone and touches no QCF row | AC-7 |
| keeps surrogate on its own milestone | AC-7 |

### Fail-before-fix evidence

The pre-fix condition was restored in place and the suite re-run:

```
× advances an item whose vendor never responded to BID Manual Sourcing
× does not treat null as the failed-transfer marker
× routes a mixed batch per item
× marks the QCF row manually sourced when the vendor never responded
√ (the other six)
Tests: 4 failed, 6 passed, 10 total
```

The six that pass in both states are the collateral-damage guards: they assert the
behaviour that must **not** change.

### Full suite

`npx jest` — **163 passed, 20 failed, 183 total** (2026-09-04).

Baseline on the parent branch was 153 passed / 20 failed / 173 total. The delta is
exactly the 10 new tests. The 20 failures are the pre-existing `rfqLibrary.dicReminder`
and `qcfController.dicReminder` suites, unrelated to this change and failing identically
before it.

## Manual verification

Not yet performed by the owner. To reproduce end to end on the local database copy:

1. Open the RFQ detail for `RFQ0002051` as Admin. The Manual Sourcing button is present
   because milestone 2 renders as `BID Submitted / Waiting Vendor` (case 5 in
   `useManualSourcing.js`).
2. Submit Manual Sourcing with any reason.
3. Expect `rfq_library.status_milestone` to become `6` and `tipe_rfq` to become
   `isourcing`.
4. Reopen the detail. The button must be gone: milestone 6 renders as
   `BID Submitted / Manual Sourcing`, which matches none of the twelve cases.

Note that `RFQ0002051` already carries `sourcing_reason` and `sourcing_notes` from the
failed 2026-09-04 attempt, and PR `8100020733` already has cards in `task_board`, so
`prosesToIsourcing` will take its "already exists" branch and report
`Missing items added: 0`. That is expected and does not affect the milestone.

Requires the header fix from `fix/cs-not-submitted-header` to be present, otherwise the
detail page for `RFQ0002052` returns a header containing only `vendor_batch`.

## Adjacent finding — not fixed

`qcfController.js:2899` (the 9-day dual-vendor follow-up cron) builds its batch as
`allRfqItems.map((item) => ({ id: item.id }))`, with no `status_vendor` at all. Every
item therefore reads as `undefined`, which this change keeps meaning "transfer failed",
so that cron still logs `Successfully processed RFQ … items moved to iSourcing` without
advancing any milestone.

This is the same symptom from a different call site. It is deliberately left unchanged:
the behaviour is identical before and after this fix, so nothing regresses, and fixing it
means changing the cron's payload rather than the repository. It needs an owner decision.

## Rollback

Revert the commit. The change is two conditions in one function and one new test file;
no migration, no data change, no contract change.

## Residual risk

- Rows that legitimately need to stay put on a failed transfer still do, because the
  `undefined` marker is preserved. But the marker is fragile: `undefined` and `null` are
  one keystroke apart and a future edit could reintroduce the conflation. The second test
  ("does not treat null as the failed-transfer marker") exists to fail loudly if it does.
- `qcf_library` writes for `status_vendor IS NULL` items are newly reachable. Measured
  population today: **0 rows** — none of the 11 `status_vendor IS NULL` rows has a
  `qcf_library` row — so no existing data is affected.
