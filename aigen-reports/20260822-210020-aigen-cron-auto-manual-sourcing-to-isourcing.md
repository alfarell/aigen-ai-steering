# Analisis Cron Auto Manual Sourcing — Insert Data ke Database iSourcing (`task_board`)

| Metadata | Nilai |
|---|---|
| Tanggal analisis | 2026-08-22 |
| Repository | `aigen-backend` |
| Branch | `develop-dot` |
| Commit HEAD | `4d30f82d` (Merge branch `fix/expiry-cron-handlers-and-po-published-leak`) |
| Metode | Pembacaan kode statis (read-only). Tidak ada perintah yang menyentuh database dijalankan. |
| Cakupan | Proses cron `aigen-backend` yang melakukan INSERT ke schema iSourcing (`DB_DATABASE2` / task board) |

---

## 1. Ringkasan Eksekutif

Di `aigen-backend` hanya ada **satu jalur kode** yang melakukan INSERT ke database iSourcing
(`task_board` / `DB_DATABASE2`), yaitu fungsi privat **`prosesToIsourcing()`** di
`src/controllers/qcfController.js:1103`.

Cron **tidak pernah** menulis ke task_board secara langsung. Seluruh stage cron memanggilnya
melalui adapter tepercaya `executeSystemManualSourcing()` → `sendActionToCS()` — proses yang
dikenal sebagai **Auto Manual Sourcing** (konversi otomatis item RFQ ke iSourcing karena SLA
suatu stage terlampaui).

Entry point cron adalah `src/cron.js` (`npm run run:cron`). Proses ini sekali-jalan-lalu-exit.
**Tidak ada `node-cron` atau scheduler di dalam repository**; penjadwalan berada di crontab host
(lihat `scripts/check-cron-health.sh` dan `docs/bugfix-plan-dic-expiry-and-po-published-leak.md`).

---

## 2. Daftar Proses Cron yang Insert ke `task_board`

| # | Stage CLI | Handler cron | Lokasi | Kondisi pemicu | Item yang dikirim |
|---|---|---|---|---|---|
| 1 | `dic` | `prService.handleExpiredDICReview` | `src/services/prService.js:448` | Token `Waiting_DIC_review_expiry` masih `is_active = true` dan `date_expired <= akhir hari ini` | Item `status_dic = NULL` dengan `status_vendor` ACCEPTED / NEED_CONFIRMATION |
| 2 | `cs` | `prService.handleExpiredCSReview` | `src/services/prService.js:505` | Token `Waiting_CS_expiry` expired | 4 sumber berprioritas dengan `else if` (hanya satu yang dieksekusi): **B** price-not-match → **D** surrogate → **A** declined vendor → **C** not-submitted |
| 3 | `oe` | `prService.handleExpiredOERevision` | `src/services/prService.js:777` | Token `Waiting_OE_revision_expiry` expired | Hasil `prController.getOERevisionByCS` |
| 4 | `cl` | `qcfService.handleExpiredCLReview` | `src/services/qcfService.js:57` | Token QCF `Waiting_CL_review_expiry` expired | QCF dengan `cl_approved_at IS NULL`, `po_number IS NULL`, `status_milestone` bukan SAP_SYNC_COMPLETE / QCF_MANUAL_SOURCING / MANUAL_SOURCING_FAILED |
| 5 | `management` | `qcfService.handleExpiredManagementReview` | `src/services/qcfService.js:103` | Token QCF `Waiting_Management_review_expiry` expired | Sama seperti no. 4, tetapi kolom `management_approved_at` |

### 2.1 Jalur dormant (tidak aktif)

- `qcfController.handleNineDayRfqFollowUp` (`src/controllers/qcfController.js:3187`) memanggil
  `prosesToIsourcing()` **secara langsung**, tetapi pemanggilannya dari cron sudah dikomentari di
  `src/cron.js:36-37`. Saat ini tidak pernah berjalan dari cron.

### 2.2 Stage cron yang TIDAK menulis ke task_board

- `vendor_direct` — `prService.handleExpiredVendorDirect`
- `vendor` — `prService.handleExpiredVendor`
- Blok reminder tanpa-stage: `notifyForSingleSubmissionDeadline`, `sendDicConfirmationReminders`,
  `handleSingleSubmissionFollowUp`, `handleDeclinedAndPendingFollowUp`

