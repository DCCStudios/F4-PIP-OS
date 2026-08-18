# Assembles the MO2-installable FOMOD archive from the Package\ payload.
# Builds the shell + pages, then wraps Package\ into a versioned FOMOD (fomod\info.xml carries
# <Version>, which MO2 reads into its version column) -> dist\PipOSPipboy-<ver>.zip.
#   package.ps1 [-Version X.Y.Z]   (default below). Bump the version each hand-off build.
param([string]$Version = "0.1.0")
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
$version = $Version

# 1. (re)build + verify the shell so Package\Interface\PipboyMenu.swf is current
& (Join-Path $PSScriptRoot "build_shell.ps1")
& (Join-Path $PSScriptRoot "verify_shell.ps1")

# 2. build + verify the five PIP-OS pages
& (Join-Path $PSScriptRoot "build_pages.ps1")
& (Join-Path $PSScriptRoot "verify_pages.ps1")

# 3. (optional) copy the DLL if it has been built (xmake set_targetdir -> dll\Compile\F4SE\Plugins)
$dllOut = @(Get-ChildItem -Recurse -Filter "PipOSPipboy.dll" -Path (Join-Path $proj "dll\Compile"), (Join-Path $proj "dll\build") -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($dllOut.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path (Join-Path $proj "Package\F4SE\Plugins") | Out-Null
    Copy-Item $dllOut[0].FullName (Join-Path $proj "Package\F4SE\Plugins\PipOSPipboy.dll") -Force
    Write-Host "Included companion DLL ($($dllOut[0].Length) bytes)."
} else {
    Write-Host "DLL not built; packaging without it (pages/shell fully functional; external passthrough then defaults to auto-fallback)."
}

# 4. wrap the Package\ payload into a versioned FOMOD (fomod\info.xml drives MO2's version column;
#    guided installer drops "00 Core" at the mod root -> Interface\/F4SE\, no Data\ wrapper).
$dist = Join-Path $proj "dist"
$zip = Join-Path $dist "PipOSPipboy-$version.zip"
& (Join-Path $PSScriptRoot "make_fomod_zip.ps1") -PayloadDir (Join-Path $proj "Package") -Version $version -OutZip $zip -ModName "PIP-OS Pip-Boy"
