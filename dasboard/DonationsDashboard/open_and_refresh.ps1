<#
Opens DonationsDashboard.pbip in Power BI Desktop and refreshes all tables
from SQL Server (DonationsDW) as soon as the model has loaded.
Start it with "Open dashboard (refresh data).cmd" in the same folder.
#>
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pbip = Join-Path $here 'DonationsDashboard.pbip'

# Power BI Desktop (MSI install first, then the Microsoft Store install)
$pbi = @("$env:ProgramFiles\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
         "$env:LOCALAPPDATA\Microsoft\WindowsApps\PBIDesktopStore.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $pbi) { Write-Host 'Power BI Desktop was not found.'; Read-Host 'Press Enter to close'; exit 1 }

# Tabular Object Model library (ships with SSMS and SQL Server)
$tom = Get-ChildItem -Path "$env:ProgramFiles\Microsoft SQL Server Management Studio *\Release\Common7\IDE\Microsoft.AnalysisServices.Tabular.dll",
                            "$env:ProgramFiles\Microsoft SQL Server\*\DTS\Binn\Microsoft.AnalysisServices.Tabular.dll" -ErrorAction SilentlyContinue |
       Sort-Object { $_.VersionInfo.FileVersion } -Descending | Select-Object -First 1
if (-not $tom) { Write-Host 'Microsoft.AnalysisServices.Tabular.dll not found (install SSMS). Opening without refresh.'; Start-Process $pbi -ArgumentList "`"$pbip`""; exit 0 }
Add-Type -Path $tom.FullName

Write-Host 'Opening the dashboard in Power BI Desktop...'
$before = @(Get-Process msmdsrv -ErrorAction SilentlyContinue | ForEach-Object Id)
Start-Process $pbi -ArgumentList "`"$pbip`""

# Wait for the dashboard's own model engine to start
$engine = $null; $deadline = (Get-Date).AddMinutes(4)
while (-not $engine -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $engine = Get-Process msmdsrv -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Id } | Select-Object -First 1
}
if (-not $engine) { Write-Host 'Power BI did not start its model engine in time. Use Home > Refresh instead.'; Read-Host 'Press Enter to close'; exit 1 }

$port = $null
while (-not $port -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    $port = (Get-NetTCPConnection -OwningProcess $engine.Id -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).LocalPort
}

# Wait for the model to load
$srv = New-Object Microsoft.AnalysisServices.Tabular.Server
$loaded = $false
while (-not $loaded -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    try {
        $srv.Connect("Data Source=localhost:$port")
        $loaded = ($srv.Databases.Count -gt 0 -and $srv.Databases[0].Model.Tables.Count -gt 0)
    } catch { } finally { if ($srv.Connected) { $srv.Disconnect() } }
}
Start-Sleep -Seconds 10

# Press Power BI's own Home > Refresh button, so Power BI knows the data changed
# and Ctrl+S saves the refreshed data with the file.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$window = Get-CimInstance Win32_Process -Filter "Name='PBIDesktop.exe'" |
          Where-Object { $_.ProcessId -eq (Get-CimInstance Win32_Process -Filter "ProcessId=$($engine.Id)").ParentProcessId } |
          ForEach-Object { Get-Process -Id $_.ProcessId }
$pressed = $false
if ($window) {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($window.MainWindowHandle)
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $all) {
        if ($e.Current.Name -eq 'Refresh' -and $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) {
            $o = $null
            if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$o)) { $o.Invoke(); $pressed = $true; break }
        }
    }
}
if ($pressed) {
    Write-Host 'Refreshing data from SQL Server (DonationsDW)... When it finishes, press Ctrl+S to keep it.'
} else {
    # Fallback: refresh through the engine (data shows, but Ctrl+S may not keep it)
    try {
        $srv.Connect("Data Source=localhost:$port")
        $srv.Databases[0].Model.RequestRefresh([Microsoft.AnalysisServices.Tabular.RefreshType]::Full)
        $srv.Databases[0].Model.SaveChanges() | Out-Null
        Write-Host 'Data refreshed. To save it with the file, also click Home > Refresh in Power BI, then Ctrl+S.'
    } catch { Write-Host 'Could not refresh automatically. Use Home > Refresh in Power BI, then Ctrl+S.' }
    finally { if ($srv.Connected) { $srv.Disconnect() } }
}
Start-Sleep -Seconds 6
