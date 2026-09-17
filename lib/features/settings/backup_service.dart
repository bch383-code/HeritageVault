import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../database/database_helper.dart';

class HeirloomBackupStatus {
  final String? preferredParentDirectory;
  final String? lastBackupPath;
  final String? lastBackupCreatedAt;

  const HeirloomBackupStatus({
    required this.preferredParentDirectory,
    required this.lastBackupPath,
    required this.lastBackupCreatedAt,
  });
}

class HeirloomBackupResult {
  final String backupPath;
  final bool includedAtlasBook;
  final int faceThumbnailCount;

  const HeirloomBackupResult({
    required this.backupPath,
    required this.includedAtlasBook,
    required this.faceThumbnailCount,
  });
}

class HeirloomBackupService {
  static const String _manifestName = 'heirloom_atlas_backup.json';
  static const String _mainDatabaseName = 'heritage_vault.db';
  static const String _atlasDatabaseName = 'atlas_books.db';
  static const String _preferencesName = 'preferences.json';
  static const String _facesFolderName = 'face_thumbnails';
  static const String _preferredBackupParentKey =
      'heirloom_atlas_preferred_backup_parent';
  static const String _lastBackupPathKey = 'heirloom_atlas_last_backup_path';
  static const String _lastBackupCreatedAtKey =
      'heirloom_atlas_last_backup_created_at';

