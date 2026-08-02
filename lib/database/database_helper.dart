import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/coin.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();

    final databasePath = path.join(
      documentsDirectory.path,
      'Heritage Vault',
      'heritage_vault.db',
    );

    return databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
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
        },
      ),
    );
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
}