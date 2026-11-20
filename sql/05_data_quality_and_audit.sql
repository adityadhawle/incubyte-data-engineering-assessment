
-- ============================================================
-- SkyPoints Data Engineering Assessment
-- DATA QUALITY AND AUDIT
-- Platform: Snowflake
--
-- Covers:
-- 1. Member profile quality checks
-- 2. Transaction quality checks
-- 3. Duplicate and migration checks
-- 4. Referential integrity
-- 5. Audit logging
-- 6. Rejected record quarantine
-- 7. Data reconciliation
-- ============================================================


-- ============================================================
-- 1. MEMBER PROFILE DQ SUMMARY
-- ============================================================

SELECT
    COUNT(*) AS TOTAL_RECORDS,

    COUNT_IF(
        MEMBER_NAME IS NULL OR TRIM(MEMBER_NAME) = ''
    ) AS MISSING_MEMBER_NAME,

    COUNT_IF(
        MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = ''
    ) AS MISSING_MEMBER_ID,

    COUNT_IF(
        COUNTRY IS NULL OR TRIM(COUNTRY) = ''
    ) AS MISSING_COUNTRY,

    COUNT_IF(
        ENROLLMENT_DATE IS NULL
        OR ENROLLMENT_DATE > CURRENT_DATE()
    ) AS INVALID_ENROLLMENT_DATE,

    COUNT_IF(
        DOB > CURRENT_DATE()
        OR DOB < DATEADD(YEAR, -120, CURRENT_DATE())
    ) AS INVALID_DOB,

    COUNT_IF(
        AGE < 0 OR AGE > 120
    ) AS INVALID_AGE,

    COUNT_IF(
        IS_ACTIVE IS NULL
        OR IS_ACTIVE NOT IN ('A', 'I')
    ) AS INVALID_ACTIVE_FLAG,

    COUNT_IF(
        LAST_FLIGHT_DATE > CURRENT_DATE()
    ) AS FUTURE_FLIGHT_DATE

FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE;


-- ============================================================
-- 2. MEMBER PROFILE BUSINESS RULE VALIDATION
-- NULL DOB and NULL AGE are allowed as warnings.
-- ============================================================

SELECT
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY,
    ENROLLMENT_DATE,
    DOB,
    AGE,

    CASE
        WHEN MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = ''
            THEN 'MISSING_MEMBER_ID'

        WHEN MEMBER_NAME IS NULL OR TRIM(MEMBER_NAME) = ''
            THEN 'MISSING_MEMBER_NAME'

        WHEN COUNTRY IS NULL
          OR COUNTRY NOT IN ('IND', 'USA', 'PHIL', 'CAN', 'AU')
            THEN 'INVALID_COUNTRY'

        WHEN ENROLLMENT_DATE IS NULL
            THEN 'MISSING_ENROLLMENT_DATE'

        WHEN ENROLLMENT_DATE > CURRENT_DATE()
            THEN 'FUTURE_ENROLLMENT_DATE'

        WHEN DOB > CURRENT_DATE()
            THEN 'FUTURE_DOB'

        WHEN DOB < DATEADD(YEAR, -120, CURRENT_DATE())
            THEN 'DOB_OVER_120_YEARS'

        WHEN AGE < 0 OR AGE > 120
            THEN 'INVALID_AGE'

        WHEN IS_ACTIVE IS NULL
          OR IS_ACTIVE NOT IN ('A', 'I')
            THEN 'INVALID_ACTIVE_FLAG'

        WHEN LAST_FLIGHT_DATE > CURRENT_DATE()
            THEN 'FUTURE_FLIGHT_DATE'

        ELSE 'VALID'
    END AS VALIDATION_STATUS

FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE

WHERE
       MEMBER_ID IS NULL
    OR TRIM(MEMBER_ID) = ''
    OR MEMBER_NAME IS NULL
    OR TRIM(MEMBER_NAME) = ''
    OR COUNTRY IS NULL
    OR COUNTRY NOT IN ('IND', 'USA', 'PHIL', 'CAN', 'AU')
    OR ENROLLMENT_DATE IS NULL
    OR ENROLLMENT_DATE > CURRENT_DATE()
    OR DOB > CURRENT_DATE()
    OR DOB < DATEADD(YEAR, -120, CURRENT_DATE())
    OR AGE < 0
    OR AGE > 120
    OR IS_ACTIVE IS NULL
    OR IS_ACTIVE NOT IN ('A', 'I')
    OR LAST_FLIGHT_DATE > CURRENT_DATE();


-- ============================================================
-- 3. CURRENT MEMBER DUPLICATE CHECK
-- Expected result: zero rows.
-- ============================================================

