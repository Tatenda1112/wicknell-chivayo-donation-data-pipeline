/*
=============================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
=============================================================
Method  : Full load (TRUNCATE then INSERT).
Does    : Data cleaning, standardisation, normalisation,
          derived columns and enrichment.

  Cleaning         trim text, remove line breaks, empty text -> NULL,
                   safe type conversion (TRY_CAST)
  Standardisation  one spelling per recipient (name map below),
                   status values -> status_group
  Normalisation    one recipient table, one tweet table, one
                   exchange-rate table; donation tables share the
                   same standard columns
  Derived columns  donation_year, donation_month, is_pledge,
                   is_delivered, days_tweet_to_donation,
                   counts_toward_total
  Enrichment       recipient_group, ZAR -> USD, tweet attributes

Only four things are kept OUT of the totals (counts_toward_total = 0).
Every one of them stays in the table with a reason that starts with:
  Declined:        the commitment was declined or rejected
  Duplicate:       the tweet text shows it is the same gift as another row
  Not a donation:  loans, expenses, fees for services, personal purchases
  Family:          personal gifts to his wife or ex-wife (not philanthropy)
Rows listed in #remove_rule are taken out of the donation tables
altogether and written to silver.excluded with the reason.
Anything uncertain stays IN the totals and is logged as an OVERLAP_REVIEW
warning in silver.data_quality_issues.

Edit the rule lists in section 0 if a decision changes:
  #name_map        spelling variants of the same recipient
  #group_rule      keyword rules for recipient_group
  #not_counted     confirmed duplicates and family gifts
  #review_pending  possible overlaps, counted until confirmed
  #remove_rule     rows removed from the donation data (declined offers)
  #count_override  rows counted even though a general rule would exclude them

Usage   : EXEC silver.load_silver;
=============================================================
*/

