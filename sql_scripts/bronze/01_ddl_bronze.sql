
/*
=============================================================
DDL Script: Create Bronze Tables
=============================================================
Layer   : bronze  (raw data, as-is, no transformation)
Purpose : One table per source file. Every column is text
          (NVARCHAR) so nothing is changed or rejected at load.
          Types are applied in the Silver layer.
Re-run  : Drops and recreates the tables (the data is reloaded
          by bronze.load_bronze).
=============================================================
*/

USE DonationsDW;
GO


-- Raw tweets exported from Postgres (n8n target)
IF OBJECT_ID('bronze.twitter_raw_tweets', 'U') IS NOT NULL
    DROP TABLE bronze.twitter_raw_tweets;
GO

CREATE TABLE bronze.twitter_raw_tweets (
    [tweet_id] NVARCHAR(50) NULL,
    [tweet_created_at] NVARCHAR(500) NULL,
    [author_username] NVARCHAR(500) NULL,
    [tweet_text] NVARCHAR(MAX) NULL
);
GO


-- Original LLM classification, untouched (the "before" picture)
IF OBJECT_ID('bronze.llm_donations_extract', 'U') IS NOT NULL
    DROP TABLE bronze.llm_donations_extract;
GO

CREATE TABLE bronze.llm_donations_extract (
    [donation_id] NVARCHAR(50) NULL,
    [tweet_id] NVARCHAR(50) NULL,
    [donor_name] NVARCHAR(500) NULL,
    [recipient_name] NVARCHAR(1000) NULL,
    [donation_description] NVARCHAR(4000) NULL,
    [amount_original] NVARCHAR(50) NULL,
    [currency] NVARCHAR(50) NULL,
    [amount_usd] NVARCHAR(50) NULL,
    [donation_date] NVARCHAR(50) NULL,
    [country] NVARCHAR(500) NULL,
    [location] NVARCHAR(4000) NULL,
    [donation_theme] NVARCHAR(500) NULL,
    [confidence_score] NVARCHAR(50) NULL,
    [ai_explanation] NVARCHAR(4000) NULL,
    [extracted_at] NVARCHAR(50) NULL,
    [donation_key] NVARCHAR(50) NULL,
    [recipient_type] NVARCHAR(500) NULL,
    [donation_type] NVARCHAR(500) NULL,
    [item_name] NVARCHAR(4000) NULL,
    [quantity] NVARCHAR(50) NULL,
    [amount_per_recipient] NVARCHAR(50) NULL,
    [purpose] NVARCHAR(4000) NULL,
    [commitment_status] NVARCHAR(500) NULL,
    [source_excerpt] NVARCHAR(4000) NULL,
    [beneficiary_names] NVARCHAR(4000) NULL,
    [allocation_scope] NVARCHAR(500) NULL
);
GO


-- Manually reviewed classification: money
IF OBJECT_ID('bronze.reviewed_money', 'U') IS NOT NULL
    DROP TABLE bronze.reviewed_money;
GO

CREATE TABLE bronze.reviewed_money (
    [money_id] NVARCHAR(50) NULL,
    [source_donation_id] NVARCHAR(50) NULL,
    [tweet_id] NVARCHAR(50) NULL,
    [tweet_url] NVARCHAR(500) NULL,
    [tweet_date] NVARCHAR(50) NULL,
    [donation_date] NVARCHAR(50) NULL,
    [donor_name] NVARCHAR(500) NULL,
    [recipient_name] NVARCHAR(1000) NULL,
    [recipient_type] NVARCHAR(500) NULL,
    [allocation_scope] NVARCHAR(500) NULL,
    [recipient_count] NVARCHAR(50) NULL,
    [amount_per_recipient] NVARCHAR(50) NULL,
    [currency] NVARCHAR(50) NULL,
    [total_amount] NVARCHAR(50) NULL,
    [total_amount_usd] NVARCHAR(50) NULL,
    [money_nature] NVARCHAR(500) NULL,
    [commitment_status] NVARCHAR(500) NULL,
    [purpose] NVARCHAR(4000) NULL,
    [country] NVARCHAR(500) NULL,
    [location] NVARCHAR(4000) NULL,
    [source_excerpt] NVARCHAR(4000) NULL,
    [origin] NVARCHAR(500) NULL,
    [calc_check] NVARCHAR(500) NULL,
    [review_flag] NVARCHAR(500) NULL,
    [review_note] NVARCHAR(4000) NULL,
    [overlap_group] NVARCHAR(500) NULL
);
GO


