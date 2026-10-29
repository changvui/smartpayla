param(
  [string]$Email = "",
  [string]$Password = "",
  [string]$Device = "web-server",
  [int]$Port = 8081,
  [string]$ProxyUrl = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutter = Join-Path $env:ProgramFiles "flutter\bin\flutter.bat"
if (-not (Test-Path -LiteralPath $flutter)) {
  $candidate = "C:\Users\chang\Desktop\DSH\flutter\bin\flutter.bat"
  if (Test-Path -LiteralPath $candidate) {
    $flutter = $candidate
  } else {
    $flutter = "flutter"
  }
}

if ([string]::IsNullOrWhiteSpace($Email)) {
  $Email = Read-Host "Firebase test email"
}
if ([string]::IsNullOrWhiteSpace($Password)) {
  $secure = Read-Host "Firebase test password" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

$runArgs = @("run", "-d", $Device)
if ($Device -eq "web-server") {
  $runArgs += @("--web-port", $Port.ToString(), "--web-hostname", "127.0.0.1")
}

$runArgs += @(
  "--dart-define=FIREBASE_API_KEY=AIzaSyBctRZU5Gq6u5I2SOfqKXuHYS37FRnaz9Q",
  "--dart-define=FIREBASE_APP_ID=1:70928646592:web:39318c902e056ad34d8825",
  "--dart-define=FIREBASE_MESSAGING_SENDER_ID=70928646592",
  "--dart-define=FIREBASE_PROJECT_ID=smartpayla-fyp",
  "--dart-define=FIREBASE_AUTH_DOMAIN=smartpayla-fyp.firebaseapp.com",
  "--dart-define=FIREBASE_STORAGE_BUCKET=smartpayla-fyp.firebasestorage.app",
  "--dart-define=DEMO_AUTH_EMAIL=$Email",
  "--dart-define=DEMO_AUTH_PASSWORD=$Password",
  "--dart-define=DEMO=true"
)

if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
  $runArgs += "--dart-define=REMINDER_PROXY_URL=$ProxyUrl"
}

Write-Host "Starting SmartPayLA with Firebase + demo auth..." -ForegroundColor Cyan
Write-Host "Project: smartpayla-fyp  |  user: $Email" -ForegroundColor DarkGray
if ($Device -eq "web-server") {
  Write-Host "Open this in Chrome: http://127.0.0.1:$Port" -ForegroundColor Yellow
  Write-Host "Keep this PowerShell window open while the app is running." -ForegroundColor DarkGray
}
& $flutter @runArgs
