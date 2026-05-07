
# Lab 10: Build a data lake — S3 + Glue Crawler + Athena

## Objective

Stand up a minimal data lake: drop CSV files into S3, run a Glue Crawler to infer the schema, then query the data with Athena. The point is the **pattern** — separating storage (S3) from catalog (Glue) from compute (Athena) — and seeing how cheaply you can begin without a database.

## Time budget: ~25 minutes

This is the only hands-on slot in Module 10. The first 20 minutes of the module are slide-driven (Aurora vs DynamoDB vs Redshift vs S3-data-lake decision lens); the lab proves the data-lake half of that lens by having you build one.

## Pre-staged

The Terraform under `Module_10/terraform/` provisions:

- An S3 bucket `archadv-${learner}-datalake` with public access blocked
- Two seed CSV files dropped under `s3://archadv-${learner}-datalake/sales/year=2024/`
- A Glue catalog database `archadv_${learner}_db`
- A Glue Crawler with the IAM role and S3 read permissions ready to go
- An Athena query results bucket and workgroup pointed at it

## Steps

1. `terraform init && terraform apply -var "learner=<your-name>"` — wait ~90 seconds for the bucket, seed objects, Glue catalog, and crawler to provision.
2. From the AWS console, open **AWS Glue → Crawlers → archadv-${learner}-sales-crawler**. Click **Run**. Wait until it reports `Ready` (~60 seconds).
3. Open **AWS Glue → Data Catalog → Databases → archadv_${learner}_db**. Confirm a table named `sales` was created. Click into it — verify the columns Glue inferred (`order_id`, `region`, `product`, `quantity`, `revenue`) and the partition key `year`.
4. Open **Athena → Query editor**. Select workgroup `archadv-${learner}-wg` and database `archadv_${learner}_db`.
5. Run:
   ```sql
   SELECT region, SUM(revenue) AS total_revenue
   FROM sales
   WHERE year = '2024'
   GROUP BY region
   ORDER BY total_revenue DESC;
   ```
   You should see one row per region. Note the `Data scanned` metric — Athena charges per byte scanned.
6. Drop a third CSV into `s3://archadv-${learner}-datalake/sales/year=2024/` from your Cloud9 / CloudShell:
   ```bash
   aws s3 cp /tmp/sales-extra.csv s3://archadv-${LEARNER}-datalake/sales/year=2024/
   ```
   Re-run the crawler. Confirm the new rows appear in your query — without changing the table or schema.

## Validation

- [ ] Glue Crawler ran successfully (status `Ready`, no errors)
- [ ] Glue Data Catalog shows the `sales` table with inferred columns
- [ ] Athena query returns aggregated rows
- [ ] After dropping a new CSV and re-running the crawler, the query reflects new data
- [ ] `Data scanned` per query is in single-digit KB on this dataset

## Why this matters

You did not provision a database. You did not load data through an ETL job. You dropped files into S3, pointed a catalog at them, and queried with SQL. That is the data-lake pattern — and it scales from these two CSV files to petabytes.

## Cleanup

```
terraform destroy -var "learner=<your-name>"
```

(Empty the S3 bucket first if Terraform refuses to delete it: `aws s3 rm s3://archadv-${LEARNER}-datalake/ --recursive`.)

## Stretch goals

- Add a `year=2023/` partition with a third CSV. Run the crawler. Confirm Athena treats it as a separate partition and that `WHERE year = '2024'` skips the 2023 file (partition pruning).
- Convert the data to Parquet using a CTAS query: `CREATE TABLE sales_parquet WITH (format = 'PARQUET', external_location = 's3://archadv-${LEARNER}-datalake/sales-parquet/') AS SELECT * FROM sales;`. Re-query and compare `Data scanned`.
- Wire QuickSight to the Athena workgroup and build a region-by-revenue chart.
