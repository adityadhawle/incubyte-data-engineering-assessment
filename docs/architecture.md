# Architecture and Engineering Decisions

## Logical flow

```text
Core member flat file / country sample files / redemption JSON
                     |
                     v
              RAW / LANDING
                     |
                     v
       STAGING: parse, standardize, derive
                     |
          +----------+-----------+
          |                      |
          v                      v
  DQ checks + quarantine   Latest-record logic
          |                      |
          v                      v
    AUDIT / REJECTED       TARGET MEMBER_CURRENT
                                 |
                          country views

Country-specific sample inputs -> country staging -> DQ ->
separate country target tables (IDs remain country-scoped)

Redemption JSON -> LATERAL FLATTEN -> STG_REDEMPTIONS -> FACT_REDEMPTIONS
                                             |
                                             +-> join to MEMBER_CURRENT
```

## Key transformations

- Core enrollment/flight dates: `YYYYMMDD` to DATE using `TRY_TO_DATE`.
- Core DOB: `MMDDYYYY` to DATE.
- Country USA dates: source is compact `MDDYYYY`/`MMDDYYYY` text; pad to eight digits before parsing as `MMDDYYYY`.
- India dates: `MM/DD/YYYY`. Australia dates: `YYYY-MM-DD`.
- Age: year difference adjusted when the birthday has not yet occurred in the current year.
- Stale member: last flight is more than 90 days old.
- JSON: `LATERAL FLATTEN(INPUT => PAYLOAD:redemptions)` produces one row per redemption.

## Identity and country migration

`MEMBER_CURRENT` is keyed by the assumed global member identifier. A later-ingested record for the same ID changes its country; the Ravi test record demonstrates `IND` -> `USA`. The country-specific CSV/XLSX IDs are local IDs and must not be conflated with core global IDs without a crosswalk.

## Data quality

Mandatory checks include member ID, member name, country, tier and valid enrollment date. The country DQ preview classifies records as VALID, WARNING or REJECT. Rejected Australian enrollment data is written to the quarantine table with source file, batch and reason. Audit metrics record total, non-rejected and rejected rows; comments preserve warning detail.

## Production gaps / next improvements

- Convert worksheet execution into versioned deployment scripts with separate schema migration and DML steps.
- Add a batch control table and idempotent ingestion keyed by source file + batch + source row/event ID.
- Add deterministic tie-breaking for equal ingestion timestamps; timestamp alone is not a sufficient event version.
- Make audit and quarantine part of the orchestrated pipeline, not manually executed follow-up statements.
- Add automated tests, CI linting, environment-specific configuration, task/procedure orchestration, observability, retries and alerting.
- Benchmark representative volumes before choosing warehouse sizing, clustering, streams/tasks or external orchestration.
