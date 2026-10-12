# Requirements — Flag vendor prices outside the Min/Max price band on the DIC and CL/Management screens

Status: Implemented (backend, frontend), not yet released  
Owner: Unknown  
Repositories: aigen-backend, aigen-frontend (no DB schema change, no migration, no route change, additive response fields only)  
Created: 2026-10-12  
Last updated: 2026-10-12

## Background and problem

At vendor submit, `prController.bulkUpdateRfqStatusVendor` (`PUT /pr/vendor/submit_penawaran`) checks the vendor
unit price against the band [`Min_price`%, `Max_price`%] x OE, where OE = `rfq_library.item_value` (unit price),
using `maxPricevalidation` (`src/utils/priceValidation.js`). The percentages are `config_autopo` rows with
`config_condition` `Min_price` / `Max_price` per `server_group`. Currently BCG and GEMS are both 80 and 110.

An out-of-band price is only warned to the vendor, who can continue with "Lanjutkan tanpa revisi". Nothing is
persisted, so DIC and CL see no warning when they review or approve the price.

Verified evidence:

- **RFQ0002018** (vendor 108175, quotation A009-002): items 260 and 270 were priced at 34% and 40% of OE
  (item 260: 24,000 vs OE 70,000; item 270: 20,000 vs OE 50,000; band 80%-110% = 56,000-77,000 and
  40,000-55,000). Both were approved (QCF0000827, PO 4910020970) without any reviewer-facing warning.
- Impact (local DB snapshot): 465 of 1,644 QCF items (about 28%) are outside the band.

## Goal

Show DIC, CL and Management a clear marker next to any item whose vendor price is outside the configured
Min/Max band, derived at read time, so they can decide knowingly.

## Scope

- Included:
  - Backend: pure helpers in `src/utils/priceValidation.js` (`isPriceOutOfRange`, `parsePriceRange`) and a
    config loader / flag builder in `src/helper/priceRange.js` (`loadPriceRanges`, `buildPriceRangeFlag`).
  - Backend: additive per-item fields `isPriceOutOfRange`, `priceRangeMinPct`, `priceRangeMaxPct` on
    - `qcfLibrary.repository.listApprovalItemQCF` and `listApprovalItemQCFForManagement` (feeding
      `GET` handlers `getApprovalQCFByCL`, `getApprovalQCFByManagement`, `getApprovalQCFByManagementToken`);
    - `PurchaseRequest.repository.listItemRFQDIC` (feeding `listItemRFQDIC`,
      `GET /pr/dic/get_item_list_rfq/:token`, and `listItemRFQDICAuth`,
      `GET /pr/dic/get_item_list_rfq_by_number/:rfq_number`); here the fields are on each entry of
      `items[].vendors[]` because price is per vendor.
  - Frontend: shared `PriceOutOfRangeChip.vue`; shown on the CL/Management QCF screens
    (`QuotationSummaryCL.vue`, `PreviewQuotationSummaryCL.vue`), the DIC confirmation screen
    (`TableConfirmationItems.vue`) and the DIC preview (`TablePreviewDIC.vue`).
- Excluded:
  - **Historical config is not tracked.** The flag uses the *currently active* `Min_price` / `Max_price`. If
    the band changes later, old QCFs/RFQs are re-evaluated against the new band. Accepted trade-off to avoid a
    schema change or persisting the flag.
  - **No vendor-side change.** The vendor warning, "Lanjutkan tanpa revisi" and the submit validation are
    untouched.
  - No persistence, no blocking, no approval-rule change, no email/report change, no summary banner.
  - Other screens (admin dashboards, CS price-not-match screens) are not changed.

## Actors

| Actor/system | Need or responsibility |
|---|---|
| DIC | See, while confirming offers, that a vendor price is outside the allowed band |
| CL / Management | See the same marker on the QCF before approving |

## Functional requirements

- **FR-1:** `isPriceOutOfRange(vendorPrice, itemValue, minPct, maxPct)` returns `true` when
  `!(vendorPrice >= itemValue * (minPct / 100) && vendorPrice <= itemValue * (maxPct / 100))` - the same
  inclusive arithmetic as the submit check. Inputs may be numbers or decimal strings.
- **FR-2:** It returns `false` (not flagged) for a null/undefined/empty vendor price, a null/undefined/empty
  or zero OE, or a missing/non-numeric percentage.
- **FR-3:** `parsePriceRange(minConfig, maxConfig)` returns `{ minPct, maxPct }` or `null` when either config
  row is missing/inactive or not numeric.
- **FR-4:** `loadPriceRanges(serverGroups)` reads `Min_price` and `Max_price` (`is_active: 1`) via
  `getConfigDetail` once per distinct server group per request, never per item; a failed read resolves to
  `null` instead of throwing, so the host endpoint never breaks.
