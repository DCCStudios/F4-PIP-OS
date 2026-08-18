# Wraps a flat mod-root payload (Interface\, F4SE\, README...) into a versioned FOMOD archive
# whose fomod\info.xml carries <Version>, which MO2 reads into its Version column on install.
# Same mechanism S2 HUD Rework uses. Reusable by package.ps1 and the test-build packaging.
#
#   make_fomod_zip.ps1 -PayloadDir <dir with Interface\ etc.> -Version 0.0.4 -OutZip <path.zip>
#                      [-ModName "PIP-OS Pip-Boy"] [-Author "Robert"] [-Description "..."]
param(
    [Parameter(Mandatory)][string]$PayloadDir,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$OutZip,
    [string]$ModName = "PIP-OS Pip-Boy",
    [string]$Author = "Robert",
    [string]$Description = "Full visual replacement of the Fallout 4 Pip-Boy menu, companion to Baka Fullscreen Pip-Boy."
)
$ErrorActionPreference = "Stop"
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must be X.Y.Z, got '$Version'." }
if (-not (Test-Path -LiteralPath $PayloadDir)) { throw "Payload dir not found: $PayloadDir" }

# Stage into a temp tree: 00 Core\<payload>  +  fomod\{info.xml,ModuleConfig.xml}
$stage = Join-Path ([IO.Path]::GetTempPath()) ("pipos_fomod_" + [Guid]::NewGuid().ToString("N"))
$core = Join-Path $stage "00 Core"
$fomod = Join-Path $stage "fomod"
New-Item -ItemType Directory -Force -Path $core, $fomod | Out-Null
Copy-Item -Path (Join-Path $PayloadDir "*") -Destination $core -Recurse -Force

# fomod\info.xml -- MO2 parses <Version> into the mod's version column.
$xmlEsc = { param($s) $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }
@"
<?xml version="1.0" encoding="UTF-8"?>
<fomod>
  <Name>$(& $xmlEsc $ModName)</Name>
  <Author>$(& $xmlEsc $Author)</Author>
  <Version>$Version</Version>
  <Website></Website>
  <Description>$(& $xmlEsc $Description)</Description>
</fomod>
"@ | Set-Content -LiteralPath (Join-Path $fomod "info.xml") -Encoding UTF8

# fomod\ModuleConfig.xml -- minimal guided installer: install 00 Core to the mod root.
@"
<?xml version="1.0" encoding="UTF-8"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://qconsulting.ca/fo3/ModConfig5.0.xsd">
  <moduleName>$(& $xmlEsc $ModName)</moduleName>
  <requiredInstallFiles>
    <folder source="00 Core" destination="" priority="0" />
  </requiredInstallFiles>
</config>
"@ | Set-Content -LiteralPath (Join-Path $fomod "ModuleConfig.xml") -Encoding UTF8

# Zip: archive root = { "00 Core\", "fomod\" }
$outDir = Split-Path -Parent $OutZip
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
if (Test-Path -LiteralPath $OutZip) { Remove-Item -LiteralPath $OutZip -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $OutZip -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force

Write-Host ("FOMOD archive: {0}  (v{1}, {2} KB)" -f $OutZip, $Version, [math]::Round((Get-Item $OutZip).Length/1KB,1))
Write-Host "  MO2 will show version '$Version' from fomod\info.xml on install."
