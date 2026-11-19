/*
=============================================================
Quality Checks
=============================================================
Run after bronze.load_bronze and silver.load_silver.
Every check returns rows ONLY when something is wrong,
except the first two (row counts) which always return a table.
=============================================================
*/

USE DonationsDW;
GO

-- ---------------------------------------------------------
-- 1. Bronze row counts against the CSV files
-- ---------------------------------------------------------
SELECT e.table_name, e.expected_rows,
       l.rows_loaded,
       CASE WHEN l.rows_loaded = e.expected_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM (VALUES
    (N'llm_donations_extract', 445),
    (N'reviewed_money', 206),
    (N'reviewed_vehicle', 230),
    (N'reviewed_house', 8),
    (N'reviewed_other_giving', 18),
    (N'reviewed_excluded', 6),
    (N'reviewed_corrections_log', 59)
) e (table_name, expected_rows)
OUTER APPLY (SELECT TOP 1 rows_loaded FROM bronze.load_log WHERE table_name = e.table_name AND status = 'SUCCESS' ORDER BY log_id DESC) l;

-- ---------------------------------------------------------
-- 2. Silver row counts against Bronze (donation tables + excluded)
-- ---------------------------------------------------------
SELECT x.silver_table, x.bronze_rows, x.silver_rows,
       CASE WHEN x.bronze_rows = x.silver_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT 'donation_money'   AS silver_table, (SELECT COUNT(*) FROM bronze.reviewed_money)        AS bronze_rows, (SELECT COUNT(*) FROM silver.donation_money)   AS silver_rows
    UNION ALL SELECT 'donation_vehicle', (SELECT COUNT(*) FROM bronze.reviewed_vehicle),     (SELECT COUNT(*) FROM silver.donation_vehicle)
    UNION ALL SELECT 'donation_house',   (SELECT COUNT(*) FROM bronze.reviewed_house),       (SELECT COUNT(*) FROM silver.donation_house)
    UNION ALL SELECT 'donation_other',   (SELECT COUNT(*) FROM bronze.reviewed_other_giving),(SELECT COUNT(*) FROM silver.donation_other)
    UNION ALL SELECT 'excluded',         (SELECT COUNT(*) FROM bronze.reviewed_excluded),    (SELECT COUNT(*) FROM silver.excluded)
) x;

-- ---------------------------------------------------------
-- 3. Duplicate ids inside Silver (expect no rows)
-- ---------------------------------------------------------
SELECT 'donation_money' AS tbl, money_id AS id, COUNT(*) AS n FROM silver.donation_money GROUP BY money_id HAVING COUNT(*) > 1
UNION ALL SELECT 'donation_vehicle', vehicle_id, COUNT(*) FROM silver.donation_vehicle GROUP BY vehicle_id HAVING COUNT(*) > 1
UNION ALL SELECT 'recipient', recipient_name, COUNT(*) FROM silver.recipient GROUP BY recipient_name HAVING COUNT(*) > 1;

-- ---------------------------------------------------------
-- 4. Money rows where recipient_count x amount_per_recipient <> total (expect no rows)
-- ---------------------------------------------------------
SELECT money_id, source_donation_id, recipient_count, amount_per_recipient, total_amount
FROM silver.donation_money
WHERE recipient_count IS NOT NULL AND amount_per_recipient IS NOT NULL AND total_amount IS NOT NULL
  AND ABS(recipient_count * amount_per_recipient - total_amount) > 0.5;

-- ---------------------------------------------------------
-- 5. Vehicle rows where quantity x unit value <> total (expect no rows)
-- ---------------------------------------------------------
SELECT vehicle_id, source_donation_id, quantity, unit_value_usd, total_value_usd
FROM silver.donation_vehicle
WHERE quantity IS NOT NULL AND unit_value_usd IS NOT NULL AND total_value_usd IS NOT NULL
  AND ABS(quantity * unit_value_usd - total_value_usd) > 1;

