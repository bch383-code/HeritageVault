import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import '../database/database_helper.dart';
import '../models/vault_photo.dart';
import '../models/photo_catalog_metadata.dart';
import 'photo_detail_screen.dart';
import 'photo_batch_edit_screen.dart';
import 'face_scan_screen.dart';
import 'known_people_screen.dart';
import 'whole_library_face_scan_screen.dart';
import 'unidentified_faces_screen.dart';
import 'photo_metadata_import_screen.dart';

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

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

  String _currentFolder = '';
  bool _selectionMode = false;
  final Set<String> _selectedPaths = <String>{};

  final TextEditingController _searchController = TextEditingController();
  Map<String, PhotoCatalogMetadata> _catalogByPath =
      <String, PhotoCatalogMetadata>{};
  String _quickFilter = 'All';

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

  Future<void> _load() async {
    try {
      final libraryPath =
          await _databaseHelper.getSetting('photo_library_path');
      final photos = await _databaseHelper.getIndexedPhotos();
      final catalogRecords =
          await _databaseHelper.getAllPhotoCatalogMetadata();

      final catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };

      if (!mounted) return;

      setState(() {
        _libraryPath = libraryPath;
        _photos = photos;
        _catalogByPath = catalogByPath;
        _loading = false;
      });
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

  Future<void> _scanLibrary() async {
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
      final indexed = <VaultPhoto>[];

      await for (final entity in root.list(recursive: true, followLinks: false)) {
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
        final folderCompare = a.relativeFolder
            .toLowerCase()
            .compareTo(b.relativeFolder.toLowerCase());
        if (folderCompare != 0) return folderCompare;
        return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
      });

      await _databaseHelper.replaceIndexedPhotos(indexed);
      final photos = await _databaseHelper.getIndexedPhotos();

      if (!mounted) return;
      setState(() {
        _photos = photos;
        _scanning = false;
        _currentFolder = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _scanning = false;
      });
    }
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

    final folders = counts.entries
        .map(
          (entry) => _PhotoFolder(
            path: entry.key,
            name: path.basename(entry.key),
            photoCount: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoDetailScreen(
          photos: navigationPhotos,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
        ),
      ),
    );

    final catalogRecords =
        await _databaseHelper.getAllPhotoCatalogMetadata();
    if (!mounted) return;

    setState(() {
      _catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };
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
        builder: (context) => PhotoBatchEditScreen(
          photos: selected,
        ),
      ),
    );

    if (!mounted) return;

    if (changed == true) {
      final catalogRecords =
          await _databaseHelper.getAllPhotoCatalogMetadata();

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
      MaterialPageRoute(
        builder: (context) => FaceScanScreen(photos: selected),
      ),
    );

    if (!mounted) return;

    final catalogRecords =
        await _databaseHelper.getAllPhotoCatalogMetadata();

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
        builder: (context) => FaceScanScreen(
          photos: folderPhotos,
        ),
      ),
    );

    if (!mounted) return;

    final catalogRecords =
        await _databaseHelper.getAllPhotoCatalogMetadata();

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
        builder: (context) => WholeLibraryFaceScanScreen(
          photos: _photos,
        ),
      ),
    );

    if (!mounted) return;

    final catalogRecords =
        await _databaseHelper.getAllPhotoCatalogMetadata();

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
        builder: (context) => PhotoMetadataImportScreen(
          photos: _photos,
        ),
      ),
    );

    if (!mounted) return;

    final catalogRecords =
        await _databaseHelper.getAllPhotoCatalogMetadata();

    setState(() {
      _catalogByPath = <String, PhotoCatalogMetadata>{
        for (final record in catalogRecords) record.filePath: record,
      };
    });
  }

  Future<void> _findPossibleDuplicates() async {
    if (_possibleDuplicateScanning || _duplicateScanning || _photos.length < 2) {
      return;
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
            _dbInt(row['modified_milliseconds']) == photo.modifiedMilliseconds &&
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
        if (generation != _possibleDuplicateScanGeneration) return;

        final end = (start + batchSize < pending.length)
            ? start + batchSize
            : pending.length;
        final batch = pending.sublist(start, end);
        final input = batch.map((photo) => <String, Object?>{
          'file_path': photo.filePath,
          'file_size': photo.fileSize,
          'modified_milliseconds': photo.modifiedMilliseconds,
        }).toList();

        final results = await compute(_fingerprintPhotoBatch, input);

        if (generation != _possibleDuplicateScanGeneration) return;

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
        if (!mounted || generation != _possibleDuplicateScanGeneration) return;
        setState(() => _duplicateScanCurrent = completed);
        await Future<void>.delayed(Duration.zero);
      }

      await _databaseHelper.deletePhotoFingerprintsNotIn(
        _photos.map((photo) => photo.filePath),
      );

      if (!mounted || generation != _possibleDuplicateScanGeneration) return;

      final matches = await compute(_compareFingerprintRecords, records);

      if (!mounted || generation != _possibleDuplicateScanGeneration) return;

      final pairs = <_PossibleDuplicatePair>[];
      for (final match in matches) {
        final first = photoByPath[match['first_path'] as String? ?? ''];
        final second = photoByPath[match['second_path'] as String? ?? ''];
        if (first == null || second == null) continue;
        pairs.add(_PossibleDuplicatePair(
          first: first,
          second: second,
          similarity: _dbInt(match['similarity']),
        ));
      }

      setState(() {
        _possibleDuplicateScanning = false;
        _duplicateScanCurrent = _duplicateScanTotal;
      });

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _PossibleDuplicatesDialog(
          pairs: pairs,
          resultsLimited: pairs.length >= 200,
        ),
      );
    } catch (error) {
      if (!mounted || generation != _possibleDuplicateScanGeneration) return;
      setState(() => _possibleDuplicateScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not scan for possible duplicates: $error')),
      );
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
        content: Text('Photo analysis canceled. Completed fingerprints were saved.'),
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
              final candidateBytes =
                  await File(candidate.filePath).readAsBytes();

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

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _ExactDuplicatesDialog(
          groups: duplicates,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _duplicateScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not scan for duplicates: $error'),
        ),
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

    switch (_quickFilter) {
      case 'Uncataloged':
        return !_hasAnyCatalogData(metadata);
      case 'No People':
        return metadata == null || metadata.people.isEmpty;
      case 'No Date':
        return metadata == null || metadata.approximateDate.trim().isEmpty;
      case 'No Location':
        return metadata == null || metadata.location.trim().isEmpty;
      case 'No Description':
        return metadata == null || metadata.description.trim().isEmpty;
      default:
        return true;
    }
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
                onPressed: () =>
                    _toggleSelectAll(_visiblePhotosForSelection),
                icon: Icon(
                  _visiblePhotosForSelection.isNotEmpty &&
                          _visiblePhotosForSelection.every(
                            (photo) =>
                                _selectedPaths.contains(photo.filePath),
                          )
                      ? Icons.deselect
                      : Icons.select_all,
                ),
                label: Text(
                  _visiblePhotosForSelection.isNotEmpty &&
                          _visiblePhotosForSelection.every(
                            (photo) =>
                                _selectedPaths.contains(photo.filePath),
                          )
                      ? 'Clear All'
                      : 'Select All',
                ),
              ),
            if (_selectionMode)
              const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _toggleSelectionMode,
              icon: Icon(
                _selectionMode ? Icons.close : Icons.check_box_outlined,
              ),
              label: Text(_selectionMode ? 'Cancel' : 'Select'),
            ),
            IconButton(
              tooltip: 'Find Possible Duplicates',
              onPressed: _selectionMode ||
                      _possibleDuplicateScanning ||
                      _duplicateScanning
                  ? null
                  : _findPossibleDuplicates,
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
              onPressed: _selectionMode ||
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
              onPressed: _selectionMode
                  ? null
                  : _openMetadataImport,
              icon: const Icon(Icons.file_download_outlined),
            ),
            IconButton(
              tooltip: 'Scan Entire Photo Library for Faces',
              onPressed: _selectionMode
                  ? null
                  : _openWholeLibraryFaceScan,
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
                          builder: (context) =>
                              const UnidentifiedFacesScreen(),
                        ),
                      );

                      if (!mounted) return;

                      final catalogRecords =
                          await _databaseHelper.getAllPhotoCatalogMetadata();
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

                      final catalogRecords =
                          await _databaseHelper.getAllPhotoCatalogMetadata();
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
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                _libraryPath!,
                                maxLines: 2,
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _scanning ? null : _chooseFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(
                      _libraryPath == null ? 'Choose Folder' : 'Change Folder',
                    ),
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
          if (_libraryPath != null)
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText:
                            'Search filename, person, tag, date, location, description...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final filter in const [
                            'All',
                            'Uncataloged',
                            'No People',
                            'No Date',
                            'No Location',
                            'No Description',
                          ])
                            FilterChip(
                              label: Text(filter),
                              selected: _quickFilter == filter,
                              onSelected: (_) {
                                setState(() => _quickFilter = filter);
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 8),
                            child: Text(
                              '${_filteredPhotos.length} matching photos',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
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

    return Column(
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
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
                      final target =
                          path.joinAll(segments.take(i + 1).toList());
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
        subtitle: Text('${_filteredPhotos.length} matching photos across all folders'),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'All Photos',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${_filteredPhotos.length} matching photos',
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
                        itemBuilder: (context, index) =>
                            _photoTile(_filteredPhotos[index], _filteredPhotos),
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
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
      final value =
          ((hashes[i] >> (chunk * 16)) & BigInt.from(0xFFFF)).toInt();
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

    final similarity =
        (100 - (distance * 8) - (colorDistance ~/ 12)).clamp(0, 99);
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

  const _PossibleDuplicatesDialog({
    required this.pairs,
    required this.resultsLimited,
  });

  @override
  State<_PossibleDuplicatesDialog> createState() =>
      _PossibleDuplicatesDialogState();
}

class _PossibleDuplicatesDialogState
    extends State<_PossibleDuplicatesDialog> {
  final Set<String> _dismissed = <String>{};

  String _pairKey(_PossibleDuplicatePair pair) =>
      '${pair.first.filePath}|${pair.second.filePath}';

  @override
  Widget build(BuildContext context) {
    final visible = widget.pairs
        .where((pair) => !_dismissed.contains(_pairKey(pair)))
        .toList();

    return Dialog(
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
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
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
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library_outlined, size: 64),
                            const SizedBox(height: 14),
                            Text(
                              widget.pairs.isEmpty
                                  ? 'No possible duplicates found'
                                  : 'Review complete',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.pairs.isEmpty
                                  ? 'This visual scan looks for photos that '
                                      'remain similar after resizing or '
                                      're-encoding.'
                                  : 'You reviewed all possible matches in '
                                      'this scan.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(18),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final pair = visible[index];
                        return _PossibleDuplicatePairCard(
                          pair: pair,
                          onNotMatch: () {
                            setState(() {
                              _dismissed.add(_pairKey(pair));
                            });
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Possible means visually similar, not identical. '
                      'Nothing is deleted, moved, or merged.',
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
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

class _PossibleDuplicatePairCard extends StatelessWidget {
  final _PossibleDuplicatePair pair;
  final VoidCallback onNotMatch;

  const _PossibleDuplicatePairCard({
    required this.pair,
    required this.onNotMatch,
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
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onNotMatch,
                  icon: const Icon(Icons.close),
                  label: const Text('Not a Match'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _PossibleDuplicatePhoto(photo: pair.first)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 80),
                  child: Icon(Icons.compare_arrows),
                ),
                Expanded(child: _PossibleDuplicatePhoto(photo: pair.second)),
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

  const _PossibleDuplicatePhoto({
    required this.photo,
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
              ? Image.file(
                  file,
                  fit: BoxFit.contain,
                  cacheWidth: 600,
                )
              : const Center(
                  child: Icon(Icons.image_not_supported_outlined),
                ),
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
            photo.relativeFolder.isEmpty
                ? 'Pictures'
                : photo.relativeFolder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ExactDuplicatesDialog extends StatelessWidget {
  final List<List<VaultPhoto>> groups;

  const _ExactDuplicatesDialog({
    required this.groups,
  });

  int get _duplicateCopies =>
      groups.fold<int>(0, (sum, group) => sum + group.length - 1);

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exact Duplicate Photos',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          groups.isEmpty
                              ? 'No exact duplicate image files were found.'
                              : '${groups.length} duplicate '
                                  '${groups.length == 1 ? 'group' : 'groups'} • '
                                  '$_duplicateCopies extra '
                                  '${_duplicateCopies == 1 ? 'copy' : 'copies'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 64,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No exact duplicates found',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'This scan compares the actual file contents, '
                              'so renamed copies are still detected.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(18),
                      itemCount: groups.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        return _ExactDuplicateGroupCard(
                          number: index + 1,
                          photos: groups[index],
                        );
                      },
                    ),
            ),
            if (groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Review only for now — Heirloom Atlas will not delete '
                        'or move any files from this screen.',
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
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

class _ExactDuplicateGroupCard extends StatelessWidget {
  final int number;
  final List<VaultPhoto> photos;

  const _ExactDuplicateGroupCard({
    required this.number,
    required this.photos,
  });

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes bytes';
  }

  @override
  Widget build(BuildContext context) {
    final first = photos.first;

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
                  'Duplicate Group $number',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Text(
                  '${photos.length} identical files • '
                  '${_formatBytes(first.fileSize)} each',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  final file = File(photo.filePath);

                  return SizedBox(
                    width: 230,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
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
                            const SizedBox(height: 8),
                            Text(
                              index == 0 ? 'Copy 1' : 'Copy ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              photo.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Tooltip(
                              message: photo.filePath,
                              child: Text(
                                photo.relativeFolder.isEmpty
                                    ? 'Pictures'
                                    : photo.relativeFolder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
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
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
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
            color: missing
                ? scheme.onSurfaceVariant
                : scheme.primary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: missing
                    ? FontWeight.w500
                    : FontWeight.w700,
                color: missing
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
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
