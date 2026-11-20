
-- ============================================================
-- SkyPoints Data Engineering Assessment
-- File: 02_core_member_transform_and_current.sql
-- Platform: Snowflake
--
-- Purpose:
-- 1. Transform raw member records into staging.
-- 2. Parse dates and calculate AGE and STALE_MEMBER.
-- 3. Prevent duplicate staging loads for the same
--    member, batch and source file.
-- 4. Maintain the latest member record in MEMBER_CURRENT.
-- 5. Create country-specific views.
-- 6. Demonstrate a member country migration.
-- 7. Validate the core member pipeline.
--
-- Important assumptions:
-- - MEMBER_ID is treated as the stable global member key.
-- - One member record per batch/source file is expected.
-- - BATCH_ID is used as a secondary ordering field.
-- - Exact timestamp and batch ties need a source event ID
--   for fully deterministic production processing.
-- ============================================================


-- ============================================================
-- 1. RAW TO STAGING TRANSFORMATION
-- ============================================================

-- Convert source date strings into DATE values.
-- Calculate age using the current date and birthday.
-- A member is stale when the last flight was more than 90 days ago.

INSERT INTO SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE (
    MEMBER_NAME,
    MEMBER_ID,
    ENROLLMENT_DATE,
    LAST_FLIGHT_DATE,
    TIER_CODE,
    AGENT_NAME,
    STATE,
    COUNTRY,
    DOB,
    AGE,
    IS_ACTIVE,
    STALE_MEMBER,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID,
    POST_CODE
)
SELECT
    R.MEMBER_NAME,
    R.MEMBER_ID,

    TRY_TO_DATE(R.ENROLLMENT_DATE, 'YYYYMMDD')
        AS ENROLLMENT_DATE,

    TRY_TO_DATE(R.LAST_FLIGHT_DATE, 'YYYYMMDD')
        AS LAST_FLIGHT_DATE,

    R.TIER_CODE,
    R.AGENT_NAME,
    R.STATE,
    R.COUNTRY,

    TRY_TO_DATE(R.DOB, 'MMDDYYYY')
        AS DOB,

    CASE
        WHEN TRY_TO_DATE(R.DOB, 'MMDDYYYY') IS NOT NULL
        THEN
            DATEDIFF(
                YEAR,
                TRY_TO_DATE(R.DOB, 'MMDDYYYY'),
                CURRENT_DATE()
            )
            - IFF(
                TO_CHAR(CURRENT_DATE(), 'MMDD')
                < TO_CHAR(
                    TRY_TO_DATE(R.DOB, 'MMDDYYYY'),
                    'MMDD'
                ),
                1,
                0
            )
        ELSE NULL
    END AS AGE,

    R.IS_ACTIVE,

    CASE
        WHEN TRY_TO_DATE(R.LAST_FLIGHT_DATE, 'YYYYMMDD') IS NULL
            THEN NULL

        WHEN DATEDIFF(
            DAY,
            TRY_TO_DATE(R.LAST_FLIGHT_DATE, 'YYYYMMDD'),
            CURRENT_DATE()
        ) > 90
            THEN TRUE

        ELSE FALSE
    END AS STALE_MEMBER,

    R.SOURCE_FILE,
    R.INGESTION_TIME,
    R.BATCH_ID,
    R.POST_CODE

FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE R

WHERE R.MEMBER_ID IS NOT NULL
  AND TRIM(R.MEMBER_ID) <> ''

  AND NOT EXISTS (
      SELECT 1
      FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE S
      WHERE S.MEMBER_ID = R.MEMBER_ID
        AND S.BATCH_ID = R.BATCH_ID
        AND EQUAL_NULL(S.SOURCE_FILE, R.SOURCE_FILE)
  );


-- ============================================================
-- 2. STAGING DATA VALIDATION
-- ============================================================

-- Review transformed staging records.

SELECT
    MEMBER_NAME,
    MEMBER_ID,
    ENROLLMENT_DATE,
    LAST_FLIGHT_DATE,
    DOB,
    AGE,
    STALE_MEMBER,
    COUNTRY,
    POST_CODE,
    SOURCE_FILE,
    BATCH_ID
FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE
ORDER BY MEMBER_ID, INGESTION_TIME;


-- Mandatory field and date validation.

SELECT
    COUNT(*) AS TOTAL_RECORDS,

    COUNT_IF(
        MEMBER_NAME IS NULL OR TRIM(MEMBER_NAME) = ''
    ) AS MISSING_MEMBER_NAME,

    COUNT_IF(
        MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = ''
    ) AS MISSING_MEMBER_ID,

    COUNT_IF(
        ENROLLMENT_DATE IS NULL
    ) AS INVALID_ENROLLMENT_DATE,

    COUNT_IF(
        LAST_FLIGHT_DATE IS NULL
    ) AS INVALID_LAST_FLIGHT_DATE,

    COUNT_IF(
        COUNTRY IS NULL OR TRIM(COUNTRY) = ''
    ) AS MISSING_COUNTRY,

    COUNT_IF(
        DOB IS NULL
    ) AS MISSING_DOB,

    COUNT(DISTINCT MEMBER_ID) AS UNIQUE_MEMBER_IDS

FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE;


-- Check duplicate member records within staging.

SELECT
    MEMBER_ID,
    COUNT(*) AS RECORD_COUNT
FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE
GROUP BY MEMBER_ID
HAVING COUNT(*) > 1;


-- ============================================================
-- 3. CENTRAL CURRENT MEMBER TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.TARGET.MEMBER_CURRENT (
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


-- ============================================================
-- 4. LATEST-RECORD MERGE
-- ============================================================

-- Select the latest available record per member.
-- MERGE handles both new members and existing members.
-- This replaces the earlier direct INSERT and duplicate MERGE.

MERGE INTO SKYPOINTS_DB.TARGET.MEMBER_CURRENT T

USING (
    SELECT
        MEMBER_NAME,
        MEMBER_ID,
        ENROLLMENT_DATE,
        LAST_FLIGHT_DATE,
        TIER_CODE,
        AGENT_NAME,
        STATE,
        COUNTRY,
        DOB,
        AGE,
        IS_ACTIVE,
        STALE_MEMBER,
        SOURCE_FILE,
        INGESTION_TIME,
        BATCH_ID,
        POST_CODE

    FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE

    WHERE MEMBER_ID IS NOT NULL
      AND TRIM(MEMBER_ID) <> ''

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MEMBER_ID
        ORDER BY
            INGESTION_TIME DESC NULLS LAST,
            BATCH_ID DESC NULLS LAST,
            SOURCE_FILE DESC NULLS LAST
    ) = 1

) S

ON T.MEMBER_ID = S.MEMBER_ID

WHEN MATCHED AND (
       T.INGESTION_TIME IS NULL
    OR S.INGESTION_TIME > T.INGESTION_TIME
    OR (
        EQUAL_NULL(S.INGESTION_TIME, T.INGESTION_TIME)
        AND COALESCE(S.BATCH_ID, '') > COALESCE(T.BATCH_ID, '')
    )
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
    T.AGE = S.AGE,
    T.IS_ACTIVE = S.IS_ACTIVE,
    T.STALE_MEMBER = S.STALE_MEMBER,
    T.SOURCE_FILE = S.SOURCE_FILE,
    T.INGESTION_TIME = S.INGESTION_TIME,
    T.BATCH_ID = S.BATCH_ID,
    T.POST_CODE = COALESCE(S.POST_CODE, T.POST_CODE)

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
    AGE,
    IS_ACTIVE,
    STALE_MEMBER,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID,
    POST_CODE
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
    S.AGE,
    S.IS_ACTIVE,
    S.STALE_MEMBER,
    S.SOURCE_FILE,
    S.INGESTION_TIME,
    S.BATCH_ID,
    S.POST_CODE
);


-- ============================================================
-- 5. COUNTRY-SPECIFIC MEMBER VIEWS
-- ============================================================

-- These views expose the current member records by country.
-- CREATE OR REPLACE updates the view definition, not the
-- underlying MEMBER_CURRENT table data.

CREATE OR REPLACE VIEW SKYPOINTS_DB.TARGET.VW_MEMBERS_INDIA AS
SELECT *
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
WHERE COUNTRY = 'IND';


CREATE OR REPLACE VIEW SKYPOINTS_DB.TARGET.VW_MEMBERS_USA AS
SELECT *
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
WHERE COUNTRY = 'USA';


CREATE OR REPLACE VIEW SKYPOINTS_DB.TARGET.VW_MEMBERS_AU AS
SELECT *
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
WHERE COUNTRY = 'AU';


CREATE OR REPLACE VIEW SKYPOINTS_DB.TARGET.VW_MEMBERS_CAN AS
SELECT *
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
WHERE COUNTRY = 'CAN';


CREATE OR REPLACE VIEW SKYPOINTS_DB.TARGET.VW_MEMBERS_PHIL AS
SELECT *
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
WHERE COUNTRY = 'PHIL';


-- Country-wise member counts.

SELECT 'INDIA' AS COUNTRY, COUNT(*) AS TOTAL_MEMBERS
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_INDIA

UNION ALL

SELECT 'USA', COUNT(*)
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_USA

UNION ALL

SELECT 'AU', COUNT(*)
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_AU

UNION ALL

SELECT 'CAN', COUNT(*)
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_CAN

UNION ALL

SELECT 'PHIL', COUNT(*)
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_PHIL;


-- ============================================================
-- 6. OPTIONAL COUNTRY-MIGRATION TEST
-- ============================================================

