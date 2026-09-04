# Requirements — Manual Sourcing leaves the RFQ on its old milestone

Status: active
Opened: 2026-09-04
Primary repository: `aigen-backend`
Related spec: `../rfq-vendor-token-not-created/` (same underlying data condition, `status_vendor IS NULL`)

## Problem

A CS or Admin user opens the RFQ detail page, presses **Manual Sourcing**, fills in the
reason and notes, and submits. The API answers 200, the activity log records
"berhasil melakukan manual sourcing", and the PR is transferred to iSourcing
(`task_board`). But `rfq_library.status_milestone` is never advanced. The RFQ therefore
still renders the Manual Sourcing button, and to the user nothing appears to have
happened.

Reported against `RFQ0002051` (PR 8100020733) and `RFQ0002052` (PR 8100020736).

## Measured evidence (local copy of the production database, 2026-09-04)

`RFQ0002051`, submitted at 15:58:16:

| Artefact | Observed |
| --- | --- |
| `log_activity` #169242 | "Admin berhasil melakukan manual sourcing dengan nomor PR G8100020733" |
| `task_board.board_card` #128386 | created |
| `task_board.item_card` #73019 (item 20) | created |
| `rfq_library.sourcing_reason` / `sourcing_notes` | written from the form |
| `rfq_library.status_milestone` | **unchanged, still 2** |
| `rfq_library.tipe_rfq` | **unchanged, still NULL** |

Population of the affected data shape: 11 `rfq_library` rows have
`status_vendor IS NULL`; none of them has a `qcf_library` row.

## Root cause

`src/repository/qcfLibrary.repository.js` conflated two distinct meanings of a missing
`status_vendor`:

```js
const isManualSourcingFailed =
    item.status_vendor === null || item.status_vendor === undefined;
```

`qcfController.sendActionToCS` marks a **failed** iSourcing transfer by setting
`item.status_vendor = undefined`, and on success copies the database value onto the item.
For an RFQ whose vendor never responded that database value is `null` — a normal
manual-sourcing case, not a failure. The repository read it as a failure, set
`status_milestone` and `tipe_rfq` to `undefined`, and Sequelize omitted both from the
`SET` clause. Only `sourcing_reason` and `sourcing_notes` were written.

`rfqLibrary.update` still reported one affected row, so `updatedCount > 0`, so the
controller took its success branch, logged success and returned 200.

The same conflation appears a second time in the QCF branch of the same function.

## Functional requirements

- **FR-1** — An item transferred to iSourcing whose `status_vendor` is `null` must be
  advanced to `STATUS_MILESTONE.BID_MANUAL_SOURCING` (6), together with
  `tipe_rfq = 'isourcing'`, `sourcing_reason` and `sourcing_notes`.
- **FR-2** — An item whose `status_vendor` is `STATUS_VENDOR.ACCEPTED` must keep
  advancing to `STATUS_MILESTONE.ISOURCING` (12). Unchanged behaviour.
- **FR-3** — An item whose `status_vendor` is any other defined value must advance to
  `STATUS_MILESTONE.BID_MANUAL_SOURCING` (6). Unchanged behaviour. `PENDING` is `0`
  and must not be mistaken for absent.
- **FR-4** — Only `undefined` may be read as the failed-transfer marker. In that case
  `status_milestone` and `tipe_rfq` stay untouched. Unchanged behaviour.
- **FR-5** — The QCF branch must apply the same rule: a `null` `status_vendor` updates
  the QCF row to `QCF_MANUAL_SOURCING` (19) with `qcf_approved = 2`; only `undefined`
  skips it.
- **FR-6** — `REVISI_OE` and `SURROGATE` behaviour is untouched.

## Milestone choice

`6` was chosen by the owner on 2026-09-04.

Supporting evidence: milestone 6 maps to `BID Submitted / Manual Sourcing` in
`config_milestone`, and the code immediately before the regression was introduced
(`git show bda89a83^`) read

```js
valuesToUpdate.status_milestone = item.status_vendor === STATUS_VENDOR.ACCEPTED
    ? STATUS_MILESTONE.ISOURCING
    : STATUS_MILESTONE.BID_MANUAL_SOURCING;
```

so `6` restores the pre-regression outcome for this case.

Unexplained observation, recorded rather than resolved: 9 historical rows
(Nov–Dec 2025, reasons "Vendor tidak submit" / "Vendor tidak bisa supply") carry
`status_vendor IS NULL` **and** `status_milestone = 12`. Neither the pre-regression code
above nor the current code produces that combination from this path, so those rows were
written by an older revision or a different path. This does not block the change.

## Acceptance criteria

- **AC-1** — Given an ISOURCING batch with one item at `status_vendor = null`, the
  `rfq_library` update carries `status_milestone = 6` and `tipe_rfq = 'isourcing'`.
- **AC-2** — Given the same item, `qcf_library` is updated with milestone 19 and
  `qcf_approved = 2`.
- **AC-3** — Given `status_vendor = undefined`, neither `status_milestone` nor
  `tipe_rfq` appears in the update values, and `qcf_library` is not touched.
- **AC-4** — Given `status_vendor = 1`, the milestone is 12.
- **AC-5** — Given `status_vendor = 0`, the milestone is 6.
- **AC-6** — A mixed batch routes each item independently.
- **AC-7** — `REVISI_OE` yields milestone 14 and no QCF write; `SURROGATE` yields 16.
- **AC-8** — After the change, the RFQ detail no longer offers Manual Sourcing for a
  successfully sourced RFQ. Verified against `useManualSourcing.js`: milestone 6 renders
  as `BID Submitted / Manual Sourcing`, which matches none of the twelve
  `canShowManualSourcing` cases, and `is_manual_sourcing` is false for both RFQs because
  it requires an **active** `WAITING_CS_EXPIRY` token.

## Out of scope

- The frontend. No change is required there for this defect.
- Remediating the two affected production rows. Needs a separate owner decision.
- The `sendActionToCS` edge case where `getItemList` does not contain a submitted id, so
  `item.status_vendor` stays `undefined` and the transfer is treated as failed. This is a
  safe fallback and was not reported.
- See `test-plan.md` "Adjacent finding" for the 9-day dual-vendor cron, which carries the
  same symptom from a different call site and is deliberately left unchanged.
