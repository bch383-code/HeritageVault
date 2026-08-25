$ErrorActionPreference = "Stop"

$root = Get-Location

$files = @(
    "lib\screens\sports_cards_screen.dart",
    "lib\screens\postcard_edit_screen.dart",
    "lib\screens\valuable_edit_screen.dart",
    "lib\screens\antique_edit_screen.dart",
    "lib\screens\family_person_edit_screen.dart",
    "lib\screens\gedcom_import_screen.dart",
    "lib\screens\custom_collection_item_edit_screen.dart"
)

Write-Host "Updating FilePicker 12 API usage..." -ForegroundColor Cyan

foreach ($relativePath in $files) {
    $path = Join-Path $root $relativePath

    if (-not (Test-Path $path)) {
        Write-Warning "Skipped missing file: $relativePath"
        continue
    }

    $backup = "$path.filepicker11.bak"
    if (-not (Test-Path $backup)) {
        Copy-Item $path $backup
    }

    $text = Get-Content $path -Raw

    $text = $text.Replace("result?.files.single.path", "result?.single.path")
    $text = $text.Replace("result.files.single.path", "result.single.path")
    $text = $text.Replace("result.files.isEmpty", "result.isEmpty")
    $text = $text.Replace("result.files", "result")

    Set-Content -Path $path -Value $text -Encoding UTF8

    Write-Host "Updated: $relativePath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Patch complete. Backups end in .filepicker11.bak" -ForegroundColor Cyan
Write-Host "Next run: flutter analyze" -ForegroundColor Yellow