USE DonationsDW;
GO

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @batch_start DATETIME2 = SYSDATETIME();
    DECLARE @rows INT, @expected INT, @msg NVARCHAR(500), @dq_issue_count INT;

    BEGIN TRY
        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';

        -- Guard: Silver is built from Bronze. If Bronze is empty, stop with a clear message
        -- instead of silently loading zero rows.
        SELECT @expected = (SELECT COUNT(*) FROM bronze.reviewed_money)
                         + (SELECT COUNT(*) FROM bronze.reviewed_vehicle)
                         + (SELECT COUNT(*) FROM bronze.reviewed_house)
                         + (SELECT COUNT(*) FROM bronze.reviewed_other_giving);
        IF @expected = 0
            THROW 50001, N'Bronze tables are empty. Run EXEC bronze.load_bronze first and check bronze.load_log.', 1;

        -- =====================================================
        -- 0. Rule lists (temporary tables)
        -- =====================================================
        IF OBJECT_ID('tempdb..#name_map') IS NOT NULL DROP TABLE #name_map;
        CREATE TABLE #name_map (raw_name NVARCHAR(300) NOT NULL PRIMARY KEY, clean_name NVARCHAR(300) NOT NULL);
        INSERT INTO #name_map (raw_name, clean_name) VALUES
            (N'Benjamin Mwaruwari', N'Benjani Mwaruwari'),
            (N'Benjani Mwaruwaru', N'Benjani Mwaruwari'),
            (N'C. H. MUKUNGUNUGWA', N'C. H. Mukungunugwa'),
            (N'CDE C.H. MUKUNGUNUGWA', N'C. H. Mukungunugwa'),
            (N'Highlanders', N'Highlanders FC'),
            (N'Scotland Football Club', N'Scotland FC'),
            (N'ZCC', N'Zion Christian Church (ZCC)'),
            (N'ZCC (Zion Christian Church)', N'Zion Christian Church (ZCC)'),
            (N'Zion Christian Church', N'Zion Christian Church (ZCC)'),
            (N'Advocate Lewis Uriri', N'Advocate Lewis Uriri SC'),
            (N'Advocate Sylvester Munya Hashiti', N'Sylvester Hashiti'),
            (N'Senior Prophet Eubert Angel', N'Prophet Uebert Angel'),
            (N'Mukudzei ''JAH PRAYZAH'' Mukombe', N'Jah Prayzah'),
            (N'Thomas ''MUKANYA'' Mapfumo', N'Thomas Mapfumo'),
            (N'Thomas Tafirenyika Mapfumo', N'Thomas Mapfumo'),
            (N'Wilson Manase', N'Wilson Tatenda Manase'),
            (N'Hon Murenyanyi', N'Hon S Mureyanyi'),
            (N'Tazvi Mhaka', N'Joseph Tazviona Mhaka'),
            (N'Madzimai Violet (Amai Katsiru)', N'Madzimai Violet Katsiru'),
            (N'CDE TINO CHIBAGE', N'Tinotenda Nyamandu Chibage'),
            (N'ED UNZA Scholarship', N'ED-UNZA Scholarship Program'),
            (N'JOHANNE MASOWE CHISHANU', N'Johane Masowe Chishanu Church'),
            (N'Zimbabwe National Football Team (Warriors)', N'Zimbabwe Warriors Football Team'),
            (N'Zimbabwe National Team Warriors', N'Zimbabwe Warriors Football Team');

        IF OBJECT_ID('tempdb..#group_rule') IS NOT NULL DROP TABLE #group_rule;
        CREATE TABLE #group_rule (prio INT NOT NULL, grp NVARCHAR(50) NOT NULL, pattern NVARCHAR(100) NOT NULL);
        INSERT INTO #group_rule (prio, grp, pattern) VALUES
            (1, N'Family and staff', N'%Chivayo%'),
            (1, N'Family and staff', N'Ex-wife%'),
            (1, N'Family and staff', N'%(Mother)%'),
            (1, N'Family and staff', N'%(Son)%'),
            (1, N'Family and staff', N'Mukomana%'),
            (1, N'Family and staff', N'Personal trainer%'),
            (1, N'Family and staff', N'Ishmael Assistant'),
            (1, N'Family and staff', N'Ishmael Tailor'),
            (1, N'Family and staff', N'Cameraman'),
            (1, N'Family and staff', N'Event Planner%'),
            (1, N'Family and staff', N'Venue Decor%'),
            (1, N'Family and staff', N'Young lady employee'),
            (1, N'Family and staff', N'Bridal Team'),
            (1, N'Family and staff', N'Him'),
            (1, N'Family and staff', N'Gift'),
            (1, N'Family and staff', N'Sweet little baby'),
            (2, N'Security and government', N'CID%'),
            (2, N'Security and government', N'%Police%'),
            (2, N'Security and government', N'ZRP%'),
            (2, N'Security and government', N'ZDF%'),
            (2, N'Security and government', N'ZPCS%'),
            (2, N'Security and government', N'Ministry of%'),
            (2, N'Security and government', N'%Government%'),
            (2, N'Security and government', N'%Hospital%'),
            (2, N'Security and government', N'%Parliamentarians%'),
            (2, N'Security and government', N'Hon %'),
            (2, N'Security and government', N'Hon. %'),
            (2, N'Security and government', N'%Eswatini%'),
            (2, N'Security and government', N'RTD COL%'),
            (3, N'Religious', N'%church%'),
            (3, N'Religious', N'%Zion%'),
            (3, N'Religious', N'%ZCC%'),
            (3, N'Religious', N'%Masowe%'),
            (3, N'Religious', N'%Madzibaba%'),
            (3, N'Religious', N'%Madzimai%'),
            (3, N'Religious', N'%Prophet%'),
            (3, N'Religious', N'%Bishop%'),
            (3, N'Religious', N'%Pastor%'),
            (3, N'Religious', N'%Apostle%'),
            (3, N'Religious', N'%Evangelist%'),
            (3, N'Religious', N'Rev.%'),
            (3, N'Religious', N'%Ministries%'),
            (3, N'Religious', N'%Cathedral%'),
            (3, N'Religious', N'%Mutendi%'),
            (3, N'Religious', N'%Mudare%'),
            (3, N'Religious', N'%Mutumwa%'),
            (3, N'Religious', N'%Makandiwa%'),
            (3, N'Religious', N'%Magaya%'),
            (3, N'Religious', N'%Ushers%'),
            (3, N'Religious', N'%(UFIC)%'),
            (3, N'Religious', N'%chemadzimai%'),
            (3, N'Religious', N'%Amai ava%'),
            (4, N'Sports', N'% FC'),
            (4, N'Sports', N'% FC %'),
            (4, N'Sports', N'%Football%'),
            (4, N'Sports', N'%Warriors%'),
            (4, N'Sports', N'%Highlanders%'),
            (4, N'Sports', N'%Dynamos%'),
            (4, N'Sports', N'%Scotland%'),
            (4, N'Sports', N'%ZIFA%'),
            (4, N'Sports', N'%Cricket%'),
            (4, N'Sports', N'%Chevrons%'),
            (4, N'Sports', N'Coach %'),
            (4, N'Sports', N'%Mwaruwari%'),
            (4, N'Sports', N'%Mnkandla%'),
            (4, N'Sports', N'Madinda Ndlovu'),
            (4, N'Sports', N'Peter Ndlovu'),
            (4, N'Sports', N'%Manyuchi%'),
            (4, N'Sports', N'%Chidzambwa%'),
            (4, N'Sports', N'%Bambo%'),
            (4, N'Sports', N'%Mabika%'),
            (5, N'Charity and community', N'%Foundation%'),
            (5, N'Charity and community', N'%Trust%'),
            (5, N'Charity and community', N'%charity%'),
            (5, N'Charity and community', N'%orphans%'),
            (5, N'Charity and community', N'%Community%'),
            (5, N'Charity and community', N'%districts%'),
            (5, N'Charity and community', N'Families of%'),
            (5, N'Charity and community', N'Deserving youths%'),
            (5, N'Charity and community', N'%ghetto youths%'),
            (5, N'Charity and community', N'Children'),
            (6, N'Education', N'%School%'),
            (6, N'Education', N'%UNZA%'),
            (6, N'Education', N'%Scholarship%'),
            (7, N'Arts, music and media', N'%Prayzah%'),
            (7, N'Arts, music and media', N'%Winky%'),
            (7, N'Arts, music and media', N'%Tocky%'),
            (7, N'Arts, music and media', N'Killer T'),
            (7, N'Arts, music and media', N'%Mapfumo%'),
            (7, N'Arts, music and media', N'%Zhakata%'),
            (7, N'Arts, music and media', N'%Mathias Mhere%'),
            (7, N'Arts, music and media', N'DJ %'),
            (7, N'Arts, music and media', N'Band %'),
            (7, N'Arts, music and media', N'% Band'),
            (7, N'Arts, music and media', N'% Band %'),
            (7, N'Arts, music and media', N'%Orchestra%'),
            (7, N'Arts, music and media', N'%Mosquito%'),
            (7, N'Arts, music and media', N'%Sugar Sugar%'),
            (7, N'Arts, music and media', N'%Shinsoman%'),
            (7, N'Arts, music and media', N'%Ras Caleb%'),
            (7, N'Arts, music and media', N'%Jah Master%'),
            (7, N'Arts, music and media', N'%Mudiwa Hood%'),
            (7, N'Arts, music and media', N'%Manyeruke%'),
            (7, N'Arts, music and media', N'%Spragga%'),
            (7, N'Arts, music and media', N'%Dancers%'),
            (7, N'Arts, music and media', N'%Comic%'),
            (7, N'Arts, music and media', N'%Cde Garwe%'),
            (7, N'Arts, music and media', N'%Chisamba%'),
            (7, N'Arts, music and media', N'%Radio%'),
            (7, N'Arts, music and media', N'%CAPITALK%');

        IF OBJECT_ID('tempdb..#not_counted') IS NOT NULL DROP TABLE #not_counted;
        CREATE TABLE #not_counted (source_donation_id INT NOT NULL PRIMARY KEY, reason NVARCHAR(500) NOT NULL);
        INSERT INTO #not_counted (source_donation_id, reason) VALUES
            (278, N'Duplicate: announcement of the USD 1M Highlanders package, which is counted through its instalments #277, #223 and #170'),
            (203, N'Duplicate: re-mention of the same USD 1M Highlanders package'),
            (19, N'Duplicate: second tweet of the same Junior Parliamentarians offer in #18'),
            (601, N'Duplicate: delivery update for the two cars already listed in #38 and #39'),
            (107, N'Duplicate: promise of the Cullinan that is delivered in #748 (the USD 1.2M value is carried to #748)'),
            (342, N'Duplicate: re-mention of the Range Rover already counted in #363'),
            (343, N'Duplicate: re-mention of the Land Cruiser already counted in #364'),
            (111, N'Duplicate: same 2026 Rolls-Royce Ghost for Prophet Angel''s wife as #708'),
            (154, N'Duplicate: the 10 ambulances are part of the 20 already pledged in #239'),
            (157, N'Duplicate: the USD 2M pledge is the figure that #106 later raises to USD 5M, so it is already inside the 5M'),
            (428, N'Duplicate: the same "small donation" to ZCC as #429 (USD 1M, one day earlier); no separate amount'),
            (188, N'Duplicate: same USD 250k Warriors pledge as #179, which shows it was withheld in trust and never delivered'),
            -- Personal gifts to his wife and ex-wife: kept for audit, not counted as philanthropy
            (383, N'Family: personal support paid to his ex-wife (Sonja), not philanthropy'),
            (382, N'Family: personal support paid to his ex-wife and children, not philanthropy'),
            (136, N'Family: personal gift to his wife Lulu, not philanthropy'),
            (135, N'Family: personal gift (Bentley Bentayga) to his wife Lulu, not philanthropy'),
            (128, N'Family: court-ordered child support paid for his own children, not philanthropy'),
            -- Thomas Mapfumo: the two 4 July 2026 offers were replaced by the final commitment in #46
            (53, N'Duplicate: earlier USD 500,000 wedding-performance offer to Thomas Mapfumo, superseded by the final USD 1M two-show commitment in #46'),
            (54, N'Duplicate: earlier USD 1M birthday-performance offer to Thomas Mapfumo, superseded by the final USD 1M two-show commitment in #46');

        -- Rows counted even though a general rule (for example money_nature = performance_fee)
        -- would leave them out of the totals. Money rows only.
        IF OBJECT_ID('tempdb..#count_override') IS NOT NULL DROP TABLE #count_override;
        CREATE TABLE #count_override (source_donation_id INT NOT NULL PRIMARY KEY, reason NVARCHAR(500) NOT NULL);
        INSERT INTO #count_override (source_donation_id, reason) VALUES
            (46, N'Counted by decision: final USD 1M commitment to Thomas Mapfumo (two shows at USD 500,000 each)');

        -- Rows removed from the donation data altogether. They are deleted from the
        -- donation tables after loading and written to silver.excluded with the reason.
        IF OBJECT_ID('tempdb..#remove_rule') IS NOT NULL DROP TABLE #remove_rule;
        CREATE TABLE #remove_rule (source_donation_id INT NOT NULL PRIMARY KEY, reason NVARCHAR(500) NOT NULL);
        INSERT INTO #remove_rule (source_donation_id, reason) VALUES
            (730, N'Declined offer: Land Rover Discovery 4 linked to the gifts Advocate Uriri publicly declined (see #727)'),
            (731, N'Declined offer: 2026 Range Rover Sport offered to Advocate Uriri was publicly declined (see #727)'),
            (732, N'Declined offer: USD 50,000 offered to Advocate Uriri, publicly declined (see #727)'),
            (733, N'Declined offer: USD 50,000 offered to Mrs Uriri, part of the declined Uriri gifts (see #727)');

        -- Possible overlaps that the tweets do NOT prove. They stay in the totals and
        -- are written to silver.data_quality_issues as OVERLAP_REVIEW warnings.
        -- To exclude one after checking it, move it to #not_counted with the reason 'Duplicate: ...'.
        IF OBJECT_ID('tempdb..#review_pending') IS NOT NULL DROP TABLE #review_pending;
        CREATE TABLE #review_pending (source_table SYSNAME NOT NULL, source_donation_id INT NOT NULL PRIMARY KEY, description NVARCHAR(500) NOT NULL);
        INSERT INTO #review_pending (source_table, source_donation_id, description) VALUES
            (N'donation_vehicle', 257, N'Promise of 10 more buses by Dec 2025 may be fulfilled by the 10 buses in #33 (Aug 2026); confirm'),
            (N'donation_vehicle', 258, N'Promise of 10 more buses by Apr 2026 may be fulfilled by the 10 buses in #33 (Aug 2026); confirm'),
            (N'donation_vehicle', 242, N'10 ICU ambulances (Sep 2025) may be the 10 delivered in Nov 2025 that belong to the 20 pledged in #239; confirm whether the total is 20 or 30');

        -- =====================================================
        -- 7. silver.exchange_rate
        -- =====================================================
        PRINT '>> Loading silver.exchange_rate';
        TRUNCATE TABLE silver.exchange_rate;
        INSERT INTO silver.exchange_rate (currency_code, rate_to_usd, rate_source)
        VALUES ('USD', 1.0, N'Base currency'),
               ('ZAR', 0.05538462, N'Derived from tweet 387: R2.6 million = USD 144,000 (about 18.06 ZAR per USD). Replace with a dated rate if you prefer.');

        -- =====================================================
        -- 6. silver.recipient
        -- =====================================================
        PRINT '>> Loading silver.recipient';
        TRUNCATE TABLE silver.recipient;

        -- all recipient names used by the four donation tables
        IF OBJECT_ID('tempdb..#name_raw') IS NOT NULL DROP TABLE #name_raw;
        SELECT silver.fn_clean_text(recipient_name) AS name_original,
               silver.fn_clean_text(recipient_type) AS recipient_type
        INTO #name_raw
        FROM (
            SELECT recipient_name, recipient_type FROM bronze.reviewed_money
            UNION ALL SELECT recipient_name, recipient_type FROM bronze.reviewed_vehicle
            UNION ALL SELECT recipient_name, recipient_type FROM bronze.reviewed_house
            UNION ALL SELECT recipient_name, recipient_type FROM bronze.reviewed_other_giving
        ) u
        WHERE silver.fn_clean_text(recipient_name) IS NOT NULL;

        -- original spelling -> standard spelling
        IF OBJECT_ID('tempdb..#name_std') IS NOT NULL DROP TABLE #name_std;
        SELECT n.name_original,
               n.recipient_type,
               COALESCE(m.clean_name, n.name_original) AS name_std
        INTO #name_std
        FROM #name_raw n
        LEFT JOIN #name_map m ON m.raw_name = n.name_original;

        ;WITH type_rank AS (
            SELECT name_std, recipient_type, COUNT(*) AS n,
                   ROW_NUMBER() OVER (PARTITION BY name_std ORDER BY COUNT(*) DESC, recipient_type) AS rn
            FROM #name_std
            GROUP BY name_std, recipient_type
        ),
        names AS (
            SELECT t.name_std,
                   t.recipient_type,
                   (SELECT COUNT(DISTINCT s.name_original) FROM #name_std s WHERE s.name_std = t.name_std) AS variants
            FROM type_rank t
            WHERE t.rn = 1
        )
        INSERT INTO silver.recipient (recipient_name, recipient_type, recipient_group, name_variants_count)
        SELECT n.name_std,
               n.recipient_type,
               CASE
                   WHEN n.recipient_type = 'Church'                 THEN 'Religious'
                   WHEN n.recipient_type = 'School'                 THEN 'Education'
                   WHEN n.recipient_type = 'Government Institution' THEN 'Security and government'
                   WHEN n.recipient_type IN ('Trust', 'Community')  THEN 'Charity and community'
                   ELSE COALESCE(g.grp,
                        CASE n.recipient_type WHEN 'Person'       THEN 'Individual'
                                              WHEN 'Group'        THEN 'Group (other)'
                                              WHEN 'Organization' THEN 'Organisation (other)'
                                              ELSE 'Other' END)
               END,
               n.variants
        FROM names n
        OUTER APPLY (SELECT TOP 1 r.grp FROM #group_rule r WHERE n.name_std LIKE r.pattern ORDER BY r.prio) g
        ORDER BY n.name_std;
        PRINT '>> Rows loaded: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));

        -- lookup: original spelling -> recipient_id (used by the donation tables)
        IF OBJECT_ID('tempdb..#recipient_lookup') IS NOT NULL DROP TABLE #recipient_lookup;
        SELECT DISTINCT n.name_original, r.recipient_id
        INTO #recipient_lookup
        FROM #name_std n
        JOIN silver.recipient r ON r.recipient_name = n.name_std;

        -- =====================================================
        -- 1 to 4. Donation tables
        -- =====================================================

        -- ---------------------------------------------------------
        -- silver.donation_money  (from bronze.reviewed_money)
        -- ---------------------------------------------------------
        PRINT '>> Loading silver.donation_money';
        TRUNCATE TABLE silver.donation_money;

        INSERT INTO silver.donation_money ([money_id], [source_donation_id], [tweet_id], [tweet_date], [donation_date], [donation_year], [donation_month], [days_tweet_to_donation], [donor_name], [recipient_id], [recipient_name], [recipient_name_original], [recipient_type], [recipient_group], [allocation_scope], [recipient_count], [amount_per_recipient], [currency], [total_amount], [total_amount_usd], [usd_is_converted], [money_nature], [calc_check], [commitment_status], [status_group], [is_pledge], [is_delivered], [purpose], [country], [location], [source_excerpt], [origin], [review_flag], [review_note], [overlap_group], [counts_toward_total], [not_counted_reason])
        SELECT
        LEFT(silver.fn_clean_text(b.money_id), 10) AS [money_id],
        c.sid AS [source_donation_id],
        COALESCE(TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(b.tweet_id)), N'')), TRY_CONVERT(BIGINT, RIGHT(RTRIM(b.tweet_url), NULLIF(CHARINDEX('/', REVERSE(RTRIM(b.tweet_url))) - 1, -1)))) AS [tweet_id],
        c.d_tw AS [tweet_date],
        c.d_don AS [donation_date],
        CAST(YEAR(c.d_don) AS SMALLINT) AS [donation_year],
        CAST(MONTH(c.d_don) AS TINYINT) AS [donation_month],
        DATEDIFF(DAY, c.d_tw, c.d_don) AS [days_tweet_to_donation],
        LEFT(silver.fn_clean_text(b.donor_name), 100) AS [donor_name],
        l.recipient_id AS [recipient_id],
        r.recipient_name AS [recipient_name],
        l.name_original AS [recipient_name_original],
        LEFT(silver.fn_clean_text(b.recipient_type), 50) AS [recipient_type],
        r.recipient_group AS [recipient_group],
        LEFT(silver.fn_clean_text(b.allocation_scope), 30) AS [allocation_scope],
        TRY_CAST(TRY_CAST(b.recipient_count AS DECIMAL(18,2)) AS INT) AS [recipient_count],
        TRY_CAST(b.amount_per_recipient AS DECIMAL(18,2)) AS [amount_per_recipient],
        UPPER(LEFT(silver.fn_clean_text(b.currency), 3)) AS [currency],
        TRY_CAST(b.total_amount AS DECIMAL(18,2)) AS [total_amount],
        COALESCE(TRY_CAST(b.total_amount_usd AS DECIMAL(18,2)), CAST(TRY_CAST(b.total_amount AS DECIMAL(18,2)) * fx.rate_to_usd AS DECIMAL(18,2))) AS [total_amount_usd],
        CASE WHEN TRY_CAST(b.total_amount_usd AS DECIMAL(18,2)) IS NULL AND TRY_CAST(b.total_amount AS DECIMAL(18,2)) IS NOT NULL AND fx.rate_to_usd IS NOT NULL THEN 1 ELSE 0 END AS [usd_is_converted],
        LEFT(silver.fn_clean_text(b.money_nature), 50) AS [money_nature],
        LEFT(silver.fn_clean_text(b.calc_check), 30) AS [calc_check],
        c.st AS [commitment_status],
        CASE WHEN c.st = 'Promised' THEN 'Promised' WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 'Delivered' ELSE 'Unknown' END AS [status_group],
        CASE WHEN c.st = 'Promised' THEN 1 ELSE 0 END AS [is_pledge],
        CASE WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 1 ELSE 0 END AS [is_delivered],
        LEFT(silver.fn_clean_text(b.purpose), 500) AS [purpose],
        LEFT(silver.fn_clean_text(b.country), 100) AS [country],
        LEFT(silver.fn_clean_text(b.location), 500) AS [location],
        LEFT(silver.fn_clean_text(b.source_excerpt), 1000) AS [source_excerpt],
        LEFT(silver.fn_clean_text(b.origin), 50) AS [origin],
        LEFT(silver.fn_clean_text(b.review_flag), 100) AS [review_flag],
        LEFT(silver.fn_clean_text(b.review_note), 2000) AS [review_note],
        LEFT(silver.fn_clean_text(b.overlap_group), 100) AS [overlap_group],
        CASE WHEN co.source_donation_id IS NOT NULL THEN 1          -- counted by decision (#count_override)
             WHEN nc.source_donation_id IS NOT NULL
                   OR (LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%')
                   OR (LEFT(silver.fn_clean_text(b.money_nature), 50) = 'loan')
                   OR (LEFT(silver.fn_clean_text(b.money_nature), 50) = 'vehicle_related_expense')
                   OR (LEFT(silver.fn_clean_text(b.money_nature), 50) = 'performance_fee') THEN 0 ELSE 1 END AS [counts_toward_total],
        CASE WHEN co.source_donation_id IS NOT NULL THEN NULL ELSE
        LEFT(COALESCE(nc.reason,
                 CASE WHEN LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%' THEN N'Declined: commitment declined or rejected'
                     WHEN LEFT(silver.fn_clean_text(b.money_nature), 50) = 'loan' THEN N'Not a donation: interest-free loan'
                     WHEN LEFT(silver.fn_clean_text(b.money_nature), 50) = 'vehicle_related_expense' THEN N'Not a donation: number-plate expense'
                     WHEN LEFT(silver.fn_clean_text(b.money_nature), 50) = 'performance_fee' THEN N'Not a donation: fee paid for a performance (a service)' END), 300) END AS [not_counted_reason]
        FROM bronze.reviewed_money b
        CROSS APPLY (SELECT TRY_CAST(b.source_donation_id AS INT) AS sid,
                            TRY_CAST(b.tweet_date AS DATE) AS d_tw,
                            TRY_CAST(b.donation_date AS DATE) AS d_don,
                            silver.fn_clean_text(b.commitment_status) AS st) c
        JOIN #recipient_lookup l ON l.name_original = silver.fn_clean_text(b.recipient_name)
        JOIN silver.recipient r ON r.recipient_id = l.recipient_id
        LEFT JOIN #not_counted nc ON nc.source_donation_id = c.sid
        LEFT JOIN #count_override co ON co.source_donation_id = c.sid
    LEFT JOIN silver.exchange_rate fx ON fx.currency_code = UPPER(LEFT(silver.fn_clean_text(b.currency), 3));
        SET @rows = @@ROWCOUNT;
        SELECT @expected = COUNT(*) FROM bronze.reviewed_money;
        PRINT '>> Rows loaded: ' + CAST(@rows AS NVARCHAR(20)) + ' of ' + CAST(@expected AS NVARCHAR(20)) + ' in bronze';
        IF @rows <> @expected
        BEGIN
            SET @msg = CONCAT(N'silver.donation_money loaded ', @rows, N' of ', @expected, N' rows. Check recipient names and data types.');
            THROW 50002, @msg, 1;
        END;

        -- ---------------------------------------------------------
        -- silver.donation_vehicle  (from bronze.reviewed_vehicle)
        -- ---------------------------------------------------------
        PRINT '>> Loading silver.donation_vehicle';
        TRUNCATE TABLE silver.donation_vehicle;

        INSERT INTO silver.donation_vehicle ([vehicle_id], [source_donation_id], [tweet_id], [tweet_date], [donation_date], [donation_year], [donation_month], [days_tweet_to_donation], [donor_name], [recipient_id], [recipient_name], [recipient_name_original], [recipient_type], [recipient_group], [allocation_scope], [vehicle_class], [item_name], [quantity], [unit_value_usd], [total_value_usd], [bundle_key], [bundle_value_usd], [calc_check], [commitment_status], [status_group], [is_pledge], [is_delivered], [purpose], [country], [location], [source_excerpt], [origin], [review_flag], [review_note], [overlap_group], [counts_toward_total], [not_counted_reason])
        SELECT
        LEFT(silver.fn_clean_text(b.vehicle_id), 10) AS [vehicle_id],
        c.sid AS [source_donation_id],
        COALESCE(TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(b.tweet_id)), N'')), TRY_CONVERT(BIGINT, RIGHT(RTRIM(b.tweet_url), NULLIF(CHARINDEX('/', REVERSE(RTRIM(b.tweet_url))) - 1, -1)))) AS [tweet_id],
        c.d_tw AS [tweet_date],
        c.d_don AS [donation_date],
        CAST(YEAR(c.d_don) AS SMALLINT) AS [donation_year],
        CAST(MONTH(c.d_don) AS TINYINT) AS [donation_month],
        DATEDIFF(DAY, c.d_tw, c.d_don) AS [days_tweet_to_donation],
        LEFT(silver.fn_clean_text(b.donor_name), 100) AS [donor_name],
        l.recipient_id AS [recipient_id],
        r.recipient_name AS [recipient_name],
        l.name_original AS [recipient_name_original],
        LEFT(silver.fn_clean_text(b.recipient_type), 50) AS [recipient_type],
        r.recipient_group AS [recipient_group],
        LEFT(silver.fn_clean_text(b.allocation_scope), 30) AS [allocation_scope],
        LEFT(silver.fn_clean_text(b.vehicle_class), 30) AS [vehicle_class],
        LEFT(silver.fn_clean_text(b.item_name), 200) AS [item_name],
        TRY_CAST(TRY_CAST(b.quantity AS DECIMAL(18,2)) AS INT) AS [quantity],
        CASE WHEN c.sid = 748 AND TRY_CAST(b.unit_value_usd AS DECIMAL(18,2)) IS NULL THEN CAST(1200000.00 AS DECIMAL(18,2)) ELSE TRY_CAST(b.unit_value_usd AS DECIMAL(18,2)) END AS [unit_value_usd],
        CASE WHEN c.sid = 748 AND TRY_CAST(b.total_value_usd AS DECIMAL(18,2)) IS NULL THEN CAST(1200000.00 AS DECIMAL(18,2)) ELSE TRY_CAST(b.total_value_usd AS DECIMAL(18,2)) END AS [total_value_usd],
        LEFT(silver.fn_clean_text(b.bundle_key), 100) AS [bundle_key],
        TRY_CAST(b.bundle_value_usd_DO_NOT_SUM AS DECIMAL(18,2)) AS [bundle_value_usd],
        LEFT(silver.fn_clean_text(b.calc_check), 30) AS [calc_check],
        c.st AS [commitment_status],
        CASE WHEN c.st = 'Promised' THEN 'Promised' WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 'Delivered' ELSE 'Unknown' END AS [status_group],
        CASE WHEN c.st = 'Promised' THEN 1 ELSE 0 END AS [is_pledge],
        CASE WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 1 ELSE 0 END AS [is_delivered],
        LEFT(silver.fn_clean_text(b.purpose), 500) AS [purpose],
        LEFT(silver.fn_clean_text(b.country), 100) AS [country],
        LEFT(silver.fn_clean_text(b.location), 500) AS [location],
        LEFT(silver.fn_clean_text(b.source_excerpt), 1000) AS [source_excerpt],
        LEFT(silver.fn_clean_text(b.origin), 50) AS [origin],
        LEFT(silver.fn_clean_text(b.review_flag), 100) AS [review_flag],
        LEFT(silver.fn_clean_text(b.review_note), 2000) AS [review_note],
        LEFT(silver.fn_clean_text(b.overlap_group), 100) AS [overlap_group],
        CASE WHEN nc.source_donation_id IS NOT NULL
                   OR (LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%') THEN 0 ELSE 1 END AS [counts_toward_total],
        LEFT(COALESCE(nc.reason,
                 CASE WHEN LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%' THEN N'Declined: commitment declined or rejected' END), 300) AS [not_counted_reason]
        FROM bronze.reviewed_vehicle b
        CROSS APPLY (SELECT TRY_CAST(b.source_donation_id AS INT) AS sid,
                            TRY_CAST(b.tweet_date AS DATE) AS d_tw,
                            TRY_CAST(b.donation_date AS DATE) AS d_don,
                            silver.fn_clean_text(b.commitment_status) AS st) c
        JOIN #recipient_lookup l ON l.name_original = silver.fn_clean_text(b.recipient_name)
        JOIN silver.recipient r ON r.recipient_id = l.recipient_id
        LEFT JOIN #not_counted nc ON nc.source_donation_id = c.sid;
        SET @rows = @@ROWCOUNT;
        SELECT @expected = COUNT(*) FROM bronze.reviewed_vehicle;
        PRINT '>> Rows loaded: ' + CAST(@rows AS NVARCHAR(20)) + ' of ' + CAST(@expected AS NVARCHAR(20)) + ' in bronze';
        IF @rows <> @expected
        BEGIN
            SET @msg = CONCAT(N'silver.donation_vehicle loaded ', @rows, N' of ', @expected, N' rows. Check recipient names and data types.');
            THROW 50002, @msg, 1;
        END;

        -- ---------------------------------------------------------
        -- silver.donation_house  (from bronze.reviewed_house)
        -- ---------------------------------------------------------
        PRINT '>> Loading silver.donation_house';
        TRUNCATE TABLE silver.donation_house;

        INSERT INTO silver.donation_house ([house_id], [source_donation_id], [tweet_id], [tweet_date], [donation_date], [donation_year], [donation_month], [days_tweet_to_donation], [donor_name], [recipient_id], [recipient_name], [recipient_name_original], [recipient_type], [recipient_group], [allocation_scope], [house_count], [unit_value], [currency], [total_value], [total_value_usd], [usd_is_converted], [furnished], [house_nature], [calc_check], [commitment_status], [status_group], [is_pledge], [is_delivered], [purpose], [country], [location], [source_excerpt], [origin], [review_flag], [review_note], [overlap_group], [counts_toward_total], [not_counted_reason])
        SELECT
        LEFT(silver.fn_clean_text(b.house_id), 10) AS [house_id],
        c.sid AS [source_donation_id],
        COALESCE(TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(b.tweet_id)), N'')), TRY_CONVERT(BIGINT, RIGHT(RTRIM(b.tweet_url), NULLIF(CHARINDEX('/', REVERSE(RTRIM(b.tweet_url))) - 1, -1)))) AS [tweet_id],
        c.d_tw AS [tweet_date],
        c.d_don AS [donation_date],
        CAST(YEAR(c.d_don) AS SMALLINT) AS [donation_year],
        CAST(MONTH(c.d_don) AS TINYINT) AS [donation_month],
        DATEDIFF(DAY, c.d_tw, c.d_don) AS [days_tweet_to_donation],
        LEFT(silver.fn_clean_text(b.donor_name), 100) AS [donor_name],
        l.recipient_id AS [recipient_id],
        r.recipient_name AS [recipient_name],
        l.name_original AS [recipient_name_original],
        LEFT(silver.fn_clean_text(b.recipient_type), 50) AS [recipient_type],
        r.recipient_group AS [recipient_group],
        LEFT(silver.fn_clean_text(b.allocation_scope), 30) AS [allocation_scope],
        TRY_CAST(TRY_CAST(b.house_count AS DECIMAL(18,2)) AS INT) AS [house_count],
        TRY_CAST(b.unit_value AS DECIMAL(18,2)) AS [unit_value],
        UPPER(LEFT(silver.fn_clean_text(b.currency), 3)) AS [currency],
        TRY_CAST(b.total_value AS DECIMAL(18,2)) AS [total_value],
        COALESCE(TRY_CAST(b.total_value_usd AS DECIMAL(18,2)), CAST(TRY_CAST(b.total_value AS DECIMAL(18,2)) * fx.rate_to_usd AS DECIMAL(18,2))) AS [total_value_usd],
        CASE WHEN TRY_CAST(b.total_value_usd AS DECIMAL(18,2)) IS NULL AND TRY_CAST(b.total_value AS DECIMAL(18,2)) IS NOT NULL AND fx.rate_to_usd IS NOT NULL THEN 1 ELSE 0 END AS [usd_is_converted],
        TRY_CAST(silver.fn_clean_text(b.furnished) AS BIT) AS [furnished],
        LEFT(silver.fn_clean_text(b.house_nature), 50) AS [house_nature],
        LEFT(silver.fn_clean_text(b.calc_check), 30) AS [calc_check],
        c.st AS [commitment_status],
        CASE WHEN c.st = 'Promised' THEN 'Promised' WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 'Delivered' ELSE 'Unknown' END AS [status_group],
        CASE WHEN c.st = 'Promised' THEN 1 ELSE 0 END AS [is_pledge],
        CASE WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 1 ELSE 0 END AS [is_delivered],
        LEFT(silver.fn_clean_text(b.purpose), 500) AS [purpose],
        LEFT(silver.fn_clean_text(b.country), 100) AS [country],
        LEFT(silver.fn_clean_text(b.location), 500) AS [location],
        LEFT(silver.fn_clean_text(b.source_excerpt), 1000) AS [source_excerpt],
        LEFT(silver.fn_clean_text(b.origin), 50) AS [origin],
        LEFT(silver.fn_clean_text(b.review_flag), 100) AS [review_flag],
        LEFT(silver.fn_clean_text(b.review_note), 2000) AS [review_note],
        LEFT(silver.fn_clean_text(b.overlap_group), 100) AS [overlap_group],
        CASE WHEN nc.source_donation_id IS NOT NULL
                   OR (LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%')
                   OR (LEFT(silver.fn_clean_text(b.house_nature), 50) = 'personal_purchase') THEN 0 ELSE 1 END AS [counts_toward_total],
        LEFT(COALESCE(nc.reason,
                 CASE WHEN LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%' THEN N'Declined: commitment declined or rejected'
                     WHEN LEFT(silver.fn_clean_text(b.house_nature), 50) = 'personal_purchase' THEN N'Not a donation: house bought for his own use' END), 300) AS [not_counted_reason]
        FROM bronze.reviewed_house b
        CROSS APPLY (SELECT TRY_CAST(b.source_donation_id AS INT) AS sid,
                            TRY_CAST(b.tweet_date AS DATE) AS d_tw,
                            TRY_CAST(b.donation_date AS DATE) AS d_don,
                            silver.fn_clean_text(b.commitment_status) AS st) c
        JOIN #recipient_lookup l ON l.name_original = silver.fn_clean_text(b.recipient_name)
        JOIN silver.recipient r ON r.recipient_id = l.recipient_id
        LEFT JOIN #not_counted nc ON nc.source_donation_id = c.sid
    LEFT JOIN silver.exchange_rate fx ON fx.currency_code = UPPER(LEFT(silver.fn_clean_text(b.currency), 3));
        SET @rows = @@ROWCOUNT;
        SELECT @expected = COUNT(*) FROM bronze.reviewed_house;
        PRINT '>> Rows loaded: ' + CAST(@rows AS NVARCHAR(20)) + ' of ' + CAST(@expected AS NVARCHAR(20)) + ' in bronze';
        IF @rows <> @expected
        BEGIN
            SET @msg = CONCAT(N'silver.donation_house loaded ', @rows, N' of ', @expected, N' rows. Check recipient names and data types.');
            THROW 50002, @msg, 1;
        END;

        -- ---------------------------------------------------------
        -- silver.donation_other  (from bronze.reviewed_other_giving)
        -- ---------------------------------------------------------
        PRINT '>> Loading silver.donation_other';
        TRUNCATE TABLE silver.donation_other;

        INSERT INTO silver.donation_other ([other_id], [source_donation_id], [tweet_id], [tweet_date], [donation_date], [donation_year], [donation_month], [days_tweet_to_donation], [donor_name], [recipient_id], [recipient_name], [recipient_name_original], [recipient_type], [recipient_group], [allocation_scope], [category], [item_name], [quantity], [quantity_unit], [unit_value_usd], [total_value_usd], [commitment_status], [status_group], [is_pledge], [is_delivered], [purpose], [country], [location], [source_excerpt], [origin], [review_flag], [review_note], [overlap_group], [counts_toward_total], [not_counted_reason])
        SELECT
        LEFT(silver.fn_clean_text(b.other_id), 10) AS [other_id],
        c.sid AS [source_donation_id],
        COALESCE(TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(b.tweet_id)), N'')), TRY_CONVERT(BIGINT, RIGHT(RTRIM(b.tweet_url), NULLIF(CHARINDEX('/', REVERSE(RTRIM(b.tweet_url))) - 1, -1)))) AS [tweet_id],
        c.d_tw AS [tweet_date],
        c.d_don AS [donation_date],
        CAST(YEAR(c.d_don) AS SMALLINT) AS [donation_year],
        CAST(MONTH(c.d_don) AS TINYINT) AS [donation_month],
        DATEDIFF(DAY, c.d_tw, c.d_don) AS [days_tweet_to_donation],
        LEFT(silver.fn_clean_text(b.donor_name), 100) AS [donor_name],
        l.recipient_id AS [recipient_id],
        r.recipient_name AS [recipient_name],
        l.name_original AS [recipient_name_original],
        LEFT(silver.fn_clean_text(b.recipient_type), 50) AS [recipient_type],
        r.recipient_group AS [recipient_group],
        LEFT(silver.fn_clean_text(b.allocation_scope), 30) AS [allocation_scope],
        LEFT(silver.fn_clean_text(b.category), 60) AS [category],
        LEFT(silver.fn_clean_text(b.item_name), 300) AS [item_name],
        TRY_CAST(b.quantity AS DECIMAL(18,2)) AS [quantity],
        LEFT(silver.fn_clean_text(b.quantity_unit), 30) AS [quantity_unit],
        TRY_CAST(b.unit_value_usd AS DECIMAL(18,2)) AS [unit_value_usd],
        TRY_CAST(b.total_value_usd AS DECIMAL(18,2)) AS [total_value_usd],
        c.st AS [commitment_status],
        CASE WHEN c.st = 'Promised' THEN 'Promised' WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 'Delivered' ELSE 'Unknown' END AS [status_group],
        CASE WHEN c.st = 'Promised' THEN 1 ELSE 0 END AS [is_pledge],
        CASE WHEN c.st IN ('Donated', 'Delivered', 'Previously Donated') THEN 1 ELSE 0 END AS [is_delivered],
        LEFT(silver.fn_clean_text(b.purpose), 500) AS [purpose],
        LEFT(silver.fn_clean_text(b.country), 100) AS [country],
        LEFT(silver.fn_clean_text(b.location), 500) AS [location],
        LEFT(silver.fn_clean_text(b.source_excerpt), 1000) AS [source_excerpt],
        LEFT(silver.fn_clean_text(b.origin), 50) AS [origin],
        LEFT(silver.fn_clean_text(b.review_flag), 100) AS [review_flag],
        LEFT(silver.fn_clean_text(b.review_note), 2000) AS [review_note],
        LEFT(silver.fn_clean_text(b.overlap_group), 100) AS [overlap_group],
        CASE WHEN nc.source_donation_id IS NOT NULL
                   OR (LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%') THEN 0 ELSE 1 END AS [counts_toward_total],
        LEFT(COALESCE(nc.reason,
                 CASE WHEN LOWER(COALESCE(c.st, N'')) LIKE N'%declin%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%reject%' OR LOWER(COALESCE(c.st, N'')) LIKE N'%not accepted%' THEN N'Declined: commitment declined or rejected' END), 300) AS [not_counted_reason]
        FROM bronze.reviewed_other_giving b
        CROSS APPLY (SELECT TRY_CAST(b.source_donation_id AS INT) AS sid,
                            TRY_CAST(b.tweet_date AS DATE) AS d_tw,
                            TRY_CAST(b.donation_date AS DATE) AS d_don,
                            silver.fn_clean_text(b.commitment_status) AS st) c
        JOIN #recipient_lookup l ON l.name_original = silver.fn_clean_text(b.recipient_name)
        JOIN silver.recipient r ON r.recipient_id = l.recipient_id
        LEFT JOIN #not_counted nc ON nc.source_donation_id = c.sid;
        SET @rows = @@ROWCOUNT;
        SELECT @expected = COUNT(*) FROM bronze.reviewed_other_giving;
        PRINT '>> Rows loaded: ' + CAST(@rows AS NVARCHAR(20)) + ' of ' + CAST(@expected AS NVARCHAR(20)) + ' in bronze';
        IF @rows <> @expected
        BEGIN
            SET @msg = CONCAT(N'silver.donation_other loaded ', @rows, N' of ', @expected, N' rows. Check recipient names and data types.');
            THROW 50002, @msg, 1;
        END;

        -- =====================================================
        -- 8. silver.excluded
        -- =====================================================
        PRINT '>> Loading silver.excluded';
        TRUNCATE TABLE silver.excluded;

        INSERT INTO silver.excluded (source_donation_id, tweet_id, tweet_date, donation_date, donor_name, recipient_name,
                                     recipient_type, allocation_scope, donation_type_in_source, item_name,
                                     amount_original, currency, amount_usd, reason_excluded, source_excerpt)
        SELECT TRY_CAST(b.source_donation_id AS INT),
               TRY_CAST(b.tweet_id AS BIGINT),
               TRY_CAST(b.tweet_date AS DATE),
               TRY_CAST(b.donation_date AS DATE),
               LEFT(silver.fn_clean_text(b.donor_name), 100),
               LEFT(silver.fn_clean_text(b.recipient_name), 500),
               LEFT(silver.fn_clean_text(b.recipient_type), 50),
               LEFT(silver.fn_clean_text(b.allocation_scope), 30),
               LEFT(silver.fn_clean_text(b.donation_type_in_source), 30),
               LEFT(silver.fn_clean_text(b.item_name), 300),
               TRY_CAST(b.amount_original AS DECIMAL(18,2)),
               UPPER(LEFT(silver.fn_clean_text(b.currency), 3)),
               TRY_CAST(b.amount_usd AS DECIMAL(18,2)),
               LEFT(silver.fn_clean_text(b.reason_excluded), 500),
               LEFT(silver.fn_clean_text(b.source_excerpt), 1000)
        FROM bronze.reviewed_excluded b;
        PRINT '>> Rows loaded: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));

        -- Rows in #remove_rule: copy them to silver.excluded with the reason,
        -- then delete them from the donation tables.
        INSERT INTO silver.excluded (source_donation_id, tweet_id, tweet_date, donation_date, donor_name, recipient_name,
                                     recipient_type, allocation_scope, donation_type_in_source, item_name,
                                     amount_original, currency, amount_usd, reason_excluded, source_excerpt)
        SELECT m.source_donation_id, m.tweet_id, m.tweet_date, m.donation_date, LEFT(m.donor_name, 100), LEFT(m.recipient_name, 500),
               LEFT(m.recipient_type, 50), LEFT(m.allocation_scope, 30), N'Cash', NULL,
               m.total_amount, m.currency, m.total_amount_usd, LEFT(rr.reason, 500), LEFT(m.source_excerpt, 1000)
        FROM silver.donation_money m JOIN #remove_rule rr ON rr.source_donation_id = m.source_donation_id
        UNION ALL
        SELECT v.source_donation_id, v.tweet_id, v.tweet_date, v.donation_date, LEFT(v.donor_name, 100), LEFT(v.recipient_name, 500),
               LEFT(v.recipient_type, 50), LEFT(v.allocation_scope, 30), N'Vehicle', LEFT(v.item_name, 300),
               v.total_value_usd, 'USD', v.total_value_usd, LEFT(rr.reason, 500), LEFT(v.source_excerpt, 1000)
        FROM silver.donation_vehicle v JOIN #remove_rule rr ON rr.source_donation_id = v.source_donation_id
        UNION ALL
        SELECT h.source_donation_id, h.tweet_id, h.tweet_date, h.donation_date, LEFT(h.donor_name, 100), LEFT(h.recipient_name, 500),
               LEFT(h.recipient_type, 50), LEFT(h.allocation_scope, 30), N'House', NULL,
               h.total_value, h.currency, h.total_value_usd, LEFT(rr.reason, 500), LEFT(h.source_excerpt, 1000)
        FROM silver.donation_house h JOIN #remove_rule rr ON rr.source_donation_id = h.source_donation_id
        UNION ALL
        SELECT o.source_donation_id, o.tweet_id, o.tweet_date, o.donation_date, LEFT(o.donor_name, 100), LEFT(o.recipient_name, 500),
               LEFT(o.recipient_type, 50), LEFT(o.allocation_scope, 30), N'Other', LEFT(o.item_name, 300),
               o.total_value_usd, 'USD', o.total_value_usd, LEFT(rr.reason, 500), LEFT(o.source_excerpt, 1000)
        FROM silver.donation_other o JOIN #remove_rule rr ON rr.source_donation_id = o.source_donation_id;
        PRINT '>> Rows moved to silver.excluded by #remove_rule: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));

        DELETE m FROM silver.donation_money   m JOIN #remove_rule rr ON rr.source_donation_id = m.source_donation_id;
        DELETE v FROM silver.donation_vehicle v JOIN #remove_rule rr ON rr.source_donation_id = v.source_donation_id;
        DELETE h FROM silver.donation_house   h JOIN #remove_rule rr ON rr.source_donation_id = h.source_donation_id;
        DELETE o FROM silver.donation_other   o JOIN #remove_rule rr ON rr.source_donation_id = o.source_donation_id;

        -- =====================================================
        -- 5. silver.tweet
        -- =====================================================
        PRINT '>> Loading silver.tweet';
        TRUNCATE TABLE silver.tweet;

        ;WITH u AS (
            SELECT tweet_id, tweet_date, 1 AS is_line FROM silver.donation_money
            UNION ALL SELECT tweet_id, tweet_date, 1 FROM silver.donation_vehicle
            UNION ALL SELECT tweet_id, tweet_date, 1 FROM silver.donation_house
            UNION ALL SELECT tweet_id, tweet_date, 1 FROM silver.donation_other
            UNION ALL SELECT tweet_id, tweet_date, 0 FROM silver.excluded
        ),
        g AS (
            SELECT tweet_id, MIN(tweet_date) AS tweet_date, SUM(is_line) AS donation_line_count, SUM(1 - is_line) AS excluded_line_count
            FROM u
            GROUP BY tweet_id
        ),
        raw AS (
            SELECT TRY_CAST(tweet_id AS BIGINT) AS tweet_id,
                   TRY_CAST(tweet_created_at AS DATETIME2) AS tweet_created_at,
                   LEFT(silver.fn_clean_text(author_username), 100) AS author_username,
                   tweet_text,
                   ROW_NUMBER() OVER (PARTITION BY TRY_CAST(tweet_id AS BIGINT) ORDER BY TRY_CAST(tweet_created_at AS DATETIME2) DESC) AS rn
            FROM bronze.twitter_raw_tweets
        )
        INSERT INTO silver.tweet (tweet_id, tweet_url, tweet_date, tweet_created_at, author_username, tweet_text,
                                  has_tweet_text, donation_line_count, excluded_line_count)
        SELECT g.tweet_id,
               CONCAT(N'https://x.com/i/status/', g.tweet_id),
               g.tweet_date,
               raw.tweet_created_at,
               raw.author_username,
               silver.fn_clean_text(raw.tweet_text),
               CASE WHEN silver.fn_clean_text(raw.tweet_text) IS NULL THEN 0 ELSE 1 END,
               g.donation_line_count,
               g.excluded_line_count
        FROM g
        LEFT JOIN raw ON raw.tweet_id = g.tweet_id AND raw.rn = 1;
        PRINT '>> Rows loaded: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));

        -- =====================================================
        -- 9. silver.data_quality_issues
        -- =====================================================
        PRINT '>> Loading silver.data_quality_issues';
        TRUNCATE TABLE silver.data_quality_issues;

        -- (a) rows carrying a review flag
        INSERT INTO silver.data_quality_issues (source_table, source_donation_id, issue_type, severity, description)
        SELECT t, source_donation_id, 'REVIEW_FLAG',
               CASE WHEN review_flag IN ('split_from_vehicle_row', 'split_row', 'added_row', 'moved_from_money', 'moved_from_equipment') THEN 'Info' ELSE 'Warning' END,
               CONCAT(review_flag, ': ', review_note)
        FROM (
            SELECT 'donation_money' AS t, source_donation_id, review_flag, review_note FROM silver.donation_money
            UNION ALL SELECT 'donation_vehicle', source_donation_id, review_flag, review_note FROM silver.donation_vehicle
            UNION ALL SELECT 'donation_house', source_donation_id, review_flag, review_note FROM silver.donation_house
            UNION ALL SELECT 'donation_other', source_donation_id, review_flag, review_note FROM silver.donation_other
        ) x
        WHERE review_flag IS NOT NULL;

        -- (b) rows that are kept but NOT added to totals (repeated pledges, loans, personal purchases)
        INSERT INTO silver.data_quality_issues (source_table, source_donation_id, issue_type, severity, description)
        SELECT t, source_donation_id, 'NOT_COUNTED_IN_TOTAL', 'Warning', not_counted_reason
        FROM (
            SELECT 'donation_money' AS t, source_donation_id, counts_toward_total, not_counted_reason FROM silver.donation_money
            UNION ALL SELECT 'donation_vehicle', source_donation_id, counts_toward_total, not_counted_reason FROM silver.donation_vehicle
            UNION ALL SELECT 'donation_house', source_donation_id, counts_toward_total, not_counted_reason FROM silver.donation_house
            UNION ALL SELECT 'donation_other', source_donation_id, counts_toward_total, not_counted_reason FROM silver.donation_other
        ) x
        WHERE counts_toward_total = 0;

        -- (c) money rows whose recipient count x amount could not be checked
        INSERT INTO silver.data_quality_issues (source_table, source_donation_id, issue_type, severity, description)
        SELECT 'donation_money', source_donation_id, 'AMOUNT_NOT_COMPUTABLE', 'Warning',
               CONCAT('calc_check = ', calc_check, ' (amount or recipient count missing)')
        FROM silver.donation_money
        WHERE calc_check <> 'OK';

        -- (d) every correction made to the original LLM output
        INSERT INTO silver.data_quality_issues (source_table, source_donation_id, issue_type, severity, description)
        SELECT 'llm_donations_extract', TRY_CAST(source_donation_id AS INT), 'LLM_CORRECTION', 'Info',
               LEFT(CONCAT(silver.fn_clean_text(field), ': ', silver.fn_clean_text(old_value), ' -> ',
                           silver.fn_clean_text(new_value), ' | ', silver.fn_clean_text(reason)), 2000)
        FROM bronze.reviewed_corrections_log;

        -- (e) rows removed because they are not donations
        INSERT INTO silver.data_quality_issues (source_table, source_donation_id, issue_type, severity, description)
        SELECT 'excluded', source_donation_id, 'EXCLUDED_NOT_A_DONATION', 'Info', reason_excluded
        FROM silver.excluded;
        -- (f) possible overlaps that are still counted until someone confirms them
        INSERT INTO silver.data_quality_issues (source_table, source_donation_id, issue_type, severity, description)
        SELECT source_table, source_donation_id, 'OVERLAP_REVIEW', 'Warning', description
        FROM #review_pending;

        SELECT @dq_issue_count = COUNT(*) FROM silver.data_quality_issues;
        PRINT '>> Rows loaded: ' + CAST(@dq_issue_count AS NVARCHAR(20));

        PRINT '================================================';
        PRINT 'Silver load finished. Duration (seconds): ' + CAST(DATEDIFF(SECOND, @batch_start, SYSDATETIME()) AS NVARCHAR(20));
        PRINT '================================================';
    END TRY
    BEGIN CATCH
        PRINT '================================================';
        PRINT 'ERROR while loading the Silver layer';
        PRINT 'Message : ' + ERROR_MESSAGE();
        PRINT 'Line    : ' + CAST(ERROR_LINE() AS NVARCHAR(10));
        PRINT '================================================';
        THROW;
    END CATCH
END;
GO
