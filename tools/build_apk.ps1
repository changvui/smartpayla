<#
.SYNOPSIS
  Build the SmartPayLA release APK with the right --dart-define values.

.DESCRIPTION
  The Android build needs the API proxy URL (AI reminders) and the OAuth Web
  client id (native Google sign-in). Both are public values, so they live here
  instead of being retyped on every build.

  Usage:
    .\tools\build_apk.ps1                # one universal APK
    .\tools\build_apk.ps1 -Split         # smaller per-ABI APKs
    .\tools\build_apk.ps1 -NoDemo        # no seeded demo data
#>
[CmdletBinding()]
param(
  [string]$ProxyUrl = 'https://smartpayla-ai.changvui12.workers.dev',
  [string]$GoogleClientId = '70928646592-18hnmshon6aghhv4qngqqdgrm0ninpqe.apps.googleusercontent.com',
  [switch]$Split,
  [switch]$NoDemo
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  $flutter = 'C:\flutter\bin\flutter.bat'
} else {
  $flutter = 'flutter'
}

$flutterArgs = @('build', 'apk', '--release')
if ($Split) { $flutterArgs += '--split-per-abi' }
if (-not $NoDemo) { $flutterArgs += '--dart-define=DEMO=true' }
$flutterArgs += "--dart-define=REMINDER_PROXY_URL=$ProxyUrl"
$flutterArgs += "--dart-define=GOOGLE_SERVER_CLIENT_ID=$GoogleClientId"

Write-Host ''
Write-Host 'Building SmartPayLA APK' -ForegroundColor Cyan
Write-Host ("  proxy       : $ProxyUrl") -ForegroundColor DarkGray
Write-Host ("  google id   : $GoogleClientId") -ForegroundColor DarkGray
Write-Host ("  demo data   : " + $(if ($NoDemo) { 'no' } else { 'yes' })) -ForegroundColor DarkGray
Write-Host ''

& $flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Build failed - see the messages above.' -ForegroundColor Red
  exit $LASTEXITCODE
}

Write-Host ''
Write-Host 'APK ready:' -ForegroundColor Green
Get-ChildItem (Join-Path $root 'build\app\outputs\flutter-apk') -Filter '*.apk' |
  ForEach-Object {
    "{0}  ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB)
  }
