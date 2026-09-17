import '../database/database_helper.dart';

class DocumentPageRecord {
  final int? id;
  final int documentId;
  final int pageIndex;
  final String filePath;
  final int createdAtMilliseconds;

  const DocumentPageRecord({
    this.id,
    required this.documentId,
    required this.pageIndex,
    required this.filePath,
    this.createdAtMilliseconds = 0,
  });

  factory DocumentPageRecord.fromMap(Map<String, Object?> map) {
    return DocumentPageRecord(
      id: map['id'] as int?,
      documentId: (map['document_id'] as num?)?.toInt() ?? 0,
      pageIndex: (map['page_index'] as num?)?.toInt() ?? 0,
      filePath: map['file_path'] as String? ?? '',
      createdAtMilliseconds:
          (map['created_at_milliseconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class DocumentPageService {
  DocumentPageService._();

  static final DocumentPageService instance = DocumentPageService._();

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Future<void> ensureTable() async {
    final db = await _databaseHelper.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_pages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        page_index INTEGER NOT NULL DEFAULT 0,
        file_path TEXT NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        UNIQUE(document_id, page_index)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS document_pages_document_index
      ON document_pages(document_id, page_index)
    ''');
  }

  Future<List<DocumentPageRecord>> getPages(int documentId) async {
    await ensureTable();
    final db = await _databaseHelper.database;

    final rows = await db.query(
      'document_pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'page_index ASC, id ASC',
    );

    return rows.map(DocumentPageRecord.fromMap).toList();
  }

  Future<int> addPage({
    required int documentId,
    required String filePath,
    int? pageIndex,
  }) async {
    await ensureTable();
    final db = await _databaseHelper.database;

    var resolvedIndex = pageIndex;

    if (resolvedIndex == null) {
      final rows = await db.rawQuery(
        '''
        SELECT COALESCE(MAX(page_index), -1) + 1 AS next_index
        FROM document_pages
        WHERE document_id = ?
        ''',
        [documentId],
      );

      final raw = rows.isEmpty ? null : rows.first['next_index'];
      resolvedIndex = raw is num ? raw.toInt() : 0;
    }

    return db.insert(
      'document_pages',
      {
        'document_id': documentId,
        'page_index': resolvedIndex,
        'file_path': filePath,
        'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> replacePages({
    required int documentId,
    required List<String> filePaths,
  }) async {
    await ensureTable();
    final db = await _databaseHelper.database;

    await db.transaction((txn) async {
      await txn.delete(
        'document_pages',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );

      for (var index = 0; index < filePaths.length; index++) {
        await txn.insert(
          'document_pages',
          {
            'document_id': documentId,
            'page_index': index,
            'file_path': filePaths[index],
            'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  Future<void> reorderPages({
    required int documentId,
    required List<DocumentPageRecord> pages,
  }) async {
    await ensureTable();
    final db = await _databaseHelper.database;

    await db.transaction((txn) async {
      for (var index = 0; index < pages.length; index++) {
        final page = pages[index];
        if (page.id == null) continue;

        await txn.update(
          'document_pages',
          {'page_index': index},
          where: 'id = ? AND document_id = ?',
          whereArgs: [page.id, documentId],
        );
      }
    });
  }

  Future<void> deletePage(int pageId) async {
    await ensureTable();
    final db = await _databaseHelper.database;

    await db.delete(
      'document_pages',
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  Future<void> deletePagesForDocument(int documentId) async {
    await ensureTable();
    final db = await _databaseHelper.database;

    await db.delete(
      'document_pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
  }
}
