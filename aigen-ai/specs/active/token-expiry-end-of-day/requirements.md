# Requirements — Token deadline valid until end of day, landing pages read-only for inactive tokens

Status: In progress  
Owner: Unknown  
Repositories: aigen-backend, aigen-frontend  
Created: 2026-10-12  
Last updated: 2026-10-13

## Background and problem

Reported case: **RFQ0002356** — "Gagal — Token is not active." dialog.

Verified evidence (local DB on `DB_PORT` 3307, confirmed identical to production on 2026-10-13, read-only):

- **Deadline cut-off.** `rfq_token_email.id = 9099` (vendor 300022 KOPERASI KARYAWAN BINA BERSAMA,
  agregator, `Waiting_vendor_expiry`) was created 2026-09-29 08:04:05 with
  `date_expired = 2026-10-02 07:00:00` and closed at 2026-10-02 08:03:42 by the daily expiry cron, together
  with 17 other tokens of other RFQs that also expired 2026-10-02 07:00. The email showed "02 Oct 2026".
  100 % of recent `rfq_token_email` (4 133 rows) and `qcf_token_email` (529 rows) expire at 07:00:00.
- **Who saw the dialog (confirmed by BA, 2026-10-13): the DIC.** After token 9099 expired, the cron created
  DIC token **9184** (batch 4, `vendor_sequence` 3, 2026-10-02 08:03:40). The DIC page was opened while 9184
  was still active and showed the item as awaiting DIC confirmation with action buttons, while the RFQ still
  showed "Waiting Vendor" for the agregator. At 08:13:23 a DIC Accept closed 9184 (`is_active = 0`) and
  created CS token 9190. Around 11:00–12:00 the DIC clicked an action button in the **still-open tab**;
  `PUT /pr/dic/konfirmasi_penawaran` (`authService.authenticateTokenEmail`) answered 401
  "Token is not active.", shown as the "Gagal" dialog.
- This is **not** the Issue No. 11 pattern (cross-vendor deactivation; RFQ0002069 token 7959 is).

Root causes:

1. `addBusinessDays` (`aigen-backend/src/helper/date.js:58`) returns `startOf('day')` in the process
   timezone (UTC in production), so a token "valid until 02 Oct" dies at 02 Oct 07:00 WIB, while the email
   shows only the date. The expiry queries additionally select `date_expired <= endOf('day')`, so the
   ≈ 08:00 cron closes every token of the current day.
2. The landing endpoints `GET /pr/vendor/get_item_list_rfq/:token` and `GET /pr/dic/get_item_list_rfq/:token`
   use `decodeTokenWithForbiddenException` (JWT only). They never tell the page whether the
   `rfq_token_email` row is still active, so the page always renders action buttons; only the action
   endpoints reject the closed token. A tab opened while the token was active keeps its buttons after the
   token is closed.

## Goal

A token is usable through the whole deadline date shown in the email (until 23:59:59 WIB). A vendor or DIC
whose token is no longer active never sees action buttons on the landing page, including a page that was
opened before the token was closed.

## Scope

- Included:
  - Deadline/expiry computation for **all** email tokens stored in `rfq_token_email` and
    `qcf_token_email` (vendor, vendor direct, DIC, CS, OE, CL, management, …).
  - Expiry-cron selection queries for those tables.
  - Token state on the **vendor quotation** page (`/#/vendor/quotation/:token`) and the **DIC confirmation**
    page (`ConfirmationItemDIC`), on load and while the page stays open.
- Excluded:
  - Changing any error message text ("Token is not active." / "Token has expired." stay as-is).
  - Changing the action endpoints' validation (`authenticateTokenEmail` keeps rejecting closed tokens).
  - Issue No. 11 (cross-vendor deactivation) — separate fix queue.
  - Other token pages (CS, CL, management, quotation summary, OE).
  - Back-filling `date_expired` of tokens already issued.
  - Business-day/holiday calendar changes (still Mon–Fri only).

## Actors

| Actor/system | Need or responsibility |
|---|---|
| Vendor / agregator | Can open and submit the offer until 23:59:59 WIB of the deadline date |
| DIC | Can confirm until 23:59:59 WIB of the deadline date; sees no buttons once the token is closed |
| CS, CL, Management | Same end-of-day validity for their email links |
| Expiry cron (`src/cron.js`, daily ≈ 08:00 WIB, scheduled outside the repo) | Closes only tokens whose deadline has actually passed |

## Functional requirements

- **FR-1:** The stored `date_expired` of every newly issued email token equals 23:59:59 **Asia/Jakarta** of
  the deadline business date, regardless of the server process timezone.
- **FR-2:** The deadline date printed in emails is the same calendar date (Asia/Jakarta) as `date_expired`.
- **FR-3:** The JWT `exp` of a newly issued token is not earlier than its `date_expired`.
- **FR-4:** The expiry cron selects only tokens with `is_active = 1 AND date_expired <= NOW()`; a token
  whose deadline is later today is never closed early.
