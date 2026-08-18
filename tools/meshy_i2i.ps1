# Meshy Image-to-Image (nano-banana): puts an AR-15 in the soldier's hands.
# Uses front+back cutouts as references, requests a multi-view sheet so the
# result can feed image-to-3d directly via input_task_id.
# Key file is read at call time and never printed.
$ErrorActionPreference = "Stop"
$key = (Get-Content "C:\Users\rober\Documents\meshy key.txt" -Raw).Trim()
$assets = Join-Path $PSScriptRoot "..\Previews\assets"
$gen = Join-Path $assets "gen"
New-Item -ItemType Directory -Force $gen | Out-Null

$front = (Get-Content (Join-Path $assets "soldier_front.png.b64.txt") -Raw).Trim()
$back  = (Get-Content (Join-Path $assets "soldier_back.png.b64.txt") -Raw).Trim()

$body = @{
  ai_model = "nano-banana-pro"
  prompt = "Same character as the reference images: a wasteland soldier wearing a dark red beret, grey-green gas mask, camouflage fatigues, dark brown chest armor, pouched belt, and brown leather boots. He now holds an AR-15 carbine with a worn parkerized finish in both hands in a relaxed low-ready patrol position across his chest, muzzle pointed down toward his left boot, a simple two-point sling over his right shoulder. Keep the outfit, colors, materials, body proportions, and photorealistic game-render style exactly identical to the references. Full body from beret to boots, standing upright, centered, plain uniform light grey studio background, soft even lighting, no watermark text."
  reference_image_urls = @(
    "data:image/png;base64,$front",
    "data:image/png;base64,$back"
  )
  generate_multi_view = $true
} | ConvertTo-Json -Depth 4

$hdr = @{ Authorization = "Bearer $key" }
$create = Invoke-RestMethod -Method Post -Uri "https://api.meshy.ai/openapi/v1/image-to-image" -Headers $hdr -ContentType "application/json" -Body $body
$id = $create.result
"task: $id"
Set-Content (Join-Path $gen "i2i_task.txt") $id -Encoding ascii

$deadline = (Get-Date).AddSeconds(260)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 8
  $t = Invoke-RestMethod -Method Get -Uri "https://api.meshy.ai/openapi/v1/image-to-image/$id" -Headers $hdr
  "{0}  {1}%" -f $t.status, $t.progress
  if ($t.status -eq "SUCCEEDED") {
    $i = 1
    foreach ($u in $t.image_urls) {
      $f = Join-Path $gen ("i2i_{0}.png" -f $i)
      Invoke-WebRequest -Uri $u -OutFile $f | Out-Null
      "saved $f"
      $i++
    }
    "credits consumed: $($t.consumed_credits)"
    exit 0
  }
  if ($t.status -in @("FAILED","CANCELED")) { "task error: $($t.task_error | ConvertTo-Json -Compress)"; exit 1 }
}
"timed out waiting; task id saved for later polling"
exit 2