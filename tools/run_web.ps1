<#
.SYNOPSIS
  Start SmartPayLA on the web with the right build-time defines.

.DESCRIPTION
  Both AI features go through the Cloudflare Worker, so no API key ever lives in
  this project or in the browser bundle:

    * /reminder -> DeepSeek      (DEEPSEEK_API_KEY, a Worker secret)
    * /scan     -> Workers AI    (an `AI` binding, no key at all)

  Usage:
    .\tools\run_web.ps1                 # demo data, AI through the Worker
    .\tools\run_web.ps1 -Port 8081      # different port
    .\tools\run_web.ps1 -NoDemo         # empty ledger
    .\tools\run_web.ps1 -NoAi           # no Worker: offline, manual entry only
#>
[CmdletBinding()]
param(
  [int]$Port = 8080,
  [string]$ProxyUrl = 'https://smartpayla-ai.changvui12.workers.dev',
  [switch]$NoDemo,
  [switch]$NoAi
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "flutter is not on PATH. Open a new terminal, or run:" -ForegroundColor Red
  Write-Host '  $env:Path = "C:\flutter\bin;$env:Path"' -ForegroundColor Yellow
  exit 1
}

$flutterArgs = @(
  'run',
  '-d', 'web-server',
  "--web-port=$Port"
)

if (-not $NoDemo) { $flutterArgs += '--dart-define=DEMO=true' }
if (-not $NoAi -and -not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
  $flutterArgs += "--dart-define=REMINDER_PROXY_URL=$ProxyUrl"
}

Write-Host ''
Write-Host "SmartPayLA  ->  http://localhost:$Port" -ForegroundColor Cyan
Write-Host ("AI reminder : " + $(if ($NoAi) { 'off' } else { $ProxyUrl })) -ForegroundColor DarkGray
Write-Host ("Bill scan   : " + $(if ($NoAi) { 'off' } else { 'Workers AI via Worker (no key)' })) -ForegroundColor DarkGray
Write-Host 'Hot reload: r   Hot restart: R   Quit: q' -ForegroundColor DarkGray
Write-Host ''

flutter @flutterArgs
