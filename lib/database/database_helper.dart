import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/coin.dart';
import '../models/imported_coin.dart';
import '../models/postcard.dart';
import '../models/valuable.dart';
import '../models/antique.dart';
import '../models/vault_photo.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/custom_collection.dart';
import '../models/custom_collection_item.dart';
import '../models/detected_face_record.dart';
import '../models/family_person.dart';
import '../models/sports_card.dart';

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
        version: 23,
        onCreate: (database, version) async {
          await _createManualCoinsTable(database);
          await _createImportedCoinsTable(database);
          await _createStorageLocationsTable(database);
          await _createPostcardsTable(database);
          await _createValuablesTables(database);
          await _createAntiquesTables(database);
          await _createPhotoLibraryTables(database);
          await _createPhotoCatalogMetadataTable(database);
          await _createPhotoFacesTable(database);
          await _createPhotoFaceScanStateTable(database);
          await _createPhotoMetadataImportStateTable(database);
          await _createPhotoFingerprintTable(database);
          await _createCustomCollectionsTable(database);
          await _createCustomCollectionItemsTable(database);
          await _createFamilyPeopleTable(database);
          await _createFamilyRelationshipsTables(database);
          await _createGedcomImportTables(database);
          await _createFamilyPersonLinksTable(database);
          await _createSportsCardsTable(database);
          await _createSportsCardCatalogTables(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createImportedCoinsTable(database);
          }
          if (oldVersion < 3) {
            await _upgradeToVersion3(database);
          }
          if (oldVersion < 4) {
            await _createPostcardsTable(database);
          }
          if (oldVersion < 5) {
            await _createValuablesTables(database);
          }
          if (oldVersion < 6) {
            await _createAntiquesTables(database);
          }
          if (oldVersion < 7) {
            await _createPhotoLibraryTables(database);
          }
          if (oldVersion < 8) {
            await database.execute(
              "ALTER TABLE indexed_photos ADD COLUMN relative_folder TEXT NOT NULL DEFAULT ''",
            );
            await database.execute('''
              CREATE INDEX IF NOT EXISTS indexed_photos_relative_folder_index
              ON indexed_photos(relative_folder)
            ''');
          }
          if (oldVersion < 9) {
            await _createPhotoCatalogMetadataTable(database);
          }
          if (oldVersion < 10) {
            await _createPhotoFacesTable(database);
          }
          if (oldVersion < 11) {
            await _createPhotoFaceScanStateTable(database);
          }
          if (oldVersion < 12) {
            await _createPhotoMetadataImportStateTable(database);
          }
          if (oldVersion < 13) {
            await _createCustomCollectionsTable(database);
          }
          if (oldVersion < 14) {
            await _createCustomCollectionItemsTable(database);
          }
          if (oldVersion < 15) {
            await _createFamilyPeopleTable(database);
          }
          if (oldVersion < 16) {
            await _createFamilyRelationshipsTables(database);
          }
          if (oldVersion < 17) {
            await _createGedcomImportTables(database);
          }
          if (oldVersion < 18) {
            await _createFamilyPersonLinksTable(database);
          }
          if (oldVersion < 19) {
            await _createSportsCardsTable(database);
          }
          if (oldVersion < 20) {
            await _createSportsCardCatalogTables(database);
            await _migrateLegacySportsCards(database);
          }
          if (oldVersion < 21) {
            await database.execute(
              "ALTER TABLE sports_card_collection "
              "ADD COLUMN value_source TEXT NOT NULL DEFAULT ''",
            );
            await database.execute(
              "ALTER TABLE sports_card_collection "
              "ADD COLUMN value_updated_at_milliseconds INTEGER NOT NULL DEFAULT 0",
            );
          }
          if (oldVersion < 22) {
            await database.execute(
              "ALTER TABLE sports_card_collection "
              "ADD COLUMN image_path TEXT NOT NULL DEFAULT ''",
            );
          }
          if (oldVersion < 23) {
            await _createPhotoFingerprintTable(database);
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
        quantity_owned INTEGER NOT NULL DEFAULT 0,
        storage_location TEXT NOT NULL DEFAULT '',
        grade TEXT NOT NULL DEFAULT '',
        value REAL,
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

  static Future<void> _upgradeToVersion3(Database database) async {
    await database.execute(
      'ALTER TABLE imported_coins ADD COLUMN quantity_owned INTEGER NOT NULL DEFAULT 0',
    );
    await database.execute(
      'ALTER TABLE imported_coins ADD COLUMN value REAL',
    );
    await _createStorageLocationsTable(database);
  }

  static Future<void> _createStorageLocationsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS storage_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        brand TEXT NOT NULL DEFAULT '',
        color TEXT NOT NULL DEFAULT '',
        number TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  static Future<void> _createPostcardsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS postcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        acquired_from TEXT NOT NULL DEFAULT '',
        purchase_price REAL,
        estimated_value REAL,
        front_image_path TEXT NOT NULL DEFAULT '',
        back_image_path TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<int> insertPostcard(Postcard postcard) async {
    final database = await this.database;
    final map = postcard.toMap();
    map.remove('id');

    return database.insert(
      'postcards',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updatePostcard(Postcard postcard) async {
    final database = await this.database;
    final id = postcard.id;
    if (id == null) {
      throw ArgumentError('A postcard ID is required for updates.');
    }

    final map = postcard.toMap();
    map.remove('id');

    return database.update(
      'postcards',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePostcard(int id) async {
    final database = await this.database;
    return database.delete(
      'postcards',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Postcard>> getPostcards() async {
    final database = await this.database;
    final rows = await database.query(
      'postcards',
      orderBy: '''
        CASE WHEN year = '' THEN 1 ELSE 0 END,
        year COLLATE NOCASE,
        title COLLATE NOCASE
      ''',
    );

    return rows.map(Postcard.fromMap).toList();
  }

  static Future<void> _createValuablesTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS valuables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        acquired_from TEXT NOT NULL DEFAULT '',
        purchase_price REAL,
        estimated_value REAL,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS valuable_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        valuable_id INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<int> insertValuable(Valuable valuable) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      final map = valuable.toMap();
      map.remove('id');

      final id = await transaction.insert('valuables', map);

      for (var index = 0; index < valuable.imagePaths.length; index++) {
        await transaction.insert(
          'valuable_images',
          {
            'valuable_id': id,
            'image_path': valuable.imagePaths[index],
            'sort_order': index,
          },
        );
      }

      return id;
    });
  }

  Future<int> updateValuable(Valuable valuable) async {
    final database = await this.database;
    final id = valuable.id;
    if (id == null) {
      throw ArgumentError('A valuable ID is required for updates.');
    }

    return database.transaction((transaction) async {
      final map = valuable.toMap();
      map.remove('id');

      final changed = await transaction.update(
        'valuables',
        map,
        where: 'id = ?',
        whereArgs: [id],
      );

      await transaction.delete(
        'valuable_images',
        where: 'valuable_id = ?',
        whereArgs: [id],
      );

      for (var index = 0; index < valuable.imagePaths.length; index++) {
        await transaction.insert(
          'valuable_images',
          {
            'valuable_id': id,
            'image_path': valuable.imagePaths[index],
            'sort_order': index,
          },
        );
      }

      return changed;
    });
  }

  Future<int> deleteValuable(int id) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      await transaction.delete(
        'valuable_images',
        where: 'valuable_id = ?',
        whereArgs: [id],
      );

      return transaction.delete(
        'valuables',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Valuable>> getValuables() async {
    final database = await this.database;
    final rows = await database.query(
      'valuables',
      orderBy: '''
        CASE WHEN year = '' THEN 1 ELSE 0 END,
        year COLLATE NOCASE,
        title COLLATE NOCASE
      ''',
    );

    final result = <Valuable>[];

    for (final row in rows) {
      final id = row['id'] as int?;
      final imageRows = id == null
          ? <Map<String, Object?>>[]
          : await database.query(
              'valuable_images',
              where: 'valuable_id = ?',
              whereArgs: [id],
              orderBy: 'sort_order ASC, id ASC',
            );

      final imagePaths = imageRows
          .map((imageRow) => imageRow['image_path'] as String? ?? '')
          .where((value) => value.isNotEmpty)
          .toList();

      result.add(
        Valuable.fromMap(
          row,
          imagePaths: imagePaths,
        ),
      );
    }

    return result;
  }

  static Future<void> _createAntiquesTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS antiques (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        acquired_from TEXT NOT NULL DEFAULT '',
        purchase_price REAL,
        estimated_value REAL,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS antique_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        antique_id INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<int> insertAntique(Antique antique) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      final map = antique.toMap();
      map.remove('id');

      final id = await transaction.insert('antiques', map);

      for (var index = 0; index < antique.imagePaths.length; index++) {
        await transaction.insert(
          'antique_images',
          {
            'antique_id': id,
            'image_path': antique.imagePaths[index],
            'sort_order': index,
          },
        );
      }

      return id;
    });
  }

  Future<int> updateAntique(Antique antique) async {
    final database = await this.database;
    final id = antique.id;
    if (id == null) {
      throw ArgumentError('An antique ID is required for updates.');
    }

    return database.transaction((transaction) async {
      final map = antique.toMap();
      map.remove('id');

      final changed = await transaction.update(
        'antiques',
        map,
        where: 'id = ?',
        whereArgs: [id],
      );

      await transaction.delete(
        'antique_images',
        where: 'antique_id = ?',
        whereArgs: [id],
      );

      for (var index = 0; index < antique.imagePaths.length; index++) {
        await transaction.insert(
          'antique_images',
          {
            'antique_id': id,
            'image_path': antique.imagePaths[index],
            'sort_order': index,
          },
        );
      }

      return changed;
    });
  }

  Future<int> deleteAntique(int id) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      await transaction.delete(
        'antique_images',
        where: 'antique_id = ?',
        whereArgs: [id],
      );

      return transaction.delete(
        'antiques',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Antique>> getAntiques() async {
    final database = await this.database;
    final rows = await database.query(
      'antiques',
      orderBy: '''
        CASE WHEN year = '' THEN 1 ELSE 0 END,
        year COLLATE NOCASE,
        title COLLATE NOCASE
      ''',
    );

    final result = <Antique>[];

    for (final row in rows) {
      final id = row['id'] as int?;
      final imageRows = id == null
          ? <Map<String, Object?>>[]
          : await database.query(
              'antique_images',
              where: 'antique_id = ?',
              whereArgs: [id],
              orderBy: 'sort_order ASC, id ASC',
            );

      final imagePaths = imageRows
          .map((imageRow) => imageRow['image_path'] as String? ?? '')
          .where((value) => value.isNotEmpty)
          .toList();

      result.add(
        Antique.fromMap(
          row,
          imagePaths: imagePaths,
        ),
      );
    }

    return result;
  }


  static Future<void> _createPhotoLibraryTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS indexed_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL UNIQUE,
        file_name TEXT NOT NULL DEFAULT '',
        extension TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        relative_folder TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS indexed_photos_file_name_index
      ON indexed_photos(file_name)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS indexed_photos_relative_folder_index
      ON indexed_photos(relative_folder)
    ''');
  }

  Future<String?> getSetting(String key) async {
    final database = await this.database;
    final rows = await database.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final value = rows.first['setting_value'] as String? ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> setSetting(String key, String value) async {
    final database = await this.database;
    await database.insert(
      'app_settings',
      {
        'setting_key': key,
        'setting_value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> replaceIndexedPhotos(List<VaultPhoto> photos) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      await transaction.delete('indexed_photos');
      final batch = transaction.batch();

      for (final photo in photos) {
        final map = photo.toMap();
        map.remove('id');
        batch.insert(
          'indexed_photos',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      return photos.length;
    });
  }

  Future<List<VaultPhoto>> getIndexedPhotos() async {
    final database = await this.database;
    final rows = await database.query(
      'indexed_photos',
      orderBy: 'file_name COLLATE NOCASE, file_path COLLATE NOCASE',
    );
    return rows.map(VaultPhoto.fromMap).toList();
  }


  static Future<void> _createPhotoFingerprintTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_fingerprints (
        file_path TEXT PRIMARY KEY,
        file_size INTEGER NOT NULL DEFAULT 0,
        modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        hash_hex TEXT NOT NULL DEFAULT '',
        average_r INTEGER NOT NULL DEFAULT 0,
        average_g INTEGER NOT NULL DEFAULT 0,
        average_b INTEGER NOT NULL DEFAULT 0,
        analyzed_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<Map<String, Map<String, Object?>>> getPhotoFingerprints() async {
    final database = await this.database;
    final rows = await database.query('photo_fingerprints');
    return {
      for (final row in rows)
        row['file_path'] as String? ?? '': Map<String, Object?>.from(row),
    };
  }

  Future<void> savePhotoFingerprint({
    required String filePath,
    required int fileSize,
    required int modifiedMilliseconds,
    required String hashHex,
    required int averageR,
    required int averageG,
    required int averageB,
  }) async {
    final database = await this.database;
    await database.insert(
      'photo_fingerprints',
      {
        'file_path': filePath,
        'file_size': fileSize,
        'modified_milliseconds': modifiedMilliseconds,
        'hash_hex': hashHex,
        'average_r': averageR,
        'average_g': averageG,
        'average_b': averageB,
        'analyzed_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePhotoFingerprintsNotIn(Iterable<String> filePaths) async {
    final database = await this.database;
    final keep = filePaths.toSet();
    final rows = await database.query(
      'photo_fingerprints',
      columns: ['file_path'],
    );
    final batch = database.batch();
    for (final row in rows) {
      final filePath = row['file_path'] as String? ?? '';
      if (!keep.contains(filePath)) {
        batch.delete(
          'photo_fingerprints',
          where: 'file_path = ?',
          whereArgs: [filePath],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _createPhotoCatalogMetadataTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_catalog_metadata (
        file_path TEXT PRIMARY KEY,
        people_json TEXT NOT NULL DEFAULT '[]',
        tags_json TEXT NOT NULL DEFAULT '[]',
        approximate_date TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<PhotoCatalogMetadata> getPhotoCatalogMetadata(
    String filePath,
  ) async {
    final database = await this.database;
    final rows = await database.query(
      'photo_catalog_metadata',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );

    if (rows.isEmpty) {
      return PhotoCatalogMetadata(filePath: filePath);
    }

    return PhotoCatalogMetadata.fromMap(rows.first);
  }

  Future<List<PhotoCatalogMetadata>> getAllPhotoCatalogMetadata() async {
    final database = await this.database;
    final rows = await database.query('photo_catalog_metadata');
    return rows.map(PhotoCatalogMetadata.fromMap).toList();
  }

  Future<void> savePhotoCatalogMetadata(
    PhotoCatalogMetadata metadata,
  ) async {
    final database = await this.database;
    await database.insert(
      'photo_catalog_metadata',
      metadata.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }


  static Future<void> _createPhotoFacesTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_faces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        photo_file_path TEXT NOT NULL,
        face_index INTEGER NOT NULL DEFAULT 0,
        box_left REAL NOT NULL DEFAULT 0,
        box_top REAL NOT NULL DEFAULT 0,
        box_width REAL NOT NULL DEFAULT 0,
        box_height REAL NOT NULL DEFAULT 0,
        detection_score REAL NOT NULL DEFAULT 0,
        embedding_json TEXT NOT NULL DEFAULT '[]',
        thumbnail_path TEXT NOT NULL DEFAULT '',
        person_name TEXT NOT NULL DEFAULT '',
        confirmed INTEGER NOT NULL DEFAULT 0,
        UNIQUE(photo_file_path, face_index)
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS photo_faces_photo_path_index
      ON photo_faces(photo_file_path)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS photo_faces_person_name_index
      ON photo_faces(person_name)
    ''');
  }

  Future<void> replaceFacesForPhotos(
    List<String> photoPaths,
    List<DetectedFaceRecord> faces,
  ) async {
    final database = await this.database;

    await database.transaction((transaction) async {
      for (final photoPath in photoPaths) {
        await transaction.delete(
          'photo_faces',
          where: 'photo_file_path = ?',
          whereArgs: [photoPath],
        );
      }

      final batch = transaction.batch();
      for (final face in faces) {
        final map = face.toMap();
        map.remove('id');
        batch.insert(
          'photo_faces',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<List<DetectedFaceRecord>> getFacesForPhotoPaths(
    List<String> photoPaths,
  ) async {
    if (photoPaths.isEmpty) return const [];

    final database = await this.database;
    final placeholders = List.filled(photoPaths.length, '?').join(',');

    final rows = await database.rawQuery(
      '''
      SELECT *
      FROM photo_faces
      WHERE photo_file_path IN ($placeholders)
      ORDER BY photo_file_path, face_index
      ''',
      photoPaths,
    );

    return rows.map(DetectedFaceRecord.fromMap).toList();
  }

  Future<void> confirmFaceGroup({
    required List<int> faceIds,
    required String personName,
  }) async {
    if (faceIds.isEmpty) return;

    final database = await this.database;
    final placeholders = List.filled(faceIds.length, '?').join(',');

    await database.rawUpdate(
      '''
      UPDATE photo_faces
      SET person_name = ?, confirmed = 1
      WHERE id IN ($placeholders)
      ''',
      [personName, ...faceIds],
    );
  }


  Future<List<DetectedFaceRecord>> getConfirmedFaces() async {
    final database = await this.database;
    final rows = await database.query(
      'photo_faces',
      where: "confirmed = 1 AND person_name <> ''",
      orderBy: 'person_name COLLATE NOCASE, photo_file_path, face_index',
    );

    return rows.map(DetectedFaceRecord.fromMap).toList();
  }

  Future<int> getUnconfirmedFaceCount() async {
    final database = await this.database;
    final rows = await database.rawQuery('''
      SELECT COUNT(*) AS total
      FROM photo_faces
      WHERE confirmed = 0
    ''');

    return _mapInt(rows.first['total']);
  }

  Future<List<DetectedFaceRecord>> getUnconfirmedFaces() async {
    final database = await this.database;
    final rows = await database.query(
      'photo_faces',
      where: 'confirmed = 0',
      orderBy: 'photo_file_path, face_index',
    );

    return rows.map(DetectedFaceRecord.fromMap).toList();
  }

  Future<void> renameConfirmedPerson({
    required String oldName,
    required String newName,
  }) async {
    final database = await this.database;
    await database.update(
      'photo_faces',
      {'person_name': newName.trim()},
      where: 'confirmed = 1 AND person_name = ?',
      whereArgs: [oldName],
    );

    final rows = await database.query('photo_catalog_metadata');
    for (final row in rows) {
      final metadata = PhotoCatalogMetadata.fromMap(row);
      if (!metadata.people.contains(oldName)) continue;

      final updatedPeople = metadata.people
          .map((person) => person == oldName ? newName.trim() : person)
          .toSet()
          .toList();

      await database.insert(
        'photo_catalog_metadata',
        PhotoCatalogMetadata(
          filePath: metadata.filePath,
          people: updatedPeople,
          tags: metadata.tags,
          approximateDate: metadata.approximateDate,
          location: metadata.location,
          description: metadata.description,
          notes: metadata.notes,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }


  static Future<void> _createPhotoFaceScanStateTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_face_scan_state (
        file_path TEXT PRIMARY KEY,
        modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        scanned_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        face_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<Map<String, int>> getPhotoFaceScanVersions() async {
    final database = await this.database;
    final rows = await database.query(
      'photo_face_scan_state',
      columns: ['file_path', 'modified_milliseconds'],
    );

    return {
      for (final row in rows)
        row['file_path'] as String? ?? '':
            _mapInt(row['modified_milliseconds']),
    };
  }

  Future<void> markPhotoFaceScanned({
    required VaultPhoto photo,
    required int faceCount,
  }) async {
    final database = await this.database;
    await database.insert(
      'photo_face_scan_state',
      {
        'file_path': photo.filePath,
        'modified_milliseconds': photo.modifiedMilliseconds,
        'scanned_at_milliseconds':
            DateTime.now().millisecondsSinceEpoch,
        'face_count': faceCount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _createPhotoMetadataImportStateTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_metadata_import_state (
        file_path TEXT PRIMARY KEY,
        modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        imported_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<Map<String, int>> getPhotoMetadataImportVersions() async {
    final database = await this.database;
    final rows = await database.query(
      'photo_metadata_import_state',
      columns: ['file_path', 'modified_milliseconds'],
    );

    return {
      for (final row in rows)
        row['file_path'] as String? ?? '':
            _mapInt(row['modified_milliseconds']),
    };
  }

  Future<void> markPhotoMetadataImported(
    VaultPhoto photo,
  ) async {
    final database = await this.database;
    await database.insert(
      'photo_metadata_import_state',
      {
        'file_path': photo.filePath,
        'modified_milliseconds': photo.modifiedMilliseconds,
        'imported_at_milliseconds':
            DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _createCustomCollectionsTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS custom_collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon_key TEXT NOT NULL DEFAULT 'inventory',
        enabled_fields_json TEXT NOT NULL DEFAULT '[]',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS custom_collections_name_index
      ON custom_collections(name COLLATE NOCASE)
    ''');
  }

  Future<List<CustomCollection>> getCustomCollections() async {
    final database = await this.database;
    final rows = await database.query(
      'custom_collections',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(CustomCollection.fromMap).toList();
  }

  Future<int> insertCustomCollection(CustomCollection collection) async {
    final database = await this.database;
    final map = collection.toMap();
    map.remove('id');
    return database.insert('custom_collections', map,
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> updateCustomCollection(CustomCollection collection) async {
    final id = collection.id;
    if (id == null) throw ArgumentError('A collection ID is required.');
    final database = await this.database;
    final map = collection.toMap();
    map.remove('id');
    return database.update('custom_collections', map,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomCollection(int id) async {
    final database = await this.database;
    return database.delete('custom_collections',
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _createCustomCollectionItemsTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS custom_collection_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        collection_id INTEGER NOT NULL,
        values_json TEXT NOT NULL DEFAULT '{}',
        photo_paths_json TEXT NOT NULL DEFAULT '[]',
        document_paths_json TEXT NOT NULL DEFAULT '[]',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS custom_collection_items_collection_index
      ON custom_collection_items(collection_id)
    ''');
  }

  Future<List<CustomCollectionItem>> getCustomCollectionItems(
    int collectionId,
  ) async {
    final database = await this.database;
    final rows = await database.query(
      'custom_collection_items',
      where: 'collection_id = ?',
      whereArgs: [collectionId],
      orderBy: 'updated_at_milliseconds DESC, id DESC',
    );
    return rows.map(CustomCollectionItem.fromMap).toList();
  }

  Future<int> insertCustomCollectionItem(
    CustomCollectionItem item,
  ) async {
    final database = await this.database;
    final map = item.toMap();
    map.remove('id');
    return database.insert('custom_collection_items', map);
  }

  Future<int> updateCustomCollectionItem(
    CustomCollectionItem item,
  ) async {
    final id = item.id;
    if (id == null) {
      throw ArgumentError('An item ID is required.');
    }
    final database = await this.database;
    final map = item.toMap();
    map.remove('id');
    return database.update(
      'custom_collection_items',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> moveCustomCollectionItem({
    required int itemId,
    required int destinationCollectionId,
  }) async {
    final database = await this.database;
    return database.update(
      'custom_collection_items',
      {
        'collection_id': destinationCollectionId,
        'updated_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<int> deleteCustomCollectionItem(int id) async {
    final database = await this.database;
    return database.delete(
      'custom_collection_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> _createFamilyPeopleTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS family_people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL DEFAULT '',
        middle_name TEXT NOT NULL DEFAULT '',
        last_name TEXT NOT NULL DEFAULT '',
        birth_name TEXT NOT NULL DEFAULT '',
        sex TEXT NOT NULL DEFAULT '',
        birth_date TEXT NOT NULL DEFAULT '',
        birth_place TEXT NOT NULL DEFAULT '',
        death_date TEXT NOT NULL DEFAULT '',
        death_place TEXT NOT NULL DEFAULT '',
        biography TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        profile_photo_path TEXT NOT NULL DEFAULT '',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<int> insertFamilyPerson(FamilyPerson person) async {
    final database = await this.database;
    final map = person.toMap()..remove('id');
    return database.insert('family_people', map);
  }

  Future<int> updateFamilyPerson(FamilyPerson person) async {
    if (person.id == null) throw ArgumentError('A family person ID is required.');
    final database = await this.database;
    final map = person.toMap()..remove('id');
    return database.update('family_people', map, where: 'id = ?', whereArgs: [person.id]);
  }

  Future<FamilyPerson?> getFamilyPerson(int id) async {
    final database = await this.database;
    final rows = await database.query('family_people', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : FamilyPerson.fromMap(rows.first);
  }

  Future<List<FamilyPerson>> getFamilyPeople({String searchText = ''}) async {
    final database = await this.database;
    final search = searchText.trim();
    final rows = await database.query(
      'family_people',
      where: search.isEmpty ? null : 'first_name LIKE ? OR middle_name LIKE ? OR last_name LIKE ? OR birth_name LIKE ? OR birth_place LIKE ? OR death_place LIKE ?',
      whereArgs: search.isEmpty ? null : List<Object?>.filled(6, '%$search%'),
      orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE, middle_name COLLATE NOCASE',
    );
    return rows.map(FamilyPerson.fromMap).toList();
  }

  Future<int> deleteFamilyPerson(int id) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      await transaction.delete(
        'family_person_links',
        where: 'person_id = ?',
        whereArgs: [id],
      );

      return transaction.delete(
        'family_people',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  static Future<void> _createFamilyRelationshipsTables(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS family_parent_child (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER NOT NULL,
        child_id INTEGER NOT NULL,
        parent_role TEXT NOT NULL DEFAULT 'Parent',
        UNIQUE(parent_id, child_id)
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS family_parent_child_parent_index
      ON family_parent_child(parent_id)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS family_parent_child_child_index
      ON family_parent_child(child_id)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS family_spouses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person1_id INTEGER NOT NULL,
        person2_id INTEGER NOT NULL,
        UNIQUE(person1_id, person2_id)
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS family_spouses_person1_index
      ON family_spouses(person1_id)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS family_spouses_person2_index
      ON family_spouses(person2_id)
    ''');
  }

  Future<void> addFamilyParentChild({
    required int parentId,
    required int childId,
    required String parentRole,
  }) async {
    if (parentId == childId) {
      throw ArgumentError('A person cannot be their own parent.');
    }

    final database = await this.database;
    await database.insert(
      'family_parent_child',
      {
        'parent_id': parentId,
        'child_id': childId,
        'parent_role': parentRole,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addFamilySpouse({
    required int person1Id,
    required int person2Id,
  }) async {
    if (person1Id == person2Id) {
      throw ArgumentError('A person cannot be their own spouse.');
    }

    final low = person1Id < person2Id ? person1Id : person2Id;
    final high = person1Id < person2Id ? person2Id : person1Id;

    final database = await this.database;
    await database.insert(
      'family_spouses',
      {
        'person1_id': low,
        'person2_id': high,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<FamilyPerson>> getFamilyParents(int childId) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT p.*
      FROM family_people p
      INNER JOIN family_parent_child r ON r.parent_id = p.id
      WHERE r.child_id = ?
      ORDER BY
        CASE r.parent_role
          WHEN 'Father' THEN 0
          WHEN 'Mother' THEN 1
          ELSE 2
        END,
        p.last_name COLLATE NOCASE,
        p.first_name COLLATE NOCASE
      ''',
      [childId],
    );

    return rows.map(FamilyPerson.fromMap).toList();
  }

  Future<List<FamilyPerson>> getFamilyChildren(int parentId) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT p.*
      FROM family_people p
      INNER JOIN family_parent_child r ON r.child_id = p.id
      WHERE r.parent_id = ?
      ORDER BY p.last_name COLLATE NOCASE, p.first_name COLLATE NOCASE
      ''',
      [parentId],
    );

    return rows.map(FamilyPerson.fromMap).toList();
  }

  Future<List<FamilyPerson>> getFamilySpouses(int personId) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT p.*
      FROM family_people p
      INNER JOIN family_spouses s
        ON (
          (s.person1_id = ? AND p.id = s.person2_id)
          OR
          (s.person2_id = ? AND p.id = s.person1_id)
        )
      ORDER BY p.last_name COLLATE NOCASE, p.first_name COLLATE NOCASE
      ''',
      [personId, personId],
    );

    return rows.map(FamilyPerson.fromMap).toList();
  }

  Future<String> getFamilyParentRole({
    required int parentId,
    required int childId,
  }) async {
    final database = await this.database;
    final rows = await database.query(
      'family_parent_child',
      columns: ['parent_role'],
      where: 'parent_id = ? AND child_id = ?',
      whereArgs: [parentId, childId],
      limit: 1,
    );

    if (rows.isEmpty) return 'Parent';
    return rows.first['parent_role'] as String? ?? 'Parent';
  }

  Future<void> removeFamilyParentChild({
    required int parentId,
    required int childId,
  }) async {
    final database = await this.database;
    await database.delete(
      'family_parent_child',
      where: 'parent_id = ? AND child_id = ?',
      whereArgs: [parentId, childId],
    );
  }

  Future<void> removeFamilySpouse({
    required int person1Id,
    required int person2Id,
  }) async {
    final low = person1Id < person2Id ? person1Id : person2Id;
    final high = person1Id < person2Id ? person2Id : person1Id;

    final database = await this.database;
    await database.delete(
      'family_spouses',
      where: 'person1_id = ? AND person2_id = ?',
      whereArgs: [low, high],
    );
  }


  static Future<void> _createFamilyPersonLinksTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS family_person_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        item_key TEXT NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        UNIQUE(person_id, item_type, item_key)
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS family_person_links_person_index
      ON family_person_links(person_id)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS family_person_links_item_index
      ON family_person_links(item_type, item_key)
    ''');
  }

  Future<void> linkFamilyPersonToItem({
    required int personId,
    required String itemType,
    required String itemKey,
  }) async {
    final cleanType = itemType.trim().toLowerCase();
    final cleanKey = itemKey.trim();

    if (cleanType.isEmpty) {
      throw ArgumentError('An item type is required.');
    }
    if (cleanKey.isEmpty) {
      throw ArgumentError('An item key is required.');
    }

    final database = await this.database;
    await database.insert(
      'family_person_links',
      {
        'person_id': personId,
        'item_type': cleanType,
        'item_key': cleanKey,
        'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> unlinkFamilyPersonFromItem({
    required int personId,
    required String itemType,
    required String itemKey,
  }) async {
    final database = await this.database;
    await database.delete(
      'family_person_links',
      where: 'person_id = ? AND item_type = ? AND item_key = ?',
      whereArgs: [personId, itemType.trim().toLowerCase(), itemKey.trim()],
    );
  }

  Future<void> replaceFamilyPeopleForItem({
    required String itemType,
    required String itemKey,
    required Iterable<int> personIds,
  }) async {
    final cleanType = itemType.trim().toLowerCase();
    final cleanKey = itemKey.trim();

    if (cleanType.isEmpty) {
      throw ArgumentError('An item type is required.');
    }
    if (cleanKey.isEmpty) {
      throw ArgumentError('An item key is required.');
    }

    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'family_person_links',
        where: 'item_type = ? AND item_key = ?',
        whereArgs: [cleanType, cleanKey],
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final personId in personIds.toSet()) {
        await transaction.insert(
          'family_person_links',
          {
            'person_id': personId,
            'item_type': cleanType,
            'item_key': cleanKey,
            'created_at_milliseconds': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<int>> getFamilyPersonIdsForItem({
    required String itemType,
    required String itemKey,
  }) async {
    final database = await this.database;
    final rows = await database.query(
      'family_person_links',
      columns: ['person_id'],
      where: 'item_type = ? AND item_key = ?',
      whereArgs: [itemType.trim().toLowerCase(), itemKey.trim()],
      orderBy: 'created_at_milliseconds ASC, id ASC',
    );

    return rows.map((row) => _mapInt(row['person_id'])).toList();
  }

  Future<List<FamilyPerson>> getFamilyPeopleForItem({
    required String itemType,
    required String itemKey,
  }) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT p.*
      FROM family_people p
      INNER JOIN family_person_links l ON l.person_id = p.id
      WHERE l.item_type = ? AND l.item_key = ?
      ORDER BY p.last_name COLLATE NOCASE,
               p.first_name COLLATE NOCASE,
               p.middle_name COLLATE NOCASE
      ''',
      [itemType.trim().toLowerCase(), itemKey.trim()],
    );

    return rows.map(FamilyPerson.fromMap).toList();
  }

  Future<List<String>> getItemKeysForFamilyPeople({
    required Iterable<int> personIds,
    required String itemType,
  }) async {
    final ids = personIds.toSet().toList();
    if (ids.isEmpty) return const [];

    final cleanType = itemType.trim().toLowerCase();
    final database = await this.database;
    final placeholders = List.filled(ids.length, '?').join(',');

    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT item_key
      FROM family_person_links
      WHERE item_type = ?
        AND person_id IN ($placeholders)
      ORDER BY item_key COLLATE NOCASE
      ''',
      [cleanType, ...ids],
    );

    return rows
        .map((row) => row['item_key'] as String? ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<List<String>> getPhotoPathsForFamilyPeople(
    Iterable<int> personIds,
  ) {
    return getItemKeysForFamilyPeople(
      personIds: personIds,
      itemType: 'photo',
    );
  }

  Future<void> linkFamilyPersonToPhoto({
    required int personId,
    required String photoFilePath,
  }) {
    return linkFamilyPersonToItem(
      personId: personId,
      itemType: 'photo',
      itemKey: photoFilePath,
    );
  }

  Future<void> replaceFamilyPeopleForPhoto({
    required String photoFilePath,
    required Iterable<int> personIds,
  }) {
    return replaceFamilyPeopleForItem(
      itemType: 'photo',
      itemKey: photoFilePath,
      personIds: personIds,
    );
  }

  Future<List<FamilyPerson>> getFamilyPeopleForPhoto(
    String photoFilePath,
  ) {
    return getFamilyPeopleForItem(
      itemType: 'photo',
      itemKey: photoFilePath,
    );
  }


  static Future<void> _createGedcomImportTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS gedcom_imports (
        import_key TEXT PRIMARY KEY,
        file_name TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        individual_count INTEGER NOT NULL DEFAULT 0,
        family_count INTEGER NOT NULL DEFAULT 0,
        imported_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS gedcom_person_links (
        import_key TEXT NOT NULL,
        gedcom_xref TEXT NOT NULL,
        person_id INTEGER NOT NULL,
        PRIMARY KEY(import_key, gedcom_xref)
      )
    ''');
  }

  Future<Map<String, int>> getGedcomPersonLinks(String importKey) async {
    final database = await this.database;
    final rows = await database.query(
      'gedcom_person_links',
      columns: ['gedcom_xref', 'person_id'],
      where: 'import_key = ?',
      whereArgs: [importKey],
    );

    return {
      for (final row in rows)
        row['gedcom_xref'] as String? ?? '': _mapInt(row['person_id']),
    };
  }

  Future<void> saveGedcomPersonLinks({
    required String importKey,
    required Map<String, int> links,
  }) async {
    if (links.isEmpty) return;
    final database = await this.database;

    await database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final entry in links.entries) {
        batch.insert(
          'gedcom_person_links',
          {
            'import_key': importKey,
            'gedcom_xref': entry.key,
            'person_id': entry.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveGedcomImportRecord({
    required String importKey,
    required String fileName,
    required int fileSize,
    required int modifiedMilliseconds,
    required int individualCount,
    required int familyCount,
  }) async {
    final database = await this.database;
    await database.insert(
      'gedcom_imports',
      {
        'import_key': importKey,
        'file_name': fileName,
        'file_size': fileSize,
        'modified_milliseconds': modifiedMilliseconds,
        'individual_count': individualCount,
        'family_count': familyCount,
        'imported_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> importFamilyRelationshipsBatch({
    required List<Map<String, Object?>> parentChildLinks,
    required List<Map<String, Object?>> spouseLinks,
  }) async {
    final database = await this.database;

    await database.transaction((transaction) async {
      const chunkSize = 1000;

      for (var start = 0; start < parentChildLinks.length; start += chunkSize) {
        final end = (start + chunkSize < parentChildLinks.length)
            ? start + chunkSize
            : parentChildLinks.length;
        final batch = transaction.batch();

        for (var index = start; index < end; index++) {
          batch.insert(
            'family_parent_child',
            parentChildLinks[index],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      for (var start = 0; start < spouseLinks.length; start += chunkSize) {
        final end = (start + chunkSize < spouseLinks.length)
            ? start + chunkSize
            : spouseLinks.length;
        final batch = transaction.batch();

        for (var index = start; index < end; index++) {
          batch.insert(
            'family_spouses',
            spouseLinks[index],
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }


  Future<Map<String, Object?>> getFamilyDiagnostics() async {
    final database = await this.database;

    Future<int> count(String table) async {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM $table',
      );
      return _mapInt(rows.first['total']);
    }

    final databasePath = _databasePath ?? '';
    final backupDirectory = databasePath.isEmpty
        ? null
        : Directory(path.join(path.dirname(databasePath), 'Backups'));

    final backupPaths = <String>[];
    if (backupDirectory != null && await backupDirectory.exists()) {
      final files = await backupDirectory
          .list()
          .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.db'))
          .cast<File>()
          .toList();

      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      backupPaths.addAll(files.map((file) => file.path));
    }

    return {
      'database_path': databasePath,
      'family_people': await count('family_people'),
      'parent_child_links': await count('family_parent_child'),
      'spouse_links': await count('family_spouses'),
      'gedcom_imports': await count('gedcom_imports'),
      'gedcom_person_links': await count('gedcom_person_links'),
      'backup_paths': backupPaths,
    };
  }



  Future<List<Map<String, Object?>>> inspectDatabaseBackups() async {
    final sourcePath = _databasePath;
    if (sourcePath == null || sourcePath.isEmpty) return const [];

    final backupDirectory =
        Directory(path.join(path.dirname(sourcePath), 'Backups'));
    if (!await backupDirectory.exists()) return const [];

    final files = await backupDirectory.list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.db'))
        .cast<File>().toList();
    files.sort((a, b) =>
        b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    Future<int> countTable(Database db, String table) async {
      final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [table],
      );
      if (exists.isEmpty) return 0;
      final rows =
          await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
      return _mapInt(rows.first['total']);
    }

    final results = <Map<String, Object?>>[];
    for (final file in files) {
      Database? backupDb;
      try {
        backupDb = await databaseFactory.openDatabase(
          file.path,
          options: OpenDatabaseOptions(
            readOnly: true,
            singleInstance: false,
          ),
        );
        results.add({
          'name': path.basename(file.path),
          'path': file.path,
          'modified': file.lastModifiedSync().millisecondsSinceEpoch,
          'people': await countTable(backupDb, 'family_people'),
          'parent_child':
              await countTable(backupDb, 'family_parent_child'),
          'spouses': await countTable(backupDb, 'family_spouses'),
          'gedcom_imports': await countTable(backupDb, 'gedcom_imports'),
          'gedcom_links':
              await countTable(backupDb, 'gedcom_person_links'),
          'error': '',
        });
      } catch (error) {
        results.add({
          'name': path.basename(file.path),
          'path': file.path,
          'modified': file.lastModifiedSync().millisecondsSinceEpoch,
          'people': 0,
          'parent_child': 0,
          'spouses': 0,
          'gedcom_imports': 0,
          'gedcom_links': 0,
          'error': error.toString(),
        });
      } finally {
        await backupDb?.close();
      }
    }
    return results;
  }


  Future<Map<String, Object?>> inspectDatabaseFile(String filePath) async {
    Database? checkDb;
    Future<int> countTable(Database db, String table) async {
      final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [table],
      );
      if (exists.isEmpty) return 0;
      final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
      return _mapInt(rows.first['total']);
    }

    try {
      checkDb = await databaseFactory.openDatabase(
        filePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      return {
        'database_path': filePath,
        'family_people': await countTable(checkDb, 'family_people'),
        'parent_child_links': await countTable(checkDb, 'family_parent_child'),
        'spouse_links': await countTable(checkDb, 'family_spouses'),
        'gedcom_imports': await countTable(checkDb, 'gedcom_imports'),
        'gedcom_person_links': await countTable(checkDb, 'gedcom_person_links'),
      };
    } finally {
      await checkDb?.close();
    }
  }

  Future<Map<String, Object?>> createVerifiedFamilyBackup({
    String label = 'family_tree_verified',
  }) async {
    final db = await database;
    final sourcePath = _databasePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw StateError('Database path is not available.');
    }

    await db.execute('PRAGMA wal_checkpoint(FULL)');
    final backupDirectory =
        Directory(path.join(path.dirname(sourcePath), 'Backups'));
    await backupDirectory.create(recursive: true);

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final safeLabel = label.trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    final destination = path.join(
      backupDirectory.path,
      'heritage_vault_${stamp}_${safeLabel.isEmpty ? 'family_tree_verified' : safeLabel}.db',
    );

    await db.execute("VACUUM INTO '${destination.replaceAll("'", "''")}'");

    final backup = await inspectDatabaseFile(destination);
    final live = await getFamilyDiagnostics();
    final verified =
        backup['family_people'] == live['family_people'] &&
        backup['parent_child_links'] == live['parent_child_links'] &&
        backup['spouse_links'] == live['spouse_links'] &&
        backup['gedcom_person_links'] == live['gedcom_person_links'];

    return {'path': destination, 'verified': verified, 'backup': backup};
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
    String? series,
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

    if (series != null && series.trim().isNotEmpty) {
      whereParts.add('series = ?');
      whereArguments.add(series);
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
      quantityOwned: coin.quantityOwned,
      storageLocation: coin.storageLocation,
      grade: coin.grade,
      value: coin.value,
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
      category = ? AND
      series = ? AND
      year = ? AND
      mint = ? AND
      variety = ?
    ''',
    whereArgs: [
      originalCoin.category,
      originalCoin.series,
      originalCoin.year,
      originalCoin.mint,
      originalCoin.variety,
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
      'quantity_owned': coin.quantityOwned,
      'storage_location': coin.storageLocation,
      'grade': coin.grade,
      'value': coin.value,
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
      quantityOwned: _mapInt(row['quantity_owned']),
      storageLocation: row['storage_location'] as String? ?? '',
      grade: row['grade'] as String? ?? '',
      value: _mapDouble(row['value']),
      notes: row['notes'] as String? ?? '',
    );
  }
  int _mapInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _mapDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<int> replaceStorageLocations(
    List<Map<String, Object?>> locations,
  ) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      await transaction.delete('storage_locations');
      final batch = transaction.batch();

      for (final location in locations) {
        batch.insert('storage_locations', location);
      }

      await batch.commit(noResult: true);
      return locations.length;
    });
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


  static Future<void> _createSportsCardsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sports_cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sport TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        brand TEXT NOT NULL DEFAULT '',
        set_name TEXT NOT NULL DEFAULT '',
        card_number TEXT NOT NULL DEFAULT '',
        player TEXT NOT NULL DEFAULT '',
        team TEXT NOT NULL DEFAULT '',
        attributes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Untracked',
        quantity_owned INTEGER NOT NULL DEFAULT 0,
        grade TEXT NOT NULL DEFAULT '',
        storage_location TEXT NOT NULL DEFAULT '',
        value REAL,
        notes TEXT NOT NULL DEFAULT '',
        UNIQUE(sport, year, brand, set_name, card_number)
      )
    ''');
  }

  static Future<void> _createSportsCardCatalogTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sports_card_sets (
        source_key TEXT PRIMARY KEY,
        source_name TEXT NOT NULL DEFAULT 'CardLists',
        sport TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        brand TEXT NOT NULL DEFAULT '',
        set_name TEXT NOT NULL DEFAULT '',
        installed_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        refreshed_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sports_card_catalog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_key TEXT NOT NULL,
        sport TEXT NOT NULL DEFAULT '',
        year TEXT NOT NULL DEFAULT '',
        brand TEXT NOT NULL DEFAULT '',
        set_name TEXT NOT NULL DEFAULT '',
        card_number TEXT NOT NULL DEFAULT '',
        player TEXT NOT NULL DEFAULT '',
        team TEXT NOT NULL DEFAULT '',
        attributes TEXT NOT NULL DEFAULT '',
        catalog_notes TEXT NOT NULL DEFAULT '',
        UNIQUE(source_key, card_number)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sports_card_collection (
        catalog_id INTEGER PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'Untracked',
        quantity_owned INTEGER NOT NULL DEFAULT 0,
        grade TEXT NOT NULL DEFAULT '',
        storage_location TEXT NOT NULL DEFAULT '',
        value REAL,
        value_source TEXT NOT NULL DEFAULT '',
        value_updated_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        image_path TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS sports_card_catalog_set_index
      ON sports_card_catalog(source_key, card_number)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS sports_card_collection_status_index
      ON sports_card_collection(status)
    ''');
  }

  static Future<void> _migrateLegacySportsCards(Database database) async {
    final rows = await database.query('sports_cards');
    if (rows.isEmpty) return;

    await database.transaction((transaction) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final grouped = <String, List<Map<String, Object?>>>{};

      for (final row in rows) {
        final sport = row['sport'] as String? ?? '';
        final year = row['year'] as String? ?? '';
        final brand = row['brand'] as String? ?? '';
        final setName = row['set_name'] as String? ?? '';
        final sourceKey = 'legacy:$sport:$year:$brand:$setName';
        grouped.putIfAbsent(sourceKey, () => []).add(row);
      }

      for (final entry in grouped.entries) {
        final first = entry.value.first;

        await transaction.insert(
          'sports_card_sets',
          {
            'source_key': entry.key,
            'source_name': 'Migrated',
            'sport': first['sport'] as String? ?? '',
            'year': first['year'] as String? ?? '',
            'brand': first['brand'] as String? ?? '',
            'set_name': first['set_name'] as String? ?? '',
            'installed_at_milliseconds': now,
            'refreshed_at_milliseconds': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        for (final row in entry.value) {
          final catalogId = await transaction.insert(
            'sports_card_catalog',
            {
              'source_key': entry.key,
              'sport': row['sport'] as String? ?? '',
              'year': row['year'] as String? ?? '',
              'brand': row['brand'] as String? ?? '',
              'set_name': row['set_name'] as String? ?? '',
              'card_number': row['card_number'] as String? ?? '',
              'player': row['player'] as String? ?? '',
              'team': row['team'] as String? ?? '',
              'attributes': row['attributes'] as String? ?? '',
              'catalog_notes': row['notes'] as String? ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          var resolvedId = catalogId;
          if (resolvedId == 0) {
            final match = await transaction.query(
              'sports_card_catalog',
              columns: ['id'],
              where: 'source_key = ? AND card_number = ?',
              whereArgs: [entry.key, row['card_number'] as String? ?? ''],
              limit: 1,
            );
            if (match.isEmpty) continue;
            resolvedId = _staticMapInt(match.first['id']);
          }

          await transaction.insert(
            'sports_card_collection',
            {
              'catalog_id': resolvedId,
              'status': row['status'] as String? ?? 'Untracked',
              'quantity_owned': _staticMapInt(row['quantity_owned']),
              'grade': row['grade'] as String? ?? '',
              'storage_location': row['storage_location'] as String? ?? '',
              'value': row['value'],
              'notes': row['notes'] as String? ?? '',
              'updated_at_milliseconds': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
  }

  static int _staticMapInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<Map<String, Object?>>> getInstalledSportsCardSets() async {
    final db = await database;
    return db.query(
      'sports_card_sets',
      orderBy: 'sport COLLATE NOCASE, year DESC, brand COLLATE NOCASE, set_name COLLATE NOCASE',
    );
  }

  Future<int> importSportsCardSet({
    required String sourceKey,
    required String sourceName,
    required String sport,
    required String year,
    required String brand,
    required String setName,
    required List<SportsCard> cards,
  }) async {
    final db = await database;

    return db.transaction((transaction) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      final existingSet = await transaction.query(
        'sports_card_sets',
        columns: ['installed_at_milliseconds'],
        where: 'source_key = ?',
        whereArgs: [sourceKey],
        limit: 1,
      );

      final installedAt = existingSet.isEmpty
          ? now
          : _staticMapInt(existingSet.first['installed_at_milliseconds']);

      await transaction.insert(
        'sports_card_sets',
        {
          'source_key': sourceKey,
          'source_name': sourceName,
          'sport': sport,
          'year': year,
          'brand': brand,
          'set_name': setName,
          'installed_at_milliseconds': installedAt,
          'refreshed_at_milliseconds': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final oldRows = await transaction.rawQuery(
        '''
        SELECT c.card_number, u.status, u.quantity_owned, u.grade,
               u.storage_location, u.value, u.value_source,
               u.value_updated_at_milliseconds, u.image_path, u.notes
        FROM sports_card_catalog c
        LEFT JOIN sports_card_collection u ON u.catalog_id = c.id
        WHERE c.source_key = ?
        ''',
        [sourceKey],
      );

      final userByNumber = <String, Map<String, Object?>>{
        for (final row in oldRows)
          row['card_number'] as String? ?? '': row,
      };

      final oldCatalog = await transaction.query(
        'sports_card_catalog',
        columns: ['id'],
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );

      for (final row in oldCatalog) {
        await transaction.delete(
          'sports_card_collection',
          where: 'catalog_id = ?',
          whereArgs: [row['id']],
        );
      }

      await transaction.delete(
        'sports_card_catalog',
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );

      var imported = 0;

      for (final card in cards) {
        final catalogId = await transaction.insert(
          'sports_card_catalog',
          {
            'source_key': sourceKey,
            'sport': sport,
            'year': year,
            'brand': brand,
            'set_name': setName,
            'card_number': card.cardNumber,
            'player': card.player,
            'team': card.team,
            'attributes': card.attributes,
            'catalog_notes': card.notes,
          },
        );

        final previous = userByNumber[card.cardNumber];

        await transaction.insert(
          'sports_card_collection',
          {
            'catalog_id': catalogId,
            'status': previous?['status'] as String? ?? 'Untracked',
            'quantity_owned': _staticMapInt(previous?['quantity_owned']),
            'grade': previous?['grade'] as String? ?? '',
            'storage_location': previous?['storage_location'] as String? ?? '',
            'value': previous?['value'],
            'value_source': previous?['value_source'] as String? ?? '',
            'value_updated_at_milliseconds':
                _staticMapInt(previous?['value_updated_at_milliseconds']),
            'image_path': previous?['image_path'] as String? ?? '',
            'notes': previous?['notes'] as String? ?? '',
            'updated_at_milliseconds': now,
          },
        );

        imported++;
      }

      return imported;
    });
  }

  Future<List<SportsCard>> getSportsCards({
    required String sourceKey,
    String searchText = '',
    String status = 'All',
  }) async {
    final db = await database;
    final where = <String>['c.source_key = ?'];
    final args = <Object?>[sourceKey];

    if (status != 'All') {
      where.add("COALESCE(u.status, 'Untracked') = ?");
      args.add(status);
    }

    if (searchText.trim().isNotEmpty) {
      where.add('''
        (c.player LIKE ? OR c.team LIKE ? OR c.card_number LIKE ? OR
         c.year LIKE ? OR c.brand LIKE ? OR c.set_name LIKE ? OR
         c.attributes LIKE ?)
      ''');
      final pattern = '%${searchText.trim()}%';
      args.addAll(List<Object?>.filled(7, pattern));
    }

    final rows = await db.rawQuery(
      '''
      SELECT c.id, c.sport, c.year, c.brand, c.set_name, c.card_number,
             c.player, c.team, c.attributes,
             COALESCE(u.status, 'Untracked') AS status,
             COALESCE(u.quantity_owned, 0) AS quantity_owned,
             COALESCE(u.grade, '') AS grade,
             COALESCE(u.storage_location, '') AS storage_location,
             u.value,
             COALESCE(u.value_source, '') AS value_source,
             COALESCE(u.value_updated_at_milliseconds, 0)
               AS value_updated_at_milliseconds,
             COALESCE(u.image_path, '') AS image_path,
             COALESCE(u.notes, '') AS notes
      FROM sports_card_catalog c
      LEFT JOIN sports_card_collection u ON u.catalog_id = c.id
      WHERE ${where.join(' AND ')}
      ORDER BY CAST(c.card_number AS INTEGER), c.card_number COLLATE NOCASE
      ''',
      args,
    );

    return rows.map(SportsCard.fromMap).toList();
  }

  Future<SportsCard?> findSportsCard({
    required String year,
    required String brand,
    required String cardNumber,
    String setName = '',
  }) async {
    final db = await database;

    final where = <String>[
      'c.year = ?',
      'LOWER(c.brand) = LOWER(?)',
      'LOWER(c.card_number) = LOWER(?)',
    ];

    final args = <Object?>[
      year.trim(),
      brand.trim(),
      cardNumber.trim(),
    ];

    if (setName.trim().isNotEmpty) {
      where.add('LOWER(c.set_name) = LOWER(?)');
      args.add(setName.trim());
    }

    final rows = await db.rawQuery(
      '''
      SELECT c.id, c.sport, c.year, c.brand, c.set_name, c.card_number,
             c.player, c.team, c.attributes,
             COALESCE(u.status, 'Untracked') AS status,
             COALESCE(u.quantity_owned, 0) AS quantity_owned,
             COALESCE(u.grade, '') AS grade,
             COALESCE(u.storage_location, '') AS storage_location,
             u.value,
             COALESCE(u.value_source, '') AS value_source,
             COALESCE(u.value_updated_at_milliseconds, 0)
               AS value_updated_at_milliseconds,
             COALESCE(u.image_path, '') AS image_path,
             COALESCE(u.notes, '') AS notes
      FROM sports_card_catalog c
      LEFT JOIN sports_card_collection u ON u.catalog_id = c.id
      WHERE ${where.join(' AND ')}
      LIMIT 2
      ''',
      args,
    );

    if (rows.length != 1) {
      return null;
    }

    return SportsCard.fromMap(rows.first);
  }

  Future<int> updateSportsCard(SportsCard card) async {
    if (card.id == null) throw ArgumentError('Sports card catalog ID required.');
    final db = await database;

    return db.insert(
      'sports_card_collection',
      {
        'catalog_id': card.id,
        'status': card.status,
        'quantity_owned': card.quantityOwned,
        'grade': card.grade,
        'storage_location': card.storageLocation,
        'value': card.value,
        'value_source': card.valueSource,
        'value_updated_at_milliseconds': card.valueUpdatedAtMilliseconds,
        'image_path': card.imagePath,
        'notes': card.notes,
        'updated_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, int>> getSportsCardSummary({
    required String sourceKey,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total,
        SUM(CASE WHEN COALESCE(u.status, 'Untracked') = 'Owned' THEN 1 ELSE 0 END) AS owned,
        SUM(CASE WHEN COALESCE(u.status, 'Untracked') = 'Need' THEN 1 ELSE 0 END) AS needed,
        SUM(CASE WHEN COALESCE(u.status, 'Untracked') = 'Untracked' THEN 1 ELSE 0 END) AS untracked
      FROM sports_card_catalog c
      LEFT JOIN sports_card_collection u ON u.catalog_id = c.id
      WHERE c.source_key = ?
      ''',
      [sourceKey],
    );

    final row = rows.first;
    return {
      'total': _mapInt(row['total']),
      'owned': _mapInt(row['owned']),
      'needed': _mapInt(row['needed']),
      'untracked': _mapInt(row['untracked']),
    };
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
class StorageProgress {
  final String storageLocation;
  final int total;
  final int owned;
  final int needed;
  final int untracked;

  const StorageProgress({
    required this.storageLocation,
    required this.total,
    required this.owned,
    required this.needed,
    required this.untracked,
  });

  double get completionRate {
    final tracked = owned + needed;

    if (tracked == 0) {
      return 0;
    }

    return owned / tracked;
  }
}
