# Static verification of the built shell. Proves the vanilla contract is intact by BODY-DIFFING every
# exported class against a fresh vanilla export (catches mangled bytecode in untouched classes -- the
# exact JPEXS -replace risk), asserting PipboyMenu.as is additively patched, and comparing SymbolClass
# bindings (the PipboyTabs getChildAt(4)/Menu_mc contract). All scratch output goes to a temp dir.
$ErrorActionPreference = "Stop"
$ffdec   = "E:\Fallout 4 Modding\F4SE\PluginTemplate\jpexs-gui\ffdec.bat"
$vanilla = "D:\Fallout 4 Interface Source\Interface\PipboyMenu.swf"
$proj    = Split-Path -Parent $PSScriptRoot
$outSwf  = Join-Path $proj "build\shell\PipboyMenu.swf"
$tmp     = Join-Path $env:TEMP ("pipos_verify_shell_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$fail = 0

# (1) header
& $ffdec -swf2xml $outSwf (Join-Path $tmp "head.xml") 2>&1 | Out-Null
$h = Get-Content (Join-Path $tmp "head.xml") -Raw
if ($h -match '<swf[^>]*\sversion="15"' -and $h -match 'compression="ZLIB"' -and $h -match 'frameCount="1"') {
  Write-Host "[PASS] header: version 15 / ZLIB / frameCount 1"
} else { Write-Host "[FAIL] header mismatch"; $fail++ }

# (2) body-diff every class vs a fresh vanilla export
& $ffdec -export script (Join-Path $tmp "van") $vanilla 2>&1 | Out-Null
& $ffdec -export script (Join-Path $tmp "pat") $outSwf 2>&1 | Out-Null
$vanFiles = Get-ChildItem -Recurse (Join-Path $tmp "van\scripts") -Filter *.as
$patFiles = Get-ChildItem -Recurse (Join-Path $tmp "pat\scripts") -Filter *.as
$vanNames = $vanFiles | ForEach-Object { $_.Name } | Sort-Object
$patNames = $patFiles | ForEach-Object { $_.Name } | Sort-Object
if (Compare-Object $vanNames $patNames) { Write-Host "[FAIL] class inventory differs"; $fail++ }
else { Write-Host "[PASS] class inventory identical ($($patNames.Count) classes)" }

$changed = @(); $identical = 0
foreach ($vf in $vanFiles) {
    $pf = $patFiles | Where-Object { $_.Name -eq $vf.Name } | Select-Object -First 1
    if (-not $pf) { continue }
    $vh = (Get-FileHash $vf.FullName -Algorithm SHA256).Hash
    $ph = (Get-FileHash $pf.FullName -Algorithm SHA256).Hash
    if ($vh -ne $ph) { $changed += $vf.Name } else { $identical++ }
}
# Only PipboyMenu.as may differ (additive patch); everything else must be byte-identical.
$unexpected = $changed | Where-Object { $_ -ne "PipboyMenu.as" }
if ($unexpected.Count -eq 0 -and ($changed -contains "PipboyMenu.as")) {
    Write-Host "[PASS] body-diff: $identical/$($vanFiles.Count) classes byte-identical to vanilla; only PipboyMenu.as changed (by design)"
} else {
    Write-Host "[FAIL] body-diff: unexpected changed classes: $($unexpected -join ', ')"; $fail++
}

# (3) PipboyMenu.as additively patched (markers present, vanilla API preserved)
$menu = Get-Content (Join-Path $tmp "pat\scripts\PipboyMenu.as") -Raw
$markers = @('PipOS_StatsPage.swf','SetPageMode','onPageLoadError','ExternalPageName')
$missing = $markers | Where-Object { $menu -notmatch [regex]::Escape($_) }
$apiKept = ($menu -match 'onNewPage' -and $menu -match 'onNewTab' -and $menu -match 'PopulatePipboyInfoObj' -and $menu -match 'RegisterMovie')
if ($missing.Count -eq 0 -and $apiKept) { Write-Host "[PASS] PipboyMenu.as additively patched (PIP-OS loader present, vanilla BGSCodeObj API preserved)" }
else { Write-Host "[FAIL] PipboyMenu.as patch/API issue (missing: $($missing -join ','))"; $fail++ }

# (4) SymbolClass bindings identical (PipboyTabs Menu_mc / getChildAt(4) contract).
# Compare the SymbolClassTag <tags>(char ids) and <names>(class names) verbatim between vanilla
# and patched via the full swf2xml export.
function Get-SymbolClass($swf, $dest) {
    & $ffdec -swf2xml $swf $dest 2>&1 | Out-Null
    $x = Get-Content $dest -Raw
    $m = [regex]::Match($x, 'SymbolClassTag".*?<tags>(.*?)</tags>.*?<names>(.*?)</names>', 'Singleline')
    if (-not $m.Success) { return $null }
    $ids   = [regex]::Matches($m.Groups[1].Value, '<item>([^<]+)</item>') | ForEach-Object { $_.Groups[1].Value }
    $names = [regex]::Matches($m.Groups[2].Value, '<item>([^<]+)</item>') | ForEach-Object { $_.Groups[1].Value }
    return @{ ids = ($ids -join ','); names = ($names -join ',') }
}
$vsc = Get-SymbolClass $vanilla (Join-Path $tmp "vsc.xml")
$psc = Get-SymbolClass $outSwf  (Join-Path $tmp "psc.xml")
if ($vsc -and $psc -and $vsc.ids -eq $psc.ids -and $vsc.names -eq $psc.names) {
    Write-Host "[PASS] SymbolClass bindings identical (Menu_mc/getChildAt contract intact; $($psc.names.Split(',').Count) symbols)"
} else { Write-Host "[FAIL] SymbolClass bindings differ"; $fail++ }

# (5) Child-index safety: the CRT chrome must attach as a ROOT SIBLING (this.parent.addChild), never a
# child of Menu_mc, so Menu_mc.getChildAt(4) still resolves to the page (PipboyTabs contract). Assert
# the patched PipboyMenu adds chrome via parent, never via this.addChild(chrome), and the vanilla
# page addChild path in onPageLoadComplete is preserved.
$menu2 = Get-Content (Join-Path $tmp "pat\scripts\PipboyMenu.as") -Raw
$allChromeAdds    = ([regex]::Matches($menu2, 'addChild\(this\._chrome')).Count
$parentChromeAdds = ([regex]::Matches($menu2, 'parent\.addChild\(this\._chrome')).Count
$parentAdd   = ($parentChromeAdds -ge 1)                 # chrome added via this.parent
$noSelfAdd   = ($allChromeAdds -eq $parentChromeAdds)    # NO chrome addChild goes to Menu_mc itself
$pageAddKept = ($menu2 -match 'addChild\(_loc2_\)')      # onPageLoadComplete adds the page as before
if ($parentAdd -and $noSelfAdd -and $pageAddKept) {
    Write-Host "[PASS] child-index safety: chrome attaches to this.parent (root sibling); Menu_mc child list (getChildAt(4)=page) unchanged"
} else {
    Write-Host "[FAIL] child-index safety (parentAdd=$parentAdd noSelfAdd=$noSelfAdd pageAddKept=$pageAddKept)"; $fail++
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fail -eq 0) { Write-Host "`nVERIFY SHELL: ALL CHECKS PASSED" } else { throw "VERIFY SHELL: $fail check(s) failed" }
