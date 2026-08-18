# Builds the PIP-OS page SWFs with mxmlc (Apache Flex 4.16.1). Shell-provided classes are compiled
# against external stubs (PipOSStubs.swc) so they are NOT embedded; at runtime the shell's real
# definitions win via the shared ApplicationDomain (same technique as S2 HUD Rework).
# Output is normalized to SWF version 15 / ZLIB to match the vanilla pages.
param([string[]]$Pages = @("PipOS_InvPage","PipOS_StatsPage","PipOS_DataPage","PipOS_MapPage","PipOS_RadioPage"))
$ErrorActionPreference = "Stop"

$flexBin = "E:\Fallout 4 Modding\F4SE\_tools\flex\bin"
$player  = "E:\Fallout 4 Modding\F4SE\_tools\airsdk\frameworks\libs\player"
$ffdec   = "E:\Fallout 4 Modding\F4SE\PluginTemplate\jpexs-gui\ffdec.bat"
$proj    = Split-Path -Parent $PSScriptRoot
$stubSrc = Join-Path $proj "InterfaceStubs"
$src     = Join-Path $proj "InterfaceSource"
$out     = Join-Path $proj "build\pages"
$pkg     = Join-Path $proj "Package\Interface"
$env:PLAYERGLOBAL_HOME = $player
New-Item -ItemType Directory -Force -Path $out, $pkg | Out-Null

# 1. stub SWC (external contract)
$swc = Join-Path $out "PipOSStubs.swc"
& (Join-Path $flexBin "compc.bat") `
    "-target-player=32.0" "-swf-version=17" `
    "-source-path=$stubSrc" `
    "-output=$swc" `
    "-include-classes" `
    "Shared.AS3.BSUIComponent" "Shared.AS3.BSButtonHintData" "Shared.BGSExternalInterface" `
    "PipboyUpdateMask" "PipboyChangeEvent" "Pipboy_DataObj" "PipboySubMenu" "PipboyPage" 2>&1 | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { throw "compc stub SWC failed" }
Write-Host "[ok] PipOSStubs.swc"

# 2. each page
foreach ($p in $Pages) {
    $main = Join-Path $src "$p.as"
    if (-not (Test-Path $main)) { Write-Host "[skip] $p (no source)"; continue }
    $swf = Join-Path $out "$p.swf"
    & (Join-Path $flexBin "mxmlc.bat") `
        "-target-player=32.0" "-swf-version=17" "-debug=false" "-optimize=true" `
        "-default-frame-rate=30" "-default-size=1280,720" `
        "-source-path=$src" `
        "-external-library-path+=$swc" `
        "-output=$swf" $main 2>&1 | Select-Object -Last 4
    if ($LASTEXITCODE -ne 0) { throw "mxmlc $p failed" }

    # mxmlc already emits CWS (ZLIB) / SWF version 15 / frameCount 1 -- matches the vanilla pages.
    Copy-Item $swf (Join-Path $pkg "$p.swf") -Force
    Write-Host "[ok] $p.swf ($((Get-Item $swf).Length) bytes) -> package"
}

# PIP-OS CRT chrome overlay (pipos.Chrome + embedded font). 0.0.56: the SHELL MEDIC references shell-contract
# classes (PipboyChangeEvent/PipboyUpdateMask), so chrome now links the stub SWC EXTERNALLY like the pages
# (compile-only; at runtime the shell's real definitions win via first-def-wins).
$chromeMain = Join-Path $src "pipos\Chrome.as"
if (Test-Path $chromeMain) {
    $chromeSwf = Join-Path $out "PipOS_Chrome.swf"
    & (Join-Path $flexBin "mxmlc.bat") `
        "-target-player=32.0" "-swf-version=17" "-debug=false" "-optimize=true" `
        "-default-frame-rate=30" "-default-size=1280,720" `
        "-source-path=$src" `
        "-external-library-path+=$swc" `
        "-output=$chromeSwf" $chromeMain 2>&1 | Select-Object -Last 3
    if ($LASTEXITCODE -ne 0) { throw "mxmlc PipOS_Chrome failed" }
    Copy-Item $chromeSwf (Join-Path $pkg "PipOS_Chrome.swf") -Force
    Write-Host "[ok] PipOS_Chrome.swf ($((Get-Item $chromeSwf).Length) bytes) -> package"
}

# PipboyBackgroundMenu override (1920x1080, 16:9 first) -- full-screen CRT framing. Overwrites Baka's.
$bgMain = Join-Path $src "PipboyBackgroundMenu.as"
if (Test-Path $bgMain) {
    $bgSwf = Join-Path $out "PipboyBackgroundMenu.swf"
    & (Join-Path $flexBin "mxmlc.bat") `
        "-target-player=32.0" "-swf-version=17" "-debug=false" "-optimize=true" `
        "-default-frame-rate=30" "-default-size=1920,1080" `
        "-source-path=$src" `
        "-output=$bgSwf" $bgMain 2>&1 | Select-Object -Last 3
    if ($LASTEXITCODE -ne 0) { throw "mxmlc PipboyBackgroundMenu failed" }
    Copy-Item $bgSwf (Join-Path $pkg "PipboyBackgroundMenu.swf") -Force
    Write-Host "[ok] PipboyBackgroundMenu.swf ($((Get-Item $bgSwf).Length) bytes) -> package"
}
Write-Host "Pages built."