- **FR-5:** Each QCF item (CL and Management lists) carries `isPriceOutOfRange` (boolean), `priceRangeMinPct`
  and `priceRangeMaxPct` (number or `null`). OE is `request_price` (`qcf_library.item_value`), vendor price is
  `offer_vendor_price`.
- **FR-6:** Each `items[].vendors[]` entry of the DIC list carries the same three fields (OE = `request_price`,
  vendor price = `price`/`offer_vendor_price`).
  The DIC list flags **accepted vendors only** (`status_vendor = ACCEPTED`); declined, pending and
  need-confirmation vendor entries always get `isPriceOutOfRange = false` (their min/max pct fields are still
  returned). The QCF lists need no such rule: their rows are awarded `qcf_library` rows.
- **FR-7:** With a missing or inactive config the fields are `false`, `null`, `null`; no error is returned.
- **FR-8 (frontend mapping):** `mapQcfItem` (`QuotationSummaryCLService.js`) maps the three fields (defaults
  `false`, `null`, `null`); `getConfirmationData` (`ConfirmationItemDICService.js`) maps them per vendor.
- **FR-9 (UI):** `PriceOutOfRangeChip` renders a small warning `v-chip` only when out of range, with text
  `Di luar batas harga (80%–110% OE)` using the returned percentages (the bracket is omitted when a percentage
  is `null`).
  - CL/Management screens: in the "Harga" row, Deviasi cell, below the existing deviation text.
  - DIC preview: in the "Harga" row, Deviasi cell, replacing the intentionally blank `-` only when flagged.
  - DIC confirmation: this screen has **no price row** (only Jumlah, Tanggal Pengiriman, Brand, Garansi,
    Alamat Pengiriman), so the chip is placed next to the vendor label (multi vendor) or under the item name
    (single vendor). No price value is shown there.

## Business rules

- **BR-1:** The band is [Min_price%, Max_price%] x OE, bounds inclusive (RFQ0002018: 24,000 vs 70,000 is
  34% -> out; 70,000 vs 70,000 -> in; 56,000 and 77,000 -> in).
- **BR-2:** The flag is informational only; it never blocks DIC confirmation or CL/Management approval.
- **BR-3 (Inferred):** A vendor price of 0 against a non-zero OE is flagged (consistent with submit check).

## Security and permissions

- No new endpoint, role or request field. Response changes are additive fields only, on endpoints that already
  return OE and vendor price (the DIC token endpoint already returned both).
- The band percentages are exposed to DIC/CL/Management; they already see the pricing data on these screens
  (the DIC confirmation screen did not render price, but the API already returned it).

## Acceptance criteria

- **AC-1:** 24,000 vs OE 70,000 and 20,000 vs OE 50,000 at 80-110 -> `isPriceOutOfRange = true`.
- **AC-2:** 70,000 vs OE 70,000 -> `false`; boundaries 56,000 and 77,000 -> `false`; 55,999 and 77,001 -> `true`.
- **AC-3:** Null/zero OE, null vendor price -> `false`.
- **AC-4:** Missing/inactive/non-numeric config -> `false`, percentages `null`, no error.
- **AC-5:** Config rows are read once per server group per request (two `getConfigDetail` calls for a
  single-group QCF regardless of item count).
- **AC-6:** `listApprovalItemQCF` and `listApprovalItemQCFForManagement` items include the three fields.
- **AC-7:** Existing response fields keep their names and shape; no other field changes.
- **AC-8:** The marker is visible on the CL, Management (and token) QCF screens, the DIC confirmation screen
  and the DIC preview for out-of-band items, and absent for in-band items.

## Non-functional requirements

- Performance: +2 indexed config lookups per distinct server group per request (typically 1 group).
- Reliability: config read failure degrades to "no flag".
- Observability: failed config read is logged via `console.error` (existing `getConfigDetail` behaviour).

## Verification notes

- Backend tests: `tests/utils/priceValidation.priceRange.test.js` (FR-1..FR-3, parity with
  `maxPricevalidation`), `tests/helper/priceRange.test.js` (FR-4, FR-7),
  `tests/repository/qcfLibrary.listApprovalItemQCF.priceRange.test.js` (FR-5, AC-5, AC-6).
- `tests/repository/PurchaseRequest.listItemRFQDIC.priceRange.test.js` (FR-6): accepted vendor flagged,
  declined/pending vendors not flagged.
- No frontend test runner exists; verification is `eslint` plus a manual check with an out-of-band item
  (e.g. RFQ0002018 / QCF0000827) on the screens listed in FR-9.

## Open questions

- Should the flag eventually be persisted so a later band change does not re-evaluate historical QCFs?
- Should a summary banner be shown above the item table when any item is out of band?
