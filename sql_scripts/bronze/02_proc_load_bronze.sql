USE DonationsDW;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @batch_id UNIQUEIDENTIFIER = NEWID();
    DECLARE @base_path NVARCHAR(400) =
        N'C:\donations-datawarehouse\datasets\curated\';
    DECLARE @file NVARCHAR(400);
    DECLARE @batch_start DATETIME2 = SYSDATETIME();

    PRINT '================================================';
    PRINT 'Loading Donations Bronze Layer';
    PRINT '================================================';


    SET @file = N'C:\donations-datawarehouse\datasets\llm_extract\llm_donations_extract.csv';;
    EXEC bronze.usp_load_csv
        @table_name = N'llm_donations_extract',
        @file_path = @file,
        @batch_id = @batch_id;

    SET @file = @base_path + N'money.csv';
    EXEC bronze.usp_load_csv
        @table_name = N'reviewed_money',
        @file_path = @file,
        @batch_id = @batch_id;

    SET @file = @base_path + N'vehicle.csv';
    EXEC bronze.usp_load_csv
        @table_name = N'reviewed_vehicle',
        @file_path = @file,
        @batch_id = @batch_id;

    SET @file = @base_path + N'house.csv';
    EXEC bronze.usp_load_csv
        @table_name = N'reviewed_house',
        @file_path = @file,
        @batch_id = @batch_id;

    SET @file = @base_path + N'other_giving.csv';
    EXEC bronze.usp_load_csv
        @table_name = N'reviewed_other_giving',
        @file_path = @file,
        @batch_id = @batch_id;

    SET @file = @base_path + N'excluded_not_donations.csv';
    EXEC bronze.usp_load_csv
        @table_name = N'reviewed_excluded',
        @file_path = @file,
        @batch_id = @batch_id;

    SET @file = @base_path + N'corrections_log.csv';
    EXEC bronze.usp_load_csv
        @table_name = N'reviewed_corrections_log',
        @file_path = @file,
        @batch_id = @batch_id;

    PRINT '================================================';
    PRINT 'Bronze load finished. Duration (seconds): '
        + CAST(DATEDIFF(SECOND, @batch_start, SYSDATETIME()) AS NVARCHAR(20));
    PRINT '================================================';

    SELECT
        table_name,
        rows_loaded,
        status,
        DATEDIFF(SECOND, load_start, load_end) AS duration_sec,
        error_message
    FROM bronze.load_log
    WHERE batch_id = @batch_id
    ORDER BY log_id;
END;
GO

EXEC bronze.load_bronze;
GO