SELECT
    MEMBER_ID,
    COUNT(*) AS RECORD_COUNT
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT
GROUP BY MEMBER_ID
HAVING COUNT(*) > 1;


-- ============================================================
-- 4. MEMBER COUNTRY MIGRATION ANALYSIS
-- Multiple staging rows can be valid historical records.
-- This query identifies migration vs potential duplicates.
-- ============================================================

SELECT
    MEMBER_ID,
    COUNT(*) AS RECORD_COUNT,
    COUNT(DISTINCT COUNTRY) AS COUNTRY_COUNT,

    CASE
        WHEN COUNT(DISTINCT COUNTRY) > 1
            THEN 'COUNTRY_MIGRATION'
        ELSE 'MULTIPLE_STAGING_RECORDS'
    END AS RECORD_CLASSIFICATION

FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE

GROUP BY MEMBER_ID

HAVING COUNT(*) > 1;


-- ============================================================
-- 5. MEMBER NAME CONSISTENCY CHECK
-- A name can belong to multiple members.
-- This is an investigation query, not an automatic rejection.
-- ============================================================

SELECT
    MEMBER_NAME,
    COUNT(*) AS RECORD_COUNT,
    COUNT(DISTINCT MEMBER_ID) AS DISTINCT_MEMBER_IDS
FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE
GROUP BY MEMBER_NAME
HAVING COUNT(DISTINCT MEMBER_ID) > 1;


-- ============================================================
-- 6. REDEMPTION TRANSACTION DQ SUMMARY
-- Business key: MEMBER_ID + TXN_ID
-- ============================================================

SELECT
    COUNT(*) AS TOTAL_TRANSACTIONS,

    COUNT_IF(
        MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = ''
    ) AS MISSING_MEMBER_IDS,

    COUNT_IF(
        TXN_ID IS NULL OR TRIM(TXN_ID) = ''
    ) AS MISSING_TXN_IDS,

    COUNT_IF(
        TXN_DATE IS NULL
    ) AS INVALID_TXN_DATES,

    COUNT_IF(
        MILES_REDEEMED IS NULL OR MILES_REDEEMED < 0
    ) AS INVALID_MILES,

    COUNT_IF(
        PARTNER IS NULL OR TRIM(PARTNER) = ''
    ) AS MISSING_PARTNER,

    COUNT_IF(
        STATUS IS NULL
        OR STATUS NOT IN ('COMPLETED', 'PENDING', 'FAILED')
    ) AS INVALID_STATUS

FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS;


-- ============================================================
-- 7. DUPLICATE TRANSACTION CHECK IN STAGING
-- Expected result: zero rows.
-- ============================================================

SELECT
    MEMBER_ID,
    TXN_ID,
    COUNT(*) AS RECORD_COUNT
FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS
GROUP BY MEMBER_ID, TXN_ID
HAVING COUNT(*) > 1;


-- ============================================================
-- 8. DUPLICATE TRANSACTION CHECK IN FACT
-- Expected result: zero rows.
-- ============================================================

SELECT
    MEMBER_ID,
    TXN_ID,
    COUNT(*) AS RECORD_COUNT
FROM SKYPOINTS_DB.TARGET.FACT_REDEMPTIONS
GROUP BY MEMBER_ID, TXN_ID
HAVING COUNT(*) > 1;


-- ============================================================
-- 9. ORPHAN TRANSACTION CHECK
-- Transactions without a matching current member.
-- ============================================================

SELECT
    R.MEMBER_ID,
    R.TXN_ID
FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS R

LEFT JOIN SKYPOINTS_DB.TARGET.MEMBER_CURRENT M
    ON R.MEMBER_ID = M.MEMBER_ID

WHERE M.MEMBER_ID IS NULL;


-- ============================================================
-- 10. TRANSACTION BUSINESS RULE VALIDATION
-- ============================================================

SELECT
    R.MEMBER_ID,
    R.TXN_ID,
    R.STATUS,

    CASE
        WHEN M.MEMBER_ID IS NULL
            THEN 'ORPHAN_MEMBER'

        WHEN R.TXN_ID IS NULL OR TRIM(R.TXN_ID) = ''
            THEN 'MISSING_TXN_ID'

        WHEN R.TXN_DATE IS NULL
            THEN 'INVALID_TXN_DATE'

        WHEN R.MILES_REDEEMED IS NULL
          OR R.MILES_REDEEMED < 0
            THEN 'INVALID_MILES'

        WHEN R.PARTNER IS NULL OR TRIM(R.PARTNER) = ''
            THEN 'MISSING_PARTNER'

        WHEN R.STATUS IS NULL
          OR R.STATUS NOT IN ('COMPLETED', 'PENDING', 'FAILED')
            THEN 'INVALID_STATUS'

        ELSE 'VALID'
    END AS VALIDATION_STATUS

FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS R

LEFT JOIN SKYPOINTS_DB.TARGET.MEMBER_CURRENT M
    ON R.MEMBER_ID = M.MEMBER_ID;


-- ============================================================
-- 11. DQ AUDIT LOG TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.AUDIT.DQ_AUDIT_LOG (
    AUDIT_ID NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    BATCH_ID VARCHAR(100),
    TABLE_NAME VARCHAR(255),
    TOTAL_RECORDS NUMBER,
    VALID_RECORDS NUMBER,
    REJECTED_RECORDS NUMBER,
    VALIDATION_STATUS VARCHAR(30),
    EXECUTION_TIME TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    COMMENTS VARCHAR(1000)
);


-- ============================================================
-- 12. MEMBER PROFILE AUDIT LOG
-- One audit entry per batch and table.
-- Valid + rejected = total records.
-- ============================================================

INSERT INTO SKYPOINTS_DB.AUDIT.DQ_AUDIT_LOG
(
    BATCH_ID,
    TABLE_NAME,
    TOTAL_RECORDS,
    VALID_RECORDS,
    REJECTED_RECORDS,
    VALIDATION_STATUS,
    COMMENTS
)

WITH CLASSIFIED AS (
    SELECT
        BATCH_ID,

        CASE
            WHEN MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = ''
              OR MEMBER_NAME IS NULL OR TRIM(MEMBER_NAME) = ''
              OR COUNTRY IS NULL
              OR COUNTRY NOT IN ('IND', 'USA', 'PHIL', 'CAN', 'AU')
              OR ENROLLMENT_DATE IS NULL
              OR ENROLLMENT_DATE > CURRENT_DATE()
              OR DOB > CURRENT_DATE()
              OR DOB < DATEADD(YEAR, -120, CURRENT_DATE())
              OR IS_ACTIVE IS NULL
              OR IS_ACTIVE NOT IN ('A', 'I')
              OR AGE < 0 OR AGE > 120
              OR LAST_FLIGHT_DATE > CURRENT_DATE()
            THEN 1
            ELSE 0
        END AS IS_REJECTED

    FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE
)

SELECT
    C.BATCH_ID,
    'STG_MEMBER_PROFILE',
    COUNT(*),
    COUNT_IF(C.IS_REJECTED = 0),
    COUNT_IF(C.IS_REJECTED = 1),

    CASE
        WHEN COUNT_IF(C.IS_REJECTED = 1) = 0
            THEN 'PASSED'
        ELSE 'FAILED'
    END,

    'Member profile mandatory fields and business-rule validation'

FROM CLASSIFIED C

WHERE NOT EXISTS (
    SELECT 1
    FROM SKYPOINTS_DB.AUDIT.DQ_AUDIT_LOG A
    WHERE A.BATCH_ID = C.BATCH_ID
      AND A.TABLE_NAME = 'STG_MEMBER_PROFILE'
)

GROUP BY C.BATCH_ID;


-- ============================================================
-- 13. AUDIT LOG REVIEW
-- ============================================================

SELECT
    BATCH_ID,
    TABLE_NAME,
    TOTAL_RECORDS,
    VALID_RECORDS,
    REJECTED_RECORDS,
    VALIDATION_STATUS,
    EXECUTION_TIME,
    COMMENTS
FROM SKYPOINTS_DB.AUDIT.DQ_AUDIT_LOG
ORDER BY EXECUTION_TIME DESC;


-- ============================================================
-- 14. REJECTED MEMBER RECORD QUARANTINE TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.AUDIT.REJECTED_MEMBER_RECORDS (
    MEMBER_ID VARCHAR(18),
    MEMBER_NAME VARCHAR(255),
    COUNTRY VARCHAR(20),
    BATCH_ID VARCHAR(100),
    SOURCE_FILE VARCHAR(500),
    REJECTION_REASON VARCHAR(1000),
    REJECTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);


-- ============================================================
-- 15. INSERT INVALID MEMBER RECORDS INTO QUARANTINE
-- Includes invalid DOB and all audit rejection conditions.
-- Prevents repeated inserts for the same source record/reason.
-- ============================================================

INSERT INTO SKYPOINTS_DB.AUDIT.REJECTED_MEMBER_RECORDS
(
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY,
    BATCH_ID,
    SOURCE_FILE,
    REJECTION_REASON
)

