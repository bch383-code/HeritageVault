import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../database/database_helper.dart';

enum SyncProviderType {
  localFolder,
  oneDrive,
  googleDrive,
  iCloud,
}

extension SyncProviderTypeValue on SyncProviderType {
  String get value {
    switch (this) {
      case SyncProviderType.localFolder:
        return 'local_folder';
      case SyncProviderType.oneDrive:
        return 'onedrive';
      case SyncProviderType.googleDrive:
        return 'google_drive';
      case SyncProviderType.iCloud:
        return 'icloud';
    }
  }
}

enum SyncPlanReadiness {
  readyForProvider,
  needsSourceMapping,
  needsProviderConnection,
  blockedBySafety,
  unsupported,
}

extension SyncPlanReadinessLabel on SyncPlanReadiness {
  String get label {
    switch (this) {
      case SyncPlanReadiness.readyForProvider:
        return 'Provider ready';
      case SyncPlanReadiness.needsSourceMapping:
        return 'Needs mapping';
      case SyncPlanReadiness.needsProviderConnection:
        return 'Needs connection';
      case SyncPlanReadiness.blockedBySafety:
        return 'Safety blocked';
      case SyncPlanReadiness.unsupported:
        return 'Unsupported';
    }
  }
}

enum SyncPlanAction {
  create,
  update,
  delete,
}

extension SyncPlanActionLabel on SyncPlanAction {
  String get label {
    switch (this) {
      case SyncPlanAction.create:
        return 'Create';
      case SyncPlanAction.update:
        return 'Update';
      case SyncPlanAction.delete:
        return 'Delete';
    }
  }
}

class SyncPlanItem {
  const SyncPlanItem({
    required this.entityType,
    required this.localKey,
    required this.action,
    required this.readiness,
    required this.providerType,
    required this.sourceName,
    required this.changedFields,
    required this.reason,
  });

  final String entityType;
  final String localKey;
  final SyncPlanAction action;
  final SyncPlanReadiness readiness;
  final String providerType;
  final String sourceName;
  final List<String> changedFields;
  final String reason;
}

class SyncPlanSummary {
  const SyncPlanSummary({
    required this.items,
    required this.readyForProvider,
    required this.needsProviderConnection,
    required this.needsSourceMapping,
    required this.blockedBySafety,
  });

  final int items;
  final int readyForProvider;
  final int needsProviderConnection;
  final int needsSourceMapping;
  final int blockedBySafety;
}

class OutboundSyncPlan {
  const OutboundSyncPlan({
    required this.items,
    required this.summary,
  });

  final List<SyncPlanItem> items;
  final SyncPlanSummary summary;
}

class OneDriveMappingResult {
  const OneDriveMappingResult({
    required this.oneDriveDetected,
    required this.mappedSources,
    required this.detectedRoots,
  });

  final bool oneDriveDetected;
  final int mappedSources;
  final List<String> detectedRoots;
}

class OneDriveRemoteMatchResult {
  const OneDriveRemoteMatchResult({
    required this.matched,
    required this.alreadyMatched,
    required this.notFound,
    required this.errors,
    this.lastError = '',
  });

  final int matched;
  final int alreadyMatched;
  final int notFound;
  final int errors;
  final String lastError;
}


class LocalFolderExportResult {
  const LocalFolderExportResult({
    required this.exported,
    required this.skipped,
    required this.errors,
    required this.packagePaths,
    this.lastError = '',
  });

  final int exported;
  final int skipped;
  final int errors;
  final List<String> packagePaths;
  final String lastError;
}

/// Provider-neutral sync coordinator.
///
/// This preserves the API already used by the Photos and Sync & Storage
/// screens while keeping provider writes disabled until an actual provider
/// confirms success.
class SyncService {
  SyncService();

  static final SyncService instance = SyncService();

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<Map<String, Object?>> initializeDevice({String? displayName}) {
    return _db.ensureCurrentSyncDevice(displayName: displayName);
  }