-- This test creates a newer staging record for Ravi
-- (MEMBER_ID 223458), moving the member from IND to USA.
--
-- It is kept separate from the regular ingestion flow.
-- The NOT EXISTS condition prevents adding the same test
-- batch more than once.
--
-- Expected result after the MERGE:
-- MEMBER_ID 223458 should appear in the USA view,
-- and should no longer appear in the India view.

INSERT INTO SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE (
    MEMBER_NAME,
    MEMBER_ID,
    ENROLLMENT_DATE,
    LAST_FLIGHT_DATE,
    TIER_CODE,
    AGENT_NAME,
    STATE,
    COUNTRY,
    DOB,
    AGE,
    IS_ACTIVE,
    STALE_MEMBER,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID,
    POST_CODE
)
SELECT
    MEMBER_NAME,
    MEMBER_ID,
    ENROLLMENT_DATE,
    LAST_FLIGHT_DATE,
    TIER_CODE,
    AGENT_NAME,
    STATE,
    'USA' AS COUNTRY,
    DOB,
    AGE,
    IS_ACTIVE,
    STALE_MEMBER,
    SOURCE_FILE,
    DATEADD(SECOND, 10, INGESTION_TIME),
    'BATCH_002',
    POST_CODE

FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE

WHERE MEMBER_ID = '223458'
  AND BATCH_ID = 'BATCH_001'

QUALIFY ROW_NUMBER() OVER (
    ORDER BY INGESTION_TIME DESC NULLS LAST
) = 1

AND NOT EXISTS (
    SELECT 1
    FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE EXISTING
    WHERE EXISTING.MEMBER_ID = '223458'
      AND EXISTING.BATCH_ID = 'BATCH_002'
);


-- Run the same latest-record MERGE after the optional test
-- if the migration test record was newly inserted.

MERGE INTO SKYPOINTS_DB.TARGET.MEMBER_CURRENT T

USING (
    SELECT *
    FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE
    WHERE MEMBER_ID IS NOT NULL
      AND TRIM(MEMBER_ID) <> ''

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MEMBER_ID
        ORDER BY
            INGESTION_TIME DESC NULLS LAST,
            BATCH_ID DESC NULLS LAST,
            SOURCE_FILE DESC NULLS LAST
    ) = 1
) S

ON T.MEMBER_ID = S.MEMBER_ID

WHEN MATCHED AND (
       T.INGESTION_TIME IS NULL
    OR S.INGESTION_TIME > T.INGESTION_TIME
    OR (
        EQUAL_NULL(S.INGESTION_TIME, T.INGESTION_TIME)
        AND COALESCE(S.BATCH_ID, '') > COALESCE(T.BATCH_ID, '')
    )
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
    T.AGE = S.AGE,
    T.IS_ACTIVE = S.IS_ACTIVE,
    T.STALE_MEMBER = S.STALE_MEMBER,
    T.SOURCE_FILE = S.SOURCE_FILE,
    T.INGESTION_TIME = S.INGESTION_TIME,
    T.BATCH_ID = S.BATCH_ID,
    T.POST_CODE = COALESCE(S.POST_CODE, T.POST_CODE)

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
    AGE,
    IS_ACTIVE,
    STALE_MEMBER,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID,
    POST_CODE
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
    S.AGE,
    S.IS_ACTIVE,
    S.STALE_MEMBER,
    S.SOURCE_FILE,
    S.INGESTION_TIME,
    S.BATCH_ID,
    S.POST_CODE
);


-- ============================================================
-- 7. FINAL MEMBER VALIDATION
-- ============================================================

-- Central member table summary.

SELECT
    COUNT(*) AS TOTAL_MEMBERS,
    COUNT(DISTINCT MEMBER_ID) AS UNIQUE_MEMBERS,
    COUNT_IF(
        MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = ''
    ) AS MISSING_MEMBER_IDS
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT;


-- Check for duplicate member IDs in the target.

SELECT
    MEMBER_ID,
    COUNT(*) AS DUPLICATE_COUNT
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
GROUP BY MEMBER_ID
HAVING COUNT(*) > 1;


-- Latest record per member in staging.

SELECT
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY,
    INGESTION_TIME,
    BATCH_ID
FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY MEMBER_ID
    ORDER BY
        INGESTION_TIME DESC NULLS LAST,
        BATCH_ID DESC NULLS LAST,
        SOURCE_FILE DESC NULLS LAST
) = 1

ORDER BY MEMBER_ID;


-- Verify the migration result.

SELECT
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY,
    BATCH_ID,
    INGESTION_TIME
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
WHERE MEMBER_ID = '223458';


SELECT *
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_INDIA
WHERE MEMBER_ID = '223458';


SELECT *
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_USA
WHERE MEMBER_ID = '223458';


-- Inspect the final target table structure.

DESC TABLE SKYPOINTS_DB.TARGET.MEMBER_CURRENT;
