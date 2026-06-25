-- ============================================================
-- BigQuery Partitioning & Clustering — Annotated Examples
-- Module 3: Data Warehouse
-- ============================================================
-- ============================================================
-- 1. QUERY PUBLIC TABLE
-- ============================================================
-- Standard BQ public dataset query — no optimization needed,
-- citibike_stations is tiny (<1MB), partitioning irrelevant for small tables
SELECT
    station_id,
    name
FROM
    bigquery-public-data.new_york_citibike.citibike_stations
LIMIT
    100;

-- ============================================================
-- 2. EXTERNAL TABLE
-- ============================================================
-- External table = pointer to GCS files, zero data copied into BQ
-- BQ reads CSV directly from GCS on every query — no storage cost in BQ
-- Wildcard (*) matches multiple files across 2019 and 2020
-- Downside: slower repeated queries vs native table (re-reads GCS each time)
-- Use case: one-time ingestion, staging layer, cost-sensitive raw storage
CREATE OR REPLACE EXTERNAL TABLE `taxi-rides-ny.nytaxi.external_yellow_tripdata` OPTIONS(
    format = 'CSV',
    uris = [
        'gs://nyc-tl-data/trip data/yellow_tripdata_2019-*.csv',
        'gs://nyc-tl-data/trip data/yellow_tripdata_2020-*.csv'
    ]
);

-- Preview — LIMIT prevents full external scan, but BQ still reads some data
-- External tables can't use partition pruning — always scan everything
SELECT
    *
FROM
    taxi-rides-ny.nytaxi.external_yellow_tripdata
LIMIT
    10;

-- ============================================================
-- 3. NON-PARTITIONED TABLE (baseline for comparison)
-- ============================================================
-- Copies data from external table into native BQ columnar storage
-- Fast repeated queries vs external table, but no partition pruning
-- Any date-filtered query scans the ENTIRE table regardless of date range
-- At scale: 1.6GB scanned for a single month filter (see comparison below)
CREATE OR REPLACE TABLE taxi-rides-ny.nytaxi.yellow_tripdata_non_partitioned AS
SELECT
    *
FROM
    taxi-rides-ny.nytaxi.external_yellow_tripdata;

-- ============================================================
-- 4. PARTITIONED TABLE
-- ============================================================
-- PARTITION BY DATE(tpep_pickup_datetime):
-- → BQ physically stores each day's data in separate files
-- → queries with date filters skip irrelevant partitions entirely
-- → max 4000 partitions per table (date partitioning = ~11 years max)
-- → one partition column only — choose the one you filter most frequently
-- Cost rule: $5/TB scanned — partitioning directly reduces your BQ bill
CREATE OR REPLACE TABLE taxi-rides-ny.nytaxi.yellow_tripdata_partitioned
PARTITION BY
    DATE(tpep_pickup_datetime) AS
SELECT
    *
FROM
    taxi-rides-ny.nytaxi.external_yellow_tripdata;

-- ============================================================
-- 5. PARTITION IMPACT COMPARISON
-- ============================================================
-- Non-partitioned: scans entire 2-year table to find June 2019 rows
-- BQ reads all 1.6GB even though result is only ~1 month of data
-- Cost: ~$0.008 per query at $5/TB
SELECT DISTINCT
    (vendorid)
FROM
    taxi-rides-ny.nytaxi.yellow_tripdata_non_partitioned
WHERE
    DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2019-06-30';

-- Partitioned: BQ skips to June 2019 partition directly
-- Only ~106MB scanned — ~15x less data than non-partitioned
-- Cost: ~$0.0005 per query — significant saving at production scale
-- This is the core value of partitioning: skip what you don't need
SELECT DISTINCT
    (vendorid)
FROM
    taxi-rides-ny.nytaxi.yellow_tripdata_partitioned
WHERE
    DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2019-06-30';

-- ============================================================
-- 6. INSPECT PARTITION METADATA
-- ============================================================
-- INFORMATION_SCHEMA.PARTITIONS: BQ system view showing partition stats
-- Useful for: identifying skewed partitions, validating data landed correctly,
-- checking partition sizes before deciding on clustering strategy
-- If any partition is <10MB → consider clustering instead (too fine-grained)
-- If partition count approaches 4000 → consider coarser partition grain
SELECT
    table_name,
    partition_id,
    total_rows
FROM
    `nytaxi.INFORMATION_SCHEMA.PARTITIONS`
WHERE
    table_name = 'yellow_tripdata_partitioned'
ORDER BY
    total_rows DESC;

-- ============================================================
-- 7. PARTITIONED + CLUSTERED TABLE
-- ============================================================
-- CLUSTER BY VendorID:
-- → within each date partition, data is physically sorted by VendorID
-- → queries filtering on both date AND VendorID get double pruning:
--   first skip irrelevant partitions (date), then skip irrelevant
--   cluster blocks within the partition (VendorID)
-- → up to 4 clustering columns, order matters (put highest cardinality first)
-- → no storage cost premium — clustering is free
-- → unlike partitioning, clustering is a "soft" optimization:
--   BQ estimates which blocks to skip, not guaranteed but usually very effective
--
-- When to cluster instead of partition:
-- → partitions would be too small (<10MB each)
-- → writing to many partitions frequently (DML cost adds up)
-- → need to filter on a non-date column as the primary access pattern
CREATE OR REPLACE TABLE taxi-rides-ny.nytaxi.yellow_tripdata_partitioned_clustered
PARTITION BY
    DATE(tpep_pickup_datetime)
CLUSTER BY
    vendorid AS
SELECT
    *
FROM
    taxi-rides-ny.nytaxi.external_yellow_tripdata;

-- ============================================================
-- 8. CLUSTERING IMPACT COMPARISON
-- ============================================================
-- Partitioned only: date filter prunes to relevant months (good)
-- but VendorID=1 filter must scan ALL rows within those months
-- 1.1GB scanned across the 18-month range
SELECT
    COUNT(*) AS trips
FROM
    taxi-rides-ny.nytaxi.yellow_tripdata_partitioned
WHERE
    DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2020-12-31'
    AND vendorid = 1;

-- Partitioned + clustered: date pruning AND VendorID block skipping
-- 864.5MB scanned — ~21% less than partitioned alone
-- Saving grows proportionally with table size and query frequency
-- At $5/TB and 1000 queries/day: ~$1,100/year saving on this query alone
--
-- Note: clustering benefit varies — depends on data distribution within partitions
-- High cardinality VendorID with even distribution = better clustering benefit
-- Skewed data (one vendor dominates) = less benefit
SELECT
    COUNT(*) AS trips
FROM
    taxi-rides-ny.nytaxi.yellow_tripdata_partitioned_clustered
WHERE
    DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2020-12-31'
    AND vendorid = 1;

-- ============================================================
-- SUMMARY: DECISION GUIDE
-- ============================================================
--
-- Table < 1GB                          → no optimization needed
-- Table > 1GB, filter by date always   → PARTITION BY date column
-- Partitions would be tiny (<10MB)     → CLUSTER instead
-- Write to many partitions frequently  → CLUSTER instead (avoid DML costs)
-- Filter by date + other columns       → PARTITION BY date + CLUSTER BY other cols
-- High cardinality non-date filter     → CLUSTER BY that column
-- Want to prevent accidental full scan → add OPTIONS(require_partition_filter=TRUE)
--
-- Storage cost: same price regardless of partitioning/clustering ($0.02/GB active)
-- Query cost:   partitioning/clustering reduces bytes scanned → reduces bill
-- Old partitions not modified 90+ days → automatically drop to $0.01/GB (long-term rate)
