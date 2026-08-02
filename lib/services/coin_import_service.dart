import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

class CoinImportResult {
  final String fileName;
  final int sheetCount;
  final int neededCount;
  final int ownedCount;

  const CoinImportResult({
    required this.fileName,
    required this.sheetCount,
    required this.neededCount,
    required this.ownedCount,
  });

  int get trackedCount => neededCount + ownedCount;
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

    int sheetCount = 0;
    int neededCount = 0;
    int ownedCount = 0;

    for (final sheetName in workbook.tables.keys) {
      if (_ignoredSheets.contains(sheetName)) {
        continue;
      }

      final sheet = workbook.tables[sheetName];

      if (sheet == null) {
        continue;
      }

      sheetCount++;

      for (final row in sheet.rows) {
        for (final cell in row) {
          final value = _cellText(cell).toUpperCase();

          if (value == 'NEED') {
            neededCount++;
          } else if (value == 'X') {
            ownedCount++;
          }
        }
      }
    }

    return CoinImportResult(
      fileName: platformFile.name,
      sheetCount: sheetCount,
      neededCount: neededCount,
      ownedCount: ownedCount,
    );
  }

  String _cellText(dynamic value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }
}