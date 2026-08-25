$ErrorActionPreference = "Stop"

$path = Join-Path (Get-Location) "lib\services\coin_import_service.dart"

if (-not (Test-Path $path)) {
    throw "Could not find lib\services\coin_import_service.dart"
}

$backup = "$path.filepicker12-bytes.bak"
if (-not (Test-Path $backup)) {
    Copy-Item $path $backup
}

$text = Get-Content $path -Raw

$replacements = @(
    @("final Uint8List? bytes = platformFile.bytes;", "final Uint8List bytes = await platformFile.readAsBytes();"),
    @("final bytes = platformFile.bytes;", "final bytes = await platformFile.readAsBytes();")
)

$changed = $false

foreach ($pair in $replacements) {
    if ($text.Contains($pair[0])) {
        $text = $text.Replace($pair[0], $pair[1])
        $changed = $true
    }
}

# Remove the obsolete null check if it is still present.
$text = $text.Replace(@'
    if (bytes == null) {
      throw Exception('Heritage Vault could not read the selected file.');
    }
'@, "")

if (-not $changed) {
    throw "Could not find the old PlatformFile.bytes line."
}

Set-Content -Path $path -Value $text -Encoding UTF8

Write-Host "Updated: lib\services\coin_import_service.dart" -ForegroundColor Green
Write-Host "Next: flutter analyze" -ForegroundColor Cyan