Seluruhnya hanya membaca data, mengirim email, dan memperbarui database Aigen.

---

## 3. Tabel `task_board` yang Di-INSERT

Semua write melalui `src/repository/qcfLibrary.repository.js` dengan koneksi `seqSourcing`
(`src/config/database_isourcing.js`, database `DB_DATABASE2`).

| Tabel | Fungsi repository | Baris | Keterangan |
|---|---|---|---|
| `board_card` | `insertBoardCard` / `insertBoardCardAndReturnId` | L1792 / L1796 | Header PR: kartu Admin (`board_id=1, user_id=1, list_id=1`), kartu kategori, kartu milik CL |
| `counter_split_pr_items` | `insertCounterSplit` | L1824 | Nomor split untuk kartu CL |
| `item_card` | `insertItemCard` | L1899 | Baris item PR |
| `exports_data` | `insertExportData` | L1913 | Raw SQL `INSERT … SELECT` join `board_card` + `item_card` + `milestone_config` |
| `pr_logs` | `insertPRLogs` | L2005 | Log lifecycle PR/item |
| `history_log_assign` | `insertHistoryLog` | L2009 | Aktivitas `Auto Assign` (PR baru) / `New Item` (PR existing) |

UPDATE pendamping pada schema yang sama: `updateAdminCardHeader` dan `updateSplitCard`
(keduanya menyentuh `board_card`).

Model Sequelize terkait berada di `src/models/isourcing/`: `boardCard.js`, `boardList.js`,
`itemCard.js`, `counterSplitPrItems.js`, `prLogs.js`, `historyLogAssign.js`.

---

## 4. Flow Lengkap

### 4.1 Alur end-to-end (contoh stage `dic`)

```
node src/cron.js [--stage=dic] [--rfq_number=RFQ0001446]
  └─ sequelize.authenticate() → delay 5 detik → runCronTasks()
       └─ prService.handleExpiredDICReview()
            ├─ getExpiredRFQTokenEmailByConfig('Waiting_DIC_review_expiry')      [DB aigen]
            └─ untuk setiap token:
                 ├─ findItemsAwaitingDicReview() → excludeFinishedItems()
                 │     (buang item tipe_rfq = isourcing, dan item yang sudah punya po_number)
                 ├─ bentuk req mock: user = ADMIN_APP_USER (id 1, "Admin Procurement - (By system)")
                 │                   body.rfq_tipe = 'isourcing'
                 ├─ qcfController.executeSystemManualSourcing(req, ResMocker)
                 │     └─ sendActionToCS() dengan trusted marker (Symbol privat modul)
                 │          ├─ prosesToIsourcing(pr_number, server_groups, items)   ◄── INSERT task_board
                 │          ├─ addLogQuotationByDataItems(
                 │          │      milestone 12 ISOURCING untuk item ACCEPTED,
                 │          │      milestone 6 BID_MANUAL_SOURCING untuk sisanya,
                 │          │      LOG_TYPE.SLA, actor SYSTEM)
                 │          └─ transaksi DB aigen:
                 │                 bulkUpdateStatusRFQ(tipe_rfq='isourcing', sourcing_reason, sourcing_notes)
                 │               + rfqTokenStore.deactivateTokens(rfq_number, vendor_batch, vendor_code)
                 │               + qcfTokenStore.deactivateTokensByRfqNumber(rfq_number)
                 ├─ rfqLibrary.update({ status_dic: STATUS_DIC.PENDING })
                 └─ rfqTokenStore.updateToken(is_active = false)
                       // bila terjadi error: token dibiarkan aktif agar di-retry pada run berikutnya
```

### 4.2 Detail `prosesToIsourcing()` (`qcfController.js:1103`)

#### Persiapan

1. `card_title = getPrefix(server_groups) + pr_number`.
   Prefix (`src/helper/log.js:599`): `BC`/`BCG` → `B`, `gems`/`GEMS` → `G`, `BKES` → `K`,
   selain itu string kosong.
2. Membuka **satu transaksi** pada koneksi iSourcing. Seluruh write ke task_board memakai
   `{ transaction }` yang sama.
3. `countByCardTitle(card_title)` menentukan cabang eksekusi.

#### Cabang A — PR baru (`count < 1`)

