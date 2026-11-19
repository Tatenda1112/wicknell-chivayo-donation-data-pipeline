/*
=============================================================
Diagnose: why are the Silver tables empty?
=============================================================
Run the blocks one by one and read the result grids.
=============================================================
*/

USE DonationsDW;
GO

-- 1. Did the Bronze load work? (status must be SUCCESS and rows_loaded > 0)
SELECT TOP (20) log_id, table_name, rows_loaded, status, error_message, load_end
FROM bronze.load_log
ORDER BY log_id DESC;

-- 2. What is actually inside Bronze right now?
SELECT 'reviewed_money' AS bronze_table, COUNT(*) AS n FROM bronze.reviewed_money
UNION ALL SELECT 'reviewed_vehicle',      COUNT(*) FROM bronze.reviewed_vehicle
UNION ALL SELECT 'reviewed_house',        COUNT(*) FROM bronze.reviewed_house
UNION ALL SELECT 'reviewed_other_giving', COUNT(*) FROM bronze.reviewed_other_giving
UNION ALL SELECT 'reviewed_excluded',     COUNT(*) FROM bronze.reviewed_excluded
UNION ALL SELECT 'llm_donations_extract', COUNT(*) FROM bronze.llm_donations_extract;

-- 3. Does the Silver procedure exist, and when was it last changed?
SELECT name, create_date, modify_date
FROM sys.procedures
WHERE SCHEMA_ID('silver') = schema_id;

-- 4. What is inside Silver right now?
SELECT 'donation_money' AS silver_table, COUNT(*) AS n FROM silver.donation_money
UNION ALL SELECT 'donation_vehicle',  COUNT(*) FROM silver.donation_vehicle
UNION ALL SELECT 'donation_house',    COUNT(*) FROM silver.donation_house
UNION ALL SELECT 'donation_other',    COUNT(*) FROM silver.donation_other
UNION ALL SELECT 'recipient',         COUNT(*) FROM silver.recipient
UNION ALL SELECT 'tweet',             COUNT(*) FROM silver.tweet
UNION ALL SELECT 'excluded',          COUNT(*) FROM silver.excluded
UNION ALL SELECT 'data_quality_issues', COUNT(*) FROM silver.data_quality_issues
UNION ALL SELECT 'exchange_rate',     COUNT(*) FROM silver.exchange_rate;

-- 5. Run the Silver load and read the MESSAGES tab (it prints every step and stops with a clear error)
-- EXEC silver.load_silver;
