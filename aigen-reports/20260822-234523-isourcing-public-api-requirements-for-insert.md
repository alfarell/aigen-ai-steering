# Kebutuhan API Publik iSourcing untuk Insert Data dari Aigen

| Metadata | Nilai |
|---|---|
| Tanggal | 2026-08-22 |
| Status | **Draft — menunggu kontrak resmi dari tim iSourcing** |
| Sistem sumber | `aigen-backend` (cron auto manual sourcing + route HTTP manual sourcing) |
| Sistem tujuan | iSourcing baru (**isourcing-vanilla**) |
| Dokumen terkait | `aigen-reports/20260822-210020-aigen-cron-auto-manual-sourcing-to-isourcing.md` |
| Sifat dokumen | Kebutuhan dari sisi konsumen (Aigen). Bukan spesifikasi final; menjadi bahan diskusi dengan tim iSourcing. |

---

## 1. Konteks

Saat ini `aigen-backend` menulis **langsung ke database `task_board`** melalui koneksi MySQL
(6 tabel, satu transaksi). Ke depan penulisan tersebut diganti menjadi pemanggilan API publik
milik iSourcing.

Di sisi Aigen akan disiapkan **port transfer tersentralisasi** dengan dua driver (`database` dan
`api`) yang dipilih lewat satu variabel `.env`. Kerangka driver API dibangun lebih dulu, sehingga
ketika kontrak API tersedia yang perlu ditambahkan hanya: **API path, bentuk payload, kredensial,
dan mapping error**.

### Keputusan yang sudah ditetapkan

| Kode | Keputusan |
|---|---|
| K-1 | Autentikasi memakai **Basic Auth**, kredensial disimpan di `.env`, dikirim langsung pada pemanggilan API insert |
| K-2 | API **menjamin atomicity**: satu PR beserta seluruh itemnya terbentuk seluruhnya atau tidak sama sekali, melalui **satu endpoint** yang menerima header + items |
| K-3 | **Auto-assign kategori/CL dilakukan oleh iSourcing**, bukan oleh Aigen |
| K-4 | Tabel `exports_data` **tidak diperlukan** di isourcing-vanilla — proses ini diabaikan pada mode API |
| K-5 | Bila API gagal, Aigen **tidak melakukan fallback** ke penulisan database. Transfer dinyatakan gagal dan diulang pada run cron berikutnya |
| K-6 | Tidak ada mode shadow/dry-run |

---

## 2. Ringkasan Endpoint yang Dibutuhkan

| # | Endpoint | Prioritas | Kegunaan |
|---|---|---|---|
| **E-1** | Transfer PR ke iSourcing (header + items) | **Wajib** | Satu-satunya jalur penulisan. Menggantikan seluruh penulisan langsung ke database |
| **E-2** | Cek keberadaan PR / item | Direkomendasikan | Idempotensi dan penambahan item yang tertinggal. Dapat ditiadakan bila E-1 bersifat *upsert* |
| **E-3** | Health check | Opsional | Verifikasi konektivitas dan kredensial saat boot atau saat diagnosa |

Bila E-1 sudah bersifat *upsert* penuh (lihat §3.5), **E-2 tidak diperlukan** dan cukup satu
endpoint saja.

---

## 3. E-1 — Transfer PR ke iSourcing

### 3.1 Ringkasan

| Aspek | Kebutuhan |
|---|---|
| Method | `POST` |
| Path | **Belum ditentukan** — akan disimpan di `.env` sebagai `ISOURCING_API_TRANSFER_PATH` |
| Auth | Basic Auth pada header `Authorization` |
| Content-Type | `application/json` |
| Atomicity | Header + seluruh item dalam satu transaksi (K-2) |
| Idempotensi | Wajib — lihat §3.5 |
| Timeout klien | Default 10 detik (dapat dikonfigurasi) |

### 3.2 Payload — struktur umum

