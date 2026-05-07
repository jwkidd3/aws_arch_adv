# Lab 10 proof harness

Builds: S3 data lake bucket with two seed CSVs under `sales/year=2024/` + Glue catalog DB + Glue Crawler with IAM role + Athena workgroup with results bucket.

## What it asserts

- Lake bucket exists with public access fully blocked
- Seed CSVs are under the partition path
- Glue database exists with hyphen-stripped name (per the lab guide patch)
- Glue role has both `AWSGlueServiceRole` managed policy and inline S3 read
- Crawler can be triggered, reaches `READY` state, and last-run is `SUCCEEDED`
- Sales table appears in catalog with expected columns + `year` partition key
- Athena query against the workgroup returns the expected 4 region rows + header

## What it does NOT assert

- The CTAS-to-Parquet stretch goal (it's a stretch, and adds time/cost)
- QuickSight integration (not API-driven from a CI runner)

## Cost (approximate, per harness run)

- S3: free for this size
- Glue catalog: $1/100k ops/month — negligible
- Glue Crawler: $0.44/DPU-hour, ~1 min run = ~$0.01
- Athena query: $5/TB scanned; this query scans <1KB = ~$0.000005
- IAM: free

Per run: **< $0.02**. Weekly CI: < $1/year.
