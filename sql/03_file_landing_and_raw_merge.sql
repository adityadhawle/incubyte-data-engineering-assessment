
-- ============================================================
-- SkyPoints Data Engineering Assessment
-- File: 03_file_landing_and_raw_merge.sql
-- Platform: Snowflake
--
-- Purpose:
-- 1. Define the pipe-delimited CSV file format.
-- 2. Create an internal Snowflake stage.
-- 3. Create a raw file landing table.
-- 4. Load staged files into the landing table.
-- 5. Validate landing records and identify duplicate member IDs.
-- 6. Merge valid file records into RAW_MEMBER_PROFILE.
--
-- Notes:
-- - Files must be uploaded to the internal stage separately.
-- - COPY INTO uses FORCE = FALSE to avoid intentionally
--   reloading files already recorded as loaded by Snowflake.
-- - Duplicate member IDs within a landing batch are excluded
--   from the RAW MERGE to avoid ambiguous source matches.
-- - Staging transformations and MEMBER_CURRENT MERGE are
--   maintained in 02_core_member_transform_and_current.sql.
-- ============================================================


-- ============================================================
-- 1. PIPE-DELIMITED FILE FORMAT
-- ============================================================

CREATE FILE FORMAT IF NOT EXISTS
    SKYPOINTS_DB.RAW.MEMBER_PIPE_FORMAT
TYPE = CSV
FIELD_DELIMITER = '|'
SKIP_HEADER = 0
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
TRIM_SPACE = TRUE
EMPTY_FIELD_AS_NULL = TRUE
NULL_IF = ('NULL', 'null');


-- Inspect file format definition.
DESC FILE FORMAT SKYPOINTS_DB.RAW.MEMBER_PIPE_FORMAT;


-- ============================================================
-- 2. INTERNAL STAGE
-- ============================================================

CREATE STAGE IF NOT EXISTS
    SKYPOINTS_DB.RAW.MEMBER_FILE_STAGE
FILE_FORMAT = SKYPOINTS_DB.RAW.MEMBER_PIPE_FORMAT;


-- List files uploaded to the stage.
LIST @SKYPOINTS_DB.RAW.MEMBER_FILE_STAGE;


-- ============================================================
-- 3. RAW FILE LANDING TABLE
-- ============================================================

-- Landing table stores source fields as strings.
-- FIELD_1 to FIELD_12 preserve the incoming file structure.

CREATE TABLE IF NOT EXISTS
    SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING (
    FIELD_1  VARCHAR,
    FIELD_2  VARCHAR,
    FIELD_3  VARCHAR,
    FIELD_4  VARCHAR,
    FIELD_5  VARCHAR,
    FIELD_6  VARCHAR,
    FIELD_7  VARCHAR,
    FIELD_8  VARCHAR,
    FIELD_9  VARCHAR,
    FIELD_10 VARCHAR,
    FIELD_11 VARCHAR,
    FIELD_12 VARCHAR
);


-- ============================================================
-- 4. LOAD FILES INTO LANDING TABLE
-- ============================================================

-- Upload the source file to MEMBER_FILE_STAGE before running COPY.
-- FORCE = FALSE avoids intentionally reloading files that
-- Snowflake already recognizes as loaded into this table.

COPY INTO SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING
FROM @SKYPOINTS_DB.RAW.MEMBER_FILE_STAGE
FILE_FORMAT = (
    FORMAT_NAME = 'SKYPOINTS_DB.RAW.MEMBER_PIPE_FORMAT'
)
ON_ERROR = 'ABORT_STATEMENT'
FORCE = FALSE;


-- Review loaded landing records.

SELECT *
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING;


-- Landing table row count.

SELECT
    COUNT(*) AS LANDING_RECORD_COUNT
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING;


-- Existing raw member count.

SELECT
    COUNT(*) AS EXISTING_RAW_RECORDS
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE;


-- ============================================================
-- 5. LANDING DATA VALIDATION
-- ============================================================

-- The assessment file uses FIELD_2 = 'D' for data records.
-- Check duplicate member IDs in the incoming data records.

SELECT
    FIELD_4 AS MEMBER_ID,
    COUNT(*) AS FILE_RECORD_COUNT
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING
WHERE FIELD_2 = 'D'
GROUP BY FIELD_4
HAVING COUNT(*) > 1;


-- Check missing mandatory source fields.

SELECT
    COUNT(*) AS TOTAL_DATA_RECORDS,

    COUNT_IF(
        FIELD_3 IS NULL OR TRIM(FIELD_3) = ''
    ) AS MISSING_MEMBER_NAMES,

    COUNT_IF(
        FIELD_4 IS NULL OR TRIM(FIELD_4) = ''
    ) AS MISSING_MEMBER_IDS,

    COUNT_IF(
        FIELD_5 IS NULL OR TRIM(FIELD_5) = ''
    ) AS MISSING_ENROLLMENT_DATES,

    COUNT_IF(
        FIELD_6 IS NULL OR TRIM(FIELD_6) = ''
    ) AS MISSING_LAST_FLIGHT_DATES,

    COUNT_IF(
        FIELD_10 IS NULL OR TRIM(FIELD_10) = ''
    ) AS MISSING_COUNTRIES

FROM SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING
WHERE FIELD_2 = 'D';


-- Compare incoming member IDs with existing raw records.

SELECT
    L.FIELD_4 AS FILE_MEMBER_ID,
    L.FIELD_3 AS FILE_MEMBER_NAME,
    R.MEMBER_ID AS RAW_MEMBER_ID,
    R.MEMBER_NAME AS RAW_MEMBER_NAME,

    CASE
        WHEN R.MEMBER_ID IS NOT NULL THEN 'MATCHED'
        ELSE 'NOT FOUND'
    END AS VALIDATION_STATUS

