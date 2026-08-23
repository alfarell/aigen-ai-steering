-- MySQL 8.x
-- Use the same script in development and production.
-- REVIEW BEFORE RUNNING. TRUNCATE auto-commits and cannot be rolled back.
-- vendor_matriks_assign is the migration source and is NEVER truncated here.
-- Keep it in development. In production, truncate it manually only after all
-- post-migration verification and application tests have passed.
--
-- Actual table names verified in development:
--   category_matrix_sub_users (plural)
--   material_assignments       (with "n")

-- ============================================================================
-- 0. Add master vendor required by vendor_matriks_assign ids 128 and 129
-- ============================================================================

INSERT INTO master_vendor
    (id, server_groups, vendor_number, vendor_name, vendor_email, vendor_city,
     vendor_street, created_at, updated_at, user_id, is_active)
SELECT
    102, 'BCG', '100353', 'INDO PERKASA MANDIRI',
    'marketing_ipm01@indoperkasamandiri.com', 'BALIKPAPAN',
    'JL. MULAWARMAN NO. 33',
    '2025-09-28 13:31:50', '2025-09-28 13:31:50', NULL, 1
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1
    FROM master_vendor
    WHERE id = 102
       OR (server_groups = 'BCG' AND vendor_number = '100353')
);

-- ============================================================================
-- 1. Preflight: these result sets must be empty before migration
-- ============================================================================

-- Missing direct vendors.
SELECT
    vma.id,
    vma.server_groups,
    vma.external_mat_group,
    vma.vendor_lvl_1 AS missing_vendor_number
FROM vendor_matriks_assign AS vma
LEFT JOIN master_vendor AS mv
    ON BINARY mv.vendor_number = BINARY vma.vendor_lvl_1
   AND BINARY mv.server_groups = BINARY vma.server_groups
WHERE vma.vendor_lvl_1 IS NOT NULL
  AND vma.vendor_lvl_1 <> ''
  AND mv.id IS NULL;

-- Missing aggregate vendors.
SELECT
    vma.id,
    vma.server_groups,
    vma.external_mat_group,
    vma.vendor_lvl_2 AS missing_vendor_number
FROM vendor_matriks_assign AS vma
LEFT JOIN master_vendor AS mv
    ON BINARY mv.vendor_number = BINARY vma.vendor_lvl_2
   AND BINARY mv.server_groups = BINARY vma.server_groups
WHERE vma.vendor_lvl_2 IS NOT NULL
  AND vma.vendor_lvl_2 <> ''
  AND mv.id IS NULL;

-- CS values not covered by the development category-matrix seed below.
SELECT DISTINCT
    vma.cs_id AS missing_cs_id
FROM vendor_matriks_assign AS vma
WHERE vma.cs_id NOT IN (68, 72, 73)
   OR vma.cs_id IS NULL;

-- Same server/extended-material-group mapped to more than one assignment.
-- This result set must be empty to prevent ambiguous vendor/category mapping.
SELECT
    vma.server_groups,
    vma.external_mat_group,
    COUNT(*) AS row_count,
    COUNT(DISTINCT CONCAT_WS(
        '|', vma.vendor_lvl_1, vma.vendor_lvl_2, vma.cs_id
    )) AS assignment_variants
FROM vendor_matriks_assign AS vma
GROUP BY
    vma.server_groups,
    vma.external_mat_group
HAVING COUNT(*) > 1
    OR assignment_variants > 1;

-- Users required by the development category seed but absent in the target.
SELECT required.user_id AS missing_user_id
FROM (
    SELECT 4 AS user_id UNION ALL
    SELECT 64 UNION ALL
    SELECT 65 UNION ALL
    SELECT 68 UNION ALL
    SELECT 71 UNION ALL
    SELECT 72 UNION ALL
    SELECT 73 UNION ALL
    SELECT 75 UNION ALL
    SELECT 79 UNION ALL
    SELECT 81
) AS required
LEFT JOIN users AS u ON u.id = required.user_id
WHERE u.id IS NULL;

-- ============================================================================
-- 2. Truncate target tables
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE material_assignment_vendor_aggregates;
TRUNCATE TABLE material_assignments;
TRUNCATE TABLE master_hierarchy;

TRUNCATE TABLE category_matrix_sub_users;
TRUNCATE TABLE category_matrices;
TRUNCATE TABLE categories;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- 3. Seed categories exactly as they currently exist in development
-- ============================================================================

INSERT INTO categories
    (id, name, created_at, updated_at, parent_id, parent_name, level, is_active)
