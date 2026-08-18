# Meshy Image-to-3D: converts the approved nano-banana multi-view task into a GLB.
$ErrorActionPreference = "Stop"
$key = (Get-Content "C:\Users\rober\Documents\meshy key.txt" -Raw).Trim()
$gen = Join-Path $PSScriptRoot "..\Previews\assets\gen"
# multi-view i2i tasks are rejected as input_task_id; send the front render directly
$frontB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $gen "i2i_1.png")))

$body = @{
  image_url = "data:image/png;base64,$frontB64"
  model_type = "standard"
  ai_model = "latest"
  should_remesh = $true
  topology = "triangle"
  target_polycount = 30000
  should_texture = $true
  enable_pbr = $false
  texture_resolution = "2k"
  target_formats = @("glb")
  alpha_thumbnail = $true
  multi_view_thumbnails = $true
  origin_at = "bottom"
} | ConvertTo-Json -Depth 4

$hdr = @{ Authorization = "Bearer $key" }
$create = Invoke-RestMethod -Method Post -Uri "https://api.meshy.ai/openapi/v1/image-to-3d" -Headers $hdr -ContentType "application/json" -Body $body
$id = $create.result
"task: $id"
Set-Content (Join-Path $gen "i23d_task.txt") $id -Encoding ascii

$deadline = (Get-Date).AddMinutes(12)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 15
  $t = Invoke-RestMethod -Method Get -Uri "https://api.meshy.ai/openapi/v1/image-to-3d/$id" -Headers $hdr
  "{0}  {1}%" -f $t.status, $t.progress
  if ($t.status -eq "SUCCEEDED") {
    Invoke-WebRequest -Uri $t.model_urls.glb -OutFile (Join-Path $gen "soldier.glb") | Out-Null
    "saved soldier.glb ({0:n0} bytes)" -f (Get-Item (Join-Path $gen "soldier.glb")).Length
    if ($t.thumbnail_urls) {
      foreach ($side in @("front","right","back","left")) {
        $u = $t.thumbnail_urls.$side
        if ($u) { Invoke-WebRequest -Uri $u -OutFile (Join-Path $gen "thumb_$side.png") | Out-Null; "saved thumb_$side.png" }
      }
    }
    "credits consumed: $($t.consumed_credits)"
    exit 0
  }
  if ($t.status -in @("FAILED","CANCELED")) { "task error: $($t.task_error | ConvertTo-Json -Compress)"; exit 1 }
}
"timed out; task id saved for later polling"
exit 2