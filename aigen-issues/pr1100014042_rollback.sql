-- =============================================================================
-- ROLLBACK penghapusan PR 1100014042 (schema `aigen`)
-- =============================================================================
-- Prasyarat: tabel bak_pr1100014042_* hasil pr1100014042_delete.sql masih ada.
-- Data dikembalikan dengan id (primary key) asli. Urutan: induk dulu, lalu anak.
-- INSERT IGNORE tidak dipakai agar konflik id (jika ada) terlihat sebagai error.
-- =============================================================================

USE aigen;

-- -----------------------------------------------------------------------------
-- 0. PRE-CHECK
-- -----------------------------------------------------------------------------
-- Tabel backup harus lengkap (ekspektasi 13)
SELECT COUNT(*) AS backup_tables
FROM information_schema.tables
WHERE table_schema = 'aigen' AND table_name LIKE 'bak\_pr1100014042\_%';

-- Tidak boleh ada id yang sudah terpakai lagi di tabel asli (semua harus 0)
SELECT 'rfq_library' t, COUNT(*) n FROM rfq_library t JOIN bak_pr1100014042_rfq_library b ON b.id = t.id
UNION ALL SELECT 'qcf_library',     COUNT(*) FROM qcf_library     t JOIN bak_pr1100014042_qcf_library     b ON b.id = t.id
UNION ALL SELECT 'images',          COUNT(*) FROM images          t JOIN bak_pr1100014042_images          b ON b.id = t.id
UNION ALL SELECT 'evidences',       COUNT(*) FROM evidences       t JOIN bak_pr1100014042_evidences       b ON b.id = t.id
UNION ALL SELECT 'documents',       COUNT(*) FROM documents       t JOIN bak_pr1100014042_documents       b ON b.id = t.id
UNION ALL SELECT 'failed_emails',   COUNT(*) FROM failed_emails   t JOIN bak_pr1100014042_failed_emails   b ON b.id = t.id
UNION ALL SELECT 'log_quotation',   COUNT(*) FROM log_quotation   t JOIN bak_pr1100014042_log_quotation   b ON b.id = t.id
UNION ALL SELECT 'log_sla',         COUNT(*) FROM log_sla         t JOIN bak_pr1100014042_log_sla         b ON b.id = t.id
UNION ALL SELECT 'rfq_token_email', COUNT(*) FROM rfq_token_email t JOIN bak_pr1100014042_rfq_token_email b ON b.id = t.id
UNION ALL SELECT 'qcf_token_email', COUNT(*) FROM qcf_token_email t JOIN bak_pr1100014042_qcf_token_email b ON b.id = t.id
UNION ALL SELECT 'pr_library',      COUNT(*) FROM pr_library      t JOIN bak_pr1100014042_pr_library      b ON b.id = t.id
UNION ALL SELECT 'log_activity',    COUNT(*) FROM log_activity    t JOIN bak_pr1100014042_log_activity    b ON b.id = t.id
UNION ALL SELECT 'emails',          COUNT(*) FROM emails          t JOIN bak_pr1100014042_emails          b ON b.id = t.id;

-- -----------------------------------------------------------------------------
-- 1. RESTORE (dalam transaksi)
-- -----------------------------------------------------------------------------
START TRANSACTION;

-- Induk
INSERT INTO rfq_library     SELECT * FROM bak_pr1100014042_rfq_library;

-- Anak
INSERT INTO qcf_library     SELECT * FROM bak_pr1100014042_qcf_library;
INSERT INTO images          SELECT * FROM bak_pr1100014042_images;
INSERT INTO evidences       SELECT * FROM bak_pr1100014042_evidences;
INSERT INTO documents       SELECT * FROM bak_pr1100014042_documents;
INSERT INTO failed_emails   SELECT * FROM bak_pr1100014042_failed_emails;
INSERT INTO log_quotation   SELECT * FROM bak_pr1100014042_log_quotation;
INSERT INTO log_sla         SELECT * FROM bak_pr1100014042_log_sla;
INSERT INTO rfq_token_email SELECT * FROM bak_pr1100014042_rfq_token_email;
INSERT INTO qcf_token_email SELECT * FROM bak_pr1100014042_qcf_token_email;
INSERT INTO pr_library      SELECT * FROM bak_pr1100014042_pr_library;