VALUES
    (1,  'CPI',   '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (2,  'FEL',   '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (3,  'GSL',   '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (4,  'MRR',   '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (5,  'TF',    '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (6,  'CM',    '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (7,  'CAT1',  '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (8,  'IT',    '2026-05-20 23:24:21', '2026-05-20 23:24:21', NULL, NULL,  0, 1),
    (15, 'GSL-1', '2026-05-20 23:24:21', '2026-05-20 23:24:21', 3,    'GSL', 1, 1),
    (16, 'GSL-2', '2026-05-20 23:24:21', '2026-05-20 23:24:21', 3,    'GSL', 1, 1),
    (18, 'MRR-1', '2026-05-20 23:24:21', '2026-05-20 23:24:21', 4,    'MRR', 1, 1),
    (30, 'IT-1',  '2026-05-20 23:24:21', '2026-05-20 23:24:21', 8,    'IT',  1, 1);

ALTER TABLE categories AUTO_INCREMENT = 31;

-- ============================================================================
-- 4. Seed category matrices exactly as they currently exist in development
-- ============================================================================

INSERT INTO category_matrices
    (id, category_id, main_category_user_id, sub_category_user_id,
     leader_category_user_id, management_user_id, is_active,
     created_at, updated_at, deleted_at)
VALUES
    (1, 18, 68, 68, 65, 64, 1,
     '2026-07-08 00:00:00', '2026-07-21 14:28:29', NULL),
    (2, 15, 72, 72, 4,  64, 1,
     '2026-07-08 00:00:00', '2026-07-21 14:21:21', NULL),
    (3, 30, 73, 79, 81, 64, 1,
     '2026-07-08 00:00:00', '2026-07-21 14:30:29', NULL);

ALTER TABLE category_matrices AUTO_INCREMENT = 5;

INSERT INTO category_matrix_sub_users
    (id, category_matrix_id, user_id, created_at, updated_at)
VALUES
    (5, 2, 71, '2026-07-21 14:21:21', '2026-07-21 14:21:21'),
    (6, 1, 75, '2026-07-21 14:28:29', '2026-07-21 14:28:29'),
    (7, 3, 73, '2026-07-21 14:30:29', '2026-07-21 14:30:29');

ALTER TABLE category_matrix_sub_users AUTO_INCREMENT = 8;

-- ============================================================================
-- 5. Build a temporary hierarchy from vendor_matriks_assign
-- ============================================================================
-- vendor_matriks_assign has external_mat_group but no material_group/parent.
-- The normal rule observed in development is XXYY -> XX00.
-- master_hierarchy confirms that the standard relation is XXYY -> XX00.
-- vendor_matriks_assign has no material_number, so the migrated hierarchy only
-- contains material-group -> extended-material-group relationships.

DROP TEMPORARY TABLE IF EXISTS tmp_vma_material_hierarchy;

CREATE TEMPORARY TABLE tmp_vma_material_hierarchy (
    server_groups            varchar(10)  NOT NULL,
    external_material_group  varchar(255) NOT NULL,
    material_group           varchar(255) NOT NULL,
    PRIMARY KEY (server_groups, external_material_group)
);

INSERT INTO tmp_vma_material_hierarchy
    (server_groups, external_material_group, material_group)
SELECT DISTINCT
    vma.server_groups,
    vma.external_mat_group,
    CONCAT(
        LEFT(vma.external_mat_group, LENGTH(vma.external_mat_group) - 2),
        '00'
    ) AS material_group
FROM vendor_matriks_assign AS vma;

INSERT INTO master_hierarchy
    (material_group, server, extended_material_group, material_number,
     is_active, created_at, updated_at)
SELECT
    h.material_group,
    h.server_groups,
    h.external_material_group,
    '',
    1,
    COALESCE(vma.created_at, CURRENT_TIMESTAMP),
    COALESCE(vma.updated_at, CURRENT_TIMESTAMP)
FROM tmp_vma_material_hierarchy AS h
JOIN vendor_matriks_assign AS vma
    ON BINARY vma.server_groups = BINARY h.server_groups
   AND BINARY vma.external_mat_group = BINARY h.external_material_group;

-- ============================================================================
-- 6. Create parent material-group assignments
-- ============================================================================
-- Parent rows intentionally have no vendor/category because one material group
-- can contain external groups assigned to different CS/category/vendor values.

INSERT INTO material_assignments
    (parent_id, server_groups, group_type, group_value, vendor_direct_id,
     category_id, sub_category_id, is_active, created_at, updated_at)
SELECT DISTINCT
    NULL,
    h.server_groups,
    'material_group',
    h.material_group,
    NULL,
    NULL,
    NULL,
    1,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM tmp_vma_material_hierarchy AS h;

-- ============================================================================
-- 7. Create external-material-group assignments from vendor_matriks_assign
-- ============================================================================
-- vendor_lvl_1 -> direct vendor
-- cs_id        -> category matrix -> subcategory and its parent category

INSERT INTO material_assignments
    (parent_id, server_groups, group_type, group_value, vendor_direct_id,
     category_id, sub_category_id, is_active, created_at, updated_at)
SELECT
    parent_ma.id,
    vma.server_groups,
    'extended_material_group',
    vma.external_mat_group,
    direct_vendor.id,
    sub_category.parent_id,
    cm.category_id,
    1,
    COALESCE(vma.created_at, CURRENT_TIMESTAMP),
    COALESCE(vma.updated_at, CURRENT_TIMESTAMP)
FROM vendor_matriks_assign AS vma
JOIN tmp_vma_material_hierarchy AS h
    ON BINARY h.server_groups = BINARY vma.server_groups
   AND BINARY h.external_material_group = BINARY vma.external_mat_group
JOIN material_assignments AS parent_ma
    ON parent_ma.parent_id IS NULL
   AND BINARY parent_ma.server_groups = BINARY h.server_groups
   AND parent_ma.group_type = 'material_group'
   AND BINARY parent_ma.group_value = BINARY h.material_group
JOIN category_matrices AS cm
    ON cm.main_category_user_id = vma.cs_id
   AND cm.is_active = 1
JOIN categories AS sub_category
    ON sub_category.id = cm.category_id
LEFT JOIN master_vendor AS direct_vendor
    ON BINARY direct_vendor.vendor_number = BINARY vma.vendor_lvl_1
   AND BINARY direct_vendor.server_groups = BINARY vma.server_groups;

-- ============================================================================
-- 8. Map vendor_lvl_2 as aggregate vendor
-- ============================================================================

INSERT INTO material_assignment_vendor_aggregates
    (material_assignment_id, vendor_id, created_at, updated_at)
SELECT
    ma.id,
    aggregate_vendor.id,
    COALESCE(vma.created_at, CURRENT_TIMESTAMP),
    COALESCE(vma.updated_at, CURRENT_TIMESTAMP)
FROM vendor_matriks_assign AS vma
JOIN material_assignments AS ma
    ON BINARY ma.server_groups = BINARY vma.server_groups
   AND ma.group_type = 'extended_material_group'
   AND BINARY ma.group_value = BINARY vma.external_mat_group
JOIN master_vendor AS aggregate_vendor
    ON BINARY aggregate_vendor.vendor_number = BINARY vma.vendor_lvl_2
   AND BINARY aggregate_vendor.server_groups = BINARY vma.server_groups
WHERE vma.vendor_lvl_2 IS NOT NULL
  AND vma.vendor_lvl_2 <> '';

DROP TEMPORARY TABLE IF EXISTS tmp_vma_material_hierarchy;

-- ============================================================================
-- 9. Post-migration verification
-- ============================================================================

SELECT 'vendor_matriks_assign' AS table_name, COUNT(*) AS row_count
FROM vendor_matriks_assign
UNION ALL
SELECT 'categories', COUNT(*) FROM categories
UNION ALL
SELECT 'category_matrices', COUNT(*) FROM category_matrices
UNION ALL
SELECT 'category_matrix_sub_users', COUNT(*) FROM category_matrix_sub_users
UNION ALL
SELECT 'master_hierarchy', COUNT(*) FROM master_hierarchy
UNION ALL
SELECT 'material_assignments', COUNT(*) FROM material_assignments
UNION ALL
SELECT 'material_assignment_vendor_aggregates', COUNT(*)
FROM material_assignment_vendor_aggregates;

-- Assignment rows that could not resolve a direct vendor.
SELECT
    ma.id AS material_assignment_id,
    ma.server_groups,
    ma.group_value AS external_material_group
FROM material_assignments AS ma
WHERE ma.group_type = 'extended_material_group'
  AND ma.vendor_direct_id IS NULL;

-- Must return no rows: duplicate material/extended assignment keys.
SELECT
    ma.parent_id,
    ma.server_groups,
    ma.group_type,
    ma.group_value,
    COUNT(*) AS duplicate_count,
    COUNT(DISTINCT COALESCE(ma.vendor_direct_id, 0)) AS direct_vendor_variants
FROM material_assignments AS ma
GROUP BY
    ma.parent_id,
    ma.server_groups,
    ma.group_type,
    ma.group_value
HAVING COUNT(*) > 1
    OR direct_vendor_variants > 1;

-- Must return no rows: duplicate aggregate vendor pairs.
SELECT
    mava.material_assignment_id,
    mava.vendor_id,
    COUNT(*) AS duplicate_count
FROM material_assignment_vendor_aggregates AS mava
GROUP BY
    mava.material_assignment_id,
    mava.vendor_id
HAVING COUNT(*) > 1;
