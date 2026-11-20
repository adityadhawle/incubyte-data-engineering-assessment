
-- ============================================================
-- SkyPoints Data Engineering Assessment
-- Redemption JSON Pipeline
-- Platform: Snowflake
--
-- Flow:
-- RAW JSON -> FLATTEN -> STAGING -> FACT MERGE -> VALIDATION
--
-- Note:
-- Sample data is included for assessment demonstration.
-- Do not replay sample data blindly in production.
-- ============================================================


-- ============================================================
-- 1. RAW TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.RAW.RAW_REDEMPTION_JSON (
    MEMBER_ID       VARCHAR(18),
    FEED_DATE       VARCHAR(8),
    PAYLOAD         VARIANT,
    SOURCE_FILE     VARCHAR(500),
    INGESTION_TIME  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    BATCH_ID        VARCHAR(100)
);


-- ============================================================
-- 2. SAMPLE JSON INGESTION
-- Prevent duplicate ingestion for the same source batch.
-- ============================================================

INSERT INTO SKYPOINTS_DB.RAW.RAW_REDEMPTION_JSON
(
    MEMBER_ID,
    FEED_DATE,
    PAYLOAD,
    SOURCE_FILE,
    BATCH_ID
)
SELECT
    '223457',
    '20240115',
    PARSE_JSON('{
        "member_id": "223457",
        "feed_date": "20240115",
        "redemptions": [
            {
                "txn_id": "RX10091",
                "txn_date": "20240110",
                "partner": "AeroLink",
                "miles_redeemed": 12000,
                "status": "COMPLETED"
            },
            {
                "txn_id": "RX10092",
                "txn_date": "20240113",
                "partner": "SkyPoints",
                "miles_redeemed": 5000,
                "status": "PENDING"
            }
        ]
    }'),
    'redemption_sample.json',
    'BATCH_001'
WHERE NOT EXISTS (
    SELECT 1
    FROM SKYPOINTS_DB.RAW.RAW_REDEMPTION_JSON R
    WHERE R.MEMBER_ID = '223457'
      AND R.FEED_DATE = '20240115'
      AND R.BATCH_ID = 'BATCH_001'
      AND R.SOURCE_FILE = 'redemption_sample.json'
);


-- ============================================================
-- 3. RAW JSON FLATTEN PREVIEW
-- ============================================================

SELECT
    R.MEMBER_ID,
    R.FEED_DATE,
    F.VALUE:txn_id::VARCHAR AS TXN_ID,
    TRY_TO_DATE(
        F.VALUE:txn_date::VARCHAR,
        'YYYYMMDD'
    ) AS TXN_DATE,
    F.VALUE:partner::VARCHAR AS PARTNER,
    TRY_TO_NUMBER(
        F.VALUE:miles_redeemed::VARCHAR
    ) AS MILES_REDEEMED,
    F.VALUE:status::VARCHAR AS STATUS
FROM SKYPOINTS_DB.RAW.RAW_REDEMPTION_JSON R,
LATERAL FLATTEN(
    INPUT => R.PAYLOAD:redemptions
) F;


-- ============================================================
-- 4. STAGING TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.STAGING.STG_REDEMPTIONS (
    MEMBER_ID       VARCHAR(18),
    FEED_DATE       DATE,
    TXN_ID          VARCHAR(50),
    TXN_DATE        DATE,
    PARTNER         VARCHAR(100),
    MILES_REDEEMED  NUMBER(12,0),
    STATUS          VARCHAR(30),
    SOURCE_FILE     VARCHAR(500),
    INGESTION_TIME  TIMESTAMP_NTZ,
    BATCH_ID        VARCHAR(100)
);


-- ============================================================
-- 5. FLATTEN JSON AND LOAD STAGING
-- Safe parsing + source-level deduplication +
-- protection against repeated batch ingestion.
-- ============================================================

INSERT INTO SKYPOINTS_DB.STAGING.STG_REDEMPTIONS
(
    MEMBER_ID,
    FEED_DATE,
    TXN_ID,
    TXN_DATE,
    PARTNER,
    MILES_REDEEMED,
    STATUS,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID
)
SELECT
    D.MEMBER_ID,
    D.FEED_DATE,
    D.TXN_ID,
    D.TXN_DATE,
    D.PARTNER,
    D.MILES_REDEEMED,
    D.STATUS,
    D.SOURCE_FILE,
    D.INGESTION_TIME,
    D.BATCH_ID
FROM (
    SELECT
        R.MEMBER_ID,
        TRY_TO_DATE(R.FEED_DATE, 'YYYYMMDD') AS FEED_DATE,
        F.VALUE:txn_id::VARCHAR AS TXN_ID,
        TRY_TO_DATE(
            F.VALUE:txn_date::VARCHAR,
            'YYYYMMDD'
        ) AS TXN_DATE,
        F.VALUE:partner::VARCHAR AS PARTNER,
        TRY_TO_NUMBER(
            F.VALUE:miles_redeemed::VARCHAR
        ) AS MILES_REDEEMED,
        F.VALUE:status::VARCHAR AS STATUS,
        R.SOURCE_FILE,
        R.INGESTION_TIME,
        R.BATCH_ID,

        ROW_NUMBER() OVER (
            PARTITION BY
                R.MEMBER_ID,
                F.VALUE:txn_id::VARCHAR,
                R.BATCH_ID,
                R.SOURCE_FILE
            ORDER BY
                R.INGESTION_TIME DESC,
                F.INDEX DESC
        ) AS RN

    FROM SKYPOINTS_DB.RAW.RAW_REDEMPTION_JSON R,
    LATERAL FLATTEN(
        INPUT => R.PAYLOAD:redemptions
    ) F
) D

