import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/vault_photo.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/detected_face_record.dart';
import '../services/photo_metadata_import_service.dart';
import '../services/face_recognition_service.dart';
import 'photo_detail_screen.dart';
import 'photo_batch_edit_screen.dart';
import 'face_scan_screen.dart';
import 'known_people_screen.dart';
import 'whole_library_face_scan_screen.dart';
import 'unidentified_faces_screen.dart';
import 'photo_metadata_import_screen.dart';
import 'photo_analysis_settings_screen.dart';
import '../services/photo_metadata_write_service.dart';
import '../services/photo_metadata_writer.dart';
import '../services/photo_metadata_reader.dart';

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

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

  String? _libraryPath;
  List<VaultPhoto> _photos = const [];
  bool _loading = true;
  bool _scanning = false;
  bool _duplicateScanning = false;
  bool _possibleDuplicateScanning = false;
  int _duplicateScanCurrent = 0;
  int _duplicateScanTotal = 0;
  int _possibleDuplicateScanGeneration = 0;
  String? _error;
  int? _possibleDuplicateCount;
  int _unidentifiedFaceCount = 0;
  int _duplicateTrashCount = 0;

  String _currentFolder = '';
  bool _selectionMode = false;
  final Set<String> _selectedPaths = <String>{};

  final TextEditingController _searchController = TextEditingController();
  Map<String, PhotoCatalogMetadata> _catalogByPath =
      <String, PhotoCatalogMetadata>{};
  final Set<String> _quickFilters = <String>{};
  Set<String> _recentlyAddedPaths = <String>{};

  static const _extensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.tif',
    '.tiff',
    '.bmp',
    '.webp',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizerCounts() async {
    final duplicateValue = await _databaseHelper.getSetting(
      'photo_possible_duplicate_count',
    );
    final faceCount = await _databaseHelper.getUnconfirmedFaceCount();
    final trashEntries = await _getDuplicateTrashEntries();

    if (!mounted) return;

    setState(() {
      _possibleDuplicateCount = duplicateValue == null
          ? null
          : int.tryParse(duplicateValue);
      _unidentifiedFaceCount = faceCount;
      _duplicateTrashCount = trashEntries.length;
    });
  }

  Future<void> _load() async {
    try {
      final libraryPath = await _databaseHelper.getSetting(
        'photo_library_path',
      );
      final photos = await _databaseHelper.getIndexedPhotos();
      final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
      final recentSetting = await _databaseHelper.getSetting(
        'photo_recently_added_paths',
      );

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

      final catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };

      if (!mounted) return;

      setState(() {
        _libraryPath = libraryPath;
        _photos = photos;
        _catalogByPath = catalogByPath;
        _recentlyAddedPaths = recentlyAddedPaths;
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

  Future<void> _chooseFolder() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose your OneDrive Pictures folder',
    );
    if (selected == null || selected.trim().isEmpty) return;

    await _databaseHelper.setSetting('photo_library_path', selected);
    if (!mounted) return;

    setState(() {
      _libraryPath = selected;
      _currentFolder = '';
    });

    await _scanLibrary();
  }

  Future<void> _scanLibrary({bool runAutomaticIntake = true}) async {
    final rootPath = _libraryPath;
    if (rootPath == null || rootPath.isEmpty) return;

    final root = Directory(rootPath);
    if (!await root.exists()) {
      if (!mounted) return;
      setState(() => _error = 'The selected photo folder could not be found.');
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final previousPhotos = List<VaultPhoto>.from(_photos);
      final indexed = <VaultPhoto>[];

      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;

        final extension = path.extension(entity.path).toLowerCase();
        if (!_extensions.contains(extension)) continue;

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
        } catch (_) {
          // Skip individual files that cannot be read.
        }
      }

      indexed.sort((a, b) {
        final folderCompare = a.relativeFolder.toLowerCase().compareTo(
          b.relativeFolder.toLowerCase(),
        );
        if (folderCompare != 0) return folderCompare;
        return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
      });

      await _databaseHelper.replaceIndexedPhotos(indexed);
      final photos = await _databaseHelper.getIndexedPhotos();

      final previousPaths = previousPhotos
          .map((photo) => photo.filePath)
          .toSet();
      final newlyAddedPaths = previousPhotos.isEmpty
          ? <String>{}
          : photos
                .where((photo) => !previousPaths.contains(photo.filePath))
                .map((photo) => photo.filePath)
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
        if (newlyAddedPaths.isNotEmpty) {
          _recentlyAddedPaths = newlyAddedPaths;
        }
        _scanning = false;
        _currentFolder = '';
      });

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

                await _databaseHelper.reassignConfirmedFace(
                  faceId: faceId,
                  newPersonName: newName,
                );

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

                  await _databaseHelper.savePhotoCatalogMetadata(
                    PhotoCatalogMetadata(
                      filePath: metadata.filePath,
                      people: updatedPeople.toList(),
                      tags: metadata.tags,
                      approximateDate: metadata.approximateDate,
                      location: metadata.location,
                      description: metadata.description,
                      notes: metadata.notes,
                    ),
                  );
                }

                setDialogState(() {});
              }

              final file = File(currentPhoto.filePath);

              return Dialog(
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
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Previous photo',
                              onPressed: previewIndex > 0
                                  ? () {
                                      previewIndex--;
                                      setDialogState(() {});
                                    }
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
                                  previewIndex < navigationPhotos.length - 1
                                  ? () {
                                      previewIndex++;
                                      setDialogState(() {});
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                            const SizedBox(width: 8),
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
                                        child: Text('Original file not found.'),
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
                                        if (metadata.people.isNotEmpty) ...[
                                          Text(
                                            'People',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: metadata.people
                                                .map(
                                                  (name) =>
                                                      Chip(label: Text(name)),
                                                )
                                                .toList(),
                                          ),
                                          const SizedBox(height: 18),
                                        ],
                                        Text(
                                          'Faces in this Photo',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (confirmedFaces.isEmpty)
                                          const Text(
                                            'No confirmed faces in this photo.',
                                          )
                                        else
                                          ...confirmedFaces.map((face) {
                                            final thumb = File(
                                              face.thumbnailPath,
                                            );
                                            return Card(
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 24,
                                                      backgroundImage:
                                                          thumb.existsSync()
                                                          ? FileImage(thumb)
                                                          : null,
                                                      child: thumb.existsSync()
                                                          ? null
                                                          : const Icon(
                                                              Icons
                                                                  .person_outline,
                                                            ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        face.personName,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuButton<String>(
                                                      tooltip: 'Face actions',
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
                                                          value: 'unidentify',
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
                                        if (allFaces.any(
                                          (face) => !face.confirmed,
                                        )) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            '${allFaces.where((face) => !face.confirmed).length} '
                                            'unidentified '
                                            '${allFaces.where((face) => !face.confirmed).length == 1 ? 'face' : 'faces'} '
                                            'detected in this photo.',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                        const SizedBox(height: 22),
                                        Text(
                                          'Original file',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 5),
                                        SelectableText(
                                          currentPhoto.filePath,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 22),
                                        FilledButton.tonalIcon(
                                          onPressed: () async {
                                            Navigator.pop(dialogContext);
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    PhotoDetailScreen(
                                                      photos: navigationPhotos,
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
                                            'Edit Full Details',
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

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedPaths.clear();
      }
    });
  }

  void _toggleSelected(VaultPhoto photo) {
    setState(() {
      if (_selectedPaths.contains(photo.filePath)) {
        _selectedPaths.remove(photo.filePath);
      } else {
        _selectedPaths.add(photo.filePath);
      }
    });
  }

  void _toggleSelectAll(List<VaultPhoto> visiblePhotos) {
    final visiblePaths = visiblePhotos.map((photo) => photo.filePath).toSet();
    final allVisibleSelected =
        visiblePaths.isNotEmpty && visiblePaths.every(_selectedPaths.contains);

    setState(() {
      if (allVisibleSelected) {
        _selectedPaths.removeAll(visiblePaths);
      } else {
        _selectedPaths.addAll(visiblePaths);
      }
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
    }
  }

  Future<void> _scanSelectedFaces() async {
    final selected = _photos
        .where((photo) => _selectedPaths.contains(photo.filePath))
        .toList();

    if (selected.isEmpty) return;

    if (selected.length > 250) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Large face scan'),
          content: Text(
            'You selected ${selected.length} photos. Smaller groups are '
            'easier to review while facial recognition is new. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FaceScanScreen(photos: selected)),
    );

    if (!mounted) return;

    final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();

    setState(() {
      _catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };
      _selectedPaths.clear();
      _selectionMode = false;
    });
  }

  Future<void> _scanCurrentFolderFaces() async {
    final folderPhotos = _filteredPhotosInCurrentFolder;

    if (folderPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There are no matching photos in this folder to scan.'),
        ),
      );
      return;
    }

    if (folderPhotos.length > 250) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Large folder face scan'),
          content: Text(
            'This folder contains ${folderPhotos.length} matching photos. '
            'For now, smaller scans are easier to review. Continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceScanScreen(photos: folderPhotos),
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
                padding: const EdgeInsets.all(14),
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
                    const SizedBox(height: 14),
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
      notes: combineNotes(keepMeta?.notes, removeMeta?.notes),
    );
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
              (file) =>
                  path.basename(file.path) != 'duplicate_trash_manifest.json',
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

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refresh() async {
            entries = await _getDuplicateTrashEntries();
            if (dialogContext.mounted) {
              setDialogState(() {});
            }
            if (mounted) {
              setState(() => _duplicateTrashCount = entries.length);
            }
          }

          return Dialog(
            child: SizedBox(
              width: 920,
              height: 680,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.restore_from_trash_outlined),
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
                                '${entries.length} recoverable '
                                '${entries.length == 1 ? 'photo' : 'photos'}',
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
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(child: Text('Duplicate Trash is empty.'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final trashPath =
                                  entry['trash_path'] as String? ?? '';
                              final originalPath =
                                  entry['original_path'] as String? ?? '';
                              return Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: SizedBox(
                                    width: 58,
                                    height: 58,
                                    child: File(trashPath).existsSync()
                                        ? Image.file(
                                            File(trashPath),
                                            fit: BoxFit.cover,
                                            cacheWidth: 120,
                                          )
                                        : const Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                  ),
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
                                            await _scanLibrary(
                                              runAutomaticIntake: false,
                                            );
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
                                          if (deleted) await refresh();
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
                    padding: const EdgeInsets.all(14),
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
      ),
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
    await _loadOrganizerCounts();
    return true;
  }

  Future<bool> _mergeDuplicateAndKeep(
    VaultPhoto keep,
    VaultPhoto remove,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Merge duplicate records?'),
            content: Text(
              'Heirloom Atlas will keep "${keep.fileName}", combine useful '
              'People, Tags, Date, Location, Description, and Notes from both '
              'records, then move "${remove.fileName}" to Duplicate Trash.\n\n'
              'The removed photo file will not be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.merge_type),
                label: const Text('Merge & Keep'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return false;

    final merged = _mergedDuplicateMetadata(keep, remove);
    await _databaseHelper.savePhotoCatalogMetadata(merged);

    await _movePhotoFileToDuplicateTrash(remove);

    _catalogByPath[keep.filePath] = merged;
    await _loadOrganizerCounts();
    return true;
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
      final photoByPath = <String, VaultPhoto>{
        for (final photo in _photos) photo.filePath: photo,
      };
      final records = <Map<String, Object?>>[];
      final pending = <VaultPhoto>[];

      for (final photo in _photos) {
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
      var completed = _photos.length - pending.length;

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
        _photos.map((photo) => photo.filePath),
      );

      if (!mounted || generation != _possibleDuplicateScanGeneration) {
        return null;
      }

      final matches = await compute(_compareFingerprintRecords, records);

      if (!mounted || generation != _possibleDuplicateScanGeneration) {
        return null;
      }

      final pairs = <_PossibleDuplicatePair>[];
      for (final match in matches) {
        final first = photoByPath[match['first_path'] as String? ?? ''];
        final second = photoByPath[match['second_path'] as String? ?? ''];
        if (first == null || second == null) continue;
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
        SnackBar(
          content: Text('Could not scan for possible duplicates: $error'),
        ),
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

  bool _matchesSearch(VaultPhoto photo) {
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

  List<VaultPhoto> get _filteredPhotos =>
      _photos.where(_matchesSearch).toList();

  List<VaultPhoto> get _filteredPhotosInCurrentFolder {
    return _filteredPhotos
        .where((photo) => photo.relativeFolder == _currentFolder)
        .toList();
  }

  List<VaultPhoto> get _visiblePhotosForSelection {
    return _filteredPhotosInCurrentFolder;
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
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
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
                  child: Icon(icon, size: 17, color: scheme.onPrimaryContainer),
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
      color: scheme.surfaceContainer,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
        actions: [
          if (_libraryPath != null) ...[
            if (_selectionMode && _selectedPaths.isNotEmpty)
              FilledButton.icon(
                onPressed: _openBatchEditor,
                icon: const Icon(Icons.edit_note_outlined),
                label: Text('Batch Edit (${_selectedPaths.length})'),
              ),
            if (_selectionMode && _selectedPaths.isNotEmpty)
              const SizedBox(width: 8),
            if (_selectionMode && _selectedPaths.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _scanSelectedFaces,
                icon: const Icon(Icons.face_retouching_natural),
                label: Text('Scan Faces (${_selectedPaths.length})'),
              ),
            if (_selectionMode && _selectedPaths.isNotEmpty)
              const SizedBox(width: 8),
            if (_selectionMode)
              TextButton.icon(
                onPressed: () => _toggleSelectAll(_visiblePhotosForSelection),
                icon: Icon(
                  _visiblePhotosForSelection.isNotEmpty &&
                          _visiblePhotosForSelection.every(
                            (photo) => _selectedPaths.contains(photo.filePath),
                          )
                      ? Icons.deselect
                      : Icons.select_all,
                ),
                label: Text(
                  _visiblePhotosForSelection.isNotEmpty &&
                          _visiblePhotosForSelection.every(
                            (photo) => _selectedPaths.contains(photo.filePath),
                          )
                      ? 'Clear All'
                      : 'Select All',
                ),
              ),
            if (_selectionMode) const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _toggleSelectionMode,
              icon: Icon(
                _selectionMode ? Icons.close : Icons.check_box_outlined,
              ),
              label: Text(_selectionMode ? 'Cancel' : 'Select'),
            ),
            IconButton(
              tooltip: 'Find Possible Duplicates',
              onPressed:
                  _selectionMode ||
                      _possibleDuplicateScanning ||
                      _duplicateScanning
                  ? null
                  : () => _findPossibleDuplicates(),
              icon: _possibleDuplicateScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.compare_outlined),
            ),
            IconButton(
              tooltip: 'Find Exact Duplicates',
              onPressed:
                  _selectionMode ||
                      _duplicateScanning ||
                      _possibleDuplicateScanning
                  ? null
                  : _findExactDuplicates,
              icon: _duplicateScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.content_copy_outlined),
            ),
            IconButton(
              tooltip: 'Import Embedded Photo Metadata',
              onPressed: _selectionMode ? null : _openMetadataImport,
              icon: const Icon(Icons.file_download_outlined),
            ),
            IconButton(
              tooltip: 'Scan Entire Photo Library for Faces',
              onPressed: _selectionMode ? null : _openWholeLibraryFaceScan,
              icon: const Icon(Icons.manage_search),
            ),
            IconButton(
              tooltip: 'Unidentified Faces',
              onPressed: _selectionMode
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UnidentifiedFacesScreen(),
                        ),
                      );

                      if (!mounted) return;

                      final catalogRecords = await _databaseHelper
                          .getAllPhotoCatalogMetadata();
                      setState(() {
                        _catalogByPath = <String, PhotoCatalogMetadata>{
                          for (final record in catalogRecords)
                            record.filePath: record,
                        };
                      });
                    },
              icon: const Icon(Icons.person_search_outlined),
            ),
            IconButton(
              tooltip: 'Known People',
              onPressed: _selectionMode
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const KnownPeopleScreen(),
                        ),
                      );

                      if (!mounted) return;

                      final catalogRecords = await _databaseHelper
                          .getAllPhotoCatalogMetadata();
                      setState(() {
                        _catalogByPath = <String, PhotoCatalogMetadata>{
                          for (final record in catalogRecords)
                            record.filePath: record,
                        };
                      });
                    },
              icon: const Icon(Icons.people_alt_outlined),
            ),
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
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.cloud_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _libraryPath == null
                        ? const Text(
                            'No photo library selected. Choose your OneDrive Pictures folder.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Photo Library',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(_libraryPath!, maxLines: 2),
                            ],
                          ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _libraryPath == null
                        ? 'Choose Photo Library'
                        : 'Change Photo Library',
                    onPressed: _scanning ? null : _chooseFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ],
              ),
            ),
          ),
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
                          : (_duplicateScanCurrent / _duplicateScanTotal).clamp(
                              0.0,
                              1.0,
                            ),
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
          if (_libraryPath != null)
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText:
                                  'Search filename, person, tag, date, location...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_filteredPhotos.length} shown',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_libraryPath == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_library_outlined, size: 72),
                const SizedBox(height: 18),
                Text(
                  'Connect your photo library',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Choose the Pictures folder inside OneDrive. Heirloom Atlas '
                  'will index the photos in place and will not move, copy, '
                  'rename, or modify the originals.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _chooseFolder,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Choose OneDrive Pictures'),
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
        if (!_selectionMode) ...[
          SizedBox(width: 380, child: _buildPhotoOrganizerSidebar()),
          const VerticalDivider(width: 1),
        ],
        Expanded(
          child: Column(
            children: [
              _buildBreadcrumbs(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  children: [
                    if (_currentFolder.isEmpty) _buildAllPhotosCard(),
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
                          FilledButton.tonalIcon(
                            onPressed: _selectionMode
                                ? null
                                : _scanCurrentFolderFaces,
                            icon: const Icon(Icons.face_retouching_natural),
                            label: Text(
                              'Scan Faces in This Folder '
                              '(${_filteredPhotosInCurrentFolder.length})',
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
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

  Widget _photoTile(VaultPhoto photo, List<VaultPhoto> navigationPhotos) {
    final file = File(photo.filePath);
    final selected = _selectedPaths.contains(photo.filePath);
    final metadata = _catalogByPath[photo.filePath];
    final isUncataloged = !_hasAnyCatalogData(metadata);

    final peopleCount = metadata?.people.length ?? 0;
    final date = metadata?.approximateDate.trim() ?? '';
    final location = metadata?.location.trim() ?? '';
    final description = metadata?.description.trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _selectionMode
            ? () => _toggleSelected(photo)
            : () => _openPhoto(photo, navigationPhotos),
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
                      if (isUncataloged)
                        const Positioned(
                          left: 8,
                          top: 8,
                          child: _PhotoStatusBadge(),
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
                          _PhotoMetaPill(
                            icon: Icons.calendar_today_outlined,
                            text: date.isEmpty ? 'No date' : date,
                            missing: date.isEmpty,
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
            if (_selectionMode)
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

List<Map<String, Object?>> _compareFingerprintRecords(
  List<Map<String, Object?>> records,
) {
  if (records.length < 2) return const [];

  int asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  final hashes = records.map((record) {
    final value = record['hash_hex'] as String? ?? '0';
    return BigInt.parse(value.isEmpty ? '0' : value, radix: 16);
  }).toList();

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

  final matches = <Map<String, Object?>>[];
  for (final entry in overlaps.entries) {
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

    if (asInt(first['file_size']) == asInt(second['file_size']) &&
        hashes[i] == hashes[j] &&
        colorDistance == 0) {
      continue;
    }

    final similarity = (100 - (distance * 8) - (colorDistance ~/ 12)).clamp(
      0,
      99,
    );
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
  return matches.length > 200 ? matches.sublist(0, 200) : matches;
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

  const _PossibleDuplicatesDialog({
    required this.pairs,
    required this.resultsLimited,
    required this.onMoveToTrash,
    required this.onMergeAndKeep,
  });

  @override
  State<_PossibleDuplicatesDialog> createState() =>
      _PossibleDuplicatesDialogState();
}

class _PossibleDuplicatesDialogState extends State<_PossibleDuplicatesDialog> {
  final Set<String> _dismissed = <String>{};
  bool _changed = false;

  String _pairKey(_PossibleDuplicatePair pair) =>
      '${pair.first.filePath}|${pair.second.filePath}';

  void _finish() => Navigator.pop(context, _changed);

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
    final visible = widget.pairs
        .where((pair) => !_dismissed.contains(_pairKey(pair)))
        .toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: Dialog(
        child: SizedBox(
          width: 1150,
          height: 780,
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
                            'Possible Duplicate Photos',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.pairs.isEmpty
                                ? 'No visually similar photo pairs were found.'
                                : widget.resultsLimited
                                ? 'Showing the 200 strongest possible matches.'
                                : '${visible.length} possible '
                                      '${visible.length == 1 ? 'match' : 'matches'} '
                                      'to review',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
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
                child: visible.isEmpty
                    ? const Center(child: Text('Review complete'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(18),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final pair = visible[index];
                          return _PossibleDuplicatePairCard(
                            pair: pair,
                            onNotMatch: () {
                              setState(() {
                                _dismissed.add(_pairKey(pair));
                              });
                            },
                            onRemoveFirst: () =>
                                _removePairPhoto(pair, pair.first),
                            onRemoveSecond: () =>
                                _removePairPhoto(pair, pair.second),
                            onMergeKeepFirst: () =>
                                _merge(pair, pair.first, pair.second),
                            onMergeKeepSecond: () =>
                                _merge(pair, pair.second, pair.first),
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
  final VoidCallback onNotMatch;
  final VoidCallback onRemoveFirst;
  final VoidCallback onRemoveSecond;
  final VoidCallback onMergeKeepFirst;
  final VoidCallback onMergeKeepSecond;

  const _PossibleDuplicatePairCard({
    required this.pair,
    required this.onNotMatch,
    required this.onRemoveFirst,
    required this.onRemoveSecond,
    required this.onMergeKeepFirst,
    required this.onMergeKeepSecond,
  });

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
                  '${pair.similarity}% visual similarity',
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
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PossibleDuplicatePhoto(
                    photo: pair.first,
                    onRemove: onRemoveFirst,
                    onMergeKeep: onMergeKeepFirst,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 80),
                  child: Icon(Icons.compare_arrows),
                ),
                Expanded(
                  child: _PossibleDuplicatePhoto(
                    photo: pair.second,
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
  final VaultPhoto photo;
  final VoidCallback onRemove;
  final VoidCallback onMergeKeep;

  const _PossibleDuplicatePhoto({
    required this.photo,
    required this.onRemove,
    required this.onMergeKeep,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(photo.filePath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 230,
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: file.existsSync()
              ? Image.file(file, fit: BoxFit.contain, cacheWidth: 600)
              : const Center(child: Icon(Icons.image_not_supported_outlined)),
        ),
        const SizedBox(height: 8),
        Text(
          photo.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Tooltip(
          message: photo.filePath,
          child: Text(
            photo.relativeFolder.isEmpty ? 'Pictures' : photo.relativeFolder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              onPressed: onMergeKeep,
              icon: const Icon(Icons.merge_type, size: 18),
              label: const Text('Merge & Keep This'),
            ),
            OutlinedButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove This Copy'),
            ),
          ],
        ),
      ],
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

class _PhotoStatusBadge extends StatelessWidget {
  const _PhotoStatusBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Uncataloged',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
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
