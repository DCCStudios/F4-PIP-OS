# Meshy weapon model: text-to-image (nano-banana, plain mode so it chains) -> image-to-3d.
# Produces Previews\assets\gen\weapon.glb for the mockup's R-press Inspect view.
$ErrorActionPreference = "Stop"
$key = (Get-Content "C:\Users\rober\Documents\meshy key.txt" -Raw).Trim()
$gen = Join-Path $PSScriptRoot "..\Previews\assets\gen"
$hdr = @{ Authorization = "Bearer $key" }

function Wait-Task([string]$uri) {
  $deadline = (Get-Date).AddMinutes(15)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 12
    $t = Invoke-RestMethod -Method Get -Uri $uri -Headers $hdr
    "{0}  {1}%" -f $t.status, $t.progress
    if ($t.status -eq "SUCCEEDED") { return $t }
    if ($t.status -in @("FAILED","CANCELED")) { throw "task failed: $($t | ConvertTo-Json -Compress -Depth 5)" }
  }
  throw "timed out polling $uri"
}

$t2iBody = @{
  ai_model = "nano-banana"
  prompt = "A single AR-15 carbine rifle displayed alone, worn parkerized dark steel finish with scratches and wear, standard handguard, iron sights, 30-round magazine, two-point sling removed, shown in three-quarter perspective from the right side, floating centered on a plain uniform light grey studio background, soft even lighting, photorealistic game-asset render, no hands, no people, no text, no watermark"
  aspect_ratio = "1:1"
} | ConvertTo-Json
$t2iIdFile = Join-Path $gen "weapon_t2i_task.txt"
if (Test-Path $t2iIdFile) {
  $t2iId = (Get-Content $t2iIdFile -Raw).Trim()
  "reusing t2i task: $t2iId"
} else {
  $t2i = Invoke-RestMethod -Method Post -Uri "https://api.meshy.ai/openapi/v1/text-to-image" -Headers $hdr -ContentType "application/json" -Body $t2iBody
  $t2iId = $t2i.result
  Set-Content $t2iIdFile $t2iId -Encoding ascii
  "t2i task: $t2iId"
}
$t2iT = Wait-Task "https://api.meshy.ai/openapi/v1/text-to-image/$t2iId"
"t2i credits: $($t2iT.consumed_credits)"
$imgUrl = @($t2iT.image_urls)[0]
if ($imgUrl) { Invoke-WebRequest -Uri $imgUrl -OutFile (Join-Path $gen "weapon_ref.png") | Out-Null; "saved weapon_ref.png" }

$i23dBody = @{
  input_task_id = $t2iId
  model_type = "standard"
  ai_model = "latest"
  should_remesh = $true
  topology = "triangle"
  target_polycount = 20000
  should_texture = $true
  enable_pbr = $false
  texture_resolution = "2k"
  target_formats = @("glb")
  alpha_thumbnail = $true
  multi_view_thumbnails = $true
  origin_at = "center"
} | ConvertTo-Json -Depth 4
$i23d = Invoke-RestMethod -Method Post -Uri "https://api.meshy.ai/openapi/v1/image-to-3d" -Headers $hdr -ContentType "application/json" -Body $i23dBody
$i23dId = $i23d.result
"i23d task: $i23dId"
Set-Content (Join-Path $gen "weapon_i23d_task.txt") $i23dId -Encoding ascii
$i23dT = Wait-Task "https://api.meshy.ai/openapi/v1/image-to-3d/$i23dId"
Invoke-WebRequest -Uri $i23dT.model_urls.glb -OutFile (Join-Path $gen "weapon.glb") | Out-Null
"saved weapon.glb ({0:n0} bytes)" -f (Get-Item (Join-Path $gen "weapon.glb")).Length
foreach ($side in @("front","right","back","left")) {
  $u = $i23dT.thumbnail_urls.$side
  if ($u) { Invoke-WebRequest -Uri $u -OutFile (Join-Path $gen "weapon_thumb_$side.png") | Out-Null }
}
"i23d credits: $($i23dT.consumed_credits)"