WHERE D.RN = 1

AND D.TXN_ID IS NOT NULL

AND NOT EXISTS (
    SELECT 1
    FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS S
    WHERE S.MEMBER_ID = D.MEMBER_ID
      AND S.TXN_ID = D.TXN_ID
      AND S.BATCH_ID = D.BATCH_ID
      AND EQUAL_NULL(S.SOURCE_FILE, D.SOURCE_FILE)
);


-- ============================================================
-- 6. STAGING VALIDATION
-- ============================================================

SELECT
    MEMBER_ID,
    FEED_DATE,
    TXN_ID,
    TXN_DATE,
    PARTNER,
    MILES_REDEEMED,
    STATUS,
    BATCH_ID
FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS
ORDER BY TXN_DATE;


-- ============================================================
-- 7. JOIN REDEMPTIONS WITH CURRENT MEMBER PROFILE
-- ============================================================

SELECT
    M.MEMBER_NAME,
    M.MEMBER_ID,
    M.COUNTRY,
    M.TIER_CODE,
    R.TXN_ID,
    R.TXN_DATE,
    R.PARTNER,
    R.MILES_REDEEMED,
    R.STATUS
FROM SKYPOINTS_DB.TARGET.MEMBER_CURRENT M
INNER JOIN SKYPOINTS_DB.STAGING.STG_REDEMPTIONS R
    ON M.MEMBER_ID = R.MEMBER_ID
ORDER BY R.TXN_DATE;


-- ============================================================
-- 8. FACT TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SKYPOINTS_DB.TARGET.FACT_REDEMPTIONS (
    MEMBER_ID       VARCHAR(18),
    TXN_ID          VARCHAR(50),
    FEED_DATE       DATE,
    TXN_DATE        DATE,
    PARTNER         VARCHAR(100),
    MILES_REDEEMED  NUMBER(12,0),
    STATUS          VARCHAR(30),
    SOURCE_FILE     VARCHAR(500),
    INGESTION_TIME  TIMESTAMP_NTZ,
    BATCH_ID        VARCHAR(100)
);


-- ============================================================
-- 9. INCREMENTAL FACT LOAD
-- Business key: MEMBER_ID + TXN_ID
-- Latest ingestion record wins.
-- ============================================================

MERGE INTO SKYPOINTS_DB.TARGET.FACT_REDEMPTIONS T

USING (
    SELECT *
    FROM SKYPOINTS_DB.STAGING.STG_REDEMPTIONS
    WHERE TXN_ID IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MEMBER_ID, TXN_ID
        ORDER BY
            INGESTION_TIME DESC NULLS LAST,
            BATCH_ID DESC NULLS LAST
    ) = 1
) S

ON T.MEMBER_ID = S.MEMBER_ID
AND T.TXN_ID = S.TXN_ID

WHEN MATCHED AND (
       S.INGESTION_TIME > T.INGESTION_TIME
    OR (
        EQUAL_NULL(S.INGESTION_TIME, T.INGESTION_TIME)
        AND S.BATCH_ID > T.BATCH_ID
    )
)
THEN UPDATE SET
    T.FEED_DATE = S.FEED_DATE,
    T.TXN_DATE = S.TXN_DATE,
    T.PARTNER = S.PARTNER,
    T.MILES_REDEEMED = S.MILES_REDEEMED,
    T.STATUS = S.STATUS,
    T.SOURCE_FILE = S.SOURCE_FILE,
    T.INGESTION_TIME = S.INGESTION_TIME,
    T.BATCH_ID = S.BATCH_ID

WHEN NOT MATCHED THEN
INSERT (
    MEMBER_ID,
    TXN_ID,
    FEED_DATE,
    TXN_DATE,
    PARTNER,
    MILES_REDEEMED,
    STATUS,
    SOURCE_FILE,
    INGESTION_TIME,
    BATCH_ID
)
VALUES (
    S.MEMBER_ID,
    S.TXN_ID,
    S.FEED_DATE,
    S.TXN_DATE,
    S.PARTNER,
    S.MILES_REDEEMED,
    S.STATUS,
    S.SOURCE_FILE,
    S.INGESTION_TIME,
    S.BATCH_ID
);


-- ============================================================
-- 10. FACT TABLE VALIDATION
-- ============================================================

SELECT *
FROM SKYPOINTS_DB.TARGET.FACT_REDEMPTIONS
ORDER BY TXN_DATE;


-- ============================================================
-- 11. DUPLICATE TRANSACTION VALIDATION
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
-- 12. PARTNER AND STATUS SUMMARY
-- ============================================================

SELECT
    PARTNER,
    STATUS,
    COUNT(*) AS TOTAL_TRANSACTIONS,
    SUM(MILES_REDEEMED) AS TOTAL_MILES
FROM SKYPOINTS_DB.TARGET.FACT_REDEMPTIONS
GROUP BY PARTNER, STATUS
ORDER BY PARTNER, STATUS;
