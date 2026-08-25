$ErrorActionPreference = "Stop"

$root = Get-Location

# Fix the remaining FilePicker 12 calls in coin_import_service.dart.
$coinPath = Join-Path $root "lib\services\coin_import_service.dart"
if (-not (Test-Path $coinPath)) {
    throw "Could not find lib\services\coin_import_service.dart"
}

$backup = "$coinPath.filepicker12-second-pass.bak"
if (-not (Test-Path $backup)) {
    Copy-Item $coinPath $backup
}

$text = Get-Content $coinPath -Raw

# FilePicker 12 pickFiles() returns List<PlatformFile> directly.
$text = $text.Replace("pickedFile.files.isEmpty", "pickedFile.isEmpty")
$text = $text.Replace("pickedFile.files.single", "pickedFile.single")
$text = $text.Replace("result.files.isEmpty", "result.isEmpty")
$text = $text.Replace("result.files.single", "result.single")
$text = $text.Replace("result.files", "result")

# Null checks on pickFiles results are no longer needed in FilePicker 12.
$text = $text.Replace("pickedFile == null || pickedFile.isEmpty", "pickedFile.isEmpty")
$text = $text.Replace("result == null || result.isEmpty", "result.isEmpty")

Set-Content -Path $coinPath -Value $text -Encoding UTF8
Write-Host "Updated: lib\services\coin_import_service.dart" -ForegroundColor Green

# Fix stale widget-test app class name.
$testPath = Join-Path $root "test\widget_test.dart"
if (Test-Path $testPath) {
    $testBackup = "$testPath.mobile-second-pass.bak"
    if (-not (Test-Path $testBackup)) {
        Copy-Item $testPath $testBackup
    }

    $testText = Get-Content $testPath -Raw
    $testText = $testText.Replace("HeirloomAtlasApp", "HeritageVaultApp")
    Set-Content -Path $testPath -Value $testText -Encoding UTF8
    Write-Host "Updated: test\widget_test.dart" -ForegroundColor Green
}

Write-Host ""
Write-Host "Second-pass blockers fixed. Run flutter analyze." -ForegroundColor Cyan
