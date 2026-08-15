import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models/imported_coin.dart';
import '../reference/coin_series_reference.dart';

class CoinCategorySummary {
  final String category;
  final int total;
  final int owned;
  final int needed;
  final int untracked;

  const CoinCategorySummary({
    required this.category,
    required this.total,
    required this.owned,
    required this.needed,
    required this.untracked,
  });
}

class CoinImportResult {
  final String fileName;
  final int sheetCount;
  final List<ImportedCoin> coins;
  final List<CoinCategorySummary> categories;

  const CoinImportResult({
    required this.fileName,
    required this.sheetCount,
    required this.coins,
    required this.categories,
  });

  int get neededCount => coins.where((coin) => coin.status == 'Need').length;
  int get ownedCount => coins.where((coin) => coin.status == 'Owned').length;
  int get untrackedCount =>
      coins.where((coin) => coin.status == 'Untracked').length;
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
      throw Exception('Heritage Vault could not read the selected file.');
    }

    final workbook = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    final importedCoins = <ImportedCoin>[];
    final summaries = <CoinCategorySummary>[];

    for (final sheetName in workbook.tables.keys) {
      if (_ignoredSheets.contains(sheetName)) {
        continue;
      }

      final sheet = workbook.tables[sheetName];
      if (sheet == null) {
        continue;
      }

      final sheetCoins = _readSheet(sheetName, sheet.rows);
      importedCoins.addAll(sheetCoins);

      summaries.add(
        CoinCategorySummary(
          category: sheetName,
          total: sheetCoins.length,
          owned: sheetCoins.where((coin) => coin.status == 'Owned').length,
          needed: sheetCoins.where((coin) => coin.status == 'Need').length,
          untracked:
              sheetCoins.where((coin) => coin.status == 'Untracked').length,
        ),
      );
    }

    summaries.sort((a, b) => a.category.compareTo(b.category));

    return CoinImportResult(
      fileName: platformFile.name,
      sheetCount: summaries.length,
      coins: importedCoins,
      categories: summaries,
    );
  }

  List<ImportedCoin> _readSheet(
    String category,
    List<List<dynamic>> rows,
  ) {
    final coins = <ImportedCoin>[];

    int? yearIndex;
    int? mintIndex;
    int? varietyIndex;
    int notesIndex = -1;
    List<int> ownershipIndexes = [];
    List<String> ownershipLabels = [];
    String currentSeries = '';

    for (final row in rows) {
      final cells = row.map(_cellText).toList();
      final normalized = cells.map((cell) => cell.toUpperCase()).toList();

      final detectedYearIndex = normalized.indexOf('YEAR');
      final detectedMintIndex = normalized.indexOf('MINT');
      final detectedVarietyIndex = normalized.indexOf('VARIETY');

      if (detectedYearIndex >= 0 &&
          detectedMintIndex >= 0 &&
          detectedVarietyIndex >= 0) {
        yearIndex = detectedYearIndex;
        mintIndex = detectedMintIndex;
        varietyIndex = detectedVarietyIndex;
        notesIndex = normalized.indexOf('NOTES');

        ownershipIndexes = [];
        ownershipLabels = [];

      final ownershipEnd =
    notesIndex >= 0 ? notesIndex : cells.length;
        for (var index = varietyIndex + 1;
            index < ownershipEnd;
            index++) {
          final label = cells[index].trim();
          if (_isOwnershipHeader(label)) {
            ownershipIndexes.add(index);
            ownershipLabels.add(label);
          }
        }

        continue;
      }

      final detectedSeries = _recognizedSeries(category, cells);

      if (yearIndex == null || mintIndex == null || varietyIndex == null) {
        if (detectedSeries != null) {
          currentSeries = detectedSeries;
        }
        continue;
      }

      final year = _cellAt(cells, yearIndex);
      final mint = _cellAt(cells, mintIndex);
      final variety = _cellAt(cells, varietyIndex);

      if (!_looksLikeCatalogYear(year)) {
        if (detectedSeries != null) {
          currentSeries = detectedSeries;
        }
        continue;
      }

      var status = 'Untracked';
      final locations = <String>[];

      for (var position = 0;
          position < ownershipIndexes.length;
          position++) {
        final columnIndex = ownershipIndexes[position];
        final value = _cellAt(cells, columnIndex).toUpperCase();
        final label = ownershipLabels[position];

        if (value == 'X') {
          status = 'Owned';
          locations.add(label);
        } else if (value == 'NEED') {
          if (status != 'Owned') {
            status = 'Need';
          }
          locations.add(label);
        }
      }

final notes =
    notesIndex >= 0 ? _cellAt(cells, notesIndex) : '';

      coins.add(
        ImportedCoin(
          category: category,
          series: currentSeries,
          year: year,
          mint: mint,
          variety: variety,
          status: status,
          storageLocation: locations.join(', '),
          grade: '',
          notes: notes,
        ),
      );
    }

    return coins;
  }

  String? _recognizedSeries(String category, List<String> cells) {
    for (final cell in cells.reversed) {
      final candidate = cell.trim();
      if (!_isSeriesText(candidate)) {
        continue;
      }

      var reference = CoinSeriesLibrary.find(candidate);
      if (reference != null) {
        return reference.series;
      }

      // Many workbook headings omit the denomination. Add the worksheet
      // category so names such as "Silver", "Barber", and "Liberty Seated"
      // can be matched to the correct denomination-specific series.
      reference = CoinSeriesLibrary.find('$candidate $category');
      if (reference != null) {
        return reference.series;
      }
    }

    return null;
  }

  bool _isOwnershipHeader(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'OGP') {
      return false;
    }

    return normalized.contains('BOOK') ||
        normalized.contains('BINDER') ||
        normalized.contains('ALBUM') ||
        normalized.contains('FOLDER') ||
        normalized.contains('SET');
  }

  bool _looksLikeCatalogYear(String value) {
    final normalized = value.trim();
    return RegExp(r'^\d{4}(?:-\d{2,4})?$').hasMatch(normalized);
  }

  bool _isSeriesText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.toUpperCase().startsWith('UNITED STATES') ||
        normalized.toUpperCase() == 'NOTES' ||
        normalized.toUpperCase() == 'NO BOOK') {
      return false;
    }

    // Series headings can legitimately begin with a denomination number,
    // such as "3 Cent Silver" or "20 Cent Liberty Seated".
    // _recognizedSeries() still validates the text against CoinSeriesLibrary,
    // so ordinary numeric/year cells will not become series names.
    return RegExp(r'[A-Za-z]').hasMatch(normalized);
  }

  String _cellAt(List<String> row, int index) {
    if (index < 0 || index >= row.length) {
      return '';
    }
    return row[index].trim();
  }

  String _cellText(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }
}
