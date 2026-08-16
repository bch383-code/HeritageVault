import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../database/database_helper.dart';
import '../models/vault_photo.dart';
import '../models/photo_catalog_metadata.dart';
import 'photo_detail_screen.dart';
import 'photo_batch_edit_screen.dart';
import 'face_scan_screen.dart';

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
        return metadata == null ||
            (metadata.people.isEmpty &&
                metadata.tags.isEmpty &&
                metadata.approximateDate.trim().isEmpty &&
                metadata.location.trim().isEmpty &&
                metadata.description.trim().isEmpty &&
                metadata.notes.trim().isEmpty);
      case 'No People':
        return metadata == null || metadata.people.isEmpty;
      case 'No Date':
        return metadata == null || metadata.approximateDate.trim().isEmpty;
      case 'No Location':
        return metadata == null || metadata.location.trim().isEmpty;
      default:
        return true;
    }
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
                  'Choose the Pictures folder inside OneDrive. Heritage Vault '
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
                Text(
                  _currentFolder.isEmpty
                      ? 'Photos in Pictures'
                      : 'Photos in ${path.basename(_currentFolder)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
                            child: Text(
                              'All Photos',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
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
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1,
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
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) => _photoTile(photos[index], photos),
    );
  }

  Widget _photoTile(VaultPhoto photo, List<VaultPhoto> navigationPhotos) {
    final file = File(photo.filePath);
    final selected = _selectedPaths.contains(photo.filePath);

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
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: file.existsSync()
                        ? Image.file(
                            file,
                            fit: BoxFit.contain,
                            cacheWidth: 500,
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
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    photo.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
