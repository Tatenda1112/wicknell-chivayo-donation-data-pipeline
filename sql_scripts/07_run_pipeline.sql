/*
=============================================================
Run the whole pipeline (after the one-time setup scripts)
=============================================================
One-time setup, in this order:
  scripts\00_init\00_create_database_and_schemas.sql
  scripts\bronze\01_ddl_bronze.sql
  scripts\bronze\02_proc_load_bronze.sql
  scripts\silver\03_ddl_silver.sql
  scripts\silver\04_proc_load_silver.sql
  scripts\gold\05_ddl_gold.sql

Then, every time the CSV files change:
=============================================================
*/

USE DonationsDW;
GO

EXEC bronze.load_bronze;   -- Source files -> Bronze
GO
EXEC silver.load_silver;   -- Bronze -> Silver
GO


-- Check the result:
SELECT * FROM gold.dim_item;
GO

SELECT SUM(cash_amount_usd) from gold.fact_donations 

SELECT SUM(cash_amount_usd) AS counted_cash_usd
FROM gold.fact_donations
WHERE counts_toward_total = 1;


SELECT s.status_group, SUM(f.cash_amount_usd) AS cash_usd
FROM gold.fact_donations f
JOIN gold.dim_status s ON s.status_key = f.status_key
WHERE f.counts_toward_total = 1
GROUP BY s.status_group;