-- ---------------------------------------------------------
-- 6. Values that failed conversion (expect no rows)
--    A text value exists in Bronze but became NULL in Silver
-- ---------------------------------------------------------
SELECT 'money.total_amount' AS issue, b.money_id AS id
FROM bronze.reviewed_money b
JOIN silver.donation_money s ON s.money_id = LEFT(LTRIM(RTRIM(b.money_id)), 10)
WHERE NULLIF(LTRIM(RTRIM(b.total_amount)), '') IS NOT NULL AND s.total_amount IS NULL
UNION ALL
SELECT 'money.donation_date', b.money_id
FROM bronze.reviewed_money b
JOIN silver.donation_money s ON s.money_id = LEFT(LTRIM(RTRIM(b.money_id)), 10)
WHERE NULLIF(LTRIM(RTRIM(b.donation_date)), '') IS NOT NULL AND s.donation_date IS NULL
UNION ALL
SELECT 'vehicle.quantity', b.vehicle_id
FROM bronze.reviewed_vehicle b
JOIN silver.donation_vehicle s ON s.vehicle_id = LEFT(LTRIM(RTRIM(b.vehicle_id)), 10)
WHERE NULLIF(LTRIM(RTRIM(b.quantity)), '') IS NOT NULL AND s.quantity IS NULL;

-- ---------------------------------------------------------
-- 7. Gold fact against Silver (cash and line counts must match)
-- ---------------------------------------------------------
SELECT 'cash_usd' AS measure,
       (SELECT SUM(ISNULL(total_amount_usd, 0)) FROM silver.donation_money) AS silver_value,
       (SELECT SUM(ISNULL(cash_amount_usd, 0)) FROM gold.fact_donations)    AS gold_value
UNION ALL
SELECT 'donation_lines',
       (SELECT COUNT(*) FROM silver.donation_money) + (SELECT COUNT(*) FROM silver.donation_vehicle)
       + (SELECT COUNT(*) FROM silver.donation_house) + (SELECT COUNT(*) FROM silver.donation_other),
       (SELECT COUNT(*) FROM gold.fact_donations);

-- ---------------------------------------------------------
-- 8. Fact rows without a matching dimension (expect no rows)
-- ---------------------------------------------------------
SELECT f.donation_line_id,
       CASE WHEN d.date_key IS NULL THEN 'date' WHEN r.recipient_key IS NULL THEN 'recipient' END AS missing_dimension
FROM gold.fact_donations f
LEFT JOIN gold.dim_date d ON d.date_key = f.date_key
LEFT JOIN gold.dim_recipient r ON r.recipient_key = f.recipient_key
WHERE d.date_key IS NULL OR r.recipient_key IS NULL;

-- ---------------------------------------------------------
-- 9. Headline numbers (counted rows only)
-- ---------------------------------------------------------
SELECT * FROM gold.agg_promised_vs_delivered;
SELECT * FROM gold.agg_donations_by_type ORDER BY donation_type, status_group;

-- ---------------------------------------------------------
-- 10. Audit: everything kept OUT of the totals, with the reason.
--     Only Declined, Duplicate and Not a donation are allowed here.
-- ---------------------------------------------------------
SELECT CASE WHEN CHARINDEX(':', not_counted_reason) > 0 THEN LEFT(not_counted_reason, CHARINDEX(':', not_counted_reason) - 1) ELSE 'UNCATEGORISED' END AS category,
       COUNT(*) AS rows_not_counted
FROM (
    SELECT not_counted_reason FROM silver.donation_money   WHERE counts_toward_total = 0
    UNION ALL SELECT not_counted_reason FROM silver.donation_vehicle WHERE counts_toward_total = 0
    UNION ALL SELECT not_counted_reason FROM silver.donation_house   WHERE counts_toward_total = 0
    UNION ALL SELECT not_counted_reason FROM silver.donation_other   WHERE counts_toward_total = 0
) x
GROUP BY CASE WHEN CHARINDEX(':', not_counted_reason) > 0 THEN LEFT(not_counted_reason, CHARINDEX(':', not_counted_reason) - 1) ELSE 'UNCATEGORISED' END;

SELECT source_table, source_donation_id, description
FROM silver.data_quality_issues
WHERE issue_type = 'NOT_COUNTED_IN_TOTAL'
ORDER BY source_table, source_donation_id;

-- ---------------------------------------------------------
-- 11. Still counted but possibly overlapping (needs a human decision)
-- ---------------------------------------------------------
SELECT source_table, source_donation_id, description
FROM silver.data_quality_issues
WHERE issue_type = 'OVERLAP_REVIEW'
ORDER BY source_donation_id;
