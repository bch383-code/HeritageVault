import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/coin.dart';
import '../models/imported_coin.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _database;
  static String? _databasePath;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final heritageVaultDirectory = Directory(
      path.join(documentsDirectory.path, 'Heritage Vault'),
    );

    if (!await heritageVaultDirectory.exists()) {
      await heritageVaultDirectory.create(recursive: true);
    }

    _databasePath = path.join(
      heritageVaultDirectory.path,
      'heritage_vault.db',
    );

    return databaseFactory.openDatabase(
      _databasePath!,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, version) async {
          await _createManualCoinsTable(database);
          await _createImportedCoinsTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createImportedCoinsTable(database);
          }
        },
      ),
    );
  }

  static Future<void> _createManualCoinsTable(Database database) async {
    await database.execute('''
      CREATE TABLE coins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year TEXT NOT NULL,
        name TEXT NOT NULL,
        mint_mark TEXT NOT NULL DEFAULT '',
        country TEXT NOT NULL DEFAULT 'Unknown',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  static Future<void> _createImportedCoinsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imported_coins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        series TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        mint TEXT NOT NULL DEFAULT '',
        variety TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        storage_location TEXT NOT NULL DEFAULT '',
        grade TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS imported_coins_status_index
      ON imported_coins(status)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS imported_coins_category_index
      ON imported_coins(category)
    ''');
  }

  Future<String?> createDatabaseBackup({
    String reason = 'automatic',
  }) async {
    final database = await this.database;
    final sourcePath = _databasePath;

    if (sourcePath == null) {
      return null;
    }

    final backupDirectory = Directory(
      path.join(path.dirname(sourcePath), 'Backups'),
    );

    if (!await backupDirectory.exists()) {
      await backupDirectory.create(recursive: true);
    }

    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final timestamp = '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_'
        '${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}';
    final safeReason = reason.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final backupPath = path.join(
      backupDirectory.path,
      'heritage_vault_${timestamp}_$safeReason.db',
    );

    final escapedPath = backupPath.replaceAll("'", "''");
    await database.execute("VACUUM INTO '$escapedPath'");
    return backupPath;
  }

  Future<int> insertCoin(Coin coin) async {
    final database = await this.database;
    final coinMap = coin.toMap();
    coinMap.remove('id');

    return database.insert(
      'coins',
      coinMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Coin>> getCoins() async {
    final database = await this.database;
    final results = await database.query(
      'coins',
      orderBy: 'year ASC, name ASC',
    );
    return results.map(Coin.fromMap).toList();
  }

  Future<int> deleteCoin(int id) async {
    final database = await this.database;
    return database.delete(
      'coins',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> replaceImportedCoins(List<ImportedCoin> coins) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      await transaction.delete('imported_coins');
      final batch = transaction.batch();

      for (final coin in coins) {
        batch.insert('imported_coins', _importedCoinMap(coin));
      }

      await batch.commit(noResult: true);
      return coins.length;
    });
  }

  Future<List<ImportedCoin>> getImportedCoins({
    String? status,
    String? category,
    String searchText = '',
  }) async {
    final database = await this.database;
    final whereParts = <String>[];
    final whereArguments = <Object?>[];

    if (status != null && status.trim().isNotEmpty) {
      whereParts.add('status = ?');
      whereArguments.add(status);
    }

    if (category != null && category.trim().isNotEmpty) {
      whereParts.add('category = ?');
      whereArguments.add(category);
    }

    final search = searchText.trim();
    if (search.isNotEmpty) {
      whereParts.add('''
        (
          year LIKE ? OR mint LIKE ? OR variety LIKE ? OR
          series LIKE ? OR category LIKE ? OR
          storage_location LIKE ? OR notes LIKE ?
        )
      ''');
      final pattern = '%$search%';
      for (var index = 0; index < 7; index++) {
        whereArguments.add(pattern);
      }
    }

    final results = await database.query(
      'imported_coins',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArguments.isEmpty ? null : whereArguments,
      orderBy: 'category COLLATE NOCASE, year COLLATE NOCASE, '
          'mint COLLATE NOCASE, variety COLLATE NOCASE',
    );

    return results.map(_importedCoinFromMap).toList();
  }

  Future<List<String>> getImportedCategories() async {
    final database = await this.database;
    final results = await database.rawQuery('''
      SELECT DISTINCT category
      FROM imported_coins
      WHERE category <> ''
      ORDER BY category COLLATE NOCASE
    ''');

    return results.map((row) => row['category'] as String).toList();
  }

  Future<int> getImportedCoinCount({String? status}) async {
    final database = await this.database;
    final result = await database.rawQuery(
      status == null
          ? 'SELECT COUNT(*) AS total FROM imported_coins'
          : 'SELECT COUNT(*) AS total FROM imported_coins WHERE status = ?',
      status == null ? null : [status],
    );

    final value = result.first['total'];
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString()) ?? 0;
  }

  Future<int> updateImportedCoinStatus({
    required ImportedCoin coin,
    required String newStatus,
  }) async {
    final updatedCoin = ImportedCoin(
      category: coin.category,
      series: coin.series,
      year: coin.year,
      mint: coin.mint,
      variety: coin.variety,
      status: newStatus,
      storageLocation: coin.storageLocation,
      grade: coin.grade,
      notes: coin.notes,
    );

    return updateImportedCoin(
      originalCoin: coin,
      updatedCoin: updatedCoin,
    );
  }

  Future<int> updateImportedCoin({
    required ImportedCoin originalCoin,
    required ImportedCoin updatedCoin,
  }) async {
    final database = await this.database;

    return database.update(
      'imported_coins',
      _importedCoinMap(updatedCoin),
      where: '''
        category = ? AND series = ? AND year = ? AND mint = ? AND
        variety = ? AND status = ? AND storage_location = ? AND
        grade = ? AND notes = ?
      ''',
      whereArgs: [
        originalCoin.category,
        originalCoin.series,
        originalCoin.year,
        originalCoin.mint,
        originalCoin.variety,
        originalCoin.status,
        originalCoin.storageLocation,
        originalCoin.grade,
        originalCoin.notes,
      ],
    );
  }

  Map<String, Object?> _importedCoinMap(ImportedCoin coin) {
    return {
      'category': coin.category,
      'series': coin.series,
      'year': coin.year,
      'mint': coin.mint,
      'variety': coin.variety,
      'status': coin.status,
      'storage_location': coin.storageLocation,
      'grade': coin.grade,
      'notes': coin.notes,
    };
  }

  ImportedCoin _importedCoinFromMap(Map<String, Object?> row) {
    return ImportedCoin(
      category: row['category'] as String? ?? '',
      series: row['series'] as String? ?? '',
      year: row['year'] as String? ?? '',
      mint: row['mint'] as String? ?? '',
      variety: row['variety'] as String? ?? '',
      status: row['status'] as String? ?? '',
      storageLocation: row['storage_location'] as String? ?? '',
      grade: row['grade'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
    );
  }
  Future<CollectionSummary> getCollectionSummary() async {
    final database = await this.database;
    final rows = await database.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'Owned' THEN 1 ELSE 0 END) AS owned,
        SUM(CASE WHEN status = 'Need' THEN 1 ELSE 0 END) AS needed,
        SUM(CASE WHEN status = 'Untracked' THEN 1 ELSE 0 END) AS untracked,
        COUNT(DISTINCT category) AS categories
      FROM imported_coins
    ''');

    final row = rows.first;
    int number(String key) {
      final value = row[key];
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return CollectionSummary(
      total: number('total'),
      owned: number('owned'),
      needed: number('needed'),
      untracked: number('untracked'),
      categories: number('categories'),
    );
  }

  Future<List<CategoryProgress>> getCategoryProgress() async {
    final database = await this.database;
    final rows = await database.rawQuery('''
      SELECT
        category,
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'Owned' THEN 1 ELSE 0 END) AS owned,
        SUM(CASE WHEN status = 'Need' THEN 1 ELSE 0 END) AS needed,
        SUM(CASE WHEN status = 'Untracked' THEN 1 ELSE 0 END) AS untracked
      FROM imported_coins
      WHERE category <> ''
      GROUP BY category
      ORDER BY category COLLATE NOCASE
    ''');

    int number(Map<String, Object?> row, String key) {
      final value = row[key];
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return rows.map((row) {
      return CategoryProgress(
        category: row['category'] as String? ?? '',
        total: number(row, 'total'),
        owned: number(row, 'owned'),
        needed: number(row, 'needed'),
        untracked: number(row, 'untracked'),
      );
    }).toList();
  }

}


class CollectionSummary {
  final int total;
  final int owned;
  final int needed;
  final int untracked;
  final int categories;

  const CollectionSummary({
    required this.total,
    required this.owned,
    required this.needed,
    required this.untracked,
    required this.categories,
  });

  double get completionRate {
    final tracked = owned + needed;
    if (tracked == 0) return 0;
    return owned / tracked;
  }
}

class CategoryProgress {
  final String category;
  final int total;
  final int owned;
  final int needed;
  final int untracked;

  const CategoryProgress({
    required this.category,
    required this.total,
    required this.owned,
    required this.needed,
    required this.untracked,
  });

  double get completionRate {
    final tracked = owned + needed;
    if (tracked == 0) return 0;
    return owned / tracked;
  }
}