  static Future<HeirloomBackupStatus> getBackupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return HeirloomBackupStatus(
      preferredParentDirectory: prefs.getString(_preferredBackupParentKey),
      lastBackupPath: prefs.getString(_lastBackupPathKey),
      lastBackupCreatedAt: prefs.getString(_lastBackupCreatedAtKey),
    );
  }

  static Future<void> setPreferredBackupParent(String directory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredBackupParentKey, directory);
  }


  static Future<HeirloomBackupResult> createBackup(
    String parentDirectory,
  ) async {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');

    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';

    final backupDirectory = Directory(
      path.join(parentDirectory, 'HeirloomAtlas_Backup_$stamp'),
    );
    await backupDirectory.create(recursive: true);

    final mainDestination = path.join(backupDirectory.path, _mainDatabaseName);

    final db = await DatabaseHelper.instance.database;
    await db.execute("VACUUM INTO '${mainDestination.replaceAll("'", "''")}'");

    final databaseDirectory = await databaseFactory.getDatabasesPath();
    final atlasSource = path.join(databaseDirectory, _atlasDatabaseName);
    final atlasDestination = path.join(
      backupDirectory.path,
      _atlasDatabaseName,
    );

    var includedAtlasBook = false;
    if (await File(atlasSource).exists()) {
      Database? atlasDb;
      try {
        atlasDb = await databaseFactory.openDatabase(atlasSource);
        await atlasDb.execute(
          "VACUUM INTO '${atlasDestination.replaceAll("'", "''")}'",
        );
        includedAtlasBook = await File(atlasDestination).exists();
      } finally {
        await atlasDb?.close();
      }
    }

    final preferences = await SharedPreferences.getInstance();
    final preferenceMap = <String, Object?>{};
    for (final key in preferences.getKeys()) {
      final value = preferences.get(key);
      if (value is String ||
          value is bool ||
          value is int ||
          value is double ||
          value is List<String>) {
        preferenceMap[key] = value;
      }
    }

    await File(path.join(backupDirectory.path, _preferencesName)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(preferenceMap),
      flush: true,
    );

    final documents = await getApplicationDocumentsDirectory();
    final legacyFaces = Directory(
      path.join(documents.path, 'Heritage Vault', 'Faces', 'Thumbnails'),
    );
    final faceBackupDirectory = Directory(
      path.join(backupDirectory.path, _facesFolderName),
    );

    var faceThumbnailCount = 0;
    if (await legacyFaces.exists()) {
      await faceBackupDirectory.create(recursive: true);
      await for (final entity in legacyFaces.list()) {
        if (entity is! File) continue;
        await entity.copy(
          path.join(faceBackupDirectory.path, path.basename(entity.path)),
        );
        faceThumbnailCount++;
      }
    }

    final manifest = <String, Object?>{
      'format': 'heirloom_atlas_backup',
      'format_version': 1,
      'created_at': now.toIso8601String(),
      'main_database': _mainDatabaseName,
      'atlas_book_database': includedAtlasBook ? _atlasDatabaseName : null,
      'preferences': _preferencesName,
      'face_thumbnail_folder': faceThumbnailCount > 0 ? _facesFolderName : null,
      'face_thumbnail_count': faceThumbnailCount,
      'original_media_included': false,
      'duplicate_trash_included': false,
    };

    await File(path.join(backupDirectory.path, _manifestName)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );

    final backupPrefs = await SharedPreferences.getInstance();
    await backupPrefs.setString(_preferredBackupParentKey, parentDirectory);
    await backupPrefs.setString(_lastBackupPathKey, backupDirectory.path);
    await backupPrefs.setString(
      _lastBackupCreatedAtKey,
      now.toIso8601String(),
    );

    return HeirloomBackupResult(
      backupPath: backupDirectory.path,
      includedAtlasBook: includedAtlasBook,
      faceThumbnailCount: faceThumbnailCount,
    );
  }

  static Future<HeirloomBackupResult> createBackupInPreferredLocation() async {
    final status = await getBackupStatus();
    final destination = status.preferredParentDirectory;
    if (destination == null || destination.trim().isEmpty) {
      throw const FileSystemException(
        'No backup location has been selected yet.',
      );
    }
    return createBackup(destination);
  }

  static Future<Map<String, Object?>> inspectBackup(
    String backupDirectory,
  ) async {
    final directory = Directory(backupDirectory);
    if (!await directory.exists()) {
      throw const FormatException('Backup folder was not found.');
    }

    final manifestFile = File(path.join(directory.path, _manifestName));
    if (!await manifestFile.exists()) {
      throw const FormatException(
        'This folder is not a Heirloom Atlas backup.',
      );
    }

    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Backup manifest is invalid.');
    }

    final manifest = Map<String, Object?>.from(decoded);
    if (manifest['format'] != 'heirloom_atlas_backup') {
      throw const FormatException('Unsupported backup format.');
    }

    final mainDatabase = File(path.join(directory.path, _mainDatabaseName));
    if (!await mainDatabase.exists() || await mainDatabase.length() == 0) {
      throw const FormatException(
        'The main Heirloom Atlas database is missing from this backup.',
      );
    }

    return manifest;
  }

  static Future<void> scheduleRestore(String backupDirectory) async {
    await inspectBackup(backupDirectory);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'heirloom_atlas_pending_restore_path',
      backupDirectory,
    );
  }

  static Future<bool> applyPendingRestoreIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final backupPath = prefs.getString('heirloom_atlas_pending_restore_path');
    if (backupPath == null || backupPath.trim().isEmpty) return false;

    await inspectBackup(backupPath);

    final documents = await getApplicationDocumentsDirectory();
    final mainDirectory = Directory(
      path.join(documents.path, 'Heritage Vault'),
    );
    await mainDirectory.create(recursive: true);

    final sourceMain = File(path.join(backupPath, _mainDatabaseName));
    final destinationMain = File(
      path.join(mainDirectory.path, _mainDatabaseName),
    );

    if (await destinationMain.exists()) {
      final safetyCopy = File('${destinationMain.path}.before_restore');
      if (await safetyCopy.exists()) {
        await safetyCopy.delete();
      }
      await destinationMain.copy(safetyCopy.path);
      await destinationMain.delete();
    }
    await sourceMain.copy(destinationMain.path);

    final databaseDirectory = await databaseFactory.getDatabasesPath();
    final sourceAtlas = File(path.join(backupPath, _atlasDatabaseName));
    if (await sourceAtlas.exists()) {
      final destinationAtlas = File(
        path.join(databaseDirectory, _atlasDatabaseName),
      );
      if (await destinationAtlas.exists()) {
        final safetyCopy = File('${destinationAtlas.path}.before_restore');
        if (await safetyCopy.exists()) {
          await safetyCopy.delete();
        }
        await destinationAtlas.copy(safetyCopy.path);
        await destinationAtlas.delete();
      }
      await sourceAtlas.copy(destinationAtlas.path);
    }

    final preferencesFile = File(path.join(backupPath, _preferencesName));
    if (await preferencesFile.exists()) {
      final decoded = jsonDecode(await preferencesFile.readAsString());
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          if (key == 'heirloom_atlas_pending_restore_path') continue;
          final value = entry.value;
          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is List) {
            await prefs.setStringList(
              key,
              value.map((item) => item.toString()).toList(),
            );
          }
        }
      }
    }

    final sourceFaces = Directory(path.join(backupPath, _facesFolderName));
    if (await sourceFaces.exists()) {
      final destinationFaces = Directory(
        path.join(documents.path, 'Heritage Vault', 'Faces', 'Thumbnails'),
      );
      await destinationFaces.create(recursive: true);

      await for (final entity in sourceFaces.list()) {
        if (entity is! File) continue;
        await entity.copy(
          path.join(destinationFaces.path, path.basename(entity.path)),
        );
      }
    }

    await prefs.remove('heirloom_atlas_pending_restore_path');
    await prefs.setBool('heirloom_atlas_restore_completed', true);
    return true;
  }

  static Future<bool> consumeRestoreCompletedFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final restored = prefs.getBool('heirloom_atlas_restore_completed') ?? false;
    if (restored) {
      await prefs.remove('heirloom_atlas_restore_completed');
    }
    return restored;
  }
}