WITH CLASSIFIED AS (
    SELECT
        MEMBER_ID,
        MEMBER_NAME,
        COUNTRY,
        BATCH_ID,
        SOURCE_FILE,

        ARRAY_TO_STRING(
            ARRAY_CONSTRUCT_COMPACT(
                IFF(
                    MEMBER_ID IS NULL OR TRIM(MEMBER_ID) = '',
                    'MISSING_MEMBER_ID',
                    NULL
                ),

                IFF(
                    MEMBER_NAME IS NULL OR TRIM(MEMBER_NAME) = '',
                    'MISSING_MEMBER_NAME',
                    NULL
                ),

                IFF(
                    COUNTRY IS NULL
                    OR COUNTRY NOT IN ('IND', 'USA', 'PHIL', 'CAN', 'AU'),
                    'INVALID_COUNTRY',
                    NULL
                ),

                IFF(
                    ENROLLMENT_DATE IS NULL
                    OR ENROLLMENT_DATE > CURRENT_DATE(),
                    'INVALID_ENROLLMENT_DATE',
                    NULL
                ),

                IFF(
                    DOB > CURRENT_DATE()
                    OR DOB < DATEADD(YEAR, -120, CURRENT_DATE()),
                    'INVALID_DOB',
                    NULL
                ),

                IFF(
                    IS_ACTIVE IS NULL OR IS_ACTIVE NOT IN ('A', 'I'),
                    'INVALID_ACTIVE_FLAG',
                    NULL
                ),

                IFF(
                    AGE < 0 OR AGE > 120,
                    'INVALID_AGE',
                    NULL
                ),

                IFF(
                    LAST_FLIGHT_DATE > CURRENT_DATE(),
                    'FUTURE_FLIGHT_DATE',
                    NULL
                )
            ),
            ', '
        ) AS REJECTION_REASON

    FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE
)

SELECT
    C.MEMBER_ID,
    C.MEMBER_NAME,
    C.COUNTRY,
    C.BATCH_ID,
    C.SOURCE_FILE,
    C.REJECTION_REASON

FROM CLASSIFIED C

WHERE C.REJECTION_REASON IS NOT NULL

AND NOT EXISTS (
    SELECT 1
    FROM SKYPOINTS_DB.AUDIT.REJECTED_MEMBER_RECORDS R
    WHERE EQUAL_NULL(R.MEMBER_ID, C.MEMBER_ID)
      AND EQUAL_NULL(R.BATCH_ID, C.BATCH_ID)
      AND EQUAL_NULL(R.SOURCE_FILE, C.SOURCE_FILE)
      AND R.REJECTION_REASON = C.REJECTION_REASON
);


-- ============================================================
-- 16. REJECTED RECORD REVIEW
-- ============================================================

SELECT
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY,
    BATCH_ID,
    SOURCE_FILE,
    REJECTION_REASON,
    REJECTED_AT
FROM SKYPOINTS_DB.AUDIT.REJECTED_MEMBER_RECORDS
ORDER BY REJECTED_AT DESC;


-- ============================================================
-- 17. RAW, STAGING AND TARGET RECONCILIATION
-- ============================================================

SELECT
    'RAW_MEMBER_PROFILE' AS TABLE_NAME,
    COUNT(*) AS TOTAL_RECORDS
FROM SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE

UNION ALL

SELECT
    'STG_MEMBER_PROFILE',
    COUNT(*)
FROM SKYPOINTS_DB.STAGING.STG_MEMBER_PROFILE

UNION ALL

SELECT
    'MEMBER_CURRENT',
    COUNT(*)
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT

UNION ALL

SELECT
    'RAW_REDEMPTION_JSON',
    COUNT(*)
FROM SKYPOINTS_DB.RAW.RAW_REDEMPTION_JSON

UNION ALL

SELECT
    'STG_REDEMPTIONS',
    COUNT(*)
FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS

UNION ALL

SELECT
    'FACT_REDEMPTIONS',
    COUNT(*)
FROM SKYPOINTS_DB.TARGET.FACT_REDEMPTIONS;


-- ============================================================
-- 18. COUNTRY MIGRATION VERIFICATION
-- Example: Ravi (223458) moved from India to USA.
-- ============================================================

SELECT
    'INDIA' AS COUNTRY_VIEW,
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_INDIA
WHERE MEMBER_ID = '223458'

UNION ALL

SELECT
    'USA' AS COUNTRY_VIEW,
    MEMBER_ID,
    MEMBER_NAME,
    COUNTRY
FROM SKYPOINTS_DB.TARGET.VW_MEMBERS_USA
WHERE MEMBER_ID = '223458';
