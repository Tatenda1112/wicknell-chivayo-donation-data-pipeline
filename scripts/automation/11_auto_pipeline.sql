/*
=============================================================
Automation: n8n / Postgres -> Bronze -> Silver -> Gold, no manual steps
=============================================================
Run once in SSMS (or through scripts\automation\run_pipeline.ps1 -Setup),
after the one-time setup scripts 00 to 05.

Creates
  bronze.reviewed_baseline          the donation_ids that were already reviewed
                                    by hand (the 445 rows of the first LLM extract)
  bronze.load_n8n_sources           loads raw_tweets.csv and the baseline list
  bronze.add_unreviewed_donations   sorts every NEW donation (not in the baseline,
                                    not in a curated file) into money / vehicle /
                                    house / other by rule
  bronze.run_pipeline               the whole run: Bronze -> sort new rows -> Silver

How new rows are sorted (LLM donation_type -> table)
  Cash                              -> reviewed_money
  Vehicle                           -> reviewed_vehicle
  Property that names a house/home  -> reviewed_house
  everything else                   -> reviewed_other_giving

Every row added here carries
  origin      = 'auto_rule'
  review_flag = 'auto_unreviewed'
so it is counted in the totals and listed on the Data Quality page as a
Warning until you review it. To review a row, add it to the matching
curated CSV (datasets\curated): once its donation_id is in a curated file
the automatic version is no longer created.
=============================================================
*/

USE DonationsDW;
GO

IF OBJECT_ID('bronze.reviewed_baseline', 'U') IS NULL
    CREATE TABLE bronze.reviewed_baseline (
        [donation_id] NVARCHAR(50) NULL
    );
GO


-- ---------------------------------------------------------
-- Loads the two files that bronze.load_bronze does not load.
-- ---------------------------------------------------------
CREATE OR ALTER PROCEDURE bronze.load_n8n_sources
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @batch_id UNIQUEIDENTIFIER = NEWID();

    EXEC bronze.usp_load_csv
        @table_name = N'twitter_raw_tweets',
        @file_path  = N'C:\donations-datawarehouse\datasets\raw_tweets\raw_tweets.csv',
        @batch_id   = @batch_id;

    EXEC bronze.usp_load_csv
        @table_name = N'reviewed_baseline',
        @file_path  = N'C:\donations-datawarehouse\datasets\curated\reviewed_baseline_ids.csv',
        @batch_id   = @batch_id;
END;
GO


