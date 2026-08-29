# Production Flutter Android APK. Bumps x.y.z (0-9 odometer) unless -NoBump.
param(
  [switch]$NoBump,
  [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

$bumpArgs = @()
if ($NoBump) { $bumpArgs += "--no-bump" }
if ($Notes) {
  $bumpArgs += "--notes"
  $bumpArgs += $Notes
}

Write-Host "Resolving Kurier Android version..."
$bumpOut = & dart run tool/bump_version.dart @bumpArgs
if ($LASTEXITCODE -ne 0) {
  throw "tool/bump_version.dart failed with exit $LASTEXITCODE"
}
$Stamp = ($bumpOut | Select-Object -Last 1).ToString().Trim()
if (-not $Stamp) {
  throw "bump_version.dart printed no version"
}

Write-Host "Building Kurier Android APK ANDROID v$Stamp"

flutter pub get
flutter build apk --release --dart-define=KURIER_WEB_STAMP=$Stamp

Write-Host "Output: build/app/outputs/flutter-apk/app-release.apk"