```json
{
  "idempotency_key": "B1200027667:00010,00020",
  "correlation_id": "cron-dic-20260822-231500-0007",
  "source": "aigen",
  "reason": "Auto-converted to iSourcing due to expired DIC action",
  "notes": "Auto-converted to iSourcing due to expired DIC action",
  "actor": {
    "user_id": 1,
    "name": "Admin Procurement - (By system)",
    "role": "admin"
  },
  "header": { "…lihat §3.3…" },
  "items": [ { "…lihat §3.4…" } ]
}
```

### 3.3 Payload — `header`

Sumber: `buildHeaderMetadata()` di `qcfController.js`, yang membaca `search_library` (iSearch).
Kolom tujuan lama adalah `board_card`.

| Field | Tipe | Wajib | Sumber di Aigen | Catatan |
|---|---|---|---|---|
| `card_title` | string(100) | ✔ | `getPrefix(server_groups) + pr_number` | Identitas kartu. Prefix: `BC`/`BCG` → `B`, `GEMS` → `G`, `BKES` → `K` |
| `pr_number` | string | ✔ | `rfq_library.pr_number` | Nomor PR tanpa prefix, dikirim terpisah agar iSourcing tidak perlu mem-parsing `card_title` |
| `pr_company_groups` | string(10) | ✔ | `server_groups` | Nilai: `BC`, `BCG`, `GEMS`, `BKES` |
| `company` | integer | ✔ | `search_library.company` | Tidak boleh `0` atau kosong |
| `pr_release_date` | date | ✔ | `search_library.pr_release_date` | |
| `pr_value` | decimal | ✔ | `search_library.src_value` | |
| `currency` | string(10) | ✔ | `search_library.src_currency` | |
| `pr_material_group_number` | string(10) | ✔ | `search_library.pr_material_group_number` | Dasar auto-assign kategori di sisi iSourcing |
| `pr_material_group` | string(100) | | `search_library.pr_material_group` | |
| `pr_service_group_number` | string(10) | | `search_library` | |
| `pr_service_group` | string(100) | | `search_library` | |
| `convert_value` | bigint | | `search_library.value` | Nilai konversi |
| `convert_currency` | string(5) | | `search_library.currency` | |
| `card_description` | string(255) | | item pertama `search_library` | Fallback: teks item dari dashboard |
| `pr_requestor_user` | string(100) | | `search_library` | |
| `pr_requestor_email` | string(150) | | `search_library` | |
| `pr_creator_user` | string(150) | | `search_library` | |
| `pr_creator_email` | string(200) | | `search_library` | |
| `purchase_group_code` | string(50) | | `search_library` | |
| `purchase_group` | string(100) | | `search_library` | |
| `pr_risk` | string(5) | | `search_library` | |
| `pr_permit1` / `pr_permit2` / `pr_permit3` | string(200) | | `search_library` | |
| `partial_status` | string(5) | | konstanta `"NEW"` | Dapat dihilangkan bila iSourcing menetapkannya sendiri |

**Tujuh field wajib** (`card_title`, `pr_release_date`, `pr_company_groups`, `company` ≠ 0,
`pr_material_group_number`, `pr_value`, `currency`) sudah divalidasi Aigen **sebelum** permintaan
dikirim. Aigen tidak akan mengirim header yang tidak lengkap.

### 3.4 Payload — `items[]`

Sumber: `rfq_library` (database Aigen). Kolom tujuan lama adalah `item_card`.

| Field | Tipe | Wajib | Sumber di Aigen | Catatan |
|---|---|---|---|---|
| `item_code` | string(15) | ✔ | `rfq_library.item_code` | Unik dalam satu PR |
| `text` | text | ✔ | `rfq_library.item_text` | Deskripsi item |
| `qty` | integer | ✔ | `rfq_library.quantity` | |
| `unit` | string(10) | | `rfq_library.uom` | |
| `pr_item_value` | integer | ✔ | `rfq_library.item_value` | |
| `price_item_idr` | bigint | | `rfq_library.item_value` | Saat ini bernilai sama dengan `pr_item_value` |
| `pr_release_date` | date | ✔ | `rfq_library.pr_release_date` | |
| `pr_material_group` | string(255) | | material group item | |
| `pr_material_group_number` | string(45) | | material group item | |
| `acc_assign` | string(10) | | konstanta `""` | |
| `is_repeatorder` | boolean | | konstanta `false` | |
| `text_repeatorder` | text | | konstanta `0` | |
| `partial_status` | string(25) | | konstanta `"NEW"` | Dapat dihilangkan bila ditetapkan iSourcing |
| `aigen_item_id` | integer | | `rfq_library.id` | **Usulan baru** — memudahkan penelusuran dua arah. Tidak ada padanannya di skema lama |

