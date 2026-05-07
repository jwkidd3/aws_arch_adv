# Lab 10 — Build a data lake (S3 + Glue + Athena)

## Objective

Stand up a minimal data lake by hand: drop CSV files into S3, run a Glue Crawler to infer the schema, then query the data with Athena. The point is the **pattern** — separating storage (S3) from catalog (Glue) from compute (Athena) — and seeing how cheaply you can begin without a database.

## Time budget: 30 minutes

This is the only hands-on slot in Module 10. The first 15 minutes of the module are slide-driven (Aurora vs DynamoDB vs Redshift vs S3-data-lake decision lens); the lab proves the data-lake half of that lens by having you build one.

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. Open CloudShell.

## Steps

### 1. Create the data lake bucket and seed data (5 min)

In CloudShell:

```bash
LEARNER=<your-name>
LAKE=archadv-$LEARNER-datalake

aws s3 mb s3://$LAKE
aws s3api put-public-access-block --bucket $LAKE \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

cat > /tmp/q1.csv <<'EOF'
order_id,region,product,quantity,revenue
1001,us-east,widget-a,3,29.97
1002,us-east,widget-b,1,49.99
1003,us-west,widget-a,5,49.95
1004,eu-west,widget-c,2,79.98
1005,ap-south,widget-b,4,199.96
EOF

cat > /tmp/q2.csv <<'EOF'
order_id,region,product,quantity,revenue
2001,us-east,widget-a,7,69.93
2002,us-west,widget-c,3,119.97
2003,us-west,widget-b,2,99.98
2004,eu-west,widget-a,4,39.96
2005,ap-south,widget-c,1,39.99
EOF

aws s3 cp /tmp/q1.csv s3://$LAKE/sales/year=2024/q1.csv
aws s3 cp /tmp/q2.csv s3://$LAKE/sales/year=2024/q2.csv
```

### 2. Create the Glue catalog database (1 min)

- **AWS Glue → Data Catalog → Databases → Add database**
- Name: `archadv_<your-name>_db` (lowercase alphanumeric + underscores only — **no hyphens**, even if your assigned name has one. Replace `mary-smith` with `mary_smith` here.)
- Add.

### 3. Create the IAM role for Glue (2 min)

- **IAM → Roles → Create role**
- Trusted entity: AWS service → Glue
- Permissions: attach `AWSGlueServiceRole` and create an inline policy giving `s3:GetObject`, `s3:ListBucket` on `arn:aws:s3:::archadv-<you>-datalake` and `/*`.
- Name: `archadv-<you>-glue-role`. Create.

### 4. Create and run the crawler (5 min)

- **Glue → Crawlers → Create crawler**
- Name: `archadv-<you>-sales-crawler`
- Source: S3 path `s3://archadv-<you>-datalake/sales/`
- IAM role: `archadv-<you>-glue-role`
- Output database: `archadv_<your-name>_db`
- Schedule: on demand
- Create.
- **Run crawler**. Wait ~60 sec until `Ready`.

### 5. Verify the catalog (2 min)

- **Glue → Data Catalog → Databases → archadv_<your-name>_db → Tables**.
- Open the `sales` table. Verify:
  - Columns: `order_id`, `region`, `product`, `quantity`, `revenue`
  - Partition key: `year`

### 6. Query with Athena (10 min)

- **Athena → Query editor**.
- First time only: **Settings → Manage** → under **Query result configuration**, choose **Customer managed** and set the location to `s3://archadv-<you>-datalake/athena-results/`. (The newer "Athena managed" option puts results in an Athena-owned bucket you can't easily inspect — skip it for this lab.)
- Database selector: `archadv_<your-name>_db`.
- Query:

```sql
SELECT region, SUM(revenue) AS total_revenue
FROM sales
WHERE year = '2024'
GROUP BY region
ORDER BY total_revenue DESC;
```

You should get one row per region. Note **Data scanned** in the run details — that's what Athena charges on (per byte scanned).

### 7. Drop a third file and re-query (3 min)

```bash
cat > /tmp/q3.csv <<'EOF'
order_id,region,product,quantity,revenue
3001,us-east,widget-d,10,499.90
3002,ap-south,widget-d,20,999.80
EOF

aws s3 cp /tmp/q3.csv s3://$LAKE/sales/year=2024/q3.csv
```

Re-run the crawler. Re-run the query. The totals change — without changing the table or schema. **That's the data-lake property.**

## Validation checklist

- [ ] Bucket exists with public-access fully blocked
- [ ] Three CSVs are under `sales/year=2024/`
- [ ] Glue Crawler ran successfully (status `Ready`, no errors)
- [ ] Catalog shows the `sales` table with correct columns and partition key
- [ ] Athena query returns aggregated rows
- [ ] After dropping a new CSV and re-running the crawler, the query reflects new data
- [ ] `Data scanned` per query is single-digit KB on this dataset

## Why this matters

You did not provision a database. You did not load data through an ETL job. You dropped files into S3, pointed a catalog at them, and queried with SQL. That is the data-lake pattern — and it scales from these three CSV files to petabytes.

## Cleanup

```bash
aws s3 rm s3://archadv-<you>-datalake/ --recursive
aws s3 rb s3://archadv-<you>-datalake
```

Then in console:

- Delete the Glue table, then the Glue database, then the crawler.
- Delete the IAM role.

## Stretch goals

- Add a `year=2023/` partition with a third CSV. Run the crawler. Confirm Athena treats it as a separate partition and that `WHERE year = '2024'` skips the 2023 file (partition pruning).
- Convert the data to Parquet using a CTAS query: `CREATE TABLE sales_parquet WITH (format = 'PARQUET', external_location = 's3://archadv-<you>-datalake/sales-parquet/') AS SELECT * FROM sales;`. Re-query and compare `Data scanned` — Parquet typically scans 5–20× less.
- Wire QuickSight to the Athena workgroup and build a region-by-revenue chart.