  Future<Map<String, Object?>> initialize({String? deviceName}) {
    return initializeDevice(displayName: deviceName);
  }

  Future<Map<String, int>> statusSummary() {
    return _db.getSyncFoundationSummary();
  }

  Future<List<Map<String, Object?>>> connectedSources({
    SyncProviderType? provider,
  }) {
    return _db.getConnectedSources(providerType: provider?.value);
  }

  Future<List<Map<String, Object?>>> pendingChanges({int limit = 500}) {
    return _db.getPendingSyncChanges(limit: limit);
  }

  Future<List<Map<String, Object?>>> openConflicts() {
    return _db.getOpenSyncConflicts();
  }

  Future<void> registerSource({
    required String sourceId,
    required SyncProviderType provider,
    required String displayName,
    String accountIdentifier = '',
    String rootIdentifier = '',
    String rootPath = '',
    String connectionStatus = 'disconnected',
    String capabilitiesJson = '{}',
  }) {
    return _db.upsertConnectedSource(
      sourceId: sourceId,
      providerType: provider.value,
      displayName: displayName,
      accountIdentifier: accountIdentifier,
      rootIdentifier: rootIdentifier,
      rootPath: rootPath,
      connectionStatus: connectionStatus,
      capabilitiesJson: capabilitiesJson,
    );
  }

  Future<void> recordLocalChange({
    required String entityType,
    required String localKey,
    required String operation,
    Iterable<String> changedFields = const <String>[],
    String payloadHash = '',
  }) {
    return queueLocalChange(
      entityType: entityType,
      localKey: localKey,
      operation: operation,
      changedFields: changedFields,
      payloadHash: payloadHash,
    );
  }

