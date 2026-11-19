@echo off
rem Postgres (n8n) -> SQL Server -> Power BI, in one double-click.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\automation\run_pipeline.ps1" -OpenDashboard
if errorlevel 1 (
    echo.
    echo The pipeline FAILED. See the newest file in "%~dp0logs".
    pause
)
