# Meshy rig + animate: skeletonizes the image-to-3d soldier and applies a breathing idle.
# Chain: rigging (input_task_id) -> animations (rig_task_id, action_id) -> animated GLB.
$ErrorActionPreference = "Stop"
$key = (Get-Content "C:\Users\rober\Documents\meshy key.txt" -Raw).Trim()
$gen = Join-Path $PSScriptRoot "..\Previews\assets\gen"
$hdr = @{ Authorization = "Bearer $key" }
$actionId = 0   # "Idle" — subtle breathing idle; arms stay close so the fused rifle doesn't stretch

function Wait-Task([string]$uri) {
  $deadline = (Get-Date).AddMinutes(15)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    $t = Invoke-RestMethod -Method Get -Uri $uri -Headers $hdr
    "{0}  {1}%" -f $t.status, $t.progress
    if ($t.status -eq "SUCCEEDED") { return $t }
    if ($t.status -in @("FAILED","CANCELED")) { throw "task failed: $($t | ConvertTo-Json -Compress -Depth 5)" }
  }
  throw "timed out polling $uri"
}

$i23d = (Get-Content (Join-Path $gen "i23d_task.txt") -Raw).Trim()
"rigging from image-to-3d task $i23d"
$rigBody = @{ input_task_id = $i23d; height_meters = 1.8 } | ConvertTo-Json
$rig = Invoke-RestMethod -Method Post -Uri "https://api.meshy.ai/openapi/v1/rigging" -Headers $hdr -ContentType "application/json" -Body $rigBody
$rigId = $rig.result
"rig task: $rigId"
Set-Content (Join-Path $gen "rig_task.txt") $rigId -Encoding ascii
$rigT = Wait-Task "https://api.meshy.ai/openapi/v1/rigging/$rigId"
"rig credits: $($rigT.consumed_credits)"

$animBody = @{ rig_task_id = $rigId; action_id = $actionId } | ConvertTo-Json
$anim = Invoke-RestMethod -Method Post -Uri "https://api.meshy.ai/openapi/v1/animations" -Headers $hdr -ContentType "application/json" -Body $animBody
$animId = $anim.result
"anim task: $animId"
Set-Content (Join-Path $gen "anim_task.txt") $animId -Encoding ascii
$animT = Wait-Task "https://api.meshy.ai/openapi/v1/animations/$animId"
"anim credits: $($animT.consumed_credits)"

$glbUrl = $animT.result.animation_glb_url
if (-not $glbUrl) { throw "no animation_glb_url in result: $($animT.result | ConvertTo-Json -Compress)" }
$out = Join-Path $gen "soldier_anim.glb"
Invoke-WebRequest -Uri $glbUrl -OutFile $out | Out-Null
"saved soldier_anim.glb ({0:n0} bytes)" -f (Get-Item $out).Length