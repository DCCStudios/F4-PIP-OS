# Meshy nano-banana: generate a Vault Boy condition figure for the MOCKUP preview only.
# The shipping mod composites the vanilla Condition_Body_*/Condition_Head clips (see
# ConditionBoy.as); this is a stand-in so the preview reads correctly.
$ErrorActionPreference = "Stop"
$key = (Get-Content "C:\Users\rober\Documents\meshy key.txt" -Raw).Trim()
$gen = Join-Path $PSScriptRoot "..\Previews\assets\gen"
$hdr = @{ Authorization = "Bearer $key" }

$body = @{
  ai_model = "nano-banana-pro"
  prompt = "A Fallout Pip-Boy health-screen Vault Boy figure: a cheerful retro 1950s cartoon mascot man shown full body in a mid-stride walking pose, wearing a vault jumpsuit jacket over a jumpsuit, combed hair, big friendly smile, one arm slightly forward. Rendered entirely as a single flat glowing phosphor-green silhouette with bold clean black outlines on a pure solid black background, vintage cel-shaded cartoon style, centered, full body head-to-feet with margin, front three-quarter view. No text, no logos, no watermark, no UI, no border."
  aspect_ratio = "3:4"
} | ConvertTo-Json

$t2i = Invoke-RestMethod -Method Post -Uri "https://api.meshy.ai/openapi/v1/text-to-image" -Headers $hdr -ContentType "application/json" -Body $body
$id = $t2i.result
"t2i task: $id"
Set-Content (Join-Path $gen "vboy_t2i_task.txt") $id -Encoding ascii
$deadline = (Get-Date).AddSeconds(260)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 8
  $t = Invoke-RestMethod -Method Get -Uri "https://api.meshy.ai/openapi/v1/text-to-image/$id" -Headers $hdr
  "{0}  {1}%" -f $t.status, $t.progress
  if ($t.status -eq "SUCCEEDED") {
    $u = @($t.image_urls)[0]
    Invoke-WebRequest -Uri $u -OutFile (Join-Path $gen "vboy_gen_raw.png") | Out-Null
    "saved vboy_gen_raw.png; credits $($t.consumed_credits)"
    exit 0
  }
  if ($t.status -in @("FAILED","CANCELED")) { "error: $($t.task_error | ConvertTo-Json -Compress)"; exit 1 }
}
"timed out"; exit 2