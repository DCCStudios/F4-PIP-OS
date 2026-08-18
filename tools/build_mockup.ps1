# Injects base64 assets into the mockup template -> Previews\pipos-mockup.html
$ErrorActionPreference = "Stop"
$prev = Join-Path $PSScriptRoot "..\Previews"
$tpl  = [IO.File]::ReadAllText((Join-Path $prev "pipos-mockup.template.html"))
$tpl  = $tpl.Replace("@@FONT@@",  (Get-Content (Join-Path $prev "assets\font.b64.txt") -Raw).Trim())
$tpl  = $tpl.Replace("@@BG@@",    (Get-Content (Join-Path $prev "assets\bg.jpg.b64.txt") -Raw).Trim())
# nano-banana AR-15 renders when present, original cutouts otherwise
$front = Join-Path $prev "assets\gen\front640.png.b64.txt"
$back  = Join-Path $prev "assets\gen\back640.png.b64.txt"
if (-not (Test-Path $front)) { $front = Join-Path $prev "assets\soldier_front.png.b64.txt" }
if (-not (Test-Path $back))  { $back  = Join-Path $prev "assets\soldier_back.png.b64.txt" }
$tpl  = $tpl.Replace("@@FRONT@@", (Get-Content $front -Raw).Trim())
$tpl  = $tpl.Replace("@@BACK@@",  (Get-Content $back -Raw).Trim())
# 3D model turntable when a GLB exists (static model by user choice — soldier_anim.glb has the
# rigged breathing idle if ever wanted again; flip-card fallback otherwise)
$glb = Join-Path $prev "assets\gen\soldier.glb"
$glbB64 = if (Test-Path $glb) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($glb)) } else { "" }
$tpl = $tpl.Replace("@@GLB@@", $glbB64)
# weapon model for the R-press Inspect view
$glb2 = Join-Path $prev "assets\gen\weapon.glb"
$glb2B64 = if (Test-Path $glb2) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($glb2)) } else { "" }
$tpl = $tpl.Replace("@@GLB2@@", $glb2B64)
# vanilla Vault Boy condition figure (extracted from Condition_Body_0.swf + Condition_Head.swf)
$vboy = Join-Path $prev "assets\gen\vaultboy.png.b64.txt"
$tpl = $tpl.Replace("@@VBOY@@", (Get-Content $vboy -Raw).Trim())
$out = Join-Path $prev "pipos-mockup.html"
[IO.File]::WriteAllText($out, $tpl)
"{0}  {1:n0} bytes" -f $out, (Get-Item $out).Length