-- ---------------------------------------------------------
-- Sorts new LLM rows into the four reviewed_* bronze tables.
-- Safe to run again: it first removes the rows it added before.
-- ---------------------------------------------------------
CREATE OR ALTER PROCEDURE bronze.add_unreviewed_donations
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM bronze.reviewed_money        WHERE origin = N'auto_rule';
    DELETE FROM bronze.reviewed_vehicle      WHERE origin = N'auto_rule';
    DELETE FROM bronze.reviewed_house        WHERE origin = N'auto_rule';
    DELETE FROM bronze.reviewed_other_giving WHERE origin = N'auto_rule';

    -- donation_ids that a person has already dealt with
    IF OBJECT_ID('tempdb..#handled') IS NOT NULL DROP TABLE #handled;
    SELECT DISTINCT sid INTO #handled
    FROM (
        SELECT TRY_CAST(donation_id AS INT)        AS sid FROM bronze.reviewed_baseline
        UNION ALL SELECT TRY_CAST(source_donation_id AS INT) FROM bronze.reviewed_money
        UNION ALL SELECT TRY_CAST(source_donation_id AS INT) FROM bronze.reviewed_vehicle
        UNION ALL SELECT TRY_CAST(source_donation_id AS INT) FROM bronze.reviewed_house
        UNION ALL SELECT TRY_CAST(source_donation_id AS INT) FROM bronze.reviewed_other_giving
        UNION ALL SELECT TRY_CAST(source_donation_id AS INT) FROM bronze.reviewed_excluded
    ) x
    WHERE sid IS NOT NULL;

    -- one cleaned row per new donation
    IF OBJECT_ID('tempdb..#new') IS NOT NULL DROP TABLE #new;
    ;WITH cleaned AS (
        SELECT
            TRY_CAST(e.donation_id AS INT)                                  AS sid,
            TRY_CAST(k.tweet_id AS BIGINT)                                  AS tweet_id,
            k.donor_name, k.recipient_name, k.recipient_type, k.allocation_scope,
            k.donation_type, k.item_name, k.currency, k.commitment_status,
            k.purpose, k.country, k.location, k.source_excerpt,
            TRY_CAST(k.quantity AS DECIMAL(18,2))                           AS qty,
            TRY_CAST(k.amount_original AS DECIMAL(18,2))                    AS amt,
            TRY_CAST(k.amount_per_recipient AS DECIMAL(18,2))               AS amt_each,
            TRY_CAST(k.amount_usd AS DECIMAL(18,2))                         AS usd,
            TRY_CAST(LEFT(k.donation_date, 10) AS DATE)                     AS d_don,
            ROW_NUMBER() OVER (PARTITION BY TRY_CAST(e.donation_id AS INT) ORDER BY (SELECT 1)) AS rn
        FROM bronze.llm_donations_extract e
        CROSS APPLY (
            -- trim, drop line breaks, and treat '' and the text NULL as missing
            SELECT
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.tweet_id,             CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS tweet_id,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.donor_name,           CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS donor_name,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.recipient_name,       CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS recipient_name,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.recipient_type,       CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS recipient_type,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.allocation_scope,     CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS allocation_scope,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.donation_type,        CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS donation_type,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.item_name,            CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS item_name,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.currency,             CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS currency,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.commitment_status,    CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS commitment_status,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.purpose,              CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS purpose,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.country,              CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS country,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.location,             CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS location,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.source_excerpt,       CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS source_excerpt,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.quantity,             CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS quantity,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.amount_original,      CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS amount_original,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.amount_per_recipient, CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS amount_per_recipient,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.amount_usd,           CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS amount_usd,
                NULLIF(NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(e.donation_date,        CHAR(13), ''), CHAR(10), ' '))), N''), N'NULL') AS donation_date
        ) k
    )
    SELECT
        c.sid,
        c.tweet_id,
        COALESCE(tw.d_tw, c.d_don)                                   AS d_tw,
        COALESCE(c.d_don, tw.d_tw)                                   AS d_don,
        COALESCE(c.donor_name, N'Wicknell Chivayo')                  AS donor_name,
        COALESCE(c.recipient_name, N'Unknown recipient')             AS recipient_name,
        COALESCE(c.recipient_type, N'Other')                         AS recipient_type,
        c.allocation_scope, c.donation_type, c.item_name,
        UPPER(c.currency)                                            AS currency,
        c.commitment_status, c.purpose, c.country, c.location, c.source_excerpt,
        CASE WHEN c.qty > 0 THEN c.qty END                           AS qty,      -- n8n writes 0 when no quantity is stated
        c.amt, c.amt_each, c.usd,
        CASE
            WHEN c.donation_type = N'Cash'    THEN 'money'
            WHEN c.donation_type = N'Vehicle' THEN 'vehicle'
            WHEN c.donation_type = N'Property'
                 AND (   c.item_name LIKE N'%house%'  OR c.item_name LIKE N'%home%'
                      OR c.item_name LIKE N'%residen%' OR c.item_name LIKE N'%apartment%'
                      OR c.item_name LIKE N'%mansion%' OR c.item_name LIKE N'%villa%') THEN 'house'
            ELSE 'other'
        END                                                          AS target
    INTO #new
    FROM cleaned c
    OUTER APPLY (
        SELECT TOP 1 CAST(TRY_CAST(t.tweet_created_at AS DATETIME2) AS DATE) AS d_tw
        FROM bronze.twitter_raw_tweets t
        WHERE TRY_CAST(t.tweet_id AS BIGINT) = c.tweet_id
        ORDER BY TRY_CAST(t.tweet_created_at AS DATETIME2) DESC
    ) tw
    WHERE c.rn = 1
      AND c.sid IS NOT NULL
      AND c.tweet_id IS NOT NULL            -- Silver needs a tweet id
      AND NOT EXISTS (SELECT 1 FROM #handled h WHERE h.sid = c.sid);

    DECLARE @note_prefix NVARCHAR(200) = N'Sorted automatically by rule from the LLM donation type "';
    DECLARE @note_suffix NVARCHAR(200) = N'". Not reviewed yet.';

    -- ---------------- money ----------------
    INSERT INTO bronze.reviewed_money
        (money_id, source_donation_id, tweet_id, tweet_url, tweet_date, donation_date, donor_name,
         recipient_name, recipient_type, allocation_scope, recipient_count, amount_per_recipient,
         currency, total_amount, total_amount_usd, money_nature, commitment_status, purpose,
         country, location, source_excerpt, origin, calc_check, review_flag, review_note, overlap_group)
    SELECT
        CONCAT(N'MA', n.sid), n.sid, n.tweet_id, CONCAT(N'https://x.com/i/status/', n.tweet_id),
        CONVERT(NVARCHAR(10), n.d_tw, 23), CONVERT(NVARCHAR(10), n.d_don, 23), n.donor_name,
        n.recipient_name, n.recipient_type, n.allocation_scope,
        rc.recipient_count,
        COALESCE(n.amt_each, CASE WHEN rc.recipient_count > 0 THEN CAST(n.amt / rc.recipient_count AS DECIMAL(18,2)) END),
        n.currency, tot.total_amount,
        -- USD total: recalculated when the total is "each x count"; other currencies are converted in Silver
        CASE WHEN tot.is_each_x_count = 1 THEN CASE WHEN COALESCE(n.currency, N'USD') = N'USD' THEN tot.total_amount END
             ELSE n.usd END,
        N'gift', n.commitment_status, n.purpose,
        n.country, n.location, n.source_excerpt, N'auto_rule',
        CASE WHEN tot.total_amount IS NULL OR rc.recipient_count IS NULL THEN N'NOT_COMPUTABLE' ELSE N'OK' END,
        N'auto_unreviewed',
        CONCAT(@note_prefix, n.donation_type, @note_suffix,
               CASE WHEN tot.is_each_x_count = 1 THEN N' Total = amount per recipient x recipient count.' END),
        NULL
    FROM #new n
    CROSS APPLY (SELECT CASE WHEN n.allocation_scope = N'Per Recipient' THEN CAST(n.qty AS INT)
                             WHEN n.allocation_scope = N'Group'         THEN NULL
                             ELSE 1 END AS recipient_count) rc
    -- "USD 10,000 each to 5 people": the LLM often stores only the per-person figure, so the total is each x count
    CROSS APPLY (SELECT CASE WHEN n.allocation_scope = N'Per Recipient' AND n.amt_each IS NOT NULL AND rc.recipient_count > 1
                             THEN CAST(n.amt_each * rc.recipient_count AS DECIMAL(18,2)) ELSE n.amt END AS total_amount,
                        CASE WHEN n.allocation_scope = N'Per Recipient' AND n.amt_each IS NOT NULL AND rc.recipient_count > 1
                             THEN 1 ELSE 0 END AS is_each_x_count) tot
    WHERE n.target = 'money';
    DECLARE @n_money INT = @@ROWCOUNT;

    -- ---------------- vehicle ----------------
    INSERT INTO bronze.reviewed_vehicle
        (vehicle_id, source_donation_id, tweet_id, tweet_url, tweet_date, donation_date, donor_name,
         recipient_name, recipient_type, allocation_scope, vehicle_class, item_name, quantity,
         unit_value_usd, total_value_usd, bundle_key, bundle_value_usd_DO_NOT_SUM, commitment_status,
         purpose, country, location, source_excerpt, origin, calc_check, review_flag, review_note, overlap_group)
    SELECT
        CONCAT(N'VA', n.sid), n.sid, n.tweet_id, CONCAT(N'https://x.com/i/status/', n.tweet_id),
        CONVERT(NVARCHAR(10), n.d_tw, 23), CONVERT(NVARCHAR(10), n.d_don, 23), n.donor_name,
        n.recipient_name, n.recipient_type, n.allocation_scope,
        CASE WHEN n.item_name IS NULL                THEN N'Unspecified'
             WHEN n.item_name LIKE N'%ambulance%'    THEN N'Ambulance'
             WHEN n.item_name LIKE N'%bus%'          THEN N'Bus'
             WHEN n.item_name LIKE N'%truck%'   OR n.item_name LIKE N'%pick%up%' OR n.item_name LIKE N'%pickup%'
               OR n.item_name LIKE N'%double cab%' OR n.item_name LIKE N'%hilux%' OR n.item_name LIKE N'%ranger%'
               OR n.item_name LIKE N'%d-max%'   OR n.item_name LIKE N'%navara%'  OR n.item_name LIKE N'%bt-50%'
               OR n.item_name LIKE N'%amarok%'  OR n.item_name LIKE N'%triton%'  THEN N'Pickup/Truck'
             ELSE N'Car/SUV' END,
        n.item_name, CAST(COALESCE(n.qty, 1) AS INT),
        CAST(n.usd / COALESCE(n.qty, 1) AS DECIMAL(18,2)), n.usd, NULL, NULL, n.commitment_status,
        n.purpose, n.country, n.location, n.source_excerpt, N'auto_rule',
        CASE WHEN n.usd IS NULL THEN N'NOT_COMPUTABLE' ELSE N'OK' END,
        N'auto_unreviewed', CONCAT(@note_prefix, n.donation_type, @note_suffix), NULL
    FROM #new n
    WHERE n.target = 'vehicle';
    DECLARE @n_vehicle INT = @@ROWCOUNT;

    -- ---------------- house ----------------
    INSERT INTO bronze.reviewed_house
        (house_id, source_donation_id, tweet_id, tweet_url, tweet_date, donation_date, donor_name,
         recipient_name, recipient_type, allocation_scope, house_count, unit_value, currency,
         total_value, total_value_usd, furnished, commitment_status, purpose, country, location,
         source_excerpt, origin, calc_check, house_nature, review_flag, review_note, overlap_group)
    SELECT
        CONCAT(N'HA', n.sid), n.sid, n.tweet_id, CONCAT(N'https://x.com/i/status/', n.tweet_id),
        CONVERT(NVARCHAR(10), n.d_tw, 23), CONVERT(NVARCHAR(10), n.d_don, 23), n.donor_name,
        n.recipient_name, n.recipient_type, n.allocation_scope, CAST(COALESCE(n.qty, 1) AS INT),
        CAST(n.amt / COALESCE(n.qty, 1) AS DECIMAL(18,2)), n.currency,
        n.amt, n.usd, CASE WHEN n.item_name LIKE N'%furnish%' THEN N'True' ELSE N'False' END,
        n.commitment_status, n.purpose, n.country, n.location,
        n.source_excerpt, N'auto_rule',
        CASE WHEN n.amt IS NULL THEN N'NOT_COMPUTABLE' ELSE N'OK' END,
        N'house_bought_for_recipient',
        N'auto_unreviewed', CONCAT(@note_prefix, n.donation_type, @note_suffix), NULL
    FROM #new n
    WHERE n.target = 'house';
    DECLARE @n_house INT = @@ROWCOUNT;

    -- ---------------- other giving ----------------
    INSERT INTO bronze.reviewed_other_giving
        (other_id, source_donation_id, tweet_id, tweet_url, tweet_date, donation_date, donor_name,
         recipient_name, recipient_type, allocation_scope, category, item_name, quantity, quantity_unit,
         unit_value_usd, total_value_usd, commitment_status, purpose, country, location,
         source_excerpt, origin, review_flag, review_note, overlap_group)
    SELECT
        CONCAT(N'OA', n.sid), n.sid, n.tweet_id, CONCAT(N'https://x.com/i/status/', n.tweet_id),
        CONVERT(NVARCHAR(10), n.d_tw, 23), CONVERT(NVARCHAR(10), n.d_don, 23), n.donor_name,
        n.recipient_name, n.recipient_type, n.allocation_scope,
        CASE n.donation_type WHEN N'Equipment'         THEN N'Equipment'
                             WHEN N'Education Support' THEN N'Education / training'
                             WHEN N'Medical Support'   THEN N'Medical support'
                             WHEN N'Service'           THEN N'Service'
                             WHEN N'Property'          THEN N'Property'
                             ELSE N'Unspecified gift' END,
        n.item_name, n.qty, CASE WHEN n.qty IS NOT NULL THEN N'units' END,
        CASE WHEN n.qty IS NOT NULL THEN CAST(n.usd / n.qty AS DECIMAL(18,2)) END, n.usd,
        n.commitment_status, n.purpose, n.country, n.location,
        n.source_excerpt, N'auto_rule',
        N'auto_unreviewed', CONCAT(@note_prefix, COALESCE(n.donation_type, N'(none)'), @note_suffix), NULL
    FROM #new n
    WHERE n.target = 'other';
    DECLARE @n_other INT = @@ROWCOUNT;

    DECLARE @skipped INT = (
        SELECT COUNT(*) FROM bronze.llm_donations_extract e
        WHERE TRY_CAST(e.donation_id AS INT) IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #handled h WHERE h.sid = TRY_CAST(e.donation_id AS INT))
          AND NOT EXISTS (SELECT 1 FROM #new n WHERE n.sid = TRY_CAST(e.donation_id AS INT)));

    PRINT '>> New donations sorted automatically: money ' + CAST(@n_money AS NVARCHAR(10))
        + ', vehicle ' + CAST(@n_vehicle AS NVARCHAR(10))
        + ', house ' + CAST(@n_house AS NVARCHAR(10))
        + ', other ' + CAST(@n_other AS NVARCHAR(10))
        + ' (skipped, no tweet id: ' + CAST(@skipped AS NVARCHAR(10)) + ')';

    SELECT @n_money AS new_money, @n_vehicle AS new_vehicle, @n_house AS new_house,
           @n_other AS new_other, @skipped AS skipped_no_tweet_id;
END;
GO


-- ---------------------------------------------------------
-- The whole run. Stops before Silver if any file failed to
-- load, so the dashboard keeps its last good data.
-- ---------------------------------------------------------
CREATE OR ALTER PROCEDURE bronze.run_pipeline
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start DATETIME2 = SYSDATETIME();
    DECLARE @failed NVARCHAR(1000), @msg NVARCHAR(2000);

    EXEC bronze.load_bronze;          -- curated CSVs + LLM extract
    EXEC bronze.load_n8n_sources;     -- raw tweets + reviewed baseline

    SELECT @failed = STRING_AGG(table_name, N', ')
    FROM bronze.load_log
    WHERE load_start >= @start AND status = N'FAILED';

    IF @failed IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'Bronze load failed for: ', @failed,
                          N'. Silver was NOT reloaded. See bronze.load_log for the error.');
        THROW 50010, @msg, 1;
    END;

    IF NOT EXISTS (SELECT 1 FROM bronze.reviewed_baseline)
        THROW 50011, N'bronze.reviewed_baseline is empty. Without it every old row would be added again. Silver was NOT reloaded.', 1;

    EXEC bronze.add_unreviewed_donations;
    EXEC silver.load_silver;

    SELECT 'gold.fact_donations' AS result,
           COUNT(*) AS donation_lines,
           SUM(CASE WHEN review_flag = N'auto_unreviewed' THEN 1 ELSE 0 END) AS auto_unreviewed_lines,
           SUM(CASE WHEN counts_toward_total = 1 THEN cash_amount_usd END) AS counted_cash_usd
    FROM gold.fact_donations;
END;
GO
