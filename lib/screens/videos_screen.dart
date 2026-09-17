import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../database/database_helper.dart';

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  static const Color _navy = Color(0xFF061A2C);
  static const Color _panel = Color(0xFF0A243C);
  static const Color _gold = Color(0xFFC9A45C);
  static const Color _cream = Color(0xFFF3E8D0);
  static const Color _muted = Color(0xFFA8B5BE);

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mov',
    '.m4v',
    '.avi',
    '.wmv',
    '.mkv',
    '.webm',
    '.mpeg',
    '.mpg',
    '.3gp',
  };

  List<Map<String, Object?>> _mediaSources = const [];
  List<_VideoFile> _videos = const [];
  final Map<String, _VideoMetadata> _metadata = {};
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  String _query = '';
  String _sortMode = 'date_newest';

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
      await _ensureVideoMetadataTable();
      await _loadVideoMetadata();
      final sources = await _databaseHelper.getPhotoSources();

      if (!mounted) return;
      setState(() {
        _mediaSources = sources;
        _loading = false;
      });

      await _scanSources();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _ensureVideoMetadataTable() async {
    final db = await _databaseHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_catalog_metadata (
        file_path TEXT PRIMARY KEY,
        people_json TEXT NOT NULL DEFAULT '[]',
        tags_json TEXT NOT NULL DEFAULT '[]',
        approximate_date TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<void> _loadVideoMetadata() async {
    final db = await _databaseHelper.database;
    final rows = await db.query('video_catalog_metadata');

    _metadata
      ..clear()
      ..addEntries(
        rows.map((row) {
          final metadata = _VideoMetadata.fromMap(row);
          return MapEntry(metadata.filePath, metadata);
        }),
      );
  }

  Future<void> _saveVideoMetadata(_VideoMetadata metadata) async {
    final db = await _databaseHelper.database;
    await db.rawInsert(
      '''
      INSERT OR REPLACE INTO video_catalog_metadata
      (file_path, people_json, tags_json, approximate_date, location, description, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        metadata.filePath,
        jsonEncode(metadata.people),
        jsonEncode(metadata.tags),
        metadata.approximateDate,
        metadata.location,
        metadata.description,
        metadata.notes,
      ],
    );

    if (!mounted) return;
    setState(() => _metadata[metadata.filePath] = metadata);
  }

  Future<void> _scanSources() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    final found = <String, _VideoFile>{};

    try {
      for (final source in _mediaSources) {
        final rootPath = (source['root_path'] as String? ?? '').trim();
        final sourceName =
            (source['display_name'] as String? ?? 'Media Source').trim();
        if (rootPath.isEmpty) continue;

        final root = Directory(rootPath);
        if (!await root.exists()) continue;

        try {
          await for (final entity in root.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is! File) continue;

            final extension = path.extension(entity.path).toLowerCase();
            if (!_videoExtensions.contains(extension)) continue;

            try {
              final stat = await entity.stat();
              final relative = path.relative(entity.path, from: root.path);
              final folder =
                  path.dirname(relative) == '.' ? '' : path.dirname(relative);

              found[entity.path.toLowerCase()] = _VideoFile(
                filePath: entity.path,
                fileName: path.basename(entity.path),
                extension: extension,
                fileSize: stat.size,
                modified: stat.modified,
                sourceName: sourceName.isEmpty ? 'Media Source' : sourceName,
                sourceRoot: root.path,
                relativeFolder: folder,
              );
            } catch (_) {}
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _videos = found.values.toList();
        _scanning = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _addMediaSource() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder containing photos or videos',
    );
    if (selected == null || selected.trim().isEmpty) return;

    final alreadyExists = _mediaSources.any((source) {
      final root = (source['root_path'] as String? ?? '').trim();
      return _samePath(root, selected);
    });

    if (!alreadyExists) {
      await _databaseHelper.addPhotoSource(
        sourceType: _sourceTypeForPath(selected),
        displayName: _displayNameForPath(selected),
        rootPath: selected,
      );
    }

    final sources = await _databaseHelper.getPhotoSources();
    if (!mounted) return;
    setState(() => _mediaSources = sources);
    await _scanSources();
  }

  String _sourceTypeForPath(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('onedrive')) return 'onedrive';
    if (lower.contains('google drive')) return 'google_drive';
    if (lower.contains('icloud')) return 'icloud';
    return 'local_folder';
  }

  String _displayNameForPath(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('onedrive')) return 'OneDrive';
    if (lower.contains('google drive')) return 'Google Drive';
    if (lower.contains('icloud')) return 'iCloud';

    final base = path.basename(value.trim());
    return base.isEmpty ? 'Media Folder' : base;
  }

  bool _samePath(String a, String b) {
    if (a.trim().isEmpty || b.trim().isEmpty) return false;
    try {
      return path.equals(path.normalize(a), path.normalize(b));
    } catch (_) {
      return a.toLowerCase() == b.toLowerCase();
    }
  }

  Future<void> _openVideo(_VideoFile video) async {
    if (!await File(video.filePath).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The original video could not be found.')),
      );
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.start(
          'cmd',
          ['/c', 'start', '', video.filePath],
          runInShell: true,
        );
      } else if (Platform.isMacOS) {
        await Process.start('open', [video.filePath]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [video.filePath]);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open video: $error')),
      );
    }
  }

  Future<void> _editMetadata(_VideoFile video) async {
    final current =
        _metadata[video.filePath] ?? _VideoMetadata(filePath: video.filePath);

    final people = TextEditingController(text: current.people.join(', '));
    final date = TextEditingController(text: current.approximateDate);
    final location = TextEditingController(text: current.location);
    final description = TextEditingController(text: current.description);
    final tags = TextEditingController(text: current.tags.join(', '));
    final notes = TextEditingController(text: current.notes);

    final save = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Edit Video Details'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        video.fileName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: people,
                      decoration: const InputDecoration(
                        labelText: 'People',
                        hintText: 'Separate names with commas',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: date,
                      decoration: const InputDecoration(
                        labelText: 'Date / Approximate Date',
                        hintText: 'Example: Summer 1998',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: location,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: description,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: tags,
                      decoration: const InputDecoration(
                        labelText: 'Tags',
                        hintText: 'Separate tags with commas',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'For beta, video details are stored in Heirloom Atlas. '
                        'The original video file is not modified.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    if (save) {
      List<String> split(String value) => value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();

      await _saveVideoMetadata(
        _VideoMetadata(
          filePath: video.filePath,
          people: split(people.text),
          tags: split(tags.text),
          approximateDate: date.text.trim(),
          location: location.text.trim(),
          description: description.text.trim(),
          notes: notes.text.trim(),
        ),
      );
    }

    people.dispose();
    date.dispose();
    location.dispose();
    description.dispose();
    tags.dispose();
    notes.dispose();
  }

  List<_VideoFile> get _visibleVideos {
    final q = _query.trim().toLowerCase();

    final result = _videos.where((video) {
      final metadata = _metadata[video.filePath];
      final searchable = [
        video.fileName,
        video.relativeFolder,
        video.sourceName,
        metadata?.approximateDate ?? '',
        metadata?.location ?? '',
        metadata?.description ?? '',
        metadata?.notes ?? '',
        ...(metadata?.people ?? const <String>[]),
        ...(metadata?.tags ?? const <String>[]),
      ].join(' ').toLowerCase();

      return q.isEmpty || searchable.contains(q);
    }).toList();

    switch (_sortMode) {
      case 'date_oldest':
        result.sort((a, b) => a.modified.compareTo(b.modified));
        break;
      case 'name_az':
        result.sort(
          (a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
        );
        break;
      case 'name_za':
        result.sort(
          (a, b) => b.fileName.toLowerCase().compareTo(a.fileName.toLowerCase()),
        );
        break;
      case 'size_largest':
        result.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
      default:
        result.sort((a, b) => b.modified.compareTo(a.modified));
    }

    return result;
  }

  Map<String, int> get _sourceCounts {
    final result = <String, int>{};

    for (final source in _mediaSources) {
      final root = (source['root_path'] as String? ?? '').trim();
      if (root.isNotEmpty) result[root] = 0;
    }

    for (final video in _videos) {
      result[video.sourceRoot] = (result[video.sourceRoot] ?? 0) + 1;
    }

    return result;
  }

  int get _catalogedCount => _videos
      .where((video) => _metadata[video.filePath]?.hasAny ?? false)
      .length;

  int get _peopleCount => _videos
      .where((video) => _metadata[video.filePath]?.people.isNotEmpty ?? false)
      .length;

  int get _dateCount => _videos
      .where(
        (video) =>
            _metadata[video.filePath]?.approximateDate.isNotEmpty ?? false,
      )
      .length;

  int get _locationCount => _videos
      .where((video) => _metadata[video.filePath]?.location.isNotEmpty ?? false)
      .length;

  int get _descriptionCount => _videos
      .where(
        (video) => _metadata[video.filePath]?.description.isNotEmpty ?? false,
      )
      .length;

  int _percent(int value) =>
      _videos.isEmpty ? 0 : ((value / _videos.length) * 100).round();

  @override
  Widget build(BuildContext context) {
    final visibleVideos = _visibleVideos;

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Videos',
          style: TextStyle(color: _cream, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Rescan videos',
            onPressed: _scanning ? null : _scanSources,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_scanning) const LinearProgressIndicator(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildBanner(),
                      const SizedBox(height: 14),
                      if (_error != null) ...[
                        _buildError(),
                        const SizedBox(height: 14),
                      ],
                      _buildHealth(),
                      const SizedBox(height: 14),
                      _buildSearchBar(),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 310,
                            child: Column(
                              children: [
                                _buildSourcesPanel(),
                                const SizedBox(height: 12),
                                _buildReviewPanel(),
                                const SizedBox(height: 12),
                                _buildQuickActionsPanel(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildLibraryPanel(visibleVideos),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildSafetyNote(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBanner() {
    return Container(
      height: 205,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withValues(alpha: .55)),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF071B2D),
            Color(0xFF123B55),
            Color(0xFF071A2B),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 55,
            top: 22,
            child: Transform.rotate(
              angle: -0.06,
              child: Icon(
                Icons.movie_filter_outlined,
                size: 150,
                color: _cream.withValues(alpha: .10),
              ),
            ),
          ),
          Positioned(
            right: 210,
            bottom: -15,
            child: Icon(
              Icons.video_camera_back_outlined,
              size: 115,
              color: _gold.withValues(alpha: .13),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 8,
            child: Container(color: _gold.withValues(alpha: .65)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 28, 28, 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VIDEOS',
                        style: TextStyle(
                          color: _cream,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Preserve the moments in motion.',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const SizedBox(
                        width: 610,
                        child: Text(
                          'Organize family videos, home movies, and recorded '
                          'memories alongside the people, places, and stories '
                          'they belong to.',
                          style: TextStyle(
                            color: _cream,
                            height: 1.45,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(
                            Icons.folder_copy_outlined,
                            color: _gold,
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            '${_mediaSources.length} shared media sources',
                            style: const TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 150,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 17,
                  ),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: .68),
                    border: Border.all(
                      color: _gold.withValues(alpha: .40),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_videos.length}',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'VIDEOS FOUND',
                        style: TextStyle(
                          color: _cream,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
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
    );
  }

  Widget _buildHealth() {
    Widget metric(String label, int value, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 92),
          decoration: BoxDecoration(
            color: _panel,
            border: Border.all(color: _gold.withValues(alpha: .23)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: _gold, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                '${_percent(value)}%',
                style: const TextStyle(
                  color: _gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF071D31),
        border: Border.all(color: _gold.withValues(alpha: .48)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          const Text(
            'VIDEO COLLECTION OVERVIEW & HEALTH',
            style: TextStyle(
              color: _cream,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: .65,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(minHeight: 92),
                  decoration: BoxDecoration(
                    color: _panel,
                    border: Border.all(
                      color: _gold.withValues(alpha: .23),
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.video_library_outlined,
                            color: _gold,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'COLLECTION',
                            style: TextStyle(
                              color: _cream,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${_videos.length}',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              metric('CATALOGED', _catalogedCount, Icons.fact_check_outlined),
              const SizedBox(width: 8),
              metric('PEOPLE', _peopleCount, Icons.people_outline),
              const SizedBox(width: 8),
              metric('DATES', _dateCount, Icons.event_outlined),
              const SizedBox(width: 8),
              metric('LOCATIONS', _locationCount, Icons.place_outlined),
              const SizedBox(width: 8),
              metric(
                'DESCRIPTIONS',
                _descriptionCount,
                Icons.description_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: _cream),
            decoration: InputDecoration(
              hintText:
                  'Search videos by filename, people, date, location, description, tags…',
              hintStyle: TextStyle(color: _cream.withValues(alpha: .46)),
              prefixIcon: const Icon(Icons.search, color: _gold),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: _panel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 185,
          child: DropdownButtonFormField<String>(
            initialValue: _sortMode,
            decoration: const InputDecoration(
              labelText: 'Sort',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'date_newest',
                child: Text('Newest first'),
              ),
              DropdownMenuItem(
                value: 'date_oldest',
                child: Text('Oldest first'),
              ),
              DropdownMenuItem(value: 'name_az', child: Text('Name A–Z')),
              DropdownMenuItem(value: 'name_za', child: Text('Name Z–A')),
              DropdownMenuItem(
                value: 'size_largest',
                child: Text('Largest first'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sortMode = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesPanel() {
    final counts = _sourceCounts;

    return _sidePanel(
      icon: Icons.folder_copy_outlined,
      title: 'MEDIA SOURCES',
      trailing: IconButton(
        tooltip: 'Add Media Source',
        onPressed: _addMediaSource,
        icon: const Icon(Icons.add, color: _gold),
      ),
      child: Column(
        children: [
          for (final source in _mediaSources)
            _sideRow(
              icon: Icons.folder_outlined,
              label:
                  (source['display_name'] as String? ?? 'Media Source').trim(),
              value:
                  '${counts[(source['root_path'] as String? ?? '').trim()] ?? 0}',
            ),
        ],
      ),
    );
  }

  Widget _buildReviewPanel() {
    return _sidePanel(
      icon: Icons.auto_awesome_outlined,
      title: 'REVIEW & ORGANIZE',
      child: Column(
        children: [
          _sideRow(
            icon: Icons.sell_outlined,
            label: 'Missing Metadata',
            value: '${_videos.length - _catalogedCount}',
          ),
          _sideRow(
            icon: Icons.person_outline,
            label: 'No People',
            value: '${_videos.length - _peopleCount}',
          ),
          _sideRow(
            icon: Icons.event_outlined,
            label: 'No Date',
            value: '${_videos.length - _dateCount}',
          ),
          _sideRow(
            icon: Icons.place_outlined,
            label: 'No Location',
            value: '${_videos.length - _locationCount}',
          ),
          _sideRow(
            icon: Icons.description_outlined,
            label: 'No Description',
            value: '${_videos.length - _descriptionCount}',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsPanel() {
    return _sidePanel(
      icon: Icons.bolt_outlined,
      title: 'QUICK ACTIONS',
      child: Column(
        children: [
          _sideRow(
            icon: Icons.refresh,
            label: 'Rescan Videos',
            onTap: _scanning ? null : _scanSources,
          ),
          _sideRow(
            icon: Icons.add_link_outlined,
            label: 'Add Media Source',
            onTap: _addMediaSource,
          ),
        ],
      ),
    );
  }

  Widget _sidePanel({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _gold.withValues(alpha: .23)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: _gold, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _cream,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: .45,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  Widget _sideRow({
    required IconData icon,
    required String label,
    String? value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.5),
        child: Row(
          children: [
            Icon(icon, color: _gold.withValues(alpha: .80), size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _cream, fontSize: 12),
              ),
            ),
            if (value != null)
              Text(
                value,
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: _gold, size: 17),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryPanel(List<_VideoFile> videos) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _gold.withValues(alpha: .23)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'VIDEO LIBRARY',
                style: TextStyle(
                  color: _cream,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .45,
                ),
              ),
              const Spacer(),
              Text(
                '${videos.length} videos',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_videos.isEmpty && !_scanning)
            _buildEmptyState()
          else
            _buildVideoGrid(videos),
        ],
      ),
    );
  }

  Widget _buildVideoGrid(List<_VideoFile> videos) {
    if (videos.isEmpty) return _buildNoMatches();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 760
                ? 3
                : 2;
        const spacing = 11.0;
        final width =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final video in videos)
              SizedBox(
                width: width,
                height: 230,
                child: Material(
                  color: _navy.withValues(alpha: .60),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                    side: BorderSide(
                      color: _gold.withValues(alpha: .20),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => _openVideo(video),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _videoPreview(video)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      video.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _cream,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _metadata[video.filePath]?.summary
                                                  .isNotEmpty ==
                                              true
                                          ? _metadata[video.filePath]!.summary
                                          : '${_formatDate(video.modified)} • ${_formatBytes(video.fileSize)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            _metadata[video.filePath]?.hasAny ==
                                                    true
                                                ? _gold
                                                : _muted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit Details',
                                onPressed: () => _editMetadata(video),
                                icon: Icon(
                                  Icons.edit_note_outlined,
                                  color:
                                      _metadata[video.filePath]?.hasAny == true
                                          ? _gold
                                          : _muted,
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
          ],
        );
      },
    );
  }

  Widget _videoPreview(_VideoFile video) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _videoPlaceholder(),
        Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: .80),
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withValues(alpha: .75)),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: _cream,
              size: 28,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: .86),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              video.extension.replaceFirst('.', '').toUpperCase(),
              style: const TextStyle(
                color: _gold,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _videoPlaceholder() {
    return Container(
      color: _navy.withValues(alpha: .74),
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        color: _gold.withValues(alpha: .50),
        size: 58,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.video_library_outlined, color: _gold, size: 52),
          const SizedBox(height: 12),
          const Text(
            'No videos found yet',
            style: TextStyle(
              color: _cream,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Add any folder containing videos. It can also contain photos.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _addMediaSource,
            icon: const Icon(Icons.add_link_outlined),
            label: const Text('Add Media Source'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatches() {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Center(
        child: Text(
          'No videos match this search.',
          style: TextStyle(color: _muted),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: Theme.of(context).colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(_error!, style: const TextStyle(color: _cream)),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: .58),
        border: Border.all(color: _gold.withValues(alpha: .18)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: _gold, size: 19),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your collection is yours. Not ours. Videos stay in their '
              'original folders. Heirloom Atlas catalogs them in place.',
              style: TextStyle(color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year}';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }
}

class _VideoFile {
  final String filePath;
  final String fileName;
  final String extension;
  final int fileSize;
  final DateTime modified;
  final String sourceName;
  final String sourceRoot;
  final String relativeFolder;

  const _VideoFile({
    required this.filePath,
    required this.fileName,
    required this.extension,
    required this.fileSize,
    required this.modified,
    required this.sourceName,
    required this.sourceRoot,
    required this.relativeFolder,
  });
}

class _VideoMetadata {
  final String filePath;
  final List<String> people;
  final List<String> tags;
  final String approximateDate;
  final String location;
  final String description;
  final String notes;

  const _VideoMetadata({
    required this.filePath,
    this.people = const [],
    this.tags = const [],
    this.approximateDate = '',
    this.location = '',
    this.description = '',
    this.notes = '',
  });

  bool get hasAny =>
      people.isNotEmpty ||
      tags.isNotEmpty ||
      approximateDate.isNotEmpty ||
      location.isNotEmpty ||
      description.isNotEmpty ||
      notes.isNotEmpty;

  String get summary {
    final parts = <String>[
      if (approximateDate.isNotEmpty) approximateDate,
      if (location.isNotEmpty) location,
      if (people.isNotEmpty)
        '${people.length} ${people.length == 1 ? 'person' : 'people'}',
    ];
    return parts.join(' • ');
  }

  factory _VideoMetadata.fromMap(Map<String, Object?> map) {
    List<String> readList(Object? value) {
      if (value is! String || value.trim().isEmpty) return const [];
      try {
        return (jsonDecode(value) as List)
            .map((item) => item.toString())
            .toList();
      } catch (_) {
        return const [];
      }
    }

    return _VideoMetadata(
      filePath: map['file_path'] as String? ?? '',
      people: readList(map['people_json']),
      tags: readList(map['tags_json']),
      approximateDate: map['approximate_date'] as String? ?? '',
      location: map['location'] as String? ?? '',
      description: map['description'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
    );
  }
}
