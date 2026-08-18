# Builds the PIP-OS PipboyMenu.swf shell by patching the vanilla shell's PipboyMenu ActionScript
# (contract-preserving: only the PipboyMenu ABC method table is replaced; SymbolClass / display list
# are untouched so PipboyTabs' getChildAt(4)/_TabNames injection still works).
$ErrorActionPreference = "Stop"
$ffdec   = "E:\Fallout 4 Modding\F4SE\PluginTemplate\jpexs-gui\ffdec.bat"
$vanilla = "D:\Fallout 4 Interface Source\Interface\PipboyMenu.swf"
$proj    = Split-Path -Parent $PSScriptRoot
$work    = Join-Path $proj "build\shell"
$patch   = Join-Path $work "PipboyMenu_patched.as"
$outSwf  = Join-Path $work "PipboyMenu.swf"

New-Item -ItemType Directory -Force -Path $work | Out-Null
if (-not (Test-Path $patch)) { throw "Missing patched source: $patch" }

Copy-Item $vanilla (Join-Path $work "PipboyMenu_vanilla.swf") -Force
Copy-Item $vanilla $outSwf -Force

& $ffdec -replace $outSwf $outSwf "PipboyMenu" $patch 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "ffdec replace failed (exit $LASTEXITCODE)" }

# Copy into the package payload (mod-root layout: Interface\ at archive root, no Data\ wrapper)
$pkgIface = Join-Path $proj "Package\Interface"
New-Item -ItemType Directory -Force -Path $pkgIface | Out-Null
Copy-Item $outSwf (Join-Path $pkgIface "PipboyMenu.swf") -Force

Write-Host "Built shell: $outSwf ($((Get-Item $outSwf).Length) bytes)"
Write-Host "Copied to package payload: $pkgIface\PipboyMenu.swf"
