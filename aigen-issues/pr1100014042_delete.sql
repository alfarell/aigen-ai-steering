-- =============================================================================
-- Hapus data PR 1100014042 dari schema `aigen` (salah import)
-- =============================================================================
-- Cakupan (diverifikasi di DB lokal 2026-10-08):
--   rfq_library     4  (id 6469, 6470, 6471, 6655; RFQ0002282, RFQ0002283, RFQ0002342)
--   qcf_library     3  (QCF0000922, QCF0000929)  -> PO SAP SUDAH DIBUAT: 4100067346, 4100067371
--   images          4  | evidences 0 | documents 4 | failed_emails 0 | pr_library 0
--   log_quotation   8  | log_sla 24
--   rfq_token_email 7  (token 8973 masih aktif) | qcf_token_email 2 (558, 565 masih aktif)
--   log_activity   13  | emails 15   (match teks; lihat BAGIAN 2 opsional)
--
-- Cara kerja:
--   1. Backup baris target ke tabel bak_pr1100014042_* (CREATE TABLE ... LIKE, struktur + index sama).
--   2. DELETE hanya baris yang ada di backup (join by primary key), di dalam transaksi.
--   3. Verifikasi = 0, lalu COMMIT manual (atau ROLLBACK jika ada yang tidak sesuai).
--   Rollback setelah COMMIT: jalankan pr1100014042_rollback.sql.
--
-- Catatan: CREATE TABLE adalah DDL (implicit commit), karena itu backup dijalankan
-- SEBELUM START TRANSACTION. Jangan drop tabel backup sampai data dipastikan tidak dibutuhkan.
-- File fisik (documents.file_path, images.file_path) TIDAK ikut terhapus.
-- =============================================================================

USE aigen;

-- -----------------------------------------------------------------------------
-- 0. PRE-CHECK  (pastikan tidak ada tabel backup lama & jumlah sesuai ekspektasi)
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS existing_backup_tables   -- harus 0
FROM information_schema.tables
WHERE table_schema = 'aigen' AND table_name LIKE 'bak\_pr1100014042\_%';

SELECT id, rfq_number, pr_number, item_code, vendor_code, vendor_batch, status_milestone
FROM rfq_library WHERE pr_number = '1100014042';            -- ekspektasi 4 baris

-- RFQ number milik PR ini tidak boleh dipakai PR lain (ekspektasi 0)
SELECT COUNT(*) AS rfq_shared_with_other_pr
FROM rfq_library
WHERE rfq_number IN (SELECT rfq_number FROM rfq_library WHERE pr_number = '1100014042')
  AND pr_number <> '1100014042';

-- QCF number milik PR ini tidak boleh berisi item PR lain (ekspektasi 0)
SELECT COUNT(*) AS qcf_shared_with_other_pr
FROM qcf_library
WHERE qcf_number IN (SELECT qcf_number FROM qcf_library WHERE pr_number = '1100014042')
  AND pr_number <> '1100014042';

-- -----------------------------------------------------------------------------
-- 1. BACKUP
-- -----------------------------------------------------------------------------
-- 1a. Induk: rfq_library (dipakai sebagai sumber id & rfq_number untuk tabel lain)
CREATE TABLE bak_pr1100014042_rfq_library LIKE rfq_library;
INSERT INTO bak_pr1100014042_rfq_library
SELECT * FROM rfq_library WHERE pr_number = '1100014042';

-- 1b. qcf_library
CREATE TABLE bak_pr1100014042_qcf_library LIKE qcf_library;
INSERT INTO bak_pr1100014042_qcf_library
SELECT * FROM qcf_library
WHERE pr_number = '1100014042'
   OR rfq_item_id IN (SELECT id FROM bak_pr1100014042_rfq_library)
   OR rfq_number  IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library);

-- 1c. images / evidences (FK ke rfq_library, ON DELETE CASCADE)
CREATE TABLE bak_pr1100014042_images LIKE images;
INSERT INTO bak_pr1100014042_images
SELECT * FROM images WHERE rfq_item_id IN (SELECT id FROM bak_pr1100014042_rfq_library);

CREATE TABLE bak_pr1100014042_evidences LIKE evidences;
INSERT INTO bak_pr1100014042_evidences
SELECT * FROM evidences WHERE rfq_item_id IN (SELECT id FROM bak_pr1100014042_rfq_library);

-- 1d. documents / failed_emails
CREATE TABLE bak_pr1100014042_documents LIKE documents;
INSERT INTO bak_pr1100014042_documents
SELECT * FROM documents WHERE rfq_number IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library);