### 3.5 Idempotensi (wajib)

Cron Aigen berjalan berulang dan **akan mengirim ulang** permintaan yang sama ketika sebelumnya
gagal atau timeout. API harus aman terhadap pengulangan.

| Kebutuhan | Rincian |
|---|---|
| I-1 | Kunci idempotensi bersifat deterministik dari identitas bisnis: `card_title` + daftar `item_code` terurut. Dikirim pada field `idempotency_key` (dan/atau header `Idempotency-Key`) |
| I-2 | Permintaan ulang atas PR yang sudah ada **tidak boleh** membuat kartu atau item duplikat |
| I-3 | Permintaan atas PR yang sudah ada namun membawa item baru **harus menambahkan item yang belum ada saja** (semantik *upsert*). Ini menggantikan "Cabang B" pada implementasi database saat ini |
| I-4 | Respons untuk permintaan berulang harus tetap `2xx` dengan penanda bahwa data sudah ada, bukan error konflik. Bila memakai `409`, sertakan kode error yang dapat dibedakan dari kegagalan lain |
| I-5 | Timeout di sisi klien tidak boleh meninggalkan data separuh jadi (konsekuensi langsung dari K-2) |

### 3.6 Respons sukses

```json
{
  "success": true,
  "message": "PR B1200027667 imported",
  "data": {
    "card_title": "B1200027667",
    "card_id": 12345,
    "created": true,
    "items": [
      { "item_code": "00010", "item_card_id": 67890, "created": true },
      { "item_code": "00020", "item_card_id": 67891, "created": false }
    ]
  }
}
```

Kebutuhan minimum yang harus ada pada respons sukses: `card_title`, penanda apakah kartu baru
dibuat atau sudah ada, dan status per item. Aigen memakainya untuk logging dan penelusuran.

### 3.7 Respons gagal dan pemetaan kode error

API harus mengembalikan **kode error yang dapat dibaca mesin** (bukan hanya pesan bebas), karena
Aigen memetakannya ke kode kanonik yang sudah dipakai handler cron dan route HTTP.

```json
{
  "success": false,
  "error_code": "HEADER_INCOMPLETE",
  "message": "…",
  "missing": ["company", "currency"]
}
```

| Kondisi | HTTP | Usulan `error_code` | Dipetakan Aigen ke | Di-retry? |
|---|---|---|---|---|
| Header tidak lengkap / gagal validasi | 400 / 422 | `HEADER_INCOMPLETE` | `ISOURCING_SOURCE_HEADER_INCOMPLETE` | Tidak |
| Payload tidak sah (skema salah) | 400 | `INVALID_PAYLOAD` | `ISOURCING_TRANSFER_FAILED` | Tidak |
| PR/item sudah ada | 200 / 409 | `ALREADY_EXISTS` | **sukses idempoten** | Tidak |
| Kredensial salah / tidak berhak | 401 / 403 | `UNAUTHORIZED` | `ISOURCING_TRANSFER_FAILED` | Tidak — perlu alert |
| Rate limit terlampaui | 429 | `RATE_LIMITED` | `ISOURCING_TRANSFER_FAILED` | **Ya** (hormati `Retry-After`) |
| Kesalahan internal iSourcing | 5xx | `INTERNAL_ERROR` | `ISOURCING_TRANSFER_FAILED` | **Ya** |
| Timeout / kesalahan jaringan | — | — | `ISOURCING_TRANSFER_FAILED` | **Ya** |

