$ErrorActionPreference = "Stop"

$root = Get-Location

# --- Fix FilePicker 12 in coin_import_service.dart ---
$coinPath = Join-Path $root "lib\services\coin_import_service.dart"
if (-not (Test-Path $coinPath)) {
    throw "Could not find lib\services\coin_import_service.dart"
}

$coinBackup = "$coinPath.filepicker12.bak"
if (-not (Test-Path $coinBackup)) {
    Copy-Item $coinPath $coinBackup
}

$text = Get-Content $coinPath -Raw

$oldBlock = @'
    final pickedFile = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: false,
      withData: true,
    );

    if (pickedFile == null || pickedFile.files.isEmpty) {
      return null;
    }

    final platformFile = pickedFile.files.single;
    final Uint8List? bytes = platformFile.bytes;

    if (bytes == null) {
      throw Exception('Heritage Vault could not read the selected file.');
    }
'@

$newBlock = @'
    final platformFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (platformFile == null) {
      return null;
    }

    final Uint8List bytes = await platformFile.readAsBytes();
'@

if (-not $text.Contains($oldBlock)) {
    throw "Could not find the expected FilePicker block in coin_import_service.dart"
}

$text = $text.Replace($oldBlock, $newBlock)
Set-Content -Path $coinPath -Value $text -Encoding UTF8
Write-Host "Updated: lib\services\coin_import_service.dart" -ForegroundColor Green

# --- Fix widget test class name ---
$testPath = Join-Path $root "test\widget_test.dart"
if (Test-Path $testPath) {
    $testBackup = "$testPath.mobile.bak"
    if (-not (Test-Path $testBackup)) {
        Copy-Item $testPath $testBackup
    }

    $testText = Get-Content $testPath -Raw
    $testText = $testText.Replace("HeirloomAtlasApp", "HeritageVaultApp")
    Set-Content -Path $testPath -Value $testText -Encoding UTF8
    Write-Host "Updated: test\widget_test.dart" -ForegroundColor Green
}

Write-Host ""
Write-Host "Blocking errors patched. Next run: flutter analyze" -ForegroundColor Cyan