  Future<void> queueLocalChange({
    required String entityType,
    required String localKey,
    required String operation,
    Iterable<String> changedFields = const <String>[],
    String payloadHash = '',
  }) async {
    final device = await initializeDevice();
    final deviceId = device['device_id']?.toString() ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;

    final cleanEntity = entityType.trim().toLowerCase();
    final cleanKey = localKey.trim();
    final cleanOperation = operation.trim().toLowerCase();

    if (cleanEntity.isEmpty) {
      throw ArgumentError('entityType cannot be empty.');
    }
    if (cleanKey.isEmpty) {
      throw ArgumentError('localKey cannot be empty.');
    }
    if (!const {'insert', 'update', 'delete'}.contains(cleanOperation)) {
      throw ArgumentError('operation must be insert, update, or delete.');
    }

    final fields = changedFields
        .map((field) => field.trim())
        .where((field) => field.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final changeUuid =
        '${deviceId}_${cleanEntity}_${_safeKey(cleanKey)}_${DateTime.now().microsecondsSinceEpoch}';

    await _db.recordOrMergePendingSyncChange(
      changeUuid: changeUuid,
      deviceId: deviceId,
      entityType: cleanEntity,
      localKey: cleanKey,
      operation: cleanOperation,
      payloadHash: payloadHash,
      detailsJson: jsonEncode({'changed_fields': fields}),
      changedAtMilliseconds: now,
    );

    final existing = await _db.getSyncRecords(entityType: cleanEntity);
    final alreadyRegistered = existing.any(
      (row) => row['local_key']?.toString() == cleanKey,
    );

    if (!alreadyRegistered) {
      await _db.upsertSyncRecord(
        recordUuid: _stableRecordUuid(cleanEntity, cleanKey),
        entityType: cleanEntity,
        localKey: cleanKey,
        localModifiedMilliseconds: now,
        syncState: 'local_changed',
      );
    } else {
      await _db.markSyncRecordLocalChanged(
        entityType: cleanEntity,
        localKey: cleanKey,
        localModifiedMilliseconds: now,
      );
    }
  }

  /// Registers indexed photos with stable local sync identities.
  /// This does not upload or modify any original photo.
  Future<int> registerExistingPhotoRecords() async {
    final photos = await _db.getIndexedPhotos();
    final existing = await _db.getSyncRecords(entityType: 'photo');
    final registeredKeys = existing
        .map((row) => row['local_key']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();

    var added = 0;
    for (final photo in photos) {
      if (registeredKeys.contains(photo.filePath)) continue;

      await _db.upsertSyncRecord(
        recordUuid: _stableRecordUuid('photo', photo.filePath),
        entityType: 'photo',
        localKey: photo.filePath,
        localModifiedMilliseconds: photo.modifiedMilliseconds,
        syncState: 'local_only',
      );
      added++;
    }
    return added;
  }

  /// Detects local Windows OneDrive roots and marks matching registered
  /// sources as locally mapped. No Microsoft authorization or cloud write
  /// occurs here.
  Future<OneDriveMappingResult> mapWindowsOneDriveSources() async {
    final roots = <String>{};

    for (final key in const [
      'OneDrive',
      'OneDriveConsumer',
      'OneDriveCommercial',
    ]) {
      final value = Platform.environment[key]?.trim() ?? '';
      if (value.isNotEmpty) roots.add(path.normalize(value));
    }

    final sources = await _db.getConnectedSources();
    var mapped = 0;

    for (final source in sources) {
      final sourceId = source['source_id']?.toString().trim() ?? '';
      final rootPath = source['root_path']?.toString().trim() ?? '';
      if (sourceId.isEmpty || rootPath.isEmpty) continue;

      final normalizedSource = path.normalize(rootPath);
      final matchingRoot = roots.cast<String?>().firstWhere(
        (root) =>
            root != null &&
            (path.equals(normalizedSource, root) ||
                path.isWithin(root, normalizedSource)),
        orElse: () => null,
      );

      if (matchingRoot == null) continue;

      await _db.upsertConnectedSource(
        sourceId: sourceId,
        providerType: SyncProviderType.oneDrive.value,
        displayName: source['display_name']?.toString() ?? 'OneDrive',
        accountIdentifier:
            source['account_identifier']?.toString() ?? '',
        rootIdentifier:
            source['root_identifier']?.toString() ?? sourceId,
        rootPath: rootPath,
        connectionStatus: 'mapped_local',
        capabilitiesJson:
            source['capabilities_json']?.toString() ?? '{}',
      );
      mapped++;
    }

    return OneDriveMappingResult(
      oneDriveDetected: roots.isNotEmpty,
      mappedSources: mapped,
      detectedRoots: roots.toList()..sort(),
    );
  }

  Future<OutboundSyncPlan> buildOutboundSyncPlan({int limit = 500}) async {
    final changes = await pendingChanges(limit: limit);
    final sources = await connectedSources();

    final items = <SyncPlanItem>[];

    for (final change in changes) {
      final entity = change['entity_type']?.toString() ?? '';
      final localKey = change['local_key']?.toString() ?? '';
      final operation = change['operation']?.toString() ?? 'update';

      final fields = _changedFields(change['details_json']);

      Map<String, Object?>? source;
      if (entity == 'photo' && localKey.isNotEmpty) {
        for (final candidate in sources) {
          final root = candidate['root_path']?.toString().trim() ?? '';
          if (root.isEmpty) continue;
          if (path.equals(path.normalize(root), path.normalize(localKey)) ||
              path.isWithin(path.normalize(root), path.normalize(localKey))) {
            source = candidate;
            break;
          }
        }
      }

      final provider = source?['provider_type']?.toString() ?? '';
      final sourceName = source?['display_name']?.toString() ?? '';
      final status = source?['connection_status']?.toString() ?? '';

      SyncPlanReadiness readiness;
      String reason;

      if (source == null && entity == 'photo') {
        readiness = SyncPlanReadiness.needsSourceMapping;
        reason = 'The photo is pending, but its source has not been mapped.';
      } else if (provider == SyncProviderType.oneDrive.value &&
          status != 'connected') {
        readiness = SyncPlanReadiness.needsProviderConnection;
        reason =
            'The OneDrive folder is mapped locally, but cloud authorization is not active.';
      } else if (provider == SyncProviderType.localFolder.value) {
        final capabilities =
            source?['capabilities_json']?.toString() ?? '{}';
        final uploadAllowed = capabilities.contains('"upload":true') ||
            capabilities.contains('"upload": true');
        if (uploadAllowed) {
          readiness = SyncPlanReadiness.readyForProvider;
          reason =
              'The local sync folder is connected and available for a future provider pass.';
        } else {
          readiness = SyncPlanReadiness.blockedBySafety;
          reason =
              'This source is indexed read-only; Heirloom Atlas will not write to the originals.';
        }
      } else if (source == null) {
        readiness = SyncPlanReadiness.unsupported;
        reason = 'This entity type does not yet have an outbound provider.';
      } else {
        readiness = SyncPlanReadiness.needsProviderConnection;
        reason = 'The source is known but its provider is not connected.';
      }

      items.add(
        SyncPlanItem(
          entityType: entity,
          localKey: localKey,
          action: _actionForOperation(operation),
          readiness: readiness,
          providerType: provider,
          sourceName: sourceName,
          changedFields: fields,
          reason: reason,
        ),
      );
    }

    int count(SyncPlanReadiness value) =>
        items.where((item) => item.readiness == value).length;

    return OutboundSyncPlan(
      items: List.unmodifiable(items),
      summary: SyncPlanSummary(
        items: items.length,
        readyForProvider: count(SyncPlanReadiness.readyForProvider),
        needsProviderConnection:
            count(SyncPlanReadiness.needsProviderConnection),
        needsSourceMapping: count(SyncPlanReadiness.needsSourceMapping),
        blockedBySafety: count(SyncPlanReadiness.blockedBySafety),
      ),
    );
  }

  /// Safe compatibility hook for the current Sync & Storage UI.
  ///
  /// Remote Graph matching is intentionally not performed in this service
  /// revision. Returning "not found" leaves every pending item untouched and
  /// unprocessed rather than falsely marking anything synced.
  Future<OneDriveRemoteMatchResult> matchPendingOneDrivePhotoItems({
    required dynamic session,
    required dynamic graphService,
    int limit = 1,
  }) async {
    final changes = await pendingChanges(limit: limit);
    final photoChanges = changes
        .where((row) => row['entity_type']?.toString() == 'photo')
        .toList();

    return OneDriveRemoteMatchResult(
      matched: 0,
      alreadyMatched: 0,
      notFound: photoChanges.length,
      errors: 0,
      lastError: photoChanges.isEmpty
          ? ''
          : 'Remote matching is paused until the provider connection layer is enabled.',
    );
  }


  /// Exports pending Antique captures into a portable folder package.
  ///
  /// The package is intentionally provider-neutral. A future OneDrive,
  /// Google Drive, iCloud, or direct-LAN transport can move the same package
  /// without changing the database model.
  ///
  /// Nothing is marked processed here. The originating device keeps the
  /// change pending until a receiver/provider explicitly acknowledges it.
  Future<LocalFolderExportResult> exportPendingAntiquePackages({
    required String syncFolderPath,
    int limit = 100,
  }) async {
    final cleanRoot = syncFolderPath.trim();
    if (cleanRoot.isEmpty) {
      throw ArgumentError('A sync folder path is required.');
    }

    final root = Directory(path.normalize(cleanRoot));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    final outbox = Directory(path.join(root.path, 'Heirloom Atlas', 'Outbox'));
    if (!await outbox.exists()) {
      await outbox.create(recursive: true);
    }

    final device = await initializeDevice();
    final deviceId = device['device_id']?.toString() ?? '';
    final changes = await pendingChanges(limit: limit);

    var exported = 0;
    var skipped = 0;
    var errors = 0;
    var lastError = '';
    final packagePaths = <String>[];

    for (final change in changes) {
      final entityType =
          change['entity_type']?.toString().trim().toLowerCase() ?? '';
      if (entityType != 'antique') {
        skipped++;
        continue;
      }

      final operation =
          change['operation']?.toString().trim().toLowerCase() ?? '';
      if (operation != 'insert' && operation != 'create') {
        skipped++;
        continue;
      }

      final localKey = change['local_key']?.toString().trim() ?? '';
      final changeUuid = change['change_uuid']?.toString().trim() ?? '';
      if (localKey.isEmpty || changeUuid.isEmpty) {
        errors++;
        lastError = 'A pending Antique change is missing its local identity.';
        continue;
      }

      final antiqueId = int.tryParse(localKey);
      if (antiqueId == null || antiqueId <= 0) {
        errors++;
        lastError = 'Antique $localKey does not have a valid local ID.';
        continue;
      }

      try {
        final antique = await _antiqueById(antiqueId);
        if (antique == null) {
          skipped++;
          continue;
        }

        final safeChangeUuid = _safeFileName(changeUuid);
        final finalDirectory =
            Directory(path.join(outbox.path, safeChangeUuid));
        final tempDirectory =
            Directory(path.join(outbox.path, '.$safeChangeUuid.tmp'));

        if (await finalDirectory.exists()) {
          // Re-export is idempotent. An existing complete package is enough;
          // leave the database change pending until a real acknowledgement.
          packagePaths.add(finalDirectory.path);
          exported++;
          continue;
        }

        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
        await tempDirectory.create(recursive: true);

        final mediaDirectory = Directory(path.join(tempDirectory.path, 'media'));
        await mediaDirectory.create(recursive: true);

        final exportedImages = <Map<String, Object?>>[];
        final imagePaths = (antique['image_paths'] as List<Object?>? ?? const [])
            .map((value) => value.toString())
            .where((value) => value.trim().isNotEmpty)
            .toList(growable: false);

        for (var index = 0; index < imagePaths.length; index++) {
          final originalPath = imagePaths[index];
          final sourceFile = File(originalPath);
          if (!await sourceFile.exists()) continue;

          final extension = path.extension(originalPath);
          final mediaName =
              'image_${(index + 1).toString().padLeft(2, '0')}$extension';
          final relativeMediaPath = path.join('media', mediaName);
          await sourceFile.copy(path.join(tempDirectory.path, relativeMediaPath));

          exportedImages.add({
            'relative_path': relativeMediaPath.replaceAll('\\', '/'),
            'original_file_name': path.basename(originalPath),
            'sort_order': index,
          });
        }

        final manifest = <String, Object?>{
          'format': 'heirloom_atlas_sync_package',
          'format_version': 1,
          'created_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
          'origin_device_id': deviceId,
          'change_uuid': changeUuid,
          'entity_type': 'antique',
          'operation': 'create',
          'origin_local_key': localKey,
          'record_uuid': _stableRecordUuid('antique', localKey),
          'antique': <String, Object?>{
            'title': antique['title']?.toString() ?? '',
            'description': antique['description']?.toString() ?? '',
            'year': antique['year']?.toString() ?? '',
            'acquired_from': antique['acquired_from']?.toString() ?? '',
            'purchase_price': antique['purchase_price'],
            'estimated_value': antique['estimated_value'],
            'notes': antique['notes']?.toString() ?? '',
            'condition': antique['condition']?.toString() ?? '',
            'condition_notes': antique['condition_notes']?.toString() ?? '',
            'provenance': antique['provenance']?.toString() ?? '',
            'appraisal_source': antique['appraisal_source']?.toString() ?? '',
            'valuation_date': antique['valuation_date']?.toString() ?? '',
            'images': exportedImages,
          },
        };

        final manifestFile = File(path.join(tempDirectory.path, 'manifest.json'));
        await manifestFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(manifest),
          flush: true,
        );

        await tempDirectory.rename(finalDirectory.path);
        packagePaths.add(finalDirectory.path);
        exported++;
      } catch (error) {
        errors++;
        lastError = error.toString();
      }
    }

    return LocalFolderExportResult(
      exported: exported,
      skipped: skipped,
      errors: errors,
      packagePaths: List.unmodifiable(packagePaths),
      lastError: lastError,
    );
  }

  /// Returns the Antique row plus its image paths without exposing raw
  /// database access outside the sync service.
  Future<Map<String, Object?>?> _antiqueById(int antiqueId) async {
    final database = await _db.database;
    final rows = await database.query(
      'antiques',
      where: 'id = ?',
      whereArgs: [antiqueId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final imageRows = await database.query(
      'antique_images',
      columns: ['image_path'],
      where: 'antique_id = ?',
      whereArgs: [antiqueId],
      orderBy: 'sort_order ASC, id ASC',
    );

    return <String, Object?>{
      ...rows.first,
      'image_paths': imageRows
          .map((row) => row['image_path']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    };
  }

  static String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'sync_package' : cleaned;
  }

  Future<void> acknowledgeUploadedChange({
    required String changeUuid,
    String? recordUuid,
    String? remoteId,
    String remoteParentId = '',
    String remoteEtag = '',
    int? remoteModifiedMilliseconds,
  }) async {
    if (recordUuid != null &&
        recordUuid.trim().isNotEmpty &&
        remoteId != null &&
        remoteId.trim().isNotEmpty) {
      await _db.updateSyncRecordRemoteIdentity(
        recordUuid: recordUuid,
        remoteId: remoteId,
        remoteParentId: remoteParentId,
        remoteEtag: remoteEtag,
        remoteModifiedMilliseconds:
            remoteModifiedMilliseconds ??
            DateTime.now().millisecondsSinceEpoch,
      );
    }

    await _db.markSyncChangeProcessed(changeUuid);
  }

  Future<void> markReviewed(String changeUuid) {
    return _db.markSyncChangeReviewed(changeUuid);
  }

  Future<SyncSnapshot> snapshot() async {
    await initializeDevice();
    final summary = await statusSummary();
    final sources = await connectedSources();

    return SyncSnapshot(
      devices: summary['devices'] ?? 0,
      connectedSources: summary['connected_sources'] ?? 0,
      syncRecords: summary['sync_records'] ?? 0,
      pendingChanges: summary['pending_changes'] ?? 0,
      openConflicts: summary['open_conflicts'] ?? 0,
      sources: sources,
    );
  }

  static SyncPlanAction _actionForOperation(String operation) {
    switch (operation.trim().toLowerCase()) {
      case 'insert':
      case 'create':
        return SyncPlanAction.create;
      case 'delete':
        return SyncPlanAction.delete;
      default:
        return SyncPlanAction.update;
    }
  }

  static List<String> _changedFields(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return const [];

    try {
      final decoded = jsonDecode(text);
      final values = decoded is Map ? decoded['changed_fields'] : null;
      if (values is! List) return const [];
      return values
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String _stableRecordUuid(String entityType, String localKey) {
    final encoded =
        base64Url.encode(utf8.encode('$entityType|$localKey')).replaceAll('=', '');
    return 'ha_${entityType}_$encoded';
  }

  static String _safeKey(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }
}

class SyncSnapshot {
  const SyncSnapshot({
    required this.devices,
    required this.connectedSources,
    required this.syncRecords,
    required this.pendingChanges,
    required this.openConflicts,
    required this.sources,
  });

  final int devices;
  final int connectedSources;
  final int syncRecords;
  final int pendingChanges;
  final int openConflicts;
  final List<Map<String, Object?>> sources;

  bool get hasPendingWork => pendingChanges > 0 || openConflicts > 0;
}
