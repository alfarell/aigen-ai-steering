-- =============================================================================
-- Hapus data RFQ0002342 (PR 1100014042, item 6) dari schema `aigen`
-- =============================================================================
-- Cakupan HANYA RFQ0002342. RFQ lain dari PR yang sama (RFQ0002282, RFQ0002283)
-- beserta QCF/PO-nya TIDAK disentuh.
--
-- Cakupan (diverifikasi di DB lokal 2026-10-08):
--   rfq_library     1  (id 6655, vendor 101962, batch 2, milestone 14)
--   images          1  | documents 2 | log_quotation 2 | log_sla 6
--   rfq_token_email 3  (8910, 8961, 8973 -- 8973 masih aktif)
--   qcf_library 0 | qcf_token_email 0 | evidences 0 | failed_emails 0 | pr_library 0
--   log_activity    5  | emails 4   (match teks 'RFQ0002342'; lihat bagian OPSIONAL)
--
-- Cara kerja:
--   1. Backup baris target ke tabel bak_rfq0002342_* (CREATE TABLE ... LIKE).
--   2. DELETE hanya baris yang ada di backup (join by primary key), di dalam transaksi.
--   3. Verifikasi = 0, lalu COMMIT manual (atau ROLLBACK jika ada yang tidak sesuai).
--   Rollback setelah COMMIT: jalankan rfq0002342_rollback.sql.
--
-- Catatan: CREATE TABLE adalah DDL (implicit commit), karena itu backup dijalankan
-- SEBELUM START TRANSACTION. Jangan drop tabel backup sampai data dipastikan tidak dibutuhkan.
-- File fisik (documents.file_path, images.file_path) TIDAK ikut terhapus.
-- =============================================================================

USE aigen;

-- -----------------------------------------------------------------------------
-- 0. PRE-CHECK
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS existing_backup_tables   -- harus 0
FROM information_schema.tables
WHERE table_schema = 'aigen' AND table_name LIKE 'bak\_rfq0002342\_%';

SELECT id, rfq_number, pr_number, item_code, vendor_code, vendor_batch, status_milestone
FROM rfq_library WHERE rfq_number = 'RFQ0002342';           -- ekspektasi 1 baris (id 6655)

-- Item RFQ ini tidak boleh punya baris QCF (ekspektasi 0). Jika > 0, STOP dan review:
-- QCF bisa berisi item lain / sudah menjadi PO.
SELECT COUNT(*) AS qcf_rows
FROM qcf_library
WHERE rfq_number = 'RFQ0002342'
   OR rfq_item_id IN (SELECT id FROM rfq_library WHERE rfq_number = 'RFQ0002342');

-- -----------------------------------------------------------------------------
-- 1. BACKUP
-- -----------------------------------------------------------------------------
-- 1a. Induk: rfq_library (sumber id untuk tabel lain)
CREATE TABLE bak_rfq0002342_rfq_library LIKE rfq_library;
INSERT INTO bak_rfq0002342_rfq_library
SELECT * FROM rfq_library WHERE rfq_number = 'RFQ0002342';

-- 1b. qcf_library (ekspektasi 0; tetap dibackup untuk keamanan FK)
CREATE TABLE bak_rfq0002342_qcf_library LIKE qcf_library;
INSERT INTO bak_rfq0002342_qcf_library
SELECT * FROM qcf_library
WHERE rfq_number = 'RFQ0002342'
   OR rfq_item_id IN (SELECT id FROM bak_rfq0002342_rfq_library);

-- 1c. images / evidences (FK ke rfq_library, ON DELETE CASCADE)
CREATE TABLE bak_rfq0002342_images LIKE images;
INSERT INTO bak_rfq0002342_images
SELECT * FROM images WHERE rfq_item_id IN (SELECT id FROM bak_rfq0002342_rfq_library);

CREATE TABLE bak_rfq0002342_evidences LIKE evidences;
INSERT INTO bak_rfq0002342_evidences
SELECT * FROM evidences WHERE rfq_item_id IN (SELECT id FROM bak_rfq0002342_rfq_library);

-- 1d. documents / failed_emails
CREATE TABLE bak_rfq0002342_documents LIKE documents;
INSERT INTO bak_rfq0002342_documents
SELECT * FROM documents WHERE rfq_number = 'RFQ0002342';

CREATE TABLE bak_rfq0002342_failed_emails LIKE failed_emails;
INSERT INTO bak_rfq0002342_failed_emails
SELECT * FROM failed_emails WHERE rfq_number = 'RFQ0002342';

