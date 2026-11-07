/*
=============================================================
DDL Script: Create Silver Tables (+ helper function)
=============================================================
Layer   : silver  (cleaned and standardised data)
Tables  : 9
            1 silver.donation_money      5 silver.tweet
            2 silver.donation_vehicle    6 silver.recipient
            3 silver.donation_house      7 silver.exchange_rate
            4 silver.donation_other      8 silver.excluded
                                         9 silver.data_quality_issues
Rules   : Data types are applied here (dates, decimals, ints, bits).
          Text is trimmed and standardised, ZAR is converted to USD,
          derived columns are added. No foreign keys, so the tables
          can be reloaded with TRUNCATE.
Re-run  : Drops and recreates the objects.
=============================================================
*/

USE DonationsDW;
GO

-- ---------------------------------------------------------
-- Helper function: trims text, removes line breaks/tabs,
-- collapses double spaces and turns empty text into NULL.
-- ---------------------------------------------------------
CREATE OR ALTER FUNCTION silver.fn_clean_text (@x NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @r NVARCHAR(MAX) = @x;
    SET @r = REPLACE(REPLACE(REPLACE(@r, CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' ');
    SET @r = REPLACE(REPLACE(REPLACE(@r, '  ', ' '), '  ', ' '), '  ', ' ');
    SET @r = LTRIM(RTRIM(@r));
    RETURN NULLIF(@r, '');
END;
GO

-- ---------------------------------------------------------
-- 7. Exchange rates (reference table)
-- ---------------------------------------------------------
IF OBJECT_ID('silver.exchange_rate', 'U') IS NOT NULL
    DROP TABLE silver.exchange_rate;
GO

CREATE TABLE silver.exchange_rate (
    currency_code CHAR(3)       NOT NULL CONSTRAINT PK_silver_exchange_rate PRIMARY KEY,
    rate_to_usd   DECIMAL(18,8) NOT NULL,
    rate_source   NVARCHAR(300) NULL,
    dwh_load_date DATETIME2     NOT NULL CONSTRAINT DF_exchange_rate_load DEFAULT SYSDATETIME()
);
GO

-- ---------------------------------------------------------
-- 6. Recipients (one row per standardised recipient)
-- ---------------------------------------------------------
IF OBJECT_ID('silver.recipient', 'U') IS NOT NULL
    DROP TABLE silver.recipient;
GO

CREATE TABLE silver.recipient (
    recipient_id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_silver_recipient PRIMARY KEY,
    recipient_name      NVARCHAR(500) NOT NULL CONSTRAINT UQ_silver_recipient_name UNIQUE,
    recipient_type      NVARCHAR(50)  NULL,
    recipient_group     NVARCHAR(50)  NOT NULL,
    name_variants_count INT           NOT NULL,   -- how many spellings were merged into this name
    dwh_load_date       DATETIME2     NOT NULL CONSTRAINT DF_recipient_load DEFAULT SYSDATETIME()
);
GO

-- ---------------------------------------------------------
-- 1 to 4. Donation tables
-- ---------------------------------------------------------

IF OBJECT_ID('silver.donation_money', 'U') IS NOT NULL
    DROP TABLE silver.donation_money;
GO

CREATE TABLE silver.donation_money (
    [money_id] NVARCHAR(10) NOT NULL,
    [source_donation_id] INT NOT NULL,
    [tweet_id] BIGINT NOT NULL,
    [tweet_date] DATE NULL,
    [donation_date] DATE NULL,
    [donation_year] SMALLINT NULL,
    [donation_month] TINYINT NULL,
    [days_tweet_to_donation] INT NULL,
    [donor_name] NVARCHAR(100) NULL,
    [recipient_id] INT NOT NULL,
    [recipient_name] NVARCHAR(500) NOT NULL,
    [recipient_name_original] NVARCHAR(500) NOT NULL,
    [recipient_type] NVARCHAR(50) NULL,
    [recipient_group] NVARCHAR(50) NOT NULL,
    [allocation_scope] NVARCHAR(30) NULL,
    [recipient_count] INT NULL,
    [amount_per_recipient] DECIMAL(18,2) NULL,
    [currency] CHAR(3) NULL,
    [total_amount] DECIMAL(18,2) NULL,
    [total_amount_usd] DECIMAL(18,2) NULL,
    [usd_is_converted] BIT NOT NULL,
    [money_nature] NVARCHAR(50) NULL,
    [calc_check] NVARCHAR(30) NULL,
    [commitment_status] NVARCHAR(30) NULL,
    [status_group] NVARCHAR(20) NOT NULL,
    [is_pledge] BIT NOT NULL,
    [is_delivered] BIT NOT NULL,
    [purpose] NVARCHAR(500) NULL,
    [country] NVARCHAR(100) NULL,
    [location] NVARCHAR(500) NULL,
    [source_excerpt] NVARCHAR(1000) NULL,
    [origin] NVARCHAR(50) NULL,
    [review_flag] NVARCHAR(100) NULL,
    [review_note] NVARCHAR(2000) NULL,
    [overlap_group] NVARCHAR(100) NULL,
    [counts_toward_total] BIT NOT NULL,
    [not_counted_reason] NVARCHAR(300) NULL,
    [dwh_load_date] DATETIME2 NOT NULL CONSTRAINT DF_donation_money_load DEFAULT SYSDATETIME()
    ,CONSTRAINT PK_silver_donation_money PRIMARY KEY (money_id)
);
GO

IF OBJECT_ID('silver.donation_vehicle', 'U') IS NOT NULL
    DROP TABLE silver.donation_vehicle;
GO

CREATE TABLE silver.donation_vehicle (
    [vehicle_id] NVARCHAR(10) NOT NULL,
    [source_donation_id] INT NOT NULL,
    [tweet_id] BIGINT NOT NULL,
    [tweet_date] DATE NULL,
    [donation_date] DATE NULL,
    [donation_year] SMALLINT NULL,
    [donation_month] TINYINT NULL,
    [days_tweet_to_donation] INT NULL,
    [donor_name] NVARCHAR(100) NULL,
    [recipient_id] INT NOT NULL,
    [recipient_name] NVARCHAR(500) NOT NULL,
    [recipient_name_original] NVARCHAR(500) NOT NULL,
    [recipient_type] NVARCHAR(50) NULL,
    [recipient_group] NVARCHAR(50) NOT NULL,
    [allocation_scope] NVARCHAR(30) NULL,
    [vehicle_class] NVARCHAR(30) NULL,
    [item_name] NVARCHAR(200) NULL,
    [quantity] INT NULL,
    [unit_value_usd] DECIMAL(18,2) NULL,
    [total_value_usd] DECIMAL(18,2) NULL,
    [bundle_key] NVARCHAR(100) NULL,
    [bundle_value_usd] DECIMAL(18,2) NULL,
    [calc_check] NVARCHAR(30) NULL,
    [commitment_status] NVARCHAR(30) NULL,
    [status_group] NVARCHAR(20) NOT NULL,
    [is_pledge] BIT NOT NULL,
    [is_delivered] BIT NOT NULL,
    [purpose] NVARCHAR(500) NULL,
    [country] NVARCHAR(100) NULL,
    [location] NVARCHAR(500) NULL,
    [source_excerpt] NVARCHAR(1000) NULL,
    [origin] NVARCHAR(50) NULL,
    [review_flag] NVARCHAR(100) NULL,
    [review_note] NVARCHAR(2000) NULL,
    [overlap_group] NVARCHAR(100) NULL,
    [counts_toward_total] BIT NOT NULL,
    [not_counted_reason] NVARCHAR(300) NULL,
    [dwh_load_date] DATETIME2 NOT NULL CONSTRAINT DF_donation_vehicle_load DEFAULT SYSDATETIME()
    ,CONSTRAINT PK_silver_donation_vehicle PRIMARY KEY (vehicle_id)
);
GO

IF OBJECT_ID('silver.donation_house', 'U') IS NOT NULL
    DROP TABLE silver.donation_house;
GO

CREATE TABLE silver.donation_house (
    [house_id] NVARCHAR(10) NOT NULL,
    [source_donation_id] INT NOT NULL,
    [tweet_id] BIGINT NOT NULL,
    [tweet_date] DATE NULL,
    [donation_date] DATE NULL,
    [donation_year] SMALLINT NULL,
    [donation_month] TINYINT NULL,
    [days_tweet_to_donation] INT NULL,
    [donor_name] NVARCHAR(100) NULL,
    [recipient_id] INT NOT NULL,
    [recipient_name] NVARCHAR(500) NOT NULL,
    [recipient_name_original] NVARCHAR(500) NOT NULL,
    [recipient_type] NVARCHAR(50) NULL,
    [recipient_group] NVARCHAR(50) NOT NULL,
    [allocation_scope] NVARCHAR(30) NULL,
    [house_count] INT NULL,
    [unit_value] DECIMAL(18,2) NULL,
    [currency] CHAR(3) NULL,
    [total_value] DECIMAL(18,2) NULL,
    [total_value_usd] DECIMAL(18,2) NULL,
    [usd_is_converted] BIT NOT NULL,
    [furnished] BIT NULL,
    [house_nature] NVARCHAR(50) NULL,
    [calc_check] NVARCHAR(30) NULL,
    [commitment_status] NVARCHAR(30) NULL,
    [status_group] NVARCHAR(20) NOT NULL,
    [is_pledge] BIT NOT NULL,
    [is_delivered] BIT NOT NULL,
    [purpose] NVARCHAR(500) NULL,
    [country] NVARCHAR(100) NULL,
    [location] NVARCHAR(500) NULL,
    [source_excerpt] NVARCHAR(1000) NULL,
    [origin] NVARCHAR(50) NULL,
    [review_flag] NVARCHAR(100) NULL,
    [review_note] NVARCHAR(2000) NULL,
    [overlap_group] NVARCHAR(100) NULL,
    [counts_toward_total] BIT NOT NULL,
    [not_counted_reason] NVARCHAR(300) NULL,
    [dwh_load_date] DATETIME2 NOT NULL CONSTRAINT DF_donation_house_load DEFAULT SYSDATETIME()
    ,CONSTRAINT PK_silver_donation_house PRIMARY KEY (house_id)
);
GO

IF OBJECT_ID('silver.donation_other', 'U') IS NOT NULL
    DROP TABLE silver.donation_other;
GO

CREATE TABLE silver.donation_other (
    [other_id] NVARCHAR(10) NOT NULL,
    [source_donation_id] INT NOT NULL,
    [tweet_id] BIGINT NOT NULL,
    [tweet_date] DATE NULL,
    [donation_date] DATE NULL,
    [donation_year] SMALLINT NULL,
    [donation_month] TINYINT NULL,
    [days_tweet_to_donation] INT NULL,
    [donor_name] NVARCHAR(100) NULL,
    [recipient_id] INT NOT NULL,
    [recipient_name] NVARCHAR(500) NOT NULL,
    [recipient_name_original] NVARCHAR(500) NOT NULL,
    [recipient_type] NVARCHAR(50) NULL,
    [recipient_group] NVARCHAR(50) NOT NULL,
    [allocation_scope] NVARCHAR(30) NULL,
    [category] NVARCHAR(60) NULL,
    [item_name] NVARCHAR(300) NULL,
    [quantity] DECIMAL(18,2) NULL,
    [quantity_unit] NVARCHAR(30) NULL,
    [unit_value_usd] DECIMAL(18,2) NULL,
    [total_value_usd] DECIMAL(18,2) NULL,
    [commitment_status] NVARCHAR(30) NULL,
    [status_group] NVARCHAR(20) NOT NULL,
    [is_pledge] BIT NOT NULL,
    [is_delivered] BIT NOT NULL,
    [purpose] NVARCHAR(500) NULL,
    [country] NVARCHAR(100) NULL,
    [location] NVARCHAR(500) NULL,
    [source_excerpt] NVARCHAR(1000) NULL,
    [origin] NVARCHAR(50) NULL,
    [review_flag] NVARCHAR(100) NULL,
    [review_note] NVARCHAR(2000) NULL,
    [overlap_group] NVARCHAR(100) NULL,
    [counts_toward_total] BIT NOT NULL,
    [not_counted_reason] NVARCHAR(300) NULL,
    [dwh_load_date] DATETIME2 NOT NULL CONSTRAINT DF_donation_other_load DEFAULT SYSDATETIME()
    ,CONSTRAINT PK_silver_donation_other PRIMARY KEY (other_id)
);
GO

-- ---------------------------------------------------------
-- 8. Rows that are not donations (aggregates, declined, etc.)
-- ---------------------------------------------------------
IF OBJECT_ID('silver.excluded', 'U') IS NOT NULL
    DROP TABLE silver.excluded;
GO

CREATE TABLE silver.excluded (
    source_donation_id      INT           NOT NULL CONSTRAINT PK_silver_excluded PRIMARY KEY,
    tweet_id                BIGINT        NOT NULL,
    tweet_date              DATE          NULL,
    donation_date           DATE          NULL,
    donor_name              NVARCHAR(100) NULL,
    recipient_name          NVARCHAR(500) NULL,
    recipient_type          NVARCHAR(50)  NULL,
    allocation_scope        NVARCHAR(30)  NULL,
    donation_type_in_source NVARCHAR(30)  NULL,
    item_name               NVARCHAR(300) NULL,
    amount_original         DECIMAL(18,2) NULL,
    currency                CHAR(3)       NULL,
    amount_usd              DECIMAL(18,2) NULL,
    reason_excluded         NVARCHAR(500) NOT NULL,
    source_excerpt          NVARCHAR(1000) NULL,
    dwh_load_date           DATETIME2     NOT NULL CONSTRAINT DF_excluded_load DEFAULT SYSDATETIME()
);
GO

-- ---------------------------------------------------------
-- 5. Tweets (one row per tweet that holds a donation)
-- ---------------------------------------------------------
IF OBJECT_ID('silver.tweet', 'U') IS NOT NULL
    DROP TABLE silver.tweet;
GO

CREATE TABLE silver.tweet (
    tweet_id            BIGINT         NOT NULL CONSTRAINT PK_silver_tweet PRIMARY KEY,
    tweet_url           NVARCHAR(200)  NOT NULL,
    tweet_date          DATE           NULL,
    tweet_created_at    DATETIME2      NULL,     -- only when raw tweets were loaded
    author_username     NVARCHAR(100)  NULL,
    tweet_text          NVARCHAR(MAX)  NULL,
    has_tweet_text      BIT            NOT NULL,
    donation_line_count INT            NOT NULL,
    excluded_line_count INT            NOT NULL,
    dwh_load_date       DATETIME2      NOT NULL CONSTRAINT DF_tweet_load DEFAULT SYSDATETIME()
);
GO

-- ---------------------------------------------------------
-- 9. Data quality issues (flags, overlaps, LLM corrections)
-- ---------------------------------------------------------
IF OBJECT_ID('silver.data_quality_issues', 'U') IS NOT NULL
    DROP TABLE silver.data_quality_issues;
GO

CREATE TABLE silver.data_quality_issues (
    issue_id           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_silver_dqi PRIMARY KEY,
    source_table       NVARCHAR(60)  NOT NULL,
    source_donation_id INT           NULL,
    issue_type         NVARCHAR(50)  NOT NULL,
    severity           NVARCHAR(10)  NOT NULL,   -- Info / Warning
    description        NVARCHAR(2000) NULL,
    detected_at        DATETIME2     NOT NULL CONSTRAINT DF_dqi_detected DEFAULT SYSDATETIME()
);
GO
