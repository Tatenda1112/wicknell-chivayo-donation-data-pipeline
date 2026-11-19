@echo off
rem Opens the dashboard in Power BI Desktop and refreshes it from SQL Server.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open_and_refresh.ps1"