FROM SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING L

LEFT JOIN SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE R
    ON L.FIELD_4 = R.MEMBER_ID

WHERE L.FIELD_2 = 'D'
  AND L.FIELD_4 IS NOT NULL
  AND TRIM(L.FIELD_4) <> '';


-- ============================================================
-- 6. MERGE VALID FILE RECORDS INTO RAW MEMBER PROFILE
-- ============================================================

-- Source mapping:
-- FIELD_3  -> MEMBER_NAME
-- FIELD_4  -> MEMBER_ID
-- FIELD_5  -> ENROLLMENT_DATE
-- FIELD_6  -> LAST_FLIGHT_DATE
-- FIELD_7  -> TIER_CODE
-- FIELD_8  -> AGENT_NAME
-- FIELD_9  -> STATE
-- FIELD_10 -> COUNTRY
-- FIELD_11 -> DOB
-- FIELD_12 -> IS_ACTIVE
--
-- Duplicate MEMBER_ID values in the same landing data set
-- are excluded from the MERGE because no source event version
-- is available to determine which duplicate is latest.
--
-- FILE_BATCH_001 is a reference batch identifier.
-- Replace it with the actual batch identifier in a production
-- ingestion process.

MERGE INTO SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE T

USING (
    SELECT
        FIELD_3 AS MEMBER_NAME,
        FIELD_4 AS MEMBER_ID,
        FIELD_5 AS ENROLLMENT_DATE,
        FIELD_6 AS LAST_FLIGHT_DATE,
        FIELD_7 AS TIER_CODE,
        FIELD_8 AS AGENT_NAME,
        FIELD_9 AS STATE,
        FIELD_10 AS COUNTRY,
        FIELD_11 AS DOB,
        FIELD_12 AS IS_ACTIVE

    FROM SKYPOINTS_DB.RAW.RAW_MEMBER_FILE_LANDING

    WHERE FIELD_2 = 'D'
      AND FIELD_4 IS NOT NULL
      AND TRIM(FIELD_4) <> ''

    QUALIFY COUNT(*) OVER (
        PARTITION BY FIELD_4
    ) = 1

) S

ON T.MEMBER_ID = S.MEMBER_ID

WHEN MATCHED AND (
       T.MEMBER_NAME IS DISTINCT FROM S.MEMBER_NAME
    OR T.ENROLLMENT_DATE IS DISTINCT FROM S.ENROLLMENT_DATE
    OR T.LAST_FLIGHT_DATE IS DISTINCT FROM S.LAST_FLIGHT_DATE
    OR T.TIER_CODE IS DISTINCT FROM S.TIER_CODE
    OR T.AGENT_NAME IS DISTINCT FROM S.AGENT_NAME
    OR T.STATE IS DISTINCT FROM S.STATE
    OR T.COUNTRY IS DISTINCT FROM S.COUNTRY
    OR T.DOB IS DISTINCT FROM S.DOB
    OR T.IS_ACTIVE IS DISTINCT FROM S.IS_ACTIVE
    OR T.SOURCE_FILE IS DISTINCT FROM 'STAGE_FILE_IMPORT'
    OR T.BATCH_ID IS DISTINCT FROM 'FILE_BATCH_001'
)

THEN UPDATE SET
    T.MEMBER_NAME = S.MEMBER_NAME,
    T.ENROLLMENT_DATE = S.ENROLLMENT_DATE,
    T.LAST_FLIGHT_DATE = S.LAST_FLIGHT_DATE,
    T.TIER_CODE = S.TIER_CODE,
    T.AGENT_NAME = S.AGENT_NAME,
    T.STATE = S.STATE,
    T.COUNTRY = S.COUNTRY,
    T.DOB = S.DOB,
    T.IS_ACTIVE = S.IS_ACTIVE,
    T.SOURCE_FILE = 'STAGE_FILE_IMPORT',
    T.INGESTION_TIME = CURRENT_TIMESTAMP(),
    T.BATCH_ID = 'FILE_BATCH_001'

WHEN NOT MATCHED THEN INSERT (
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
    INGESTION_TIME,
    BATCH_ID
)

VALUES (
    S.MEMBER_NAME,
    S.MEMBER_ID,
    S.ENROLLMENT_DATE,
    S.LAST_FLIGHT_DATE,
    S.TIER_CODE,
    S.AGENT_NAME,
    S.STATE,
    S.COUNTRY,
    S.DOB,
    S.IS_ACTIVE,
    'STAGE_FILE_IMPORT',
    CURRENT_TIMESTAMP(),
    'FILE_BATCH_001'
);


-- ============================================================
-- 7. FINAL RAW TABLE VALIDATION
-- ============================================================

SELECT
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE
ORDER BY MEMBER_ID;


-- Check duplicate member IDs in the raw profile.

SELECT
    MEMBER_ID,
    COUNT(*) AS RECORD_COUNT
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE
GROUP BY MEMBER_ID
HAVING COUNT(*) > 1;


-- Raw member summary.

SELECT
    COUNT(*) AS TOTAL_MEMBERS,
    COUNT(DISTINCT MEMBER_ID) AS UNIQUE_MEMBERS,
    COUNT_IF(
        MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = ''
    ) AS MISSING_MEMBER_IDS
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE;


-- ============================================================
-- 8. NEXT PIPELINE STEP
-- ============================================================

-- After validating RAW_MEMBER_PROFILE:
-- Run the staging transformation and current-member pipeline
-- defined in 02_core_member_transform_and_current.sql.
--
-- This file intentionally does not MERGE into MEMBER_CURRENT.
-- ============================================================
