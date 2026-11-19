/*
=============================================================
Gold Summary: final numbers for vehicles, money and everything else
=============================================================
Run after bronze.load_bronze and silver.load_silver.
Every query reads the Gold view gold.fact_donations_flat.
counts_toward_total = 1 removes declined rows, confirmed
duplicates and non-donations (loans, fees, personal purchases).
=============================================================
*/

USE DonationsDW;
GO

-- ---------------------------------------------------------
-- 1. VEHICLES: promised vs delivered vs total (units)
-- ---------------------------------------------------------
SELECT
    CASE WHEN GROUPING(status_group) = 1 THEN 'TOTAL' ELSE status_group END AS status_group,
    COUNT(*)                                   AS donation_lines,
    SUM(ISNULL(quantity, 0))                   AS vehicles,
    SUM(CASE WHEN quantity IS NULL THEN 1 ELSE 0 END) AS lines_with_unknown_quantity,
    SUM(ISNULL(asset_value_usd, 0))            AS stated_value_usd
FROM gold.fact_donations_flat
WHERE donation_type = 'Vehicle'
  AND counts_toward_total = 1
GROUP BY ROLLUP (status_group);

-- 1b. Vehicles by class and status (pivoted)
SELECT
    item_category AS vehicle_class,
    SUM(CASE WHEN status_group = 'Delivered' THEN ISNULL(quantity, 0) ELSE 0 END) AS delivered,
    SUM(CASE WHEN status_group = 'Promised'  THEN ISNULL(quantity, 0) ELSE 0 END) AS promised,
    SUM(ISNULL(quantity, 0))                                                       AS total_vehicles,
    SUM(ISNULL(asset_value_usd, 0))                                                AS stated_value_usd
FROM gold.fact_donations_flat
WHERE donation_type = 'Vehicle'
  AND counts_toward_total = 1
GROUP BY item_category
ORDER BY total_vehicles DESC;

-- ---------------------------------------------------------
-- 2. MONEY: promised vs delivered vs total (USD)
--    Cash only. The value of cars and houses is never added here.
-- ---------------------------------------------------------
SELECT
    CASE WHEN GROUPING(status_group) = 1 THEN 'TOTAL' ELSE status_group END AS status_group,
    COUNT(*)                                        AS donation_lines,
    SUM(ISNULL(cash_amount_usd, 0))                 AS cash_usd,
    SUM(CASE WHEN usd_is_converted = 1 THEN ISNULL(cash_amount_usd, 0) ELSE 0 END) AS of_which_converted_from_zar,
    SUM(CASE WHEN cash_amount_usd IS NULL THEN 1 ELSE 0 END) AS lines_without_amount
FROM gold.fact_donations_flat
WHERE donation_type = 'Money'
  AND counts_toward_total = 1
GROUP BY ROLLUP (status_group);

-- 2b. Money by nature (gift, family support, compensation, ...)
SELECT
    item_category AS money_nature,
    SUM(CASE WHEN status_group = 'Delivered' THEN ISNULL(cash_amount_usd, 0) ELSE 0 END) AS delivered_usd,
    SUM(CASE WHEN status_group = 'Promised'  THEN ISNULL(cash_amount_usd, 0) ELSE 0 END) AS promised_usd,
    SUM(ISNULL(cash_amount_usd, 0))                                                      AS total_usd
FROM gold.fact_donations_flat
WHERE donation_type = 'Money'
  AND counts_toward_total = 1
GROUP BY item_category
ORDER BY total_usd DESC;

-- 2c. Money by year (donation date)
SELECT
    [year],
    SUM(CASE WHEN status_group = 'Delivered' THEN ISNULL(cash_amount_usd, 0) ELSE 0 END) AS delivered_usd,
    SUM(CASE WHEN status_group = 'Promised'  THEN ISNULL(cash_amount_usd, 0) ELSE 0 END) AS promised_usd,
    SUM(ISNULL(cash_amount_usd, 0))                                                      AS total_usd
FROM gold.fact_donations_flat
WHERE donation_type = 'Money'
  AND counts_toward_total = 1
GROUP BY [year]
ORDER BY [year];

-- ---------------------------------------------------------
-- 3. EVERYTHING: one table for all four donation types
-- ---------------------------------------------------------
SELECT
    donation_type,
    SUM(CASE WHEN status_group = 'Delivered' THEN 1 ELSE 0 END) AS delivered_lines,
    SUM(CASE WHEN status_group = 'Promised'  THEN 1 ELSE 0 END) AS promised_lines,
    COUNT(*)                                                    AS total_lines,
    SUM(ISNULL(cash_amount_usd, 0))                             AS cash_usd,
    SUM(ISNULL(asset_value_usd, 0))                             AS asset_value_usd,
    SUM(ISNULL(quantity, 0))                                    AS units
FROM gold.fact_donations_flat
WHERE counts_toward_total = 1
GROUP BY donation_type
ORDER BY donation_type;

-- Houses: promised vs delivered
SELECT
    status_group,
    SUM(ISNULL(quantity, 0))        AS houses,
    SUM(ISNULL(asset_value_usd, 0)) AS stated_value_usd
FROM gold.fact_donations_flat
WHERE donation_type = 'House'
  AND counts_toward_total = 1
GROUP BY status_group;

-- ---------------------------------------------------------
-- 4. WHAT THE RULES REMOVED: counted vs not counted
-- ---------------------------------------------------------
SELECT
    donation_type,
    SUM(CASE WHEN counts_toward_total = 1 THEN 1 ELSE 0 END) AS counted_lines,
    SUM(CASE WHEN counts_toward_total = 0 THEN 1 ELSE 0 END) AS not_counted_lines,
    SUM(CASE WHEN counts_toward_total = 1 THEN ISNULL(cash_amount_usd, 0) ELSE 0 END) AS counted_cash_usd,
    SUM(CASE WHEN counts_toward_total = 0 THEN ISNULL(cash_amount_usd, 0) ELSE 0 END) AS not_counted_cash_usd,
    SUM(CASE WHEN counts_toward_total = 1 THEN ISNULL(quantity, 0) ELSE 0 END) AS counted_units,
    SUM(CASE WHEN counts_toward_total = 0 THEN ISNULL(quantity, 0) ELSE 0 END) AS not_counted_units
FROM gold.fact_donations_flat
GROUP BY donation_type
ORDER BY donation_type;

-- ---------------------------------------------------------
-- 5. TOP 10 recipients by cash and by vehicles
-- ---------------------------------------------------------
SELECT TOP (10) recipient_name, recipient_group, cash_usd
FROM gold.agg_donations_by_recipient
ORDER BY cash_usd DESC;

SELECT TOP (10) recipient_name, recipient_group, vehicles
FROM gold.agg_donations_by_recipient
ORDER BY vehicles DESC;

-- ---------------------------------------------------------
-- 6. Money by recipient group
-- ---------------------------------------------------------
SELECT recipient_group,
       SUM(CASE WHEN status_group = 'Delivered' THEN cash_usd ELSE 0 END) AS delivered_usd,
       SUM(CASE WHEN status_group = 'Promised'  THEN cash_usd ELSE 0 END) AS promised_usd,
       SUM(cash_usd)                                                      AS total_usd
FROM gold.agg_donations_by_recipient_group
GROUP BY recipient_group
ORDER BY total_usd DESC;
GO
