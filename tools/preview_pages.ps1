# Renders the five PIP-OS pages in Ruffle (headless Edge) using the scratchpad harness, so visual
# regressions are caught before packaging. Adopted as a verify step after every page change:
#   build_pages.ps1  ->  verify_pages.ps1  ->  preview_pages.ps1  (inspect out\*.png)
# The harness (PreviewHost.as + shell-contract stubs + BGSCodeObj mocks) lives in the scratchpad; it
# force-links the shell classes and drives each page with mock live data, then screenshots it.
# Vanilla ConditionClips must sit at the server root under Components\ConditionClips (relative URLs
# resolve against the ROOT movie URL -- in game that root is Interface\, confirming the path).
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
$harness = "C:\Users\rober\AppData\Local\Temp\claude\e--Fallout-4-Modding-F4SE\800cd7d8-599e-4ebe-940c-b0690f31f037\scratchpad\swf_preview"
if (-not (Test-Path $harness)) { Write-Host "Preview harness not present ($harness); skipping visual preview."; exit 0 }

Copy-Item (Join-Path $proj "build\pages\PipOS_*.swf") (Join-Path $harness "swf") -Force
$srv = Start-Process node -ArgumentList "server.js" -WorkingDirectory $harness -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Seconds 2
    Push-Location $harness
    & node run_preview.js 2>&1 | Select-Object -Last 3
    Pop-Location
} finally {
    Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
}
$report = Get-Content (Join-Path $harness "out\report.json") -Raw | ConvertFrom-Json
$anyErr = $false
foreach ($k in $report.PSObject.Properties.Name) {
    $e = $report.$k.errors
    if ($e -and $e.Count -gt 0) { Write-Host "[FAIL] $k : $($e -join '; ')"; $anyErr = $true }
    else { Write-Host "[PASS] $k : rendered, 0 AS errors" }
}
Write-Host "Captures: $harness\out\*.png"
if ($anyErr) { throw "Preview render reported AS errors." }
Write-Host "PREVIEW: ALL PAGES RENDERED CLEAN"
