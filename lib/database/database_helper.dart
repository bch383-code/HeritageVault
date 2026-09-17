import 'dart:convert';
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
import '../models/document_record.dart';

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

    _databasePath = path.join(heritageVaultDirectory.path, 'heritage_vault.db');

    return databaseFactory.openDatabase(
      _databasePath!,
      options: OpenDatabaseOptions(
        version: 41,
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
          await _createPersonGroupsTables(database);
          await _createPhotoPersonFamilyLinksTable(database);
          await _createPhotoPersonAliasesTable(database);
          await _createPhotoSourcesTables(database);
          await _createPersonMatchRejectionsTable(database);
          await _createAtlasBookFavoritesTable(database);
          await _createSyncFoundationTables(database);
          await _createDocumentsTable(database);
          await _createNewspaperClippingsTables(database);
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
          if (oldVersion < 24) {
            await database.execute(
              "ALTER TABLE photo_faces "
              "ADD COLUMN review_status TEXT NOT NULL DEFAULT 'pending'",
            );
            await database.execute(
              "UPDATE photo_faces SET review_status = 'identified' "
              "WHERE confirmed = 1 AND person_name <> ''",
            );
          }
          if (oldVersion < 25) {
            await _createPersonGroupsTables(database);
          }
          if (oldVersion < 26) {
            await _createPhotoPersonFamilyLinksTable(database);
          }
          if (oldVersion < 27) {
            await database.execute(
              "ALTER TABLE photo_catalog_metadata "
              "ADD COLUMN back_writing TEXT NOT NULL DEFAULT ''",
            );
          }
          if (oldVersion < 28) {
            await _createPhotoPersonAliasesTable(database);
          }
          if (oldVersion < 29) {
            await _upgradeFamilyPersonLinksToRoles(database);
          }
          if (oldVersion < 30) {
            await _upgradePhotoFacesForSFace(database);
          }
          if (oldVersion < 31) {
            await _createPhotoSourcesTables(database);
            await _migrateLegacyPhotoSource(database);
          }
          if (oldVersion < 32) {
            await _createPersonMatchRejectionsTable(database);
          }
          if (oldVersion < 33) {
            await _createAtlasBookFavoritesTable(database);
          }
          if (oldVersion < 34) {
            await _upgradeAntiquesToVersion34(database);
          }
          if (oldVersion < 35) {
            await _upgradeValuablesToVersion35(database);
          }
          if (oldVersion < 36) {
            await _createSyncFoundationTables(database);
          }
          if (oldVersion < 37) {
            await _upgradeSyncFoundationToVersion37(database);
          }
          if (oldVersion < 38) {
            await _upgradeSyncFoundationToVersion38(database);
          }
          if (oldVersion < 39) {
            final info = await database.rawQuery(
              "PRAGMA table_info(imported_coins)",
            );
            final columns = info
                .map((row) => row['name'] as String? ?? '')
                .toSet();
            if (!columns.contains('image_path')) {
              await database.execute(
                "ALTER TABLE imported_coins "
                "ADD COLUMN image_path TEXT NOT NULL DEFAULT ''",
              );
            }
          }
          if (oldVersion < 40) {
            await _createDocumentsTable(database);
          }
          if (oldVersion < 41) {
            await _createNewspaperClippingsTables(database);
          }
        },
      ),
    );
  }

  static Future<void> _upgradeSyncFoundationToVersion37(
    Database database,
  ) async {
    final columns = await database.rawQuery(
      'PRAGMA table_info(sync_change_log)',
    );
    final hasDetailsJson = columns.any(
      (column) => column['name']?.toString() == 'details_json',
    );
    if (!hasDetailsJson) {
      await database.execute(
        "ALTER TABLE sync_change_log "
        "ADD COLUMN details_json TEXT NOT NULL DEFAULT '{}'",
      );
    }
  }

  static Future<void> _upgradeSyncFoundationToVersion38(
    Database database,
  ) async {
    final columns = await database.rawQuery(
      'PRAGMA table_info(sync_change_log)',
    );
    final columnNames = columns
        .map((column) => column['name']?.toString() ?? '')
        .toSet();

    if (!columnNames.contains('details_json')) {
      await database.execute(
        "ALTER TABLE sync_change_log "
        "ADD COLUMN details_json TEXT NOT NULL DEFAULT '{}'",
      );
    }

    if (!columnNames.contains('reviewed')) {
      await database.execute(
        "ALTER TABLE sync_change_log "
        "ADD COLUMN reviewed INTEGER NOT NULL DEFAULT 0",
      );
    }

    // No provider sync processing exists yet. Any processed rows at this
    // stage came from the temporary Mark Reviewed behavior.
    await database.execute(
      'UPDATE sync_change_log SET processed = 0, reviewed = 1 '
      'WHERE processed = 1',
    );
  }

  static Future<void> _createSyncFoundationTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_devices (
        device_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL DEFAULT '',
        platform TEXT NOT NULL DEFAULT '',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        last_seen_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        is_current INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_devices_current_index
      ON sync_devices(is_current)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS connected_sources (
        source_id TEXT PRIMARY KEY,
        provider_type TEXT NOT NULL,
        display_name TEXT NOT NULL DEFAULT '',
        account_identifier TEXT NOT NULL DEFAULT '',
        root_identifier TEXT NOT NULL DEFAULT '',
        root_path TEXT NOT NULL DEFAULT '',
        connection_status TEXT NOT NULL DEFAULT 'disconnected',
        capabilities_json TEXT NOT NULL DEFAULT '{}',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS connected_sources_provider_index
      ON connected_sources(provider_type, connection_status)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_uuid TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        local_key TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT '',
        remote_id TEXT NOT NULL DEFAULT '',
        remote_parent_id TEXT NOT NULL DEFAULT '',
        remote_etag TEXT NOT NULL DEFAULT '',
        local_modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        remote_modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        last_synced_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        sync_state TEXT NOT NULL DEFAULT 'local_only',
        deleted_local INTEGER NOT NULL DEFAULT 0,
        deleted_remote INTEGER NOT NULL DEFAULT 0,
        conflict_details TEXT NOT NULL DEFAULT '',
        UNIQUE(entity_type, local_key, source_id)
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_records_state_index
      ON sync_records(sync_state, entity_type)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_records_remote_index
      ON sync_records(source_id, remote_id)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_change_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        change_uuid TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL DEFAULT '',
        entity_type TEXT NOT NULL,
        local_key TEXT NOT NULL,
        operation TEXT NOT NULL,
        changed_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        payload_hash TEXT NOT NULL DEFAULT '',
        details_json TEXT NOT NULL DEFAULT '{}',
        reviewed INTEGER NOT NULL DEFAULT 0,
        processed INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_change_log_pending_index
      ON sync_change_log(processed, changed_at_milliseconds)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        local_key TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT '',
        local_modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        remote_modified_milliseconds INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'open',
        details TEXT NOT NULL DEFAULT '',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        resolved_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_conflicts_status_index
      ON sync_conflicts(status, created_at_milliseconds)
    ''');
  }

  Future<Map<String, Object?>> ensureCurrentSyncDevice({
    String? displayName,
  }) async {
    final database = await this.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final currentRows = await database.query(
      'sync_devices',
      where: 'is_current = 1',
      limit: 1,
    );

    if (currentRows.isNotEmpty) {
      final existing = currentRows.first;
      await database.update(
        'sync_devices',
        {
          'last_seen_at_milliseconds': now,
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
        },
        where: 'device_id = ?',
        whereArgs: [existing['device_id']],
      );
      final refreshed = await database.query(
        'sync_devices',
        where: 'device_id = ?',
        whereArgs: [existing['device_id']],
        limit: 1,
      );
      return refreshed.first;
    }

    final cleanHost = Platform.localHostname.trim().isEmpty
        ? 'device'
        : Platform.localHostname.trim();
    final deviceId =
        '${Platform.operatingSystem}_${cleanHost}_${DateTime.now().microsecondsSinceEpoch}';

    await database.insert('sync_devices', {
      'device_id': deviceId,
      'display_name': displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : cleanHost,
      'platform': Platform.operatingSystem,
      'created_at_milliseconds': now,
      'last_seen_at_milliseconds': now,
      'is_current': 1,
    });

    final rows = await database.query(
      'sync_devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    return rows.first;
  }

  Future<List<Map<String, Object?>>> getSyncDevices() async {
    final database = await this.database;
    return database.query(
      'sync_devices',
      orderBy: 'is_current DESC, last_seen_at_milliseconds DESC',
    );
  }

  Future<void> upsertConnectedSource({
    required String sourceId,
    required String providerType,
    required String displayName,
    String accountIdentifier = '',
    String rootIdentifier = '',
    String rootPath = '',
    String connectionStatus = 'disconnected',
    String capabilitiesJson = '{}',
  }) async {
    final cleanSourceId = sourceId.trim();
    final cleanProvider = providerType.trim().toLowerCase();
    if (cleanSourceId.isEmpty) {
      throw ArgumentError('A source ID is required.');
    }
    if (cleanProvider.isEmpty) {
      throw ArgumentError('A provider type is required.');
    }

    final database = await this.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await database.query(
      'connected_sources',
      columns: ['created_at_milliseconds'],
      where: 'source_id = ?',
      whereArgs: [cleanSourceId],
      limit: 1,
    );

    await database.insert('connected_sources', {
      'source_id': cleanSourceId,
      'provider_type': cleanProvider,
      'display_name': displayName.trim(),
      'account_identifier': accountIdentifier.trim(),
      'root_identifier': rootIdentifier.trim(),
      'root_path': rootPath.trim(),
      'connection_status': connectionStatus.trim().isEmpty
          ? 'disconnected'
          : connectionStatus.trim(),
      'capabilities_json': capabilitiesJson.trim().isEmpty
          ? '{}'
          : capabilitiesJson.trim(),
      'created_at_milliseconds': existing.isEmpty
          ? now
          : _mapInt(existing.first['created_at_milliseconds']),
      'updated_at_milliseconds': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getConnectedSources({
    String? providerType,
  }) async {
    final database = await this.database;
    final cleanProvider = providerType?.trim().toLowerCase() ?? '';
    return database.query(
      'connected_sources',
      where: cleanProvider.isEmpty ? null : 'provider_type = ?',
      whereArgs: cleanProvider.isEmpty ? null : [cleanProvider],
      orderBy: 'display_name COLLATE NOCASE, provider_type',
    );
  }

  Future<void> removeConnectedSource(String sourceId) async {
    final database = await this.database;
    await database.delete(
      'connected_sources',
      where: 'source_id = ?',
      whereArgs: [sourceId.trim()],
    );
  }

  Future<void> upsertSyncRecord({
    required String recordUuid,
    required String entityType,
    required String localKey,
    String sourceId = '',
    String remoteId = '',
    String remoteParentId = '',
    String remoteEtag = '',
    int localModifiedMilliseconds = 0,
    int remoteModifiedMilliseconds = 0,
    int lastSyncedAtMilliseconds = 0,
    String syncState = 'local_only',
    bool deletedLocal = false,
    bool deletedRemote = false,
    String conflictDetails = '',
  }) async {
    final database = await this.database;
    await database.insert('sync_records', {
      'record_uuid': recordUuid.trim(),
      'entity_type': entityType.trim().toLowerCase(),
      'local_key': localKey.trim(),
      'source_id': sourceId.trim(),
      'remote_id': remoteId.trim(),
      'remote_parent_id': remoteParentId.trim(),
      'remote_etag': remoteEtag.trim(),
      'local_modified_milliseconds': localModifiedMilliseconds,
      'remote_modified_milliseconds': remoteModifiedMilliseconds,
      'last_synced_at_milliseconds': lastSyncedAtMilliseconds,
      'sync_state': syncState.trim().isEmpty ? 'local_only' : syncState.trim(),
      'deleted_local': deletedLocal ? 1 : 0,
      'deleted_remote': deletedRemote ? 1 : 0,
      'conflict_details': conflictDetails,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSyncRecordRemoteIdentity({
    required String recordUuid,
    required String remoteId,
    String remoteParentId = '',
    String remoteEtag = '',
    int remoteModifiedMilliseconds = 0,
  }) async {
    final database = await this.database;
    await database.update(
      'sync_records',
      {
        'remote_id': remoteId.trim(),
        'remote_parent_id': remoteParentId.trim(),
        'remote_etag': remoteEtag.trim(),
        'remote_modified_milliseconds': remoteModifiedMilliseconds,
      },
      where: 'record_uuid = ?',
      whereArgs: [recordUuid.trim()],
    );
  }

  Future<List<Map<String, Object?>>> getSyncRecords({
    String? state,
    String? entityType,
    String? sourceId,
  }) async {
    final database = await this.database;
    final where = <String>[];
    final args = <Object?>[];

    if (state != null && state.trim().isNotEmpty) {
      where.add('sync_state = ?');
      args.add(state.trim());
    }
    if (entityType != null && entityType.trim().isNotEmpty) {
      where.add('entity_type = ?');
      args.add(entityType.trim().toLowerCase());
    }
    if (sourceId != null && sourceId.trim().isNotEmpty) {
      where.add('source_id = ?');
      args.add(sourceId.trim());
    }

    return database.query(
      'sync_records',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'local_modified_milliseconds DESC, id DESC',
    );
  }

  Future<void> markSyncRecordLocalChanged({
    required String entityType,
    required String localKey,
    int? localModifiedMilliseconds,
  }) async {
    final database = await this.database;
    await database.update(
      'sync_records',
      {
        'sync_state': 'local_changed',
        'local_modified_milliseconds':
            localModifiedMilliseconds ?? DateTime.now().millisecondsSinceEpoch,
      },
      where: 'entity_type = ? AND local_key = ?',
      whereArgs: [entityType.trim().toLowerCase(), localKey.trim()],
    );
  }

  Future<void> recordSyncChange({
    required String changeUuid,
    required String deviceId,
    required String entityType,
    required String localKey,
    required String operation,
    String payloadHash = '',
    String detailsJson = '{}',
    int? changedAtMilliseconds,
  }) async {
    final database = await this.database;
    await database.insert('sync_change_log', {
      'change_uuid': changeUuid.trim(),
      'device_id': deviceId.trim(),
      'entity_type': entityType.trim().toLowerCase(),
      'local_key': localKey.trim(),
      'operation': operation.trim().toLowerCase(),
      'changed_at_milliseconds':
          changedAtMilliseconds ?? DateTime.now().millisecondsSinceEpoch,
      'payload_hash': payloadHash.trim(),
      'details_json': detailsJson.trim().isEmpty ? '{}' : detailsJson.trim(),
      'reviewed': 0,
      'processed': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> recordOrMergePendingSyncChange({
    required String changeUuid,
    required String deviceId,
    required String entityType,
    required String localKey,
    required String operation,
    String payloadHash = '',
    String detailsJson = '{}',
    int? changedAtMilliseconds,
  }) async {
    final database = await this.database;
    final cleanEntityType = entityType.trim().toLowerCase();
    final cleanLocalKey = localKey.trim();
    final cleanOperation = operation.trim().toLowerCase();
    final changedAt =
        changedAtMilliseconds ?? DateTime.now().millisecondsSinceEpoch;

    await database.transaction((txn) async {
      final existing = await txn.query(
        'sync_change_log',
        where:
            'processed = 0 AND entity_type = ? AND local_key = ? AND operation = ?',
        whereArgs: [cleanEntityType, cleanLocalKey, cleanOperation],
        orderBy: 'changed_at_milliseconds ASC, id ASC',
      );

      if (existing.isEmpty) {
        await txn.insert('sync_change_log', {
          'change_uuid': changeUuid.trim(),
          'device_id': deviceId.trim(),
          'entity_type': cleanEntityType,
          'local_key': cleanLocalKey,
          'operation': cleanOperation,
          'changed_at_milliseconds': changedAt,
          'payload_hash': payloadHash.trim(),
          'details_json': detailsJson.trim().isEmpty
              ? '{}'
              : detailsJson.trim(),
          'reviewed': 0,
          'processed': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return;
      }

      final mergedFields = <String>{};

      void addFieldsFromJson(Object? rawValue) {
        final raw = rawValue?.toString().trim() ?? '';
        if (raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final fields = decoded['changed_fields'];
            if (fields is List) {
              for (final field in fields) {
                final clean = field.toString().trim();
                if (clean.isNotEmpty) mergedFields.add(clean);
              }
            }
          }
        } catch (_) {
          // Preserve the pending change even if an older details payload is bad.
        }
      }

      for (final row in existing) {
        addFieldsFromJson(row['details_json']);
      }
      addFieldsFromJson(detailsJson);

      final sortedFields = mergedFields.toList()..sort();
      final keeperId = existing.first['id'];

      await txn.update(
        'sync_change_log',
        {
          'device_id': deviceId.trim(),
          'changed_at_milliseconds': changedAt,
          'payload_hash': payloadHash.trim(),
          'details_json': jsonEncode({'changed_fields': sortedFields}),
          // A fresh edit means the combined pending item needs review again.
          'reviewed': 0,
          'processed': 0,
        },
        where: 'id = ?',
        whereArgs: [keeperId],
      );

      if (existing.length > 1) {
        final duplicateIds = existing
            .skip(1)
            .map((row) => row['id'])
            .where((id) => id != null)
            .toList();
        if (duplicateIds.isNotEmpty) {
          final placeholders = List.filled(duplicateIds.length, '?').join(', ');
          await txn.delete(
            'sync_change_log',
            where: 'id IN ($placeholders)',
            whereArgs: duplicateIds,
          );
        }
      }
    });
  }

  Future<List<Map<String, Object?>>> getPendingSyncChanges({
    int limit = 500,
  }) async {
    final database = await this.database;
    return database.query(
      'sync_change_log',
      where: 'processed = 0',
      orderBy: 'changed_at_milliseconds ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> markSyncChangeReviewed(String changeUuid) async {
    final database = await this.database;
    await database.update(
      'sync_change_log',
      {'reviewed': 1},
      where: 'change_uuid = ?',
      whereArgs: [changeUuid.trim()],
    );
  }

  Future<void> markSyncChangeProcessed(String changeUuid) async {
    final database = await this.database;
    await database.update(
      'sync_change_log',
      {'processed': 1},
      where: 'change_uuid = ?',
      whereArgs: [changeUuid.trim()],
    );
  }

  Future<int> recordSyncConflict({
    required String entityType,
    required String localKey,
    String sourceId = '',
    int localModifiedMilliseconds = 0,
    int remoteModifiedMilliseconds = 0,
    String details = '',
  }) async {
    final database = await this.database;
    return database.insert('sync_conflicts', {
      'entity_type': entityType.trim().toLowerCase(),
      'local_key': localKey.trim(),
      'source_id': sourceId.trim(),
      'local_modified_milliseconds': localModifiedMilliseconds,
      'remote_modified_milliseconds': remoteModifiedMilliseconds,
      'status': 'open',
      'details': details,
      'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      'resolved_at_milliseconds': 0,
    });
  }

  Future<List<Map<String, Object?>>> getOpenSyncConflicts() async {
    final database = await this.database;
    return database.query(
      'sync_conflicts',
      where: "status = 'open'",
      orderBy: 'created_at_milliseconds DESC, id DESC',
    );
  }

  Future<void> resolveSyncConflict({
    required int conflictId,
    required String resolution,
  }) async {
    final database = await this.database;
    await database.update(
      'sync_conflicts',
      {
        'status': resolution.trim().isEmpty ? 'resolved' : resolution.trim(),
        'resolved_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conflictId],
    );
  }

  Future<Map<String, int>> getSyncFoundationSummary() async {
    final database = await this.database;

    Future<int> count(String table, {String? where}) async {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM $table'
        '${where == null ? '' : ' WHERE $where'}',
      );
      return _mapInt(rows.first['total']);
    }

    return {
      'devices': await count('sync_devices'),
      'connected_sources': await count('connected_sources'),
      'sync_records': await count('sync_records'),
      'pending_changes': await count('sync_change_log', where: 'processed = 0'),
      'open_conflicts': await count('sync_conflicts', where: "status = 'open'"),
    };
  }

  static Future<void> _createPhotoPersonFamilyLinksTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_person_family_links (
        person_name TEXT PRIMARY KEY COLLATE NOCASE,
        family_person_id INTEGER NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS photo_person_family_links_family_index
      ON photo_person_family_links(family_person_id)
    ''');
  }

  Future<void> setFamilyTreeLinkForPhotoPerson({
    required String personName,
    required int familyPersonId,
  }) async {
    final cleanName = personName.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('A photo person name is required.');
    }

    final database = await this.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await database.query(
      'photo_person_family_links',
      columns: ['created_at_milliseconds'],
      where: 'person_name = ? COLLATE NOCASE',
      whereArgs: [cleanName],
      limit: 1,
    );

    await database.insert('photo_person_family_links', {
      'person_name': cleanName,
      'family_person_id': familyPersonId,
      'created_at_milliseconds': existing.isEmpty
          ? now
          : _mapInt(existing.first['created_at_milliseconds']),
      'updated_at_milliseconds': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, int>> getPhotoPersonFamilyTreeLinks() async {
    final database = await this.database;
    final rows = await database.query('photo_person_family_links');
    final result = <String, int>{};
    for (final row in rows) {
      final name = row['person_name'] as String? ?? '';
      if (name.isNotEmpty) {
        result[name] = _mapInt(row['family_person_id']);
      }
    }
    return result;
  }

  Future<void> removeFamilyTreeLinkForPhotoPerson(String personName) async {
    final database = await this.database;
    await database.delete(
      'photo_person_family_links',
      where: 'person_name = ? COLLATE NOCASE',
      whereArgs: [personName.trim()],
    );
  }

  static Future<void> _createPhotoPersonAliasesTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_person_aliases (
        alias_name TEXT PRIMARY KEY COLLATE NOCASE,
        family_person_id INTEGER NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS photo_person_aliases_family_index
      ON photo_person_aliases(family_person_id)
    ''');
  }

  Future<void> setPhotoPersonAlias({
    required String aliasName,
    required int familyPersonId,
  }) async {
    final cleanName = aliasName.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('A photo person alias is required.');
    }

    final database = await this.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await database.query(
      'photo_person_aliases',
      columns: ['created_at_milliseconds'],
      where: 'alias_name = ? COLLATE NOCASE',
      whereArgs: [cleanName],
      limit: 1,
    );

    await database.insert('photo_person_aliases', {
      'alias_name': cleanName,
      'family_person_id': familyPersonId,
      'created_at_milliseconds': existing.isEmpty
          ? now
          : _mapInt(existing.first['created_at_milliseconds']),
      'updated_at_milliseconds': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await setFamilyTreeLinkForPhotoPerson(
      personName: cleanName,
      familyPersonId: familyPersonId,
    );
  }

  Future<Map<String, int>> getPhotoPersonAliases() async {
    final database = await this.database;
    final rows = await database.query('photo_person_aliases');
    final result = <String, int>{};
    for (final row in rows) {
      final alias = row['alias_name'] as String? ?? '';
      if (alias.isNotEmpty) {
        result[alias] = _mapInt(row['family_person_id']);
      }
    }
    return result;
  }

  Future<List<String>> getPhotoPersonAliasesForFamilyPerson(
    int familyPersonId,
  ) async {
    final database = await this.database;
    final rows = await database.query(
      'photo_person_aliases',
      columns: ['alias_name'],
      where: 'family_person_id = ?',
      whereArgs: [familyPersonId],
      orderBy: 'alias_name COLLATE NOCASE',
    );
    return rows
        .map((row) => row['alias_name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> removePhotoPersonAlias(String aliasName) async {
    final cleanName = aliasName.trim();
    if (cleanName.isEmpty) return;

    final database = await this.database;
    await database.delete(
      'photo_person_aliases',
      where: 'alias_name = ? COLLATE NOCASE',
      whereArgs: [cleanName],
    );
    await removeFamilyTreeLinkForPhotoPerson(cleanName);
  }

  Future<int?> resolveFamilyPersonIdForPhotoName(String personName) async {
    final cleanName = personName.trim();
    if (cleanName.isEmpty) return null;

    final database = await this.database;
    final aliasRows = await database.query(
      'photo_person_aliases',
      columns: ['family_person_id'],
      where: 'alias_name = ? COLLATE NOCASE',
      whereArgs: [cleanName],
      limit: 1,
    );
    if (aliasRows.isNotEmpty) {
      return _mapInt(aliasRows.first['family_person_id']);
    }

    final linkRows = await database.query(
      'photo_person_family_links',
      columns: ['family_person_id'],
      where: 'person_name = ? COLLATE NOCASE',
      whereArgs: [cleanName],
      limit: 1,
    );
    if (linkRows.isNotEmpty) {
      return _mapInt(linkRows.first['family_person_id']);
    }

    return null;
  }

  Future<Map<int, List<String>>> getPhotoAliasesGroupedByFamilyPerson() async {
    final database = await this.database;
    final rows = await database.rawQuery('''
      SELECT alias_name, family_person_id
      FROM photo_person_aliases
      ORDER BY family_person_id, alias_name COLLATE NOCASE
    ''');

    final result = <int, List<String>>{};
    for (final row in rows) {
      final familyId = _mapInt(row['family_person_id']);
      final alias = row['alias_name'] as String? ?? '';
      if (familyId > 0 && alias.isNotEmpty) {
        result.putIfAbsent(familyId, () => <String>[]).add(alias);
      }
    }
    return result;
  }

  static Future<void> _createPersonGroupsTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS person_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS person_groups_name_index
      ON person_groups(name COLLATE NOCASE)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS person_group_people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        person_name TEXT NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS person_group_people_unique_index
      ON person_group_people(group_id, person_name COLLATE NOCASE)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS person_group_people_name_index
      ON person_group_people(person_name COLLATE NOCASE)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS person_group_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        photo_file_path TEXT NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        UNIQUE(group_id, photo_file_path)
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS person_group_photos_group_index
      ON person_group_photos(group_id)
    ''');
  }

  Future<int> createPersonGroup({
    required String name,
    Iterable<String> personNames = const [],
    Iterable<String> photoFilePaths = const [],
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('A group name is required.');
    }

    final database = await this.database;
    return database.transaction((transaction) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final groupId = await transaction.insert('person_groups', {
        'name': cleanName,
        'created_at_milliseconds': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      for (final personName
          in personNames
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()) {
        await transaction.insert('person_group_people', {
          'group_id': groupId,
          'person_name': personName,
          'created_at_milliseconds': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final filePath
          in photoFilePaths
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()) {
        await transaction.insert('person_group_photos', {
          'group_id': groupId,
          'photo_file_path': filePath,
          'created_at_milliseconds': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      return groupId;
    });
  }

  Future<List<Map<String, Object?>>> getPersonGroups() async {
    final database = await this.database;
    return database.rawQuery('''
      SELECT
        g.id,
        g.name,
        g.created_at_milliseconds,
        (SELECT COUNT(*) FROM person_group_people p
         WHERE p.group_id = g.id) AS people_count,
        (SELECT COUNT(*) FROM person_group_photos ph
         WHERE ph.group_id = g.id) AS photo_count
      FROM person_groups g
      ORDER BY g.name COLLATE NOCASE
    ''');
  }

  Future<List<String>> getPersonNamesForGroup(int groupId) async {
    final database = await this.database;
    final rows = await database.query(
      'person_group_people',
      columns: ['person_name'],
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'person_name COLLATE NOCASE',
    );
    return rows
        .map((row) => row['person_name'] as String? ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<List<String>> getPhotoPathsForPersonGroup(int groupId) async {
    final database = await this.database;
    final rows = await database.query(
      'person_group_photos',
      columns: ['photo_file_path'],
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at_milliseconds ASC, id ASC',
    );
    return rows
        .map((row) => row['photo_file_path'] as String? ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> replacePersonGroupPeople({
    required int groupId,
    required Iterable<String> personNames,
  }) async {
    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'person_group_people',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final personName
          in personNames
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()) {
        await transaction.insert('person_group_people', {
          'group_id': groupId,
          'person_name': personName,
          'created_at_milliseconds': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> replacePersonGroupPhotos({
    required int groupId,
    required Iterable<String> photoFilePaths,
  }) async {
    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'person_group_photos',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final filePath
          in photoFilePaths
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()) {
        await transaction.insert('person_group_photos', {
          'group_id': groupId,
          'photo_file_path': filePath,
          'created_at_milliseconds': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> renamePersonGroup({
    required int groupId,
    required String name,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('A group name is required.');
    }
    final database = await this.database;
    await database.update(
      'person_groups',
      {'name': cleanName},
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  Future<void> deletePersonGroup(int groupId) async {
    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'person_group_people',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      await transaction.delete(
        'person_group_photos',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      await transaction.delete(
        'person_groups',
        where: 'id = ?',
        whereArgs: [groupId],
      );
    });
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
        notes TEXT NOT NULL DEFAULT '',
        image_path TEXT NOT NULL DEFAULT ''
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
    await database.execute('ALTER TABLE imported_coins ADD COLUMN value REAL');
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

    return database.update('postcards', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletePostcard(int id) async {
    final database = await this.database;
    return database.delete('postcards', where: 'id = ?', whereArgs: [id]);
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
        notes TEXT NOT NULL DEFAULT '',
        condition TEXT NOT NULL DEFAULT '',
        condition_notes TEXT NOT NULL DEFAULT '',
        provenance TEXT NOT NULL DEFAULT '',
        appraisal_source TEXT NOT NULL DEFAULT '',
        valuation_date TEXT NOT NULL DEFAULT ''
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

    await database.execute('''
      CREATE TABLE IF NOT EXISTS valuable_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        valuable_id INTEGER NOT NULL,
        document_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _upgradeValuablesToVersion35(Database database) async {
    final info = await database.rawQuery("PRAGMA table_info(valuables)");
    final columns = info.map((row) => row['name'] as String? ?? '').toSet();

    Future<void> addColumn(String name, String definition) async {
      if (!columns.contains(name)) {
        await database.execute(
          'ALTER TABLE valuables ADD COLUMN $name $definition',
        );
      }
    }

    await addColumn('condition', "TEXT NOT NULL DEFAULT ''");
    await addColumn('condition_notes', "TEXT NOT NULL DEFAULT ''");
    await addColumn('provenance', "TEXT NOT NULL DEFAULT ''");
    await addColumn('appraisal_source', "TEXT NOT NULL DEFAULT ''");
    await addColumn('valuation_date', "TEXT NOT NULL DEFAULT ''");

    await database.execute('''
      CREATE TABLE IF NOT EXISTS valuable_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        valuable_id INTEGER NOT NULL,
        document_path TEXT NOT NULL,
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
        await transaction.insert('valuable_images', {
          'valuable_id': id,
          'image_path': valuable.imagePaths[index],
          'sort_order': index,
        });
      }

      for (
        var index = 0;
        index < valuable.supportingDocumentPaths.length;
        index++
      ) {
        await transaction.insert('valuable_documents', {
          'valuable_id': id,
          'document_path': valuable.supportingDocumentPaths[index],
          'sort_order': index,
        });
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
      await transaction.delete(
        'valuable_documents',
        where: 'valuable_id = ?',
        whereArgs: [id],
      );

      for (var index = 0; index < valuable.imagePaths.length; index++) {
        await transaction.insert('valuable_images', {
          'valuable_id': id,
          'image_path': valuable.imagePaths[index],
          'sort_order': index,
        });
      }

      for (
        var index = 0;
        index < valuable.supportingDocumentPaths.length;
        index++
      ) {
        await transaction.insert('valuable_documents', {
          'valuable_id': id,
          'document_path': valuable.supportingDocumentPaths[index],
          'sort_order': index,
        });
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
      await transaction.delete(
        'valuable_documents',
        where: 'valuable_id = ?',
        whereArgs: [id],
      );

      return transaction.delete('valuables', where: 'id = ?', whereArgs: [id]);
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

      final documentRows = id == null
          ? <Map<String, Object?>>[]
          : await database.query(
              'valuable_documents',
              where: 'valuable_id = ?',
              whereArgs: [id],
              orderBy: 'sort_order ASC, id ASC',
            );
      final documentPaths = documentRows
          .map((row) => row['document_path'] as String? ?? '')
          .where((value) => value.isNotEmpty)
          .toList();

      result.add(
        Valuable.fromMap(
          row,
          imagePaths: imagePaths,
          supportingDocumentPaths: documentPaths,
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
        notes TEXT NOT NULL DEFAULT '',
        condition TEXT NOT NULL DEFAULT '',
        condition_notes TEXT NOT NULL DEFAULT '',
        provenance TEXT NOT NULL DEFAULT '',
        appraisal_source TEXT NOT NULL DEFAULT '',
        valuation_date TEXT NOT NULL DEFAULT ''
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

  static Future<void> _upgradeAntiquesToVersion34(Database database) async {
    final info = await database.rawQuery("PRAGMA table_info(antiques)");
    final columns = info.map((row) => row['name'] as String? ?? '').toSet();

    Future<void> addColumn(String name, String definition) async {
      if (!columns.contains(name)) {
        await database.execute(
          'ALTER TABLE antiques ADD COLUMN $name $definition',
        );
      }
    }

    await addColumn('condition', "TEXT NOT NULL DEFAULT ''");
    await addColumn('condition_notes', "TEXT NOT NULL DEFAULT ''");
    await addColumn('provenance', "TEXT NOT NULL DEFAULT ''");
    await addColumn('appraisal_source', "TEXT NOT NULL DEFAULT ''");
    await addColumn('valuation_date', "TEXT NOT NULL DEFAULT ''");

    await database.execute('''
      CREATE TABLE IF NOT EXISTS antique_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        antique_id INTEGER NOT NULL,
        document_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS antique_documents_antique_index
      ON antique_documents(antique_id)
    ''');
  }

  Future<int> insertAntique(Antique antique) async {
    final database = await this.database;

    return database.transaction((transaction) async {
      final map = antique.toMap();
      map.remove('id');

      final id = await transaction.insert('antiques', map);

      for (var index = 0; index < antique.imagePaths.length; index++) {
        await transaction.insert('antique_images', {
          'antique_id': id,
          'image_path': antique.imagePaths[index],
          'sort_order': index,
        });
      }

      for (
        var index = 0;
        index < antique.supportingDocumentPaths.length;
        index++
      ) {
        await transaction.insert('antique_documents', {
          'antique_id': id,
          'document_path': antique.supportingDocumentPaths[index],
          'sort_order': index,
        });
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
      await transaction.delete(
        'antique_documents',
        where: 'antique_id = ?',
        whereArgs: [id],
      );

      for (var index = 0; index < antique.imagePaths.length; index++) {
        await transaction.insert('antique_images', {
          'antique_id': id,
          'image_path': antique.imagePaths[index],
          'sort_order': index,
        });
      }

      for (
        var index = 0;
        index < antique.supportingDocumentPaths.length;
        index++
      ) {
        await transaction.insert('antique_documents', {
          'antique_id': id,
          'document_path': antique.supportingDocumentPaths[index],
          'sort_order': index,
        });
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
      await transaction.delete(
        'antique_documents',
        where: 'antique_id = ?',
        whereArgs: [id],
      );

      return transaction.delete('antiques', where: 'id = ?', whereArgs: [id]);
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

      final documentRows = id == null
          ? <Map<String, Object?>>[]
          : await database.query(
              'antique_documents',
              where: 'antique_id = ?',
              whereArgs: [id],
              orderBy: 'sort_order ASC, id ASC',
            );
      final documentPaths = documentRows
          .map((documentRow) => documentRow['document_path'] as String? ?? '')
          .where((value) => value.isNotEmpty)
          .toList();

      result.add(
        Antique.fromMap(
          row,
          imagePaths: imagePaths,
          supportingDocumentPaths: documentPaths,
        ),
      );
    }

    return result;
  }

  static Future<void> _createAtlasBookFavoritesTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS atlas_book_favorites (
        item_type TEXT NOT NULL,
        item_key TEXT NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (item_type, item_key)
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS atlas_book_favorites_type_index
      ON atlas_book_favorites(item_type)
    ''');
  }

  Future<void> setAtlasBookFavorite({
    required String itemType,
    required String itemKey,
    required bool favorite,
  }) async {
    final cleanType = itemType.trim().toLowerCase();
    final cleanKey = itemKey.trim();
    if (cleanType.isEmpty || cleanKey.isEmpty) return;

    final database = await this.database;
    if (!favorite) {
      await database.delete(
        'atlas_book_favorites',
        where: 'item_type = ? AND item_key = ?',
        whereArgs: [cleanType, cleanKey],
      );
      return;
    }

    await database.insert('atlas_book_favorites', {
      'item_type': cleanType,
      'item_key': cleanKey,
      'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> isAtlasBookFavorite({
    required String itemType,
    required String itemKey,
  }) async {
    final database = await this.database;
    final rows = await database.query(
      'atlas_book_favorites',
      columns: ['item_key'],
      where: 'item_type = ? AND item_key = ?',
      whereArgs: [itemType.trim().toLowerCase(), itemKey.trim()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> getAtlasBookFavoriteKeys({String? itemType}) async {
    final database = await this.database;
    final cleanType = itemType?.trim().toLowerCase() ?? '';
    final rows = await database.query(
      'atlas_book_favorites',
      columns: ['item_key'],
      where: cleanType.isEmpty ? null : 'item_type = ?',
      whereArgs: cleanType.isEmpty ? null : [cleanType],
      orderBy: 'created_at_milliseconds DESC',
    );
    return rows
        .map((row) => row['item_key'] as String? ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  static Future<void> _createPersonMatchRejectionsTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS person_match_rejections (
        person_name TEXT NOT NULL,
        face_id INTEGER NOT NULL,
        rejected_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (person_name, face_id)
      )
    ''');
  }

  Future<Set<int>> getRejectedFaceIdsForPerson(String personName) async {
    final database = await this.database;
    final rows = await database.query(
      'person_match_rejections',
      columns: ['face_id'],
      where: 'person_name = ?',
      whereArgs: [personName.trim()],
    );

    return rows
        .map((row) => _mapInt(row['face_id']))
        .where((id) => id > 0)
        .toSet();
  }

  Future<void> rejectFaceMatch({
    required String personName,
    required int faceId,
  }) async {
    final database = await this.database;
    await database.insert('person_match_rejections', {
      'person_name': personName.trim(),
      'face_id': faceId,
      'rejected_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearFaceMatchRejection({
    required String personName,
    required int faceId,
  }) async {
    final database = await this.database;
    await database.delete(
      'person_match_rejections',
      where: 'person_name = ? AND face_id = ?',
      whereArgs: [personName.trim(), faceId],
    );
  }

  static Future<void> _createPhotoSourcesTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_type TEXT NOT NULL DEFAULT 'folder',
        display_name TEXT NOT NULL DEFAULT '',
        root_path TEXT NOT NULL UNIQUE,
        last_scan_milliseconds INTEGER NOT NULL DEFAULT 0,
        photo_count INTEGER NOT NULL DEFAULT 0,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS photo_source_files (
        file_path TEXT PRIMARY KEY,
        source_id INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS photo_source_files_source_index
      ON photo_source_files(source_id)
    ''');
  }

  static Future<void> _migrateLegacyPhotoSource(Database database) async {
    final rows = await database.query('app_settings');
    final settings = <String, String>{
      for (final row in rows)
        (row['setting_key'] as String? ?? ''):
            (row['setting_value'] as String? ?? ''),
    };

    final rootPath = settings['photo_library_path']?.trim() ?? '';
    if (rootPath.isEmpty) return;

    final savedType = settings['photo_source_type']?.trim() ?? '';
    final sourceType = savedType.isNotEmpty
        ? savedType
        : (rootPath.toLowerCase().contains('onedrive') ? 'onedrive' : 'folder');
    final savedName = settings['photo_source_name']?.trim() ?? '';
    final displayName = savedName.isNotEmpty
        ? savedName
        : (sourceType == 'onedrive' ? 'OneDrive' : 'Existing Photo Library');
    final lastScan =
        int.tryParse(settings['photo_source_last_scan_milliseconds'] ?? '') ??
        0;

    var sourceId = await database.insert('photo_sources', {
      'source_type': sourceType,
      'display_name': displayName,
      'root_path': rootPath,
      'last_scan_milliseconds': lastScan,
      'photo_count': 0,
      'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    if (sourceId == 0) {
      final existing = await database.query(
        'photo_sources',
        columns: ['id'],
        where: 'root_path = ?',
        whereArgs: [rootPath],
        limit: 1,
      );
      if (existing.isEmpty) return;
      sourceId = _staticMapInt(existing.first['id']);
    }

    final photoRows = await database.query(
      'indexed_photos',
      columns: ['file_path'],
    );
    var count = 0;
    final batch = database.batch();
    for (final row in photoRows) {
      final filePath = row['file_path'] as String? ?? '';
      if (filePath.isEmpty) continue;
      if (!path.isWithin(rootPath, filePath)) continue;
      count++;
      batch.insert('photo_source_files', {
        'file_path': filePath,
        'source_id': sourceId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);

    await database.update(
      'photo_sources',
      {'photo_count': count},
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  Future<List<Map<String, Object?>>> getPhotoSources() async {
    final database = await this.database;
    return database.query(
      'photo_sources',
      orderBy: 'created_at_milliseconds ASC, id ASC',
    );
  }

  Future<bool> removePhotoSourceByRootPath(String rootPath) async {
    final cleanPath = rootPath.trim();
    if (cleanPath.isEmpty) return false;

    final sources = await getPhotoSources();
    for (final source in sources) {
      final sourcePath = (source['root_path'] as String? ?? '').trim();
      if (sourcePath.toLowerCase() != cleanPath.toLowerCase()) continue;

      final sourceId = source['id'] as int? ?? 0;
      if (sourceId <= 0) continue;

      await removePhotoSource(sourceId);
      return true;
    }

    return false;
  }

  Future<void> removePhotoSource(int sourceId) async {
    if (sourceId <= 0) {
      throw ArgumentError('A valid photo source ID is required.');
    }

    final database = await this.database;
    await database.transaction((transaction) async {
      final mappings = await transaction.query(
        'photo_source_files',
        columns: ['file_path'],
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );

      final mappedPaths = mappings
          .map((row) => row['file_path'] as String? ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();

      await transaction.delete(
        'photo_source_files',
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );

      for (final filePath in mappedPaths) {
        final otherMapping = await transaction.query(
          'photo_source_files',
          columns: ['file_path'],
          where: 'file_path = ?',
          whereArgs: [filePath],
          limit: 1,
        );
        if (otherMapping.isEmpty) {
          await transaction.delete(
            'indexed_photos',
            where: 'file_path = ?',
            whereArgs: [filePath],
          );
        }
      }

      await transaction.delete(
        'photo_sources',
        where: 'id = ?',
        whereArgs: [sourceId],
      );
    });
  }

  Future<int> addPhotoSource({
    required String sourceType,
    required String displayName,
    required String rootPath,
  }) async {
    final database = await this.database;
    final cleanPath = rootPath.trim();
    final existing = await database.query(
      'photo_sources',
      columns: ['id'],
      where: 'root_path = ?',
      whereArgs: [cleanPath],
      limit: 1,
    );
    if (existing.isNotEmpty) return _mapInt(existing.first['id']);

    return database.insert('photo_sources', {
      'source_type': sourceType.trim(),
      'display_name': displayName.trim(),
      'root_path': cleanPath,
      'last_scan_milliseconds': 0,
      'photo_count': 0,
      'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> replaceIndexedPhotosForSource({
    required int sourceId,
    required List<VaultPhoto> photos,
  }) async {
    final database = await this.database;
    await database.transaction((transaction) async {
      final oldMappings = await transaction.query(
        'photo_source_files',
        columns: ['file_path'],
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );
      final oldPaths = oldMappings
          .map((row) => row['file_path'] as String? ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();
      final newPaths = photos.map((photo) => photo.filePath).toSet();

      for (final removedPath in oldPaths.difference(newPaths)) {
        await transaction.delete(
          'photo_source_files',
          where: 'file_path = ? AND source_id = ?',
          whereArgs: [removedPath, sourceId],
        );
        final otherMapping = await transaction.query(
          'photo_source_files',
          columns: ['file_path'],
          where: 'file_path = ?',
          whereArgs: [removedPath],
          limit: 1,
        );
        if (otherMapping.isEmpty) {
          await transaction.delete(
            'indexed_photos',
            where: 'file_path = ?',
            whereArgs: [removedPath],
          );
        }
      }

      for (final photo in photos) {
        final map = photo.toMap()..remove('id');
        await transaction.insert(
          'indexed_photos',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await transaction.insert('photo_source_files', {
          'file_path': photo.filePath,
          'source_id': sourceId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await transaction.update(
        'photo_sources',
        {
          'photo_count': photos.length,
          'last_scan_milliseconds': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [sourceId],
      );
    });
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
    await database.insert('app_settings', {
      'setting_key': key,
      'setting_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  static Future<void> _createPhotoFingerprintTable(Database database) async {
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
    await database.insert('photo_fingerprints', {
      'file_path': filePath,
      'file_size': fileSize,
      'modified_milliseconds': modifiedMilliseconds,
      'hash_hex': hashHex,
      'average_r': averageR,
      'average_g': averageG,
      'average_b': averageB,
      'analyzed_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
        back_writing TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<PhotoCatalogMetadata> getPhotoCatalogMetadata(String filePath) async {
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

  Future<void> savePhotoCatalogMetadata(PhotoCatalogMetadata metadata) async {
    final database = await this.database;
    await database.insert(
      'photo_catalog_metadata',
      metadata.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _upgradePhotoFacesForSFace(Database database) async {
    final tableInfo = await database.rawQuery("PRAGMA table_info(photo_faces)");
    final columns = tableInfo
        .map((row) => row['name'] as String? ?? '')
        .toSet();

    // Existing identity/review fields are deliberately untouched.
    if (!columns.contains('sface_embedding_json')) {
      await database.execute(
        "ALTER TABLE photo_faces ADD COLUMN sface_embedding_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (!columns.contains('sface_embedding_version')) {
      await database.execute(
        "ALTER TABLE photo_faces ADD COLUMN sface_embedding_version INTEGER NOT NULL DEFAULT 0",
      );
    }
    if (!columns.contains('sface_embedded_at_milliseconds')) {
      await database.execute(
        "ALTER TABLE photo_faces ADD COLUMN sface_embedded_at_milliseconds INTEGER NOT NULL DEFAULT 0",
      );
    }
  }

  Future<void> saveSFaceEmbedding({
    required int faceId,
    required String embeddingJson,
    int embeddingVersion = 1,
  }) async {
    final database = await this.database;
    await database.update(
      'photo_faces',
      {
        'sface_embedding_json': embeddingJson,
        'sface_embedding_version': embeddingVersion,
        'sface_embedded_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [faceId],
    );
  }

  Future<List<Map<String, Object?>>> getFacesMissingSFaceEmbeddings({
    int? limit,
  }) async {
    final database = await this.database;
    return database.query(
      'photo_faces',
      where: "sface_embedding_json = '[]'",
      orderBy: 'confirmed DESC, person_name COLLATE NOCASE, id ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, Object?>>> getAllSFaceEmbeddingRows() async {
    final database = await this.database;
    return database.query(
      'photo_faces',
      columns: ['id', 'person_name', 'confirmed', 'sface_embedding_json'],
      where: "sface_embedding_json <> '[]'",
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, Object?>>> getIndexedSFaceRecoveryRows({
    required int excludeFaceId,
  }) async {
    final database = await this.database;
    return database.rawQuery(
      '''
      SELECT f.id, f.photo_file_path, f.face_index, f.person_name,
             f.confirmed, f.sface_embedding_json
      FROM photo_faces f
      INNER JOIN indexed_photos p ON p.file_path = f.photo_file_path
      WHERE f.id <> ?
        AND f.sface_embedding_json <> '[]'
      ORDER BY f.id ASC
      ''',
      [excludeFaceId],
    );
  }

  Future<int> getFacesMissingSFaceEmbeddingCount() async {
    final database = await this.database;
    final rows = await database.rawQuery(
      "SELECT COUNT(*) AS total FROM photo_faces WHERE sface_embedding_json = '[]'",
    );
    return _mapInt(rows.first['total']);
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
        sface_embedding_json TEXT NOT NULL DEFAULT '[]',
        sface_embedding_version INTEGER NOT NULL DEFAULT 0,
        sface_embedded_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        thumbnail_path TEXT NOT NULL DEFAULT '',
        person_name TEXT NOT NULL DEFAULT '',
        confirmed INTEGER NOT NULL DEFAULT 0,
        review_status TEXT NOT NULL DEFAULT 'pending',
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

  /// Repairs stale photo paths stored on face records when the old file no
  /// longer exists and exactly one currently indexed photo has the same
  /// filename. Ambiguous filenames are deliberately left unchanged.
  Future<int> repairStaleFacePhotoPaths() async {
    final database = await this.database;

    final faceRows = await database.query(
      'photo_faces',
      columns: ['id', 'photo_file_path', 'face_index'],
    );
    if (faceRows.isEmpty) return 0;

    final indexedRows = await database.query(
      'indexed_photos',
      columns: ['file_path', 'file_name'],
    );

    final indexedByName = <String, List<String>>{};
    for (final row in indexedRows) {
      final filePath = (row['file_path'] as String? ?? '').trim();
      var fileName = (row['file_name'] as String? ?? '').trim();
      if (filePath.isEmpty) continue;

      if (fileName.isEmpty) {
        fileName = filePath.replaceAll('\\', '/').split('/').last;
      }
      if (fileName.isEmpty) continue;

      indexedByName
          .putIfAbsent(fileName.toLowerCase(), () => <String>[])
          .add(filePath);
    }

    var repaired = 0;

    await database.transaction((transaction) async {
      for (final row in faceRows) {
        final id = row['id'];
        final oldPath = (row['photo_file_path'] as String? ?? '').trim();
        if (id is! int || oldPath.isEmpty) continue;

        if (await File(oldPath).exists()) continue;

        final oldName = oldPath
            .replaceAll('\\', '/')
            .split('/')
            .last
            .toLowerCase();
        if (oldName.isEmpty) continue;

        final matches = indexedByName[oldName] ?? const <String>[];
        if (matches.length != 1) continue;

        final newPath = matches.single;
        if (newPath == oldPath || !await File(newPath).exists()) continue;

        // Never overwrite another face record that already occupies the
        // destination photo/face-index pair.
        final faceIndex = _mapInt(row['face_index']);
        final conflict = await transaction.query(
          'photo_faces',
          columns: ['id'],
          where: 'photo_file_path = ? AND face_index = ? AND id <> ?',
          whereArgs: [newPath, faceIndex, id],
          limit: 1,
        );
        if (conflict.isNotEmpty) continue;

        final count = await transaction.update(
          'photo_faces',
          {'photo_file_path': newPath},
          where: 'id = ?',
          whereArgs: [id],
        );
        repaired += count;
      }
    });

    return repaired;
  }

  /// Manually reconnects all face records that point to [oldPath] to
  /// [newPath]. Destination conflicts are preserved rather than overwritten.
  Future<int> relinkFacePhotoPath({
    required String oldPath,
    required String newPath,
  }) async {
    final cleanOld = oldPath.trim();
    final cleanNew = newPath.trim();
    if (cleanOld.isEmpty || cleanNew.isEmpty || cleanOld == cleanNew) return 0;

    final database = await this.database;
    var repaired = 0;

    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'photo_faces',
        columns: ['id', 'face_index'],
        where: 'photo_file_path = ?',
        whereArgs: [cleanOld],
        orderBy: 'face_index ASC, id ASC',
      );

      for (final row in rows) {
        final id = row['id'];
        if (id is! int) continue;
        final faceIndex = _mapInt(row['face_index']);

        final conflict = await transaction.query(
          'photo_faces',
          columns: ['id'],
          where: 'photo_file_path = ? AND face_index = ?',
          whereArgs: [cleanNew, faceIndex],
          limit: 1,
        );
        if (conflict.isNotEmpty) continue;

        repaired += await transaction.update(
          'photo_faces',
          {'photo_file_path': cleanNew},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });

    return repaired;
  }

  Future<List<DetectedFaceRecord>> getFacesForPhotoPaths(
    List<String> photoPaths,
  ) async {
    if (photoPaths.isEmpty) return const [];

    final database = await this.database;
    final placeholders = List.filled(photoPaths.length, '?').join(',');

    final rows = await database.rawQuery('''
      SELECT *
      FROM photo_faces
      WHERE photo_file_path IN ($placeholders)
      ORDER BY photo_file_path, face_index
      ''', photoPaths);

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
      SET person_name = ?, confirmed = 1, review_status = 'identified'
      WHERE id IN ($placeholders)
      ''',
      [personName, ...faceIds],
    );
  }

  Future<void> markFaceUnidentified(int faceId) async {
    final database = await this.database;
    await database.update(
      'photo_faces',
      {'person_name': '', 'confirmed': 0, 'review_status': 'pending'},
      where: 'id = ?',
      whereArgs: [faceId],
    );
  }

  Future<void> reassignConfirmedFace({
    required int faceId,
    required String newPersonName,
  }) async {
    final cleanName = newPersonName.trim();
    if (cleanName.isEmpty) return;

    final database = await this.database;
    final faceRows = await database.query(
      'photo_faces',
      where: 'id = ?',
      whereArgs: [faceId],
      limit: 1,
    );
    if (faceRows.isEmpty) return;

    final face = DetectedFaceRecord.fromMap(faceRows.first);
    final oldName = face.personName.trim();

    await database.update(
      'photo_faces',
      {'person_name': cleanName, 'confirmed': 1, 'review_status': 'identified'},
      where: 'id = ?',
      whereArgs: [faceId],
    );

    final metadata = await getPhotoCatalogMetadata(face.photoFilePath);
    final people = metadata.people.toSet()..add(cleanName);

    if (oldName.isNotEmpty && oldName != cleanName) {
      final otherOldFaceRows = await database.query(
        'photo_faces',
        columns: ['id'],
        where:
            'photo_file_path = ? AND confirmed = 1 AND person_name = ? AND id <> ?',
        whereArgs: [face.photoFilePath, oldName, faceId],
        limit: 1,
      );
      if (otherOldFaceRows.isEmpty) people.remove(oldName);
    }

    await savePhotoCatalogMetadata(
      PhotoCatalogMetadata(
        filePath: metadata.filePath,
        people: people.toList(),
        tags: metadata.tags,
        approximateDate: metadata.approximateDate,
        location: metadata.location,
        description: metadata.description,
        backWriting: metadata.backWriting,
        notes: metadata.notes,
      ),
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
      WHERE confirmed = 0 AND review_status <> 'unknown'
    ''');

    return _mapInt(rows.first['total']);
  }

  Future<List<DetectedFaceRecord>> getUnconfirmedFaces() async {
    final database = await this.database;
    final rows = await database.query(
      'photo_faces',
      where: "confirmed = 0 AND review_status <> 'unknown'",
      orderBy: 'photo_file_path, face_index',
    );

    return rows.map(DetectedFaceRecord.fromMap).toList();
  }

  Future<void> markFaceUnknown(int faceId) async {
    final database = await this.database;
    await database.update(
      'photo_faces',
      {'person_name': '', 'confirmed': 0, 'review_status': 'unknown'},
      where: 'id = ?',
      whereArgs: [faceId],
    );
  }

  Future<void> restoreUnknownFace(int faceId) async {
    final database = await this.database;
    await database.update(
      'photo_faces',
      {'review_status': 'pending'},
      where: "id = ? AND review_status = 'unknown'",
      whereArgs: [faceId],
    );
  }

  Future<List<DetectedFaceRecord>> getUnknownFaces() async {
    final database = await this.database;
    final rows = await database.query(
      'photo_faces',
      where: "confirmed = 0 AND review_status = 'unknown'",
      orderBy: 'photo_file_path, face_index',
    );
    return rows.map(DetectedFaceRecord.fromMap).toList();
  }

  Future<int> getUnknownFaceCount() async {
    final database = await this.database;
    final rows = await database.rawQuery('''
      SELECT COUNT(*) AS total
      FROM photo_faces
      WHERE confirmed = 0 AND review_status = 'unknown'
    ''');
    return _mapInt(rows.first['total']);
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

  static Future<void> _createPhotoFaceScanStateTable(Database database) async {
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
        row['file_path'] as String? ?? '': _mapInt(
          row['modified_milliseconds'],
        ),
    };
  }

  Future<void> markPhotoFaceScanned({
    required VaultPhoto photo,
    required int faceCount,
  }) async {
    final database = await this.database;
    await database.insert('photo_face_scan_state', {
      'file_path': photo.filePath,
      'modified_milliseconds': photo.modifiedMilliseconds,
      'scanned_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      'face_count': faceCount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
        row['file_path'] as String? ?? '': _mapInt(
          row['modified_milliseconds'],
        ),
    };
  }

  Future<void> markPhotoMetadataImported(VaultPhoto photo) async {
    final database = await this.database;
    await database.insert('photo_metadata_import_state', {
      'file_path': photo.filePath,
      'modified_milliseconds': photo.modifiedMilliseconds,
      'imported_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _createCustomCollectionsTable(Database database) async {
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
    return database.insert(
      'custom_collections',
      map,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> updateCustomCollection(CustomCollection collection) async {
    final id = collection.id;
    if (id == null) throw ArgumentError('A collection ID is required.');
    final database = await this.database;
    final map = collection.toMap();
    map.remove('id');
    return database.update(
      'custom_collections',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCustomCollection(int id) async {
    final database = await this.database;
    return database.delete(
      'custom_collections',
      where: 'id = ?',
      whereArgs: [id],
    );
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

  Future<int> insertCustomCollectionItem(CustomCollectionItem item) async {
    final database = await this.database;
    final map = item.toMap();
    map.remove('id');
    return database.insert('custom_collection_items', map);
  }

  Future<int> updateCustomCollectionItem(CustomCollectionItem item) async {
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
    if (person.id == null) {
      throw ArgumentError('A family person ID is required.');
    }
    final database = await this.database;
    final map = person.toMap()..remove('id');
    return database.update(
      'family_people',
      map,
      where: 'id = ?',
      whereArgs: [person.id],
    );
  }

  Future<FamilyPerson?> getFamilyPerson(int id) async {
    final database = await this.database;
    final rows = await database.query(
      'family_people',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : FamilyPerson.fromMap(rows.first);
  }

  Future<List<FamilyPerson>> getFamilyPeople({String searchText = ''}) async {
    final database = await this.database;
    final search = searchText.trim();

    if (search.isEmpty) {
      final rows = await database.query(
        'family_people',
        orderBy:
            'last_name COLLATE NOCASE, first_name COLLATE NOCASE, middle_name COLLATE NOCASE',
      );
      return rows.map(FamilyPerson.fromMap).toList();
    }

    // Treat each word as an independent search term. This lets searches such
    // as "John Smith" match "John Michael Smith" without requiring the
    // middle name, and also supports terms entered in a different order.
    final terms = search
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList();

    const searchableFields = <String>[
      'first_name',
      'middle_name',
      'last_name',
      'birth_name',
      'birth_place',
      'death_place',
    ];

    final whereParts = <String>[];
    final whereArgs = <Object?>[];

    for (final term in terms) {
      whereParts.add(
        '(${searchableFields.map((field) => '$field LIKE ? COLLATE NOCASE').join(' OR ')})',
      );
      final pattern = '%$term%';
      whereArgs.addAll(List<Object?>.filled(searchableFields.length, pattern));
    }

    final rows = await database.query(
      'family_people',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy:
          'last_name COLLATE NOCASE, first_name COLLATE NOCASE, middle_name COLLATE NOCASE',
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
      await transaction.delete(
        'photo_person_family_links',
        where: 'family_person_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'photo_person_aliases',
        where: 'family_person_id = ?',
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
    await database.insert('family_parent_child', {
      'parent_id': parentId,
      'child_id': childId,
      'parent_role': parentRole,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await database.insert('family_spouses', {
      'person1_id': low,
      'person2_id': high,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

  static Future<void> _upgradeFamilyPersonLinksToRoles(
    Database database,
  ) async {
    final tableInfo = await database.rawQuery(
      "PRAGMA table_info(family_person_links)",
    );
    if (tableInfo.isEmpty) {
      await _createFamilyPersonLinksTable(database);
      return;
    }

    final hasRole = tableInfo.any((row) => row['name'] == 'role');
    if (hasRole) return;

    await database.execute(
      'ALTER TABLE family_person_links RENAME TO family_person_links_legacy',
    );

    await _createFamilyPersonLinksTable(database);

    await database.execute('''
      INSERT INTO family_person_links (
        person_id,
        item_type,
        item_key,
        role,
        created_at_milliseconds
      )
      SELECT
        person_id,
        item_type,
        item_key,
        'Associated',
        created_at_milliseconds
      FROM family_person_links_legacy
    ''');

    await database.execute('DROP TABLE family_person_links_legacy');
  }

  static Future<void> _createFamilyPersonLinksTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS family_person_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        item_key TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'Associated',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        UNIQUE(person_id, item_type, item_key, role)
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

  static const String defaultFamilyItemRole = 'Associated';

  Future<void> linkFamilyPersonToItem({
    required int personId,
    required String itemType,
    required String itemKey,
    String role = defaultFamilyItemRole,
  }) async {
    final cleanType = itemType.trim().toLowerCase();
    final cleanKey = itemKey.trim();
    final cleanRole = _cleanFamilyItemRole(role);

    if (cleanType.isEmpty) {
      throw ArgumentError('An item type is required.');
    }
    if (cleanKey.isEmpty) {
      throw ArgumentError('An item key is required.');
    }

    final database = await this.database;
    await database.insert('family_person_links', {
      'person_id': personId,
      'item_type': cleanType,
      'item_key': cleanKey,
      'role': cleanRole,
      'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> unlinkFamilyPersonFromItem({
    required int personId,
    required String itemType,
    required String itemKey,
    String? role,
  }) async {
    final cleanType = itemType.trim().toLowerCase();
    final cleanKey = itemKey.trim();
    final database = await this.database;

    if (role == null) {
      await database.delete(
        'family_person_links',
        where: 'person_id = ? AND item_type = ? AND item_key = ?',
        whereArgs: [personId, cleanType, cleanKey],
      );
      return;
    }

    await database.delete(
      'family_person_links',
      where: 'person_id = ? AND item_type = ? AND item_key = ? AND role = ?',
      whereArgs: [personId, cleanType, cleanKey, _cleanFamilyItemRole(role)],
    );
  }

  Future<void> replaceFamilyPeopleForItem({
    required String itemType,
    required String itemKey,
    required Iterable<int> personIds,
    String role = defaultFamilyItemRole,
  }) async {
    final cleanType = itemType.trim().toLowerCase();
    final cleanKey = itemKey.trim();
    final cleanRole = _cleanFamilyItemRole(role);

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
        await transaction.insert('family_person_links', {
          'person_id': personId,
          'item_type': cleanType,
          'item_key': cleanKey,
          'role': cleanRole,
          'created_at_milliseconds': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> replaceFamilyPersonRolesForItem({
    required String itemType,
    required String itemKey,
    required Iterable<FamilyItemPersonRole> links,
  }) async {
    final cleanType = itemType.trim().toLowerCase();
    final cleanKey = itemKey.trim();

    if (cleanType.isEmpty) {
      throw ArgumentError('An item type is required.');
    }
    if (cleanKey.isEmpty) {
      throw ArgumentError('An item key is required.');
    }

    final unique = <String, FamilyItemPersonRole>{};
    for (final link in links) {
      final cleanRole = _cleanFamilyItemRole(link.role);
      unique['${link.personId}:$cleanRole'] = FamilyItemPersonRole(
        personId: link.personId,
        role: cleanRole,
      );
    }

    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'family_person_links',
        where: 'item_type = ? AND item_key = ?',
        whereArgs: [cleanType, cleanKey],
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final link in unique.values) {
        await transaction.insert('family_person_links', {
          'person_id': link.personId,
          'item_type': cleanType,
          'item_key': cleanKey,
          'role': link.role,
          'created_at_milliseconds': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<List<FamilyItemPersonRole>> getFamilyPersonRolesForItem({
    required String itemType,
    required String itemKey,
  }) async {
    final database = await this.database;
    final rows = await database.query(
      'family_person_links',
      columns: ['person_id', 'role'],
      where: 'item_type = ? AND item_key = ?',
      whereArgs: [itemType.trim().toLowerCase(), itemKey.trim()],
      orderBy: 'created_at_milliseconds ASC, id ASC',
    );

    return rows
        .map(
          (row) => FamilyItemPersonRole(
            personId: _mapInt(row['person_id']),
            role: row['role'] as String? ?? defaultFamilyItemRole,
          ),
        )
        .toList();
  }

  Future<List<FamilyPersonItemLink>> getFamilyPeopleWithRolesForItem({
    required String itemType,
    required String itemKey,
  }) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT p.*, l.role AS link_role
      FROM family_people p
      INNER JOIN family_person_links l ON l.person_id = p.id
      WHERE l.item_type = ? AND l.item_key = ?
      ORDER BY p.last_name COLLATE NOCASE,
               p.first_name COLLATE NOCASE,
               p.middle_name COLLATE NOCASE,
               l.role COLLATE NOCASE
      ''',
      [itemType.trim().toLowerCase(), itemKey.trim()],
    );

    return rows
        .map(
          (row) => FamilyPersonItemLink(
            person: FamilyPerson.fromMap(row),
            role: row['link_role'] as String? ?? defaultFamilyItemRole,
          ),
        )
        .toList();
  }

  Future<List<int>> getFamilyPersonIdsForItem({
    required String itemType,
    required String itemKey,
  }) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT person_id
      FROM family_person_links
      WHERE item_type = ? AND item_key = ?
      ORDER BY person_id
      ''',
      [itemType.trim().toLowerCase(), itemKey.trim()],
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
      SELECT DISTINCT p.*
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
    String? role,
  }) async {
    final ids = personIds.toSet().toList();
    if (ids.isEmpty) return const [];

    final cleanType = itemType.trim().toLowerCase();
    final database = await this.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final roleFilter = role == null ? '' : ' AND role = ?';
    final args = <Object?>[cleanType, ...ids];
    if (role != null) args.add(_cleanFamilyItemRole(role));

    final rows = await database.rawQuery('''
      SELECT DISTINCT item_key
      FROM family_person_links
      WHERE item_type = ?
        AND person_id IN ($placeholders)
        $roleFilter
      ORDER BY item_key COLLATE NOCASE
      ''', args);

    return rows
        .map((row) => row['item_key'] as String? ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, String>>> getFamilyItemLinksForPerson(
    int personId,
  ) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT item_type, item_key, role
      FROM family_person_links
      WHERE person_id = ?
      ORDER BY item_type COLLATE NOCASE, item_key COLLATE NOCASE
      ''',
      [personId],
    );

    return rows
        .map(
          (row) => <String, String>{
            'itemType': row['item_type'] as String? ?? '',
            'itemKey': row['item_key'] as String? ?? '',
            'role': row['role'] as String? ?? defaultFamilyItemRole,
          },
        )
        .where(
          (row) =>
              (row['itemType'] ?? '').isNotEmpty &&
              (row['itemKey'] ?? '').isNotEmpty,
        )
        .toList();
  }

  static String _cleanFamilyItemRole(String role) {
    final cleanRole = role.trim();
    return cleanRole.isEmpty ? defaultFamilyItemRole : cleanRole;
  }

  Future<List<String>> getPhotoPathsForFamilyPeople(Iterable<int> personIds) {
    return getItemKeysForFamilyPeople(personIds: personIds, itemType: 'photo');
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

  Future<List<FamilyPerson>> getFamilyPeopleForPhoto(String photoFilePath) {
    return getFamilyPeopleForItem(itemType: 'photo', itemKey: photoFilePath);
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
        batch.insert('gedcom_person_links', {
          'import_key': importKey,
          'gedcom_xref': entry.key,
          'person_id': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await database.insert('gedcom_imports', {
      'import_key': importKey,
      'file_name': fileName,
      'file_size': fileSize,
      'modified_milliseconds': modifiedMilliseconds,
      'individual_count': individualCount,
      'family_count': familyCount,
      'imported_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
          .where(
            (entity) =>
                entity is File && entity.path.toLowerCase().endsWith('.db'),
          )
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

    final backupDirectory = Directory(
      path.join(path.dirname(sourcePath), 'Backups'),
    );
    if (!await backupDirectory.exists()) return const [];

    final files = await backupDirectory
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.db'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    Future<int> countTable(Database db, String table) async {
      final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [table],
      );
      if (exists.isEmpty) return 0;
      final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
      return _mapInt(rows.first['total']);
    }

    final results = <Map<String, Object?>>[];
    for (final file in files) {
      Database? backupDb;
      try {
        backupDb = await databaseFactory.openDatabase(
          file.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        results.add({
          'name': path.basename(file.path),
          'path': file.path,
          'modified': file.lastModifiedSync().millisecondsSinceEpoch,
          'people': await countTable(backupDb, 'family_people'),
          'parent_child': await countTable(backupDb, 'family_parent_child'),
          'spouses': await countTable(backupDb, 'family_spouses'),
          'gedcom_imports': await countTable(backupDb, 'gedcom_imports'),
          'gedcom_links': await countTable(backupDb, 'gedcom_person_links'),
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
    final backupDirectory = Directory(
      path.join(path.dirname(sourcePath), 'Backups'),
    );
    await backupDirectory.create(recursive: true);

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final safeLabel = label
        .trim()
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

  Future<String?> createDatabaseBackup({String reason = 'automatic'}) async {
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
    final timestamp =
        '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_'
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
    return database.delete('coins', where: 'id = ?', whereArgs: [id]);
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
      orderBy:
          'category COLLATE NOCASE, year COLLATE NOCASE, '
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
      imagePath: coin.imagePath,
    );

    return updateImportedCoin(originalCoin: coin, updatedCoin: updatedCoin);
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
      'image_path': coin.imagePath,
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
      imagePath: row['image_path'] as String? ?? '',
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

        await transaction.insert('sports_card_sets', {
          'source_key': entry.key,
          'source_name': 'Migrated',
          'sport': first['sport'] as String? ?? '',
          'year': first['year'] as String? ?? '',
          'brand': first['brand'] as String? ?? '',
          'set_name': first['set_name'] as String? ?? '',
          'installed_at_milliseconds': now,
          'refreshed_at_milliseconds': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        for (final row in entry.value) {
          final catalogId = await transaction.insert('sports_card_catalog', {
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
          }, conflictAlgorithm: ConflictAlgorithm.ignore);

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

          await transaction.insert('sports_card_collection', {
            'catalog_id': resolvedId,
            'status': row['status'] as String? ?? 'Untracked',
            'quantity_owned': _staticMapInt(row['quantity_owned']),
            'grade': row['grade'] as String? ?? '',
            'storage_location': row['storage_location'] as String? ?? '',
            'value': row['value'],
            'notes': row['notes'] as String? ?? '',
            'updated_at_milliseconds': now,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
      orderBy:
          'sport COLLATE NOCASE, year DESC, brand COLLATE NOCASE, set_name COLLATE NOCASE',
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

      await transaction.insert('sports_card_sets', {
        'source_key': sourceKey,
        'source_name': sourceName,
        'sport': sport,
        'year': year,
        'brand': brand,
        'set_name': setName,
        'installed_at_milliseconds': installedAt,
        'refreshed_at_milliseconds': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

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
        for (final row in oldRows) row['card_number'] as String? ?? '': row,
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
        final catalogId = await transaction.insert('sports_card_catalog', {
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
        });

        final previous = userByNumber[card.cardNumber];

        await transaction.insert('sports_card_collection', {
          'catalog_id': catalogId,
          'status': previous?['status'] as String? ?? 'Untracked',
          'quantity_owned': _staticMapInt(previous?['quantity_owned']),
          'grade': previous?['grade'] as String? ?? '',
          'storage_location': previous?['storage_location'] as String? ?? '',
          'value': previous?['value'],
          'value_source': previous?['value_source'] as String? ?? '',
          'value_updated_at_milliseconds': _staticMapInt(
            previous?['value_updated_at_milliseconds'],
          ),
          'image_path': previous?['image_path'] as String? ?? '',
          'notes': previous?['notes'] as String? ?? '',
          'updated_at_milliseconds': now,
        });

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

    final rows = await db.rawQuery('''
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
      ''', args);

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

    final args = <Object?>[year.trim(), brand.trim(), cardNumber.trim()];

    if (setName.trim().isNotEmpty) {
      where.add('LOWER(c.set_name) = LOWER(?)');
      args.add(setName.trim());
    }

    final rows = await db.rawQuery('''
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
      ''', args);

    if (rows.length != 1) {
      return null;
    }

    return SportsCard.fromMap(rows.first);
  }

  Future<int> updateSportsCard(SportsCard card) async {
    if (card.id == null) {
      throw ArgumentError('Sports card catalog ID required.');
    }
    final db = await database;

    return db.insert('sports_card_collection', {
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  static Future<void> _createDocumentsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        document_date TEXT NOT NULL DEFAULT '',
        document_type TEXT NOT NULL DEFAULT '',
        people TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL,
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS documents_title_index
      ON documents(title COLLATE NOCASE)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS documents_type_index
      ON documents(document_type COLLATE NOCASE)
    ''');
  }

  Future<List<DocumentRecord>> getDocuments() async {
    final database = await this.database;
    final rows = await database.query(
      'documents',
      orderBy: 'title COLLATE NOCASE, id DESC',
    );
    return rows.map(DocumentRecord.fromMap).toList();
  }

  Future<int> insertDocument(DocumentRecord document) async {
    final database = await this.database;
    final map = document.toMap();
    map.remove('id');
    return database.insert('documents', map);
  }

  Future<int> updateDocument(DocumentRecord document) async {
    final id = document.id;
    if (id == null) throw ArgumentError('A document ID is required.');
    final database = await this.database;
    final map = document.toMap();
    map.remove('id');
    return database.update('documents', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteDocument(int id) async {
    final database = await this.database;
    return database.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _createNewspaperClippingsTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS newspaper_clippings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        newspaper_name TEXT NOT NULL DEFAULT '',
        publication_date TEXT NOT NULL DEFAULT '',
        page_number TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        article_type TEXT NOT NULL DEFAULT '',
        headline TEXT NOT NULL DEFAULT '',
        transcription TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL DEFAULT '',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        updated_at_milliseconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS newspaper_clippings_title_index
      ON newspaper_clippings(title COLLATE NOCASE)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS newspaper_clippings_newspaper_index
      ON newspaper_clippings(newspaper_name COLLATE NOCASE)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS newspaper_clippings_date_index
      ON newspaper_clippings(publication_date)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS newspaper_clipping_people (
        clipping_id INTEGER NOT NULL,
        family_person_id INTEGER NOT NULL,
        role TEXT NOT NULL DEFAULT 'Mentioned',
        created_at_milliseconds INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (clipping_id, family_person_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS newspaper_clipping_people_person_index
      ON newspaper_clipping_people(family_person_id, clipping_id)
    ''');
  }

  Future<List<Map<String, Object?>>> getNewspaperClippings({
    String searchText = '',
  }) async {
    final database = await this.database;
    final cleanSearch = searchText.trim();
    if (cleanSearch.isEmpty) {
      return database.query(
        'newspaper_clippings',
        orderBy:
            'publication_date DESC, newspaper_name COLLATE NOCASE, title COLLATE NOCASE, id DESC',
      );
    }

    final like = '%$cleanSearch%';
    return database.query(
      'newspaper_clippings',
      where: '''
        title LIKE ? COLLATE NOCASE OR
        headline LIKE ? COLLATE NOCASE OR
        newspaper_name LIKE ? COLLATE NOCASE OR
        publication_date LIKE ? COLLATE NOCASE OR
        location LIKE ? COLLATE NOCASE OR
        article_type LIKE ? COLLATE NOCASE OR
        transcription LIKE ? COLLATE NOCASE OR
        description LIKE ? COLLATE NOCASE OR
        source LIKE ? COLLATE NOCASE
      ''',
      whereArgs: List<Object?>.filled(9, like),
      orderBy:
          'publication_date DESC, newspaper_name COLLATE NOCASE, title COLLATE NOCASE, id DESC',
    );
  }

  Future<Map<String, Object?>?> getNewspaperClipping(int id) async {
    final database = await this.database;
    final rows = await database.query(
      'newspaper_clippings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insertNewspaperClipping(
    Map<String, Object?> clipping, {
    Iterable<FamilyItemPersonRole> people = const [],
  }) async {
    final database = await this.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = Map<String, Object?>.from(clipping)
      ..remove('id')
      ..putIfAbsent('created_at_milliseconds', () => now)
      ..['updated_at_milliseconds'] = now;

    return database.transaction((txn) async {
      final clippingId = await txn.insert('newspaper_clippings', map);
      await _replaceNewspaperClippingPeopleTxn(txn, clippingId, people);
      return clippingId;
    });
  }

  Future<int> updateNewspaperClipping(
    int id,
    Map<String, Object?> clipping, {
    Iterable<FamilyItemPersonRole>? people,
  }) async {
    final database = await this.database;
    final map = Map<String, Object?>.from(clipping)
      ..remove('id')
      ..['updated_at_milliseconds'] = DateTime.now().millisecondsSinceEpoch;

    return database.transaction((txn) async {
      final updated = await txn.update(
        'newspaper_clippings',
        map,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (people != null) {
        await _replaceNewspaperClippingPeopleTxn(txn, id, people);
      }
      return updated;
    });
  }

  Future<void> replaceNewspaperClippingPeople(
    int clippingId,
    Iterable<FamilyItemPersonRole> people,
  ) async {
    final database = await this.database;
    await database.transaction(
      (txn) => _replaceNewspaperClippingPeopleTxn(txn, clippingId, people),
    );
  }

  static Future<void> _replaceNewspaperClippingPeopleTxn(
    DatabaseExecutor database,
    int clippingId,
    Iterable<FamilyItemPersonRole> people,
  ) async {
    await database.delete(
      'newspaper_clipping_people',
      where: 'clipping_id = ?',
      whereArgs: [clippingId],
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final seen = <int>{};
    for (final person in people) {
      if (!seen.add(person.personId)) continue;
      await database.insert('newspaper_clipping_people', {
        'clipping_id': clippingId,
        'family_person_id': person.personId,
        'role': person.role.trim().isEmpty ? 'Mentioned' : person.role.trim(),
        'created_at_milliseconds': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<FamilyPersonItemLink>> getNewspaperClippingPeople(
    int clippingId,
  ) async {
    final database = await this.database;
    final rows = await database.rawQuery(
      '''
      SELECT p.*, l.role AS item_link_role
      FROM newspaper_clipping_people l
      INNER JOIN family_people p ON p.id = l.family_person_id
      WHERE l.clipping_id = ?
      ORDER BY p.last_name COLLATE NOCASE, p.first_name COLLATE NOCASE, p.id
    ''',
      [clippingId],
    );

    return rows
        .map(
          (row) => FamilyPersonItemLink(
            person: FamilyPerson.fromMap(row),
            role: row['item_link_role']?.toString() ?? 'Mentioned',
          ),
        )
        .toList();
  }

  Future<List<Map<String, Object?>>> getNewspaperClippingsForFamilyPerson(
    int familyPersonId,
  ) async {
    final database = await this.database;
    return database.rawQuery(
      '''
      SELECT c.*, l.role AS person_role
      FROM newspaper_clipping_people l
      INNER JOIN newspaper_clippings c ON c.id = l.clipping_id
      WHERE l.family_person_id = ?
      ORDER BY c.publication_date DESC, c.newspaper_name COLLATE NOCASE, c.title COLLATE NOCASE
    ''',
      [familyPersonId],
    );
  }

  Future<int> deleteNewspaperClipping(int id) async {
    final database = await this.database;
    return database.transaction((txn) async {
      await txn.delete(
        'newspaper_clipping_people',
        where: 'clipping_id = ?',
        whereArgs: [id],
      );
      return txn.delete(
        'newspaper_clippings',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}

class FamilyItemPersonRole {
  final int personId;
  final String role;

  const FamilyItemPersonRole({
    required this.personId,
    this.role = DatabaseHelper.defaultFamilyItemRole,
  });
}

class FamilyPersonItemLink {
  final FamilyPerson person;
  final String role;

  const FamilyPersonItemLink({
    required this.person,
    this.role = DatabaseHelper.defaultFamilyItemRole,
  });
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