-- 1e. log_quotation / log_sla (pr_number TIDAK dipakai sebagai filter: baris PR
--     yang sama milik RFQ lain harus tetap ada)
CREATE TABLE bak_rfq0002342_log_quotation LIKE log_quotation;
INSERT INTO bak_rfq0002342_log_quotation
SELECT * FROM log_quotation
WHERE rfq_number = 'RFQ0002342'
   OR item_id IN (SELECT id FROM bak_rfq0002342_rfq_library);

CREATE TABLE bak_rfq0002342_log_sla LIKE log_sla;
INSERT INTO bak_rfq0002342_log_sla
SELECT * FROM log_sla
WHERE rfq_number = 'RFQ0002342'
   OR item_id IN (SELECT id FROM bak_rfq0002342_rfq_library);

-- 1f. token email
CREATE TABLE bak_rfq0002342_rfq_token_email LIKE rfq_token_email;
INSERT INTO bak_rfq0002342_rfq_token_email
SELECT * FROM rfq_token_email WHERE rfq_number = 'RFQ0002342';

CREATE TABLE bak_rfq0002342_qcf_token_email LIKE qcf_token_email;
INSERT INTO bak_rfq0002342_qcf_token_email
SELECT * FROM qcf_token_email WHERE rfq_number = 'RFQ0002342';

-- 1g. pr_library (saat ini kosong)
CREATE TABLE bak_rfq0002342_pr_library LIKE pr_library;
INSERT INTO bak_rfq0002342_pr_library
SELECT * FROM pr_library WHERE rfq_number = 'RFQ0002342';

-- 1h. [OPSIONAL] log_activity & emails (audit log / arsip email, match teks)
CREATE TABLE bak_rfq0002342_log_activity LIKE log_activity;
INSERT INTO bak_rfq0002342_log_activity
SELECT * FROM log_activity WHERE action_description LIKE '%RFQ0002342%';

CREATE TABLE bak_rfq0002342_emails LIKE emails;
INSERT INTO bak_rfq0002342_emails
SELECT * FROM emails WHERE CONCAT_WS(' ', subject, body, html) LIKE '%RFQ0002342%';

-- Ringkasan backup (ekspektasi lokal: 1,0,1,0,2,0,2,6,3,0,0,5,4)
SELECT 'rfq_library' t, COUNT(*) n FROM bak_rfq0002342_rfq_library
UNION ALL SELECT 'qcf_library',     COUNT(*) FROM bak_rfq0002342_qcf_library
UNION ALL SELECT 'images',          COUNT(*) FROM bak_rfq0002342_images
UNION ALL SELECT 'evidences',       COUNT(*) FROM bak_rfq0002342_evidences
UNION ALL SELECT 'documents',       COUNT(*) FROM bak_rfq0002342_documents
UNION ALL SELECT 'failed_emails',   COUNT(*) FROM bak_rfq0002342_failed_emails
UNION ALL SELECT 'log_quotation',   COUNT(*) FROM bak_rfq0002342_log_quotation
UNION ALL SELECT 'log_sla',         COUNT(*) FROM bak_rfq0002342_log_sla
UNION ALL SELECT 'rfq_token_email', COUNT(*) FROM bak_rfq0002342_rfq_token_email
UNION ALL SELECT 'qcf_token_email', COUNT(*) FROM bak_rfq0002342_qcf_token_email
UNION ALL SELECT 'pr_library',      COUNT(*) FROM bak_rfq0002342_pr_library
UNION ALL SELECT 'log_activity',    COUNT(*) FROM bak_rfq0002342_log_activity
UNION ALL SELECT 'emails',          COUNT(*) FROM bak_rfq0002342_emails;

-- Review isi backup log_activity & emails sebelum lanjut
SELECT id, action_type, LEFT(action_description, 120) FROM bak_rfq0002342_log_activity;
SELECT id, LEFT(subject, 100) FROM bak_rfq0002342_emails;

-- -----------------------------------------------------------------------------
-- 2. DELETE (dalam transaksi; hanya baris yang ada di backup, by primary key)
-- -----------------------------------------------------------------------------
START TRANSACTION;