Aturan penting: **sukses parsial tidak boleh terjadi.** Bila sebagian item gagal, seluruh
permintaan harus gagal dan tidak menyisakan data (K-2).

---

## 4. E-2 — Cek Keberadaan PR / Item *(direkomendasikan, dapat ditiadakan)*

| Aspek | Kebutuhan |
|---|---|
| Method | `GET` |
| Path | Belum ditentukan; disimpan di `.env` bila dipakai |
| Input | `card_title` (dan opsional daftar `item_code`) |
| Output | Keberadaan kartu, status kartu, dan daftar `item_code` yang sudah ada |
| Kegunaan | Verifikasi idempotensi, diagnosa selisih data, dan pemeriksaan pasca-cutover |

**Tidak diperlukan** bila E-1 sudah memenuhi I-2 dan I-3. Namun tanpa endpoint ini, Aigen tidak
punya cara membuktikan kesetaraan data setelah cutover selain membaca database secara langsung.

---

## 5. E-3 — Health Check *(opsional)*

`GET` sederhana yang mengembalikan `200` bila layanan hidup dan kredensial Basic Auth valid.
Berguna untuk memvalidasi konfigurasi `.env` saat boot tanpa harus mengirim data nyata.

---

## 6. Yang TIDAK Lagi Dikirim oleh Aigen

Konsekuensi dari K-3 dan K-4. Semua hal berikut sebelumnya ditulis Aigen langsung ke `task_board`
dan kini menjadi tanggung jawab internal iSourcing.

| Tabel / proses lama | Status pada mode API | Dasar |
|---|---|---|
| `board_card` — kolom penempatan papan: `board_id`, `user_id`, `list_id`, `card_color`, `split_from`, `split_for`, `split_no`, `is_updated` | **Tidak dikirim** | Hasil auto-assign — K-3 |
| `counter_split_pr_items` | **Tidak dikirim** | Turunan dari split kartu CL — K-3 |
| `item_card` — kolom `assigned_to_cl`, `send_email_to`, `is_updated` | **Tidak dikirim** | Hasil auto-assign — K-3 |
| Pembacaan master `category_group`, `matrix_auto_assign`, `board_list` | **Tidak dilakukan** | Auto-assign pindah ke iSourcing — K-3 |
| `exports_data` | **Diabaikan** | Tidak ada di isourcing-vanilla — K-4 |
| `milestone_config` (`SUM(appointment)` untuk `sla_target`) | **Tidak dibaca** | Turunan `exports_data` — K-4 |
| `history_log_assign` (`Auto Assign` / `New Item`) | **Tidak dikirim** | Turunan auto-assign — K-3 |
| `pr_logs` | **Perlu dikonfirmasi** — lihat §9 | Field sumbernya (`server`, `pr_start_date`) sudah ada di payload E-1 |

**Manfaat langsung:** setelah K-3 dan K-4 berlaku, `aigen-backend` tidak lagi memerlukan akses
apa pun ke database `task_board` — baik tulis maupun baca. Hak tulis akun database milik
`aigen-backend` dapat dicabut sepenuhnya. Perlu dicatat bahwa `aigen-import-pr` **masih membaca**
`task_board` (`item_card`, `category_group`, `users`), sehingga hak bacanya harus dipertahankan.

---

## 7. Kebutuhan Non-Fungsional

| ID | Kebutuhan | Nilai usulan |
|---|---|---|
| NF-1 | Timeout per permintaan | 10 detik (mengikuti pola integrasi SAP yang ada) |
| NF-2 | Retry oleh klien | Maksimal 2 kali, hanya untuk timeout / jaringan / 5xx / 429, dengan backoff |
| NF-3 | Rate limit | Perlu dinyatakan tim iSourcing. Satu run cron dapat memproses puluhan PR secara berurutan |
| NF-4 | Ukuran payload maksimum | Perlu dinyatakan. Satu PR dapat memiliki puluhan item |
| NF-5 | Versioning | Path memuat versi (mis. `/v1/…`) agar perubahan kontrak tidak memutus klien |
| NF-6 | Lingkungan | Tersedia base URL terpisah untuk non-produksi agar dapat diuji sebelum cutover |
| NF-7 | Kerahasiaan | Kredensial tidak pernah muncul di log, pesan error, maupun payload Sentry di sisi Aigen |

