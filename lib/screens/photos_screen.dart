// LOCKED PHOTOS DASHBOARD — matches approved navy/gold/cream visual blueprint.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/vault_photo.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/detected_face_record.dart';
import '../services/photo_metadata_import_service.dart';
import '../services/sync_service.dart';
import '../services/face_recognition_service.dart';
import 'photo_detail_screen.dart';
import 'photo_batch_edit_screen.dart';
import 'known_people_screen.dart';
import 'whole_library_face_scan_screen.dart';
import 'unidentified_faces_screen.dart';
import 'photo_metadata_import_screen.dart';
import 'photo_analysis_settings_screen.dart';
import '../services/photo_metadata_write_service.dart';
import '../services/photo_metadata_writer.dart';
import '../services/photo_metadata_reader.dart';

class PhotosScreen extends StatefulWidget {
  final String? initialImagePath;
  final VoidCallback? onInitialImageConsumed;

  const PhotosScreen({
    super.key,
    this.initialImagePath,
    this.onInitialImageConsumed,
  });

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final PhotoMetadataImportService _metadataImportService =
      PhotoMetadataImportService();
  final PhotoMetadataWriteService _metadataWriteService =
      const PhotoMetadataWriteService();
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();
  final SyncService _syncService = SyncService();

  String? _libraryPath;
  List<Map<String, Object?>> _photoSources = const [];
  List<VaultPhoto> _photos = const [];
  bool _loading = true;
  bool _quickCaptureHandled = false;
  bool _scanning = false;
  bool _duplicateScanning = false;
  bool _possibleDuplicateScanning = false;
  int _duplicateScanCurrent = 0;
  int _duplicateScanTotal = 0;
  int _possibleDuplicateScanGeneration = 0;
  String? _error;
  int? _possibleDuplicateCount;
  int _unidentifiedFaceCount = 0;
  int _photoTrashCount = 0;
  int _duplicateTrashCount = 0;
  int _knownPeopleCount = 0;

  String _currentFolder = '';
  bool _selectionMode = false;
  final bool _exploreMode = false;
  bool _showAllPhotosOnLanding = false;
  bool _searchSelectionMode = false;
  final Set<String> _selectedPaths = <String>{};
  String? _selectionAnchorPath;

  final TextEditingController _searchController = TextEditingController();
  Map<String, PhotoCatalogMetadata> _catalogByPath =
      <String, PhotoCatalogMetadata>{};
  final Set<String> _quickFilters = <String>{};
  int? _selectedPhotoSourceId;
  String _photoSortMode = 'date_newest';
  Set<String> _recentlyAddedPaths = <String>{};
  Set<String> _atlasFavoritePhotoPaths = <String>{};

  // Keep Windows/desktop photo sources synchronized with changes made
  // outside Heirloom Atlas (Explorer, OneDrive, scanners, etc.).
  final List<StreamSubscription<FileSystemEvent>> _photoSourceWatchers =
      <StreamSubscription<FileSystemEvent>>[];
  Timer? _photoSourceChangeDebounce;
  bool _sourceReconciliationRunning = false;
  bool _sourceReconciliationQueued = false;

  // Persisted as JSON in app settings:
  // { "top-level folder": "chosen photo file path" }
  Map<String, String> _folderCoverByFolder = <String, String>{};

