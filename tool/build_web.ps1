# Production Flutter web build. Copies nowhere — drop build/web onto the Caddy site root.
param(
  [string]$Stamp = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not $Stamp) {
  $pubspec = Get-Content -Raw "pubspec.yaml"
  if ($pubspec -match "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
    $Stamp = $Matches[1]
  } else {
    $Stamp = "1.0.0"
  }
}

Write-Host "Building Kurier web overlay WEB v$Stamp"

flutter pub get
flutter build web --release --base-href / --no-wasm-dry-run `
  --dart-define=WEBRTC_USE_HTML_ELEMENT_VIEW=true `
  --dart-define=KURIER_WEB_STAMP=$Stamp

$notes = @{
  version = $Stamp
  builtAt = [DateTime]::UtcNow.ToString("o")
  notes   = @("Kurier Flutter web overlay $Stamp")
} | ConvertTo-Json
Set-Content -Path "build/web/web_releases.json" -Value $notes -Encoding utf8

Write-Host "Output: build/web"
Write-Host "Copy that folder to the Caddy site root (/var/www/brozantine) and reload Caddy."