-- Manually reviewed classification: vehicles
IF OBJECT_ID('bronze.reviewed_vehicle', 'U') IS NOT NULL
    DROP TABLE bronze.reviewed_vehicle;
GO

CREATE TABLE bronze.reviewed_vehicle (
    [vehicle_id] NVARCHAR(50) NULL,
    [source_donation_id] NVARCHAR(50) NULL,
    [tweet_id] NVARCHAR(50) NULL,
    [tweet_url] NVARCHAR(500) NULL,
    [tweet_date] NVARCHAR(50) NULL,
    [donation_date] NVARCHAR(50) NULL,
    [donor_name] NVARCHAR(500) NULL,
    [recipient_name] NVARCHAR(1000) NULL,
    [recipient_type] NVARCHAR(500) NULL,
    [allocation_scope] NVARCHAR(500) NULL,
    [vehicle_class] NVARCHAR(500) NULL,
    [item_name] NVARCHAR(4000) NULL,
    [quantity] NVARCHAR(50) NULL,
    [unit_value_usd] NVARCHAR(50) NULL,
    [total_value_usd] NVARCHAR(50) NULL,
    [bundle_key] NVARCHAR(500) NULL,
    [bundle_value_usd_DO_NOT_SUM] NVARCHAR(50) NULL,
    [commitment_status] NVARCHAR(500) NULL,
    [purpose] NVARCHAR(4000) NULL,
    [country] NVARCHAR(500) NULL,
    [location] NVARCHAR(4000) NULL,
    [source_excerpt] NVARCHAR(4000) NULL,
    [origin] NVARCHAR(500) NULL,
    [calc_check] NVARCHAR(500) NULL,
    [review_flag] NVARCHAR(500) NULL,
    [review_note] NVARCHAR(4000) NULL,
    [overlap_group] NVARCHAR(500) NULL
);
GO


-- Manually reviewed classification: houses
IF OBJECT_ID('bronze.reviewed_house', 'U') IS NOT NULL
    DROP TABLE bronze.reviewed_house;
GO

CREATE TABLE bronze.reviewed_house (
    [house_id] NVARCHAR(50) NULL,
    [source_donation_id] NVARCHAR(50) NULL,
    [tweet_id] NVARCHAR(50) NULL,
    [tweet_url] NVARCHAR(500) NULL,
    [tweet_date] NVARCHAR(50) NULL,
    [donation_date] NVARCHAR(50) NULL,
    [donor_name] NVARCHAR(500) NULL,
    [recipient_name] NVARCHAR(1000) NULL,
    [recipient_type] NVARCHAR(500) NULL,
    [allocation_scope] NVARCHAR(500) NULL,
    [house_count] NVARCHAR(50) NULL,
    [unit_value] NVARCHAR(50) NULL,
    [currency] NVARCHAR(50) NULL,
    [total_value] NVARCHAR(50) NULL,
    [total_value_usd] NVARCHAR(50) NULL,
    [furnished] NVARCHAR(50) NULL,
    [commitment_status] NVARCHAR(500) NULL,
    [purpose] NVARCHAR(4000) NULL,
    [country] NVARCHAR(500) NULL,
    [location] NVARCHAR(4000) NULL,
    [source_excerpt] NVARCHAR(4000) NULL,
    [origin] NVARCHAR(500) NULL,
    [calc_check] NVARCHAR(500) NULL,
    [house_nature] NVARCHAR(500) NULL,
    [review_flag] NVARCHAR(500) NULL,
    [review_note] NVARCHAR(4000) NULL,
    [overlap_group] NVARCHAR(500) NULL
);
GO


-- Manually reviewed classification: other giving
IF OBJECT_ID('bronze.reviewed_other_giving', 'U') IS NOT NULL
    DROP TABLE bronze.reviewed_other_giving;