1. `getMaterialGroupData()` membaca `${DB_DATABASE3}.search_library` (iSearch) melalui koneksi
   primer, dengan filter: `tipe_data = 'DETAIL'`, `status = 'Full Release'`,
   `groups = server_groups`, `material_number IN (item_code)`, serta wajib memiliki
   `pr_release_date`, `pr_material_group_number` non-kosong, dan `company <> 0`.
   Hasil di-dedupe per material group memakai ordering deterministik.
   Bila kosong → rollback dengan kode `ISOURCING_SOURCE_HEADER_INCOMPLETE`.
2. Untuk setiap material group: `getCategoryDetail()` (join `category_group` +
   `matrix_auto_assign` + `board_list` di task_board) menghasilkan `list_id`, `card_color`,
   `asigned_id`. Bila tidak ada mapping → default Admin (`list_id = 1`) disertai warning
   `[ISOURCING] CATEGORY_MAPPING_NOT_FOUND`.
3. `buildHeaderMetadata()` + `validateISourcingHeader()`. Field wajib: `card_title`,
   `pr_release_date`, `pr_company_groups`, `company` (dan tidak boleh 0),
   `pr_material_group_number`, `pr_value`, `currency`. Satu saja invalid → rollback dengan daftar
   field `missing`.
4. **INSERT `board_card`** per kategori (dilewati bila `findExistingCard` sudah menemukan kartu),
   `partial_status = 'NEW'`, `split_from`/`split_for` = `null` untuk Admin dan `'pr_item'`/`'CL'`
   untuk kartu kategori.
5. Bila `list_id != 1`: `getSplitCount` → `getBoardAssigned` → `findAutoAssignedCard`.
   Bila kartu CL belum ada → **INSERT `board_card`** milik CL (mengambil id) →
   **INSERT `counter_split_pr_items`** → `updateSplitCard(split_no, is_updated = 1)`.
6. `ensureActiveAdminHeader()` memastikan tersedia kartu Admin aktif (`complete = '0'`) yang valid.
   Bila tidak valid, header direkonstruksi dari kartu historis (`findValidHeaderCardByTitle`) lalu
   di-`update`, atau **INSERT `board_card`** Admin baru. Gagal → `ISOURCING_VALID_HEADER_NOT_FOUND`
   atau `ISOURCING_HEADER_REPAIR_FAILED`.
7. Loop item — `getDetailItemCard()` membaca `rfq_library` di DB Aigen (group by `item_code`):
   - dilewati bila `findCompletedCardByTitle(complete = 1)` atau `countItemCard >= 1`
     (mekanisme **idempotensi**);
   - `getCategoryAssignment()` menentukan auto-assign CL (`assigned_to_cl`, `send_email_to`,
     `is_updated = 1`), fallback ke `Admin`;
   - **INSERT `item_card`** → **INSERT `exports_data`** → **INSERT `pr_logs`** →
     **INSERT `history_log_assign`** dengan `activity = 'Auto Assign'`.
8. Postcondition: kartu Admin divalidasi ulang dan item yang baru di-insert dibaca ulang.
   Mismatch → rollback `ISOURCING_HEADER_VERIFICATION_FAILED`. Bila lolos → `commit`.
   Pesan sukses: `PR with number <card_title> success import`.

#### Cabang B — PR sudah ada (`count >= 1`)

`getItemsByCardTitle()` → `ensureActiveAdminHeader()` → untuk setiap item: dilewati bila
`countItemCard >= 1`, selain itu **INSERT `item_card`** (tanpa auto-assign CL:
`assigned_to_cl = null`, `send_email_to = null`, `is_updated = null`) + `exports_data` +
`pr_logs` + `history_log_assign` (`activity = 'New Item'`, kategori `Admin`) → verifikasi
postcondition → `commit`.
Pesan sukses: `PR with number <card_title> already exists. Missing items added: N`.

#### Penanganan kegagalan

Kegagalan dikembalikan sebagai objek `{ success: false, card_title, code, missing, message }`,
bukan exception. `sendActionToCS` menghentikan proses **sebelum** mutasi DB Aigen dan
mengembalikan HTTP 400. Di sisi cron, respons non-2xx menjadi `ManualSourcingInvocationError`,
sehingga token dibiarkan aktif untuk di-retry pada run berikutnya.

Kode error yang mungkin muncul:

| Kode | Penyebab |
|---|---|
| `ISOURCING_SOURCE_HEADER_INCOMPLETE` | `search_library` tidak mengembalikan baris valid, atau header sumber tidak lengkap |
| `ISOURCING_VALID_HEADER_NOT_FOUND` | Tidak ada kartu manapun yang bisa dijadikan sumber header valid |
| `ISOURCING_HEADER_REPAIR_FAILED` | Perbaikan/pembuatan kartu Admin tetap menghasilkan header invalid |
| `ISOURCING_HEADER_VERIFICATION_FAILED` | Postcondition sebelum commit tidak terpenuhi |
| `ISOURCING_TRANSFER_FAILED` | Fallback default di `sendActionToCS` |
| `ITEM_SCOPE_REQUIRED` / `ITEM_SCOPE_MISMATCH` | Hanya untuk invokasi HTTP, bukan cron |

---

## 5. Catatan Penting dan Risiko

- **Batas transaksi.** Seluruh write task_board berada dalam satu transaksi `database_isourcing`.
  Mutasi DB Aigen (status RFQ + deaktivasi token) memakai transaksi terpisah dan baru dijalankan
  **setelah** task_board commit. Konsekuensinya: kegagalan pada sisi Aigen setelah commit tidak
  me-rollback kartu yang sudah terbentuk di task_board.
- **Lintas tiga schema dalam satu proses.** Membaca `search_library` (`DB_DATABASE3` / iSearch)
  dan `rfq_library` + `qcf_library` (`DB_DATABASE` / Aigen), menulis ke `DB_DATABASE2`
  (task_board).
- **Idempotensi bertumpu pada COUNT, bukan constraint database.** Sesuai KI-012 dan KI-013 di
  `aigen-ai/context/known-issues.md`: tidak ada migrasi unique constraint maupun lock tambahan,
  sehingga run cron yang tumpang-tindih masih berisiko menghasilkan duplikat.
- **Aktor.** Semua insert dari cron tercatat atas nama user id `1`
  (`Admin Procurement - (By system)`, `src/const/defined-user.js`) dengan `LOG_ACTOR.SYSTEM`.
- **Penjadwalan berada di luar repository.** `src/cron.js` menjalankan seluruh stage satu kali lalu
  keluar; eksekusi bergantung pada crontab host. Sebelum menyimpulkan penyebab suatu anomali data,
  pastikan dulu stage terkait memang pernah berjalan di lingkungan tersebut.
- **Spesifikasi aktif yang mengatur perilaku ini:**
  `aigen-ai/specs/active/auto-manual-sourcing-header-integrity/spec.md` — Delivery 1 sampai 5 sudah
  diimplementasikan dan diverifikasi secara lokal; mutasi data produksi belum dilakukan.
- **Verifikasi yang belum ada** (menurut known-issues): jalur ini belum diuji terhadap schema MySQL
  nyata yang terisolasi, dan belum dijalankan pada window cron menyerupai produksi.

---

## 6. Referensi File

| File | Peran |
|---|---|
| `aigen-backend/src/cron.js` | Entry point cron, orkestrasi per stage, parsing `--stage` dan `--rfq_number` |
| `aigen-backend/src/const/cron-stages.js` | Daftar stage valid |
| `aigen-backend/src/const/config-auto-po.js` | Kunci konfigurasi SLA/expiry per stage |
| `aigen-backend/src/services/prService.js` | Handler expiry stage vendor_direct, vendor, dic, cs, oe |
| `aigen-backend/src/services/qcfService.js` | Handler expiry stage cl dan management |
| `aigen-backend/src/controllers/qcfController.js` | `executeSystemManualSourcing`, `sendActionToCS`, `prosesToIsourcing`, `ensureActiveAdminHeader` |
| `aigen-backend/src/repository/qcfLibrary.repository.js` | Seluruh fungsi insert/lookup task_board |
| `aigen-backend/src/config/database_isourcing.js` | Koneksi Sequelize ke `DB_DATABASE2` |
| `aigen-backend/src/models/isourcing/*.js` | Model tabel task_board |
| `aigen-backend/src/repository/rfqTokenEmail.query.repository.js` | Query token expired berdasarkan config |
| `aigen-backend/scripts/check-cron-health.sh` | Diagnosa read-only penjadwalan dan aktivitas cron di host |