- **FR-5:** `GET /pr/vendor/get_item_list_rfq/:token` and `GET /pr/dic/get_item_list_rfq/:token` keep their
  current status codes and payload, and add a boolean that is `true` only when the `rfq_token_email` row
  exists, `is_active = 1`, and `date_expired` is empty or in the future.
- **FR-6:** When that boolean is `false`, the vendor quotation page and the DIC confirmation page render
  their content read-only, without any action button (vendor: Submit/Reset/upload/status changes;
  DIC: accept/revise/submit). No error dialog, toast, or new message is shown for this state.
- **FR-7:** While either page is open, it re-checks the token state when the tab becomes visible again and
  immediately before sending an action. If the token is no longer active, the page switches to the
  read-only state of FR-6 without sending the action and without an error dialog. The re-check uses
  `GET /pr/token/status/:token`, which always answers HTTP 200 `{ token_active: boolean }` for a
  well-formed request (`false` for an invalid JWT, missing/inactive row, or passed `date_expired`), so the
  frontend 401 interceptor never redirects or shows a toast. A failed re-check request leaves the page
  unchanged; the action endpoint stays authoritative.
- **FR-7a:** Tokens issued outside `calculateSubmissionDeadlineAndSla` (`generateTokenRFQ`, the DIC reminder
  token in `qcfController`) follow FR-1 and FR-3 as well.
- **FR-8:** Messages are unchanged: "Token is not active.", "Token has expired.", "Token not found in database.".

## Business rules

- **BR-1:** A deadline date is valid through 23:59:59 WIB of that date (confirmed by business, 2026-10-12;
  re-confirmed by BA, 2026-10-13: "berlaku sampai" = end of that day).
- **BR-2:** Business timezone is Asia/Jakarta (`config.tz`, default `Asia/Jakarta`).
- **BR-3:** Deadline = start date + N business days (Mon–Fri), unchanged.
- **BR-4 (Inferred):** Because the cron runs once a day at ≈ 08:00 WIB, follow-up actions after an expiry
  (send to CS / DIC / sibling, RFQ Not Submitted) now happen on the morning **after** the deadline date
  instead of the morning **of** it. Business should confirm this is acceptable.
- **BR-5:** An inactive token means no buttons on the landing page; the "Token is not active." text does not
  need to be shown to the user (BA, 2026-10-13).

## Security and permissions

- Authentication mechanism: JWT in the URL path, plus the `rfq_token_email` row as the revocation record.
- Action endpoints remain the enforcement point; the landing flag is presentation only.
- Sensitive data/logging constraints: never log the token string.

## Acceptance criteria

- **AC-1:** Given a vendor token issued 2026-09-29 08:04 WIB with SLA 3 business days, then
  `date_expired = 2026-10-02 23:59:59` (WIB) and the email shows "02 Oct 2026".
- **AC-2:** Given AC-1's token, when the vendor opens the link and submits on 2026-10-02 at 15:00 WIB,
  then the page loads with the form and the submit succeeds.
- **AC-3:** Given AC-1's token, when the cron runs on 2026-10-02 at 08:00 WIB, then the token stays
  `is_active = 1`; when it runs on 2026-10-03 at 08:00 WIB, then it is processed as expired.
- **AC-4:** Given a vendor token with `is_active = 0` and a valid JWT, when the vendor opens the link, then
  the quotation is shown read-only with no Submit/Reset/upload button and no error dialog or toast.
- **AC-5:** Given a DIC token with `is_active = 0` whose items are still awaiting DIC, when the DIC opens the
  link, then the items are shown read-only with no action button and no error dialog or toast.
- **AC-6 (RFQ0002356 scenario):** Given the DIC page opened while the token was active, when the token is
  closed by another action and the DIC returns to the tab or clicks an action, then the page switches to
  read-only, no request is sent to `konfirmasi_penawaran`, and no "Token is not active." dialog appears.
- **AC-7:** Given a token whose `date_expired` passed but the cron has not run yet, the landing flag is
  `false` (same read-only behaviour).
- **AC-8:** Given the server process runs in UTC, AC-1 and AC-3 still hold.
- **AC-9:** Given an issue time between 00:00 and 07:00 WIB, the business-day count starts from the WIB
  date (not the UTC date).

## Non-functional requirements

- Performance/concurrency: one extra indexed lookup on `rfq_token_email` per landing load / re-check.
- Reliability/idempotency: cron behaviour stays idempotent; only the cut-off changes.
- Observability: no new logging required.

## Open questions

- BR-4 timing shift — confirm with business.
- Tokens already issued keep their 07:00 `date_expired`; confirm no back-fill is wanted.
- A race between the pre-action re-check and the action itself can still surface the existing dialog
  (accepted; the action endpoint stays authoritative).