---

## 8. Konfigurasi `.env` yang Disiapkan di Sisi Aigen

| Variabel | Contoh | Keterangan |
|---|---|---|
| `ISOURCING_TRANSFER_DRIVER` | `database` \| `api` | Saklar utama. Default `database`. Nilai tidak dikenal → gagal saat boot |
| `ISOURCING_API_BASE_URL` | `https://isourcing.example.com` | Base URL API publik |
| `ISOURCING_API_TRANSFER_PATH` | `/api/v1/pr-transfer` | Path E-1, dipisah dari base URL agar mudah diganti |
| `ISOURCING_API_USERNAME` | — | Basic Auth (K-1) |
| `ISOURCING_API_PASSWORD` | — | Basic Auth (K-1) |
| `ISOURCING_API_TIMEOUT_MS` | `10000` | NF-1 |
| `ISOURCING_API_MAX_RETRY` | `2` | NF-2 |

Catatan: integrasi SAP yang sudah ada menyimpan kredensial dalam bentuk base64 siap pakai
(`SAP_TOKEN_AUTH_BC`). Untuk iSourcing diusulkan menyimpan **username dan password terpisah** lalu
meng-encode saat runtime, karena lebih jelas saat rotasi kredensial dan menghindari kesalahan
double-encoding. Bila tim lebih memilih konsistensi dengan pola SAP, satu variabel token base64
juga dapat dipakai.

Nilai `ISOURCING_TRANSFER_DRIVER` harus **identik** antara environment aplikasi HTTP dan
environment cron — keduanya adalah proses terpisah dengan `.env` terpisah.

---

## 9. Pertanyaan Terbuka untuk Tim iSourcing

| No | Pertanyaan |
|---|---|
| Q-1 | Berapa endpoint yang akan disediakan — cukup E-1 dengan semantik *upsert*, atau E-1 dan E-2 terpisah? |
| Q-2 | Apakah `idempotency_key` diterima dari klien, atau iSourcing menurunkan sendiri kunci dedup dari `card_title` + `item_code`? |
| Q-3 | Apa bentuk respons ketika PR sudah ada — `200` dengan penanda, atau `409`? |
| Q-4 | Apakah `pr_logs` menjadi tanggung jawab internal iSourcing, atau Aigen tetap perlu mengirim data lifecycle awal? |
| Q-5 | Bagaimana perilaku ketika `pr_material_group_number` tidak memiliki pemetaan kategori? Pada implementasi database saat ini kartu jatuh ke Admin (`list_id = 1`) disertai peringatan, bukan error |
| Q-6 | Apakah `card_title` beserta aturan prefix (`B`/`G`/`K`) tetap dipakai di isourcing-vanilla, atau iSourcing yang menyusunnya dari `pr_number` + `server`? |
| Q-7 | Berapa rate limit dan ukuran payload maksimum (NF-3, NF-4)? |
| Q-8 | Apakah tersedia lingkungan non-produksi untuk pengujian sebelum cutover (NF-6)? |
| Q-9 | Apakah field usulan `aigen_item_id` dapat disimpan di sisi iSourcing untuk penelusuran dua arah? |

---

## 10. Catatan Verifikasi

- Seluruh daftar field pada §3.3 dan §3.4 diturunkan dari kode aktual `aigen-backend` pada branch
  `develop-dot` commit `4d30f82d`: `buildHeaderMetadata()`, `insertBoardCard()`, `insertItemCard()`,
  serta definisi model di `src/models/isourcing/`.
- Bagian yang menyangkut perilaku isourcing-vanilla (§4, §5, §7, §9) **belum dapat diverifikasi**
  dari workspace ini dan berstatus usulan.
- Dokumen ini tidak mengubah kode apa pun.
