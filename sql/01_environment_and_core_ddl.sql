-- SkyPoints Data Engineering Assessment
-- Snowflake SQL | Reference implementation extracted from the two submitted worksheets.
-- Review README.md before execution. Sample INSERT statements are not safe to replay blindly.

-- Environment, database/schema setup and initial core table definitions.
show warehouses;

ALTER WAREHOUSE COMPUTE_WH
SET AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;


CREATE DATABASE IF NOT EXISTS SKYPOINTS_DB;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.RAW;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.STAGING;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.TARGET;

CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.AUDIT;

SHOW SCHEMAS IN DATABASE SKYPOINTS_DB;


USE DATABASE SKYPOINTS_DB;
USE SCHEMA RAW;

CREATE TABLE IF NOT EXISTS RAW_MEMBER_PROFILE (
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

    SOURCE_FILE       VARCHAR(500),
    INGESTION_TIME    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    BATCH_ID          VARCHAR(100)
);

DESC TABLE RAW_MEMBER_PROFILE;

INSERT INTO RAW_MEMBER_PROFILE (
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
VALUES
('Elena', '223457', '20101012', '20121013', 'GLD', 'Sam', 'CA', 'USA', '03051985', 'A', 'member_profile_sample.txt', 'BATCH_001'),
('Ravi', '223458', '20101012', '20121013', 'SLV', 'Sam', 'TN', 'IND', '03051985', 'A', 'member_profile_sample.txt', 'BATCH_001'),
('Mateo', '223459', '20101012', '20121013', 'GLD', 'Sam', 'NCR', 'PHIL', '03051985', 'A', 'member_profile_sample.txt', 'BATCH_001'),
('Nora', '22345', '20101012', '20121013', 'PLT', 'Sam', 'ONT', 'CAN', '03051985', 'A', 'member_profile_sample.txt', 'BATCH_001'),
('Jacob', '2256', '20101012', '20121013', 'SLV', 'Sam', 'VIC', 'AU', '03051985', 'A', 'member_profile_sample.txt', 'BATCH_001');

select * 
from raw_member_profile
order by member_name;



USE SCHEMA SKYPOINTS_DB.STAGING;

CREATE TABLE IF NOT EXISTS STG_MEMBER_PROFILE (
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
    BATCH_ID          VARCHAR(100)
);

-- Audit table definitions are in 05_data_quality_and_audit.sql.
