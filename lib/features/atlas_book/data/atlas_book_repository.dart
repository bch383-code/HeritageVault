import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/atlas_book_page.dart';
import '../models/atlas_book_project.dart';

class AtlasBookRepository {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final databasePath = await databaseFactory.getDatabasesPath();
    final path = '$databasePath${Platform.pathSeparator}atlas_books.db';

    _database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE atlas_books (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              subtitle TEXT,
              scope TEXT NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');

          await _createBookPeopleTable(db);
          await _createBookPhotosTable(db);
          await _createBookPagesTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createBookPeopleTable(db);
          }

          if (oldVersion < 3) {
            await _createBookPhotosTable(db);
          }

          if (oldVersion < 4) {
            await _createBookPagesTable(db);
          }

          if (oldVersion < 5) {
            await db.execute(
              'ALTER TABLE atlas_book_pages '
              'ADD COLUMN generation_count INTEGER NOT NULL DEFAULT 4',
            );
          }

          if (oldVersion < 6) {
            await db.execute(
              'ALTER TABLE atlas_book_pages '
              'ADD COLUMN related_person_id INTEGER',
            );
          }

          if (oldVersion < 7) {
            await db.execute(
              'ALTER TABLE atlas_book_pages '
              "ADD COLUMN collage_photo_paths_json TEXT NOT NULL DEFAULT '[]'",
            );
            await db.execute(
              'ALTER TABLE atlas_book_pages '
              "ADD COLUMN collage_layout_key TEXT NOT NULL DEFAULT 'balanced'",
            );
          }
        },
      ),
    );

    return _database!;
  }

  static Future<void> _createBookPeopleTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS atlas_book_people (
        book_id INTEGER NOT NULL,
        person_id INTEGER NOT NULL,
        added_at TEXT NOT NULL,
        PRIMARY KEY (book_id, person_id)
      )
    ''');
  }

  static Future<void> _createBookPhotosTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS atlas_book_photos (
        book_id INTEGER NOT NULL,
        photo_file_path TEXT NOT NULL,
        added_at TEXT NOT NULL,
        PRIMARY KEY (book_id, photo_file_path)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS atlas_book_photos_book_index
      ON atlas_book_photos(book_id)
    ''');
  }

  static Future<void> _createBookPagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS atlas_book_pages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        page_type TEXT NOT NULL,
        person_id INTEGER,
        related_person_id INTEGER,
        hero_photo_path TEXT NOT NULL DEFAULT '',
        generation_count INTEGER NOT NULL DEFAULT 4,
        collage_photo_paths_json TEXT NOT NULL DEFAULT '[]',
        collage_layout_key TEXT NOT NULL DEFAULT 'balanced',
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS atlas_book_pages_book_index
      ON atlas_book_pages(book_id, sort_order, id)
    ''');
  }

  Future<List<AtlasBookProject>> getBooks() async {
    final db = await database;

    final rows = await db.query(
      'atlas_books',
      orderBy: 'created_at DESC',
    );

    return rows.map(AtlasBookProject.fromMap).toList();
  }

  Future<AtlasBookProject> createBook(
    AtlasBookProject project,
  ) async {
    final db = await database;

    final map = project.toMap();
    map.remove('id');

    final id = await db.insert(
      'atlas_books',
      map,
    );

    return AtlasBookProject(
      id: id,
      title: project.title,
      subtitle: project.subtitle,
      scope: project.scope,
      status: project.status,
      createdAt: project.createdAt,
    );
  }

  Future<List<int>> getBookPersonIds(int bookId) async {
    final db = await database;

    final rows = await db.query(
      'atlas_book_people',
      columns: ['person_id'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'added_at ASC',
    );

    return rows
        .map((row) => (row['person_id'] as num).toInt())
        .toList();
  }

  Future<void> replaceBookPeople(
    int bookId,
    Iterable<int> personIds,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'atlas_book_people',
        where: 'book_id = ?',
        whereArgs: [bookId],
      );

      final now = DateTime.now().toIso8601String();

      for (final personId in personIds.toSet()) {
        await txn.insert(
          'atlas_book_people',
          {
            'book_id': bookId,
            'person_id': personId,
            'added_at': now,
          },
        );
      }
    });
  }

  Future<List<String>> getBookPhotoPaths(int bookId) async {
    final db = await database;

    final rows = await db.query(
      'atlas_book_photos',
      columns: ['photo_file_path'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'added_at ASC',
    );

    return rows
        .map((row) => row['photo_file_path'] as String? ?? '')
        .where((path) => path.isNotEmpty)
        .toList();
  }

  Future<void> replaceBookPhotos(
    int bookId,
    Iterable<String> photoPaths,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'atlas_book_photos',
        where: 'book_id = ?',
        whereArgs: [bookId],
      );

      final now = DateTime.now().toIso8601String();

      for (final photoPath in photoPaths
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toSet()) {
        await txn.insert(
          'atlas_book_photos',
          {
            'book_id': bookId,
            'photo_file_path': photoPath,
            'added_at': now,
          },
        );
      }
    });
  }
  Future<List<AtlasBookPage>> getBookPages(int bookId) async {
    final db = await database;
    final rows = await db.query(
      'atlas_book_pages',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(AtlasBookPage.fromMap).toList();
  }

  Future<int> getNextBookPageSortOrder(int bookId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order
      FROM atlas_book_pages
      WHERE book_id = ?
      ''',
      [bookId],
    );
    return (rows.first['next_order'] as num?)?.toInt() ?? 0;
  }

  Future<AtlasBookPage> insertBookPage(AtlasBookPage page) async {
    final db = await database;
    final map = page.toMap();
    map.remove('id');
    final id = await db.insert('atlas_book_pages', map);

    return AtlasBookPage(
      id: id,
      bookId: page.bookId,
      pageType: page.pageType,
      personId: page.personId,
      relatedPersonId: page.relatedPersonId,
      heroPhotoPath: page.heroPhotoPath,
      generationCount: page.generationCount,
      collagePhotoPathsJson: page.collagePhotoPathsJson,
      collageLayoutKey: page.collageLayoutKey,
      sortOrder: page.sortOrder,
      createdAt: page.createdAt,
      updatedAt: page.updatedAt,
    );
  }

  Future<void> updateBookPage(AtlasBookPage page) async {
    final pageId = page.id;
    if (pageId == null) return;

    final db = await database;
    final map = page.toMap();
    map.remove('id');

    await db.update(
      'atlas_book_pages',
      map,
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  Future<void> deleteBookPage(int pageId) async {
    final db = await database;
    await db.delete(
      'atlas_book_pages',
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  Future<void> reorderBookPages(
    int bookId,
    List<int> pageIdsInOrder,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var index = 0; index < pageIdsInOrder.length; index++) {
        await txn.update(
          'atlas_book_pages',
          {
            'sort_order': index,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ? AND book_id = ?',
          whereArgs: [pageIdsInOrder[index], bookId],
        );
      }
    });
  }

}
