import '../database/database_helper.dart';
import '../models/family_person.dart';
import '../models/heritage_story.dart';

class StoryAttachment {
  final int? id;
  final int storyId;
  final String path;
  final bool isCover;
  final int sortOrder;

  const StoryAttachment({
    this.id,
    required this.storyId,
    required this.path,
    this.isCover = false,
    this.sortOrder = 0,
  });

  factory StoryAttachment.fromMap(Map<String, Object?> map) => StoryAttachment(
        id: map['id'] as int?,
        storyId: map['story_id'] as int,
        path: (map['path'] as String?) ?? '',
        isCover: ((map['is_cover'] as int?) ?? 0) == 1,
        sortOrder: (map['sort_order'] as int?) ?? 0,
      );
}

class StoryRepository {
  StoryRepository._();
  static final StoryRepository instance = StoryRepository._();
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<void> ensureReady() async {
    final database = await _db.database;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS heritage_stories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        story_text TEXT NOT NULL DEFAULT '',
        date_text TEXT NOT NULL DEFAULT '',
        place TEXT NOT NULL DEFAULT '',
        author_source TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        attachment_path TEXT NOT NULL DEFAULT '',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS heritage_story_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        story_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        is_cover INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        UNIQUE(story_id, path)
      )
    ''');

    // Preserve/migrate the original v1 single attachment.
    final legacy = await database.query(
      'heritage_stories',
      columns: ['id', 'attachment_path'],
      where: "TRIM(attachment_path) <> ''",
    );
    for (final row in legacy) {
      final storyId = row['id'] as int;
      final path = (row['attachment_path'] as String?)?.trim() ?? '';
      if (path.isEmpty) continue;
      final count = await database.rawQuery(
        'SELECT COUNT(*) AS c FROM heritage_story_attachments WHERE story_id = ?',
        [storyId],
      );
      final existing = (count.first['c'] as int?) ?? 0;
      if (existing == 0) {
        await database.insert('heritage_story_attachments', {
          'story_id': storyId,
          'path': path,
          'is_cover': 1,
          'sort_order': 0,
        });
      }
    }
  }

  Future<List<HeritageStory>> getStories({String search = ''}) async {
    await ensureReady();
    final database = await _db.database;
    final q = search.trim();
    final rows = q.isEmpty
        ? await database.query('heritage_stories',
            orderBy: 'updated_at_milliseconds DESC, title COLLATE NOCASE')
        : await database.query('heritage_stories',
            where:
                'title LIKE ? OR story_text LIKE ? OR date_text LIKE ? OR place LIKE ? OR author_source LIKE ? OR notes LIKE ?',
            whereArgs: List.filled(6, '%$q%'),
            orderBy: 'updated_at_milliseconds DESC, title COLLATE NOCASE');
    return rows.map(HeritageStory.fromMap).toList();
  }

  Future<List<StoryAttachment>> getAttachments(int storyId) async {
    await ensureReady();
    final database = await _db.database;
    final rows = await database.query(
      'heritage_story_attachments',
      where: 'story_id = ?',
      whereArgs: [storyId],
      orderBy: 'is_cover DESC, sort_order ASC, id ASC',
    );
    return rows.map(StoryAttachment.fromMap).toList();
  }

  Future<StoryAttachment?> getCoverAttachment(int storyId) async {
    final items = await getAttachments(storyId);
    if (items.isEmpty) return null;
    return items.firstWhere(
      (item) => item.isCover,
      orElse: () => items.first,
    );
  }

  Future<int> saveStory(
    HeritageStory story, {
    Iterable<int> personIds = const [],
    Iterable<String>? attachmentPaths,
    String? coverPath,
  }) async {
    await ensureReady();
    final database = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = story.toMap();
    map['updated_at_milliseconds'] = now;
    int id;
    if (story.id == null) {
      map['created_at_milliseconds'] = now;
      id = await database.insert('heritage_stories', map);
    } else {
      id = story.id!;
      await database.update('heritage_stories', map,
          where: 'id = ?', whereArgs: [id]);
    }

    if (attachmentPaths != null) {
      final clean = attachmentPaths
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final chosenCover =
          clean.contains(coverPath) ? coverPath : (clean.isEmpty ? null : clean.first);

      await database.transaction((txn) async {
        await txn.delete(
          'heritage_story_attachments',
          where: 'story_id = ?',
          whereArgs: [id],
        );
        for (var i = 0; i < clean.length; i++) {
          await txn.insert('heritage_story_attachments', {
            'story_id': id,
            'path': clean[i],
            'is_cover': clean[i] == chosenCover ? 1 : 0,
            'sort_order': i,
          });
        }
        await txn.update(
          'heritage_stories',
          {'attachment_path': chosenCover ?? ''},
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    }

    await _db.replaceFamilyPeopleForItem(
      itemType: 'story',
      itemKey: id.toString(),
      personIds: personIds,
    );
    return id;
  }

  Future<void> deleteStory(int id) async {
    await ensureReady();
    final database = await _db.database;
    await database.delete(
      'heritage_story_attachments',
      where: 'story_id = ?',
      whereArgs: [id],
    );
    await database.delete('heritage_stories', where: 'id = ?', whereArgs: [id]);
    final people = await _db.getFamilyPersonIdsForItem(
        itemType: 'story', itemKey: id.toString());
    for (final personId in people) {
      await _db.unlinkFamilyPersonFromItem(
          personId: personId, itemType: 'story', itemKey: id.toString());
    }
  }

  Future<List<int>> getPersonIds(int storyId) => _db.getFamilyPersonIdsForItem(
      itemType: 'story', itemKey: storyId.toString());

  Future<List<FamilyPerson>> getPeople(int storyId) => _db.getFamilyPeopleForItem(
      itemType: 'story', itemKey: storyId.toString());

  Future<List<HeritageStory>> getStoriesForPerson(int personId) async {
    await ensureReady();
    final keys = await _db.getItemKeysForFamilyPeople(
        personIds: [personId], itemType: 'story');
    final ids = keys.map(int.tryParse).whereType<int>().toList();
    if (ids.isEmpty) return const [];
    final database = await _db.database;
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await database.rawQuery(
        'SELECT * FROM heritage_stories WHERE id IN ($marks) ORDER BY updated_at_milliseconds DESC',
        ids);
    return rows.map(HeritageStory.fromMap).toList();
  }
}
