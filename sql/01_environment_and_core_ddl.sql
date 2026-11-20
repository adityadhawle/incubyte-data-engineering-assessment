
-- ============================================================
-- SkyPoints Data Engineering Assessment
-- File: 01_environment_and_core_ddl.sql
-- Platform: Snowflake
--
-- Purpose:
-- 1. Configure the Snowflake warehouse.
-- 2. Create the assessment database and schemas.
-- 3. Define the raw member profile table.
-- 4. Define the staging member profile table.
-- 5. Load sample raw member records safely.
--
-- Notes:
-- - Raw data is stored as strings to preserve source values.
-- - Data type conversion and business transformations belong
--   in the staging pipeline.
-- - Audit table definitions are maintained separately in
--   05_data_quality_and_audit.sql.
-- - This is a reference implementation, not a complete
--   production ingestion framework.
-- ============================================================


-- ============================================================
-- 1. WAREHOUSE CONFIGURATION
-- ============================================================

SHOW WAREHOUSES;

-- Configure the assessment warehouse if it already exists.
-- Warehouse creation is intentionally not included because
-- the assessment environment may already provide COMPUTE_WH.

ALTER WAREHOUSE COMPUTE_WH
SET
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;


-- ============================================================
-- 2. DATABASE AND SCHEMA SETUP
-- ============================================================

CREATE DATABASE IF NOT EXISTS SKYPOINTS_DB;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.RAW;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.STAGING;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.TARGET;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.AUDIT;

SHOW SCHEMAS IN DATABASE SKYPOINTS_DB;


-- ============================================================
-- 3. RAW MEMBER PROFILE TABLE
-- ============================================================

-- Raw layer preserves source values in their original format.
-- Date fields are VARCHAR because source dates arrive as strings.

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE (
    MEMBER_NAME       VARCHAR(255),
    MEMBER_ID         VARCHAR(18),
    ENROLLMENT_DATE   VARCHAR(8),
    LAST_FLIGHT_DATE  VARCHAR(8),
    TIER_CODE         VARCHAR(5),
    AGENT_NAME        VARCHAR(255),
    STATE             VARCHAR(5),
    COUNTRY           VARCHAR(5),
    DOB               VARCHAR(8),
    IS_ACTIVE         VARCHAR(1),
    POST_CODE         VARCHAR(20),

    SOURCE_FILE       VARCHAR(500),
    INGESTION_TIME    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    BATCH_ID          VARCHAR(100)
);

DESC TABLE SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE;


-- ============================================================
-- 4. SAMPLE RAW DATA LOAD
-- ============================================================

-- Sample records are inserted only when the same member,
-- batch and source file combination is not already present.
--
-- Assumption:
-- A member has at most one source record per batch/file.
-- For production ingestion, use a stable source record ID
-- or file-level ingestion control for stronger deduplication.

INSERT INTO SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE (
    MEMBER_NAME,
    MEMBER_ID,
    ENROLLMENT_DATE,
    LAST_FLIGHT_DATE,
    TIER_CODE,
    AGENT_NAME,
    STATE,
    COUNTRY,
    DOB,
    IS_ACTIVE,
    SOURCE_FILE,
    BATCH_ID
)
SELECT
    V.MEMBER_NAME,
    V.MEMBER_ID,
    V.ENROLLMENT_DATE,
    V.LAST_FLIGHT_DATE,
    V.TIER_CODE,
    V.AGENT_NAME,
    V.STATE,
    V.COUNTRY,
    V.DOB,
    V.IS_ACTIVE,
    V.SOURCE_FILE,
    V.BATCH_ID
FROM VALUES
    ('Elena', '223457', '20101012', '20121013', 'GLD',
     'Sam', 'CA', 'USA', '03051985', 'A',
     'member_profile_sample.txt', 'BATCH_001'),

    ('Ravi', '223458', '20101012', '20121013', 'SLV',
     'Sam', 'TN', 'IND', '03051985', 'A',
     'member_profile_sample.txt', 'BATCH_001'),

    ('Mateo', '223459', '20101012', '20121013', 'GLD',
     'Sam', 'NCR', 'PHIL', '03051985', 'A',
     'member_profile_sample.txt', 'BATCH_001'),

    ('Nora', '22345', '20101012', '20121013', 'PLT',
     'Sam', 'ONT', 'CAN', '03051985', 'A',
     'member_profile_sample.txt', 'BATCH_001'),

    ('Jacob', '2256', '20101012', '20121013', 'SLV',
     'Sam', 'VIC', 'AU', '03051985', 'A',
     'member_profile_sample.txt', 'BATCH_001')

AS V (
    MEMBER_NAME,
    MEMBER_ID,
    ENROLLMENT_DATE,
    LAST_FLIGHT_DATE,
    TIER_CODE,
    AGENT_NAME,
    STATE,
    COUNTRY,
    DOB,
    IS_ACTIVE,
    SOURCE_FILE,
    BATCH_ID
)
WHERE NOT EXISTS (
    SELECT 1
    FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE R
    WHERE R.MEMBER_ID = V.MEMBER_ID
      AND R.BATCH_ID = V.BATCH_ID
      AND EQUAL_NULL(R.SOURCE_FILE, V.SOURCE_FILE)
);


-- Verify raw records.
SELECT
    MEMBER_NAME,
    MEMBER_ID,
    ENROLLMENT_DATE,
    LAST_FLIGHT_DATE,
    COUNTRY,
    DOB,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE
ORDER BY MEMBER_ID;


-- ============================================================
-- 5. STAGING MEMBER PROFILE TABLE
-- ============================================================

-- Staging layer stores parsed dates and derived attributes.
-- Transformations such as AGE and STALE_MEMBER are calculated
-- in the staging transformation pipeline.

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE (
    MEMBER_NAME       VARCHAR(255),
    MEMBER_ID         VARCHAR(18),
    ENROLLMENT_DATE   DATE,
    LAST_FLIGHT_DATE  DATE,
    TIER_CODE         VARCHAR(5),
    AGENT_NAME        VARCHAR(255),
    STATE             VARCHAR(5),
    COUNTRY           VARCHAR(5),
    DOB               DATE,
    AGE               INTEGER,
    IS_ACTIVE         VARCHAR(1),
    STALE_MEMBER      BOOLEAN,
    SOURCE_FILE       VARCHAR(500),
    INGESTION_TIME    TIMESTAMP_NTZ,
    BATCH_ID          VARCHAR(100),
    POST_CODE         VARCHAR(20)
);

DESC TABLE SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE;


-- ============================================================
-- 6. FINAL ENVIRONMENT AND TABLE VERIFICATION
-- ============================================================

SELECT
    CURRENT_DATABASE() AS DATABASE_NAME,
    CURRENT_SCHEMA() AS SCHEMA_NAME,
    CURRENT_WAREHOUSE() AS WAREHOUSE_NAME,
    CURRENT_TIMESTAMP() AS CHECK_TIME;

SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    ORDINAL_POSITION
FROM SKYPOINTS_DB.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('RAW', 'STAGING')
  AND TABLE_NAME IN (
      'RAW_MEMBER_PROFILE',
      'STG_MEMBER_PROFILE'
  )
ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION;
