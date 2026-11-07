/*
=============================================================
DDL Script: Create Gold Views
=============================================================
Layer   : gold  (business-ready data, views only, no load)
Model   : Star schema
            fact_donations (1 row per donation line)
            dim_date  dim_recipient  dim_donation_type
            dim_status  dim_item
          + flat view and aggregate views for Power BI
Rules   : * Money and asset values are kept in SEPARATE columns:
              cash_amount_usd   -> money rows only
              asset_value_usd   -> vehicles, houses, other giving
            so the value of a car is never added to cash.
          * counts_toward_total = 0 marks repeated pledges, loans
            and personal purchases. All aggregate views filter
            on counts_toward_total = 1.
Re-run  : CREATE OR ALTER, safe to run again.
=============================================================
*/

USE DonationsDW;
GO

-- =========================================================
-- Dimension: date
-- =========================================================
CREATE OR ALTER VIEW gold.dim_date AS
WITH all_dates AS (
    SELECT donation_date AS d FROM silver.donation_money
    UNION ALL SELECT donation_date FROM silver.donation_vehicle
    UNION ALL SELECT donation_date FROM silver.donation_house
    UNION ALL SELECT donation_date FROM silver.donation_other
    UNION ALL SELECT tweet_date FROM silver.tweet
),
bounds AS (
    SELECT MIN(d) AS d_min, MAX(d) AS d_max FROM all_dates WHERE d IS NOT NULL
),
nums AS (
    -- One row per day from 1 Jan of the first year to 31 Dec of the last year.
    -- (Was a fixed TOP (3660), which stopped the calendar after 10 years.)
    SELECT TOP (SELECT DATEDIFF(DAY, DATEFROMPARTS(YEAR(d_min), 1, 1),
                                     DATEFROMPARTS(YEAR(d_max), 12, 31)) + 1 FROM bounds)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
SELECT
    YEAR(x.dt) * 10000 + MONTH(x.dt) * 100 + DAY(x.dt)           AS date_key,
    x.dt                                                          AS full_date,
    YEAR(x.dt)                                                    AS [year],
    CONCAT('Q', DATEPART(QUARTER, x.dt))                          AS [quarter],
    MONTH(x.dt)                                                   AS month_number,
    DATENAME(MONTH, x.dt)                                         AS month_name,
    CONCAT(YEAR(x.dt), '-', RIGHT(CONCAT('0', MONTH(x.dt)), 2))   AS year_month,
    DAY(x.dt)                                                     AS day_of_month,
    DATENAME(WEEKDAY, x.dt)                                       AS day_name
FROM bounds
CROSS JOIN nums
CROSS APPLY (SELECT DATEADD(DAY, nums.n, DATEFROMPARTS(YEAR(bounds.d_min), 1, 1)) AS dt) x
WHERE x.dt <= DATEFROMPARTS(YEAR(bounds.d_max), 12, 31);
GO

-- =========================================================
-- Dimension: recipient
-- =========================================================
CREATE OR ALTER VIEW gold.dim_recipient AS
SELECT recipient_id    AS recipient_key,
       recipient_name,
       recipient_type,
       recipient_group
FROM silver.recipient;
GO

-- =========================================================
-- Dimension: donation type
-- =========================================================
CREATE OR ALTER VIEW gold.dim_donation_type AS
SELECT donation_type_key, donation_type, description
FROM (VALUES
    (1, N'Money',   N'Cash gifts, fees and support payments'),
    (2, N'Vehicle', N'Cars, buses, pickups and ambulances'),
    (3, N'House',   N'Houses and house purchases'),
    (4, N'Other',   N'Equipment, electronics, fuel, education and other items')
) v (donation_type_key, donation_type, description);
GO

-- =========================================================
-- Dimension: status
-- =========================================================
CREATE OR ALTER VIEW gold.dim_status AS
SELECT status_key, commitment_status, status_group
FROM (VALUES
    (1, N'Delivered',          N'Delivered'),
    (2, N'Donated',            N'Delivered'),
    (3, N'Previously Donated', N'Delivered'),
    (4, N'Promised',           N'Promised'),
    (5, N'Unknown',            N'Unknown')
) v (status_key, commitment_status, status_group);
GO

-- =========================================================
-- Dimension: item (category level)
-- =========================================================
CREATE OR ALTER VIEW gold.dim_item AS
WITH items AS (
    SELECT 1 AS donation_type_key, ISNULL(money_nature,  'Unspecified') AS item_category FROM silver.donation_money
    UNION
    SELECT 2, ISNULL(vehicle_class, 'Unspecified') FROM silver.donation_vehicle
    UNION
    SELECT 3, ISNULL(house_nature,  'Unspecified') FROM silver.donation_house
    UNION
    SELECT 4, ISNULL(category,      'Unspecified') FROM silver.donation_other
)
SELECT ROW_NUMBER() OVER (ORDER BY donation_type_key, item_category) AS item_key,
       donation_type_key,
       item_category
FROM items;
GO

-- =========================================================
-- Fact: donations (one row per donation line)
-- =========================================================
CREATE OR ALTER VIEW gold.fact_donations AS
WITH u AS (
    SELECT money_id AS donation_line_id, 1 AS donation_type_key, source_donation_id, tweet_id,
           COALESCE(donation_date, tweet_date) AS event_date, recipient_id,
           ISNULL(commitment_status, 'Unknown') AS commitment_status,
           ISNULL(money_nature, 'Unspecified') AS item_category,
           CAST(NULL AS NVARCHAR(300)) AS item_name,
           CAST(recipient_count AS DECIMAL(18,2)) AS quantity,
           currency AS currency_original, total_amount AS amount_original,
           total_amount_usd AS cash_amount_usd, CAST(NULL AS DECIMAL(18,2)) AS asset_value_usd,
           usd_is_converted, counts_toward_total, not_counted_reason, overlap_group, review_flag
    FROM silver.donation_money
    UNION ALL
    SELECT vehicle_id, 2, source_donation_id, tweet_id,
           COALESCE(donation_date, tweet_date), recipient_id,
           ISNULL(commitment_status, 'Unknown'),
           ISNULL(vehicle_class, 'Unspecified'),
           item_name,
           CAST(quantity AS DECIMAL(18,2)),
           CAST('USD' AS CHAR(3)), total_value_usd,
           CAST(NULL AS DECIMAL(18,2)), total_value_usd,
           CAST(0 AS BIT), counts_toward_total, not_counted_reason, overlap_group, review_flag
    FROM silver.donation_vehicle
    UNION ALL
    SELECT house_id, 3, source_donation_id, tweet_id,
           COALESCE(donation_date, tweet_date), recipient_id,
           ISNULL(commitment_status, 'Unknown'),
           ISNULL(house_nature, 'Unspecified'),
           CAST(NULL AS NVARCHAR(300)),
           CAST(house_count AS DECIMAL(18,2)),
           currency, total_value,
           CAST(NULL AS DECIMAL(18,2)), total_value_usd,
           usd_is_converted, counts_toward_total, not_counted_reason, overlap_group, review_flag
    FROM silver.donation_house
    UNION ALL
    SELECT other_id, 4, source_donation_id, tweet_id,
           COALESCE(donation_date, tweet_date), recipient_id,
           ISNULL(commitment_status, 'Unknown'),
           ISNULL(category, 'Unspecified'),
           item_name,
           quantity,
           CAST('USD' AS CHAR(3)), total_value_usd,
           CAST(NULL AS DECIMAL(18,2)), total_value_usd,
           CAST(0 AS BIT), counts_toward_total, not_counted_reason, overlap_group, review_flag
    FROM silver.donation_other
)
SELECT
    u.donation_line_id,
    u.donation_type_key,
    u.source_donation_id,
    u.tweet_id,
    YEAR(u.event_date) * 10000 + MONTH(u.event_date) * 100 + DAY(u.event_date) AS date_key,
    u.recipient_id          AS recipient_key,
    s.status_key,
    i.item_key,
    u.item_name,
    u.quantity,
    u.currency_original,
    u.amount_original,
    u.cash_amount_usd,
    u.asset_value_usd,
    u.usd_is_converted,
    u.counts_toward_total,
    u.not_counted_reason,
    u.overlap_group,
    u.review_flag
FROM u
JOIN gold.dim_status s ON s.commitment_status = u.commitment_status
JOIN gold.dim_item   i ON i.donation_type_key = u.donation_type_key AND i.item_category = u.item_category;
GO

-- =========================================================
-- Flat view for Power BI (fact + all dimensions in one table)
-- =========================================================
CREATE OR ALTER VIEW gold.fact_donations_flat AS
SELECT
    f.donation_line_id,
    f.source_donation_id,
    f.tweet_id,
    tw.tweet_url,
    d.full_date,
    d.[year],
    d.[quarter],
    d.month_number,
    d.month_name,
    d.year_month,
    t.donation_type,
    i.item_category,
    f.item_name,
    r.recipient_name,
    r.recipient_type,
    r.recipient_group,
    s.commitment_status,
    s.status_group,
    f.quantity,
    f.currency_original,
    f.amount_original,
    f.cash_amount_usd,
    f.asset_value_usd,
    f.usd_is_converted,
    f.counts_toward_total,
    f.not_counted_reason,
    f.overlap_group,
    f.review_flag
FROM gold.fact_donations f
LEFT JOIN gold.dim_date          d  ON d.date_key = f.date_key
LEFT JOIN gold.dim_recipient     r  ON r.recipient_key = f.recipient_key
LEFT JOIN gold.dim_donation_type t  ON t.donation_type_key = f.donation_type_key
LEFT JOIN gold.dim_status        s  ON s.status_key = f.status_key
LEFT JOIN gold.dim_item          i  ON i.item_key = f.item_key
LEFT JOIN silver.tweet           tw ON tw.tweet_id = f.tweet_id;
GO

-- =========================================================
-- Aggregate: by month and status
-- =========================================================
CREATE OR ALTER VIEW gold.agg_donations_by_month AS
SELECT
    year_month,
    [year],
    month_number,
    status_group,
    COUNT(*)                                                         AS donation_lines,
    SUM(ISNULL(cash_amount_usd, 0))                                  AS cash_usd,
    SUM(ISNULL(asset_value_usd, 0))                                  AS asset_value_usd,
    SUM(CASE WHEN donation_type = 'Vehicle' THEN ISNULL(quantity, 0) ELSE 0 END) AS vehicles,
    SUM(CASE WHEN donation_type = 'House'   THEN ISNULL(quantity, 0) ELSE 0 END) AS houses
FROM gold.fact_donations_flat
WHERE counts_toward_total = 1
GROUP BY year_month, [year], month_number, status_group;
GO

-- =========================================================
-- Aggregate: by donation type and status
-- =========================================================
CREATE OR ALTER VIEW gold.agg_donations_by_type AS
SELECT
    donation_type,
    status_group,
    COUNT(*)                          AS donation_lines,
    COUNT(DISTINCT recipient_name)    AS recipients,
    SUM(ISNULL(cash_amount_usd, 0))   AS cash_usd,
    SUM(ISNULL(asset_value_usd, 0))   AS asset_value_usd,
    SUM(ISNULL(quantity, 0))          AS units
FROM gold.fact_donations_flat
WHERE counts_toward_total = 1
GROUP BY donation_type, status_group;
GO

-- =========================================================
-- Aggregate: by recipient group and status
-- =========================================================
CREATE OR ALTER VIEW gold.agg_donations_by_recipient_group AS
SELECT
    recipient_group,
    status_group,
    COUNT(*)                          AS donation_lines,
    COUNT(DISTINCT recipient_name)    AS recipients,
    SUM(ISNULL(cash_amount_usd, 0))   AS cash_usd,
    SUM(ISNULL(asset_value_usd, 0))   AS asset_value_usd
FROM gold.fact_donations_flat
WHERE counts_toward_total = 1
GROUP BY recipient_group, status_group;
GO

-- =========================================================
-- Aggregate: by recipient (use Top N in Power BI)
-- =========================================================
CREATE OR ALTER VIEW gold.agg_donations_by_recipient AS
SELECT
    recipient_name,
    recipient_type,
    recipient_group,
    COUNT(*)                          AS donation_lines,
    SUM(ISNULL(cash_amount_usd, 0))   AS cash_usd,
    SUM(ISNULL(asset_value_usd, 0))   AS asset_value_usd,
    SUM(CASE WHEN donation_type = 'Vehicle' THEN ISNULL(quantity, 0) ELSE 0 END) AS vehicles
FROM gold.fact_donations_flat
WHERE counts_toward_total = 1
GROUP BY recipient_name, recipient_type, recipient_group;
GO

-- =========================================================
-- Aggregate: promised vs delivered
-- =========================================================
CREATE OR ALTER VIEW gold.agg_promised_vs_delivered AS
SELECT
    status_group,
    COUNT(*)                          AS donation_lines,
    SUM(ISNULL(cash_amount_usd, 0))   AS cash_usd,
    SUM(ISNULL(asset_value_usd, 0))   AS asset_value_usd,
    SUM(CASE WHEN donation_type = 'Vehicle' THEN ISNULL(quantity, 0) ELSE 0 END) AS vehicles,
    SUM(CASE WHEN donation_type = 'House'   THEN ISNULL(quantity, 0) ELSE 0 END) AS houses
FROM gold.fact_donations_flat
WHERE counts_toward_total = 1
GROUP BY status_group;
GO
