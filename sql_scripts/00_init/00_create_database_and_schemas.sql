/*
=============================================================
Create Database and Schemas
=============================================================
Project : Donations Data Warehouse (Medallion architecture)
Purpose : Creates the database 'DonationsDW' and the three layers
          (schemas) bronze, silver and gold.

WARNING : If the database already exists it is DROPPED and
          recreated. All data in it is lost. Run once, at the start.
=============================================================
*/

USE master;
GO

-- Drop and recreate the database if it already exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DonationsDW')
BEGIN
    ALTER DATABASE DonationsDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DonationsDW;
END;
GO

CREATE DATABASE DonationsDW;
GO

USE DonationsDW;
GO

-- Create the schemas (one per layer)
CREATE SCHEMA bronze;   -- raw data, as-is from the sources
GO
CREATE SCHEMA silver;   -- cleaned and standardised data
GO
CREATE SCHEMA gold;     -- business-ready views for Power BI
GO
