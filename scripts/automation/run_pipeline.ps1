<#
Donations warehouse: one command, no manual steps.

  Postgres (filled by n8n)  ->  CSV files  ->  Bronze  ->  sort new rows  ->  Silver  ->  Gold views

Usage
  run_pipeline.ps1                 export from Postgres, then reload the warehouse
  run_pipeline.ps1 -Setup          also (re)create the automation procedures first
  run_pipeline.ps1 -SkipExport     reload the warehouse from the CSV files already on disk
  run_pipeline.ps1 -OpenDashboard  afterwards open Power BI and refresh it

Connection settings are read from  C:\donations-datawarehouse\pipeline.env
Exit code 0 = success, 1 = failed (the dashboard keeps its last good data).
#>
param(
    [switch]$Setup,
    [switch]$SkipExport,
    [switch]$OpenDashboard
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)      # C:\donations-datawarehouse
$logDir  = Join-Path $root 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$logFile = Join-Path $logDir ("pipeline_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-Log([string]$text) {
    $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $text
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

# Runs a program, sends everything it prints to the log, returns its exit code.
function Invoke-Tool([string]$exe, [string[]]$arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & $exe @arguments 2>&1 | ForEach-Object { Write-Log ("    " + "$_".TrimEnd()) }
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

function Stop-Pipeline([string]$why) {
    Write-Log "FAILED: $why"
    Write-Log "Log file: $logFile"
    exit 1
}

# ---------- settings ----------
$cfg = @{ PGHOST = 'localhost'; PGPORT = '5432'; PGDATABASE = ''; PGUSER = 'postgres'; PGPASSWORD = '';
          SQLSERVER = 'localhost'; SQLDATABASE = 'DonationsDW' }
$envFile = Join-Path $root 'pipeline.env'
if (Test-Path $envFile) {
    foreach ($l in Get-Content $envFile) {
        if ($l -match '^\s*([A-Za-z_]+)\s*=\s*(.*?)\s*$' -and $l -notmatch '^\s*#') { $cfg[$Matches[1].ToUpper()] = $Matches[2] }
    }
}

Write-Log '================ Donations pipeline started ================'

$sqlcmd = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $sqlcmd) { Stop-Pipeline 'sqlcmd was not found (it is installed with SQL Server / SSMS).' }
$sqlArgs = @('-S', $cfg.SQLSERVER, '-d', $cfg.SQLDATABASE, '-E', '-C', '-b', '-W')

# ---------- 1. Postgres -> CSV ----------
if (-not $SkipExport) {
    $psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
    if (-not $psql) {
        $psql = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $psql) { Stop-Pipeline 'psql.exe was not found under C:\Program Files\PostgreSQL.' }
    if (-not $cfg.PGDATABASE -or -not $cfg.PGPASSWORD) {
        Stop-Pipeline "Fill in PGDATABASE and PGPASSWORD in $envFile (the same values as the Postgres credential in n8n)."
    }

    $env:PGPASSWORD = $cfg.PGPASSWORD
    $env:PGCLIENTENCODING = 'UTF8'
    $exports = @(
        @{ Query = 'export_donations.sql';  Target = Join-Path $root 'datasets\llm_extract\llm_donations_extract.csv' },
        @{ Query = 'export_raw_tweets.sql'; Target = Join-Path $root 'datasets\raw_tweets\raw_tweets.csv' }
    )
    try {
        foreach ($e in $exports) {
            $tmp = "$($e.Target).new"
            Write-Log "Exporting from Postgres: $(Split-Path -Leaf $e.Target)"
            $code = Invoke-Tool $psql @('-X', '-q', '-w', '-v', 'ON_ERROR_STOP=1',
                                        '-h', $cfg.PGHOST, '-p', $cfg.PGPORT, '-U', $cfg.PGUSER, '-d', $cfg.PGDATABASE,
                                        '-f', (Join-Path $PSScriptRoot $e.Query), '-o', $tmp)
            if ($code -ne 0) { Remove-Item $tmp -ErrorAction SilentlyContinue; Stop-Pipeline "Postgres export failed ($($e.Query)). The old CSV was kept." }
            $lines = 0; foreach ($null in [System.IO.File]::ReadLines($tmp)) { $lines++ }
            if ($lines -lt 2) { Remove-Item $tmp -ErrorAction SilentlyContinue; Stop-Pipeline "Postgres returned no rows for $($e.Query). The old CSV was kept." }
            Move-Item -Force $tmp $e.Target      # replace the old file only after a good export
            Write-Log "    $($lines - 1) rows"
        }
    } finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
} else {
    Write-Log 'Skipping the Postgres export (-SkipExport): using the CSV files on disk.'
}

# ---------- 2. (optional) create / update the automation procedures ----------
if ($Setup) {
    Write-Log 'Creating the automation procedures (11_auto_pipeline.sql)'
    $code = Invoke-Tool $sqlcmd ($sqlArgs + @('-i', (Join-Path $PSScriptRoot '11_auto_pipeline.sql')))
    if ($code -ne 0) { Stop-Pipeline 'Could not create the automation procedures.' }
}

# ---------- 3. Bronze -> sort new rows -> Silver ----------
Write-Log 'Loading the warehouse (EXEC bronze.run_pipeline)'
$code = Invoke-Tool $sqlcmd ($sqlArgs + @('-Q', 'EXEC bronze.run_pipeline;'))
if ($code -ne 0) { Stop-Pipeline 'The warehouse load failed. Silver and Gold still hold the last good data.' }

Write-Log '================ Donations pipeline finished OK ================'

# ---------- 4. (optional) Power BI ----------
if ($OpenDashboard) {
    $refresh = Join-Path $root 'dasboard\DonationsDashboard\open_and_refresh.ps1'
    if (Test-Path $refresh) { Write-Log 'Opening Power BI and refreshing the dashboard'; & $refresh }
}
exit 0
