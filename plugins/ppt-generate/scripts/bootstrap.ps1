$ErrorActionPreference = "Stop"

function Get-NodeMajor {
  $command = Get-Command node -ErrorAction SilentlyContinue
  if (-not $command) { return 0 }
  $version = (& $command.Source --version 2>$null)
  if ($version -match '^v(\d+)') { return [int]$Matches[1] }
  return 0
}

$major = Get-NodeMajor
if ($major -ge 22) {
  Write-Output "Node.js $major is already available."
  exit 0
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
  throw "Node.js 22+ is required and Winget is unavailable. PPTX Generate will not download executables from unknown sources."
}

Write-Output "Installing Node.js LTS through Winget..."
& $winget.Source install --id OpenJS.NodeJS.LTS --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) {
  throw "Winget failed to install Node.js LTS with exit code $LASTEXITCODE."
}

$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
$major = Get-NodeMajor
if ($major -lt 22) {
  throw "Node.js installation completed, but Node.js 22+ is not available in the refreshed PATH."
}

Write-Output "Node.js $major is ready. Restart Codex so the PPTX Generate MCP server can start."