CREATE TABLE bak_pr1100014042_failed_emails LIKE failed_emails;
INSERT INTO bak_pr1100014042_failed_emails
SELECT * FROM failed_emails WHERE rfq_number IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library);

-- 1e. log_quotation / log_sla
CREATE TABLE bak_pr1100014042_log_quotation LIKE log_quotation;
INSERT INTO bak_pr1100014042_log_quotation
SELECT * FROM log_quotation
WHERE rfq_number IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library)
   OR item_id    IN (SELECT id FROM bak_pr1100014042_rfq_library);

CREATE TABLE bak_pr1100014042_log_sla LIKE log_sla;
INSERT INTO bak_pr1100014042_log_sla
SELECT * FROM log_sla
WHERE pr_number = '1100014042'
   OR rfq_number IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library)
   OR item_id    IN (SELECT id FROM bak_pr1100014042_rfq_library);

-- 1f. token email
CREATE TABLE bak_pr1100014042_rfq_token_email LIKE rfq_token_email;
INSERT INTO bak_pr1100014042_rfq_token_email
SELECT * FROM rfq_token_email
WHERE pr_number = '1100014042'
   OR rfq_number IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library);

CREATE TABLE bak_pr1100014042_qcf_token_email LIKE qcf_token_email;
INSERT INTO bak_pr1100014042_qcf_token_email
SELECT * FROM qcf_token_email
WHERE pr_number = '1100014042'
   OR rfq_number IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library)
   OR qcf_number IN (SELECT qcf_number FROM bak_pr1100014042_qcf_library WHERE qcf_number IS NOT NULL);

-- 1g. pr_library (saat ini kosong, tetap dibackup untuk konsistensi)
CREATE TABLE bak_pr1100014042_pr_library LIKE pr_library;
INSERT INTO bak_pr1100014042_pr_library
SELECT * FROM pr_library
WHERE pr_number = '1100014042'
   OR rfq_number IN (SELECT rfq_number FROM bak_pr1100014042_rfq_library);

-- 1h. [OPSIONAL - BAGIAN 2] log_activity & emails (audit log / arsip email, match teks)
CREATE TABLE bak_pr1100014042_log_activity LIKE log_activity;
INSERT INTO bak_pr1100014042_log_activity
SELECT * FROM log_activity
WHERE action_description REGEXP '1100014042|RFQ0002282|RFQ0002283|RFQ0002342|QCF0000922|QCF0000929';

CREATE TABLE bak_pr1100014042_emails LIKE emails;
INSERT INTO bak_pr1100014042_emails
SELECT * FROM emails
WHERE CONCAT_WS(' ', subject, body, html)
      REGEXP '1100014042|RFQ0002282|RFQ0002283|RFQ0002342|QCF0000922|QCF0000929';

-- Ringkasan backup (ekspektasi lokal: 4,3,4,0,4,0,8,24,7,2,0,13,15)
SELECT 'rfq_library' t, COUNT(*) n FROM bak_pr1100014042_rfq_library
UNION ALL SELECT 'qcf_library',     COUNT(*) FROM bak_pr1100014042_qcf_library
UNION ALL SELECT 'images',          COUNT(*) FROM bak_pr1100014042_images
UNION ALL SELECT 'evidences',       COUNT(*) FROM bak_pr1100014042_evidences
UNION ALL SELECT 'documents',       COUNT(*) FROM bak_pr1100014042_documents
UNION ALL SELECT 'failed_emails',   COUNT(*) FROM bak_pr1100014042_failed_emails
UNION ALL SELECT 'log_quotation',   COUNT(*) FROM bak_pr1100014042_log_quotation
UNION ALL SELECT 'log_sla',         COUNT(*) FROM bak_pr1100014042_log_sla
UNION ALL SELECT 'rfq_token_email', COUNT(*) FROM bak_pr1100014042_rfq_token_email
UNION ALL SELECT 'qcf_token_email', COUNT(*) FROM bak_pr1100014042_qcf_token_email
UNION ALL SELECT 'pr_library',      COUNT(*) FROM bak_pr1100014042_pr_library
UNION ALL SELECT 'log_activity',    COUNT(*) FROM bak_pr1100014042_log_activity
UNION ALL SELECT 'emails',          COUNT(*) FROM bak_pr1100014042_emails;

-- Review isi backup log_activity & emails sebelum lanjut (pastikan tidak ada baris PR lain)
SELECT id, action_type, LEFT(action_description, 120) FROM bak_pr1100014042_log_activity;
SELECT id, LEFT(subject, 100) FROM bak_pr1100014042_emails;

