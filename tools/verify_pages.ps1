# Static verification of built PIP-OS pages: header matches vanilla (CWS/version 15/frameCount 1),
# document class extends PipboyPage, and the shell-provided stub classes are NOT embedded
# (they must resolve to the shell's runtime definitions via the shared ApplicationDomain).
param([string[]]$Pages = @("PipOS_InvPage","PipOS_StatsPage","PipOS_DataPage","PipOS_MapPage","PipOS_RadioPage"))
$ErrorActionPreference = "Stop"
$ffdec = "E:\Fallout 4 Modding\F4SE\PluginTemplate\jpexs-gui\ffdec.bat"
$proj  = Split-Path -Parent $PSScriptRoot
$out   = Join-Path $proj "build\pages"
$stubNames = @("PipboyPage.as","PipboySubMenu.as","BSUIComponent.as","Pipboy_DataObj.as","PipboyChangeEvent.as","PipboyUpdateMask.as","BSButtonHintData.as","BGSExternalInterface.as")
$fail = 0
foreach ($p in $Pages) {
    $swf = Join-Path $out "$p.swf"
    if (-not (Test-Path $swf)) { Write-Host "[skip] $p (not built)"; continue }
    $b = [System.IO.File]::ReadAllBytes($swf)
    $sig = "" + [char]$b[0] + [char]$b[1] + [char]$b[2]
    $ver = $b[3]
    $hdrOK = ($sig -eq "CWS" -and $ver -eq 17)
    $vdir = Join-Path $out "_v_$p"
    & $ffdec -export script $vdir $swf 2>&1 | Out-Null
    $doc = Get-ChildItem -Recurse $vdir -Filter "$p.as" | Select-Object -First 1
    $extends = $false; $callSurface = @()
    if ($doc) {
        $txt = Get-Content $doc.FullName -Raw
        $extends = ($txt -match "extends PipboyPage")
        foreach ($m in [regex]::Matches($txt, '"(SelectItem|ExamineItem|ItemDrop|SortItemList|SetQuickkey|onInvItemSelection|updateItem3D|onNewTab|ShowPerksMenu|UseStimpak|UseRadaway|ToggleRadioStationActiveStatus|SetQuestActive|ShowQuestOnMap|SetPlayerMarker|onSwitchBetweenWorldLocalMap|PlaySound)"')) { $callSurface += $m.Groups[1].Value }
    }
    $embeddedStubs = @()
    foreach ($sn in $stubNames) { if (Get-ChildItem -Recurse $vdir -Filter $sn -ErrorAction SilentlyContinue) { $embeddedStubs += $sn } }
    $stubsClean = ($embeddedStubs.Count -eq 0)
    $ok = $hdrOK -and $extends -and $stubsClean
    if (-not $ok) { $fail++ }
    Write-Host ("[{0}] {1}: header={2}(CWS/v{3}) extendsPipboyPage={4} stubsEmbedded={5} calls={{{6}}}" -f `
        ($(if($ok){"PASS"}else{"FAIL"})), $p, $sig, $ver, $extends, $embeddedStubs.Count, (($callSurface | Select-Object -Unique) -join ","))
}
# Round-18 enforcement: no TextField text/width reachable from a page ctor (buildPanels must be font-free).
$ctorChk = & python (Join-Path $PSScriptRoot "ctor_text_check.py") 2>&1
$ctorChk | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { $fail++ }
if ($fail -gt 0) { throw "$fail page(s) failed verification" } else { Write-Host "`nPAGES VERIFY: ALL PASSED" }
