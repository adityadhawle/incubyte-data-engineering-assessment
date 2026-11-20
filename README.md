# SkyPoints Loyalty Data Platform — Snowflake Assessment

## What is included

- `sql/01_environment_and_core_ddl.sql` — warehouse settings, database/schemas and initial core DDL.
- `sql/02_core_member_transform_and_current.sql` — member staging transformations, current member logic, country views and migration scenario.
- `sql/03_file_landing_and_raw_merge.sql` — pipe-delimited file format/stage/landing, `COPY INTO`, RAW upsert and current-member merge.
- `sql/04_redemption_json_pipeline.sql` — JSON payload flattening, redemption staging/fact processing.
- `sql/05_data_quality_and_audit.sql` — data quality checks, audit log and rejected-record handling.
- `sql/06_country_file_pipeline_reference.sql` — USA, India and Australia sample-file workflow.
- `sql/07_final_validation_and_catalog.sql` — validation and Snowflake metadata inspection.
- `source_archive/` — exact copies of both submitted worksheet exports; preserved unchanged.
- `docs/architecture.md` — architecture, assumptions, design choices and limitations.

## Execution warning

The two source worksheets contain exploratory queries, repeated DDL/INSERT statements, test data, and statements executed at different stages of development. The organized SQL files are a navigable extraction of that work, **not a single clean-room deployment bundle**. Review each file and run only the required statements in order. In particular, do not rerun sample `INSERT` statements against the already populated Snowflake database. Existing target and staging tables should not be dropped or truncated.

## Implemented flow

1. Raw core member records are stored in `SKYPOINTS_DB.RAW.RAW_MEMBER_PROFILE`; a pipe-delimited landing path is also defined with a file format, stage, landing table and `COPY INTO`.
2. Member records are transformed in `STAGING.STG_MEMBER_PROFILE`: date parsing, DOB-based age calculation, and `STALE_MEMBER` derived from a flight date older than 90 days.
3. `TARGET.MEMBER_CURRENT` keeps the latest known record per global `MEMBER_ID`. A test migration for member `223458` demonstrates Ravi moving from `IND` to `USA`; the current target and country views reflect the latest country.
4. Nested redemption JSON is flattened with `LATERAL FLATTEN` into redemption staging and `TARGET.FACT_REDEMPTIONS`, then joined to member profile.
5. Country-local USA/India/Australia samples are staged independently, checked, and loaded into separate physical target tables.
6. Invalid Australian enrollment data for Jonnathan is written to `AUDIT.REJECTED_MEMBER_RECORDS`; the country batch is recorded in `AUDIT.DQ_AUDIT_LOG`.

## Verified sample outcomes (as observed in Snowflake on 20 Nov 2026)

| Check | Result |
|---|---:|
| Core global current members | 5 |
| Ravi's current country after migration test | USA |
| Flattened redemption transactions | 2 |
| Country staging sample records | 9 |
| Country target records | 8 (USA 3, India 3, Australia 2) |
| Country target statuses | 7 VALID, 1 WARNING |
| Country rejected records | 1 (Jonnathan, invalid enrollment date) |
| Country audit rows | 1 |
| Duplicate `(COUNTRY, MEMBER_ID)` target keys | 0 |
| Missing mandatory target fields | 0 |

## Important assumptions and caveats

- The core feed's stable cross-country identifier is treated as `MEMBER_ID`. The assessment's field specification reportedly marks `Member_Name` as a key while marking `Member_ID` non-key; this conflict should be raised for clarification. The migration logic assumes a globally stable `MEMBER_ID`.
- The USA/India/Australia file IDs are country-local values (`1`, `2`, `3`) and repeat across countries. They are **not** merged into the global `MEMBER_CURRENT` table because no crosswalk to global member IDs was supplied. Country target uniqueness is checked on `(COUNTRY, MEMBER_ID)`.
- `POST_CODE` exists in the stated schema but is absent from the supplied core sample header/data; it remains NULL rather than being fabricated.
- USA sample file has no DOB; DOB and AGE remain NULL without marking the row invalid. Australia member Mike has a missing DOB and is retained with `WARNING`. Australia member Jonnathan has an invalid enrollment date (`2021-13-13`) and is quarantined, not loaded to target.
- Country file sample rows were seeded into raw tables from the provided sample values during the assessment workflow. Do not describe those nine rows as a verified automated Excel/CSV stage upload. The core pipe-delimited stage/COPY path is separately present in the worksheet.
- The DQ audit row uses `VALID_RECORDS = 8` to mean non-rejected rows (7 clean + 1 warning); `REJECTED_RECORDS = 1`. The comments preserve the clean/warning distinction.
- `STALE_MEMBER` is true when the flight date is more than 90 days before the run date; a NULL flight date remains NULL.
- The Snowflake work was executed manually in worksheets. No Snowflake stored procedures or scheduled tasks were confirmed as implemented. For production, orchestrate with Snowflake Tasks or an external orchestrator such as Airflow, add retry/alerting and batch-level controls.
- The country MERGEs use country-local `MEMBER_ID` as their match key and latest `INGESTION_TIME` ordering. For concurrent production writers, add a deterministic source event/version key and explicit conflict handling.
- Sample data is tiny and is not a throughput benchmark. The billions-of-records/day requirement should be addressed architecturally (partitioned/clustered storage where justified, micro-batching/streaming, parallel ingestion, incremental processing, workload isolation, monitoring), not claimed as measured performance.

## Recommended review before public GitHub submission

1. Confirm no credentials, account identifiers, private URLs, or personal data are included.
2. Keep sample rows clearly labelled as synthetic/assessment sample data.
3. Decide whether to keep the worksheet archives in the public repository; they contain exploratory/repeated SQL, so the curated scripts should be the primary entry point.
4. Reconcile the assessment's key-field ambiguity (`Member_Name` vs `Member_ID`) in the README or with the assessor.
5. Add automated assertions or a test harness for date parsing, age boundaries, stale threshold, duplicate keys, rejected rows, and JSON flattening.

## Snowflake context

Database: `SKYPOINTS_DB`
Schemas: `RAW`, `STAGING`, `TARGET`, `AUDIT`
Warehouse used: `COMPUTE_WH` (X-SMALL; AUTO_SUSPEND 60 seconds; AUTO_RESUME TRUE).