-- Anak dulu (qcf_library FK ke rfq_library = NO ACTION)
DELETE t FROM qcf_library     t JOIN bak_rfq0002342_qcf_library     b ON b.id = t.id;
DELETE t FROM images          t JOIN bak_rfq0002342_images          b ON b.id = t.id;
DELETE t FROM evidences       t JOIN bak_rfq0002342_evidences       b ON b.id = t.id;
DELETE t FROM documents       t JOIN bak_rfq0002342_documents       b ON b.id = t.id;
DELETE t FROM failed_emails   t JOIN bak_rfq0002342_failed_emails   b ON b.id = t.id;
DELETE t FROM log_quotation   t JOIN bak_rfq0002342_log_quotation   b ON b.id = t.id;
DELETE t FROM log_sla         t JOIN bak_rfq0002342_log_sla         b ON b.id = t.id;
DELETE t FROM rfq_token_email t JOIN bak_rfq0002342_rfq_token_email b ON b.id = t.id;
DELETE t FROM qcf_token_email t JOIN bak_rfq0002342_qcf_token_email b ON b.id = t.id;
DELETE t FROM pr_library      t JOIN bak_rfq0002342_pr_library      b ON b.id = t.id;

-- Induk
DELETE t FROM rfq_library     t JOIN bak_rfq0002342_rfq_library     b ON b.id = t.id;

-- [OPSIONAL] audit log & arsip email. Comment-out 2 baris ini jika ingin tetap disimpan.
DELETE t FROM log_activity    t JOIN bak_rfq0002342_log_activity    b ON b.id = t.id;
DELETE t FROM emails          t JOIN bak_rfq0002342_emails          b ON b.id = t.id;

-- -----------------------------------------------------------------------------
-- 3. VERIFIKASI
-- -----------------------------------------------------------------------------
-- 3a. Data RFQ0002342 harus 0 semua
SELECT 'rfq_library' t, COUNT(*) n FROM rfq_library WHERE rfq_number = 'RFQ0002342' OR id = 6655
UNION ALL SELECT 'qcf_library',     COUNT(*) FROM qcf_library WHERE rfq_number = 'RFQ0002342' OR rfq_item_id = 6655
UNION ALL SELECT 'images',          COUNT(*) FROM images WHERE rfq_item_id = 6655
UNION ALL SELECT 'evidences',       COUNT(*) FROM evidences WHERE rfq_item_id = 6655
UNION ALL SELECT 'documents',       COUNT(*) FROM documents WHERE rfq_number = 'RFQ0002342'
UNION ALL SELECT 'failed_emails',   COUNT(*) FROM failed_emails WHERE rfq_number = 'RFQ0002342'
UNION ALL SELECT 'log_quotation',   COUNT(*) FROM log_quotation WHERE rfq_number = 'RFQ0002342' OR item_id = 6655
UNION ALL SELECT 'log_sla',         COUNT(*) FROM log_sla WHERE rfq_number = 'RFQ0002342' OR item_id = 6655
UNION ALL SELECT 'rfq_token_email', COUNT(*) FROM rfq_token_email WHERE rfq_number = 'RFQ0002342' OR JSON_CONTAINS(rfq_item_ids, '6655')
UNION ALL SELECT 'qcf_token_email', COUNT(*) FROM qcf_token_email WHERE rfq_number = 'RFQ0002342'
UNION ALL SELECT 'pr_library',      COUNT(*) FROM pr_library WHERE rfq_number = 'RFQ0002342'
UNION ALL SELECT 'log_activity',    COUNT(*) FROM log_activity WHERE action_description LIKE '%RFQ0002342%'
UNION ALL SELECT 'emails',          COUNT(*) FROM emails WHERE CONCAT_WS(' ', subject, body, html) LIKE '%RFQ0002342%'
UNION ALL SELECT 'v_dashboard_rfq_admin_list', COUNT(*) FROM v_dashboard_rfq_admin_list WHERE rfq_number = 'RFQ0002342';

-- 3b. RFQ lain dari PR yang sama harus TETAP ADA (ekspektasi lokal: rfq_library 3, qcf_library 3)
SELECT 'rfq_library (RFQ0002282/83)' t, COUNT(*) n FROM rfq_library WHERE rfq_number IN ('RFQ0002282','RFQ0002283')
UNION ALL SELECT 'qcf_library (RFQ0002282/83)', COUNT(*) FROM qcf_library WHERE rfq_number IN ('RFQ0002282','RFQ0002283');

-- Jika 3a semua 0 dan 3b sesuai:
-- COMMIT;
-- Jika ada yang tidak sesuai:
-- ROLLBACK;
