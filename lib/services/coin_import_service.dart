import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models/imported_coin.dart';

class CoinImportResult {
  final String fileName;
  final int sheetCount;
  final List<ImportedCoin> coins;

  const CoinImportResult({
    required this.fileName,
    required this.sheetCount,
    required this.coins,
  });

  int get neededCount =>
      coins.where((coin) => coin.isNeeded).length;

  int get ownedCount =>
      coins.where((coin) => coin.isOwned).length;

  int get trackedCount => coins.length;
}

class CoinImportService {
  static const Set<String> _ignoredSheets = {
    'Index',
    'Type',
    'Boxes',
  };

  Future<CoinImportResult?> chooseAndReadWorkbook() async {
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
      throw Exception(
        'Heritage Vault could not read the selected file.',
      );
    }

    final workbook = SpreadsheetDecoder.decodeBytes(
      bytes,
      update: false,
    );

    final importedCoins = <ImportedCoin>[];
    int sheetCount = 0;

    for (final sheetName in workbook.tables.keys) {
      if (_ignoredSheets.contains(sheetName)) {
        continue;
      }

      final sheet = workbook.tables[sheetName];

      if (sheet == null) {
        continue;
      }

      sheetCount++;

      String currentSeries = '';
      String currentStorageLocation = '';

      for (final row in sheet.rows) {
        final yearCell = _cellAt(row, 1);
        final mintCell = _cellAt(row, 2);
        final varietyCell = _cellAt(row, 3);
        final statusCell = _cellAt(row, 4);
        final notesCell = _cellAt(row, 8);

        /*
         * A header row looks like:
         * Year | Mint | Variety | Book 1 | ...
         */
        if (yearCell.toUpperCase() == 'YEAR') {
          currentStorageLocation = statusCell;
          continue;
        }

        /*
         * Series headings usually appear in column D immediately
         * above each section's header row.
         */
        if (yearCell.isEmpty &&
            varietyCell.isNotEmpty &&
            statusCell.isEmpty) {
          currentSeries = varietyCell;
          continue;
        }

        final normalizedStatus = statusCell.toUpperCase();

        if (normalizedStatus != 'X' &&
            normalizedStatus != 'NEED') {
          continue;
        }

        importedCoins.add(
          ImportedCoin(
            category: sheetName,
            series: currentSeries,
            year: yearCell,
            mint: mintCell,
            variety: varietyCell,
            status: normalizedStatus == 'X'
                ? 'Owned'
                : 'Need',
            storageLocation: currentStorageLocation,
            grade: '',
            notes: notesCell,
          ),
        );
      }
    }

    return CoinImportResult(
      fileName: platformFile.name,
      sheetCount: sheetCount,
      coins: importedCoins,
    );
  }

  String _cellAt(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) {
      return '';
    }

    final value = row[index];

    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }
}