GO

CREATE TABLE bronze.reviewed_other_giving (
    [other_id] NVARCHAR(50) NULL,
    [source_donation_id] NVARCHAR(50) NULL,
    [tweet_id] NVARCHAR(50) NULL,
    [tweet_url] NVARCHAR(500) NULL,
    [tweet_date] NVARCHAR(50) NULL,
    [donation_date] NVARCHAR(50) NULL,
    [donor_name] NVARCHAR(500) NULL,
    [recipient_name] NVARCHAR(1000) NULL,
    [recipient_type] NVARCHAR(500) NULL,
    [allocation_scope] NVARCHAR(500) NULL,
    [category] NVARCHAR(500) NULL,
    [item_name] NVARCHAR(4000) NULL,
    [quantity] NVARCHAR(50) NULL,
    [quantity_unit] NVARCHAR(500) NULL,
    [unit_value_usd] NVARCHAR(50) NULL,
    [total_value_usd] NVARCHAR(50) NULL,
    [commitment_status] NVARCHAR(500) NULL,
    [purpose] NVARCHAR(4000) NULL,
    [country] NVARCHAR(500) NULL,
    [location] NVARCHAR(4000) NULL,
    [source_excerpt] NVARCHAR(4000) NULL,
    [origin] NVARCHAR(500) NULL,
    [review_flag] NVARCHAR(500) NULL,
    [review_note] NVARCHAR(4000) NULL,
    [overlap_group] NVARCHAR(500) NULL
);
GO


-- Rows judged not to be donations
IF OBJECT_ID('bronze.reviewed_excluded', 'U') IS NOT NULL
    DROP TABLE bronze.reviewed_excluded;
GO

CREATE TABLE bronze.reviewed_excluded (
    [source_donation_id] NVARCHAR(50) NULL,
    [tweet_id] NVARCHAR(50) NULL,
    [tweet_url] NVARCHAR(500) NULL,
    [tweet_date] NVARCHAR(50) NULL,
    [donation_date] NVARCHAR(50) NULL,
    [donor_name] NVARCHAR(500) NULL,
    [recipient_name] NVARCHAR(1000) NULL,
    [recipient_type] NVARCHAR(500) NULL,
    [allocation_scope] NVARCHAR(500) NULL,
    [donation_type_in_source] NVARCHAR(500) NULL,
    [item_name] NVARCHAR(4000) NULL,
    [amount_original] NVARCHAR(50) NULL,
    [currency] NVARCHAR(50) NULL,
    [amount_usd] NVARCHAR(50) NULL,
    [reason_excluded] NVARCHAR(4000) NULL,
    [source_excerpt] NVARCHAR(4000) NULL
);
GO


-- Every change made to the LLM output
IF OBJECT_ID('bronze.reviewed_corrections_log', 'U') IS NOT NULL
    DROP TABLE bronze.reviewed_corrections_log;
GO

CREATE TABLE bronze.reviewed_corrections_log (
    [log_id] NVARCHAR(50) NULL,
    [source_donation_id] NVARCHAR(50) NULL,
    [field] NVARCHAR(500) NULL,
    [old_value] NVARCHAR(4000) NULL,
    [new_value] NVARCHAR(4000) NULL,
    [reason] NVARCHAR(4000) NULL
);
GO


-- Audit table: one row per file per load (rows loaded, duration, errors)
IF OBJECT_ID('bronze.load_log', 'U') IS NOT NULL
    DROP TABLE bronze.load_log;
GO

CREATE TABLE bronze.load_log (
    log_id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_bronze_load_log PRIMARY KEY,
    batch_id      UNIQUEIDENTIFIER  NOT NULL,
    table_name    SYSNAME           NOT NULL,
    source_file   NVARCHAR(260)     NOT NULL,
    rows_loaded   INT               NULL,
    load_start    DATETIME2         NOT NULL,
    load_end      DATETIME2         NOT NULL,
    duration_sec  AS DATEDIFF(SECOND, load_start, load_end),
    status        NVARCHAR(20)      NOT NULL,   -- SUCCESS or FAILED
    error_message NVARCHAR(4000)    NULL
);
GO
