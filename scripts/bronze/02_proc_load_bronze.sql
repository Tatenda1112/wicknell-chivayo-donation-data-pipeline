/*
=============================================================
Stored Procedures: Load Bronze Layer (CSV files -> Bronze)
=============================================================
Method  : Full load (TRUNCATE then BULK INSERT), one file per table.
Audit   : every file writes one row to bronze.load_log
          (rows loaded, duration, SUCCESS or FAILED with the error).
Usage   : EXEC bronze.load_bronze;
=============================================================
*/

USE DonationsDW;
GO

-- ---------------------------------------------------------
-- Helper: truncate one bronze table and BULK INSERT one CSV.
-- A failure is logged and does NOT stop the other tables.
-- ---------------------------------------------------------
CREATE OR ALTER PROCEDURE bronze.usp_load_csv
    @table_name SYSNAME,
    @file_path  NVARCHAR(260),
    @batch_id   UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start DATETIME2 = SYSDATETIME();
    DECLARE @sql   NVARCHAR(MAX);
    DECLARE @rows  INT;

    BEGIN TRY
        PRINT '>> Truncating table : bronze.' + @table_name;
        SET @sql = N'TRUNCATE TABLE bronze.' + QUOTENAME(@table_name) + N';';
        EXEC sp_executesql @sql;

        PRINT '>> Loading file     : ' + @file_path;
        SET @sql = N'BULK INSERT bronze.' + QUOTENAME(@table_name) + N'
            FROM ''' + REPLACE(@file_path, '''', '''''') + N'''
            WITH (
                FORMAT          = ''CSV'',
                FIRSTROW        = 2,
                FIELDQUOTE      = ''"'',
                FIELDTERMINATOR = '','',
                ROWTERMINATOR   = ''0x0a'',
                CODEPAGE        = ''65001'',
                TABLOCK
            );';
        EXEC sp_executesql @sql;

        SET @sql = N'SELECT @r = COUNT(*) FROM bronze.' + QUOTENAME(@table_name) + N';';
        EXEC sp_executesql @sql, N'@r INT OUTPUT', @r = @rows OUTPUT;

        INSERT INTO bronze.load_log (batch_id, table_name, source_file, rows_loaded, load_start, load_end, status)
        VALUES (@batch_id, @table_name, @file_path, @rows, @start, SYSDATETIME(), 'SUCCESS');

        PRINT '>> Rows loaded      : ' + CAST(@rows AS NVARCHAR(20));
        PRINT '>> -------------';
    END TRY
    BEGIN CATCH
        INSERT INTO bronze.load_log (batch_id, table_name, source_file, rows_loaded, load_start, load_end, status, error_message)
        VALUES (@batch_id, @table_name, @file_path, NULL, @start, SYSDATETIME(), 'FAILED', ERROR_MESSAGE());

        PRINT '>> FAILED           : bronze.' + @table_name;
        PRINT '>> Error            : ' + ERROR_MESSAGE();
        PRINT '>> -------------';
    END CATCH
END;
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