-- -----------------------------------------------------------------------------
-- 2. DELETE (dalam transaksi; hanya baris yang ada di backup, by primary key)
-- -----------------------------------------------------------------------------
START TRANSACTION;

-- Anak dulu (qcf_library FK ke rfq_library = NO ACTION)
DELETE t FROM qcf_library     t JOIN bak_pr1100014042_qcf_library     b ON b.id = t.id;
DELETE t FROM images          t JOIN bak_pr1100014042_images          b ON b.id = t.id;
DELETE t FROM evidences       t JOIN bak_pr1100014042_evidences       b ON b.id = t.id;
DELETE t FROM documents       t JOIN bak_pr1100014042_documents       b ON b.id = t.id;
DELETE t FROM failed_emails   t JOIN bak_pr1100014042_failed_emails   b ON b.id = t.id;
DELETE t FROM log_quotation   t JOIN bak_pr1100014042_log_quotation   b ON b.id = t.id;
DELETE t FROM log_sla         t JOIN bak_pr1100014042_log_sla         b ON b.id = t.id;
DELETE t FROM rfq_token_email t JOIN bak_pr1100014042_rfq_token_email b ON b.id = t.id;
DELETE t FROM qcf_token_email t JOIN bak_pr1100014042_qcf_token_email b ON b.id = t.id;
DELETE t FROM pr_library      t JOIN bak_pr1100014042_pr_library      b ON b.id = t.id;

-- Induk
DELETE t FROM rfq_library     t JOIN bak_pr1100014042_rfq_library     b ON b.id = t.id;

-- [OPSIONAL - BAGIAN 2] audit log & arsip email. Comment-out 2 baris ini jika ingin tetap disimpan.
DELETE t FROM log_activity    t JOIN bak_pr1100014042_log_activity    b ON b.id = t.id;
DELETE t FROM emails          t JOIN bak_pr1100014042_emails          b ON b.id = t.id;

-- -----------------------------------------------------------------------------
-- 3. VERIFIKASI (semua harus 0) -> lalu COMMIT; jika tidak, ROLLBACK;
-- -----------------------------------------------------------------------------
SELECT 'rfq_library' t, COUNT(*) n FROM rfq_library WHERE pr_number = '1100014042' OR rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342')
UNION ALL SELECT 'qcf_library',     COUNT(*) FROM qcf_library WHERE pr_number = '1100014042' OR rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342') OR qcf_number IN ('QCF0000922','QCF0000929') OR rfq_item_id IN (6469,6470,6471,6655)
UNION ALL SELECT 'images',          COUNT(*) FROM images WHERE rfq_item_id IN (6469,6470,6471,6655)
UNION ALL SELECT 'evidences',       COUNT(*) FROM evidences WHERE rfq_item_id IN (6469,6470,6471,6655)
UNION ALL SELECT 'documents',       COUNT(*) FROM documents WHERE rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342')
UNION ALL SELECT 'failed_emails',   COUNT(*) FROM failed_emails WHERE rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342')
UNION ALL SELECT 'log_quotation',   COUNT(*) FROM log_quotation WHERE rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342') OR item_id IN (6469,6470,6471,6655)
UNION ALL SELECT 'log_sla',         COUNT(*) FROM log_sla WHERE pr_number = '1100014042' OR rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342') OR item_id IN (6469,6470,6471,6655)
UNION ALL SELECT 'rfq_token_email', COUNT(*) FROM rfq_token_email WHERE pr_number = '1100014042' OR rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342')
UNION ALL SELECT 'qcf_token_email', COUNT(*) FROM qcf_token_email WHERE pr_number = '1100014042' OR rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342') OR qcf_number IN ('QCF0000922','QCF0000929')
UNION ALL SELECT 'pr_library',      COUNT(*) FROM pr_library WHERE pr_number = '1100014042' OR rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342')
UNION ALL SELECT 'log_activity',    COUNT(*) FROM log_activity WHERE action_description REGEXP '1100014042|RFQ0002282|RFQ0002283|RFQ0002342|QCF0000922|QCF0000929'
UNION ALL SELECT 'emails',          COUNT(*) FROM emails WHERE CONCAT_WS(' ', subject, body, html) REGEXP '1100014042|RFQ0002282|RFQ0002283|RFQ0002342|QCF0000922|QCF0000929'
UNION ALL SELECT 'v_dashboard_rfq_admin_list', COUNT(*) FROM v_dashboard_rfq_admin_list WHERE rfq_number IN ('RFQ0002282','RFQ0002283','RFQ0002342');

-- Jika semua 0:
-- COMMIT;
-- Jika ada yang tidak sesuai:
-- ROLLBACK;