-- Opsional (hanya berpengaruh jika BAGIAN 2 ikut dihapus; jika tidak, baris sudah ada
-- dan pre-check di atas akan menunjukkan n > 0 -> lewati 2 baris ini)
INSERT INTO log_activity    SELECT * FROM bak_pr1100014042_log_activity;
INSERT INTO emails          SELECT * FROM bak_pr1100014042_emails;

-- -----------------------------------------------------------------------------
-- 2. VERIFIKASI (jumlah di tabel asli harus = jumlah di backup)
-- -----------------------------------------------------------------------------
SELECT 'rfq_library' t,
       (SELECT COUNT(*) FROM rfq_library t JOIN bak_pr1100014042_rfq_library b ON b.id = t.id) restored,
       (SELECT COUNT(*) FROM bak_pr1100014042_rfq_library) expected
UNION ALL SELECT 'qcf_library',     (SELECT COUNT(*) FROM qcf_library     t JOIN bak_pr1100014042_qcf_library     b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_qcf_library)
UNION ALL SELECT 'images',          (SELECT COUNT(*) FROM images          t JOIN bak_pr1100014042_images          b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_images)
UNION ALL SELECT 'evidences',       (SELECT COUNT(*) FROM evidences       t JOIN bak_pr1100014042_evidences       b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_evidences)
UNION ALL SELECT 'documents',       (SELECT COUNT(*) FROM documents       t JOIN bak_pr1100014042_documents       b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_documents)
UNION ALL SELECT 'failed_emails',   (SELECT COUNT(*) FROM failed_emails   t JOIN bak_pr1100014042_failed_emails   b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_failed_emails)
UNION ALL SELECT 'log_quotation',   (SELECT COUNT(*) FROM log_quotation   t JOIN bak_pr1100014042_log_quotation   b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_log_quotation)
UNION ALL SELECT 'log_sla',         (SELECT COUNT(*) FROM log_sla         t JOIN bak_pr1100014042_log_sla         b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_log_sla)
UNION ALL SELECT 'rfq_token_email', (SELECT COUNT(*) FROM rfq_token_email t JOIN bak_pr1100014042_rfq_token_email b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_rfq_token_email)
UNION ALL SELECT 'qcf_token_email', (SELECT COUNT(*) FROM qcf_token_email t JOIN bak_pr1100014042_qcf_token_email b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_qcf_token_email)
UNION ALL SELECT 'pr_library',      (SELECT COUNT(*) FROM pr_library      t JOIN bak_pr1100014042_pr_library      b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_pr_library)
UNION ALL SELECT 'log_activity',    (SELECT COUNT(*) FROM log_activity    t JOIN bak_pr1100014042_log_activity    b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_log_activity)
UNION ALL SELECT 'emails',          (SELECT COUNT(*) FROM emails          t JOIN bak_pr1100014042_emails          b ON b.id = t.id), (SELECT COUNT(*) FROM bak_pr1100014042_emails);

-- Jika restored = expected untuk semua tabel:
-- COMMIT;
-- Jika tidak:
-- ROLLBACK;

-- -----------------------------------------------------------------------------
-- 3. CLEANUP tabel backup (jalankan TERPISAH, hanya setelah data dipastikan tidak
--    dibutuhkan lagi -- baik setelah delete final maupun setelah rollback sukses)
-- -----------------------------------------------------------------------------
-- DROP TABLE bak_pr1100014042_rfq_library, bak_pr1100014042_qcf_library,
--            bak_pr1100014042_images, bak_pr1100014042_evidences,
--            bak_pr1100014042_documents, bak_pr1100014042_failed_emails,
--            bak_pr1100014042_log_quotation, bak_pr1100014042_log_sla,
--            bak_pr1100014042_rfq_token_email, bak_pr1100014042_qcf_token_email,
--            bak_pr1100014042_pr_library, bak_pr1100014042_log_activity,
--            bak_pr1100014042_emails;
