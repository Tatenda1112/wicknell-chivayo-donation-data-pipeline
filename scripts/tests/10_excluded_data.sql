/*
=============================================================
Excluded Data: see everything that is NOT in the totals
=============================================================
Run after bronze.load_bronze and silver.load_silver.

Three groups, from most to least important:
  A. Rows kept in Silver but not counted (counts_toward_total = 0)
       Declined / Duplicate / Not a donation
  B. Rows removed before the donation tables (silver.excluded)
       Aggregate claims, investment plans, declined gifts, etc.
  C. Rows still COUNTED but possibly overlapping (needs a decision)
=============================================================
*/

USE DonationsDW;
GO

-- ---------------------------------------------------------
-- A1. Summary: how many rows and how much value was not counted
-- ---------------------------------------------------------
WITH not_counted AS (
    SELECT 'Money' AS donation_type, not_counted_reason, total_amount_usd AS cash_usd, CAST(0 AS DECIMAL(18,2)) AS units
    FROM silver.donation_money WHERE counts_toward_total = 0
    UNION ALL
    SELECT 'Vehicle', not_counted_reason, NULL, ISNULL(quantity, 0) FROM silver.donation_vehicle WHERE counts_toward_total = 0
    UNION ALL
    SELECT 'House', not_counted_reason, NULL, ISNULL(house_count, 0) FROM silver.donation_house WHERE counts_toward_total = 0
    UNION ALL
    SELECT 'Other', not_counted_reason, NULL, ISNULL(quantity, 0) FROM silver.donation_other WHERE counts_toward_total = 0
)
SELECT
    CASE WHEN CHARINDEX(':', not_counted_reason) > 0
         THEN LEFT(not_counted_reason, CHARINDEX(':', not_counted_reason) - 1)
         ELSE 'UNCATEGORISED' END      AS category,
    donation_type,
    COUNT(*)                           AS rows_not_counted,
    SUM(ISNULL(cash_usd, 0))           AS cash_usd_not_counted,
    SUM(units)                         AS units_not_counted
FROM not_counted
GROUP BY CASE WHEN CHARINDEX(':', not_counted_reason) > 0
              THEN LEFT(not_counted_reason, CHARINDEX(':', not_counted_reason) - 1)
              ELSE 'UNCATEGORISED' END,
         donation_type
ORDER BY category, donation_type;

-- ---------------------------------------------------------
-- A2. Detail: every row that is not counted, with the reason
-- ---------------------------------------------------------
SELECT
    x.donation_type,
    CASE WHEN CHARINDEX(':', x.not_counted_reason) > 0
         THEN LEFT(x.not_counted_reason, CHARINDEX(':', x.not_counted_reason) - 1)
         ELSE 'UNCATEGORISED' END      AS category,
    x.line_id,
    x.source_donation_id,
    x.donation_date,
    x.recipient_name,
    x.commitment_status,
    x.item_name,
    x.quantity,
    x.cash_usd,
    x.asset_value_usd,
    x.not_counted_reason,
    t.tweet_url,
    x.source_excerpt
FROM (
    SELECT 'Money' AS donation_type, money_id AS line_id, source_donation_id, tweet_id, donation_date, recipient_name,
           commitment_status, CAST(NULL AS NVARCHAR(300)) AS item_name, CAST(recipient_count AS DECIMAL(18,2)) AS quantity,
           total_amount_usd AS cash_usd, CAST(NULL AS DECIMAL(18,2)) AS asset_value_usd, not_counted_reason, source_excerpt
    FROM silver.donation_money WHERE counts_toward_total = 0
    UNION ALL
    SELECT 'Vehicle', vehicle_id, source_donation_id, tweet_id, donation_date, recipient_name,
           commitment_status, item_name, CAST(quantity AS DECIMAL(18,2)),
           CAST(NULL AS DECIMAL(18,2)), total_value_usd, not_counted_reason, source_excerpt
    FROM silver.donation_vehicle WHERE counts_toward_total = 0
    UNION ALL
    SELECT 'House', house_id, source_donation_id, tweet_id, donation_date, recipient_name,
           commitment_status, CAST(NULL AS NVARCHAR(300)), CAST(house_count AS DECIMAL(18,2)),
           CAST(NULL AS DECIMAL(18,2)), total_value_usd, not_counted_reason, source_excerpt
    FROM silver.donation_house WHERE counts_toward_total = 0
    UNION ALL
    SELECT 'Other', other_id, source_donation_id, tweet_id, donation_date, recipient_name,
           commitment_status, item_name, quantity,
           CAST(NULL AS DECIMAL(18,2)), total_value_usd, not_counted_reason, source_excerpt
    FROM silver.donation_other WHERE counts_toward_total = 0
) x
LEFT JOIN silver.tweet t ON t.tweet_id = x.tweet_id
ORDER BY category, x.donation_type, x.source_donation_id;

-- ---------------------------------------------------------
-- B. Rows removed before the donation tables (not donations)
-- ---------------------------------------------------------
SELECT
    e.source_donation_id,
    e.tweet_date,
    e.recipient_name,
    e.donation_type_in_source,
    e.item_name,
    e.amount_original,
    e.currency,
    e.amount_usd,
    e.reason_excluded,
    t.tweet_url,
    e.source_excerpt
FROM silver.excluded e
LEFT JOIN silver.tweet t ON t.tweet_id = e.tweet_id
ORDER BY e.source_donation_id;

-- ---------------------------------------------------------
-- C. Still counted, but possibly overlapping with another row
--    (move to #not_counted in silver.load_silver once confirmed)
-- ---------------------------------------------------------
SELECT
    q.source_table,
    q.source_donation_id,
    q.description,
    COALESCE(m.recipient_name, v.recipient_name)       AS recipient_name,
    COALESCE(m.commitment_status, v.commitment_status) AS commitment_status,
    m.total_amount_usd                                 AS cash_usd,
    v.quantity                                         AS vehicles,
    v.total_value_usd                                  AS vehicle_value_usd
FROM silver.data_quality_issues q
LEFT JOIN silver.donation_money   m ON q.source_table = 'donation_money'   AND m.source_donation_id = q.source_donation_id
LEFT JOIN silver.donation_vehicle v ON q.source_table = 'donation_vehicle' AND v.source_donation_id = q.source_donation_id
WHERE q.issue_type = 'OVERLAP_REVIEW'
ORDER BY q.source_donation_id;

-- ---------------------------------------------------------
-- D. Totals with and without the exclusions (cash and vehicles)
-- ---------------------------------------------------------
SELECT
    'Cash USD'                                                                     AS measure,
    SUM(ISNULL(total_amount_usd, 0))                                               AS all_rows,
    SUM(CASE WHEN counts_toward_total = 1 THEN ISNULL(total_amount_usd, 0) ELSE 0 END) AS counted,
    SUM(CASE WHEN counts_toward_total = 0 THEN ISNULL(total_amount_usd, 0) ELSE 0 END) AS not_counted
FROM silver.donation_money
UNION ALL
SELECT
    'Vehicles (units)',
    SUM(ISNULL(quantity, 0)),
    SUM(CASE WHEN counts_toward_total = 1 THEN ISNULL(quantity, 0) ELSE 0 END),
    SUM(CASE WHEN counts_toward_total = 0 THEN ISNULL(quantity, 0) ELSE 0 END)
FROM silver.donation_vehicle;
GO
