param(
  [string]$CodexPath
)

$ErrorActionPreference = "Stop"
$marketplaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$marketplaceFile = Join-Path $marketplaceRoot ".agents\plugins\marketplace.json"
$pluginManifest = Join-Path $marketplaceRoot "plugins\ppt-generate\.codex-plugin\plugin.json"

if (-not (Test-Path -LiteralPath $marketplaceFile)) {
  throw "Marketplace manifest is missing: $marketplaceFile"
}
if (-not (Test-Path -LiteralPath $pluginManifest)) {
  throw "PPTX Generate plugin manifest is missing: $pluginManifest"
}

if (-not $CodexPath) {
  $candidate = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($candidate) {
    $CodexPath = $candidate.FullName
  }
}
if (-not $CodexPath) {
  $command = Get-Command codex -ErrorAction SilentlyContinue
  if ($command) {
    $CodexPath = $command.Source
  }
}
if (-not $CodexPath -or -not (Test-Path -LiteralPath $CodexPath)) {
  throw "Codex CLI was not found. Install or start Codex, then rerun this script."
}

& $CodexPath plugin marketplace add $marketplaceRoot
if ($LASTEXITCODE -ne 0) {
  throw "Failed to add the local Marketplace."
}

& $CodexPath plugin add "ppt-generate@fishq-ppt-generate"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to install PPTX Generate."
}

& $CodexPath plugin list
if ($LASTEXITCODE -ne 0) {
  throw "PPTX Generate was installed, but the final plugin status check failed."
}

Write-Host ""
Write-Host "PPTX Generate is installed. Restart Codex or start a new thread."