  static const _extensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.tif',
    '.tiff',
    '.bmp',
    '.webp',
    '.heic',
    '.heif',
  };

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleInitialQuickCapture();
      });

      // Reconcile once after startup so files added while Heirloom Atlas was
      // closed are discovered, then keep watching for Explorer/OneDrive
      // changes while this screen is alive.
      _startPhotoSourceMonitoring();
      unawaited(_reconcilePhotoSources(reason: 'startup'));
    });
  }

  @override
  void dispose() {
    _photoSourceChangeDebounce?.cancel();
    for (final watcher in _photoSourceWatchers) {
      unawaited(watcher.cancel());
    }
    _photoSourceWatchers.clear();
    _searchController.dispose();
    super.dispose();
  }

  void _startPhotoSourceMonitoring() {
    for (final watcher in _photoSourceWatchers) {
      unawaited(watcher.cancel());
    }
    _photoSourceWatchers.clear();

    for (final source in _photoSources) {
      final rootPath = (source['root_path'] as String? ?? '').trim();
      if (rootPath.isEmpty) continue;

      final root = Directory(rootPath);
      if (!root.existsSync()) continue;

      try {
        final watcher = root
            .watch(recursive: true)
            .listen(
              (event) {
                final extension = path.extension(event.path).toLowerCase();
                if (!_extensions.contains(extension)) return;

                // Explorer can emit several events for one copy/rename. Debounce
                // them into one quiet reconciliation pass.
                _photoSourceChangeDebounce?.cancel();
                _photoSourceChangeDebounce = Timer(
                  const Duration(seconds: 2),
                  () => unawaited(
                    _reconcilePhotoSources(reason: 'filesystem change'),
                  ),
                );
              },
              onError: (Object error, StackTrace stackTrace) {
                debugPrint('PHOTO SOURCE WATCH ERROR: $rootPath: $error');
              },
            );
        _photoSourceWatchers.add(watcher);
      } catch (error) {
        debugPrint('PHOTO SOURCE WATCH START ERROR: $rootPath: $error');
      }
    }
  }

  Future<void> _reconcilePhotoSources({required String reason}) async {
    if (!mounted) return;
    if (_sourceReconciliationRunning) {
      _sourceReconciliationQueued = true;
      return;
    }

    _sourceReconciliationRunning = true;
    try {
      do {
        _sourceReconciliationQueued = false;
        debugPrint('PHOTO SOURCE RECONCILE: $reason');
        await _scanLibrary(runAutomaticIntake: false);
      } while (mounted && _sourceReconciliationQueued);
    } catch (error) {
      debugPrint('PHOTO SOURCE RECONCILE ERROR: $error');
    } finally {
      _sourceReconciliationRunning = false;
    }
  }

  Future<void> _loadOrganizerCounts() async {
    final duplicateValue = await _databaseHelper.getSetting(
      'photo_possible_duplicate_count',
    );
    final unidentifiedFaces = await _databaseHelper.getUnconfirmedFaces();
    final confirmedFaces = await _databaseHelper.getConfirmedFaces();
    final photoTrashEntries = await _getPhotoTrashEntries();
    final trashEntries = await _getDuplicateTrashEntries();

    final grouped = <String, List<DetectedFaceRecord>>{};
    for (final face in confirmedFaces) {
      final name = face.personName.trim();
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name, () => <DetectedFaceRecord>[]).add(face);
    }

    for (final entry in grouped.entries) {
      final rejectedIds = await _databaseHelper.getRejectedFaceIdsForPerson(
        entry.key,
      );

      for (final candidate in unidentifiedFaces) {
        final id = candidate.id;
        if (id != null && rejectedIds.contains(id)) continue;

        final similarity = FaceRecognitionService.consensusSimilarity(
          candidate.embedding,
          entry.value,
        );

        if (similarity >= 0.78) {
        } else if (similarity >= 0.64) {}
      }
    }

    if (!mounted) return;

    setState(() {
      _possibleDuplicateCount = duplicateValue == null
          ? null
          : int.tryParse(duplicateValue);
      _unidentifiedFaceCount = unidentifiedFaces.length;
      _photoTrashCount = photoTrashEntries.length;
      _duplicateTrashCount = trashEntries.length;
      _knownPeopleCount = grouped.length;
    });
  }

  Future<void> _refreshDuplicateTrashCountOnly() async {
    final entries = await _getDuplicateTrashEntries();
    if (!mounted) return;
    setState(() => _duplicateTrashCount = entries.length);
  }

  Future<void> _load() async {
    try {
      final libraryPath = await _databaseHelper.getSetting(
        'photo_library_path',
      );
      final photoSources = await _databaseHelper.getPhotoSources();
      await _registerPhotoSourcesWithSyncFoundation(photoSources);
      final photos = await _databaseHelper.getIndexedPhotos();
      final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
      final recentSetting = await _databaseHelper.getSetting(
        'photo_recently_added_paths',
      );
      final folderCoverSetting = await _databaseHelper.getSetting(
        'photo_folder_covers',
      );
      final atlasFavoritePhotoPaths = await _databaseHelper
          .getAtlasBookFavoriteKeys(itemType: 'photo');

      Set<String> recentlyAddedPaths = <String>{};
      if (recentSetting != null && recentSetting.isNotEmpty) {
        try {
          final decoded = jsonDecode(recentSetting);
          if (decoded is List) {
            recentlyAddedPaths = decoded.whereType<String>().toSet();
          }
        } catch (_) {
          recentlyAddedPaths = <String>{};
        }
      }

      Map<String, String> folderCoverByFolder = <String, String>{};
      if (folderCoverSetting != null && folderCoverSetting.isNotEmpty) {
        try {
          final decoded = jsonDecode(folderCoverSetting);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final folder = entry.key?.toString().trim() ?? '';
              final filePath = entry.value?.toString().trim() ?? '';
              if (folder.isNotEmpty && filePath.isNotEmpty) {
                folderCoverByFolder[folder] = filePath;
              }
            }
          }
        } catch (_) {
          folderCoverByFolder = <String, String>{};
        }
      }

      // A deleted/moved cover photo should never leave a broken folder card.
      // Remove stale choices and let the dashboard fall back automatically.
      final indexedPaths = photos.map((photo) => photo.filePath).toSet();
      folderCoverByFolder.removeWhere(
        (_, filePath) =>
            !indexedPaths.contains(filePath) || !File(filePath).existsSync(),
      );

      final catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };

      if (!mounted) return;

      setState(() {
        _libraryPath = libraryPath;
        _photoSources = photoSources;
        _photos = photos;
        _catalogByPath = catalogByPath;
        _recentlyAddedPaths = recentlyAddedPaths;
        _folderCoverByFolder = folderCoverByFolder;
        _atlasFavoritePhotoPaths = atlasFavoritePhotoPaths;
        _loading = false;
      });

      await _loadOrganizerCounts();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _handleInitialQuickCapture() async {
    if (_quickCaptureHandled) return;
    final sourcePath = widget.initialImagePath?.trim() ?? '';
    if (sourcePath.isEmpty) return;

    _quickCaptureHandled = true;
    widget.onInitialImageConsumed?.call();

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected photo could not be found.')),
      );
      return;
    }

    if (_photoSources.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Choose a Photo Source First'),
          content: const Text(
            'Quick Capture needs a connected Photos source so the selected '
            'photo has a permanent home. Add a photo source, then try Quick Capture again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    int? selectedSourceId;
    String subfolder = '';

    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final usableSources = _photoSources.where((source) {
            final id = source['id'] as int? ?? 0;
            final root = (source['root_path'] as String? ?? '').trim();
            return id > 0 && root.isNotEmpty;
          }).toList();

          selectedSourceId ??= usableSources.isEmpty
              ? null
              : usableSources.first['id'] as int?;

          return AlertDialog(
            title: const Text('Save Quick Capture Photo'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    path.basename(sourcePath),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedSourceId,
                    decoration: const InputDecoration(
                      labelText: 'Photo Source',
                      border: OutlineInputBorder(),
                    ),
                    items: usableSources.map((source) {
                      final id = source['id'] as int? ?? 0;
                      final name =
                          (source['display_name'] as String? ?? 'Photo Source')
                              .trim();
                      final root = (source['root_path'] as String? ?? '')
                          .trim();
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text(
                          '$name — $root',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedSourceId = value),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Folder within source (optional)',
                      hintText: 'e.g. Scans or Hoffman Family',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => subfolder = value.trim(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Heirloom Atlas will copy the selected photo into this source. '
                    'The original file will stay where it is.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: selectedSourceId == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Photo'),
              ),
            ],
          );
        },
      ),
    );

    if (accepted != true || selectedSourceId == null || !mounted) return;

    final selectedSource = _photoSources.firstWhere(
      (source) => (source['id'] as int? ?? 0) == selectedSourceId,
    );
    final rootPath = (selectedSource['root_path'] as String? ?? '').trim();
    final displayName =
        (selectedSource['display_name'] as String? ?? 'Photo Source').trim();

    try {
      var destinationDirectory = Directory(rootPath);
      if (subfolder.isNotEmpty) {
        final safeSegments = path
            .split(subfolder)
            .where(
              (segment) =>
                  segment != '.' &&
                  segment != '..' &&
                  segment.trim().isNotEmpty,
            )
            .toList();
        destinationDirectory = Directory(
          path.joinAll([rootPath, ...safeSegments]),
        );
      }
      await destinationDirectory.create(recursive: true);

      final originalName = path.basename(sourcePath);
      var destinationPath = path.join(destinationDirectory.path, originalName);
      if (path.equals(sourcePath, destinationPath)) {
        destinationPath = sourcePath;
      } else {
        final base = path.basenameWithoutExtension(originalName);
        final extension = path.extension(originalName);
        var counter = 2;
        while (await File(destinationPath).exists()) {
          destinationPath = path.join(
            destinationDirectory.path,
            '$base ($counter)$extension',
          );
          counter++;
        }
        await sourceFile.copy(destinationPath);
      }

      await _scanPhotoSource(
        sourceId: selectedSourceId!,
        rootPath: rootPath,
        displayName: displayName,
      );

      if (!mounted) return;
      VaultPhoto? savedPhoto;
      for (final photo in _photos) {
        if (path.equals(photo.filePath, destinationPath)) {
          savedPhoto = photo;
          break;
        }
      }

      if (savedPhoto != null) {
        await _openPhoto(savedPhoto, [savedPhoto]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${path.basename(destinationPath)} was saved and indexed.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quick Capture could not save this photo: $error'),
        ),
      );
    }
  }

  SyncProviderType? _syncProviderForPhotoSource(String sourceType) {
    switch (sourceType.trim().toLowerCase()) {
      case 'local_folder':
        return SyncProviderType.localFolder;
      case 'onedrive':
        return SyncProviderType.oneDrive;
      case 'google_drive':
        return SyncProviderType.googleDrive;
      case 'icloud':
        return SyncProviderType.iCloud;
      default:
        return null;
    }
  }

  Future<void> _registerPhotoSourceWithSyncFoundation({
    required int sourceId,
    required String sourceType,
    required String displayName,
    required String rootPath,
  }) async {
    final provider = _syncProviderForPhotoSource(sourceType);
    if (provider == null || sourceId <= 0) return;

    await _syncService.registerSource(
      sourceId: 'photo_source_$sourceId',
      provider: provider,
      displayName: displayName.trim().isEmpty ? 'Photo Source' : displayName,
      rootIdentifier: 'photo_source_$sourceId',
      rootPath: rootPath,
      connectionStatus: 'indexed',
      capabilitiesJson: jsonEncode({
        'discover': true,
        'index': true,
        'upload': false,
        'move': false,
        'rename': false,
        'delete': false,
        'connection_mode': 'windows_folder',
      }),
    );
  }

  Future<void> _registerPhotoSourcesWithSyncFoundation(
    List<Map<String, Object?>> sources,
  ) async {
    for (final source in sources) {
      final sourceId = source['id'] as int? ?? 0;
      final sourceType = source['source_type'] as String? ?? '';
      final displayName = source['display_name'] as String? ?? 'Photo Source';
      final rootPath = source['root_path'] as String? ?? '';

      await _registerPhotoSourceWithSyncFoundation(
        sourceId: sourceId,
        sourceType: sourceType,
        displayName: displayName,
        rootPath: rootPath,
      );
    }
  }

  Future<void> _addFolderPhotoSource({
    required String sourceType,
    required String displayName,
    required String dialogTitle,
  }) async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
    );
    if (selected == null || selected.trim().isEmpty) return;

    final sourceId = await _databaseHelper.addPhotoSource(
      sourceType: sourceType,
      displayName: displayName,
      rootPath: selected,
    );

    await _registerPhotoSourceWithSyncFoundation(
      sourceId: sourceId,
      sourceType: sourceType,
      displayName: displayName,
      rootPath: selected,
    );

    await _scanPhotoSource(
      sourceId: sourceId,
      rootPath: selected,
      displayName: displayName,
    );
  }

  Future<void> _showAddPhotoSourceDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Photo Source'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add another photo location. Existing sources and indexed '
                'photo work are preserved.',
              ),
              const SizedBox(height: 7),
              ListTile(
                leading: const _PhotoSourceBrandIcon(
                  sourceType: 'google_drive',
                  size: 28,
                ),
                title: const Text(
                  'Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Choose a Google Drive folder available in Windows.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  await _addFolderPhotoSource(
                    sourceType: 'google_drive',
                    displayName: 'Google Drive',
                    dialogTitle: 'Choose a Google Drive photo folder',
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _PhotoSourceBrandIcon(
                  sourceType: 'onedrive',
                  size: 28,
                ),
                title: const Text(
                  'OneDrive',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Choose a OneDrive folder available in Windows.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  await _addFolderPhotoSource(
                    sourceType: 'onedrive',
                    displayName: 'OneDrive',
                    dialogTitle: 'Choose a OneDrive photo folder',
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.folder_outlined, size: 28),
                title: const Text(
                  'Local Folder / This Computer',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Choose any photo folder on this computer, an external drive, or a network drive.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  await _addFolderPhotoSource(
                    sourceType: 'local_folder',
                    displayName: 'Local Folder',
                    dialogTitle: 'Choose a local photo folder',
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _PhotoSourceBrandIcon(
                  sourceType: 'icloud',
                  size: 28,
                ),
                title: const Text(
                  'iCloud',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Choose an iCloud Photos or iCloud Drive folder '
                  'available in Windows.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  await _addFolderPhotoSource(
                    sourceType: 'icloud',
                    displayName: 'iCloud',
                    dialogTitle: 'Choose an iCloud photo folder',
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanPhotoSource({
    required int sourceId,
    required String rootPath,
    required String displayName,
    bool runAutomaticIntake = true,
  }) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      if (!mounted) return;
      setState(() => _error = '$displayName folder could not be found.');
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final previousPhotos = await _databaseHelper.getIndexedPhotos();
      final indexed = <VaultPhoto>[];

      int entriesSeen = 0;
      int filesSeen = 0;
      int imageFilesSeen = 0;
      final scanErrors = <String>[];

      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        entriesSeen++;

        if (entity is! File) continue;
        filesSeen++;

        final extension = path.extension(entity.path).toLowerCase();
        if (!_extensions.contains(extension)) continue;
        imageFilesSeen++;

        try {
          final stat = await entity.stat();
          final relativePath = path.relative(entity.path, from: root.path);
          final relativeFolder = path.dirname(relativePath) == '.'
              ? ''
              : path.dirname(relativePath);
          indexed.add(
            VaultPhoto(
              filePath: entity.path,
              fileName: path.basename(entity.path),
              extension: extension,
              fileSize: stat.size,
              modifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
              relativeFolder: relativeFolder,
            ),
          );
        } catch (error) {
          scanErrors.add('${entity.path}: $error');
        }
      }

      debugPrint(
        'PHOTO SCAN: root="$rootPath" '
        'entries=$entriesSeen '
        'files=$filesSeen '
        'images=$imageFilesSeen '
        'indexed=${indexed.length}',
      );

      for (final error in scanErrors) {
        debugPrint('PHOTO SCAN ERROR: $error');
      }

      await _databaseHelper.replaceIndexedPhotosForSource(
        sourceId: sourceId,
        photos: indexed,
      );

      final photos = await _databaseHelper.getIndexedPhotos();
      final sources = await _databaseHelper.getPhotoSources();
      final previousPaths = previousPhotos.map((p) => p.filePath).toSet();
      final newlyAddedPaths = photos
          .where((p) => !previousPaths.contains(p.filePath))
          .map((p) => p.filePath)
          .toSet();

      if (newlyAddedPaths.isNotEmpty) {
        await _databaseHelper.setSetting(
          'photo_recently_added_paths',
          jsonEncode(newlyAddedPaths.toList()),
        );
      }

      if (!mounted) return;
      setState(() {
        _photos = photos;
        _photoSources = sources;
        _libraryPath ??= rootPath;
        if (newlyAddedPaths.isNotEmpty) _recentlyAddedPaths = newlyAddedPaths;
        _scanning = false;
        _currentFolder = '';
      });

      final diagnosticText = StringBuffer()
        ..writeln('Folder: $rootPath')
        ..writeln('Entries seen: $entriesSeen')
        ..writeln('Files seen: $filesSeen')
        ..writeln('Supported images seen: $imageFilesSeen')
        ..writeln('Images indexed: ${indexed.length}');
      if (scanErrors.isNotEmpty) {
        diagnosticText
          ..writeln()
          ..writeln('Scan errors:')
          ..write(scanErrors.join('\n'));
      }

      // Successful scans should be quiet during normal use. Keep the
      // diagnostic dialog only when the scanner actually encountered errors.
      if (mounted && scanErrors.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Photo Scan Diagnostic'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: SelectableText(diagnosticText.toString()),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      if (runAutomaticIntake) {
        await _runAutomaticPhotoIntake(
          previousPhotos: previousPhotos,
          currentPhotos: photos,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _scanning = false;
      });
    }
  }

  Future<void> _scanLibrary({bool runAutomaticIntake = true}) async {
    final sources = await _databaseHelper.getPhotoSources();
    for (final source in sources) {
      final sourceId = source['id'] as int? ?? 0;
      final rootPath = source['root_path'] as String? ?? '';
      final displayName = source['display_name'] as String? ?? 'Photo Source';
      if (sourceId <= 0 || rootPath.isEmpty) continue;
      await _scanPhotoSource(
        sourceId: sourceId,
        rootPath: rootPath,
        displayName: displayName,
        runAutomaticIntake: runAutomaticIntake,
      );
    }
  }

  Future<void> _runAutomaticPhotoIntake({
    required List<VaultPhoto> previousPhotos,
    required List<VaultPhoto> currentPhotos,
  }) async {
    final manualOnly = _settingBool(
      await _databaseHelper.getSetting('photo_analysis_manual_only'),
      fallback: false,
    );
    final analyzeNew = _settingBool(
      await _databaseHelper.getSetting('photo_analysis_analyze_new'),
      fallback: true,
    );

    if (manualOnly || !analyzeNew) return;

    final previousByPath = <String, VaultPhoto>{
      for (final photo in previousPhotos) photo.filePath: photo,
    };

    final changed = currentPhotos.where((photo) {
      final old = previousByPath[photo.filePath];
      return old == null ||
          old.fileSize != photo.fileSize ||
          old.modifiedMilliseconds != photo.modifiedMilliseconds;
    }).toList();

    if (changed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Library is up to date — no new or changed photos to analyze.',
            ),
          ),
        );
      }
      return;
    }

    final duplicatesEnabled = _settingBool(
      await _databaseHelper.getSetting('photo_analysis_duplicates'),
      fallback: true,
    );

    if (!mounted) return;

    int? possibleDuplicateCount;

    if (duplicatesEnabled) {
      // Automatic intake analyzes quietly first. The user can decide whether
      // to open the full Possible Duplicates review.
      possibleDuplicateCount = await _findPossibleDuplicates(
        showResults: false,
        countOnlyPaths: changed.map((photo) => photo.filePath).toSet(),
      );
    }

    if (!mounted) return;

    if (possibleDuplicateCount != null) {
      final count = possibleDuplicateCount;
      final action = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            '${changed.length} new/changed photo${changed.length == 1 ? '' : 's'} '
            'analyzed — $count possible match${count == 1 ? '' : 'es'} '
            'involving the new/changed photo${changed.length == 1 ? '' : 's'}.',
          ),
          action: count > 0
              ? SnackBarAction(
                  label: 'Review',
                  onPressed: () {
                    _findPossibleDuplicates();
                  },
                )
              : null,
        ),
      );

      // Keep the future referenced so the snackbar is not treated as fire-and-forget.
      await action.closed;
    }

    if (!mounted) return;

    final facesEnabled = _settingBool(
      await _databaseHelper.getSetting('photo_analysis_faces'),
      fallback: false,
    );
    final metadataEnabled = _settingBool(
      await _databaseHelper.getSetting('photo_analysis_metadata'),
      fallback: true,
    );
    final ocrEnabled = _settingBool(
      await _databaseHelper.getSetting('photo_analysis_ocr'),
      fallback: false,
    );

    if (metadataEnabled) {
      var metadataChanged = 0;
      var photosWithMetadata = 0;

      await _metadataImportService.importPhotos(
        changed,
        onPhotoComplete: (photo, progress) async {
          if (progress.foundAnyMetadata) {
            photosWithMetadata++;
          }

          final changedCatalog =
              progress.peopleImported > 0 ||
              progress.tagsImported > 0 ||
              progress.dateImported ||
              progress.locationImported ||
              progress.descriptionImported;

          if (changedCatalog) {
            metadataChanged++;
          }
        },
      );

      final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();

      if (!mounted) return;

      setState(() {
        _catalogByPath = <String, PhotoCatalogMetadata>{
          for (final record in catalogRecords) record.filePath: record,
        };
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'Embedded metadata checked for ${changed.length} new/changed '
            'photo${changed.length == 1 ? '' : 's'} — '
            '$photosWithMetadata contained metadata and '
            '$metadataChanged updated Heirloom Atlas.',
          ),
        ),
      );
    }

    if (facesEnabled) {
      var facesFound = 0;
      var photosWithFaces = 0;
      var photosScanned = 0;

      final scanVersions = await _databaseHelper.getPhotoFaceScanVersions();

      final faceCandidates = changed.where((photo) {
        final scannedVersion = scanVersions[photo.filePath];
        return scannedVersion == null ||
            scannedVersion != photo.modifiedMilliseconds;
      }).toList();

      if (faceCandidates.isNotEmpty) {
        await _faceRecognitionService.scanPhotosIncrementally(
          faceCandidates,
          onPhotoComplete: (photo, faces, progress) async {
            await _databaseHelper.replaceFacesForPhotos([
              photo.filePath,
            ], faces);

            await _databaseHelper.markPhotoFaceScanned(
              photo: photo,
              faceCount: faces.length,
            );

            photosScanned++;
            facesFound += faces.length;
            if (faces.isNotEmpty) {
              photosWithFaces++;
            }
          },
        );
      }

      if (!mounted) return;

      _unidentifiedFaceCount = await _databaseHelper.getUnconfirmedFaceCount();
      if (!mounted) return;
      setState(() {});

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Face detection checked $photosScanned new/changed '
            'photo${photosScanned == 1 ? '' : 's'} — '
            '$facesFound face${facesFound == 1 ? '' : 's'} found in '
            '$photosWithFaces photo${photosWithFaces == 1 ? '' : 's'}.',
          ),
          action: facesFound > 0
              ? SnackBarAction(
                  label: 'Review',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UnidentifiedFacesScreen(),
                      ),
                    );
                  },
                )
              : null,
        ),
      );
    }

    if (ocrEnabled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'OCR automation is enabled and will be connected next.',
          ),
        ),
      );
    }
  }

  bool _settingBool(String? value, {required bool fallback}) {
    if (value == null) return fallback;
    return value == 'true';
  }

  List<String> _folderSegments(String folder) {
    if (folder.trim().isEmpty) return const [];
    return path.split(folder);
  }

  String _joinFolder(String parent, String child) {
    if (parent.isEmpty) return child;
    return path.join(parent, child);
  }

  List<_PhotoFolder> get _childFolders {
    final counts = <String, int>{};

    for (final photo in _filteredPhotos) {
      final folder = photo.relativeFolder;
      final currentSegments = _folderSegments(_currentFolder);
      final photoSegments = _folderSegments(folder);

      if (photoSegments.length <= currentSegments.length) continue;

      var matchesCurrent = true;
      for (var i = 0; i < currentSegments.length; i++) {
        if (photoSegments[i] != currentSegments[i]) {
          matchesCurrent = false;
          break;
        }
      }
      if (!matchesCurrent) continue;

      final childName = photoSegments[currentSegments.length];
      final childPath = _joinFolder(_currentFolder, childName);
      counts[childPath] = (counts[childPath] ?? 0) + 1;
    }

    final folders =
        counts.entries
            .map(
              (entry) => _PhotoFolder(
                path: entry.key,
                name: path.basename(entry.key),
                photoCount: entry.value,
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    return folders;
  }

  int _recursiveCount(String folderPath) {
    if (folderPath.isEmpty) return _filteredPhotos.length;

    final prefix = '$folderPath${path.separator}';
    return _filteredPhotos.where((photo) {
      return photo.relativeFolder == folderPath ||
          photo.relativeFolder.startsWith(prefix);
    }).length;
  }

  Future<void> _openPhotoEditor(VaultPhoto photo) async {
    final folderBeforeEdit = _currentFolder;

    final editedPath = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PhotoEditorDialog(photo: photo),
    );

    if (editedPath == null || editedPath.isEmpty || !mounted) return;

    // Re-index only the source that contains this photo, so the edited copy
    // appears immediately without rescanning every connected source.
    final sourceCandidates =
        _photoSources.where((source) {
          final rootPath = (source['root_path'] as String? ?? '').trim();
          if (rootPath.isEmpty) return false;
          return path.isWithin(rootPath, photo.filePath) ||
              path.equals(rootPath, path.dirname(photo.filePath));
        }).toList()..sort((a, b) {
          final aRoot = (a['root_path'] as String? ?? '').length;
          final bRoot = (b['root_path'] as String? ?? '').length;
          return bRoot.compareTo(aRoot);
        });

    if (sourceCandidates.isNotEmpty) {
      final source = sourceCandidates.first;
      final sourceId = source['id'] as int? ?? 0;
      final rootPath = source['root_path'] as String? ?? '';
      final displayName = source['display_name'] as String? ?? 'Photo Source';

      if (sourceId > 0 && rootPath.isNotEmpty) {
        await _scanPhotoSource(
          sourceId: sourceId,
          rootPath: rootPath,
          displayName: displayName,
          runAutomaticIntake: false,
        );
      }
    } else {
      // If the photo source could not be matched by path, re-index the
      // connected photo sources so the edited copy is still discovered.
      await _scanLibrary(runAutomaticIntake: false);
    }

    if (!mounted) return;

    // _scanPhotoSource returns the dashboard to the root. For an edit,
    // return the user to the folder they were browsing so the newly-created
    // copy is visible beside the original.
    if (folderBeforeEdit.isNotEmpty) {
      setState(() => _currentFolder = folderBeforeEdit);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Edited copy saved as ${path.basename(editedPath)}. Original preserved.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openPhoto(
    VaultPhoto photo,
    List<VaultPhoto> navigationPhotos,
  ) async {
    final initialIndex = navigationPhotos.indexWhere(
      (item) => item.filePath == photo.filePath,
    );
    var previewIndex = initialIndex < 0 ? 0 : initialIndex;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentPhoto = navigationPhotos[previewIndex];

          return FutureBuilder<List<Object>>(
            future: Future.wait<Object>([
              _databaseHelper.getPhotoCatalogMetadata(currentPhoto.filePath),
              _databaseHelper.getFacesForPhotoPaths([currentPhoto.filePath]),
              _databaseHelper.getConfirmedFaces(),
            ]),
            builder: (context, snapshot) {
              final loading = snapshot.connectionState != ConnectionState.done;

              final metadata = snapshot.hasData
                  ? snapshot.data![0] as PhotoCatalogMetadata
                  : PhotoCatalogMetadata(filePath: currentPhoto.filePath);

              final allFaces = snapshot.hasData
                  ? snapshot.data![1] as List<DetectedFaceRecord>
                  : <DetectedFaceRecord>[];

              final confirmedFaces = allFaces
                  .where(
                    (face) =>
                        face.confirmed && face.personName.trim().isNotEmpty,
                  )
                  .toList();

              final knownFaces = snapshot.hasData
                  ? snapshot.data![2] as List<DetectedFaceRecord>
                  : <DetectedFaceRecord>[];

              final knownNames =
                  knownFaces
                      .map((face) => face.personName.trim())
                      .where((name) => name.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    );

              Future<void> scanCurrentPhotoForFaces() async {
                final messenger = ScaffoldMessenger.of(context);

                try {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Scanning this photo for faces...'),
                      duration: Duration(seconds: 2),
                    ),
                  );

                  final faces = await _faceRecognitionService.scanPhotos([
                    currentPhoto,
                  ]);

                  await _databaseHelper.replaceFacesForPhotos([
                    currentPhoto.filePath,
                  ], faces);

                  await _databaseHelper.markPhotoFaceScanned(
                    photo: currentPhoto,
                    faceCount: faces.length,
                  );

                  _unidentifiedFaceCount = await _databaseHelper
                      .getUnconfirmedFaceCount();

                  if (!mounted || !dialogContext.mounted) return;

                  setState(() {});
                  setDialogState(() {});

                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        faces.isEmpty
                            ? 'No faces were detected in this photo.'
                            : '${faces.length} ${faces.length == 1 ? 'face' : 'faces'} detected. You can identify them below.',
                      ),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                } catch (error) {
                  if (!mounted || !dialogContext.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Face scan could not be completed: $error'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }

              Future<void> addCatalogPerson() async {
                var typedName = '';

                final newName = await showDialog<String>(
                  context: dialogContext,
                  builder: (nameDialogContext) => StatefulBuilder(
                    builder: (context, setNameState) {
                      final query = typedName.trim().toLowerCase();
                      final existingPeople = metadata.people.toSet();
                      final suggestions = knownNames
                          .where(
                            (name) =>
                                !existingPeople.contains(name) &&
                                (query.isEmpty ||
                                    name.toLowerCase().contains(query)),
                          )
                          .take(12)
                          .toList();

                      void submit([String? selected]) {
                        final clean = (selected ?? typedName).trim();
                        if (clean.isEmpty || existingPeople.contains(clean)) {
                          return;
                        }
                        Navigator.pop(nameDialogContext, clean);
                      }

                      return AlertDialog(
                        title: const Text('Add Person'),
                        content: SizedBox(
                          width: 500,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Choose a Known Person or type a new name.',
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                autofocus: true,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Person',
                                  hintText: 'Search or enter a name',
                                  prefixIcon: Icon(Icons.person_add_alt_1),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  typedName = value;
                                  setNameState(() {});
                                },
                                onSubmitted: (_) => submit(),
                              ),
                              if (suggestions.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Known People',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: suggestions
                                      .map(
                                        (name) => ActionChip(
                                          avatar: const Icon(
                                            Icons.person,
                                            size: 16,
                                          ),
                                          label: Text(name),
                                          onPressed: () => submit(name),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(nameDialogContext),
                            child: const Text('Cancel'),
                          ),
                          FilledButton.icon(
                            onPressed: () => submit(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Person'),
                          ),
                        ],
                      );
                    },
                  ),
                );

                if (newName == null || newName.trim().isEmpty) return;

                final updatedPeople =
                    <String>{...metadata.people, newName.trim()}.toList()..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    );

                final updatedMetadata = PhotoCatalogMetadata(
                  filePath: metadata.filePath,
                  people: updatedPeople,
                  tags: metadata.tags,
                  approximateDate: metadata.approximateDate,
                  location: metadata.location,
                  description: metadata.description,
                  backWriting: metadata.backWriting,
                  notes: metadata.notes,
                );

                await _databaseHelper.savePhotoCatalogMetadata(updatedMetadata);
                _catalogByPath[currentPhoto.filePath] = updatedMetadata;

                await _syncService.recordLocalChange(
                  entityType: 'photo',
                  localKey: updatedMetadata.filePath,
                  operation: 'update',
                  changedFields: const ['People'],
                );

                if (!mounted || !dialogContext.mounted) return;
                setState(() {});
                setDialogState(() {});
              }

              final quickDateController = TextEditingController(
                text: metadata.approximateDate,
              );
              final quickLocationController = TextEditingController(
                text: metadata.location,
              );
              final quickDescriptionController = TextEditingController(
                text: metadata.description,
              );
              final quickTagsController = TextEditingController(
                text: metadata.tags.join(', '),
              );

              Future<void> saveQuickDetails() async {
                final updated = PhotoCatalogMetadata(
                  filePath: metadata.filePath,
                  people: metadata.people,
                  tags: quickTagsController.text
                      .split(',')
                      .map((value) => value.trim())
                      .where((value) => value.isNotEmpty)
                      .toSet()
                      .toList(),
                  approximateDate: quickDateController.text.trim(),
                  location: quickLocationController.text.trim(),
                  description: quickDescriptionController.text.trim(),
                  backWriting: metadata.backWriting,
                  notes: metadata.notes,
                );

                final changedFields = <String>[];
                if (updated.approximateDate != metadata.approximateDate) {
                  changedFields.add('Date');
                }
                if (updated.location != metadata.location) {
                  changedFields.add('Location');
                }
                if (updated.description != metadata.description) {
                  changedFields.add('Description');
                }
                if (updated.tags.join('\u0000') !=
                    metadata.tags.join('\u0000')) {
                  changedFields.add('Tags');
                }

                await _databaseHelper.savePhotoCatalogMetadata(updated);
                _catalogByPath[currentPhoto.filePath] = updated;

                var pendingVerified = false;

                if (changedFields.isNotEmpty) {
                  await _syncService.recordLocalChange(
                    entityType: 'photo',
                    localKey: updated.filePath,
                    operation: 'update',
                    changedFields: changedFields,
                  );

                  // Verify that this exact photo edit reached the pending sync
                  // queue. This makes a silent queue failure visible instead
                  // of allowing the catalog save to appear successful.
                  final pending = await _syncService.pendingChanges(limit: 500);
                  pendingVerified = pending.any(
                    (change) =>
                        change['entity_type']?.toString() == 'photo' &&
                        change['local_key']?.toString() == updated.filePath,
                  );

                  if (!pendingVerified) {
                    throw StateError(
                      'Photo details were saved, but this photo was not found '
                      'in the pending sync queue.',
                    );
                  }

                  final writeResult = await PhotoMetadataWriter.write(
                    filePath: currentPhoto.filePath,
                    metadata: updated,
                  );
                  if (!writeResult.success) {
                    if (!mounted || !dialogContext.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Details saved to Heirloom Atlas, but the original file '
                          'could not be updated: ${writeResult.message}',
                        ),
                        duration: const Duration(seconds: 6),
                      ),
                    );
                    return;
                  }
                }

                if (!mounted || !dialogContext.mounted) return;
                setState(() {});
                setDialogState(() {});

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      changedFields.isEmpty
                          ? 'No photo details changed.'
                          : pendingVerified
                          ? 'Photo details saved and written to the original file.'
                          : 'Photo details saved.',
                    ),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }

              Future<void> identifyUnidentifiedFace(
                DetectedFaceRecord face,
              ) async {
                final faceId = face.id;
                if (faceId == null) return;

                var typedName = '';

                final newName = await showDialog<String>(
                  context: dialogContext,
                  builder: (nameDialogContext) => StatefulBuilder(
                    builder: (context, setNameState) {
                      final query = typedName.trim().toLowerCase();
                      final suggestions = knownNames
                          .where(
                            (name) =>
                                query.isEmpty ||
                                name.toLowerCase().contains(query),
                          )
                          .take(12)
                          .toList();

                      void submit([String? selected]) {
                        final clean = (selected ?? typedName).trim();
                        if (clean.isEmpty) return;
                        FocusScope.of(nameDialogContext).unfocus();
                        Navigator.pop(nameDialogContext, clean);
                      }

                      return AlertDialog(
                        title: const Text('Identify Face'),
                        content: SizedBox(
                          width: 500,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Choose a known person or type the correct name.',
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                autofocus: true,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Person',
                                  hintText: 'Search or enter a name',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  typedName = value;
                                  setNameState(() {});
                                },
                                onSubmitted: (_) => submit(),
                              ),
                              if (suggestions.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Known People',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: suggestions
                                      .map(
                                        (name) => ActionChip(
                                          avatar: const Icon(
                                            Icons.person,
                                            size: 16,
                                          ),
                                          label: Text(name),
                                          onPressed: () => submit(name),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(nameDialogContext),
                            child: const Text('Cancel'),
                          ),
                          FilledButton.icon(
                            onPressed: () => submit(),
                            icon: const Icon(Icons.check),
                            label: const Text('Identify'),
                          ),
                        ],
                      );
                    },
                  ),
                );

                final cleanName = newName?.trim() ?? '';
                if (cleanName.isEmpty) return;

                await _databaseHelper.confirmFaceGroup(
                  faceIds: [faceId],
                  personName: cleanName,
                );

                final updatedPeople =
                    <String>{...metadata.people, cleanName}.toList()..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    );

                final updatedMetadata = PhotoCatalogMetadata(
                  filePath: metadata.filePath,
                  people: updatedPeople,
                  tags: metadata.tags,
                  approximateDate: metadata.approximateDate,
                  location: metadata.location,
                  description: metadata.description,
                  backWriting: metadata.backWriting,
                  notes: metadata.notes,
                );

                await _databaseHelper.savePhotoCatalogMetadata(updatedMetadata);
                _catalogByPath[currentPhoto.filePath] = updatedMetadata;

                await _syncService.recordLocalChange(
                  entityType: 'photo',
                  localKey: updatedMetadata.filePath,
                  operation: 'update',
                  changedFields: const ['People'],
                );

                if (!mounted || !dialogContext.mounted) return;
                setState(() {});
                setDialogState(() {});

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$cleanName identified in this photo.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }

              Future<void> changeFaceName(DetectedFaceRecord face) async {
                final faceId = face.id;
                if (faceId == null) return;

                var typedName = face.personName;

                final newName = await showDialog<String>(
                  context: dialogContext,
                  builder: (nameDialogContext) => StatefulBuilder(
                    builder: (context, setNameState) {
                      final query = typedName.trim().toLowerCase();
                      final suggestions = knownNames
                          .where(
                            (name) =>
                                name != face.personName &&
                                (query.isEmpty ||
                                    name.toLowerCase().contains(query)),
                          )
                          .take(8)
                          .toList();

                      void submit() {
                        final clean = typedName.trim();
                        if (clean.isEmpty || clean == face.personName) {
                          return;
                        }
                        FocusScope.of(nameDialogContext).unfocus();
                        Navigator.pop(nameDialogContext, clean);
                      }

                      return AlertDialog(
                        title: const Text('Change face identity'),
                        content: SizedBox(
                          width: 460,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Currently identified as ${face.personName}',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: face.personName,
                                autofocus: true,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Correct person',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  typedName = value;
                                  setNameState(() {});
                                },
                                onFieldSubmitted: (_) => submit(),
                              ),
                              if (suggestions.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: suggestions
                                      .map(
                                        (name) => ActionChip(
                                          label: Text(name),
                                          onPressed: () => Navigator.pop(
                                            nameDialogContext,
                                            name,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(nameDialogContext),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: submit,
                            child: const Text('Update Name'),
                          ),
                        ],
                      );
                    },
                  ),
                );

                if (newName == null || newName.trim().isEmpty) return;

                final cleanName = newName.trim();
                final oldName = face.personName.trim();

                await _databaseHelper.reassignConfirmedFace(
                  faceId: faceId,
                  newPersonName: cleanName,
                );

                final updatedPeople = metadata.people.toSet();
                updatedPeople.add(cleanName);

                final oldNameStillPresent = confirmedFaces.any(
                  (other) =>
                      other.id != face.id &&
                      other.personName.trim().toLowerCase() ==
                          oldName.toLowerCase(),
                );
                if (!oldNameStillPresent && oldName.isNotEmpty) {
                  updatedPeople.removeWhere(
                    (name) =>
                        name.trim().toLowerCase() == oldName.toLowerCase(),
                  );
                }

                final updatedMetadata = PhotoCatalogMetadata(
                  filePath: metadata.filePath,
                  people: updatedPeople.toList()
                    ..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    ),
                  tags: metadata.tags,
                  approximateDate: metadata.approximateDate,
                  location: metadata.location,
                  description: metadata.description,
                  backWriting: metadata.backWriting,
                  notes: metadata.notes,
                );

                await _databaseHelper.savePhotoCatalogMetadata(updatedMetadata);
                _catalogByPath[currentPhoto.filePath] = updatedMetadata;

                await _syncService.recordLocalChange(
                  entityType: 'photo',
                  localKey: updatedMetadata.filePath,
                  operation: 'update',
                  changedFields: const ['People'],
                );

                if (!mounted || !dialogContext.mounted) return;
                setState(() {});
                setDialogState(() {});
              }

              Future<void> markFaceUnidentified(DetectedFaceRecord face) async {
                final faceId = face.id;
                if (faceId == null) return;

                final confirmed =
                    await showDialog<bool>(
                      context: dialogContext,
                      builder: (confirmContext) => AlertDialog(
                        title: const Text('Mark face unidentified?'),
                        content: Text(
                          'Heirloom Atlas will stop treating this face as '
                          '"${face.personName}". It will return to the '
                          'Unidentified Faces queue.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(confirmContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(confirmContext, true),
                            child: const Text('Mark Unidentified'),
                          ),
                        ],
                      ),
                    ) ??
                    false;

                if (!confirmed) return;

                await _databaseHelper.markFaceUnidentified(faceId);

                final remainingSamePerson = confirmedFaces.any(
                  (other) =>
                      other.id != face.id &&
                      other.personName == face.personName,
                );

                if (!remainingSamePerson) {
                  final updatedPeople = metadata.people.toSet()
                    ..remove(face.personName);

                  final updatedMetadata = PhotoCatalogMetadata(
                    filePath: metadata.filePath,
                    people: updatedPeople.toList(),
                    tags: metadata.tags,
                    approximateDate: metadata.approximateDate,
                    location: metadata.location,
                    description: metadata.description,
                    backWriting: metadata.backWriting,
                    notes: metadata.notes,
                  );

                  await _databaseHelper.savePhotoCatalogMetadata(
                    updatedMetadata,
                  );
                  _catalogByPath[currentPhoto.filePath] = updatedMetadata;
                }

                await _syncService.recordLocalChange(
                  entityType: 'photo',
                  localKey: metadata.filePath,
                  operation: 'update',
                  changedFields: const ['People'],
                );

                if (!mounted || !dialogContext.mounted) return;
                setState(() {});
                setDialogState(() {});
              }

              final file = File(currentPhoto.filePath);

              void showPreviousPhoto() {
                if (previewIndex <= 0) return;
                previewIndex--;
                setDialogState(() {});
              }

              void showNextPhoto() {
                if (previewIndex >= navigationPhotos.length - 1) return;
                previewIndex++;
                setDialogState(() {});
              }

              return Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.arrowLeft):
                      _PreviousPhotoIntent(),
                  SingleActivator(LogicalKeyboardKey.arrowRight):
                      _NextPhotoIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _PreviousPhotoIntent: CallbackAction<_PreviousPhotoIntent>(
                      onInvoke: (_) {
                        showPreviousPhoto();
                        return null;
                      },
                    ),
                    _NextPhotoIntent: CallbackAction<_NextPhotoIntent>(
                      onInvoke: (_) {
                        showNextPhoto();
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    autofocus: true,
                    child: Dialog(
                      insetPadding: const EdgeInsets.all(28),
                      child: SizedBox(
                        width: 1400,
                        height: 860,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      currentPhoto.fileName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Previous photo',
                                    onPressed: previewIndex > 0
                                        ? showPreviousPhoto
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Text(
                                    '${previewIndex + 1} of '
                                    '${navigationPhotos.length}',
                                  ),
                                  IconButton(
                                    tooltip: 'Next photo',
                                    onPressed:
                                        previewIndex <
                                            navigationPhotos.length - 1
                                        ? showNextPhoto
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Close',
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      padding: const EdgeInsets.all(20),
                                      child: file.existsSync()
                                          ? Image.file(
                                              file,
                                              fit: BoxFit.contain,
                                              cacheWidth: 1600,
                                            )
                                          : const Center(
                                              child: Text(
                                                'Original file not found.',
                                              ),
                                            ),
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  SizedBox(
                                    width: 430,
                                    child: loading
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : ListView(
                                            padding: const EdgeInsets.all(20),
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'People',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w900,
                                                          ),
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    onPressed: addCatalogPerson,
                                                    icon: const Icon(
                                                      Icons.person_add_alt_1,
                                                      size: 18,
                                                    ),
                                                    label: const Text(
                                                      'Add Person',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              if (metadata.people.isEmpty)
                                                Text(
                                                  'No people added yet.',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                )
                                              else
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 6,
                                                  children: metadata.people
                                                      .map(
                                                        (name) => Chip(
                                                          label: Text(name),
                                                        ),
                                                      )
                                                      .toList(),
                                                ),
                                              const SizedBox(height: 18),
                                              Text(
                                                'Quick Details',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                              const SizedBox(height: 10),
                                              TextFormField(
                                                controller: quickDateController,
                                                textInputAction:
                                                    TextInputAction.next,
                                                decoration: const InputDecoration(
                                                  labelText: 'Year / Date',
                                                  hintText:
                                                      'e.g. 1964 or Summer 1964',
                                                  prefixIcon: Icon(
                                                    Icons.event_outlined,
                                                  ),
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              TextFormField(
                                                controller:
                                                    quickLocationController,
                                                textInputAction:
                                                    TextInputAction.done,
                                                decoration: const InputDecoration(
                                                  labelText: 'Location',
                                                  hintText:
                                                      'e.g. Rome, New York or Grandma\'s house',
                                                  prefixIcon: Icon(
                                                    Icons.place_outlined,
                                                  ),
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                                onFieldSubmitted: (_) async {
                                                  await saveQuickDetails();
                                                },
                                              ),
                                              const SizedBox(height: 10),
                                              TextFormField(
                                                controller:
                                                    quickDescriptionController,
                                                minLines: 2,
                                                maxLines: 4,
                                                decoration: const InputDecoration(
                                                  labelText:
                                                      'Description / Caption',
                                                  hintText:
                                                      'What is happening in this photo?',
                                                  prefixIcon: Icon(
                                                    Icons.notes_outlined,
                                                  ),
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              TextFormField(
                                                controller: quickTagsController,
                                                textInputAction:
                                                    TextInputAction.done,
                                                decoration: const InputDecoration(
                                                  labelText: 'Tags / Keywords',
                                                  hintText:
                                                      'Family, vacation, softball',
                                                  prefixIcon: Icon(
                                                    Icons.sell_outlined,
                                                  ),
                                                  helperText:
                                                      'Separate tags with commas',
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                                onFieldSubmitted: (_) async {
                                                  await saveQuickDetails();
                                                },
                                              ),
                                              const SizedBox(height: 10),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: FilledButton.icon(
                                                  onPressed: saveQuickDetails,
                                                  icon: const Icon(
                                                    Icons.save_outlined,
                                                    size: 17,
                                                  ),
                                                  label: const Text('Save'),
                                                ),
                                              ),
                                              const SizedBox(height: 22),
                                              Text(
                                                'Faces in this Photo',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              if (confirmedFaces.isEmpty)
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'No confirmed faces in this photo.',
                                                    ),
                                                    const SizedBox(height: 10),
                                                    FilledButton.tonalIcon(
                                                      onPressed:
                                                          scanCurrentPhotoForFaces,
                                                      icon: const Icon(
                                                        Icons
                                                            .face_retouching_natural,
                                                      ),
                                                      label: Text(
                                                        allFaces.isEmpty
                                                            ? 'Identify Face'
                                                            : 'Scan Again',
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      allFaces.isEmpty
                                                          ? 'Heirloom Atlas will scan this photo and show any faces it finds so you can name them here.'
                                                          : 'Run face detection again if someone was missed.',
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                    ),
                                                  ],
                                                )
                                              else ...[
                                                Row(
                                                  children: [
                                                    FilledButton.tonalIcon(
                                                      onPressed:
                                                          scanCurrentPhotoForFaces,
                                                      icon: const Icon(
                                                        Icons.refresh,
                                                        size: 18,
                                                      ),
                                                      label: const Text(
                                                        'Scan Again',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                ...confirmedFaces.map((face) {
                                                  final thumb = File(
                                                    face.thumbnailPath,
                                                  );
                                                  return Card(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          bottom: 8,
                                                        ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            10,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          CircleAvatar(
                                                            radius: 24,
                                                            backgroundImage:
                                                                thumb
                                                                    .existsSync()
                                                                ? FileImage(
                                                                    thumb,
                                                                  )
                                                                : null,
                                                            child:
                                                                thumb
                                                                    .existsSync()
                                                                ? null
                                                                : const Icon(
                                                                    Icons
                                                                        .person_outline,
                                                                  ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              face.personName,
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                            ),
                                                          ),
                                                          PopupMenuButton<
                                                            String
                                                          >(
                                                            tooltip:
                                                                'Face actions',
                                                            onSelected: (action) async {
                                                              if (action ==
                                                                  'change') {
                                                                await changeFaceName(
                                                                  face,
                                                                );
                                                              } else if (action ==
                                                                  'unidentify') {
                                                                await markFaceUnidentified(
                                                                  face,
                                                                );
                                                              }
                                                            },
                                                            itemBuilder: (_) => const [
                                                              PopupMenuItem(
                                                                value: 'change',
                                                                child: Text(
                                                                  'Change Name',
                                                                ),
                                                              ),
                                                              PopupMenuItem(
                                                                value:
                                                                    'unidentify',
                                                                child: Text(
                                                                  'Mark Unidentified',
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }),
                                              ],
                                              if (allFaces.any(
                                                (face) => !face.confirmed,
                                              )) ...[
                                                const SizedBox(height: 14),
                                                Text(
                                                  'Unidentified Faces',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Identify detected people without leaving this photo.',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                const SizedBox(height: 8),
                                                ...allFaces.where((face) => !face.confirmed).map((
                                                  face,
                                                ) {
                                                  final thumb = File(
                                                    face.thumbnailPath,
                                                  );
                                                  return Card(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          bottom: 8,
                                                        ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            10,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          CircleAvatar(
                                                            radius: 24,
                                                            backgroundImage:
                                                                thumb
                                                                    .existsSync()
                                                                ? FileImage(
                                                                    thumb,
                                                                  )
                                                                : null,
                                                            child:
                                                                thumb
                                                                    .existsSync()
                                                                ? null
                                                                : const Icon(
                                                                    Icons
                                                                        .face_outlined,
                                                                  ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          const Expanded(
                                                            child: Text(
                                                              'Unknown person',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                            ),
                                                          ),
                                                          FilledButton.tonalIcon(
                                                            onPressed: () async {
                                                              await identifyUnidentifiedFace(
                                                                face,
                                                              );
                                                            },
                                                            icon: const Icon(
                                                              Icons
                                                                  .badge_outlined,
                                                              size: 17,
                                                            ),
                                                            label: const Text(
                                                              'Identify',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }),
                                              ],
                                              const SizedBox(height: 22),
                                              Wrap(
                                                spacing: 10,
                                                runSpacing: 10,
                                                children: [
                                                  FilledButton.icon(
                                                    onPressed: () async {
                                                      Navigator.pop(
                                                        dialogContext,
                                                      );
                                                      await _openPhotoEditor(
                                                        currentPhoto,
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.tune_outlined,
                                                    ),
                                                    label: const Text(
                                                      'Edit Image',
                                                    ),
                                                  ),
                                                  FilledButton.tonalIcon(
                                                    onPressed: () async {
                                                      Navigator.pop(
                                                        dialogContext,
                                                      );
                                                      await Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) =>
                                                              PhotoDetailScreen(
                                                                photos:
                                                                    navigationPhotos,
                                                                initialIndex:
                                                                    previewIndex,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.edit_note_outlined,
                                                    ),
                                                    label: const Text(
                                                      'More Details',
                                                    ),
                                                  ),
                                                  OutlinedButton.icon(
                                                    onPressed: () async {
                                                      Navigator.pop(
                                                        dialogContext,
                                                      );
                                                      await _movePhotoToTrash(
                                                        currentPhoto,
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                    label: const Text(
                                                      'Move to Trash',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 28),
                                              const Divider(),
                                              const SizedBox(height: 12),
                                              Text(
                                                'Original File Information',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                currentPhoto.fileName,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              SelectableText(
                                                currentPhoto.filePath,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'Folder: ${currentPhoto.relativeFolder.isEmpty ? 'Pictures' : currentPhoto.relativeFolder}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                              Text(
                                                'File type: ${currentPhoto.extension.toUpperCase()}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
    final faceCount = await _databaseHelper.getUnconfirmedFaceCount();

    if (!mounted) return;

    setState(() {
      _catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };
      _unidentifiedFaceCount = faceCount;
    });
  }

  void _toggleSelected(VaultPhoto photo) {
    setState(() {
      if (_selectedPaths.contains(photo.filePath)) {
        _selectedPaths.remove(photo.filePath);
      } else {
        _selectedPaths.add(photo.filePath);
      }
      _selectionAnchorPath = photo.filePath;
    });
  }

  void _handlePhotoSelectionClick(
    VaultPhoto photo,
    List<VaultPhoto> visiblePhotos, {
    bool forceSelectionMode = false,
  }) {
    final keyboard = HardwareKeyboard.instance;
    final controlPressed = keyboard.isControlPressed || keyboard.isMetaPressed;
    final shiftPressed = keyboard.isShiftPressed;

    // Ctrl-click starts selection mode even if the user did not press
    // "Select Photos" first, matching normal Windows selection behavior.
    if (!_selectionMode && !forceSelectionMode && controlPressed) {
      setState(() {
        _selectionMode = true;
        _selectedPaths.add(photo.filePath);
        _selectionAnchorPath = photo.filePath;
      });
      return;
    }

    if (!_selectionMode && !forceSelectionMode) {
      _openPhoto(photo, visiblePhotos);
      return;
    }

    if (shiftPressed && _selectionAnchorPath != null) {
      final anchorIndex = visiblePhotos.indexWhere(
        (item) => item.filePath == _selectionAnchorPath,
      );
      final clickedIndex = visiblePhotos.indexWhere(
        (item) => item.filePath == photo.filePath,
      );

      if (anchorIndex >= 0 && clickedIndex >= 0) {
        final start = math.min(anchorIndex, clickedIndex);
        final end = math.max(anchorIndex, clickedIndex);
        final rangePaths = visiblePhotos
            .sublist(start, end + 1)
            .map((item) => item.filePath);

        setState(() {
          // Shift-click replaces the selection with the range.
          // Ctrl+Shift-click adds the range to the existing selection.
          if (!controlPressed) _selectedPaths.clear();
          _selectedPaths.addAll(rangePaths);
        });
        return;
      }
    }

    setState(() {
      if (_selectedPaths.contains(photo.filePath)) {
        _selectedPaths.remove(photo.filePath);
      } else {
        _selectedPaths.add(photo.filePath);
      }
      _selectionAnchorPath = photo.filePath;
    });
  }

  void _selectAllVisiblePhotos() {
    final visible = _filteredPhotosInCurrentFolder;
    setState(() {
      _selectionMode = true;
      _selectedPaths.addAll(visible.map((photo) => photo.filePath));
      if (visible.isNotEmpty) {
        _selectionAnchorPath = visible.first.filePath;
      }
    });
  }

  void _clearPhotoSelection() {
    setState(() {
      _selectedPaths.clear();
      _selectionAnchorPath = null;
    });
  }

  void _exitPhotoSelectionMode() {
    if (!_selectionMode && _selectedPaths.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
      _selectionAnchorPath = null;
    });
  }

  void _toggleSelectionMode() {
    if (_selectionMode) {
      _exitPhotoSelectionMode();
      return;
    }

    setState(() {
      _selectionMode = true;
      _selectionAnchorPath = null;
    });
  }

  Future<void> _openBatchEditor() async {
    final selected = _photos
        .where((photo) => _selectedPaths.contains(photo.filePath))
        .toList();

    if (selected.isEmpty) return;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoBatchEditScreen(photos: selected),
      ),
    );

    if (!mounted) return;

    if (changed == true) {
      final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
      if (!mounted) return;

      setState(() {
        _catalogByPath = <String, PhotoCatalogMetadata>{
          for (final record in catalogRecords) record.filePath: record,
        };
        _selectedPaths.clear();
        _selectionMode = false;
      });
      await _loadOrganizerCounts();
    }
  }

  Future<void> _toggleAtlasBookFavorite(VaultPhoto photo) async {
    final filePath = photo.filePath;
    final favorite = !_atlasFavoritePhotoPaths.contains(filePath);

    // Update immediately so the star feels responsive.
    setState(() {
      if (favorite) {
        _atlasFavoritePhotoPaths.add(filePath);
      } else {
        _atlasFavoritePhotoPaths.remove(filePath);
      }
    });

    try {
      await _databaseHelper.setAtlasBookFavorite(
        itemType: 'photo',
        itemKey: filePath,
        favorite: favorite,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (favorite) {
          _atlasFavoritePhotoPaths.remove(filePath);
        } else {
          _atlasFavoritePhotoPaths.add(filePath);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update Atlas Book favorite: $error')),
      );
    }
  }

  Future<void> _openWholeLibraryFaceScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WholeLibraryFaceScanScreen(photos: _photos),
      ),
    );

    if (!mounted) return;

    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();

    setState(() {
      _catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };
    });
  }

  Future<void> _openMetadataImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoMetadataImportScreen(photos: _photos),
      ),
    );

    if (!mounted) return;

    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();

    setState(() {
      _catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };
    });
  }

  Future<void> _openMetadataWritePreview() async {
    final cataloged = _photos.where((photo) {
      final metadata = _catalogByPath[photo.filePath];
      return metadata != null && _hasAnyCatalogData(metadata);
    }).toList();

    const supported = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.webp'};
    final writable = cataloged
        .where((photo) => supported.contains(photo.extension.toLowerCase()))
        .toList();

    final plans = _metadataWriteService
        .createPlans(photos: writable, catalogByPath: _catalogByPath)
        .where(
          (plan) =>
              plan.people.isNotEmpty ||
              plan.tags.isNotEmpty ||
              plan.location.trim().isNotEmpty ||
              plan.description.trim().isNotEmpty,
        )
        .toList();

    int countWhere(bool Function(PhotoCatalogMetadata metadata) test) =>
        writable.where((photo) => test(_catalogByPath[photo.filePath]!)).length;

    final withDescription = countWhere(
      (metadata) => metadata.description.trim().isNotEmpty,
    );
    final withTags = countWhere((metadata) => metadata.tags.isNotEmpty);
    final withPeople = countWhere((metadata) => metadata.people.isNotEmpty);
    final withLocation = countWhere(
      (metadata) => metadata.location.trim().isNotEmpty,
    );

    if (!mounted) return;

    final shouldWrite = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 760,
          height: 660,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.preview_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Metadata Write Preview',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Review before writing',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nothing has been changed yet. If you continue, Heirloom '
                      'Atlas will process each eligible photo individually, '
                      'create a backup before modifying it, and verify the '
                      'metadata after the write.',
                    ),
                    const SizedBox(height: 20),
                    _metadataPreviewRow(
                      'Photos in library',
                      '${_photos.length}',
                    ),
                    _metadataPreviewRow(
                      'Photos with Heirloom Atlas metadata',
                      '${cataloged.length}',
                    ),
                    _metadataPreviewRow(
                      'Supported files',
                      '${writable.length}',
                    ),
                    _metadataPreviewRow(
                      'Photos eligible for this batch',
                      '${plans.length}',
                    ),
                    const Divider(height: 28),
                    Text(
                      'Fields that would be written',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _metadataPreviewRow(
                      'Description',
                      '$withDescription photos',
                    ),
                    _metadataPreviewRow('Tags / keywords', '$withTags photos'),
                    _metadataPreviewRow(
                      'People as keywords',
                      '$withPeople photos',
                    ),
                    _metadataPreviewRow('Location', '$withLocation photos'),
                    const SizedBox(height: 18),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.shield_outlined),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Safety: every photo is backed up before it is '
                                'modified. Description, Tags, People, and '
                                'Location are verified after writing. Archival '
                                'Date and Notes stay in Heirloom Atlas only, '
                                'and the original capture date is not changed.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Supported file types: JPG, JPEG, PNG, TIF, TIFF, WEBP.',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: plans.isEmpty
                          ? null
                          : () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.drive_file_rename_outline),
                      label: Text(
                        plans.isEmpty
                            ? 'Nothing to Write'
                            : 'Write ${plans.length} Photos',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldWrite != true || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Write metadata to original photos?'),
        content: Text(
          'This will modify ${plans.length} original photo '
          '${plans.length == 1 ? 'file' : 'files'}. Heirloom Atlas will create '
          'a backup before each modification and verify each completed write. '
          'One failure will not stop the rest of the batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Write Metadata'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _runMetadataWriteBatch(plans);
  }

  Future<void> _runMetadataWriteBatch(
    List<PhotoMetadataWritePlan> plans,
  ) async {
    final progress = ValueNotifier<_MetadataBatchProgress>(
      _MetadataBatchProgress(total: plans.length),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Writing Photo Metadata'),
          content: SizedBox(
            width: 560,
            child: ValueListenableBuilder<_MetadataBatchProgress>(
              valueListenable: progress,
              builder: (context, value, _) {
                final fraction = value.total == 0
                    ? 0.0
                    : value.processed / value.total;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: fraction),
                    const SizedBox(height: 10),
                    Text('${value.processed} of ${value.total} processed'),
                    const SizedBox(height: 6),
                    if (value.currentFile.isNotEmpty)
                      Text(
                        value.currentFile,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '${value.succeeded} verified • '
                      '${value.failed} failed • ${value.skipped} skipped',
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Please leave Heirloom Atlas open until this finishes.',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    final failures = <_MetadataBatchFailure>[];
    var succeeded = 0;
    var failed = 0;
    var skipped = 0;

    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];

      progress.value = _MetadataBatchProgress(
        total: plans.length,
        processed: index,
        succeeded: succeeded,
        failed: failed,
        skipped: skipped,
        currentFile: plan.photo.fileName,
      );

      final file = File(plan.photo.filePath);
      if (!await file.exists()) {
        skipped++;
        failures.add(
          _MetadataBatchFailure(
            fileName: plan.photo.fileName,
            message: 'Original file was not found.',
          ),
        );
      } else {
        try {
          final expected = PhotoCatalogMetadata(
            filePath: plan.photo.filePath,
            people: plan.people,
            tags: plan.tags,
            approximateDate: plan.approximateDate,
            location: plan.location,
            description: plan.description,
          );

          final result = await PhotoMetadataWriter.write(
            filePath: plan.photo.filePath,
            metadata: expected,
          );

          if (!result.success) {
            failed++;
            failures.add(
              _MetadataBatchFailure(
                fileName: plan.photo.fileName,
                message: result.message,
              ),
            );
          } else {
            final refreshed = await PhotoMetadataReader.read(
              plan.photo.filePath,
            );
            final verificationFailures = _metadataVerificationFailures(
              expected,
              refreshed,
            );

            if (result.backupPath == null ||
                result.backupPath!.trim().isEmpty) {
              verificationFailures.insert(0, 'Backup was not confirmed');
            }

            if (verificationFailures.isEmpty) {
              succeeded++;
            } else {
              failed++;
              failures.add(
                _MetadataBatchFailure(
                  fileName: plan.photo.fileName,
                  message:
                      'Could not verify: ${verificationFailures.join(', ')}.',
                ),
              );
            }
          }
        } catch (error) {
          failed++;
          failures.add(
            _MetadataBatchFailure(
              fileName: plan.photo.fileName,
              message: error.toString(),
            ),
          );
        }
      }

      progress.value = _MetadataBatchProgress(
        total: plans.length,
        processed: index + 1,
        succeeded: succeeded,
        failed: failed,
        skipped: skipped,
        currentFile: plan.photo.fileName,
      );
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          failed == 0 && skipped == 0
              ? 'Batch metadata write verified'
              : 'Batch metadata write finished',
        ),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metadataPreviewRow('Verified', '$succeeded'),
                _metadataPreviewRow('Failed', '$failed'),
                _metadataPreviewRow('Skipped', '$skipped'),
                if (failures.isNotEmpty) ...[
                  const Divider(height: 28),
                  const Text(
                    'Needs review',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...failures
                      .take(20)
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SelectableText(
                            '${item.fileName}\n${item.message}',
                          ),
                        ),
                      ),
                  if (failures.length > 20)
                    Text(
                      '${failures.length - 20} additional items also need review.',
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (succeeded > 0) {
      await _scanLibrary(runAutomaticIntake: false);
    }
  }

  List<String> _metadataVerificationFailures(
    PhotoCatalogMetadata expected,
    PhotoMetadata actual,
  ) {
    final failures = <String>[];

    if (expected.description.trim().isNotEmpty &&
        actual.description.trim() != expected.description.trim()) {
      failures.add('Description');
    }

    final actualKeywords = actual.tags
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();

    final tagsVerified = expected.tags
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .every(actualKeywords.contains);
    if (!tagsVerified) failures.add('Tags / keywords');

    final peopleVerified = expected.people
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => 'person: $item'.toLowerCase())
        .every(actualKeywords.contains);
    if (!peopleVerified) failures.add('People');

    final expectedLocation = expected.location.trim();
    if (expectedLocation.isNotEmpty) {
      final actualLocation = (actual.technical['XMP Location'] ?? '').trim();
      if (actualLocation != expectedLocation) {
        failures.add('Location');
      }
    }

    return failures;
  }

  Widget _metadataPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 16),
          Text(value),
        ],
      ),
    );
  }

  PhotoCatalogMetadata _mergedDuplicateMetadata(
    VaultPhoto keep,
    VaultPhoto remove,
  ) {
    final keepMeta = _catalogByPath[keep.filePath];
    final removeMeta = _catalogByPath[remove.filePath];

    List<String> union(List<String>? first, List<String>? second) {
      final values = <String>{};
      for (final item in first ?? const <String>[]) {
        if (item.trim().isNotEmpty) values.add(item.trim());
      }
      for (final item in second ?? const <String>[]) {
        if (item.trim().isNotEmpty) values.add(item.trim());
      }
      return values.toList();
    }

    String prefer(String? first, String? second) {
      if (first != null && first.trim().isNotEmpty) return first.trim();
      return second?.trim() ?? '';
    }

    String combineNotes(String? first, String? second) {
      final parts = <String>[];
      if (first != null && first.trim().isNotEmpty) parts.add(first.trim());
      if (second != null &&
          second.trim().isNotEmpty &&
          !parts.contains(second.trim())) {
        parts.add(second.trim());
      }
      return parts.join('\n\n');
    }

    return PhotoCatalogMetadata(
      filePath: keep.filePath,
      people: union(keepMeta?.people, removeMeta?.people),
      tags: union(keepMeta?.tags, removeMeta?.tags),
      approximateDate: prefer(
        keepMeta?.approximateDate,
        removeMeta?.approximateDate,
      ),
      location: prefer(keepMeta?.location, removeMeta?.location),
      description: prefer(keepMeta?.description, removeMeta?.description),
      backWriting: prefer(keepMeta?.backWriting, removeMeta?.backWriting),
      notes: combineNotes(keepMeta?.notes, removeMeta?.notes),
    );
  }

  Future<Directory> _photoTrashDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      path.join(documents.path, 'Heirloom Atlas', 'Photo Trash'),
    );
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _photoTrashManifestFile() async {
    final directory = await _photoTrashDirectory();
    return File(path.join(directory.path, 'photo_trash_manifest.json'));
  }

  Future<List<Map<String, Object?>>> _getPhotoTrashEntries() async {
    final directory = await _photoTrashDirectory();
    final manifestFile = await _photoTrashManifestFile();
    final manifestByTrashPath = <String, Map<String, Object?>>{};

    if (manifestFile.existsSync()) {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final row = Map<String, Object?>.from(item);
              final trashPath = row['trash_path'] as String? ?? '';
              if (trashPath.isNotEmpty) {
                manifestByTrashPath[trashPath] = row;
              }
            }
          }
        }
      } catch (_) {
        // A damaged manifest should never hide recoverable files.
      }
    }

    final files =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (file) => path.basename(file.path) != 'photo_trash_manifest.json',
            )
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );

    return files.map((file) {
      final existing = manifestByTrashPath[file.path];
      return <String, Object?>{
        'trash_path': file.path,
        'original_path': existing?['original_path'] ?? '',
        'trashed_at_milliseconds':
            existing?['trashed_at_milliseconds'] ??
            file.lastModifiedSync().millisecondsSinceEpoch,
      };
    }).toList();
  }

  Future<void> _writePhotoTrashEntries(
    List<Map<String, Object?>> entries,
  ) async {
    final manifestFile = await _photoTrashManifestFile();
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entries),
      flush: true,
    );
  }

  Future<void> _recordPhotoTrashMove({
    required String originalPath,
    required String trashPath,
  }) async {
    final entries = await _getPhotoTrashEntries();
    entries.removeWhere(
      (entry) => (entry['trash_path'] as String?) == trashPath,
    );
    entries.add({
      'trash_path': trashPath,
      'original_path': originalPath,
      'trashed_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    });
    await _writePhotoTrashEntries(entries);
  }

  Future<void> _removePhotoTrashManifestEntry(String trashPath) async {
    final entries = await _getPhotoTrashEntries();
    entries.removeWhere(
      (entry) => (entry['trash_path'] as String?) == trashPath,
    );
    await _writePhotoTrashEntries(entries);
  }

  Future<String> _uniquePhotoTrashPath(VaultPhoto photo) async {
    final directory = await _photoTrashDirectory();
    final extension = path.extension(photo.fileName);
    final base = path.basenameWithoutExtension(photo.fileName);
    var candidate = path.join(directory.path, photo.fileName);
    var number = 2;

    while (File(candidate).existsSync()) {
      candidate = path.join(directory.path, '$base ($number)$extension');
      number++;
    }
    return candidate;
  }

  Future<bool> _movePhotoToTrash(VaultPhoto photo) async {
    final file = File(photo.filePath);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The source photo could not be found.')),
        );
      }
      return false;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Move photo to trash?'),
            content: Text(
              '"${photo.fileName}" will be removed from its source folder and '
              'moved to Heirloom Atlas Photo Trash.\n\n'
              'You can restore it later. It will not be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Move to Photo Trash'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return false;

    try {
      final destination = await _uniquePhotoTrashPath(photo);
      try {
        await file.rename(destination);
      } on FileSystemException {
        await file.copy(destination);
        await file.delete();
      }

      await _recordPhotoTrashMove(
        originalPath: photo.filePath,
        trashPath: destination,
      );
      await _scanLibrary(runAutomaticIntake: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${photo.fileName} moved to Photo Trash. The original location '
              'was saved for restoration.',
            ),
          ),
        );
      }
      return true;
    } on FileSystemException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Heirloom Atlas could not move this source file. '
              'The source may be read-only or unavailable.\n$error',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _moveSelectedSearchPhotosToTrash(
    List<VaultPhoto> visiblePhotos,
  ) async {
    final selectedPhotos = visiblePhotos
        .where((photo) => _selectedPaths.contains(photo.filePath))
        .toList();

    if (selectedPhotos.isEmpty) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              'Move ${selectedPhotos.length} '
              '${selectedPhotos.length == 1 ? 'photo' : 'photos'} to trash?',
            ),
            content: Text(
              'The selected ${selectedPhotos.length == 1 ? 'photo' : 'photos'} '
              'will be removed from their source '
              '${selectedPhotos.length == 1 ? 'folder' : 'folders'} and moved '
              'to Heirloom Atlas Photo Trash.\n\n'
              'You can restore them later. They will not be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_outline),
                label: Text('Move ${selectedPhotos.length} to Photo Trash'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    var movedCount = 0;
    final failedNames = <String>[];

    for (final photo in selectedPhotos) {
      final file = File(photo.filePath);
      if (!file.existsSync()) {
        failedNames.add(photo.fileName);
        continue;
      }

      try {
        final destination = await _uniquePhotoTrashPath(photo);
        try {
          await file.rename(destination);
        } on FileSystemException {
          await file.copy(destination);
          await file.delete();
        }

        await _recordPhotoTrashMove(
          originalPath: photo.filePath,
          trashPath: destination,
        );
        movedCount++;
      } on FileSystemException {
        failedNames.add(photo.fileName);
      }
    }

    // Re-index once after the entire batch instead of once per photo.
    if (movedCount > 0) {
      await _scanLibrary(runAutomaticIntake: false);
    }

    if (!mounted) return;

    setState(() {
      _selectedPaths.clear();
      _searchSelectionMode = false;
    });

    final message = failedNames.isEmpty
        ? '$movedCount ${movedCount == 1 ? 'photo' : 'photos'} moved to Photo Trash.'
        : '$movedCount moved to Photo Trash. ${failedNames.length} could not be moved.';

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _restorePhotoTrashEntry(
    Map<String, Object?> entry, {
    bool rescan = true,
  }) async {
    final trashPath = entry['trash_path'] as String? ?? '';
    if (trashPath.isEmpty) return false;

    final file = File(trashPath);
    if (!file.existsSync()) {
      await _removePhotoTrashManifestEntry(trashPath);
      return false;
    }

    final originalPath = entry['original_path'] as String? ?? '';
    if (originalPath.isEmpty) return false;

    final parent = Directory(path.dirname(originalPath));
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    final destination = await _uniqueRestorePath(originalPath);
    try {
      await file.rename(destination);
    } on FileSystemException {
      await file.copy(destination);
      await file.delete();
    }

    await _removePhotoTrashManifestEntry(trashPath);
    if (rescan) {
      await _scanLibrary(runAutomaticIntake: false);
    }
    return true;
  }

  Future<bool> _deletePhotoTrashEntryWithoutConfirmation(
    Map<String, Object?> entry,
  ) async {
    final trashPath = entry['trash_path'] as String? ?? '';
    if (trashPath.isEmpty) return false;

    final file = File(trashPath);
    if (file.existsSync()) {
      await file.delete();
    }
    await _removePhotoTrashManifestEntry(trashPath);
    return true;
  }

  Future<bool> _permanentlyDeletePhotoTrashEntry(
    Map<String, Object?> entry,
  ) async {
    final trashPath = entry['trash_path'] as String? ?? '';
    if (trashPath.isEmpty) return false;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Permanently delete photo?'),
            content: Text(
              'This permanently deletes "${path.basename(trashPath)}" from '
              'Photo Trash. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete Permanently'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return false;

    return _deletePhotoTrashEntryWithoutConfirmation(entry);
  }

  Future<void> _openPhotoTrash() async {
    var entries = await _getPhotoTrashEntries();
    final selectedTrashPaths = <String>{};
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refresh() async {
            entries = await _getPhotoTrashEntries();
            final available = entries
                .map((entry) => entry['trash_path'] as String? ?? '')
                .where((value) => value.isNotEmpty)
                .toSet();
            selectedTrashPaths.removeWhere(
              (trashPath) => !available.contains(trashPath),
            );
            if (dialogContext.mounted) {
              setDialogState(() {});
            }
          }

          final allPaths = entries
              .map((entry) => entry['trash_path'] as String? ?? '')
              .where((value) => value.isNotEmpty)
              .toSet();
          final allSelected =
              allPaths.isNotEmpty &&
              allPaths.every(selectedTrashPaths.contains);

          Future<void> restoreSelected() async {
            if (selectedTrashPaths.isEmpty) return;

            final selectedEntries = entries.where((entry) {
              final trashPath = entry['trash_path'] as String? ?? '';
              return selectedTrashPaths.contains(trashPath);
            }).toList();

            var restored = 0;
            for (final entry in selectedEntries) {
              if (await _restorePhotoTrashEntry(entry, rescan: false)) {
                restored++;
              }
            }

            if (restored > 0) {
              await _scanLibrary(runAutomaticIntake: false);
            }

            selectedTrashPaths.clear();
            await refresh();

            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(
                content: Text(
                  '$restored ${restored == 1 ? 'photo' : 'photos'} restored.',
                ),
              ),
            );
          }

          Future<void> deleteSelected() async {
            if (selectedTrashPaths.isEmpty) return;

            final count = selectedTrashPaths.length;
            final confirmed =
                await showDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: Text(
                      'Permanently delete $count '
                      '${count == 1 ? 'photo' : 'photos'}?',
                    ),
                    content: const Text(
                      'The selected photos will be permanently deleted from '
                      'Photo Trash. This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(confirmContext, true),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: Text('Delete $count Permanently'),
                      ),
                    ],
                  ),
                ) ??
                false;

            if (!confirmed) return;

            final selectedEntries = entries.where((entry) {
              final trashPath = entry['trash_path'] as String? ?? '';
              return selectedTrashPaths.contains(trashPath);
            }).toList();

            var deleted = 0;
            for (final entry in selectedEntries) {
              if (await _deletePhotoTrashEntryWithoutConfirmation(entry)) {
                deleted++;
              }
            }

            selectedTrashPaths.clear();
            await refresh();

            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(
                content: Text(
                  '$deleted ${deleted == 1 ? 'photo' : 'photos'} permanently deleted.',
                ),
              ),
            );
          }

          return Dialog(
            child: SizedBox(
              width: 860,
              height: 680,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Photo Trash',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                selectedTrashPaths.isEmpty
                                    ? '${entries.length} recoverable ${entries.length == 1 ? 'photo' : 'photos'}'
                                    : '${selectedTrashPaths.length} selected',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: allSelected,
                          tristate:
                              selectedTrashPaths.isNotEmpty && !allSelected,
                          onChanged: (_) {
                            setDialogState(() {
                              if (allSelected) {
                                selectedTrashPaths.clear();
                              } else {
                                selectedTrashPaths
                                  ..clear()
                                  ..addAll(allPaths);
                              }
                            });
                          },
                        ),
                        TextButton(
                          onPressed: entries.isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    if (allSelected) {
                                      selectedTrashPaths.clear();
                                    } else {
                                      selectedTrashPaths
                                        ..clear()
                                        ..addAll(allPaths);
                                    }
                                  });
                                },
                          child: Text(allSelected ? 'Clear All' : 'Select All'),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: selectedTrashPaths.isEmpty
                              ? null
                              : restoreSelected,
                          icon: const Icon(Icons.restore, size: 18),
                          label: Text(
                            selectedTrashPaths.isEmpty
                                ? 'Restore Selected'
                                : 'Restore (${selectedTrashPaths.length})',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: selectedTrashPaths.isEmpty
                              ? null
                              : deleteSelected,
                          icon: const Icon(
                            Icons.delete_forever_outlined,
                            size: 18,
                          ),
                          label: Text(
                            selectedTrashPaths.isEmpty
                                ? 'Delete Selected'
                                : 'Delete (${selectedTrashPaths.length})',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Photos here were removed from their source folders. '
                        'Restore returns them to the saved original location. '
                        'Permanent deletion cannot be undone.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(child: Text('Photo Trash is empty.'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(10),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final trashPath =
                                  entry['trash_path'] as String? ?? '';
                              final originalPath =
                                  entry['original_path'] as String? ?? '';
                              final selected = selectedTrashPaths.contains(
                                trashPath,
                              );

                              return ListTile(
                                selected: selected,
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: selected,
                                      onChanged: (_) {
                                        setDialogState(() {
                                          if (selected) {
                                            selectedTrashPaths.remove(
                                              trashPath,
                                            );
                                          } else if (trashPath.isNotEmpty) {
                                            selectedTrashPaths.add(trashPath);
                                          }
                                        });
                                      },
                                    ),
                                    SizedBox(
                                      width: 58,
                                      height: 58,
                                      child: Image.file(
                                        File(trashPath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedTrashPaths.remove(trashPath);
                                    } else if (trashPath.isNotEmpty) {
                                      selectedTrashPaths.add(trashPath);
                                    }
                                  });
                                },
                                title: Text(
                                  path.basename(trashPath),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  originalPath.isEmpty
                                      ? 'Original location unavailable'
                                      : originalPath,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () async {
                                        final restored =
                                            await _restorePhotoTrashEntry(
                                              entry,
                                            );
                                        if (restored) {
                                          await refresh();
                                        }
                                      },
                                      icon: const Icon(Icons.restore),
                                      label: const Text('Restore'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        final deleted =
                                            await _permanentlyDeletePhotoTrashEntry(
                                              entry,
                                            );
                                        if (deleted) {
                                          await refresh();
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.delete_forever_outlined,
                                      ),
                                      label: const Text('Delete Permanently'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await _loadOrganizerCounts();
  }

  Future<Directory> _duplicateTrashDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      path.join(documents.path, 'Heirloom Atlas', 'Duplicate Trash'),
    );
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _duplicateTrashManifestFile() async {
    final directory = await _duplicateTrashDirectory();
    return File(path.join(directory.path, 'duplicate_trash_manifest.json'));
  }

  Future<List<Map<String, Object?>>> _getDuplicateTrashEntries() async {
    final directory = await _duplicateTrashDirectory();
    final manifestFile = await _duplicateTrashManifestFile();

    if (await manifestFile.exists()) {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is List) {
          final entries = <Map<String, Object?>>[];
          for (final item in decoded) {
            if (item is! Map) continue;
            final row = Map<String, Object?>.from(item);
            final trashPath = row['trash_path'] as String? ?? '';
            if (trashPath.isEmpty) continue;
            entries.add(<String, Object?>{
              'trash_path': trashPath,
              'original_path': row['original_path'] ?? '',
              'trashed_at_milliseconds': row['trashed_at_milliseconds'] ?? 0,
            });
          }
          entries.sort(
            (a, b) => _dbInt(
              b['trashed_at_milliseconds'],
            ).compareTo(_dbInt(a['trashed_at_milliseconds'])),
          );
          return entries;
        }
      } catch (_) {
        // Fall through to a one-time folder rebuild if the manifest is damaged.
      }
    }

    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .where(
          (file) => path.basename(file.path) != 'duplicate_trash_manifest.json',
        )
        .toList();

    final entries = <Map<String, Object?>>[];
    for (final file in files) {
      int modified = 0;
      try {
        modified = (await file.lastModified()).millisecondsSinceEpoch;
      } catch (_) {}
      entries.add(<String, Object?>{
        'trash_path': file.path,
        'original_path': '',
        'trashed_at_milliseconds': modified,
      });
    }
    entries.sort(
      (a, b) => _dbInt(
        b['trashed_at_milliseconds'],
      ).compareTo(_dbInt(a['trashed_at_milliseconds'])),
    );
    await _writeDuplicateTrashEntries(entries);
    return entries;
  }

  Future<void> _writeDuplicateTrashEntries(
    List<Map<String, Object?>> entries,
  ) async {
    final manifestFile = await _duplicateTrashManifestFile();
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entries),
      flush: true,
    );
  }

  Future<void> _recordDuplicateTrashMove({
    required String originalPath,
    required String trashPath,
  }) async {
    final entries = await _getDuplicateTrashEntries();
    entries.removeWhere(
      (entry) => (entry['trash_path'] as String?) == trashPath,
    );
    entries.add({
      'trash_path': trashPath,
      'original_path': originalPath,
      'trashed_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeDuplicateTrashEntries(entries);
  }

  Future<void> _removeDuplicateTrashManifestEntry(String trashPath) async {
    final entries = await _getDuplicateTrashEntries();
    entries.removeWhere(
      (entry) => (entry['trash_path'] as String?) == trashPath,
    );
    await _writeDuplicateTrashEntries(entries);
  }

  Future<String> _uniqueTrashPath(VaultPhoto photo) async {
    final directory = await _duplicateTrashDirectory();
    final extension = path.extension(photo.fileName);
    final base = path.basenameWithoutExtension(photo.fileName);
    var candidate = path.join(directory.path, photo.fileName);
    var number = 2;

    while (File(candidate).existsSync()) {
      candidate = path.join(directory.path, '$base ($number)$extension');
      number++;
    }
    return candidate;
  }

  Future<String> _movePhotoFileToDuplicateTrash(VaultPhoto photo) async {
    final file = File(photo.filePath);
    if (!file.existsSync()) return '';

    final destination = await _uniqueTrashPath(photo);
    try {
      await file.rename(destination);
    } on FileSystemException {
      await file.copy(destination);
      await file.delete();
    }

    await _recordDuplicateTrashMove(
      originalPath: photo.filePath,
      trashPath: destination,
    );
    return destination;
  }

  Future<int> _movePhotosToDuplicateTrashBatch(List<VaultPhoto> photos) async {
    if (photos.isEmpty) return 0;

    final directory = await _duplicateTrashDirectory();
    final entries = await _getDuplicateTrashEntries();
    final usedTrashPaths = directory
        .listSync()
        .whereType<File>()
        .map((file) => path.normalize(file.path).toLowerCase())
        .toSet();

    var moved = 0;
    for (final photo in photos) {
      final file = File(photo.filePath);
      if (!file.existsSync()) continue;

      final extension = path.extension(photo.fileName);
      final base = path.basenameWithoutExtension(photo.fileName);
      var destination = path.join(directory.path, photo.fileName);
      var number = 2;
      while (usedTrashPaths.contains(
        path.normalize(destination).toLowerCase(),
      )) {
        destination = path.join(directory.path, '$base ($number)$extension');
        number++;
      }

      try {
        await file.rename(destination);
      } on FileSystemException {
        await file.copy(destination);
        await file.delete();
      }

      usedTrashPaths.add(path.normalize(destination).toLowerCase());
      entries.add({
        'trash_path': destination,
        'original_path': photo.filePath,
        'trashed_at_milliseconds': DateTime.now().millisecondsSinceEpoch,
      });
      moved++;
    }

    if (moved > 0) {
      await _writeDuplicateTrashEntries(entries);
    }
    return moved;
  }

  Future<String> _uniqueRestorePath(String desiredPath) async {
    if (!File(desiredPath).existsSync()) return desiredPath;

    final directory = path.dirname(desiredPath);
    final extension = path.extension(desiredPath);
    final base = path.basenameWithoutExtension(desiredPath);
    var number = 2;
    var candidate = path.join(directory, '$base restored ($number)$extension');

    while (File(candidate).existsSync()) {
      number++;
      candidate = path.join(directory, '$base restored ($number)$extension');
    }
    return candidate;
  }

  Future<bool> _restoreDuplicateTrashEntry(Map<String, Object?> entry) async {
    final trashPath = entry['trash_path'] as String? ?? '';
    if (trashPath.isEmpty) return false;

    final file = File(trashPath);
    if (!file.existsSync()) {
      await _removeDuplicateTrashManifestEntry(trashPath);
      return false;
    }

    var originalPath = entry['original_path'] as String? ?? '';
    if (originalPath.isEmpty) {
      final libraryPath = _libraryPath;
      if (libraryPath == null || libraryPath.isEmpty) return false;
      originalPath = path.join(libraryPath, path.basename(trashPath));
    }

    final parent = Directory(path.dirname(originalPath));
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    final destination = await _uniqueRestorePath(originalPath);
    try {
      await file.rename(destination);
    } on FileSystemException {
      await file.copy(destination);
      await file.delete();
    }

    // Do not remove the safety-net manifest entry until the restored file is
    // confirmed at its destination. Duplicate-trash moves leave the existing
    // indexed photo/source records intact, so a full library rescan is not
    // needed to restore visibility.
    if (!File(destination).existsSync()) {
      return false;
    }

    await _removeDuplicateTrashManifestEntry(trashPath);
    return true;
  }

  Future<bool> _permanentlyDeleteTrashEntry(Map<String, Object?> entry) async {
    final trashPath = entry['trash_path'] as String? ?? '';
    if (trashPath.isEmpty) return false;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Permanently delete photo?'),
            content: Text(
              'This permanently deletes "${path.basename(trashPath)}" from '
              'Duplicate Trash. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete Permanently'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return false;

    final file = File(trashPath);
    if (file.existsSync()) {
      await file.delete();
    }
    await _removeDuplicateTrashManifestEntry(trashPath);
    return true;
  }

  Future<void> _openDuplicateTrash() async {
    var entries = await _getDuplicateTrashEntries();
    if (!mounted) return;

    final selectedTrashPaths = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> refresh() async {
              final updated = await _getDuplicateTrashEntries();
              if (!dialogContext.mounted) return;
              setDialogState(() {
                entries = updated;
                final availablePaths = entries
                    .map((entry) => entry['trash_path'] as String? ?? '')
                    .where((value) => value.isNotEmpty)
                    .toSet();
                selectedTrashPaths.removeWhere(
                  (value) => !availablePaths.contains(value),
                );
              });
            }

            final allPaths = entries
                .map((entry) => entry['trash_path'] as String? ?? '')
                .where((value) => value.isNotEmpty)
                .toSet();
            final allSelected =
                allPaths.isNotEmpty &&
                selectedTrashPaths.length == allPaths.length &&
                selectedTrashPaths.containsAll(allPaths);

            Future<void> restoreSelected() async {
              final selectedEntries = entries.where((entry) {
                final trashPath = entry['trash_path'] as String? ?? '';
                return selectedTrashPaths.contains(trashPath);
              }).toList();

              var restored = 0;
              for (final entry in selectedEntries) {
                if (await _restoreDuplicateTrashEntry(entry)) {
                  restored++;
                }
              }

              selectedTrashPaths.clear();
              if (restored > 0) {
                // Restored duplicates are already represented by their original
                // indexed-photo/source records. Refresh those records directly
                // instead of rescanning the library root (for example G:\\).
                final photos = await _databaseHelper.getIndexedPhotos();
                if (mounted) {
                  setState(() {
                    _photos = photos;
                  });
                  await _loadOrganizerCounts();
                }
              }
              await refresh();

              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    '$restored ${restored == 1 ? 'photo' : 'photos'} restored.',
                  ),
                ),
              );
            }

            Future<void> deleteSelected() async {
              final count = selectedTrashPaths.length;
              if (count == 0) return;

              final confirmed =
                  await showDialog<bool>(
                    context: dialogContext,
                    builder: (confirmContext) => AlertDialog(
                      title: Text(
                        count == 1
                            ? 'Delete selected photo permanently?'
                            : 'Delete $count selected photos permanently?',
                      ),
                      content: const Text(
                        'This cannot be undone. The selected files will be '
                        'permanently deleted from Duplicate Trash.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(confirmContext, true),
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: const Text('Delete Permanently'),
                        ),
                      ],
                    ),
                  ) ??
                  false;

              if (!confirmed) return;

              final selectedEntries = entries.where((entry) {
                final trashPath = entry['trash_path'] as String? ?? '';
                return selectedTrashPaths.contains(trashPath);
              }).toList();

              var deleted = 0;
              for (final entry in selectedEntries) {
                final trashPath = entry['trash_path'] as String? ?? '';
                if (trashPath.isEmpty) continue;
                try {
                  final file = File(trashPath);
                  if (await file.exists()) {
                    await file.delete();
                  }
                  deleted++;
                } catch (_) {}
              }

              if (deleted > 0) {
                final remaining = await _getDuplicateTrashEntries();
                final deletedPaths = selectedEntries
                    .map((entry) => entry['trash_path'] as String? ?? '')
                    .where((value) => value.isNotEmpty)
                    .toSet();
                final cleaned = remaining
                    .where(
                      (entry) => !deletedPaths.contains(
                        entry['trash_path'] as String? ?? '',
                      ),
                    )
                    .toList();
                await _writeDuplicateTrashEntries(cleaned);
              }

              selectedTrashPaths.clear();
              await refresh();

              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    '$deleted ${deleted == 1 ? 'photo' : 'photos'} permanently deleted.',
                  ),
                ),
              );
            }

            return Dialog(
              child: SizedBox(
                width: 860,
                height: 680,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
                      child: Row(
                        children: [
                          const Icon(Icons.delete_sweep_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Duplicate Trash',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  selectedTrashPaths.isEmpty
                                      ? '${entries.length} recoverable '
                                            '${entries.length == 1 ? 'photo' : 'photos'}'
                                      : '${selectedTrashPaths.length} selected',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: Row(
                        children: [
                          Checkbox(
                            value: allSelected,
                            tristate:
                                selectedTrashPaths.isNotEmpty && !allSelected,
                            onChanged: entries.isEmpty
                                ? null
                                : (_) {
                                    setDialogState(() {
                                      if (allSelected) {
                                        selectedTrashPaths.clear();
                                      } else {
                                        selectedTrashPaths
                                          ..clear()
                                          ..addAll(allPaths);
                                      }
                                    });
                                  },
                          ),
                          TextButton(
                            onPressed: entries.isEmpty
                                ? null
                                : () {
                                    setDialogState(() {
                                      if (allSelected) {
                                        selectedTrashPaths.clear();
                                      } else {
                                        selectedTrashPaths
                                          ..clear()
                                          ..addAll(allPaths);
                                      }
                                    });
                                  },
                            child: Text(
                              allSelected ? 'Clear All' : 'Select All',
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: selectedTrashPaths.isEmpty
                                ? null
                                : restoreSelected,
                            icon: const Icon(Icons.restore, size: 18),
                            label: Text(
                              selectedTrashPaths.isEmpty
                                  ? 'Restore Selected'
                                  : 'Restore (${selectedTrashPaths.length})',
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: selectedTrashPaths.isEmpty
                                ? null
                                : deleteSelected,
                            icon: const Icon(
                              Icons.delete_forever_outlined,
                              size: 18,
                            ),
                            label: Text(
                              selectedTrashPaths.isEmpty
                                  ? 'Delete Selected'
                                  : 'Delete (${selectedTrashPaths.length})',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(
                              child: Text('Duplicate Trash is empty.'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: entries.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                final trashPath =
                                    entry['trash_path'] as String? ?? '';
                                final originalPath =
                                    entry['original_path'] as String? ?? '';
                                final selected = selectedTrashPaths.contains(
                                  trashPath,
                                );

                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    selected: selected,
                                    leading: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Checkbox(
                                          value: selected,
                                          onChanged: (_) {
                                            setDialogState(() {
                                              if (selected) {
                                                selectedTrashPaths.remove(
                                                  trashPath,
                                                );
                                              } else if (trashPath.isNotEmpty) {
                                                selectedTrashPaths.add(
                                                  trashPath,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                        SizedBox(
                                          width: 58,
                                          height: 58,
                                          child: Image.file(
                                            File(trashPath),
                                            fit: BoxFit.cover,
                                            cacheWidth: 120,
                                            cacheHeight: 120,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(
                                                  Icons.broken_image_outlined,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      setDialogState(() {
                                        if (selected) {
                                          selectedTrashPaths.remove(trashPath);
                                        } else if (trashPath.isNotEmpty) {
                                          selectedTrashPaths.add(trashPath);
                                        }
                                      });
                                    },
                                    title: Text(path.basename(trashPath)),
                                    subtitle: Text(
                                      originalPath.isEmpty
                                          ? 'Original location unavailable'
                                          : 'Original: $originalPath',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Wrap(
                                      spacing: 6,
                                      children: [
                                        FilledButton.tonalIcon(
                                          onPressed: () async {
                                            final restored =
                                                await _restoreDuplicateTrashEntry(
                                                  entry,
                                                );
                                            if (restored) {
                                              selectedTrashPaths.remove(
                                                trashPath,
                                              );
                                              // No full-drive rescan: the
                                              // original indexed record remains
                                              // valid after a duplicate restore.
                                              final photos =
                                                  await _databaseHelper
                                                      .getIndexedPhotos();
                                              if (mounted) {
                                                setState(() {
                                                  _photos = photos;
                                                });
                                                await _loadOrganizerCounts();
                                              }
                                            }
                                            await refresh();
                                          },
                                          icon: const Icon(
                                            Icons.restore_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('Restore'),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete permanently',
                                          onPressed: () async {
                                            final deleted =
                                                await _permanentlyDeleteTrashEntry(
                                                  entry,
                                                );
                                            if (deleted) {
                                              selectedTrashPaths.remove(
                                                trashPath,
                                              );
                                              await refresh();
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.delete_forever_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(11),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Duplicate cleanup is recoverable until you choose '
                              'Delete Permanently.',
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await _loadOrganizerCounts();
  }

  Future<bool> _moveDuplicateToTrash(
    VaultPhoto photo, {
    required String actionLabel,
  }) async {
    final file = File(photo.filePath);
    if (!file.existsSync()) return true;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(actionLabel),
            content: Text(
              'Move "${photo.fileName}" out of your photo library and into '
              'Heirloom Atlas Duplicate Trash?\n\n'
              'The original file will not be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Move to Trash'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return false;

    await _movePhotoFileToDuplicateTrash(photo);
    await _refreshDuplicateTrashCountOnly();
    return true;
  }

  Future<bool> _mergeDuplicateAndKeep(
    VaultPhoto keep,
    VaultPhoto remove,
  ) async {
    final before =
        _catalogByPath[keep.filePath] ??
        PhotoCatalogMetadata(filePath: keep.filePath);
    final merged = _mergedDuplicateMetadata(keep, remove);

    final changedFields = <String>[];
    if (!setEquals(before.people.toSet(), merged.people.toSet())) {
      changedFields.add('People');
    }
    if (!setEquals(before.tags.toSet(), merged.tags.toSet())) {
      changedFields.add('Tags');
    }
    if (before.approximateDate != merged.approximateDate) {
      changedFields.add('Date');
    }
    if (before.location != merged.location) {
      changedFields.add('Location');
    }
    if (before.description != merged.description) {
      changedFields.add('Description');
    }
    if (before.backWriting != merged.backWriting) {
      changedFields.add('Back writing');
    }
    if (before.notes != merged.notes) {
      changedFields.add('Notes');
    }

    await _databaseHelper.savePhotoCatalogMetadata(merged);

    if (changedFields.isNotEmpty) {
      await _syncService.recordLocalChange(
        entityType: 'photo',
        localKey: merged.filePath,
        operation: 'update',
        changedFields: changedFields,
      );
    }

    await _movePhotoFileToDuplicateTrash(remove);

    _catalogByPath[keep.filePath] = merged;
    await _refreshDuplicateTrashCountOnly();
    return true;
  }

  String _persistentDuplicatePairKey(String firstPath, String secondPath) {
    final first = path.normalize(firstPath).toLowerCase();
    final second = path.normalize(secondPath).toLowerCase();
    return first.compareTo(second) <= 0 ? '$first|$second' : '$second|$first';
  }

  Future<Set<String>> _getRejectedPossibleDuplicatePairs() async {
    final raw = await _databaseHelper.getSetting(
      'photo_possible_duplicate_not_matches',
    );
    if (raw == null || raw.trim().isEmpty) return <String>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<bool> _savePossibleDuplicateNotMatch(
    _PossibleDuplicatePair pair,
  ) async {
    try {
      final rejected = await _getRejectedPossibleDuplicatePairs();
      rejected.add(
        _persistentDuplicatePairKey(pair.first.filePath, pair.second.filePath),
      );

      final sorted = rejected.toList()..sort();
      await _databaseHelper.setSetting(
        'photo_possible_duplicate_not_matches',
        jsonEncode(sorted),
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save Not a Match decision: $error'),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _refreshAfterDuplicateActions() async {
    await _scanLibrary(runAutomaticIntake: false);
    await _loadOrganizerCounts();
  }

  Future<int?> _findPossibleDuplicates({
    bool showResults = true,
    Set<String>? countOnlyPaths,
  }) async {
    if (_possibleDuplicateScanning ||
        _duplicateScanning ||
        _photos.length < 2) {
      return null;
    }

    final generation = ++_possibleDuplicateScanGeneration;

    setState(() {
      _possibleDuplicateScanning = true;
      _duplicateScanCurrent = 0;
      _duplicateScanTotal = _photos.length;
    });

    try {
      final stored = await _databaseHelper.getPhotoFingerprints();

      // Avoid checking every indexed photo on disk before opening Duplicate
      // Review. On large libraries (especially OneDrive) thousands of
      // synchronous existsSync() calls can make the review feel frozen.
      // We only need to exclude files Heirloom Atlas itself already moved to
      // Duplicate Trash; unreadable/missing files that still need a new
      // fingerprint are skipped safely by the fingerprint worker.
      final duplicateTrashEntries = await _getDuplicateTrashEntries();
      final trashedOriginalPaths = duplicateTrashEntries
          .map((entry) => entry['original_path'] as String? ?? '')
          .where((value) => value.isNotEmpty)
          .map((value) => path.normalize(value).toLowerCase())
          .toSet();

      final livePhotos = _photos
          .where(
            (photo) => !trashedOriginalPaths.contains(
              path.normalize(photo.filePath).toLowerCase(),
            ),
          )
          .toList();
      final photoByPath = <String, VaultPhoto>{
        for (final photo in livePhotos) photo.filePath: photo,
      };
      final records = <Map<String, Object?>>[];
      final pending = <VaultPhoto>[];

      for (final photo in livePhotos) {
        final row = stored[photo.filePath];
        if (row != null &&
            _dbInt(row['file_size']) == photo.fileSize &&
            _dbInt(row['modified_milliseconds']) ==
                photo.modifiedMilliseconds &&
            (row['hash_hex'] as String? ?? '').isNotEmpty) {
          records.add({
            'file_path': photo.filePath,
            'file_size': photo.fileSize,
            'modified_milliseconds': photo.modifiedMilliseconds,
            'hash_hex': row['hash_hex'] as String? ?? '0',
            'average_r': _dbInt(row['average_r']),
            'average_g': _dbInt(row['average_g']),
            'average_b': _dbInt(row['average_b']),
          });
        } else {
          pending.add(photo);
        }
      }

      const batchSize = 12;
      var completed = livePhotos.length - pending.length;

      for (var start = 0; start < pending.length; start += batchSize) {
        if (generation != _possibleDuplicateScanGeneration) return null;

        final end = (start + batchSize < pending.length)
            ? start + batchSize
            : pending.length;
        final batch = pending.sublist(start, end);
        final input = batch
            .map(
              (photo) => <String, Object?>{
                'file_path': photo.filePath,
                'file_size': photo.fileSize,
                'modified_milliseconds': photo.modifiedMilliseconds,
              },
            )
            .toList();

        final results = await compute(_fingerprintPhotoBatch, input);

        if (generation != _possibleDuplicateScanGeneration) return null;

        for (final result in results) {
          if ((result['error'] as String? ?? '').isNotEmpty) continue;
          final filePath = result['file_path'] as String? ?? '';
          final photo = photoByPath[filePath];
          if (photo == null) continue;

          await _databaseHelper.savePhotoFingerprint(
            filePath: filePath,
            fileSize: photo.fileSize,
            modifiedMilliseconds: photo.modifiedMilliseconds,
            hashHex: result['hash_hex'] as String? ?? '0',
            averageR: _dbInt(result['average_r']),
            averageG: _dbInt(result['average_g']),
            averageB: _dbInt(result['average_b']),
          );

          records.add({
            'file_path': filePath,
            'file_size': photo.fileSize,
            'modified_milliseconds': photo.modifiedMilliseconds,
            'hash_hex': result['hash_hex'] as String? ?? '0',
            'average_r': _dbInt(result['average_r']),
            'average_g': _dbInt(result['average_g']),
            'average_b': _dbInt(result['average_b']),
          });
        }

        completed += batch.length;
        if (!mounted || generation != _possibleDuplicateScanGeneration) {
          return null;
        }
        setState(() => _duplicateScanCurrent = completed);
        await Future<void>.delayed(Duration.zero);
      }

      await _databaseHelper.deletePhotoFingerprintsNotIn(
        livePhotos.map((photo) => photo.filePath),
      );

      if (!mounted || generation != _possibleDuplicateScanGeneration) {
        return null;
      }

      // Label fingerprint records by source so the dedicated deep comparison
      // can compare Local Folder photos only against OneDrive photos.
      String sourceLabelForPath(String filePath) {
        final normalizedPhoto = path.normalize(filePath).toLowerCase();
        var label = 'Unknown source';
        var bestLength = -1;
        for (final source in _photoSources) {
          final root = (source['root_path']?.toString() ?? '').trim();
          if (root.isEmpty) continue;
          final normalizedRoot = path.normalize(root).toLowerCase();
          if ((normalizedPhoto == normalizedRoot ||
                  normalizedPhoto.startsWith(
                    '$normalizedRoot${path.separator}',
                  )) &&
              normalizedRoot.length > bestLength) {
            final display = (source['display_name']?.toString() ?? '').trim();
            label = display.isEmpty ? 'Photo Source' : display;
            bestLength = normalizedRoot.length;
          }
        }
        return label;
      }

      final comparisonRecords = records
          .map(
            (record) => <String, Object?>{
              ...record,
              'source_label': sourceLabelForPath(
                record['file_path'] as String? ?? '',
              ),
            },
          )
          .toList();

      final normalMatches = await compute(
        _compareFingerprintRecords,
        comparisonRecords,
      );
      final deepMatches = await compute(
        _compareLocalFolderToOneDriveDeep,
        comparisonRecords,
      );

      // Merge both matchers. The deep matcher never returns 100%; only the
      // byte-for-byte verification path may produce an automatic-safe 100%.
      final mergedByPair = <String, Map<String, Object?>>{};
      for (final match in [...normalMatches, ...deepMatches]) {
        final first = path
            .normalize(match['first_path'] as String? ?? '')
            .toLowerCase();
        final second = path
            .normalize(match['second_path'] as String? ?? '')
            .toLowerCase();
        if (first.isEmpty || second.isEmpty) continue;
        final key = first.compareTo(second) <= 0
            ? '$first|$second'
            : '$second|$first';
        final existing = mergedByPair[key];
        if (existing == null ||
            _dbInt(match['similarity']) > _dbInt(existing['similarity'])) {
          mergedByPair[key] = match;
        }
      }

      final matches = mergedByPair.values.toList()
        ..sort(
          (a, b) => _dbInt(b['similarity']).compareTo(_dbInt(a['similarity'])),
        );

      if (!mounted || generation != _possibleDuplicateScanGeneration) {
        return null;
      }

      final sourceCounts = <String, int>{};
      for (final photo in livePhotos) {
        final normalizedPhoto = path.normalize(photo.filePath).toLowerCase();
        var label = 'Unknown source';
        var bestLength = -1;
        for (final source in _photoSources) {
          final root = (source['root_path']?.toString() ?? '').trim();
          if (root.isEmpty) continue;
          final normalizedRoot = path.normalize(root).toLowerCase();
          if ((normalizedPhoto == normalizedRoot ||
                  normalizedPhoto.startsWith(
                    '$normalizedRoot${path.separator}',
                  )) &&
              normalizedRoot.length > bestLength) {
            final display = (source['display_name']?.toString() ?? '').trim();
            label = display.isEmpty ? 'Photo Source' : display;
            bestLength = normalizedRoot.length;
          }
        }
        sourceCounts[label] = (sourceCounts[label] ?? 0) + 1;
      }

      final rejectedPairs = await _getRejectedPossibleDuplicatePairs();
      final pairs = <_PossibleDuplicatePair>[];
      for (final match in matches) {
        final first = photoByPath[match['first_path'] as String? ?? ''];
        final second = photoByPath[match['second_path'] as String? ?? ''];
        if (first == null || second == null) continue;

        final pairKey = _persistentDuplicatePairKey(
          first.filePath,
          second.filePath,
        );
        if (rejectedPairs.contains(pairKey)) continue;

        pairs.add(
          _PossibleDuplicatePair(
            first: first,
            second: second,
            similarity: _dbInt(match['similarity']),
          ),
        );
      }

      setState(() {
        _possibleDuplicateScanning = false;
        _duplicateScanCurrent = _duplicateScanTotal;
      });

      await _databaseHelper.setSetting(
        'photo_possible_duplicate_count',
        pairs.length.toString(),
      );
      if (mounted) {
        setState(() => _possibleDuplicateCount = pairs.length);
      }

      String sourceForPhoto(VaultPhoto photo) {
        final normalizedPhoto = path.normalize(photo.filePath).toLowerCase();
        var label = 'Unknown';
        var bestLength = -1;
        for (final source in _photoSources) {
          final root = (source['root_path']?.toString() ?? '').trim();
          if (root.isEmpty) continue;
          final normalizedRoot = path.normalize(root).toLowerCase();
          if ((normalizedPhoto == normalizedRoot ||
                  normalizedPhoto.startsWith(
                    '$normalizedRoot${path.separator}',
                  )) &&
              normalizedRoot.length > bestLength) {
            final display = (source['display_name']?.toString() ?? '').trim();
            label = display.isEmpty ? 'Photo Source' : display;
            bestLength = normalizedRoot.length;
          }
        }
        return label;
      }

      final photosByName = <String, List<VaultPhoto>>{};
      for (final photo in livePhotos) {
        final key = photo.fileName.trim().toLowerCase();
        if (key.isEmpty) continue;
        photosByName.putIfAbsent(key, () => <VaultPhoto>[]).add(photo);
      }

      var crossSourceSameNamePairs = 0;
      var crossSourceSameNameAndSizePairs = 0;
      for (final group in photosByName.values) {
        if (group.length < 2) continue;
        for (var i = 0; i < group.length; i++) {
          for (var j = i + 1; j < group.length; j++) {
            final firstSource = sourceForPhoto(group[i]);
            final secondSource = sourceForPhoto(group[j]);
            if (firstSource == secondSource) continue;
            crossSourceSameNamePairs++;
            if (group[i].fileSize == group[j].fileSize) {
              crossSourceSameNameAndSizePairs++;
            }
          }
        }
      }

      final matchBreakdown = <String, int>{};
      var exactLookingCount = 0;
      var similarCount = 0;
      for (final pair in pairs) {
        if (pair.similarity == 100) {
          exactLookingCount++;
        } else {
          similarCount++;
        }
        final labels = <String>[
          sourceForPhoto(pair.first),
          sourceForPhoto(pair.second),
        ]..sort();
        final key = '${labels[0]} ↔ ${labels[1]}';
        matchBreakdown[key] = (matchBreakdown[key] ?? 0) + 1;
      }

      if (showResults) {
        if (!mounted) return null;
        final changed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => _PossibleDuplicatesDialog(
            pairs: pairs,
            resultsLimited: pairs.length >= 200,
            onMoveToTrash: (photo) => _moveDuplicateToTrash(
              photo,
              actionLabel: 'Remove duplicate photo?',
            ),
            onMergeAndKeep: _mergeDuplicateAndKeep,
            onNotMatch: _savePossibleDuplicateNotMatch,
            catalogByPath: _catalogByPath,
            photoSources: _photoSources,
            sourceCounts: sourceCounts,
            indexedCount: livePhotos.length,
            fingerprintCount: records.length,
            matchBreakdown: matchBreakdown,
            exactLookingCount: exactLookingCount,
            similarCount: similarCount,
            crossSourceSameNamePairs: crossSourceSameNamePairs,
            crossSourceSameNameAndSizePairs: crossSourceSameNameAndSizePairs,
            onRemoveVerifiedLocalDuplicates: () async {
              final verifiedLocalPhotos = <VaultPhoto>[];
              final seenPaths = <String>{};

              String sourceFor(VaultPhoto photo) => sourceForPhoto(photo);

              for (final pair in pairs) {
                if (pair.similarity != 100) continue;
                final firstSource = sourceFor(pair.first);
                final secondSource = sourceFor(pair.second);

                VaultPhoto? localPhoto;
                if (firstSource == 'Local Folder' &&
                    secondSource == 'OneDrive') {
                  localPhoto = pair.first;
                } else if (secondSource == 'Local Folder' &&
                    firstSource == 'OneDrive') {
                  localPhoto = pair.second;
                }

                if (localPhoto != null) {
                  final key = path.normalize(localPhoto.filePath).toLowerCase();
                  if (seenPaths.add(key)) verifiedLocalPhotos.add(localPhoto);
                }
              }

              if (verifiedLocalPhotos.isEmpty) return 0;

              final removed = await _movePhotosToDuplicateTrashBatch(
                verifiedLocalPhotos,
              );
              await _refreshDuplicateTrashCountOnly();
              return removed;
            },
            onMoveSelectedLocalCopies: (selectedPhotos) async {
              if (selectedPhotos.isEmpty) return 0;
              final removed = await _movePhotosToDuplicateTrashBatch(
                selectedPhotos,
              );
              await _refreshDuplicateTrashCountOnly();
              return removed;
            },
          ),
        );
        if (changed == true && mounted) {
          await _refreshAfterDuplicateActions();
        }
      }

      if (countOnlyPaths != null && countOnlyPaths.isNotEmpty) {
        return pairs.where((pair) {
          return countOnlyPaths.contains(pair.first.filePath) ||
              countOnlyPaths.contains(pair.second.filePath);
        }).length;
      }

      return pairs.length;
    } catch (error) {
      if (!mounted || generation != _possibleDuplicateScanGeneration) {
        return null;
      }
      setState(() => _possibleDuplicateScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not scan for duplicate photos: $error')),
      );
      return null;
    }
  }

  int _dbInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _cancelPossibleDuplicateScan() {
    if (!_possibleDuplicateScanning) return;
    _possibleDuplicateScanGeneration++;
    setState(() {
      _possibleDuplicateScanning = false;
      _duplicateScanCurrent = 0;
      _duplicateScanTotal = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo analysis canceled. Completed fingerprints were saved.',
        ),
      ),
    );
  }

  Future<void> _findExactDuplicates() async {
    if (_duplicateScanning || _photos.length < 2) return;

    setState(() {
      _duplicateScanning = true;
      _duplicateScanCurrent = 0;
      _duplicateScanTotal = _photos.length;
    });

    try {
      final bySize = <int, List<VaultPhoto>>{};

      for (final photo in _photos) {
        final file = File(photo.filePath);
        if (!file.existsSync()) continue;
        bySize.putIfAbsent(photo.fileSize, () => <VaultPhoto>[]).add(photo);
      }

      final candidateGroups = bySize.values
          .where((group) => group.length > 1)
          .toList();

      final duplicates = <List<VaultPhoto>>[];
      var processed = 0;

      for (final sizeGroup in candidateGroups) {
        final remaining = List<VaultPhoto>.from(sizeGroup);

        while (remaining.isNotEmpty) {
          final seed = remaining.removeAt(0);
          final seedFile = File(seed.filePath);

          Uint8List seedBytes;
          try {
            seedBytes = await seedFile.readAsBytes();
          } catch (_) {
            processed++;
            if (mounted) {
              setState(() => _duplicateScanCurrent = processed);
            }
            continue;
          }

          final exact = <VaultPhoto>[seed];

          for (var i = remaining.length - 1; i >= 0; i--) {
            final candidate = remaining[i];
            try {
              final candidateBytes = await File(
                candidate.filePath,
              ).readAsBytes();

              if (_sameBytes(seedBytes, candidateBytes)) {
                exact.add(candidate);
                remaining.removeAt(i);
              }
            } catch (_) {
              // Skip unreadable individual files.
            }
          }

          if (exact.length > 1) {
            duplicates.add(exact);
          }

          processed += exact.length;
          if (mounted) {
            setState(() => _duplicateScanCurrent = processed);
          }

          // Yield briefly so the UI can repaint during large scans.
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (!mounted) return;

      setState(() {
        _duplicateScanning = false;
        _duplicateScanCurrent = _duplicateScanTotal;
      });

      final changed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _ExactDuplicatesDialog(
          groups: duplicates,
          catalogByPath: _catalogByPath,
          onMoveToTrash: (photo) => _moveDuplicateToTrash(
            photo,
            actionLabel: 'Remove exact duplicate?',
          ),
          onMergeAndKeep: _mergeDuplicateAndKeep,
        ),
      );
      if (changed == true && mounted) {
        await _refreshAfterDuplicateActions();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _duplicateScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not scan for duplicates: $error')),
      );
    }
  }

  bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.lengthInBytes != b.lengthInBytes) return false;

    for (var i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }

  Map<String, Object?>? _sourceForPhoto(VaultPhoto photo) {
    final candidates =
        _photoSources.where((source) {
          final rootPath = (source['root_path'] as String? ?? '').trim();
          if (rootPath.isEmpty) return false;
          return path.isWithin(rootPath, photo.filePath) ||
              path.equals(rootPath, path.dirname(photo.filePath));
        }).toList()..sort((a, b) {
          final aRoot = (a['root_path'] as String? ?? '').length;
          final bRoot = (b['root_path'] as String? ?? '').length;
          return bRoot.compareTo(aRoot);
        });

    return candidates.isEmpty ? null : candidates.first;
  }

  bool _matchesSelectedSource(VaultPhoto photo) {
    final selectedId = _selectedPhotoSourceId;
    if (selectedId == null) return true;
    final source = _sourceForPhoto(photo);
    return (source?['id'] as int?) == selectedId;
  }

  bool _matchesSearch(VaultPhoto photo) {
    if (!_matchesSelectedSource(photo)) return false;

    final query = _searchController.text.trim().toLowerCase();
    final metadata = _catalogByPath[photo.filePath];

    if (query.isNotEmpty) {
      final haystack = <String>[
        photo.fileName,
        photo.relativeFolder,
        metadata?.people.join(' ') ?? '',
        metadata?.tags.join(' ') ?? '',
        metadata?.approximateDate ?? '',
        metadata?.location ?? '',
        metadata?.description ?? '',
        metadata?.notes ?? '',
      ].join(' ').toLowerCase();

      if (!haystack.contains(query)) return false;
    }

    if (_quickFilters.contains('Uncataloged') && _hasAnyCatalogData(metadata)) {
      return false;
    }

    if (_quickFilters.contains('No People') &&
        !(metadata == null || metadata.people.isEmpty)) {
      return false;
    }

    if (_quickFilters.contains('No Date') &&
        !(metadata == null || metadata.approximateDate.trim().isEmpty)) {
      return false;
    }

    if (_quickFilters.contains('No Location') &&
        !(metadata == null || metadata.location.trim().isEmpty)) {
      return false;
    }

    if (_quickFilters.contains('Recently Added') &&
        !_recentlyAddedPaths.contains(photo.filePath)) {
      return false;
    }

    if (_quickFilters.contains('No Description') &&
        !(metadata == null || metadata.description.trim().isEmpty)) {
      return false;
    }

    return true;
  }

  bool _hasAnyCatalogData(PhotoCatalogMetadata? metadata) {
    if (metadata == null) return false;

    return metadata.people.isNotEmpty ||
        metadata.tags.isNotEmpty ||
        metadata.approximateDate.trim().isNotEmpty ||
        metadata.location.trim().isNotEmpty ||
        metadata.description.trim().isNotEmpty ||
        metadata.notes.trim().isNotEmpty;
  }

  DateTime? _catalogDateForSort(VaultPhoto photo) {
    final raw = _catalogByPath[photo.filePath]?.approximateDate.trim() ?? '';
    if (raw.isEmpty) return null;

    // Exact ISO-style dates first: 2026-08-29 / 2026-08 / 2026.
    final iso = RegExp(
      r'^(\d{4})(?:[-/](\d{1,2}))?(?:[-/](\d{1,2}))?',
    ).firstMatch(raw);
    if (iso != null) {
      final year = int.tryParse(iso.group(1) ?? '');
      final month = int.tryParse(iso.group(2) ?? '') ?? 1;
      final day = int.tryParse(iso.group(3) ?? '') ?? 1;
      if (year != null && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }

    // Heritage dates are often entered as "c. 1920", "Summer 1954", etc.
    // A four-digit year still gives us a useful chronological sort.
    final yearMatch = RegExp(
      r'\b(1[5-9]\d{2}|20\d{2}|21\d{2})\b',
    ).firstMatch(raw);
    final year = int.tryParse(yearMatch?.group(1) ?? '');
    return year == null ? null : DateTime(year);
  }

  int _comparePhotosForCurrentSort(VaultPhoto a, VaultPhoto b) {
    switch (_photoSortMode) {
      case 'date_oldest':
      case 'date_newest':
        final aDate = _catalogDateForSort(a);
        final bDate = _catalogDateForSort(b);

        // Prefer the cataloged/embedded heritage date. If a photo has no
        // catalog date yet, use its file modified date as a practical fallback.
        final aValue = aDate?.millisecondsSinceEpoch ?? a.modifiedMilliseconds;
        final bValue = bDate?.millisecondsSinceEpoch ?? b.modifiedMilliseconds;
        final result = aValue.compareTo(bValue);
        if (result != 0) {
          return _photoSortMode == 'date_newest' ? -result : result;
        }
        return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
      case 'name_z_a':
        return b.fileName.toLowerCase().compareTo(a.fileName.toLowerCase());
      case 'name_a_z':
      default:
        return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
    }
  }

  List<VaultPhoto> _sortedPhotos(Iterable<VaultPhoto> photos) {
    final sorted = photos.toList();
    sorted.sort(_comparePhotosForCurrentSort);
    return sorted;
  }

  String get _photoSortLabel {
    switch (_photoSortMode) {
      case 'date_oldest':
        return 'Date: Oldest First';
      case 'name_a_z':
        return 'Name: A–Z';
      case 'name_z_a':
        return 'Name: Z–A';
      case 'date_newest':
      default:
        return 'Date: Newest First';
    }
  }

  List<VaultPhoto> get _filteredPhotos =>
      _photos.where(_matchesSearch).toList();

  List<VaultPhoto> get _filteredPhotosInCurrentFolder {
    return _filteredPhotos
        .where((photo) => photo.relativeFolder == _currentFolder)
        .toList();
  }

  int get _uncatalogedCount => _photos
      .where((photo) => !_hasAnyCatalogData(_catalogByPath[photo.filePath]))
      .length;

  int get _missingPeopleCount => _photos.where((photo) {
    final metadata = _catalogByPath[photo.filePath];
    return metadata == null || metadata.people.isEmpty;
  }).length;

  int get _missingDateCount => _photos.where((photo) {
    final metadata = _catalogByPath[photo.filePath];
    return metadata == null || metadata.approximateDate.trim().isEmpty;
  }).length;

  int get _missingLocationCount => _photos.where((photo) {
    final metadata = _catalogByPath[photo.filePath];
    return metadata == null || metadata.location.trim().isEmpty;
  }).length;

  int get _missingDescriptionCount => _photos.where((photo) {
    final metadata = _catalogByPath[photo.filePath];
    return metadata == null || metadata.description.trim().isEmpty;
  }).length;

  int get _recentlyAddedCount => _photos
      .where((photo) => _recentlyAddedPaths.contains(photo.filePath))
      .length;

  int get _identifiedPeoplePhotoCount => _photos.length - _missingPeopleCount;
  int get _datedPhotoCount => _photos.length - _missingDateCount;
  int get _locatedPhotoCount => _photos.length - _missingLocationCount;
  int get _describedPhotoCount => _photos.length - _missingDescriptionCount;

  void _setDashboardFilter(String filter) {
    setState(() {
      _quickFilters
        ..clear()
        ..add(filter);
      _currentFolder = '';
      _showAllPhotosOnLanding = false;
    });
  }

  Future<void> _startGuidedPeopleCleanup() async {
    final queue = _photos.where((photo) {
      final metadata = _catalogByPath[photo.filePath];
      return metadata == null || metadata.people.isEmpty;
    }).toList();

    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every photo already has people identified.'),
        ),
      );
      return;
    }

    final confirmedFaces = await _databaseHelper.getConfirmedFaces();
    if (!mounted) return;

    final knownNames =
        confirmedFaces
            .map((face) => face.personName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    var index = 0;
    var savedCount = 0;
    var skippedCount = 0;
    final selectedByPhoto = <String, Set<String>>{};
    final typedByPhoto = <String, String>{};

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final photo = queue[index];
          final existing =
              _catalogByPath[photo.filePath] ??
              PhotoCatalogMetadata(filePath: photo.filePath);
          final file = File(photo.filePath);
          final selectedNames = selectedByPhoto.putIfAbsent(
            photo.filePath,
            () => <String>{},
          );
          final nameController = TextEditingController(
            text: typedByPhoto[photo.filePath] ?? '',
          );
          nameController.selection = TextSelection.collapsed(
            offset: nameController.text.length,
          );

          Future<void> finish() async {
            Navigator.pop(dialogContext);
          }

          Future<void> advance({required bool skipped}) async {
            if (skipped) skippedCount++;
            if (index >= queue.length - 1) {
              await finish();
              return;
            }
            setDialogState(() => index++);
          }

          void addTypedName() {
            final clean = nameController.text.trim();
            if (clean.isEmpty) return;
            selectedNames.add(clean);
            nameController.clear();
            typedByPhoto[photo.filePath] = '';
            setDialogState(() {});
          }

          Future<void> saveAndNext() async {
            addTypedName();

            if (selectedNames.isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Choose or enter at least one person, or choose Skip for now.',
                  ),
                ),
              );
              return;
            }

            final updatedPeople =
                <String>{
                    ...existing.people
                        .map((name) => name.trim())
                        .where((name) => name.isNotEmpty),
                    ...selectedNames,
                  }.toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            final updated = PhotoCatalogMetadata(
              filePath: existing.filePath,
              people: updatedPeople,
              tags: existing.tags,
              approximateDate: existing.approximateDate,
              location: existing.location,
              description: existing.description,
              backWriting: existing.backWriting,
              notes: existing.notes,
            );

            await _databaseHelper.savePhotoCatalogMetadata(updated);
            _catalogByPath[photo.filePath] = updated;

            if (!setEquals(existing.people.toSet(), updated.people.toSet())) {
              await _syncService.recordLocalChange(
                entityType: 'photo',
                localKey: updated.filePath,
                operation: 'update',
                changedFields: const ['People'],
              );
            }

            savedCount++;

            if (!mounted || !dialogContext.mounted) return;
            if (index >= queue.length - 1) {
              await finish();
              return;
            }

            setState(() {});
            setDialogState(() => index++);
          }

          final query = nameController.text.trim().toLowerCase();
          final suggestions = knownNames
              .where(
                (name) =>
                    !selectedNames.contains(name) &&
                    (query.isEmpty || name.toLowerCase().contains(query)),
              )
              .take(12)
              .toList();

          return Dialog(
            child: SizedBox(
              width: 1120,
              height: 760,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.people_outline),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Guided Cleanup • Identify People',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                '${index + 1} of ${queue.length} • '
                                '$savedCount saved • $skippedCount skipped',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Done for now',
                          onPressed: finish,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: file.existsSync()
                                ? Image.file(
                                    file,
                                    fit: BoxFit.contain,
                                    cacheWidth: 1400,
                                  )
                                : const Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 60,
                                    ),
                                  ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 410,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  photo.fileName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  photo.relativeFolder.isEmpty
                                      ? 'Pictures'
                                      : photo.relativeFolder,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  'Who is in this photo?',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Choose known people below or type a new name. '
                                  'You can add more than one person.',
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: nameController,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (value) {
                                    typedByPhoto[photo.filePath] = value;
                                    setDialogState(() {});
                                  },
                                  onSubmitted: (_) => addTypedName(),
                                  decoration: InputDecoration(
                                    labelText: 'Person',
                                    hintText: 'Type a name',
                                    prefixIcon: const Icon(
                                      Icons.person_add_alt_1,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: 'Add person',
                                      onPressed: addTypedName,
                                      icon: const Icon(Icons.add),
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                if (suggestions.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Known People',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: suggestions
                                        .map(
                                          (name) => ActionChip(
                                            avatar: const Icon(
                                              Icons.person,
                                              size: 16,
                                            ),
                                            label: Text(name),
                                            onPressed: () {
                                              selectedNames.add(name);
                                              setDialogState(() {});
                                            },
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                                if (selectedNames.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    'Selected',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: selectedNames
                                        .map(
                                          (name) => InputChip(
                                            label: Text(name),
                                            onDeleted: () {
                                              selectedNames.remove(name);
                                              setDialogState(() {});
                                            },
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                                const Spacer(),
                                const Divider(),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => advance(skipped: true),
                                      icon: const Icon(Icons.skip_next),
                                      label: const Text('Skip'),
                                    ),
                                    const Spacer(),
                                    FilledButton.icon(
                                      onPressed: saveAndNext,
                                      icon: const Icon(Icons.save_outlined),
                                      label: Text(
                                        index == queue.length - 1
                                            ? 'Save & Finish'
                                            : 'Save & Next',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: TextButton(
                                    onPressed: finish,
                                    child: const Text('Done for now'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted) return;

    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
    if (!mounted) return;

    setState(() {
      _catalogByPath = {
        for (final record in catalogRecords) record.filePath: record,
      };
      _quickFilters.remove('No People');
      _currentFolder = '';
    });

    if (savedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Guided cleanup identified people in $savedCount '
            '${savedCount == 1 ? 'photo' : 'photos'}.',
          ),
        ),
      );
    }
  }

  Future<void> _startGuidedDateCleanup() async {
    final queue = _photos.where((photo) {
      final metadata = _catalogByPath[photo.filePath];
      return metadata == null || metadata.approximateDate.trim().isEmpty;
    }).toList();

    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every photo already has a date.')),
      );
      return;
    }

    var index = 0;
    var savedCount = 0;
    var skippedCount = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final photo = queue[index];
          final existing =
              _catalogByPath[photo.filePath] ??
              PhotoCatalogMetadata(filePath: photo.filePath);
          final file = File(photo.filePath);
          final dateController = TextEditingController();

          Future<void> finish() async {
            Navigator.pop(dialogContext);
          }

          Future<void> advance({required bool skipped}) async {
            if (skipped) skippedCount++;
            if (index >= queue.length - 1) {
              await finish();
              return;
            }
            setDialogState(() => index++);
          }

          Future<void> saveAndNext() async {
            final value = dateController.text.trim();
            if (value.isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Enter a date, or choose Skip for now.'),
                ),
              );
              return;
            }

            final updated = PhotoCatalogMetadata(
              filePath: existing.filePath,
              people: existing.people,
              tags: existing.tags,
              approximateDate: value,
              location: existing.location,
              description: existing.description,
              backWriting: existing.backWriting,
              notes: existing.notes,
            );

            await _databaseHelper.savePhotoCatalogMetadata(updated);
            _catalogByPath[photo.filePath] = updated;

            if (existing.approximateDate != updated.approximateDate) {
              await _syncService.recordLocalChange(
                entityType: 'photo',
                localKey: updated.filePath,
                operation: 'update',
                changedFields: const ['Date'],
              );
            }

            savedCount++;

            if (!mounted || !dialogContext.mounted) return;
            if (index >= queue.length - 1) {
              await finish();
              return;
            }
            setState(() {});
            setDialogState(() => index++);
          }

          return Dialog(
            child: SizedBox(
              width: 1120,
              height: 760,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.event_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Guided Cleanup • Add Dates',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                '${index + 1} of ${queue.length} • '
                                '$savedCount saved • $skippedCount skipped',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Done for now',
                          onPressed: finish,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: file.existsSync()
                                ? Image.file(
                                    file,
                                    fit: BoxFit.contain,
                                    cacheWidth: 1400,
                                  )
                                : const Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 60,
                                    ),
                                  ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 390,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  photo.fileName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  photo.relativeFolder.isEmpty
                                      ? 'Pictures'
                                      : photo.relativeFolder,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'When was this photo taken?',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Use the best date you know. An exact day, '
                                  'month/year, year, or an approximate phrase '
                                  'such as "about 1955" is okay.',
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: dateController,
                                  autofocus: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => saveAndNext(),
                                  decoration: const InputDecoration(
                                    labelText: 'Date',
                                    hintText: 'Example: 1955 or about 1955',
                                    prefixIcon: Icon(
                                      Icons.calendar_today_outlined,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ActionChip(
                                      label: const Text('About 1950'),
                                      onPressed: () {
                                        dateController.text = 'about 1950';
                                      },
                                    ),
                                    ActionChip(
                                      label: const Text('1950s'),
                                      onPressed: () {
                                        dateController.text = '1950s';
                                      },
                                    ),
                                    ActionChip(
                                      label: const Text('Unknown'),
                                      onPressed: () {
                                        dateController.text = 'Unknown';
                                      },
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                const Divider(),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => advance(skipped: true),
                                      icon: const Icon(Icons.skip_next),
                                      label: const Text('Skip'),
                                    ),
                                    const Spacer(),
                                    FilledButton.icon(
                                      onPressed: saveAndNext,
                                      icon: const Icon(Icons.save_outlined),
                                      label: Text(
                                        index == queue.length - 1
                                            ? 'Save & Finish'
                                            : 'Save & Next',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: TextButton(
                                    onPressed: finish,
                                    child: const Text('Done for now'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted) return;

    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
    if (!mounted) return;

    setState(() {
      _catalogByPath = {
        for (final record in catalogRecords) record.filePath: record,
      };
      _quickFilters.remove('No Date');
      _currentFolder = '';
    });

    if (savedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Guided cleanup saved dates for $savedCount '
            '${savedCount == 1 ? 'photo' : 'photos'}.',
          ),
        ),
      );
    }
  }

  Future<void> _openPeople() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const KnownPeopleScreen()),
    );

    if (!mounted) return;

    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
    final faceCount = await _databaseHelper.getUnconfirmedFaceCount();

    setState(() {
      _catalogByPath = {
        for (final record in catalogRecords) record.filePath: record,
      };
      _unidentifiedFaceCount = faceCount;
    });
  }

  Future<void> _openUnidentifiedFacesFromHealth() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UnidentifiedFacesScreen()),
    );
    if (!mounted) return;
    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
    final faceCount = await _databaseHelper.getUnconfirmedFaceCount();
    setState(() {
      _catalogByPath = {
        for (final record in catalogRecords) record.filePath: record,
      };
      _unidentifiedFaceCount = faceCount;
    });
  }

  BoxDecoration _heritagePanelDecoration({
    double radius = 14,
    double opacity = 0.78,
    bool goldBorder = true,
  }) {
    return BoxDecoration(
      color: const Color(0xFF0B2742).withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: goldBorder
            ? const Color(0xFFC9A65A).withValues(alpha: 0.42)
            : const Color(0xFF527A98).withValues(alpha: 0.42),
      ),
    );
  }

  Color get _heritageGold => const Color(0xFFC9A65A);
  Color get _heritageCream => const Color(0xFFF3E9D1);

  Widget _buildPhotoReferenceHero() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Preserve the approved 210px desktop banner, but keep it from
        // consuming too much vertical space on smaller laptop windows.
        final heroHeight = constraints.maxWidth < 850 ? 150.0 : 210.0;
        return Container(
          height: heroHeight,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF071A2B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _heritageGold.withValues(alpha: 0.55),
              width: .8,
            ),
          ),
          child: Image.asset(
            'assets/photos_decor/photos_banner.png',
            width: double.infinity,
            height: heroHeight,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: const Color(0xFF071A2B),
                alignment: Alignment.center,
                child: Text(
                  'Photos banner image not found',
                  style: TextStyle(color: _heritageCream),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCollectionOverviewPanel() {
    final total = _photos.length;
    int pct(int complete) =>
        total == 0 ? 0 : ((complete / total) * 100).round();
    final peoplePct = pct(_identifiedPeoplePhotoCount);
    final datesPct = pct(_datedPhotoCount);
    final placesPct = pct(_locatedPhotoCount);
    final describedPct = pct(_describedPhotoCount);
    final organizationPct = total == 0
        ? 0
        : ((peoplePct + datesPct + placesPct + describedPct) / 4).round();

    Color gaugeColor(int value) {
      // Soft archival stoplight palette: warm, readable, but not neon.
      if (value >= 75) return const Color(0xFF8FCB78); // soft heritage green
      if (value >= 45) return const Color(0xFFE6C766); // muted warm yellow
      return const Color(0xFFE28A7A); // softened coral red
    }

    Widget collectionStat(String value, String label) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _heritageCream,
              fontWeight: FontWeight.w900,
              fontSize: 19,
              letterSpacing: .1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .50),
              fontWeight: FontWeight.w700,
              fontSize: 8.5,
              letterSpacing: .75,
            ),
          ),
        ],
      ),
    );

    Widget gauge(
      String label,
      int value, {
      VoidCallback? onTap,
      double size = 54,
      bool overall = false,
    }) {
      final color = gaugeColor(value);
      final ring = SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: value / 100,
                strokeWidth: overall ? 5 : 4,
                strokeCap: StrokeCap.round,
                backgroundColor: _heritageCream.withValues(alpha: .09),
                color: color,
              ),
            ),
            Container(
              width: size - (overall ? 15 : 14),
              height: size - (overall ? 15 : 14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: .08),
                border: Border.all(
                  color: color.withValues(alpha: .16),
                  width: .7,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '$value%',
                style: TextStyle(
                  color: color,
                  fontSize: overall ? 13 : 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ring,
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: overall
                      ? _heritageGold
                      : _heritageCream.withValues(alpha: .70),
                  fontSize: overall ? 9.5 : 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: overall ? .45 : .15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF071B2D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _heritageGold.withValues(alpha: .48),
          width: .9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PHOTO COLLECTION',
                  style: TextStyle(
                    color: _heritageGold,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.2,
                    letterSpacing: 1.05,
                  ),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    collectionStat('$total', 'Photos'),
                    collectionStat('$_knownPeopleCount', 'People Identified'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 1,
            height: 70,
            color: _heritageGold.withValues(alpha: .20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ORGANIZATION',
                  style: TextStyle(
                    color: _heritageGold,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.2,
                    letterSpacing: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  alignment: WrapAlignment.spaceAround,
                  runAlignment: WrapAlignment.center,
                  runSpacing: 8,
                  children: [
                    gauge('OVERALL', organizationPct, size: 60, overall: true),
                    gauge(
                      'People',
                      peoplePct,
                      onTap: () => _setDashboardFilter('No People'),
                    ),
                    gauge(
                      'Dates',
                      datesPct,
                      onTap: () => _setDashboardFilter('No Date'),
                    ),
                    gauge(
                      'Locations',
                      placesPct,
                      onTap: () => _setDashboardFilter('No Location'),
                    ),
                    gauge(
                      'Descriptions',
                      describedPct,
                      onTap: () => _setDashboardFilter('No Description'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardRailPanel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081E33).withValues(alpha: .97),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _heritageGold.withValues(alpha: .30),
          width: .8,
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 37,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF091F34),
              border: Border(
                bottom: BorderSide(
                  color: _heritageGold.withValues(alpha: .26),
                  width: .8,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 1,
                  color: _heritageGold.withValues(alpha: .82),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: _heritageGold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      fontSize: 10.8,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildWorkOnSection() {
    Widget option({
      required IconData icon,
      required String label,
      required int? count,
      required Future<void> Function() onTap,
    }) {
      return InkWell(
        onTap: () async => onTap(),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(color: _heritageGold.withValues(alpha: .18)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _heritageGold.withValues(alpha: .80),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: _heritageCream,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .72),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right,
                color: _heritageGold.withValues(alpha: .8),
                size: 17,
              ),
            ],
          ),
        ),
      );
    }

    return _dashboardRailPanel(
      title: 'REVIEW & ORGANIZE',
      icon: Icons.fact_check_outlined,
      child: Column(
        children: [
          option(
            icon: Icons.copy_all_outlined,
            label: 'Review Possible Duplicates',
            count: _possibleDuplicateCount,
            onTap: () async {
              await _findPossibleDuplicates();
            },
          ),
          option(
            icon: Icons.face_outlined,
            label: 'Unidentified Faces',
            count: _unidentifiedFaceCount,
            onTap: () async {
              await _openUnidentifiedFacesFromHealth();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsPanel() {
    Widget row(IconData icon, String label, VoidCallback onTap, {int? count}) =>
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _heritageGold.withValues(alpha: .80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                if (count != null) ...[
                  Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2946),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _heritageGold.withValues(alpha: .35),
                      ),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _heritageGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.chevron_right,
                  color: _heritageGold.withValues(alpha: .62),
                  size: 16,
                ),
              ],
            ),
          ),
        );
    return _dashboardRailPanel(
      title: 'QUICK ACTIONS',
      icon: Icons.bolt_outlined,
      child: Column(
        children: [
          row(
            Icons.delete_outline,
            'Photo Trash',
            _openPhotoTrash,
            count: _photoTrashCount,
          ),
          row(
            Icons.restore_from_trash_outlined,
            'Duplicate Trash',
            _openDuplicateTrash,
            count: _duplicateTrashCount,
          ),
          row(Icons.sell_outlined, 'Metadata', _openMetadataImport),
        ],
      ),
    );
  }

  Widget _buildLandingSearch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF081E33).withValues(alpha: .97),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _heritageGold.withValues(alpha: .48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onSubmitted: (_) {
              // Search stays on the dashboard, but only refreshes when
              // submitted so large photo libraries are not rebuilt on
              // every keystroke.
              setState(() {});
            },
            style: TextStyle(color: _heritageCream, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF071A2B),
              hintText: 'Search your photos…',
              hintStyle: TextStyle(
                color: _heritageCream.withValues(alpha: .48),
              ),
              prefixIcon: Icon(Icons.search, color: _heritageGold),
              suffixIcon: _searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _showAllPhotosOnLanding = false;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(
                  color: _heritageGold.withValues(alpha: .22),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(
                  color: _heritageGold.withValues(alpha: .22),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: _heritageGold),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _selectedPhotoSourceId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF071A2B),
                    labelText: 'Source',
                    labelStyle: TextStyle(
                      color: _heritageCream.withValues(alpha: .65),
                    ),
                    prefixIcon: Icon(
                      Icons.source_outlined,
                      color: _heritageGold,
                      size: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(2),
                      borderSide: BorderSide(
                        color: _heritageGold.withValues(alpha: .22),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(2),
                      borderSide: BorderSide(
                        color: _heritageGold.withValues(alpha: .22),
                      ),
                    ),
                  ),
                  dropdownColor: const Color(0xFF081E33),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All Sources'),
                    ),
                    ..._photoSources.map(
                      (source) => DropdownMenuItem<int?>(
                        value: source['id'] as int?,
                        child: Text(
                          source['display_name'] as String? ?? 'Photo Source',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedPhotoSourceId = value;
                      _currentFolder = '';
                      _showAllPhotosOnLanding = value != null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Filters',
                onSelected: (value) {
                  if (value == 'clear') {
                    _clearDashboardFilters();
                  } else {
                    _setDashboardFilter(value);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'No People', child: Text('No people')),
                  PopupMenuItem(value: 'No Date', child: Text('No date')),
                  PopupMenuItem(
                    value: 'No Location',
                    child: Text('No location'),
                  ),
                  PopupMenuItem(
                    value: 'No Description',
                    child: Text('No description'),
                  ),
                  PopupMenuItem(
                    value: 'Recently Added',
                    child: Text('Recently added'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'clear', child: Text('Clear filters')),
                ],
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2946),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: _heritageGold.withValues(alpha: .48),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.filter_alt_outlined,
                        color: _heritageGold,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Filters',
                        style: TextStyle(
                          color: _heritageCream,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more, color: _heritageGold, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _topLevelFolderForPhoto(VaultPhoto photo) {
    final segments = _folderSegments(photo.relativeFolder.trim());
    if (segments.isEmpty) return null;
    return segments.first;
  }

  Future<void> _setFolderCover(VaultPhoto photo) async {
    final folder = _topLevelFolderForPhoto(photo);
    if (folder == null || folder.isEmpty) return;

    final updated = Map<String, String>.from(_folderCoverByFolder)
      ..[folder] = photo.filePath;

    await _databaseHelper.setSetting(
      'photo_folder_covers',
      jsonEncode(updated),
    );

    if (!mounted) return;
    setState(() => _folderCoverByFolder = updated);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${photo.fileName}" is now the cover for $folder.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _chooseFolderCover(_PhotoFolder folder) async {
    final prefix = '${folder.path}${path.separator}';
    final candidates = _sortedPhotos(
      _photos.where((photo) {
        return photo.relativeFolder == folder.path ||
            photo.relativeFolder.startsWith(prefix);
      }),
    );

    if (candidates.isEmpty || !mounted) return;

    final selected = await showDialog<VaultPhoto>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 980,
          height: 720,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, color: _heritageGold),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose Cover Photo',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '${folder.name} • ${candidates.length} photos',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: candidates.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  itemBuilder: (context, index) {
                    final photo = candidates[index];
                    final file = File(photo.filePath);
                    final isCurrent =
                        _folderCoverByFolder[folder.path] == photo.filePath;

                    return InkWell(
                      onTap: () => Navigator.pop(dialogContext, photo),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B2439),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isCurrent
                                ? _heritageGold
                                : _heritageGold.withValues(alpha: .28),
                            width: isCurrent ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                                child: file.existsSync()
                                    ? Image.file(
                                        file,
                                        fit: BoxFit.cover,
                                        cacheWidth: 360,
                                        errorBuilder: (_, _, _) => const Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        ),
                                      )
                                    : const Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      photo.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _heritageCream,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.check_circle,
                                      color: _heritageGold,
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null) return;
    await _setFolderCover(selected);
  }

  Future<void> _resetFolderCover(_PhotoFolder folder) async {
    if (!_folderCoverByFolder.containsKey(folder.path)) return;

    final updated = Map<String, String>.from(_folderCoverByFolder)
      ..remove(folder.path);

    await _databaseHelper.setSetting(
      'photo_folder_covers',
      jsonEncode(updated),
    );

    if (!mounted) return;
    setState(() => _folderCoverByFolder = updated);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${folder.name} cover reset to automatic.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showFolderCoverMenu(
    _PhotoFolder folder,
    Offset globalPosition,
  ) async {
    if (!mounted) return;

    final hasCustomCover = _folderCoverByFolder.containsKey(folder.path);

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'choose',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.image_outlined),
            title: Text('Choose Cover Photo…'),
          ),
        ),
        if (hasCustomCover)
          const PopupMenuItem<String>(
            value: 'reset',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restart_alt),
              title: Text('Reset Cover Photo'),
            ),
          ),
      ],
    );

    if (action == 'choose') {
      await _chooseFolderCover(folder);
    } else if (action == 'reset') {
      await _resetFolderCover(folder);
    }
  }

  Widget _buildPicturesFoldersLanding() {
    List<VaultPhoto> photosForFolder(String folderPath) {
      final prefix = '$folderPath${path.separator}';
      return _filteredPhotos.where((photo) {
        return photo.relativeFolder == folderPath ||
            photo.relativeFolder.startsWith(prefix);
      }).toList();
    }

    List<_PhotoFolder> allFolders() {
      // The landing dashboard shows only top-level parent folders. Photos in
      // nested subfolders roll up into their parent folder's image count.
      // Subfolders remain available after the parent folder is opened.
      final counts = <String, int>{};
      for (final photo in _filteredPhotos) {
        final folder = photo.relativeFolder.trim();
        if (folder.isEmpty) continue;

        final segments = _folderSegments(folder);
        if (segments.isEmpty) continue;

        final parentFolder = segments.first;
        counts[parentFolder] = (counts[parentFolder] ?? 0) + 1;
      }

      final folders =
          counts.entries
              .map(
                (entry) => _PhotoFolder(
                  path: entry.key,
                  name: entry.key,
                  photoCount: entry.value,
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      return folders;
    }

    VaultPhoto? representativePhoto(String folderPath) {
      final photos = photosForFolder(folderPath);
      if (photos.isEmpty) return null;

      final chosenPath = _folderCoverByFolder[folderPath];
      if (chosenPath != null && chosenPath.isNotEmpty) {
        for (final photo in photos) {
          if (photo.filePath == chosenPath &&
              File(photo.filePath).existsSync()) {
            return photo;
          }
        }
      }

      // If the chosen cover was moved/deleted, automatically fall back.
      return photos.first;
    }

    Widget folderCard(_PhotoFolder folder) {
      final cover = representativePhoto(folder.path);
      final file = cover == null ? null : File(cover.filePath);
      final parent = path.dirname(folder.path);
      final subtitle = parent == '.' || parent.isEmpty
          ? '${folder.photoCount} images'
          : '$parent  •  ${folder.photoCount} images';

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showFolderCoverMenu(folder, details.globalPosition);
        },
        child: InkWell(
          onTap: () {
            setState(() {
              _currentFolder = folder.path;
              _showAllPhotosOnLanding = true;
            });
          },
          borderRadius: BorderRadius.circular(3),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B2439),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: _heritageGold.withValues(alpha: .30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                    child: file != null && file.existsSync()
                        ? Image.file(
                            file,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            cacheWidth: 420,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFF10283D),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.folder_outlined,
                                color: _heritageGold,
                                size: 44,
                              ),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF10283D),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.folder_outlined,
                              color: _heritageGold,
                              size: 44,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 1,
                        color: _heritageGold.withValues(alpha: .75),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _heritageCream,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _heritageCream.withValues(alpha: .60),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final folders = allFolders();

    final hasSearch = _searchController.text.trim().isNotEmpty;
    final showPhotoResults =
        hasSearch ||
        _showAllPhotosOnLanding ||
        _quickFilters.isNotEmpty ||
        _selectedPhotoSourceId != null;
    final photoResults = _sortedPhotos(
      _currentFolder.isEmpty
          ? _filteredPhotos
          : _filteredPhotos.where((photo) {
              final prefix = '$_currentFolder${path.separator}';
              return photo.relativeFolder == _currentFolder ||
                  photo.relativeFolder.startsWith(prefix);
            }),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF081E33).withValues(alpha: .96),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _heritageGold.withValues(alpha: .40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                showPhotoResults
                    ? (hasSearch
                          ? 'SEARCH RESULTS'
                          : (_currentFolder.isNotEmpty
                                ? path.basename(_currentFolder).toUpperCase()
                                : 'ALL PHOTOS'))
                    : 'PICTURES & FOLDERS',
                style: TextStyle(
                  color: _heritageCream,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                showPhotoResults
                    ? '${photoResults.length} photos'
                    : '${folders.length} folders',
                style: TextStyle(
                  color: _heritageCream.withValues(alpha: .55),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              if (hasSearch && !_searchSelectionMode)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchSelectionMode = true;
                      _selectedPaths.clear();
                    });
                  },
                  icon: const Icon(Icons.check_box_outlined, size: 16),
                  label: const Text('Select'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _heritageGold,
                    side: BorderSide(
                      color: _heritageGold.withValues(alpha: .38),
                      width: .8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (hasSearch && _searchSelectionMode) ...[
                TextButton(
                  onPressed: () {
                    setState(() {
                      final visiblePaths = photoResults
                          .map((photo) => photo.filePath)
                          .toSet();
                      final allVisibleSelected =
                          visiblePaths.isNotEmpty &&
                          visiblePaths.every(_selectedPaths.contains);
                      if (allVisibleSelected) {
                        _selectedPaths.removeAll(visiblePaths);
                      } else {
                        _selectedPaths.addAll(visiblePaths);
                      }
                    });
                  },
                  child: Text(
                    photoResults.isNotEmpty &&
                            photoResults
                                .map((photo) => photo.filePath)
                                .every(_selectedPaths.contains)
                        ? 'Clear All'
                        : 'Select All',
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _selectedPaths.isEmpty
                      ? null
                      : () => _moveSelectedSearchPhotosToTrash(photoResults),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(
                    _selectedPaths.isEmpty
                        ? 'Delete Selected'
                        : 'Delete Selected (${_selectedPaths.length})',
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _searchSelectionMode = false;
                      _selectedPaths.clear();
                    });
                  },
                  child: const Text('Cancel'),
                ),
              ],
              const SizedBox(width: 8),
              if (showPhotoResults) ...[
                PopupMenuButton<String>(
                  tooltip: 'Sort photos',
                  initialValue: _photoSortMode,
                  onSelected: (value) {
                    setState(() => _photoSortMode = value);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'date_newest',
                      child: Text('Date: Newest First'),
                    ),
                    PopupMenuItem(
                      value: 'date_oldest',
                      child: Text('Date: Oldest First'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'name_a_z', child: Text('Name: A–Z')),
                    PopupMenuItem(value: 'name_z_a', child: Text('Name: Z–A')),
                  ],
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2946),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: _heritageGold.withValues(alpha: .38),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_vert, color: _heritageGold, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _photoSortLabel,
                          style: TextStyle(
                            color: _heritageCream,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more, color: _heritageGold, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    if (showPhotoResults) {
                      _showAllPhotosOnLanding = false;
                      _searchController.clear();
                      _quickFilters.clear();
                      _currentFolder = '';
                    } else {
                      _showAllPhotosOnLanding = true;
                    }
                  });
                },
                icon: Icon(
                  showPhotoResults
                      ? Icons.folder_outlined
                      : Icons.photo_library_outlined,
                  size: 16,
                ),
                label: Text(
                  showPhotoResults ? 'Show Folders' : 'View All Photos',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _heritageGold,
                  side: BorderSide(
                    color: _heritageGold.withValues(alpha: .38),
                    width: .8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                  ),
                ),
              ),
            ],
          ),
          Divider(color: _heritageGold.withValues(alpha: .22)),
          if (showPhotoResults &&
              (hasSearch ||
                  _quickFilters.isNotEmpty ||
                  _selectedPhotoSourceId != null))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasSearch
                          ? 'Showing matches for “${_searchController.text.trim()}”'
                          : _selectedPhotoSourceId != null
                          ? 'Filtered by photo source'
                          : 'Filtered photo results',
                      style: TextStyle(
                        color: _heritageCream.withValues(alpha: .72),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _quickFilters.clear();
                        _selectedPhotoSourceId = null;
                        _currentFolder = '';
                        _showAllPhotosOnLanding = false;
                      });
                    },
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: _heritageGold,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 5),

          if (showPhotoResults)
            if (photoResults.isEmpty)
              Container(
                height: 180,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B2439),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .24),
                  ),
                ),
                child: Text(
                  hasSearch
                      ? 'No matching photos found'
                      : 'No photos to display',
                  style: TextStyle(
                    color: _heritageCream,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              SizedBox(
                height: 620,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 700
                        ? (hasSearch ? 3 : 5)
                        : constraints.maxWidth >= 520
                        ? (hasSearch ? 3 : 4)
                        : 2;

                    return GridView.builder(
                      primary: false,
                      padding: EdgeInsets.zero,
                      itemCount: photoResults.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.78,
                      ),
                      itemBuilder: (context, index) {
                        final photo = photoResults[index];
                        return _photoTile(
                          photo,
                          photoResults,
                          searchSelectionMode:
                              hasSearch && _searchSelectionMode,
                        );
                      },
                    );
                  },
                ),
              )
          else if (folders.isEmpty)
            Container(
              height: 180,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF0B2439),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: _heritageGold.withValues(alpha: .24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_outlined, color: _heritageGold, size: 46),
                  const SizedBox(height: 8),
                  Text(
                    'No folders to display',
                    style: TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final columns = constraints.maxWidth >= 700
                    ? 5
                    : constraints.maxWidth >= 520
                    ? 4
                    : 2;
                final cardWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: folders
                      .map(
                        (folder) => SizedBox(
                          width: cardWidth,
                          height: 190,
                          child: folderCard(folder),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPhotosLanding() {
    return Container(
      color: const Color(0xFF061725).withValues(alpha: .90),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // The approved wide layout remains unchanged. On narrower
              // laptop windows, stack Search below Collection/Organization
              // instead of squeezing both panels side-by-side.
              if (constraints.maxWidth < 980) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCollectionOverviewPanel(),
                    const SizedBox(height: 10),
                    _buildLandingSearch(),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 7, child: _buildCollectionOverviewPanel()),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: _buildLandingSearch()),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Keep the locked desktop dashboard as a true 1/3 + 2/3 split.
              // Only collapse on genuinely narrow/mobile-sized content.
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPhotoSourcesStrip(),
                    const SizedBox(height: 10),
                    _buildWorkOnSection(),
                    const SizedBox(height: 10),
                    _buildQuickActionsPanel(),
                    const SizedBox(height: 12),
                    _buildPicturesFoldersLanding(),
                  ],
                );
              }

              final gap = 14.0;
              final usableWidth = constraints.maxWidth - gap;
              final leftWidth = usableWidth / 3;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: leftWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPhotoSourcesStrip(),
                        const SizedBox(height: 10),
                        _buildWorkOnSection(),
                        const SizedBox(height: 10),
                        _buildQuickActionsPanel(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: _buildPicturesFoldersLanding()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _removePhotoSource(Map<String, Object?> source) async {
    final sourceId = source['id'] as int? ?? 0;
    final displayName = (source['display_name'] as String? ?? 'Photo Source')
        .trim();
    final rootPath = (source['root_path'] as String? ?? '').trim();
    final sourceType = (source['source_type'] as String? ?? '').trim();

    if (sourceId <= 0) return;

    final folderName = rootPath.isEmpty
        ? displayName
        : path.basename(path.normalize(rootPath));
    final sourceLabel = sourceType == 'local_folder' && folderName.isNotEmpty
        ? folderName
        : displayName;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Remove $sourceLabel as a photo source?'),
            content: Text(
              'Heirloom Atlas will stop indexing this location and remove its '
              'photos from the Photos view.\n\n'
              'No original photos or folders will be deleted from your '
              'computer, drive, or cloud storage.\n\n'
              '${rootPath.isEmpty ? '' : 'Location:\n$rootPath'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.link_off),
                label: const Text('Remove Source'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      final database = await _databaseHelper.database;

      await database.transaction((transaction) async {
        final mappings = await transaction.query(
          'photo_source_files',
          columns: ['file_path'],
          where: 'source_id = ?',
          whereArgs: [sourceId],
        );

        final sourcePaths = mappings
            .map((row) => row['file_path'] as String? ?? '')
            .where((value) => value.isNotEmpty)
            .toSet();

        await transaction.delete(
          'photo_source_files',
          where: 'source_id = ?',
          whereArgs: [sourceId],
        );

        // Only remove an indexed-photo row when no other connected source
        // still points to that same physical file. Original files are never
        // touched by this operation.
        for (final filePath in sourcePaths) {
          final otherMappings = await transaction.query(
            'photo_source_files',
            columns: ['file_path'],
            where: 'file_path = ?',
            whereArgs: [filePath],
            limit: 1,
          );
          if (otherMappings.isEmpty) {
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

      await _databaseHelper.removeConnectedSource('photo_source_$sourceId');

      final photos = await _databaseHelper.getIndexedPhotos();
      final sources = await _databaseHelper.getPhotoSources();

      if (!mounted) return;

      setState(() {
        _photos = photos;
        _photoSources = sources;
        if (_selectedPhotoSourceId == sourceId) {
          _selectedPhotoSourceId = null;
          _showAllPhotosOnLanding = false;
        }
        _currentFolder = '';
        _selectionMode = false;
        _searchSelectionMode = false;
        _selectedPaths.clear();
      });

      await _loadOrganizerCounts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$sourceLabel removed from Heirloom Atlas. Original files were not deleted.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove photo source: $error')),
      );
    }
  }

  Widget _buildPhotoSourcesStrip() {
    Widget sourceRow(Map<String, Object?> source) {
      final name = source['display_name'] as String? ?? 'Photo Source';
      final count = source['photo_count'] as int? ?? 0;
      final sourceType = source['source_type'] as String? ?? '';
      final sourceId = source['id'] as int?;
      final rootPath = (source['root_path'] as String? ?? '').trim();
      final isSelected = sourceId != null && _selectedPhotoSourceId == sourceId;

      final folderName = rootPath.isEmpty
          ? ''
          : path.basename(path.normalize(rootPath));
      final primaryLabel = sourceType == 'local_folder' && folderName.isNotEmpty
          ? folderName
          : name;

      return InkWell(
        onTap: sourceId == null
            ? null
            : () {
                setState(() {
                  // Clicking the active source again returns to All Sources.
                  _selectedPhotoSourceId = isSelected ? null : sourceId;
                  _currentFolder = '';
                  _showAllPhotosOnLanding = !isSelected;
                  _selectionMode = false;
                  _selectedPaths.clear();
                });
              },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? _heritageGold.withValues(alpha: .10)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: _heritageGold.withValues(alpha: .16)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
          child: Row(
            children: [
              _PhotoSourceBrandIcon(
                sourceType: sourceType,
                displayName: name,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _heritageCream,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                    if (rootPath.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          rootPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _heritageCream.withValues(alpha: .48),
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.check,
                size: 13,
                color: const Color(0xFF78C850).withValues(alpha: .78),
              ),
              const SizedBox(width: 7),
              Text(
                '$count',
                style: TextStyle(
                  color: _heritageCream,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 5),
                Icon(Icons.filter_alt, size: 13, color: _heritageGold),
              ],
              PopupMenuButton<String>(
                tooltip: 'Photo source options',
                padding: EdgeInsets.zero,
                iconSize: 18,
                color: const Color(0xFF081E33),
                onSelected: (value) async {
                  if (value == 'remove') {
                    await _removePhotoSource(source);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.link_off, size: 18),
                        SizedBox(width: 9),
                        Text('Remove Source'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return _dashboardRailPanel(
      title: 'PHOTO SOURCES',
      icon: Icons.cloud_outlined,
      trailing: TextButton.icon(
        onPressed: _scanning ? null : _showAddPhotoSourceDialog,
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Add Source'),
        style: TextButton.styleFrom(
          foregroundColor: _heritageGold,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 7),
        ),
      ),
      child: Column(
        children: [
          if (_photoSources.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No sources connected yet.',
                style: TextStyle(color: _heritageCream.withValues(alpha: .65)),
              ),
            )
          else
            ..._photoSources.map(sourceRow),
        ],
      ),
    );
  }

  Widget _buildPhotoWorldDashboard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _heritagePanelDecoration(radius: 18, opacity: 0.68),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2946),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _heritageGold.withValues(alpha: .28),
                    ),
                  ),
                  child: Icon(Icons.public_outlined, color: _heritageGold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Photo World',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _heritageCream,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'A simple view of where your collection lives.',
                        style: TextStyle(
                          color: _heritageCream.withValues(alpha: .60),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_photoSources.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFF071A2B).withValues(alpha: .46),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .20),
                  ),
                ),
                child: Text(
                  'No photo locations are connected yet.',
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .62),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _photoSources.map((source) {
                  final name =
                      source['display_name'] as String? ?? 'Photo Source';
                  final sourceType = source['source_type'] as String? ?? '';
                  final count = source['photo_count'] as int? ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF071A2B).withValues(alpha: .50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _heritageGold.withValues(alpha: .20),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PhotoSourceBrandIcon(
                          sourceType: sourceType,
                          displayName: name,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          name,
                          style: TextStyle(
                            color: _heritageCream,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: _heritageGold,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionHealthCard() {
    final scheme = Theme.of(context).colorScheme;
    Widget metric({
      required IconData icon,
      required String label,
      required int complete,
      required int missing,
      required String filter,
      VoidCallback? action,
    }) {
      final total = _photos.length;
      final percent = total == 0 ? 0 : ((complete / total) * 100).round();
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: missing == 0
              ? null
              : action ?? () => _setDashboardFilter(filter),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: scheme.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '$complete of $total • $percent%',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : complete / total,
                ),
                const SizedBox(height: 5),
                Text(
                  missing == 0 ? 'Complete' : '$missing need attention',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: _heritagePanelDecoration(radius: 18, opacity: 0.68),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.health_and_safety_outlined,
                    color: _heritageGold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collection Health',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _heritageCream,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_photos.length} ${_photos.length == 1 ? 'photo' : 'photos'} • see what is organized and what still needs attention',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                metric(
                  icon: Icons.people_outline,
                  label: 'People',
                  complete: _identifiedPeoplePhotoCount,
                  missing: _missingPeopleCount,
                  filter: 'No People',
                  action: _startGuidedPeopleCleanup,
                ),
                metric(
                  icon: Icons.event_outlined,
                  label: 'Dates',
                  complete: _datedPhotoCount,
                  missing: _missingDateCount,
                  filter: 'No Date',
                  action: _startGuidedDateCleanup,
                ),
                metric(
                  icon: Icons.place_outlined,
                  label: 'Places',
                  complete: _locatedPhotoCount,
                  missing: _missingLocationCount,
                  filter: 'No Location',
                ),
                metric(
                  icon: Icons.notes_outlined,
                  label: 'Stories',
                  complete: _describedPhotoCount,
                  missing: _missingDescriptionCount,
                  filter: 'No Description',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleDashboardFilter(String filter) {
    setState(() {
      if (_quickFilters.contains(filter)) {
        _quickFilters.remove(filter);
      } else {
        _quickFilters.add(filter);
      }
      _currentFolder = '';
    });
  }

  void _clearDashboardFilters() {
    setState(() {
      _quickFilters.clear();
      _selectedPhotoSourceId = null;
      _currentFolder = '';
    });
  }

  Widget _buildPhotoOrganizerSidebar() {
    final scheme = Theme.of(context).colorScheme;

    Widget sectionShell({
      required IconData icon,
      required String title,
      required Widget child,
    }) {
      return Container(
        padding: const EdgeInsets.all(11),
        decoration: _heritagePanelDecoration(
          radius: 16,
          opacity: 0.70,
          goldBorder: false,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: _heritageGold),
                ),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 18),
        children: [
          sectionShell(
            icon: Icons.tune_outlined,
            title: 'ORGANIZE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose one or more',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                _organizerSideItem(
                  icon: Icons.inventory_2_outlined,
                  count: _uncatalogedCount,
                  label: 'Uncataloged',
                  selected: _quickFilters.contains('Uncataloged'),
                  onTap: () => _toggleDashboardFilter('Uncataloged'),
                ),
                _organizerSideItem(
                  icon: Icons.event_outlined,
                  count: _missingDateCount,
                  label: 'No date',
                  selected: _quickFilters.contains('No Date'),
                  onTap: () => _toggleDashboardFilter('No Date'),
                ),
                _organizerSideItem(
                  icon: Icons.place_outlined,
                  count: _missingLocationCount,
                  label: 'No location',
                  selected: _quickFilters.contains('No Location'),
                  onTap: () => _toggleDashboardFilter('No Location'),
                ),
                _organizerSideItem(
                  icon: Icons.people_outline,
                  count: _missingPeopleCount,
                  label: 'No people',
                  selected: _quickFilters.contains('No People'),
                  onTap: () => _toggleDashboardFilter('No People'),
                ),
                _organizerSideItem(
                  icon: Icons.notes_outlined,
                  count: _missingDescriptionCount,
                  label: 'No description',
                  selected: _quickFilters.contains('No Description'),
                  onTap: () => _toggleDashboardFilter('No Description'),
                ),
                _organizerSideItem(
                  icon: Icons.new_releases_outlined,
                  count: _recentlyAddedCount,
                  label: 'Recently added',
                  selected: _quickFilters.contains('Recently Added'),
                  onTap: _recentlyAddedCount == 0
                      ? () {}
                      : () => _toggleDashboardFilter('Recently Added'),
                ),
                if (_quickFilters.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  OutlinedButton.icon(
                    onPressed: _clearDashboardFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: Text(
                      _quickFilters.length == 1
                          ? 'Clear filter'
                          : 'Clear ${_quickFilters.length} filters',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          sectionShell(
            icon: Icons.fact_check_outlined,
            title: 'REVIEW',
            child: Column(
              children: [
                _reviewActionButton(
                  icon: Icons.compare_outlined,
                  label: 'Possible duplicates',
                  count: _possibleDuplicateCount,
                  unknownLabel: 'Scan',
                  onTap: _possibleDuplicateScanning || _duplicateScanning
                      ? null
                      : () => _findPossibleDuplicates(),
                ),
                const SizedBox(height: 7),
                _reviewActionButton(
                  icon: Icons.person_search_outlined,
                  label: 'Unidentified faces',
                  count: _unidentifiedFaceCount,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UnidentifiedFacesScreen(),
                      ),
                    );
                    if (!mounted) return;
                    final catalogRecords = await _databaseHelper
                        .getAllPhotoCatalogMetadata();
                    final faceCount = await _databaseHelper
                        .getUnconfirmedFaceCount();
                    setState(() {
                      _catalogByPath = {
                        for (final record in catalogRecords)
                          record.filePath: record,
                      };
                      _unidentifiedFaceCount = faceCount;
                    });
                  },
                ),
                const SizedBox(height: 7),
                _reviewActionButton(
                  icon: Icons.restore_from_trash_outlined,
                  label: 'Duplicate Trash',
                  count: _duplicateTrashCount,
                  onTap: _openDuplicateTrash,
                ),
                const SizedBox(height: 7),
                _reviewActionButton(
                  icon: Icons.preview_outlined,
                  label: 'Metadata preview',
                  onTap: _openMetadataWritePreview,
                ),
                const SizedBox(height: 7),
                _reviewActionButton(
                  icon: Icons.data_object_outlined,
                  label: 'Metadata tools',
                  onTap: _openMetadataImport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewActionButton({
    required IconData icon,
    required String label,
    int? count,
    String unknownLabel = '—',
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (count != null || unknownLabel != '—')
                _reviewCountBadge(count, unknownLabel: unknownLabel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewCountBadge(int? count, {String unknownLabel = '—'}) {
    final scheme = Theme.of(context).colorScheme;
    final text = count == null ? unknownLabel : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _organizerSideItem({
    required IconData icon,
    required int count,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        elevation: selected ? 1 : 0,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.55)
                    : scheme.outlineVariant.withValues(alpha: 0.65),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.16)
                        : scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: selected
                        ? scheme.primary
                        : scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _selectionMode) {
          _exitPhotoSelectionMode();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: const Color(0xFF071A2B).withValues(alpha: 0.76),
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: const SizedBox.shrink(),
          actions: [
            if (_libraryPath != null) ...[
              // Batch selection belongs inside an opened photo folder, not on
              // the Pictures & Folders landing screen.
              if (_currentFolder.isNotEmpty && _selectionMode) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      '${_selectedPaths.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _selectAllVisiblePhotos,
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select All'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _selectedPaths.isEmpty
                      ? null
                      : _clearPhotoSelection,
                  icon: const Icon(Icons.deselect),
                  label: const Text('Clear'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _selectedPaths.isEmpty ? null : _openBatchEditor,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Edit Selected'),
                ),
                const SizedBox(width: 8),
              ],
              if (_currentFolder.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: _toggleSelectionMode,
                  icon: Icon(
                    _selectionMode ? Icons.close : Icons.check_box_outlined,
                  ),
                  label: Text(_selectionMode ? 'Cancel' : 'Select Photos'),
                ),
                const SizedBox(width: 4),
              ],
              PopupMenuButton<String>(
                tooltip: 'Photo Tools',
                onSelected: (value) async {
                  switch (value) {
                    case 'possible_duplicates':
                      await _findPossibleDuplicates();
                      break;
                    case 'exact_duplicates':
                      await _findExactDuplicates();
                      break;
                    case 'metadata':
                      _openMetadataImport();
                      break;
                    case 'face_scan':
                      _openWholeLibraryFaceScan();
                      break;
                    case 'unidentified_faces':
                      await _openUnidentifiedFacesFromHealth();
                      break;
                    case 'people':
                      _openPeople();
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'possible_duplicates',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.compare_outlined),
                      title: Text('Duplicate Review'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'exact_duplicates',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.content_copy_outlined),
                      title: Text('Exact Duplicates'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'metadata',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('Import Metadata'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'face_scan',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.manage_search),
                      title: Text('Scan Library for Faces'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'unidentified_faces',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.person_search_outlined),
                      title: Text('Unidentified Faces'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'people',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.people_alt_outlined),
                      title: Text('People'),
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: const [
                      Icon(Icons.build_outlined),
                      SizedBox(width: 6),
                      Text('Tools'),
                      SizedBox(width: 2),
                      Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Photo Analysis Settings',
                onPressed: _selectionMode
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const PhotoAnalysisSettingsScreen(),
                          ),
                        );
                      },
                icon: const Icon(Icons.tune_outlined),
              ),
              IconButton(
                tooltip: 'Rescan Photo Library',
                onPressed: _scanning || _selectionMode ? null : _scanLibrary,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            if (_scanning) const LinearProgressIndicator(),
            if (_duplicateScanning || _possibleDuplicateScanning)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: _duplicateScanTotal == 0
                            ? null
                            : (_duplicateScanCurrent / _duplicateScanTotal)
                                  .clamp(0.0, 1.0),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _possibleDuplicateScanning
                                  ? 'Indexing new/changed photos... '
                                        '$_duplicateScanCurrent / $_duplicateScanTotal'
                                  : 'Checking for exact duplicate photos... '
                                        '$_duplicateScanCurrent / $_duplicateScanTotal',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (_possibleDuplicateScanning)
                            TextButton.icon(
                              onPressed: _cancelPossibleDuplicateScan,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('Cancel'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_libraryPath != null) _buildPhotoReferenceHero(),
            Expanded(
              child:
                  _photoSources.isNotEmpty &&
                      !_exploreMode &&
                      !_selectionMode &&
                      _currentFolder.isEmpty
                  ? _buildPhotosLanding()
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_photoSources.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_photo_alternate_outlined, size: 72),
                const SizedBox(height: 18),
                Text(
                  'Add a photo source',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Connect Google Drive or iCloud alongside your existing library. Heirloom Atlas indexes photos in '
                  'place, so the originals stay where they are. New or changed '
                  'photos can then flow through your existing photo-analysis '
                  'and face-review workflow.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _showAddPhotoSourceDialog,
                  icon: const Icon(Icons.add_link_outlined),
                  label: const Text('Add Photo Source'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_selectionMode && _currentFolder.isEmpty) ...[
          SizedBox(width: 340, child: _buildPhotoOrganizerSidebar()),
          const VerticalDivider(width: 1),
        ],
        Expanded(
          child: Column(
            children: [
              if (_currentFolder.isNotEmpty) _buildBreadcrumbs(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  children: [
                    if (_currentFolder.isEmpty && !_selectionMode)
                      _buildPhotoWorldDashboard(),
                    if (_currentFolder.isEmpty && !_selectionMode)
                      _buildCollectionHealthCard(),
                    if (_currentFolder.isEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.folder_copy_outlined,
                            size: 20,
                            color: _heritageGold,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Pictures & Folders',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _heritageCream,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildAllPhotosCard(),
                    ],
                    ..._childFolders.map(_buildFolderCard),
                    if (_filteredPhotosInCurrentFolder.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _currentFolder.isEmpty
                                  ? 'Photos in Pictures'
                                  : 'Photos in ${path.basename(_currentFolder)}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildPhotoGrid(_filteredPhotosInCurrentFolder),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbs() {
    final segments = _folderSegments(_currentFolder);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectionMode
                        ? null
                        : () => setState(() => _currentFolder = ''),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Pictures'),
                  ),
                  for (var i = 0; i < segments.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 18),
                    TextButton(
                      onPressed: _selectionMode
                          ? null
                          : () {
                              final target = path.joinAll(
                                segments.take(i + 1).toList(),
                              );
                              setState(() => _currentFolder = target);
                            },
                      child: Text(segments[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllPhotosCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.photo_library_outlined),
        title: const Text(
          'All Photos',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_filteredPhotos.length} matching photos across all folders',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _selectionMode
            ? null
            : () {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => Dialog(
                    child: SizedBox(
                      width: 1100,
                      height: 780,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'All Photos',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      Text(
                                        '${_filteredPhotos.length} matching photos',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredPhotos.length,
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 285,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 0.78,
                                  ),
                              itemBuilder: (context, index) => _photoTile(
                                _filteredPhotos[index],
                                _filteredPhotos,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
      ),
    );
  }

  Widget _buildFolderCard(_PhotoFolder folder) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(
          folder.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_recursiveCount(folder.path)} photos including subfolders',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _selectionMode
            ? null
            : () => setState(() => _currentFolder = folder.path),
      ),
    );
  }

  Widget _buildPhotoGrid(List<VaultPhoto> photos) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 285,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) => _photoTile(photos[index], photos),
    );
  }

  Widget _photoTile(
    VaultPhoto photo,
    List<VaultPhoto> navigationPhotos, {
    bool searchSelectionMode = false,
  }) {
    final file = File(photo.filePath);
    final selected = _selectedPaths.contains(photo.filePath);
    final atlasFavorite = _atlasFavoritePhotoPaths.contains(photo.filePath);
    final tileSelectionMode = _selectionMode || searchSelectionMode;
    final metadata = _catalogByPath[photo.filePath];

    final peopleCount = metadata?.people.length ?? 0;
    final location = metadata?.location.trim() ?? '';
    final description = metadata?.description.trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handlePhotoSelectionClick(
          photo,
          navigationPhotos,
          forceSelectionMode: searchSelectionMode,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        width: double.infinity,
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: file.existsSync()
                            ? Image.file(
                                file,
                                fit: BoxFit.contain,
                                cacheWidth: 600,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 44,
                                  ),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.image_not_supported_outlined),
                              ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photo.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          _PhotoMetaPill(
                            icon: Icons.people_outline,
                            text: peopleCount == 0
                                ? 'No people'
                                : '$peopleCount ${peopleCount == 1 ? 'person' : 'people'}',
                            missing: peopleCount == 0,
                          ),
                          if (location.isNotEmpty)
                            _PhotoMetaPill(
                              icon: Icons.place_outlined,
                              text: location,
                            )
                          else
                            const _PhotoMetaPill(
                              icon: Icons.place_outlined,
                              text: 'No location',
                              missing: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!tileSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: const Color(0xFF071A2B).withValues(alpha: .90),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: atlasFavorite
                        ? 'Remove from Atlas Book favorites'
                        : 'Favorite for Atlas Book',
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    onPressed: () => _toggleAtlasBookFavorite(photo),
                    icon: Icon(
                      atlasFavorite ? Icons.star : Icons.star_outline,
                      color: atlasFavorite ? _heritageGold : _heritageCream,
                    ),
                  ),
                ),
              ),
            if (!tileSelectionMode && _currentFolder.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: const Color(0xFF071A2B).withValues(alpha: .90),
                  borderRadius: BorderRadius.circular(3),
                  child: PopupMenuButton<String>(
                    tooltip: 'Photo actions',
                    icon: Icon(
                      Icons.more_vert,
                      size: 19,
                      color: _heritageCream,
                    ),
                    onSelected: (value) async {
                      if (value == 'folder_cover') {
                        await _setFolderCover(photo);
                      } else if (value == 'move_to_trash') {
                        await _movePhotoToTrash(photo);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'folder_cover',
                        child: Row(
                          children: [
                            Icon(Icons.photo_library_outlined, size: 18),
                            SizedBox(width: 9),
                            Text('Set as Folder Cover'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'move_to_trash',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18),
                            SizedBox(width: 9),
                            Text('Move to Trash'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (tileSelectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleSelected(photo),
                  ),
                ),
              ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<Map<String, Object?>> _fingerprintPhotoBatch(
  List<Map<String, Object?>> inputs,
) {
  final results = <Map<String, Object?>>[];
  for (final input in inputs) {
    final filePath = input['file_path'] as String? ?? '';
    try {
      final bytes = File(filePath).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        results.add({'file_path': filePath, 'error': 'Unsupported image'});
        continue;
      }

      final oriented = img.bakeOrientation(decoded);
      final small = img.copyResize(
        oriented,
        width: 17,
        height: 16,
        interpolation: img.Interpolation.average,
      );

      var hash = BigInt.zero;
      var bit = 0;
      var totalR = 0;
      var totalG = 0;
      var totalB = 0;
      var pixelCount = 0;

      int luminanceAt(int x, int y) {
        final pixel = small.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        return ((r * 299) + (g * 587) + (b * 114)) ~/ 1000;
      }

      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          if (luminanceAt(x, y) > luminanceAt(x + 1, y)) {
            hash |= BigInt.one << bit;
          }
          bit++;
        }
      }

      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 17; x++) {
          final pixel = small.getPixel(x, y);
          totalR += pixel.r.toInt();
          totalG += pixel.g.toInt();
          totalB += pixel.b.toInt();
          pixelCount++;
        }
      }

      results.add({
        'file_path': filePath,
        'hash_hex': hash.toRadixString(16),
        'average_r': totalR ~/ pixelCount,
        'average_g': totalG ~/ pixelCount,
        'average_b': totalB ~/ pixelCount,
        'error': '',
      });
    } catch (error) {
      results.add({'file_path': filePath, 'error': error.toString()});
    }
  }
  return results;
}

Future<List<Map<String, Object?>>> _compareFingerprintRecords(
  List<Map<String, Object?>> records,
) async {
  if (records.length < 2) {
    return <Map<String, Object?>>[];
  }

  int asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  final hashes = records.map((record) {
    final value = record['hash_hex'] as String? ?? '0';
    return BigInt.parse(value.isEmpty ? '0' : value, radix: 16);
  }).toList();

  // Verify likely mirrored copies byte-for-byte before the visual
  // similarity pass. This gives us the certainty needed for future safe
  // bulk removal of redundant Local copies after confirming OneDrive copies.
  final likelyExactGroups = <String, List<int>>{};
  for (var i = 0; i < records.length; i++) {
    final record = records[i];
    final fileSize = asInt(record['file_size']);
    // Exact duplicates must not depend on the visual fingerprint cache. Two
    // byte-identical files can have stale/incompatible cached visual hashes.
    // File size is a safe candidate gate; the existing byte-for-byte comparison
    // below remains the final authority before a pair is marked 100% exact.
    final key = '$fileSize';
    likelyExactGroups.putIfAbsent(key, () => <int>[]).add(i);
  }

  Future<bool> filesAreByteIdentical(
    String firstPath,
    String secondPath,
  ) async {
    final first = File(firstPath);
    final second = File(secondPath);
    if (!await first.exists() || !await second.exists()) return false;

    final firstLength = await first.length();
    final secondLength = await second.length();
    if (firstLength != secondLength) return false;

    const chunkSize = 1024 * 1024;
    final firstHandle = await first.open();
    final secondHandle = await second.open();
    try {
      var offset = 0;
      while (offset < firstLength) {
        final remaining = firstLength - offset;
        final count = remaining < chunkSize ? remaining : chunkSize;
        final a = await firstHandle.read(count);
        final b = await secondHandle.read(count);
        if (a.length != b.length) return false;
        for (var k = 0; k < a.length; k++) {
          if (a[k] != b[k]) return false;
        }
        offset += count;
      }
      return true;
    } finally {
      await firstHandle.close();
      await secondHandle.close();
    }
  }

  final exactPairKeys = <String>{};
  final exactMatches = <Map<String, Object?>>[];
  for (final indexes in likelyExactGroups.values) {
    if (indexes.length < 2) continue;
    for (var a = 0; a < indexes.length; a++) {
      for (var b = a + 1; b < indexes.length; b++) {
        final i = indexes[a];
        final j = indexes[b];
        final firstPath = records[i]['file_path'] as String? ?? '';
        final secondPath = records[j]['file_path'] as String? ?? '';
        if (firstPath.isEmpty || secondPath.isEmpty) continue;

        if (await filesAreByteIdentical(firstPath, secondPath)) {
          final key = i < j ? '$i:$j' : '$j:$i';
          exactPairKeys.add(key);
          exactMatches.add({
            'first_path': firstPath,
            'second_path': secondPath,
            'similarity': 100,
          });
        }
      }
    }
  }

  final buckets = <String, List<int>>{};
  for (var i = 0; i < hashes.length; i++) {
    for (var chunk = 0; chunk < 16; chunk++) {
      final value = ((hashes[i] >> (chunk * 16)) & BigInt.from(0xFFFF)).toInt();
      buckets.putIfAbsent('$chunk:$value', () => <int>[]).add(i);
    }
  }

  final overlaps = <String, int>{};
  for (final indexes in buckets.values) {
    if (indexes.length < 2 || indexes.length > 350) continue;
    for (var a = 0; a < indexes.length; a++) {
      for (var b = a + 1; b < indexes.length; b++) {
        final i = indexes[a];
        final j = indexes[b];
        final key = i < j ? '$i:$j' : '$j:$i';
        overlaps[key] = (overlaps[key] ?? 0) + 1;
      }
    }
  }

  int hamming(BigInt a, BigInt b) {
    var value = a ^ b;
    var count = 0;
    while (value != BigInt.zero) {
      count++;
      value &= value - BigInt.one;
    }
    return count;
  }

  final matches = <Map<String, Object?>>[...exactMatches];
  for (final entry in overlaps.entries) {
    if (exactPairKeys.contains(entry.key)) continue;
    if (entry.value < 4) continue;

    final parts = entry.key.split(':');
    final i = int.parse(parts[0]);
    final j = int.parse(parts[1]);
    final first = records[i];
    final second = records[j];

    final distance = hamming(hashes[i], hashes[j]);
    if (distance > 8) continue;

    final colorDistance =
        (asInt(first['average_r']) - asInt(second['average_r'])).abs() +
        (asInt(first['average_g']) - asInt(second['average_g'])).abs() +
        (asInt(first['average_b']) - asInt(second['average_b'])).abs();
    if (colorDistance > 95) continue;

    final exactLooking =
        asInt(first['file_size']) == asInt(second['file_size']) &&
        hashes[i] == hashes[j] &&
        colorDistance == 0;

    final similarity = exactLooking
        ? 99
        : (100 - (distance * 8) - (colorDistance ~/ 12)).clamp(0, 99);
    if (similarity < 60) continue;

    matches.add({
      'first_path': first['file_path'],
      'second_path': second['file_path'],
      'similarity': similarity,
    });
  }

  matches.sort(
    (a, b) => asInt(b['similarity']).compareTo(asInt(a['similarity'])),
  );
  return matches;
}

Future<List<Map<String, Object?>>> _compareLocalFolderToOneDriveDeep(
  List<Map<String, Object?>> records,
) async {
  int asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int bitCount(BigInt value) {
    var count = 0;
    var v = value;
    while (v != BigInt.zero) {
      v &= v - BigInt.one;
      count++;
    }
    return count;
  }

  final local = <Map<String, Object?>>[];
  final oneDrive = <Map<String, Object?>>[];
  for (final record in records) {
    final source = (record['source_label'] as String? ?? '').trim();
    if (source == 'Local Folder') {
      local.add(record);
    } else if (source == 'OneDrive') {
      oneDrive.add(record);
    }
  }
  if (local.isEmpty || oneDrive.isEmpty) return <Map<String, Object?>>[];

  BigInt hashOf(Map<String, Object?> record) {
    final text = record['hash_hex'] as String? ?? '0';
    return BigInt.parse(text.isEmpty ? '0' : text, radix: 16);
  }

  // Build 8-bit hash-chunk buckets for OneDrive. Requiring only two shared
  // chunks is intentionally broader than the normal matcher, while the final
  // Hamming/color checks keep the review list useful.
  final oneHashes = oneDrive.map(hashOf).toList();
  final buckets = <String, List<int>>{};
  for (var i = 0; i < oneHashes.length; i++) {
    final hash = oneHashes[i];
    for (var chunk = 0; chunk < 32; chunk++) {
      final value = ((hash >> (chunk * 8)) & BigInt.from(255)).toInt();
      buckets.putIfAbsent('$chunk:$value', () => <int>[]).add(i);
    }
  }

  final results = <Map<String, Object?>>[];
  for (final localRecord in local) {
    final localHash = hashOf(localRecord);
    final votes = <int, int>{};
    for (var chunk = 0; chunk < 32; chunk++) {
      final value = ((localHash >> (chunk * 8)) & BigInt.from(255)).toInt();
      final indexes = buckets['$chunk:$value'];
      if (indexes == null || indexes.length > 600) continue;
      for (final index in indexes) {
        votes[index] = (votes[index] ?? 0) + 1;
      }
    }

    final candidates = votes.entries
        .where((entry) => entry.value >= 2)
        .toList();
    Map<String, Object?>? best;
    var bestSimilarity = 0;

    for (final candidate in candidates) {
      final other = oneDrive[candidate.key];
      final distance = bitCount(localHash ^ oneHashes[candidate.key]);
      if (distance > 52) continue;

      final colorDistance =
          (asInt(localRecord['average_r']) - asInt(other['average_r'])).abs() +
          (asInt(localRecord['average_g']) - asInt(other['average_g'])).abs() +
          (asInt(localRecord['average_b']) - asInt(other['average_b'])).abs();
      if (colorDistance > 210) continue;

      // Review-only confidence. Never return 100 here.
      final similarity = (99 - distance - (colorDistance ~/ 24)).clamp(0, 99);
      if (similarity < 68 || similarity <= bestSimilarity) continue;

      bestSimilarity = similarity;
      best = <String, Object?>{
        'first_path': localRecord['file_path'],
        'second_path': other['file_path'],
        'similarity': similarity,
        'deep_match': true,
      };
    }

    if (best != null) results.add(best);
  }

  results.sort(
    (a, b) => asInt(b['similarity']).compareTo(asInt(a['similarity'])),
  );
  return results;
}

class _MetadataBatchProgress {
  final int total;
  final int processed;
  final int succeeded;
  final int failed;
  final int skipped;
  final String currentFile;

  const _MetadataBatchProgress({
    required this.total,
    this.processed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = 0,
    this.currentFile = '',
  });
}

class _MetadataBatchFailure {
  final String fileName;
  final String message;

  const _MetadataBatchFailure({required this.fileName, required this.message});
}

class _PossibleDuplicatePair {
  final VaultPhoto first;
  final VaultPhoto second;
  final int similarity;

  const _PossibleDuplicatePair({
    required this.first,
    required this.second,
    required this.similarity,
  });
}

class _PossibleDuplicatesDialog extends StatefulWidget {
  final List<_PossibleDuplicatePair> pairs;
  final bool resultsLimited;
  final Future<bool> Function(VaultPhoto photo) onMoveToTrash;
  final Future<bool> Function(VaultPhoto keep, VaultPhoto remove)
  onMergeAndKeep;
  final Future<bool> Function(_PossibleDuplicatePair pair) onNotMatch;
  final Map<String, PhotoCatalogMetadata> catalogByPath;
  final List<Map<String, Object?>> photoSources;
  final Map<String, int> sourceCounts;
  final int indexedCount;
  final int fingerprintCount;
  final Map<String, int> matchBreakdown;
  final int exactLookingCount;
  final int similarCount;
  final int crossSourceSameNamePairs;
  final int crossSourceSameNameAndSizePairs;
  final Future<int> Function() onRemoveVerifiedLocalDuplicates;
  final Future<int> Function(List<VaultPhoto>) onMoveSelectedLocalCopies;

  const _PossibleDuplicatesDialog({
    required this.pairs,
    required this.resultsLimited,
    required this.onMoveToTrash,
    required this.onMergeAndKeep,
    required this.onNotMatch,
    required this.catalogByPath,
    required this.photoSources,
    required this.sourceCounts,
    required this.indexedCount,
    required this.fingerprintCount,
    required this.matchBreakdown,
    required this.exactLookingCount,
    required this.similarCount,
    required this.crossSourceSameNamePairs,
    required this.crossSourceSameNameAndSizePairs,
    required this.onRemoveVerifiedLocalDuplicates,
    required this.onMoveSelectedLocalCopies,
  });

  @override
  State<_PossibleDuplicatesDialog> createState() =>
      _PossibleDuplicatesDialogState();
}

class _PossibleDuplicatesDialogState extends State<_PossibleDuplicatesDialog> {
  final Set<String> _dismissed = <String>{};
  bool _changed = false;
  bool _bulkRemovingLocal = false;
  String _pairFilter = 'all';
  final Set<String> _selectedLocalPaths = <String>{};
  bool _movingSelectedLocal = false;
  String? _focusedSelectedPath;
  final Map<String, GlobalKey> _duplicatePairKeys = <String, GlobalKey>{};

  GlobalKey _keyForDuplicatePair(_PossibleDuplicatePair pair) =>
      _duplicatePairKeys.putIfAbsent(_pairKey(pair), GlobalKey.new);

  void _scrollToFirstSelectedPair() {
    final selectedPair = _visiblePairs()
        .cast<_PossibleDuplicatePair?>()
        .firstWhere(
          (pair) =>
              pair != null &&
              (_isSelectedLocal(pair.first) || _isSelectedLocal(pair.second)),
          orElse: () => null,
        );
    if (selectedPair == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _keyForDuplicatePair(selectedPair).currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  String _sourceForPhoto(VaultPhoto photo) {
    final normalized = path.normalize(photo.filePath).toLowerCase();
    var sourceKind = 'Unknown';
    var bestLength = -1;

    for (final source in widget.photoSources) {
      final root = (source['root_path']?.toString() ?? '').trim();
      if (root.isEmpty) continue;

      final normalizedRoot = path.normalize(root).toLowerCase();
      final separator = path.separator;
      final insideSource =
          normalized == normalizedRoot ||
          normalized.startsWith('$normalizedRoot$separator');
      if (!insideSource || normalizedRoot.length <= bestLength) continue;

      final type = (source['source_type']?.toString() ?? '')
          .trim()
          .toLowerCase();
      final display = (source['display_name']?.toString() ?? '')
          .trim()
          .toLowerCase();

      // Use a stable source category for duplicate bulk actions. The visible
      // source name may be a folder name, so comparing display_name directly
      // with "Local Folder" / "OneDrive" can leave every bulk selection empty.
      if (type.contains('onedrive') || display.contains('onedrive')) {
        sourceKind = 'OneDrive';
      } else if (type == 'local_folder' ||
          type.contains('local') ||
          display.contains('local folder') ||
          display.contains('this computer')) {
        sourceKind = 'Local Folder';
      } else {
        sourceKind = 'Other';
      }
      bestLength = normalizedRoot.length;
    }

    return sourceKind;
  }

  bool _matchesPairFilter(_PossibleDuplicatePair pair) {
    if (_pairFilter == 'all') return true;
    final first = _sourceForPhoto(pair.first);
    final second = _sourceForPhoto(pair.second);

    switch (_pairFilter) {
      case 'local_onedrive':
        return (first == 'Local Folder' && second == 'OneDrive') ||
            (first == 'OneDrive' && second == 'Local Folder');
      case 'local_local':
        return first == 'Local Folder' && second == 'Local Folder';
      case 'onedrive_onedrive':
        return first == 'OneDrive' && second == 'OneDrive';
      case 'exact':
        return pair.similarity == 100;
      case 'similar':
        return pair.similarity < 100;
      default:
        return true;
    }
  }

  VaultPhoto? _localPhotoForCrossSourcePair(_PossibleDuplicatePair pair) {
    final firstSource = _sourceForPhoto(pair.first);
    final secondSource = _sourceForPhoto(pair.second);
    if (firstSource == 'Local Folder' && secondSource == 'OneDrive') {
      return pair.first;
    }
    if (secondSource == 'Local Folder' && firstSource == 'OneDrive') {
      return pair.second;
    }
    return null;
  }

  bool _isSelectedLocal(VaultPhoto photo) => _selectedLocalPaths.contains(
    path.normalize(photo.filePath).toLowerCase(),
  );

  void _toggleSelectedLocal(VaultPhoto photo, bool selected) {
    final key = path.normalize(photo.filePath).toLowerCase();
    setState(() {
      if (selected) {
        _selectedLocalPaths.add(key);
      } else {
        _selectedLocalPaths.remove(key);
        if (_focusedSelectedPath == key) _focusedSelectedPath = null;
      }
    });
  }

  int _duplicateMetadataScore(VaultPhoto photo) {
    final metadata = widget.catalogByPath[photo.filePath];
    if (metadata == null) return 0;
    var score = 0;
    score += metadata.people.length * 4;
    score += metadata.tags.length * 2;
    if (metadata.approximateDate.trim().isNotEmpty) score += 3;
    if (metadata.location.trim().isNotEmpty) score += 3;
    if (metadata.description.trim().isNotEmpty) score += 4;
    if (metadata.notes.trim().isNotEmpty) score += 2;
    return score;
  }

  VaultPhoto? _recommendedKeeper(_PossibleDuplicatePair pair) {
    final firstMeta = _duplicateMetadataScore(pair.first);
    final secondMeta = _duplicateMetadataScore(pair.second);
    final firstSize = pair.first.fileSize;
    final secondSize = pair.second.fileSize;

    if (firstSize > secondSize * 1.25 && firstMeta >= secondMeta) {
      return pair.first;
    }
    if (secondSize > firstSize * 1.25 && secondMeta >= firstMeta) {
      return pair.second;
    }
    if (firstMeta >= secondMeta + 3) return pair.first;
    if (secondMeta >= firstMeta + 3) return pair.second;

    // Byte-for-byte verified exact duplicates always get a deterministic
    // keeper so Select Recommended can handle same-source copies too.
    if (pair.similarity == 100) {
      final firstSource = _sourceForPhoto(pair.first);
      final secondSource = _sourceForPhoto(pair.second);

      // Prefer the managed OneDrive copy over a Local Folder copy.
      if (firstSource == 'OneDrive' && secondSource == 'Local Folder') {
        return pair.first;
      }
      if (secondSource == 'OneDrive' && firstSource == 'Local Folder') {
        return pair.second;
      }

      // For same-source exact duplicates, prefer the original-looking
      // filename over common Windows Explorer copy names.
      bool looksLikeCopyName(VaultPhoto photo) {
        final stem = path
            .basenameWithoutExtension(photo.fileName)
            .toLowerCase();
        return RegExp(r' - copy(?: \\(\\d+\\))?$').hasMatch(stem) ||
            RegExp(r' \\(\\d+\\)$').hasMatch(stem);
      }

      final firstLooksCopied = looksLikeCopyName(pair.first);
      final secondLooksCopied = looksLikeCopyName(pair.second);
      if (firstLooksCopied != secondLooksCopied) {
        return firstLooksCopied ? pair.second : pair.first;
      }

      // Final stable tie-breaker: keep the lexically earlier path. This makes
      // the recommendation repeatable without implying a quality difference.
      final firstPath = path.normalize(pair.first.filePath).toLowerCase();
      final secondPath = path.normalize(pair.second.filePath).toLowerCase();
      return firstPath.compareTo(secondPath) <= 0 ? pair.first : pair.second;
    }

    return null;
  }

  List<_PossibleDuplicatePair> _visiblePairs() {
    final pairs = widget.pairs
        .where((pair) => !_dismissed.contains(_pairKey(pair)))
        .where(_matchesPairFilter)
        .toList();

    final focused = _focusedSelectedPath;
    if (focused == null) return pairs;

    // Focus mode intentionally shows ONE comparison card, even when the same
    // selected file participates in several duplicate pairs. This keeps a
    // unique selected file from looking like several different selections.
    for (final pair in pairs) {
      final firstKey = path.normalize(pair.first.filePath).toLowerCase();
      final secondKey = path.normalize(pair.second.filePath).toLowerCase();
      if (firstKey == focused || secondKey == focused) {
        return <_PossibleDuplicatePair>[pair];
      }
    }
    return pairs;
  }

  void _selectAllShownLocalCopies() {
    final visible = _visiblePairs();
    setState(() {
      for (final pair in visible) {
        final local = _localPhotoForCrossSourcePair(pair);
        if (local != null) {
          _selectedLocalPaths.add(path.normalize(local.filePath).toLowerCase());
        }
      }
    });
  }

  void _selectRecommendedLocalRemovals() {
    // Recommendations are calculated from the currently filtered match list,
    // not from focus mode left over from a previous selection.
    final visible = widget.pairs
        .where((pair) => !_dismissed.contains(_pairKey(pair)))
        .where(_matchesPairFilter)
        .toList();
    String? firstSelectedPath;
    setState(() {
      _focusedSelectedPath = null;
      for (final pair in visible) {
        final keeper = _recommendedKeeper(pair);
        if (keeper == null) continue;

        VaultPhoto? removal;

        if (pair.similarity == 100) {
          // Exact duplicates are byte-for-byte verified, so select the
          // non-keeper even when both files come from the same source.
          removal = keeper.filePath == pair.first.filePath
              ? pair.second
              : pair.first;
        } else {
          // Preserve the conservative behavior for merely similar photos:
          // only recommend removing a Local Folder copy when the other copy
          // is the recommended keeper.
          final local = _localPhotoForCrossSourcePair(pair);
          if (local != null && keeper.filePath != local.filePath) {
            removal = local;
          }
        }

        if (removal == null) continue;
        final selectedPath = path.normalize(removal.filePath).toLowerCase();
        _selectedLocalPaths.add(selectedPath);
        firstSelectedPath ??= selectedPath;
      }

      // Bulk Select Recommended should leave the full filtered result set
      // visible. Focus mode is reserved for single-file/manual selection.
      _focusedSelectedPath = null;
    });
  }

  void _clearSelectedLocalCopies() {
    setState(() {
      _selectedLocalPaths.clear();
      _focusedSelectedPath = null;
    });
  }

  Future<void> _moveSelectedLocalCopies() async {
    if (_selectedLocalPaths.isEmpty || _movingSelectedLocal) return;

    final selectedPhotos = <VaultPhoto>[];
    final seen = <String>{};
    for (final pair in widget.pairs) {
      for (final photo in <VaultPhoto>[pair.first, pair.second]) {
        final key = path.normalize(photo.filePath).toLowerCase();
        if (_selectedLocalPaths.contains(key) && seen.add(key)) {
          selectedPhotos.add(photo);
        }
      }
    }
    if (selectedPhotos.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move Selected Copies?'),
        content: Text(
          '${selectedPhotos.length} selected '
          '${selectedPhotos.length == 1 ? 'copy' : 'copies'} will be moved to '
          'Heirloom Atlas Duplicate Trash.\n\n'
          'Exact-looking matches are byte-for-byte verified. Similar matches '
          'still require visual review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Move Selected'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _movingSelectedLocal = true);
    final moved = await widget.onMoveSelectedLocalCopies(selectedPhotos);
    if (!mounted) return;

    setState(() {
      _movingSelectedLocal = false;
      if (moved > 0) {
        _changed = true;
        for (final pair in widget.pairs) {
          final firstKey = path.normalize(pair.first.filePath).toLowerCase();
          final secondKey = path.normalize(pair.second.filePath).toLowerCase();
          if (_selectedLocalPaths.contains(firstKey) ||
              _selectedLocalPaths.contains(secondKey)) {
            _dismissed.add(_pairKey(pair));
          }
        }
        _selectedLocalPaths.clear();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          moved == 1
              ? 'Moved 1 selected copy to Duplicate Trash.'
              : 'Moved $moved selected copies to Duplicate Trash.',
        ),
      ),
    );
  }

  int _verifiedUniqueLocalDuplicateCount() {
    final unique = <String>{};

    String sourceFor(VaultPhoto photo) {
      final normalized = path.normalize(photo.filePath).toLowerCase();
      var label = 'Unknown';
      var bestLength = -1;
      for (final source in widget.photoSources) {
        final root = (source['root_path']?.toString() ?? '').trim();
        if (root.isEmpty) continue;
        final normalizedRoot = path.normalize(root).toLowerCase();
        if ((normalized == normalizedRoot ||
                normalized.startsWith('$normalizedRoot${path.separator}')) &&
            normalizedRoot.length > bestLength) {
          final display = (source['display_name']?.toString() ?? '').trim();
          label = display.isEmpty ? 'Photo Source' : display;
          bestLength = normalizedRoot.length;
        }
      }
      return label;
    }

    for (final pair in widget.pairs) {
      if (pair.similarity != 100) continue;
      final firstSource = sourceFor(pair.first);
      final secondSource = sourceFor(pair.second);

      VaultPhoto? local;
      if (firstSource == 'Local Folder' && secondSource == 'OneDrive') {
        local = pair.first;
      } else if (secondSource == 'Local Folder' && firstSource == 'OneDrive') {
        local = pair.second;
      }

      if (local != null) {
        unique.add(path.normalize(local.filePath).toLowerCase());
      }
    }
    return unique.length;
  }

  Future<void> _removeVerifiedLocalDuplicates() async {
    final uniqueLocalCount = _verifiedUniqueLocalDuplicateCount();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Verified Local Duplicates?'),
        content: Text(
          '$uniqueLocalCount unique Local Folder '
          '${uniqueLocalCount == 1 ? 'file has' : 'files have'} been verified '
          'byte-for-byte against a OneDrive copy.\n\n'
          'This will move only those Local Folder copies to Heirloom Atlas '
          'Duplicate Trash. OneDrive copies will not be removed.\n\n'
          'Nothing is permanently deleted by this action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Move Local Copies to Duplicate Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _bulkRemovingLocal = true);
    final removed = await widget.onRemoveVerifiedLocalDuplicates();
    if (!mounted) return;
    setState(() {
      _bulkRemovingLocal = false;
      if (removed > 0) _changed = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 1
              ? 'Moved 1 verified local duplicate to Duplicate Trash.'
              : 'Moved $removed verified local duplicates to Duplicate Trash.',
        ),
      ),
    );
    if (removed > 0) _finish();
  }

  String _pairKey(_PossibleDuplicatePair pair) {
    final first = path.normalize(pair.first.filePath).toLowerCase();
    final second = path.normalize(pair.second.filePath).toLowerCase();
    return first.compareTo(second) <= 0 ? '$first|$second' : '$second|$first';
  }

  void _finish() => Navigator.pop(context, _changed);

  Future<void> _markNotMatch(_PossibleDuplicatePair pair) async {
    final saved = await widget.onNotMatch(pair);
    if (!saved || !mounted) return;

    setState(() {
      _changed = true;
      _dismissed.add(_pairKey(pair));
    });
  }

  Future<void> _removePairPhoto(
    _PossibleDuplicatePair pair,
    VaultPhoto photo,
  ) async {
    final changed = await widget.onMoveToTrash(photo);
    if (!changed || !mounted) return;
    setState(() {
      _changed = true;
      _dismissed.add(_pairKey(pair));
    });
  }

  Future<void> _merge(
    _PossibleDuplicatePair pair,
    VaultPhoto keep,
    VaultPhoto remove,
  ) async {
    final changed = await widget.onMergeAndKeep(keep, remove);
    if (!changed || !mounted) return;
    setState(() {
      _changed = true;
      _dismissed.add(_pairKey(pair));
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePairs();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: Dialog(
        child: SizedBox(
          width: 1450,
          height: 820,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.compare_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Duplicate Review — FILTERS ACTIVE',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.pairs.isEmpty
                                ? 'No duplicate matches were found.'
                                : '${visible.length} '
                                      '${visible.length == 1 ? 'match' : 'matches'} '
                                      'to review',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      onPressed: _bulkRemovingLocal
                          ? null
                          : _removeVerifiedLocalDuplicates,
                      icon: _bulkRemovingLocal
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cleaning_services_outlined),
                      label: Text(
                        _bulkRemovingLocal
                            ? 'Moving Local Copies...'
                            : 'Remove Verified Local Duplicates '
                                  '(${_verifiedUniqueLocalDuplicateCount()})',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _bulkRemovingLocal ? null : _finish,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Row(
                  children: [
                    const Text(
                      'Show:',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _pairFilter,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Matches'),
                        ),
                        DropdownMenuItem(
                          value: 'exact',
                          child: Text('Exact-looking duplicates'),
                        ),
                        DropdownMenuItem(
                          value: 'similar',
                          child: Text('Similar duplicates'),
                        ),
                        DropdownMenuItem(
                          value: 'local_onedrive',
                          child: Text('Local ↔ OneDrive'),
                        ),
                        DropdownMenuItem(
                          value: 'local_local',
                          child: Text('Local ↔ Local'),
                        ),
                        DropdownMenuItem(
                          value: 'onedrive_onedrive',
                          child: Text('OneDrive ↔ OneDrive'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _pairFilter = value);
                      },
                    ),
                    const SizedBox(width: 14),
                    Text(
                      '${visible.length} shown',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _movingSelectedLocal
                          ? null
                          : _selectRecommendedLocalRemovals,
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Select Recommended'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _movingSelectedLocal
                          ? null
                          : _selectAllShownLocalCopies,
                      icon: const Icon(Icons.select_all, size: 18),
                      label: const Text('Select All Shown'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed:
                          _selectedLocalPaths.isEmpty || _movingSelectedLocal
                          ? null
                          : _clearSelectedLocalCopies,
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed:
                          _selectedLocalPaths.isEmpty || _movingSelectedLocal
                          ? null
                          : _moveSelectedLocalCopies,
                      icon: _movingSelectedLocal
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_sweep_outlined),
                      label: Text(
                        _movingSelectedLocal
                            ? 'Moving Selected...'
                            : 'Move Selected (${_selectedLocalPaths.length})',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 5,
                    children: [
                      Text(
                        'Indexed: ${widget.indexedCount}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Fingerprint-ready: ${widget.fingerprintCount}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      ...widget.sourceCounts.entries.map(
                        (entry) => Text('${entry.key}: ${entry.value}'),
                      ),
                      Text(
                        'Exact-looking: ${widget.exactLookingCount}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Similar: ${widget.similarCount}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Cross-source same filename: '
                        '${widget.crossSourceSameNamePairs}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Cross-source same filename + size: '
                        '${widget.crossSourceSameNameAndSizePairs}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      ...widget.matchBreakdown.entries.map(
                        (entry) => Text('${entry.key}: ${entry.value}'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('Review complete'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 1000 ? 2 : 1;
                          final rowCount =
                              (visible.length + columns - 1) ~/ columns;

                          Widget buildPairItem(_PossibleDuplicatePair pair) {
                            final localPhoto = _localPhotoForCrossSourcePair(
                              pair,
                            );
                            return Column(
                              key: _keyForDuplicatePair(pair),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (localPhoto != null)
                                  CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: _isSelectedLocal(localPhoto),
                                    secondary: IconButton(
                                      tooltip:
                                          'Select the recommended removal for this pair',
                                      onPressed: _movingSelectedLocal
                                          ? null
                                          : () {
                                              final keeper = _recommendedKeeper(
                                                pair,
                                              );
                                              if (keeper == null) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'No clear keeper is recommended for this pair. Review it manually.',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              _toggleSelectedLocal(
                                                localPhoto,
                                                keeper.filePath !=
                                                    localPhoto.filePath,
                                              );
                                            },
                                      icon: const Icon(
                                        Icons.auto_awesome_outlined,
                                      ),
                                    ),
                                    onChanged: _movingSelectedLocal
                                        ? null
                                        : (value) => _toggleSelectedLocal(
                                            localPhoto,
                                            value ?? false,
                                          ),
                                    title: Text(
                                      'Select Local Folder copy for Duplicate Trash — ${localPhoto.fileName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      (() {
                                        final keeper = _recommendedKeeper(pair);
                                        if (keeper == null) {
                                          return 'Manual review recommended — neither copy is clearly better.';
                                        }
                                        if (keeper.filePath ==
                                            localPhoto.filePath) {
                                          return 'Heirloom Atlas recommends keeping this Local Folder copy.';
                                        }
                                        return 'Recommended: keep the other copy; this local copy can go to Duplicate Trash.';
                                      })(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                _PossibleDuplicatePairCard(
                                  pair: pair,
                                  catalogByPath: widget.catalogByPath,
                                  photoSources: widget.photoSources,
                                  selectedFirst: _isSelectedLocal(pair.first),
                                  selectedSecond: _isSelectedLocal(pair.second),
                                  recommendedKeeperPath: _recommendedKeeper(
                                    pair,
                                  )?.filePath,
                                  onNotMatch: () => _markNotMatch(pair),
                                  onRemoveFirst: () =>
                                      _removePairPhoto(pair, pair.first),
                                  onRemoveSecond: () =>
                                      _removePairPhoto(pair, pair.second),
                                  onMergeKeepFirst: () =>
                                      _merge(pair, pair.first, pair.second),
                                  onMergeKeepSecond: () =>
                                      _merge(pair, pair.second, pair.first),
                                ),
                              ],
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: rowCount,
                            itemBuilder: (context, rowIndex) {
                              final firstIndex = rowIndex * columns;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var column = 0;
                                      column < columns;
                                      column++
                                    ) ...[
                                      if (column > 0) const SizedBox(width: 12),
                                      Expanded(
                                        child:
                                            firstIndex + column < visible.length
                                            ? buildPairItem(
                                                visible[firstIndex + column],
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Removed files go to Heirloom Atlas Duplicate Trash, '
                        'not permanent deletion. Merge combines catalog '
                        'information before moving the extra copy.',
                      ),
                    ),
                    FilledButton(onPressed: _finish, child: const Text('Done')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PossibleDuplicatePairCard extends StatelessWidget {
  final _PossibleDuplicatePair pair;
  final Map<String, PhotoCatalogMetadata> catalogByPath;
  final List<Map<String, Object?>> photoSources;
  final bool selectedFirst;
  final bool selectedSecond;
  final String? recommendedKeeperPath;
  final VoidCallback onNotMatch;
  final VoidCallback onRemoveFirst;
  final VoidCallback onRemoveSecond;
  final VoidCallback onMergeKeepFirst;
  final VoidCallback onMergeKeepSecond;

  const _PossibleDuplicatePairCard({
    required this.pair,
    required this.catalogByPath,
    required this.photoSources,
    required this.selectedFirst,
    required this.selectedSecond,
    required this.recommendedKeeperPath,
    required this.onNotMatch,
    required this.onRemoveFirst,
    required this.onRemoveSecond,
    required this.onMergeKeepFirst,
    required this.onMergeKeepSecond,
  });

  int _metadataScore(VaultPhoto photo) {
    final metadata = catalogByPath[photo.filePath];
    if (metadata == null) return 0;
    var score = 0;
    score += metadata.people.length * 4;
    score += metadata.tags.length * 2;
    if (metadata.approximateDate.trim().isNotEmpty) score += 3;
    if (metadata.location.trim().isNotEmpty) score += 3;
    if (metadata.description.trim().isNotEmpty) score += 4;
    if (metadata.notes.trim().isNotEmpty) score += 2;
    return score;
  }

  String _sourceName(VaultPhoto photo) {
    final normalized = path.normalize(photo.filePath).toLowerCase();
    Map<String, Object?>? best;
    var bestLength = -1;
    for (final source in photoSources) {
      final root = (source['root_path']?.toString() ?? '').trim();
      if (root.isEmpty) continue;
      final normalizedRoot = path.normalize(root).toLowerCase();
      if ((normalized == normalizedRoot ||
              normalized.startsWith('$normalizedRoot${path.separator}')) &&
          normalizedRoot.length > bestLength) {
        best = source;
        bestLength = normalizedRoot.length;
      }
    }
    if (best == null) return 'Unknown source';
    final name = (best['display_name']?.toString() ?? '').trim();
    return name.isEmpty ? 'Photo Source' : name;
  }

  String _recommendation() {
    final firstMeta = _metadataScore(pair.first);
    final secondMeta = _metadataScore(pair.second);
    final firstSize = pair.first.fileSize;
    final secondSize = pair.second.fileSize;

    final firstSource = _sourceName(pair.first);
    final secondSource = _sourceName(pair.second);
    final sourceText = firstSource == secondSource
        ? 'Same source'
        : '$firstSource ↔ $secondSource';

    if (firstSize > secondSize * 1.25 && firstMeta >= secondMeta) {
      return 'Recommended: keep LEFT — larger file'
          '${firstMeta > secondMeta ? ' and more catalog information' : ''}. • $sourceText';
    }
    if (secondSize > firstSize * 1.25 && secondMeta >= firstMeta) {
      return 'Recommended: keep RIGHT — larger file'
          '${secondMeta > firstMeta ? ' and more catalog information' : ''}. • $sourceText';
    }
    if (firstMeta >= secondMeta + 3) {
      return 'Recommended: keep LEFT — more catalog information. • $sourceText';
    }
    if (secondMeta >= firstMeta + 3) {
      return 'Recommended: keep RIGHT — more catalog information. • $sourceText';
    }
    if (pair.similarity == 100) {
      final firstKind = firstSource.toLowerCase().contains('onedrive');
      final secondKind = secondSource.toLowerCase().contains('onedrive');
      final firstLocal = firstSource.toLowerCase().contains('local');
      final secondLocal = secondSource.toLowerCase().contains('local');
      if (firstKind && secondLocal) {
        return 'Recommended: keep LEFT — preferred OneDrive photo source. • $sourceText';
      }
      if (secondKind && firstLocal) {
        return 'Recommended: keep RIGHT — preferred OneDrive photo source. • $sourceText';
      }
    }
    return 'Review manually — neither copy is clearly better. • $sourceText';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  pair.similarity == 100
                      ? 'Exact-looking duplicate'
                      : '${pair.similarity}% visual similarity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onNotMatch,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Not a Match'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _recommendation(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PossibleDuplicatePhoto(
                    sideLabel: 'LEFT',
                    photo: pair.first,
                    sourceName: _sourceName(pair.first),
                    metadata: catalogByPath[pair.first.filePath],
                    selectedForRemoval: selectedFirst,
                    markedKeep: selectedSecond,
                    onRemove: onRemoveFirst,
                    onMergeKeep: onMergeKeepFirst,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 55),
                  child: Icon(Icons.compare_arrows),
                ),
                Expanded(
                  child: _PossibleDuplicatePhoto(
                    sideLabel: 'RIGHT',
                    photo: pair.second,
                    sourceName: _sourceName(pair.second),
                    metadata: catalogByPath[pair.second.filePath],
                    selectedForRemoval: selectedSecond,
                    markedKeep: selectedFirst,
                    onRemove: onRemoveSecond,
                    onMergeKeep: onMergeKeepSecond,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PossibleDuplicatePhoto extends StatelessWidget {
  final String sideLabel;
  final VaultPhoto photo;
  final String sourceName;
  final PhotoCatalogMetadata? metadata;
  final bool selectedForRemoval;
  final bool markedKeep;
  final VoidCallback onRemove;
  final VoidCallback onMergeKeep;

  const _PossibleDuplicatePhoto({
    required this.sideLabel,
    required this.photo,
    required this.sourceName,
    required this.metadata,
    required this.selectedForRemoval,
    required this.markedKeep,
    required this.onRemove,
    required this.onMergeKeep,
  });

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes bytes';
  }

  String _formatModified(int milliseconds) {
    if (milliseconds <= 0) return 'Unknown';
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${date.month}/${date.day}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _metadataSummary() {
    if (metadata == null) return 'No catalog metadata';
    final parts = <String>[];
    if (metadata!.people.isNotEmpty) {
      parts.add('${metadata!.people.length} people');
    }
    if (metadata!.tags.isNotEmpty) parts.add('${metadata!.tags.length} tags');
    if (metadata!.approximateDate.trim().isNotEmpty) parts.add('date');
    if (metadata!.location.trim().isNotEmpty) parts.add('location');
    if (metadata!.description.trim().isNotEmpty) parts.add('description');
    if (metadata!.notes.trim().isNotEmpty) parts.add('notes');
    return parts.isEmpty ? 'No catalog metadata' : parts.join(' • ');
  }

  Widget _detail(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = File(photo.filePath);
    final folder = path.dirname(photo.filePath);

    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: selectedForRemoval
            ? scheme.errorContainer.withValues(alpha: .32)
            : markedKeep
            ? scheme.primaryContainer.withValues(alpha: .28)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedForRemoval
              ? scheme.error
              : markedKeep
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: .45),
          width: selectedForRemoval || markedKeep ? 3 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sideLabel,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (markedKeep)
                Chip(
                  avatar: const Icon(Icons.shield_outlined, size: 17),
                  label: const Text('KEEP'),
                  visualDensity: VisualDensity.compact,
                ),
              if (selectedForRemoval)
                Chip(
                  avatar: Icon(
                    Icons.check_circle,
                    size: 17,
                    color: scheme.error,
                  ),
                  label: const Text('REMOVE'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            height: 135,
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              cacheWidth: 600,
              errorBuilder: (_, _, _) =>
                  const Center(child: Icon(Icons.image_not_supported_outlined)),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            photo.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _detail(context, 'Source', sourceName, emphasize: true),
          _detail(context, 'Folder', folder),
          _detail(
            context,
            'Size',
            '${_formatBytes(photo.fileSize)} • ${photo.extension.replaceFirst('.', '').toUpperCase()}',
          ),
          _detail(
            context,
            'Modified',
            _formatModified(photo.modifiedMilliseconds),
          ),
          _detail(context, 'Metadata', _metadataSummary()),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.tonalIcon(
                onPressed: onMergeKeep,
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('Merge & Keep'),
              ),
              OutlinedButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExactDuplicatesDialog extends StatefulWidget {
  final List<List<VaultPhoto>> groups;
  final Map<String, PhotoCatalogMetadata> catalogByPath;
  final Future<bool> Function(VaultPhoto photo) onMoveToTrash;
  final Future<bool> Function(VaultPhoto keep, VaultPhoto remove)
  onMergeAndKeep;

  const _ExactDuplicatesDialog({
    required this.groups,
    required this.catalogByPath,
    required this.onMoveToTrash,
    required this.onMergeAndKeep,
  });

  @override
  State<_ExactDuplicatesDialog> createState() => _ExactDuplicatesDialogState();
}

class _ExactDuplicatesDialogState extends State<_ExactDuplicatesDialog> {
  late final List<List<VaultPhoto>> _groups = widget.groups
      .map((group) => List<VaultPhoto>.from(group))
      .toList();
  bool _changed = false;

  int get _duplicateCopies =>
      _groups.fold<int>(0, (sum, group) => sum + group.length - 1);

  void _finish() => Navigator.pop(context, _changed);

  Future<void> _remove(int groupIndex, VaultPhoto photo) async {
    final changed = await widget.onMoveToTrash(photo);
    if (!changed || !mounted) return;
    setState(() {
      _changed = true;
      _groups[groupIndex].removeWhere(
        (item) => item.filePath == photo.filePath,
      );
      if (_groups[groupIndex].length < 2) {
        _groups.removeAt(groupIndex);
      }
    });
  }

  Future<void> _mergeKeep(
    int groupIndex,
    VaultPhoto keep,
    VaultPhoto remove,
  ) async {
    final changed = await widget.onMergeAndKeep(keep, remove);
    if (!changed || !mounted) return;
    setState(() {
      _changed = true;
      _groups[groupIndex].removeWhere(
        (item) => item.filePath == remove.filePath,
      );
      if (_groups[groupIndex].length < 2) {
        _groups.removeAt(groupIndex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: Dialog(
        child: SizedBox(
          width: 1100,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.content_copy_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _groups.isEmpty
                            ? 'Exact Duplicate Photos'
                            : 'Exact Duplicate Photos • $_duplicateCopies extra copies',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _finish,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _groups.isEmpty
                    ? const Center(child: Text('No exact duplicates to review'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(18),
                        itemCount: _groups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          return _ExactDuplicateGroupCard(
                            number: index + 1,
                            photos: _groups[index],
                            catalogByPath: widget.catalogByPath,
                            onRemove: (photo) => _remove(index, photo),
                            onMergeKeep: (keep, remove) =>
                                _mergeKeep(index, keep, remove),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Choose the copy you want to keep. Removed copies go '
                        'to Duplicate Trash and can be recovered manually.',
                      ),
                    ),
                    FilledButton(onPressed: _finish, child: const Text('Done')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExactDuplicateGroupCard extends StatelessWidget {
  final int number;
  final List<VaultPhoto> photos;
  final Map<String, PhotoCatalogMetadata> catalogByPath;
  final Future<void> Function(VaultPhoto photo) onRemove;
  final Future<void> Function(VaultPhoto keep, VaultPhoto remove) onMergeKeep;

  const _ExactDuplicateGroupCard({
    required this.number,
    required this.photos,
    required this.catalogByPath,
    required this.onRemove,
    required this.onMergeKeep,
  });

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes bytes';
  }

  int _keeperScore(VaultPhoto photo) {
    final metadata = catalogByPath[photo.filePath];
    var score = 0;

    if (metadata != null) {
      score += metadata.people.length * 4;
      score += metadata.tags.length * 2;
      if (metadata.approximateDate.trim().isNotEmpty) score += 3;
      if (metadata.location.trim().isNotEmpty) score += 3;
      if (metadata.description.trim().isNotEmpty) score += 4;
      if (metadata.notes.trim().isNotEmpty) score += 2;
    }

    final base = path.basenameWithoutExtension(photo.fileName).toLowerCase();
    final looksGeneric = RegExp(
      r'^(img|dsc|dcim|pxl|photo|image|screenshot|scan)[-_ ]?\d+$',
      caseSensitive: false,
    ).hasMatch(base);
    if (!looksGeneric && base.length >= 5) score += 2;

    final folder = photo.relativeFolder.trim().toLowerCase();
    if (folder.isNotEmpty) score += 1;
    if (folder.contains('downloads') ||
        folder.contains('temp') ||
        folder.contains('camera roll')) {
      score -= 1;
    }

    return score;
  }

  VaultPhoto _recommendedKeeper() {
    final ranked = List<VaultPhoto>.from(photos)
      ..sort((a, b) {
        final scoreCompare = _keeperScore(b).compareTo(_keeperScore(a));
        if (scoreCompare != 0) return scoreCompare;

        final folderCompare = b.relativeFolder.length.compareTo(
          a.relativeFolder.length,
        );
        if (folderCompare != 0) return folderCompare;

        final nameCompare = b.fileName.length.compareTo(a.fileName.length);
        if (nameCompare != 0) return nameCompare;

        return a.filePath.toLowerCase().compareTo(b.filePath.toLowerCase());
      });
    return ranked.first;
  }

  List<String> _keeperReasons(VaultPhoto photo) {
    final metadata = catalogByPath[photo.filePath];
    final reasons = <String>[];

    if (metadata != null) {
      if (metadata.people.isNotEmpty) {
        reasons.add(
          '${metadata.people.length} identified '
          '${metadata.people.length == 1 ? 'person' : 'people'}',
        );
      }
      if (metadata.tags.isNotEmpty) {
        reasons.add(
          '${metadata.tags.length} ${metadata.tags.length == 1 ? 'tag' : 'tags'}',
        );
      }
      if (metadata.approximateDate.trim().isNotEmpty) {
        reasons.add('has a date');
      }
      if (metadata.location.trim().isNotEmpty) {
        reasons.add('has a location');
      }
      if (metadata.description.trim().isNotEmpty) {
        reasons.add('has a description');
      }
      if (metadata.notes.trim().isNotEmpty) {
        reasons.add('has notes');
      }
    }

    final base = path.basenameWithoutExtension(photo.fileName);
    final generic = RegExp(
      r'^(img|dsc|dcim|pxl|photo|image|screenshot|scan)[-_ ]?\d+$',
      caseSensitive: false,
    ).hasMatch(base);
    if (!generic && base.trim().length >= 5) {
      reasons.add('more descriptive filename');
    }

    if (photo.relativeFolder.trim().isNotEmpty) {
      reasons.add('stored in ${photo.relativeFolder}');
    }

    if (reasons.isEmpty) {
      reasons.add('no stronger cataloged copy was found');
    }

    return reasons.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final first = photos.first;
    final recommended = _recommendedKeeper();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Duplicate Group $number • ${photos.length} identical files • '
              '${_formatBytes(first.fileSize)} each',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.recommend_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Heirloom Atlas recommends keeping '
                        '"${recommended.fileName}" because '
                        '${_keeperReasons(recommended).join(', ')}.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  final file = File(photo.filePath);
                  final isRecommended = photo.filePath == recommended.filePath;
                  return SizedBox(
                    width: 245,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: file.existsSync()
                                    ? Image.file(
                                        file,
                                        fit: BoxFit.contain,
                                        cacheWidth: 450,
                                      )
                                    : const Center(
                                        child: Icon(
                                          Icons.image_not_supported_outlined,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            if (isRecommended) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Recommended to keep',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              photo.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              photo.relativeFolder.isEmpty
                                  ? 'Pictures'
                                  : photo.relativeFolder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: photos.length <= 1
                                        ? null
                                        : () async {
                                            final others = photos
                                                .where(
                                                  (p) =>
                                                      p.filePath !=
                                                      photo.filePath,
                                                )
                                                .toList();
                                            for (final other in others) {
                                              await onMergeKeep(photo, other);
                                            }
                                          },
                                    child: const Text('Keep This'),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'Remove this copy',
                                  onPressed: () => onRemove(photo),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhotoCropPreset { original, square, fourThree, sixteenNine }

class _PreviousPhotoIntent extends Intent {
  const _PreviousPhotoIntent();
}

class _NextPhotoIntent extends Intent {
  const _NextPhotoIntent();
}

class _PhotoEditorDialog extends StatefulWidget {
  const _PhotoEditorDialog({required this.photo});

  final VaultPhoto photo;

  @override
  State<_PhotoEditorDialog> createState() => _PhotoEditorDialogState();
}

class _PhotoEditorDialogState extends State<_PhotoEditorDialog> {
  static const Color _navy = Color(0xFF071A2B);
  static const Color _navySoft = Color(0xFF102A40);
  static const Color _gold = Color(0xFFB99A5E);
  static const Color _cream = Color(0xFFF2E7CF);

  int _quarterTurns = 0;
  double _straighten = 0;
  double _brightness = 0;
  double _contrast = 0;
  _PhotoCropPreset _cropPreset = _PhotoCropPreset.original;
  Rect? _freeformCrop;
  bool _freeformCropMode = false;
  Offset? _cropDragStart;
  bool _saving = false;

  bool get _hasEdits =>
      _quarterTurns != 0 ||
      _straighten.abs() > .01 ||
      _brightness.abs() > .01 ||
      _contrast.abs() > .01 ||
      _cropPreset != _PhotoCropPreset.original ||
      _freeformCrop != null;

  double? get _cropRatio {
    switch (_cropPreset) {
      case _PhotoCropPreset.original:
        return null;
      case _PhotoCropPreset.square:
        return 1;
      case _PhotoCropPreset.fourThree:
        return 4 / 3;
      case _PhotoCropPreset.sixteenNine:
        return 16 / 9;
    }
  }

  void _reset() {
    setState(() {
      _quarterTurns = 0;
      _straighten = 0;
      _brightness = 0;
      _contrast = 0;
      _cropPreset = _PhotoCropPreset.original;
      _freeformCrop = null;
      _freeformCropMode = false;
      _cropDragStart = null;
    });
  }

  String _uniqueEditedPath(String extension) {
    final directory = path.dirname(widget.photo.filePath);
    final base = path.basenameWithoutExtension(widget.photo.filePath);
    var candidate = path.join(directory, '$base - Edited$extension');
    var counter = 2;
    while (File(candidate).existsSync()) {
      candidate = path.join(directory, '$base - Edited $counter$extension');
      counter++;
    }
    return candidate;
  }

  img.Image _centerCrop(img.Image image, double targetRatio) {
    final currentRatio = image.width / image.height;
    if ((currentRatio - targetRatio).abs() < .001) return image;

    if (currentRatio > targetRatio) {
      final newWidth = math.max(1, (image.height * targetRatio).round());
      final x = math.max(0, ((image.width - newWidth) / 2).round());
      return img.copyCrop(
        image,
        x: x,
        y: 0,
        width: newWidth,
        height: image.height,
      );
    }

    final newHeight = math.max(1, (image.width / targetRatio).round());
    final y = math.max(0, ((image.height - newHeight) / 2).round());
    return img.copyCrop(
      image,
      x: 0,
      y: y,
      width: image.width,
      height: newHeight,
    );
  }

  Future<String> _saveEditedCopy() async {
    final bytes = await File(widget.photo.filePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw StateError('This image format could not be edited.');
    }

    image = img.bakeOrientation(image);

    final normalizedTurns = ((_quarterTurns % 4) + 4) % 4;
    if (normalizedTurns != 0) {
      image = img.copyRotate(image, angle: normalizedTurns * 90);
    }

    if (_straighten.abs() > .01) {
      image = img.copyRotate(image, angle: _straighten);
    }

    final cropRatio = _cropRatio;
    if (cropRatio != null) {
      image = _centerCrop(image, cropRatio);
    }

    final freeformCrop = _freeformCrop;
    if (freeformCrop != null &&
        freeformCrop.width > .01 &&
        freeformCrop.height > .01) {
      final cropX = (freeformCrop.left.clamp(0.0, 1.0) * image.width).round();
      final cropY = (freeformCrop.top.clamp(0.0, 1.0) * image.height).round();
      final cropRight = (freeformCrop.right.clamp(0.0, 1.0) * image.width)
          .round();
      final cropBottom = (freeformCrop.bottom.clamp(0.0, 1.0) * image.height)
          .round();
      final cropWidth = math.max(1, cropRight - cropX);
      final cropHeight = math.max(1, cropBottom - cropY);
      image = img.copyCrop(
        image,
        x: cropX,
        y: cropY,
        width: math.min(cropWidth, image.width - cropX),
        height: math.min(cropHeight, image.height - cropY),
      );
    }

    if (_brightness.abs() > .01 || _contrast.abs() > .01) {
      image = img.adjustColor(
        image,
        brightness: 1 + (_brightness / 100),
        contrast: 1 + (_contrast / 100),
      );
    }

    final sourceExt = path.extension(widget.photo.filePath).toLowerCase();
    final usePng = sourceExt == '.png';
    final outputExt = usePng ? '.png' : '.jpg';
    final outputPath = _uniqueEditedPath(outputExt);

    final encoded = usePng
        ? img.encodePng(image)
        : img.encodeJpg(image, quality: 95);

    await File(outputPath).writeAsBytes(encoded, flush: true);
    return outputPath;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final outputPath = await _saveEditedCopy();
      if (!mounted) return;
      Navigator.of(context).pop(outputPath);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save edited photo: $error')),
      );
    }
  }

  Widget _cropButton(_PhotoCropPreset preset, String label) {
    final selected = _cropPreset == preset;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() {
        _cropPreset = preset;
        _freeformCrop = null;
        _freeformCropMode = false;
      }),
      selectedColor: _gold.withValues(alpha: .24),
      side: BorderSide(color: selected ? _gold : _gold.withValues(alpha: .35)),
      labelStyle: TextStyle(
        color: selected ? _cream : _cream.withValues(alpha: .78),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: _navySoft,
      checkmarkColor: _gold,
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String Function(double)? valueLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _cream,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              valueLabel?.call(value) ?? value.toStringAsFixed(0),
              style: TextStyle(
                color: _cream.withValues(alpha: .72),
                fontSize: 12,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: _gold,
          inactiveColor: _gold.withValues(alpha: .20),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _preview() {
    Widget image = Image.file(
      File(widget.photo.filePath),
      fit: _cropRatio == null ? BoxFit.contain : BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_outlined, color: _cream, size: 72),
      ),
    );

    final brightnessOffset = _brightness * 2.0;
    final contrastFactor = 1 + (_contrast / 100);
    final translate = 128 * (1 - contrastFactor) + brightnessOffset;

    image = ColorFiltered(
      colorFilter: ColorFilter.matrix([
        contrastFactor,
        0,
        0,
        0,
        translate,
        0,
        contrastFactor,
        0,
        0,
        translate,
        0,
        0,
        contrastFactor,
        0,
        translate,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: image,
    );

    image = Transform.rotate(
      angle: (_quarterTurns * math.pi / 2) + (_straighten * math.pi / 180),
      child: image,
    );

    final cropRatio = _cropRatio;
    if (cropRatio != null) {
      image = AspectRatio(
        aspectRatio: cropRatio,
        child: ClipRect(child: image),
      );
    }

    return Container(
      color: Colors.black.withValues(alpha: .35),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final previewRect = Rect.fromLTWH(
              0,
              0,
              constraints.maxWidth,
              constraints.maxHeight,
            );

            Offset normalized(Offset local) => Offset(
              (local.dx / math.max(1.0, previewRect.width)).clamp(0.0, 1.0),
              (local.dy / math.max(1.0, previewRect.height)).clamp(0.0, 1.0),
            );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: !_freeformCropMode
                  ? null
                  : (details) {
                      final start = normalized(details.localPosition);
                      setState(() {
                        _cropDragStart = start;
                        _freeformCrop = Rect.fromPoints(start, start);
                      });
                    },
              onPanUpdate: !_freeformCropMode
                  ? null
                  : (details) {
                      final start = _cropDragStart;
                      if (start == null) return;
                      final current = normalized(details.localPosition);
                      setState(() {
                        _freeformCrop = Rect.fromLTRB(
                          math.min(start.dx, current.dx),
                          math.min(start.dy, current.dy),
                          math.max(start.dx, current.dx),
                          math.max(start.dy, current.dy),
                        );
                      });
                    },
              onPanEnd: !_freeformCropMode
                  ? null
                  : (_) => setState(() => _cropDragStart = null),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(child: image),
                  if (_freeformCropMode)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _FreeformCropPainter(
                            crop: _freeformCrop,
                            borderColor: _gold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _navy,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: BorderSide(color: _gold.withValues(alpha: .55)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 820),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 13, 10, 13),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _gold.withValues(alpha: .35)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_outlined, color: _gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Photo Editor',
                          style: TextStyle(
                            color: _cream,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          path.basename(widget.photo.filePath),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _cream.withValues(alpha: .68),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving || !_hasEdits ? null : _reset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset'),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: _cream),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 760;

                  final controls = SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rotate',
                          style: TextStyle(
                            color: _cream,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _quarterTurns--),
                                icon: const Icon(Icons.rotate_left),
                                label: const Text('Left'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _quarterTurns++),
                                icon: const Icon(Icons.rotate_right),
                                label: const Text('Right'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _slider(
                          label: 'Straighten',
                          value: _straighten,
                          min: -10,
                          max: 10,
                          divisions: 40,
                          onChanged: (value) =>
                              setState(() => _straighten = value),
                          valueLabel: (value) => '${value.toStringAsFixed(1)}°',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Crop',
                          style: TextStyle(
                            color: _cream,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _cropButton(_PhotoCropPreset.original, 'Original'),
                            _cropButton(_PhotoCropPreset.square, 'Square'),
                            _cropButton(_PhotoCropPreset.fourThree, '4:3'),
                            _cropButton(_PhotoCropPreset.sixteenNine, '16:9'),
                          ],
                        ),
                        const SizedBox(height: 9),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _cropPreset = _PhotoCropPreset.original;
                              _freeformCropMode = !_freeformCropMode;
                              if (!_freeformCropMode) {
                                _cropDragStart = null;
                              }
                            }),
                            icon: Icon(
                              _freeformCropMode
                                  ? Icons.crop_free
                                  : Icons.crop_outlined,
                            ),
                            label: Text(
                              _freeformCropMode
                                  ? 'Freeform Crop Active — Drag on Photo'
                                  : 'Freeform Crop',
                            ),
                          ),
                        ),
                        if (_freeformCrop != null) ...[
                          const SizedBox(height: 7),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: () => setState(() {
                                _freeformCrop = null;
                                _cropDragStart = null;
                              }),
                              icon: const Icon(Icons.clear),
                              label: const Text('Clear Freeform Crop'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _slider(
                          label: 'Brightness',
                          value: _brightness,
                          min: -40,
                          max: 40,
                          divisions: 80,
                          onChanged: (value) =>
                              setState(() => _brightness = value),
                        ),
                        const SizedBox(height: 8),
                        _slider(
                          label: 'Contrast',
                          value: _contrast,
                          min: -40,
                          max: 40,
                          divisions: 80,
                          onChanged: (value) =>
                              setState(() => _contrast = value),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _navySoft,
                            border: Border.all(
                              color: _gold.withValues(alpha: .22),
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                color: _gold,
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Archival safety: Save creates a new edited '
                                  'copy beside the original. The original file '
                                  'is never overwritten.',
                                  style: TextStyle(
                                    color: _cream.withValues(alpha: .78),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        Expanded(flex: 5, child: _preview()),
                        SizedBox(height: 300, child: controls),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 7, child: _preview()),
                      Container(
                        width: 330,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: _gold.withValues(alpha: .25),
                            ),
                          ),
                        ),
                        child: controls,
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: _gold.withValues(alpha: .35)),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _hasEdits
                        ? 'Edited copy will be saved next to the original.'
                        : 'Make an adjustment to create an edited copy.',
                    style: TextStyle(
                      color: _cream.withValues(alpha: .66),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving || !_hasEdits ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save Edited Copy'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreeformCropPainter extends CustomPainter {
  const _FreeformCropPainter({required this.crop, required this.borderColor});

  final Rect? crop;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final crop = this.crop;
    if (crop == null || crop.width <= 0 || crop.height <= 0) {
      final guidePaint = Paint()
        ..color = borderColor.withValues(alpha: .72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final inset = Rect.fromLTWH(
        size.width * .12,
        size.height * .12,
        size.width * .76,
        size.height * .76,
      );
      canvas.drawRect(inset, guidePaint);
      return;
    }

    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );

    final shade = Paint()..color = Colors.black.withValues(alpha: .48);
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRect(rect);
    final shaded = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(shaded, shade);

    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, border);

    final grid = Paint()
      ..color = borderColor.withValues(alpha: .58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (var i = 1; i <= 2; i++) {
      final x = rect.left + (rect.width * i / 3);
      final y = rect.top + (rect.height * i / 3);
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    final handle = Paint()..color = borderColor;
    const radius = 3.5;
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(point, radius, handle);
    }
  }

  @override
  bool shouldRepaint(covariant _FreeformCropPainter oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.borderColor != borderColor;
}

class _PhotoSourceBrandIcon extends StatelessWidget {
  final String sourceType;
  final String? displayName;
  final double size;

  const _PhotoSourceBrandIcon({
    required this.sourceType,
    this.displayName,
    this.size = 24,
  });

  String get _resolvedType {
    final type = sourceType.trim().toLowerCase();
    if (type.isNotEmpty && type != 'folder') return type;

    final name = (displayName ?? '').toLowerCase();
    if (name.contains('onedrive')) return 'onedrive';
    if (name.contains('google')) return 'google_drive';
    if (name.contains('icloud')) return 'icloud';
    return type;
  }

  @override
  Widget build(BuildContext context) {
    switch (_resolvedType) {
      case 'google_drive':
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _GoogleDriveMarkPainter()),
        );
      case 'onedrive':
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _OneDriveMarkPainter()),
        );
      case 'icloud':
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _ICloudMarkPainter()),
        );
      default:
        return Icon(
          Icons.folder_outlined,
          size: size,
          color: Theme.of(context).colorScheme.primary,
        );
    }
  }
}

class _OneDriveMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final darkBlue = Paint()..color = const Color(0xFF0364B8);
    final midBlue = Paint()..color = const Color(0xFF0078D4);
    final lightBlue = Paint()..color = const Color(0xFF28A8EA);

    canvas.drawCircle(const Offset(9.0, 12.1), 4.7, darkBlue);
    canvas.drawCircle(const Offset(13.2, 9.2), 5.6, midBlue);
    canvas.drawCircle(const Offset(17.0, 13.0), 4.8, lightBlue);

    final base = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4.2, 11.5, 15.6, 7.2),
      const Radius.circular(3.6),
    );
    canvas.drawRRect(base, lightBlue);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OneDriveMarkPainter oldDelegate) => false;
}

class _ICloudMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final cloudPaint = Paint()..color = const Color(0xFFF4F7FB);
    final outlinePaint = Paint()
      ..color = const Color(0xFFB9C8D8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final path = Path()
      ..moveTo(6.2, 17.7)
      ..cubicTo(4.3, 17.7, 2.8, 16.2, 2.8, 14.3)
      ..cubicTo(2.8, 12.5, 4.1, 11.0, 5.8, 10.7)
      ..cubicTo(6.5, 7.7, 9.0, 5.6, 12.0, 5.6)
      ..cubicTo(14.6, 5.6, 16.8, 7.1, 17.8, 9.4)
      ..cubicTo(20.0, 9.7, 21.7, 11.5, 21.7, 13.8)
      ..cubicTo(21.7, 16.0, 19.9, 17.7, 17.7, 17.7)
      ..close();

    canvas.drawPath(path, cloudPaint);
    canvas.drawPath(path, outlinePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ICloudMarkPainter oldDelegate) => false;
}

class _GoogleDriveMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final green = Paint()..color = const Color(0xFF0F9D58);
    final yellow = Paint()..color = const Color(0xFFF4B400);
    final blue = Paint()..color = const Color(0xFF4285F4);

    final greenPath = Path()
      ..moveTo(8.1, 2.0)
      ..lineTo(12.0, 2.0)
      ..lineTo(19.2, 14.4)
      ..lineTo(15.2, 14.4)
      ..close();

    final yellowPath = Path()
      ..moveTo(8.1, 2.0)
      ..lineTo(2.2, 12.2)
      ..lineTo(4.2, 15.6)
      ..lineTo(10.1, 5.4)
      ..close();

    final bluePath = Path()
      ..moveTo(4.2, 15.6)
      ..lineTo(15.2, 15.6)
      ..lineTo(19.2, 14.4)
      ..lineTo(21.8, 18.8)
      ..lineTo(6.1, 18.8)
      ..close();

    canvas.drawPath(greenPath, green);
    canvas.drawPath(yellowPath, yellow);
    canvas.drawPath(bluePath, blue);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleDriveMarkPainter oldDelegate) => false;
}

class _PhotoMetaPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool missing;

  const _PhotoMetaPill({
    required this.icon,
    required this.text,
    this.missing = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: missing
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: missing ? scheme.onSurfaceVariant : scheme.primary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: missing ? FontWeight.w500 : FontWeight.w700,
                color: missing ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoFolder {
  final String path;
  final String name;
  final int photoCount;

  const _PhotoFolder({
    required this.path,
    required this.name,
    required this.photoCount,
  });
}
