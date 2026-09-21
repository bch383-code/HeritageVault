import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
  final Map<String, DateTime> _embeddedVideoDates = {};
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  String _query = '';
  String _sortMode = 'date_newest';
  String _folderVideoFilter = 'all';
  String? _selectedVideoSourceRoot;
  String _currentVideoFolder = '';
  bool _showAllVideosOnLanding = false;
  final Set<String> _selectedVideoPaths = <String>{};
  bool _videoSelectionMode = false;

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
      await _ensureVideoCatalogCacheTable();
      await _loadVideoMetadata();
      final sources = await _databaseHelper.getPhotoSources();
      final cached = await _loadCachedVideos(sources);

      if (!mounted) return;
      setState(() {
        _mediaSources = sources;
        _videos = cached.videos;
        _embeddedVideoDates
          ..clear()
          ..addAll(cached.embeddedDates);
        _loading = false;
      });

      // The cached catalog is already on screen. Reconcile the watched
      // folders asynchronously so opening Videos never waits on a full scan.
      unawaited(_scanSources());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _ensureVideoCatalogCacheTable() async {
    final db = await _databaseHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_catalog_cache (
        file_path TEXT PRIMARY KEY,
        file_name TEXT NOT NULL,
        extension TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        modified_ms INTEGER NOT NULL,
        source_name TEXT NOT NULL,
        source_root TEXT NOT NULL,
        relative_folder TEXT NOT NULL DEFAULT '',
        embedded_date_ms INTEGER
      )
    ''');
  }

  Future<_CachedVideoCatalog> _loadCachedVideos(
    List<Map<String, Object?>> sources,
  ) async {
    final db = await _databaseHelper.database;
    final rows = await db.query('video_catalog_cache');
    final configuredRoots = sources
        .map((source) => (source['root_path'] as String? ?? '').trim())
        .where((root) => root.isNotEmpty)
        .map((root) => path.normalize(root).toLowerCase())
        .toSet();

    final videos = <_VideoFile>[];
    final embeddedDates = <String, DateTime>{};

    for (final row in rows) {
      final sourceRoot = (row['source_root'] as String? ?? '').trim();
      if (configuredRoots.isNotEmpty &&
          !configuredRoots.contains(path.normalize(sourceRoot).toLowerCase())) {
        continue;
      }

      final filePath = (row['file_path'] as String? ?? '').trim();
      if (filePath.isEmpty) continue;
      final modifiedMs = (row['modified_ms'] as num?)?.toInt() ?? 0;
      final embeddedMs = (row['embedded_date_ms'] as num?)?.toInt();

      videos.add(
        _VideoFile(
          filePath: filePath,
          fileName: (row['file_name'] as String? ?? path.basename(filePath)),
          extension: (row['extension'] as String? ?? path.extension(filePath)),
          fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch(modifiedMs),
          sourceName: (row['source_name'] as String? ?? 'Media Source'),
          sourceRoot: sourceRoot,
          relativeFolder: (row['relative_folder'] as String? ?? ''),
        ),
      );

      if (embeddedMs != null) {
        embeddedDates[path.normalize(filePath).toLowerCase()] =
            DateTime.fromMillisecondsSinceEpoch(embeddedMs);
      }
    }

    return _CachedVideoCatalog(videos, embeddedDates);
  }

  Future<void> _saveVideoCatalogCache(
    Iterable<_VideoFile> videos,
    Map<String, DateTime> embeddedDates,
  ) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.delete('video_catalog_cache');
      final batch = txn.batch();
      for (final video in videos) {
        final key = path.normalize(video.filePath).toLowerCase();
        batch.insert('video_catalog_cache', {
          'file_path': video.filePath,
          'file_name': video.fileName,
          'extension': video.extension,
          'file_size': video.fileSize,
          'modified_ms': video.modified.millisecondsSinceEpoch,
          'source_name': video.sourceName,
          'source_root': video.sourceRoot,
          'relative_folder': video.relativeFolder,
          'embedded_date_ms': embeddedDates[key]?.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
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
    debugPrint('VIDEO META SAVE requested: ${metadata.filePath}');
    debugPrint('VIDEO META SAVE description: ${metadata.description}');

    final rowId = await db.insert('video_catalog_metadata', {
      'file_path': metadata.filePath,
      'people_json': jsonEncode(metadata.people),
      'tags_json': jsonEncode(metadata.tags),
      'approximate_date': metadata.approximateDate,
      'location': metadata.location,
      'description': metadata.description,
      'notes': metadata.notes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint('VIDEO META SAVE SQLite rowId: $rowId');

    final rows = await db.query(
      'video_catalog_metadata',
      where: 'file_path = ?',
      whereArgs: [metadata.filePath],
      limit: 1,
    );
    debugPrint('VIDEO META SAVE readback rows: ${rows.length}');
    if (rows.isNotEmpty) {
      debugPrint(
        'VIDEO META SAVE readback description: ${rows.first['description']}',
      );
    }
    if (rows.isEmpty) throw StateError('Video details were not saved.');

    final saved = _VideoMetadata.fromMap(rows.first);
    if (!mounted) return;
    setState(() => _metadata[metadata.filePath] = saved);
  }

  DateTime? _parseEmbeddedVideoDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.startsWith('0000:00:00')) return null;

    // ExifTool commonly returns YYYY:MM:DD HH:MM:SS with an optional zone.
    final match = RegExp(
      r'^(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value);
    if (match == null) return DateTime.tryParse(value);

    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    final hour = int.tryParse(match.group(4) ?? '') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '') ?? 0;
    final second = int.tryParse(match.group(6) ?? '') ?? 0;
    if (year == null || month == null || day == null) return null;
    try {
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _findVideoExifTool() async {
    final candidates = <String>[];
    if (Platform.isWindows) {
      final executableDirectory = File(Platform.resolvedExecutable).parent.path;
      candidates.add(
        path.join(executableDirectory, 'tools', 'exiftool', 'exiftool.exe'),
      );
      candidates.add(r'C:\ExifTool\exiftool.exe');
    }
    candidates.addAll(['exiftool.exe', 'exiftool']);

    for (final candidate in candidates) {
      try {
        if (path.isAbsolute(candidate) && !await File(candidate).exists()) {
          continue;
        }
        final result = await Process.run(candidate, [
          '-ver',
        ], runInShell: !path.isAbsolute(candidate));
        if (result.exitCode == 0) return candidate;
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, DateTime>> _readEmbeddedVideoDates(
    Iterable<_VideoFile> videos,
  ) async {
    final executable = await _findVideoExifTool();
    if (executable == null) return <String, DateTime>{};

    final result = <String, DateTime>{};
    final files = videos.map((video) => video.filePath).toList();

    // Keep command lines comfortably below Windows limits.
    const chunkSize = 40;
    for (var start = 0; start < files.length; start += chunkSize) {
      final end = math.min(start + chunkSize, files.length);
      final chunk = files.sublist(start, end);
      try {
        final process = await Process.run(executable, [
          '-j',
          '-SourceFile',
          '-DateTimeOriginal',
          '-MediaCreateDate',
          '-CreateDate',
          '-TrackCreateDate',
          ...chunk,
        ], runInShell: false).timeout(const Duration(seconds: 30));

        if (process.exitCode != 0) continue;
        final decoded = jsonDecode(process.stdout.toString());
        if (decoded is! List) continue;

        for (final item in decoded.whereType<Map>()) {
          final source = item['SourceFile']?.toString().trim() ?? '';
          if (source.isEmpty) continue;

          // Prefer the most capture-specific fields first.
          final candidates = [
            item['DateTimeOriginal'],
            item['MediaCreateDate'],
            item['CreateDate'],
            item['TrackCreateDate'],
          ];
          DateTime? date;
          for (final candidate in candidates) {
            date = _parseEmbeddedVideoDate(candidate?.toString() ?? '');
            if (date != null) break;
          }
          if (date != null) {
            result[path.normalize(source).toLowerCase()] = date;
          }
        }
      } catch (_) {
        // A metadata failure must never stop the video library from loading.
      }
    }
    return result;
  }

  DateTime? _videoDateForSort(_VideoFile video) {
    final manual = _metadata[video.filePath]?.approximateDate.trim() ?? '';
    if (manual.isNotEmpty) {
      final iso = RegExp(
        r'^(\d{4})(?:[-/](\d{1,2}))?(?:[-/](\d{1,2}))?',
      ).firstMatch(manual);
      if (iso != null) {
        final year = int.tryParse(iso.group(1) ?? '');
        final month = int.tryParse(iso.group(2) ?? '') ?? 1;
        final day = int.tryParse(iso.group(3) ?? '') ?? 1;
        if (year != null &&
            month >= 1 &&
            month <= 12 &&
            day >= 1 &&
            day <= 31) {
          return DateTime(year, month, day);
        }
      }
      final yearMatch = RegExp(
        r'\b(1[5-9]\d{2}|20\d{2}|21\d{2})\b',
      ).firstMatch(manual);
      final year = int.tryParse(yearMatch?.group(1) ?? '');
      if (year != null) return DateTime(year);
    }
    return _embeddedVideoDates[_videoSelectionKey(video)];
  }

  String _videoDisplayDate(_VideoFile video) {
    final manual = _metadata[video.filePath]?.approximateDate.trim() ?? '';
    if (manual.isNotEmpty) return manual;

    final embedded = _embeddedVideoDates[_videoSelectionKey(video)];
    if (embedded == null) return 'Unknown date';
    return '${embedded.month}/${embedded.day}/${embedded.year}';
  }

  Future<void> _scanSources() async {
    if (_scanning) return;

    if (mounted) {
      setState(() {
        _scanning = true;
        _error = null;
      });
    }

    final previousByPath = <String, _VideoFile>{
      for (final video in _videos) _videoSelectionKey(video): video,
    };
    final previousDates = Map<String, DateTime>.from(_embeddedVideoDates);
    final found = <String, _VideoFile>{};
    final changed = <_VideoFile>[];

    try {
      for (final source in _mediaSources) {
        final rootPath = (source['root_path'] as String? ?? '').trim();
        final sourceName = (source['display_name'] as String? ?? 'Media Source')
            .trim();
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
              final folder = path.dirname(relative) == '.'
                  ? ''
                  : path.dirname(relative);
              final video = _VideoFile(
                filePath: entity.path,
                fileName: path.basename(entity.path),
                extension: extension,
                fileSize: stat.size,
                modified: stat.modified,
                sourceName: sourceName.isEmpty ? 'Media Source' : sourceName,
                sourceRoot: root.path,
                relativeFolder: folder,
              );
              final key = _videoSelectionKey(video);
              found[key] = video;

              final old = previousByPath[key];
              if (old == null ||
                  old.fileSize != video.fileSize ||
                  old.modified.millisecondsSinceEpoch !=
                      video.modified.millisecondsSinceEpoch) {
                changed.add(video);
              }
            } catch (_) {}
          }
        } catch (_) {}

        // Let newly discovered files appear without waiting for every source.
        if (mounted) {
          final interimDates = <String, DateTime>{
            for (final entry in previousDates.entries)
              if (found.containsKey(entry.key)) entry.key: entry.value,
          };
          setState(() {
            _videos = found.values.toList();
            _embeddedVideoDates
              ..clear()
              ..addAll(interimDates);
          });
        }
      }

      final refreshedDates = await _readEmbeddedVideoDates(changed);
      final finalDates = <String, DateTime>{
        for (final entry in previousDates.entries)
          if (found.containsKey(entry.key)) entry.key: entry.value,
        ...refreshedDates,
      };

      await _saveVideoCatalogCache(found.values, finalDates);

      if (!mounted) return;
      setState(() {
        _videos = found.values.toList();
        _embeddedVideoDates
          ..clear()
          ..addAll(finalDates);
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
        await Process.start('cmd', [
          '/c',
          'start',
          '',
          video.filePath,
        ], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.start('open', [video.filePath]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [video.filePath]);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open video: $error')));
    }
  }

  Future<void> _editMetadata(_VideoFile video) async {
    final db = await _databaseHelper.database;
    final diagnosticRows = await db.query(
      'video_catalog_metadata',
      where: 'file_path = ?',
      whereArgs: [video.filePath],
      limit: 1,
    );

    debugPrint('VIDEO META OPEN path: ${video.filePath}');
    debugPrint('VIDEO META OPEN SQLite rows: ${diagnosticRows.length}');
    if (diagnosticRows.isNotEmpty) {
      debugPrint(
        'VIDEO META OPEN SQLite description: ${diagnosticRows.first['description']}',
      );
    }
    debugPrint(
      'VIDEO META OPEN memory description: ${_metadata[video.filePath]?.description ?? '<none>'}',
    );

    final current = diagnosticRows.isNotEmpty
        ? _VideoMetadata.fromMap(diagnosticRows.first)
        : (_metadata[video.filePath] ??
              _VideoMetadata(filePath: video.filePath));

    final result = await showDialog<_VideoMetadata>(
      context: context,
      builder: (dialogContext) =>
          _VideoMetadataDialog(video: video, current: current),
    );

    if (!mounted || result == null) return;
    await _saveVideoMetadata(result);
  }

  String _videoSelectionKey(_VideoFile video) =>
      path.normalize(video.filePath).toLowerCase();

  bool _isVideoSelected(_VideoFile video) =>
      _selectedVideoPaths.contains(_videoSelectionKey(video));

  void _toggleVideoSelection(_VideoFile video) {
    final key = _videoSelectionKey(video);
    setState(() {
      if (!_selectedVideoPaths.add(key)) {
        _selectedVideoPaths.remove(key);
      }
    });
  }

  void _selectAllVisibleVideos(List<_VideoFile> videos) {
    setState(() {
      _videoSelectionMode = true;
      for (final video in videos) {
        _selectedVideoPaths.add(_videoSelectionKey(video));
      }
    });
  }

  void _clearVideoSelection() {
    setState(() => _selectedVideoPaths.clear());
  }

  void _toggleVideoSelectionMode() {
    setState(() {
      _videoSelectionMode = !_videoSelectionMode;
      if (!_videoSelectionMode) {
        _selectedVideoPaths.clear();
      }
    });
  }

  Future<void> _moveSelectedVideosToTrash(
    List<_VideoFile> visibleVideos,
  ) async {
    final selected = visibleVideos.where(_isVideoSelected).toList();
    if (selected.isEmpty) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              'Move ${selected.length} '
              '${selected.length == 1 ? 'video' : 'videos'} to trash?',
            ),
            content: const Text(
              'The selected videos will be moved to Heirloom Atlas Video Trash. '
              'They can be restored later and will not be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Move to Video Trash'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    final moved = await _moveVideosToTrash(selected);
    if (!mounted) return;
    setState(() {
      _selectedVideoPaths.clear();
      _videoSelectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$moved ${moved == 1 ? 'video' : 'videos'} moved to Video Trash.',
        ),
      ),
    );
  }

  Future<void> _editSelectedVideoMetadata(
    List<_VideoFile> visibleVideos,
  ) async {
    final selected = visibleVideos
        .where(_isVideoSelected)
        .toList(growable: false);
    if (selected.isEmpty) return;

    final changes = await showDialog<_VideoBatchMetadataChanges>(
      context: context,
      builder: (dialogContext) =>
          _VideoBatchMetadataDialog(selectedCount: selected.length),
    );
    if (!mounted || changes == null || !changes.hasChanges) return;

    for (final video in selected) {
      final current =
          _metadata[video.filePath] ?? _VideoMetadata(filePath: video.filePath);
      final updated = _VideoMetadata(
        filePath: video.filePath,
        people: changes.people ?? current.people,
        tags: changes.tags ?? current.tags,
        approximateDate: changes.approximateDate ?? current.approximateDate,
        location: changes.location ?? current.location,
        description: changes.description ?? current.description,
        notes: changes.notes ?? current.notes,
      );
      await _saveVideoMetadata(updated);
    }

    if (!mounted) return;
    setState(() => _selectedVideoPaths.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Updated details for ${selected.length} '
          '${selected.length == 1 ? 'video' : 'videos'}.',
        ),
      ),
    );
  }

  List<_VideoFile> get _visibleVideos {
    final q = _query.trim().toLowerCase();

    final result = _videos.where((video) {
      if (_selectedVideoSourceRoot != null &&
          !_samePath(video.sourceRoot, _selectedVideoSourceRoot!)) {
        return false;
      }
      if (_currentVideoFolder.isNotEmpty) {
        final prefix = '$_currentVideoFolder${path.separator}';
        if (video.relativeFolder != _currentVideoFolder &&
            !video.relativeFolder.startsWith(prefix)) {
          return false;
        }
      }
      final metadata = _metadata[video.filePath];

      if (_currentVideoFolder.isNotEmpty) {
        switch (_folderVideoFilter) {
          case 'no_people':
            if (metadata != null && metadata.people.isNotEmpty) return false;
            break;
          case 'no_date':
            if ((metadata?.approximateDate.trim() ?? '').isNotEmpty ||
                _embeddedVideoDates.containsKey(_videoSelectionKey(video))) {
              return false;
            }
            break;
          case 'no_location':
            if ((metadata?.location.trim() ?? '').isNotEmpty) return false;
            break;
          case 'no_description':
            if ((metadata?.description.trim() ?? '').isNotEmpty) return false;
            break;
        }
      }
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
        result.sort((a, b) {
          final aDate = _videoDateForSort(a);
          final bDate = _videoDateForSort(b);
          if (aDate == null && bDate == null) {
            return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
          }
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        });
        break;
      case 'name_az':
        result.sort(
          (a, b) =>
              a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
        );
        break;
      case 'name_za':
        result.sort(
          (a, b) =>
              b.fileName.toLowerCase().compareTo(a.fileName.toLowerCase()),
        );
        break;
      case 'size_largest':
        result.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
      default:
        result.sort((a, b) {
          final aDate = _videoDateForSort(a);
          final bDate = _videoDateForSort(b);
          if (aDate == null && bDate == null) {
            return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
          }
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });
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

  bool _videoDuplicateScanCancelled = false;

  Future<bool> _videoFilesAreByteForByteEqual(
    String firstPath,
    String secondPath,
  ) async {
    final first = File(firstPath);
    final second = File(secondPath);
    if (!await first.exists() || !await second.exists()) return false;

    final firstStat = await first.stat();
    final secondStat = await second.stat();
    if (firstStat.size != secondStat.size) return false;

    final a = await first.open();
    final b = await second.open();
    const chunkSize = 1024 * 1024;

    try {
      while (true) {
        if (_videoDuplicateScanCancelled) return false;
        final left = await a.read(chunkSize);
        final right = await b.read(chunkSize);

        if (left.length != right.length) return false;
        if (left.isEmpty) return true;

        for (var i = 0; i < left.length; i++) {
          if (left[i] != right[i]) return false;
        }
      }
    } finally {
      await a.close();
      await b.close();
    }
  }

  Future<bool> _videoSamplesMatch(
    String firstPath,
    String secondPath,
    int fileSize,
  ) async {
    final a = await File(firstPath).open();
    final b = await File(secondPath).open();
    const sampleSize = 64 * 1024;
    final maxOffset = fileSize > sampleSize ? fileSize - sampleSize : 0;
    final offsets = <int>{0, maxOffset ~/ 2, maxOffset}.toList()..sort();
    try {
      for (final offset in offsets) {
        if (_videoDuplicateScanCancelled) return false;
        await a.setPosition(offset);
        await b.setPosition(offset);
        final left = await a.read(sampleSize);
        final right = await b.read(sampleSize);
        if (left.length != right.length) return false;
        for (var i = 0; i < left.length; i++) {
          if (left[i] != right[i]) return false;
        }
        await Future<void>.delayed(Duration.zero);
      }
      return true;
    } finally {
      await a.close();
      await b.close();
    }
  }

  Future<List<List<_VideoFile>>> _findExactVideoDuplicates() async {
    // Size is a fast first pass. Every reported match is then verified
    // by directly comparing the files byte-for-byte.
    final bySize = <int, List<_VideoFile>>{};
    for (final video in _videos) {
      bySize.putIfAbsent(video.fileSize, () => <_VideoFile>[]).add(video);
    }

    final result = <List<_VideoFile>>[];

    for (final candidates in bySize.values.where((g) => g.length > 1)) {
      if (_videoDuplicateScanCancelled) return result;
      final remaining = List<_VideoFile>.from(candidates);

      while (remaining.length > 1) {
        final keeper = remaining.removeAt(0);
        final group = <_VideoFile>[keeper];

        for (var i = remaining.length - 1; i >= 0; i--) {
          if (_videoDuplicateScanCancelled) return result;
          try {
            final candidate = remaining[i];
            final samplesMatch = await _videoSamplesMatch(
              keeper.filePath,
              candidate.filePath,
              keeper.fileSize,
            );
            if (!samplesMatch || _videoDuplicateScanCancelled) continue;
            if (await _videoFilesAreByteForByteEqual(
              keeper.filePath,
              candidate.filePath,
            )) {
              group.add(remaining.removeAt(i));
            }
          } catch (_) {
            // Unreadable/unavailable files are skipped safely.
          }
        }

        if (group.length > 1) result.add(group);
      }
    }

    return result;
  }

  Future<Directory> _videoTrashDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      path.join(docs.path, 'Heirloom Atlas', 'Video Trash'),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _videoTrashManifestFile() async {
    final dir = await _videoTrashDirectory();
    return File(path.join(dir.path, 'video_trash_manifest.json'));
  }

  Future<List<Map<String, dynamic>>> _readVideoTrashManifest() async {
    try {
      final file = await _videoTrashManifestFile();
      if (!await file.exists()) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _writeVideoTrashManifest(
    List<Map<String, dynamic>> entries,
  ) async {
    final file = await _videoTrashManifestFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entries),
      flush: true,
    );
  }

  Future<String> _uniqueTrashPath(Directory trash, String fileName) async {
    var candidate = path.join(trash.path, fileName);
    if (!await File(candidate).exists()) return candidate;
    final ext = path.extension(fileName);
    final stem = path.basenameWithoutExtension(fileName);
    var i = 2;
    while (await File(candidate).exists()) {
      candidate = path.join(trash.path, '$stem ($i)$ext');
      i++;
    }
    return candidate;
  }

  Future<int> _moveVideosToTrash(List<_VideoFile> videos) async {
    final trash = await _videoTrashDirectory();
    final manifest = await _readVideoTrashManifest();
    var moved = 0;
    final seen = <String>{};
    for (final video in videos) {
      final original = path.normalize(video.filePath);
      final key = original.toLowerCase();
      if (!seen.add(key)) continue;
      final source = File(original);
      if (!await source.exists()) continue;
      try {
        final destination = await _uniqueTrashPath(
          trash,
          path.basename(original),
        );
        await source.rename(destination);
        manifest.add({
          'originalPath': original,
          'trashPath': destination,
          'movedAt': DateTime.now().toIso8601String(),
        });
        moved++;
      } catch (_) {
        // Leave an unreadable/locked original untouched.
      }
    }
    await _writeVideoTrashManifest(manifest);
    if (moved > 0) await _scanSources();
    return moved;
  }

  Future<void> _openVideoTrash() async {
    var entries = await _readVideoTrashManifest();
    entries = entries.where((e) {
      final trashPath = e['trashPath']?.toString() ?? '';
      return trashPath.isNotEmpty && File(trashPath).existsSync();
    }).toList();
    await _writeVideoTrashManifest(entries);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _VideoTrashDialog(
        entries: entries,
        onRestore: _restoreVideoTrashEntry,
        onDeletePermanently: _deleteVideoTrashEntryPermanently,
      ),
    );
    if (mounted) await _scanSources();
  }

  Future<bool> _restoreVideoTrashEntry(Map<String, dynamic> entry) async {
    final trashPath = entry['trashPath']?.toString() ?? '';
    final originalPath = entry['originalPath']?.toString() ?? '';
    if (trashPath.isEmpty || originalPath.isEmpty) return false;
    final source = File(trashPath);
    if (!await source.exists()) return false;
    try {
      final parent = Directory(path.dirname(originalPath));
      if (!await parent.exists()) await parent.create(recursive: true);
      var destination = originalPath;
      if (await File(destination).exists()) {
        final ext = path.extension(originalPath);
        final stem = path.basenameWithoutExtension(originalPath);
        var i = 2;
        do {
          destination = path.join(parent.path, '$stem (Restored $i)$ext');
          i++;
        } while (await File(destination).exists());
      }
      await source.rename(destination);
      final manifest = await _readVideoTrashManifest();
      manifest.removeWhere((e) => e['trashPath']?.toString() == trashPath);
      await _writeVideoTrashManifest(manifest);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteVideoTrashEntryPermanently(
    Map<String, dynamic> entry,
  ) async {
    final trashPath = entry['trashPath']?.toString() ?? '';
    if (trashPath.isEmpty) return false;
    try {
      final file = File(trashPath);
      if (await file.exists()) await file.delete();
      final manifest = await _readVideoTrashManifest();
      manifest.removeWhere((e) => e['trashPath']?.toString() == trashPath);
      await _writeVideoTrashManifest(manifest);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _reviewExactVideoDuplicates() async {
    if (_videos.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough videos to check for duplicates.'),
        ),
      );
      return;
    }

    _videoDuplicateScanCancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VideoDuplicateScanningDialog(
        onCancel: () => _videoDuplicateScanCancelled = true,
      ),
    );

    final groups = await _findExactVideoDuplicates();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (_videoDuplicateScanCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video duplicate scan cancelled.')),
      );
      return;
    }

    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No byte-for-byte duplicate videos found.'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _ExactVideoDuplicatesDialog(
        groups: groups,
        onMoveToTrash: _moveVideosToTrash,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleVideos = _visibleVideos;

    return Scaffold(
      backgroundColor: _navy,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_scanning)
                  Container(
                    height: 24,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: const Text(
                      'Checking for video changes…',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    children: [
                      _buildBanner(),
                      if (_error != null) ...[
                        _buildError(),
                        const SizedBox(height: 10),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 980) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHealth(),
                                const SizedBox(height: 10),
                                _buildSearchBar(),
                              ],
                            );
                          }
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 7, child: _buildHealth()),
                                const SizedBox(width: 12),
                                Expanded(flex: 4, child: _buildSearchBar()),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 900) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSourcesPanel(),
                                const SizedBox(height: 10),
                                _buildReviewPanel(),
                                const SizedBox(height: 10),
                                _buildQuickActionsPanel(),
                                const SizedBox(height: 12),
                                _buildLibraryPanel(visibleVideos),
                              ],
                            );
                          }
                          const gap = 14.0;
                          final usableWidth = constraints.maxWidth - gap;
                          final leftWidth = usableWidth / 3;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: leftWidth,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildSourcesPanel(),
                                    const SizedBox(height: 10),
                                    _buildReviewPanel(),
                                    const SizedBox(height: 10),
                                    _buildQuickActionsPanel(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: gap),
                              Expanded(
                                child: _buildLibraryPanel(visibleVideos),
                              ),
                            ],
                          );
                        },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final heroHeight = constraints.maxWidth < 850 ? 150.0 : 210.0;
        return Container(
          height: heroHeight,
          margin: const EdgeInsets.fromLTRB(0, 12, 0, 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF071A2B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _gold.withValues(alpha: .55), width: .8),
          ),
          child: Image.asset(
            'assets/videos_decor/videos_banner.png',
            width: double.infinity,
            height: heroHeight,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => Container(
              color: const Color(0xFF071A2B),
              alignment: Alignment.center,
              child: const Text(
                'Videos banner image not found',
                style: TextStyle(color: _cream),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHealth() {
    final total = _videos.length;
    int pct(int complete) =>
        total == 0 ? 0 : ((complete / total) * 100).round();
    final peoplePct = pct(_peopleCount);
    final datesPct = pct(_dateCount);
    final placesPct = pct(_locationCount);
    final describedPct = pct(_descriptionCount);
    final organizationPct = total == 0
        ? 0
        : ((peoplePct + datesPct + placesPct + describedPct) / 4).round();

    Color gaugeColor(int value) {
      if (value >= 75) return const Color(0xFF8FCB78);
      if (value >= 45) return const Color(0xFFE6C766);
      return const Color(0xFFE28A7A);
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
            style: const TextStyle(
              color: _cream,
              fontWeight: FontWeight.w900,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _cream.withValues(alpha: .50),
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
      double size = 54,
      bool overall = false,
    }) {
      final color = gaugeColor(value);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
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
                      backgroundColor: _cream.withValues(alpha: .09),
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
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: overall ? _gold : _cream.withValues(alpha: .70),
                fontSize: overall ? 9.5 : 9,
                fontWeight: FontWeight.w800,
                letterSpacing: overall ? .45 : .15,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF071B2D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withValues(alpha: .48), width: .9),
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
                const Text(
                  'VIDEO COLLECTION',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.2,
                    letterSpacing: 1.05,
                  ),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    collectionStat('$total', 'Videos'),
                    collectionStat('$_peopleCount', 'People Identified'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 70, color: _gold.withValues(alpha: .20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ORGANIZATION',
                  style: TextStyle(
                    color: _gold,
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
                    gauge('People', peoplePct),
                    gauge('Dates', datesPct),
                    gauge('Locations', placesPct),
                    gauge('Descriptions', describedPct),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF081E33).withValues(alpha: .97),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _gold.withValues(alpha: .48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: _cream, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF071A2B),
              hintText: 'Search your videos…',
              hintStyle: TextStyle(color: _cream.withValues(alpha: .48)),
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
              border: OutlineInputBorder(
                borderSide: BorderSide(color: _gold.withValues(alpha: .30)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedVideoSourceRoot ?? '',
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Source',
                    prefixIcon: Icon(Icons.folder_open_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text(
                        'All Sources',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ..._mediaSources.map((source) {
                      final root = (source['root_path'] as String? ?? '')
                          .trim();
                      final name =
                          (source['display_name'] as String? ?? 'Media Source')
                              .trim();
                      return DropdownMenuItem(
                        value: root,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedVideoSourceRoot = (value == null || value.isEmpty)
                        ? null
                        : value;
                    _currentVideoFolder = '';
                    _showAllVideosOnLanding = false;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _sortMode,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Sort',
                    prefixIcon: Icon(Icons.filter_list),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'date_newest',
                      child: Text(
                        'Newest first',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'date_oldest',
                      child: Text(
                        'Oldest first',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'name_az',
                      child: Text(
                        'Name A–Z',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'name_za',
                      child: Text(
                        'Name Z–A',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'size_largest',
                      child: Text(
                        'Largest first',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sortMode = value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesPanel() {
    final counts = _sourceCounts;
    return _sidePanel(
      icon: Icons.cloud_outlined,
      title: 'VIDEO SOURCES',
      trailing: TextButton.icon(
        onPressed: _scanning ? null : _addMediaSource,
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Add Source'),
        style: TextButton.styleFrom(
          foregroundColor: _gold,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 7),
        ),
      ),
      child: Column(
        children: [
          for (final source in _mediaSources) _videoSourceRow(source, counts),
        ],
      ),
    );
  }

  Widget _videoSourceRow(Map<String, Object?> source, Map<String, int> counts) {
    final root = (source['root_path'] as String? ?? '').trim();
    final name = (source['display_name'] as String? ?? 'Media Source').trim();
    final type = (source['source_type'] as String? ?? '').trim();
    final selected =
        _selectedVideoSourceRoot != null &&
        _samePath(root, _selectedVideoSourceRoot!);
    return InkWell(
      onTap: root.isEmpty
          ? null
          : () => setState(() {
              _selectedVideoSourceRoot = selected ? null : root;
              _currentVideoFolder = '';
              _showAllVideosOnLanding = false;
            }),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? _gold.withValues(alpha: .10) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: _gold.withValues(alpha: .16)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
        child: Row(
          children: [
            _VideoSourceBrandIcon(
              sourceType: type,
              displayName: name,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _cream,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  if (root.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        root,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _cream.withValues(alpha: .48),
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.check, size: 13, color: Color(0xFF78C850)),
            const SizedBox(width: 7),
            Text(
              '${counts[root] ?? 0}',
              style: const TextStyle(
                color: _cream,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.more_vert, size: 18, color: _muted),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPanel() {
    return _sidePanel(
      icon: Icons.fact_check_outlined,
      title: 'REVIEW & ORGANIZE',
      child: Column(
        children: [
          _sideRow(
            icon: Icons.content_copy_outlined,
            label: 'Review Exact Duplicates',
            onTap: _scanning ? null : _reviewExactVideoDuplicates,
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
            label: 'Add Video Source',
            onTap: _addMediaSource,
          ),
          _sideRow(
            icon: Icons.delete_outline,
            label: 'Video Trash',
            onTap: _openVideoTrash,
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
      decoration: BoxDecoration(
        color: const Color(0xFF081E33).withValues(alpha: .97),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _gold.withValues(alpha: .30), width: .8),
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
                  color: _gold.withValues(alpha: .26),
                  width: .8,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 1,
                  color: _gold.withValues(alpha: .82),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
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

  Widget _sideRow({
    required IconData icon,
    required String label,
    String? value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _gold.withValues(alpha: .18)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: .80),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _cream,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  letterSpacing: .2,
                ),
              ),
            ),
            if (value != null) ...[
              Text(
                value,
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 5),
            ],
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: _gold.withValues(alpha: .8),
                size: 17,
              ),
          ],
        ),
      ),
    );
  }

  bool get _isUnfiledVideoView =>
      _showAllVideosOnLanding &&
      _currentVideoFolder.isEmpty &&
      _selectedVideoSourceRoot != null;

  Widget _buildVideoBreadcrumbs() {
    if (_currentVideoFolder.isEmpty && !_isUnfiledVideoView) {
      return const SizedBox.shrink();
    }
    final segments = _currentVideoFolder.isEmpty
        ? <String>['Unfiled Videos']
        : path.split(_currentVideoFolder);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentVideoFolder = '';
                        _showAllVideosOnLanding = false;
                        _folderVideoFilter = 'all';
                        _selectedVideoPaths.clear();
                      });
                    },
                    icon: const Icon(Icons.home_outlined, size: 17),
                    label: const Text('Videos'),
                  ),
                  for (var i = 0; i < segments.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 18, color: _muted),
                    TextButton(
                      onPressed: i == segments.length - 1 || _isUnfiledVideoView
                          ? null
                          : () {
                              setState(() {
                                _currentVideoFolder = path.joinAll(
                                  segments.take(i + 1).toList(),
                                );
                                _showAllVideosOnLanding = true;
                                _folderVideoFilter = 'all';
                                _selectedVideoPaths.clear();
                              });
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

  Widget _buildLibraryPanel(List<_VideoFile> videos) {
    final q = _query.trim();
    final showVideos =
        _showAllVideosOnLanding ||
        q.isNotEmpty ||
        _currentVideoFolder.isNotEmpty;
    final folders = <_VideoFolderGroup>[];
    if (!showVideos) {
      final grouped = <String, _VideoFolderGroup>{};
      for (final video in videos) {
        final segments = video.relativeFolder.trim().isEmpty
            ? <String>[]
            : path.split(video.relativeFolder);
        final folderName = segments.isEmpty ? 'Unfiled' : segments.first;
        final relativeTopFolder = segments.isEmpty ? '' : segments.first;
        final fullFolderPath = relativeTopFolder.isEmpty
            ? video.sourceRoot
            : path.join(video.sourceRoot, relativeTopFolder);
        final key =
            '${path.normalize(video.sourceRoot).toLowerCase()}|${relativeTopFolder.toLowerCase()}';
        final group = grouped.putIfAbsent(
          key,
          () => _VideoFolderGroup(
            name: folderName,
            sourceRoot: video.sourceRoot,
            relativeFolder: relativeTopFolder,
            fullPath: fullFolderPath,
          ),
        );
        group.videos.add(video);
      }
      folders.addAll(grouped.values);
      folders.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        return a.fullPath.toLowerCase().compareTo(b.fullPath.toLowerCase());
      });
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 13),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _gold.withValues(alpha: .23)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        children: [
          if (_currentVideoFolder.isNotEmpty || _isUnfiledVideoView)
            _buildVideoBreadcrumbs(),
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                showVideos
                    ? (_isUnfiledVideoView
                          ? 'VIDEOS — Unfiled Videos'
                          : (_currentVideoFolder.isEmpty
                                ? 'VIDEOS'
                                : 'VIDEOS — ${path.basename(_currentVideoFolder)}'))
                    : 'VIDEOS & FOLDERS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _cream,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .45,
                  fontSize: 16,
                ),
              );
              if (!showVideos) {
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    Text(
                      '${folders.length} folders',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _showAllVideosOnLanding = true),
                      icon: const Icon(Icons.video_library_outlined, size: 16),
                      label: const Text('View All Videos'),
                    ),
                  ],
                );
              }
              final controls = <Widget>[
                Text(
                  '${videos.length} videos',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (_currentVideoFolder.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Filter this folder',
                    initialValue: _folderVideoFilter,
                    onSelected: (value) =>
                        setState(() => _folderVideoFilter = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'all', child: Text('All videos')),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'no_people',
                        child: Text('No people'),
                      ),
                      PopupMenuItem(value: 'no_date', child: Text('No date')),
                      PopupMenuItem(
                        value: 'no_location',
                        child: Text('No location'),
                      ),
                      PopupMenuItem(
                        value: 'no_description',
                        child: Text('No description'),
                      ),
                    ],
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: _gold.withValues(alpha: .38)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_list, size: 16, color: _gold),
                          const SizedBox(width: 5),
                          Text(
                            _folderVideoFilter == 'all'
                                ? 'Filter'
                                : _folderVideoFilter == 'no_people'
                                ? 'No People'
                                : _folderVideoFilter == 'no_date'
                                ? 'No Date'
                                : _folderVideoFilter == 'no_location'
                                ? 'No Location'
                                : 'No Description',
                            style: const TextStyle(
                              color: _cream,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.expand_more, size: 15, color: _gold),
                        ],
                      ),
                    ),
                  ),
                if (_currentVideoFolder.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Sort this folder',
                    initialValue: _sortMode,
                    onSelected: (value) => setState(() => _sortMode = value),
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
                      PopupMenuItem(value: 'name_az', child: Text('Name: A–Z')),
                      PopupMenuItem(value: 'name_za', child: Text('Name: Z–A')),
                      PopupMenuItem(
                        value: 'size_largest',
                        child: Text('Largest First'),
                      ),
                    ],
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: _gold.withValues(alpha: .38)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_vert, size: 16, color: _gold),
                          const SizedBox(width: 5),
                          Text(
                            _sortMode == 'date_newest'
                                ? 'Newest'
                                : _sortMode == 'date_oldest'
                                ? 'Oldest'
                                : _sortMode == 'name_az'
                                ? 'Name A–Z'
                                : _sortMode == 'name_za'
                                ? 'Name Z–A'
                                : 'Largest',
                            style: const TextStyle(
                              color: _cream,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.expand_more, size: 15, color: _gold),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: videos.isEmpty ? null : _toggleVideoSelectionMode,
                  icon: Icon(
                    _videoSelectionMode
                        ? Icons.close
                        : Icons.check_box_outlined,
                    size: 16,
                  ),
                  label: Text(_videoSelectionMode ? 'Cancel' : 'Select Videos'),
                ),
                if (_videoSelectionMode) ...[
                  OutlinedButton.icon(
                    onPressed: videos.isEmpty
                        ? null
                        : () => _selectAllVisibleVideos(videos),
                    icon: const Icon(Icons.select_all, size: 16),
                    label: const Text('Select All'),
                  ),
                  Text(
                    '${_selectedVideoPaths.length} selected',
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _selectedVideoPaths.isEmpty
                        ? null
                        : () => _editSelectedVideoMetadata(videos),
                    icon: const Icon(Icons.edit_note_outlined, size: 16),
                    label: const Text('Edit Selected'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _selectedVideoPaths.isEmpty
                        ? null
                        : () => _moveSelectedVideosToTrash(videos),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Move to Video Trash'),
                  ),
                  TextButton(
                    onPressed: _clearVideoSelection,
                    child: const Text('Clear'),
                  ),
                ],
              ];
              final primaryControls = _currentVideoFolder.isNotEmpty
                  ? controls.take(3).toList()
                  : controls.take(1).toList();
              final secondaryControls = _currentVideoFolder.isNotEmpty
                  ? controls.skip(3).toList()
                  : controls.skip(1).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: primaryControls,
                      ),
                    ],
                  ),
                  if (secondaryControls.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: secondaryControls,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (_videos.isEmpty && !_scanning)
            _buildEmptyState()
          else if (!showVideos)
            _buildVideoFolders(folders)
          else
            _buildVideoGrid(videos),
        ],
      ),
    );
  }

  Widget _buildVideoFolders(List<_VideoFolderGroup> folders) {
    if (folders.isEmpty) return _buildNoMatches();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 700
            ? 4
            : constraints.maxWidth >= 520
            ? 3
            : 2;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final folder in folders)
              SizedBox(
                width: cardWidth,
                height: 210,
                child: Material(
                  color: _navy.withValues(alpha: .60),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                    side: BorderSide(color: _gold.withValues(alpha: .25)),
                  ),
                  child: InkWell(
                    onTap: () => setState(() {
                      _selectedVideoSourceRoot = folder.sourceRoot;
                      _currentVideoFolder = folder.relativeFolder;
                      _showAllVideosOnLanding = true;
                    }),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _VideoThumbnail(
                            videoPath: folder.videos.first.filePath,
                            placeholder: _videoPlaceholder(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                folder.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _cream,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${folder.videos.length} videos',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Tooltip(
                                message: folder.fullPath,
                                child: Text(
                                  folder.fullPath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _cream.withValues(alpha: .46),
                                    fontSize: 9.5,
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
              ),
          ],
        );
      },
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
                  color: _isVideoSelected(video)
                      ? _gold.withValues(alpha: .12)
                      : _navy.withValues(alpha: .60),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                    side: BorderSide(
                      color: _isVideoSelected(video)
                          ? _gold
                          : _gold.withValues(alpha: .20),
                      width: _isVideoSelected(video) ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    onLongPress: () {
                      if (!_videoSelectionMode) {
                        setState(() => _videoSelectionMode = true);
                      }
                      _toggleVideoSelection(video);
                    },
                    onTap: () => _videoSelectionMode
                        ? _toggleVideoSelection(video)
                        : _openVideo(video),
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
                                      [
                                        _videoDisplayDate(video),
                                        (_metadata[video.filePath]?.location
                                                        .trim() ??
                                                    '')
                                                .isEmpty
                                            ? 'No location'
                                            : _metadata[video.filePath]!
                                                  .location
                                                  .trim(),
                                      ].join(' • '),
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
        _VideoThumbnail(
          videoPath: video.filePath,
          placeholder: _videoPlaceholder(),
        ),
        Positioned(
          top: 7,
          left: 7,
          child: Material(
            color: _navy.withValues(alpha: .82),
            shape: const CircleBorder(),
            child: Checkbox(
              value: _isVideoSelected(video),
              onChanged: (_) => _toggleVideoSelection(video),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
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

class _VideoDuplicateScanningDialog extends StatefulWidget {
  final VoidCallback onCancel;
  const _VideoDuplicateScanningDialog({required this.onCancel});

  @override
  State<_VideoDuplicateScanningDialog> createState() =>
      _VideoDuplicateScanningDialogState();
}

class _VideoDuplicateScanningDialogState
    extends State<_VideoDuplicateScanningDialog> {
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Checking Video Duplicates'),
      content: const SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 18),
            Text(
              'Sampling same-size videos first. Only likely matches receive a full byte-for-byte verification.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelling
              ? null
              : () {
                  widget.onCancel();
                  setState(() => _cancelling = true);
                },
          child: Text(_cancelling ? 'Cancelling…' : 'Cancel'),
        ),
      ],
    );
  }
}

class _ExactVideoDuplicatesDialog extends StatefulWidget {
  final List<List<_VideoFile>> groups;
  final Future<int> Function(List<_VideoFile>) onMoveToTrash;
  const _ExactVideoDuplicatesDialog({
    required this.groups,
    required this.onMoveToTrash,
  });
  @override
  State<_ExactVideoDuplicatesDialog> createState() =>
      _ExactVideoDuplicatesDialogState();
}

class _ExactVideoDuplicatesDialogState
    extends State<_ExactVideoDuplicatesDialog> {
  final Map<int, int> _keepers = {};
  bool _moving = false;

  Future<void> _moveReviewedRemovals() async {
    if (_moving || _keepers.isEmpty) return;
    final removals = <_VideoFile>[];
    for (final entry in _keepers.entries) {
      final group = widget.groups[entry.key];
      for (var i = 0; i < group.length; i++) {
        if (i != entry.value) removals.add(group[i]);
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move Selected Copies to Video Trash?'),
        content: Text(
          '${removals.length} exact duplicate ${removals.length == 1 ? 'copy' : 'copies'} will be physically moved to Heirloom Atlas Video Trash.\n\nThey can be restored later. Permanent deletion is only available from Video Trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Move to Video Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _moving = true);
    final moved = await widget.onMoveToTrash(removals);
    if (!mounted) return;
    setState(() => _moving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Moved $moved ${moved == 1 ? 'video' : 'videos'} to Video Trash.',
        ),
      ),
    );
    if (moved > 0) Navigator.of(context).pop();
  }

  String _bytes(int n) => n >= 1073741824
      ? '${(n / 1073741824).toStringAsFixed(1)} GB'
      : n >= 1048576
      ? '${(n / 1048576).toStringAsFixed(1)} MB'
      : '${(n / 1024).toStringAsFixed(0)} KB';

  String _modified(_VideoFile v) {
    try {
      final d = File(v.filePath).lastModifiedSync();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Unknown';
    }
  }

  Widget _copy(BuildContext context, _VideoFile v, int gi, int vi) {
    final keep = _keepers[gi] == vi;
    final remove = _keepers.containsKey(gi) && !keep;
    return InkWell(
      onTap: () => setState(() {
        // Clicking the current KEEP choice again clears the whole set.
        // Clicking another copy swaps KEEP/REMOVE as before.
        if (_keepers[gi] == vi) {
          _keepers.remove(gi);
        } else {
          _keepers[gi] = vi;
        }
      }),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          border: Border.all(
            color: keep
                ? const Color(0xFF4CAF50)
                : remove
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).dividerColor,
            width: keep || remove ? 2.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: _VideoThumbnail(
                  videoPath: v.filePath,
                  placeholder: Container(
                    color: const Color(0xFF10243A),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.movie_outlined,
                      size: 38,
                      color: Color(0xFFC6A15B),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  keep
                      ? Icons.check_circle
                      : remove
                      ? Icons.delete_outline
                      : Icons.radio_button_unchecked,
                  size: 17,
                  color: keep
                      ? const Color(0xFF4CAF50)
                      : remove
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                const SizedBox(width: 4),
                Text(
                  keep
                      ? 'KEEP'
                      : remove
                      ? 'REMOVE'
                      : 'Choose to keep',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: keep
                        ? const Color(0xFF4CAF50)
                        : remove
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Tooltip(
              message: v.fileName,
              child: Text(
                v.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Tooltip(
              message: v.filePath,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.folder_outlined, size: 13),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      File(v.filePath).parent.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_bytes(v.fileSize)} • ${_modified(v)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _set(BuildContext context, int gi) {
    final g = widget.groups[gi];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Duplicate set ${gi + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_keepers.containsKey(gi)) ...[
                TextButton.icon(
                  onPressed: _moving
                      ? null
                      : () => setState(() => _keepers.remove(gi)),
                  icon: const Icon(Icons.clear, size: 15),
                  label: const Text('Clear choice'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                '${g.length} copies • ${_bytes(g.first.fileSize)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (g.length == 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _copy(context, g[0], gi, 0)),
                const SizedBox(width: 7),
                Expanded(child: _copy(context, g[1], gi, 1)),
              ],
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (var i = 0; i < g.length; i++)
                  SizedBox(width: 205, child: _copy(context, g[i], gi, i)),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Row(
        children: [
          const Expanded(child: Text('Exact Video Duplicates')),
          Text(
            '${_keepers.length} of ${widget.groups.length} reviewed',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
      content: SizedBox(
        width: 1400,
        height: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All sets passed full byte-for-byte verification. Click the copy to KEEP; its identical copy is marked REMOVE. Click KEEP again or use Clear choice to reset a set. Nothing is deleted yet.',
            ),
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 1100 ? 2 : 1;
                  const gap = 10.0;
                  final w = cols == 2 ? (c.maxWidth - gap) / 2 : c.maxWidth;
                  return SingleChildScrollView(
                    child: Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < widget.groups.length; i++)
                          SizedBox(width: w, child: _set(context, i)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _moving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _moving || _keepers.isEmpty ? null : _moveReviewedRemovals,
          icon: _moving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_sweep_outlined),
          label: Text(
            _keepers.isEmpty
                ? 'Review Copies First'
                : 'Move REMOVE Copies (${_keepers.entries.fold<int>(0, (sum, e) => sum + widget.groups[e.key].length - 1)})',
          ),
        ),
      ],
    );
  }
}

class _VideoTrashDialog extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final Future<bool> Function(Map<String, dynamic>) onRestore;
  final Future<bool> Function(Map<String, dynamic>) onDeletePermanently;
  const _VideoTrashDialog({
    required this.entries,
    required this.onRestore,
    required this.onDeletePermanently,
  });
  @override
  State<_VideoTrashDialog> createState() => _VideoTrashDialogState();
}

class _VideoTrashDialogState extends State<_VideoTrashDialog> {
  late final List<Map<String, dynamic>> _entries =
      List<Map<String, dynamic>>.from(widget.entries);
  bool _busy = false;

  Future<void> _restore(Map<String, dynamic> entry) async {
    setState(() => _busy = true);
    final ok = await widget.onRestore(entry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _entries.remove(entry);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Video restored to its original folder.'
              : 'Could not restore video.',
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final name = path.basename(entry['trashPath']?.toString() ?? 'video');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Video Permanently?'),
        content: Text(
          '$name will be permanently deleted from this computer. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await widget.onDeletePermanently(entry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _entries.remove(entry);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Video permanently deleted.' : 'Could not delete video.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(24),
    title: Row(
      children: [
        const Expanded(child: Text('Video Trash')),
        Text(
          '${_entries.length} ${_entries.length == 1 ? 'video' : 'videos'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    ),
    content: SizedBox(
      width: 900,
      height: 600,
      child: _entries.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 52),
                  SizedBox(height: 10),
                  Text('Video Trash is empty.'),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final e = _entries[i];
                final trash = e['trashPath']?.toString() ?? '';
                final original = e['originalPath']?.toString() ?? '';
                return ListTile(
                  leading: SizedBox(
                    width: 120,
                    height: 68,
                    child: _VideoThumbnail(
                      videoPath: trash,
                      placeholder: Container(
                        color: const Color(0xFF10243A),
                        alignment: Alignment.center,
                        child: const Icon(Icons.movie_outlined),
                      ),
                    ),
                  ),
                  title: Text(
                    path.basename(trash),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Tooltip(
                    message: original,
                    child: Text(
                      'Original: $original',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : () => _restore(e),
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _delete(e),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Delete Permanently'),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

class _VideoThumbnail extends StatefulWidget {
  final String videoPath;
  final Widget placeholder;

  const _VideoThumbnail({required this.videoPath, required this.placeholder});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  String? _thumbnailPath;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _thumbnailPath = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final result = await _VideoThumbnailQueue.instance.get(widget.videoPath);
      if (!mounted || widget.videoPath != result.videoPath) return;
      setState(() {
        _thumbnailPath = result.thumbnailPath;
        _failed = result.thumbnailPath == null;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailPath = _thumbnailPath;
    if (thumbnailPath != null) {
      return Image.file(
        File(thumbnailPath),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.placeholder,
      );
    }

    // Do not show dozens of spinners while videos wait in the queue.
    return widget.placeholder;
  }
}

class _VideoThumbnailResult {
  final String videoPath;
  final String? thumbnailPath;

  const _VideoThumbnailResult(this.videoPath, this.thumbnailPath);
}

class _VideoThumbnailQueue {
  _VideoThumbnailQueue._();

  static final _VideoThumbnailQueue instance = _VideoThumbnailQueue._();

  // One native Media Foundation thumbnail job at a time on Windows.
  Future<void> _tail = Future<void>.value();
  final Map<String, Future<_VideoThumbnailResult>> _pending = {};

  Future<_VideoThumbnailResult> get(String videoPath) {
    return _pending.putIfAbsent(videoPath, () {
      final completer = Completer<_VideoThumbnailResult>();

      _tail = _tail.then((_) async {
        try {
          completer.complete(await _generateOrLoad(videoPath));
        } catch (_) {
          completer.complete(_VideoThumbnailResult(videoPath, null));
        }
      });

      return completer.future.whenComplete(() {
        _pending.remove(videoPath);
      });
    });
  }

  Future<_VideoThumbnailResult> _generateOrLoad(String videoPath) async {
    final video = File(videoPath);
    if (!await video.exists()) {
      return _VideoThumbnailResult(videoPath, null);
    }

    final stat = await video.stat();
    final cacheRoot = Directory(
      path.join(
        (await getTemporaryDirectory()).path,
        'HeirloomAtlas',
        'VideoThumbnails',
      ),
    );
    await cacheRoot.create(recursive: true);

    final cacheKey = _fnv1a64(
      '${path.normalize(videoPath).toLowerCase()}|${stat.size}|'
      '${stat.modified.millisecondsSinceEpoch}|orientation-v1',
    );
    final cachedPath = path.join(cacheRoot.path, '$cacheKey.png');
    final cachedFile = File(cachedPath);

    if (await cachedFile.exists() && await cachedFile.length() > 0) {
      return _VideoThumbnailResult(videoPath, cachedPath);
    }

    try {
      final generated = await FlutterVideoThumbnailPlus.thumbnailFile(
        video: videoPath,
        thumbnailPath: cachedPath,
        imageFormat: ImageFormat.png,
        maxWidth: 360,
        timeMs: 1000,
        quality: 65,
      ).timeout(const Duration(seconds: 15));

      if (generated != null &&
          generated.trim().isNotEmpty &&
          await File(generated).exists()) {
        await _applyVideoRotation(videoPath, generated);
        return _VideoThumbnailResult(videoPath, generated);
      }

      if (await cachedFile.exists() && await cachedFile.length() > 0) {
        return _VideoThumbnailResult(videoPath, cachedPath);
      }
    } catch (_) {
      // Unsupported/corrupt/slow videos keep the normal placeholder.
    }

    return _VideoThumbnailResult(videoPath, null);
  }

  Future<void> _applyVideoRotation(
    String videoPath,
    String thumbnailPath,
  ) async {
    final rotation = await _readVideoRotation(videoPath);
    if (rotation == 0) return;

    try {
      final thumbnailFile = File(thumbnailPath);
      final decoded = img.decodeImage(await thumbnailFile.readAsBytes());
      if (decoded == null) return;

      final rotated = img.copyRotate(decoded, angle: rotation.toDouble());
      await thumbnailFile.writeAsBytes(img.encodePng(rotated), flush: true);
    } catch (_) {
      // If rotation correction fails, keep the thumbnail generated normally.
    }
  }

  Future<int> _readVideoRotation(String videoPath) async {
    final executable = await _findExifTool();
    if (executable == null) return 0;

    try {
      final result = await Process.run(executable, [
        '-s',
        '-s',
        '-s',
        '-Rotation',
        '-Rotation-deg',
        videoPath,
      ], runInShell: false).timeout(const Duration(seconds: 8));

      if (result.exitCode != 0) return 0;
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return 0;

      final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(output);
      if (match == null) return 0;
      final degrees = double.tryParse(match.group(0) ?? '')?.round() ?? 0;
      final normalized = ((degrees % 360) + 360) % 360;
      return normalized == 90 || normalized == 180 || normalized == 270
          ? normalized
          : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<String?> _findExifTool() async {
    final candidates = <String>[];

    if (Platform.isWindows) {
      final executableDirectory = File(Platform.resolvedExecutable).parent.path;
      candidates.add(
        path.join(executableDirectory, 'tools', 'exiftool', 'exiftool.exe'),
      );
      candidates.add(r'C:\ExifTool\exiftool.exe');
    }

    candidates.addAll(['exiftool.exe', 'exiftool']);

    for (final candidate in candidates) {
      try {
        if (path.isAbsolute(candidate) && !await File(candidate).exists()) {
          continue;
        }
        final result = await Process.run(candidate, [
          '-ver',
        ], runInShell: !path.isAbsolute(candidate));
        if (result.exitCode == 0) return candidate;
      } catch (_) {}
    }
    return null;
  }

  String _fnv1a64(String value) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xFFFFFFFFFFFFFFFF;

    for (final unit in utf8.encode(value)) {
      hash ^= unit;
      hash = (hash * prime) & mask;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}

class _VideoMetadataDialog extends StatefulWidget {
  final _VideoFile video;
  final _VideoMetadata current;
  const _VideoMetadataDialog({required this.video, required this.current});

  @override
  State<_VideoMetadataDialog> createState() => _VideoMetadataDialogState();
}

class _VideoMetadataDialogState extends State<_VideoMetadataDialog> {
  late final TextEditingController _people;
  late final TextEditingController _date;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _tags;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _people = TextEditingController(text: widget.current.people.join(', '));
    _date = TextEditingController(text: widget.current.approximateDate);
    _location = TextEditingController(text: widget.current.location);
    _description = TextEditingController(text: widget.current.description);
    _tags = TextEditingController(text: widget.current.tags.join(', '));
    _notes = TextEditingController(text: widget.current.notes);
  }

  @override
  void dispose() {
    _people.dispose();
    _date.dispose();
    _location.dispose();
    _description.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> _split(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();

  void _save() {
    Navigator.of(context).pop(
      _VideoMetadata(
        filePath: widget.video.filePath,
        people: _split(_people.text),
        tags: _split(_tags.text),
        approximateDate: _date.text.trim(),
        location: _location.text.trim(),
        description: _description.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
                  widget.video.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _people,
                decoration: const InputDecoration(
                  labelText: 'People',
                  hintText: 'Separate names with commas',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _date,
                decoration: const InputDecoration(
                  labelText: 'Date / Approximate Date',
                  hintText: 'Example: Summer 1998',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'Separate tags with commas',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _VideoBatchMetadataChanges {
  final List<String>? people;
  final List<String>? tags;
  final String? approximateDate;
  final String? location;
  final String? description;
  final String? notes;

  const _VideoBatchMetadataChanges({
    this.people,
    this.tags,
    this.approximateDate,
    this.location,
    this.description,
    this.notes,
  });

  bool get hasChanges =>
      people != null ||
      tags != null ||
      approximateDate != null ||
      location != null ||
      description != null ||
      notes != null;
}

class _VideoBatchMetadataDialog extends StatefulWidget {
  final int selectedCount;
  const _VideoBatchMetadataDialog({required this.selectedCount});

  @override
  State<_VideoBatchMetadataDialog> createState() =>
      _VideoBatchMetadataDialogState();
}

class _VideoBatchMetadataDialogState extends State<_VideoBatchMetadataDialog> {
  final _people = TextEditingController();
  final _date = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _tags = TextEditingController();
  final _notes = TextEditingController();
  bool _applyPeople = false;
  bool _applyDate = false;
  bool _applyLocation = false;
  bool _applyDescription = false;
  bool _applyTags = false;
  bool _applyNotes = false;

  @override
  void dispose() {
    _people.dispose();
    _date.dispose();
    _location.dispose();
    _description.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> _split(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();

  Widget _field({
    required bool apply,
    required ValueChanged<bool?> onChanged,
    required TextEditingController controller,
    required String label,
    String? hint,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Checkbox(value: apply, onChanged: onChanged),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: apply,
            minLines: minLines,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  void _save() {
    Navigator.of(context).pop(
      _VideoBatchMetadataChanges(
        people: _applyPeople ? _split(_people.text) : null,
        tags: _applyTags ? _split(_tags.text) : null,
        approximateDate: _applyDate ? _date.text.trim() : null,
        location: _applyLocation ? _location.text.trim() : null,
        description: _applyDescription ? _description.text.trim() : null,
        notes: _applyNotes ? _notes.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.selectedCount} Selected Videos'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Check only the fields you want to change. Unchecked fields stay exactly as they are. A checked blank field clears that field.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
              _field(
                apply: _applyPeople,
                onChanged: (v) => setState(() => _applyPeople = v ?? false),
                controller: _people,
                label: 'People',
                hint: 'Separate names with commas',
              ),
              const SizedBox(height: 10),
              _field(
                apply: _applyDate,
                onChanged: (v) => setState(() => _applyDate = v ?? false),
                controller: _date,
                label: 'Date / Approximate Date',
                hint: 'Example: Summer 1998',
              ),
              const SizedBox(height: 10),
              _field(
                apply: _applyLocation,
                onChanged: (v) => setState(() => _applyLocation = v ?? false),
                controller: _location,
                label: 'Location',
              ),
              const SizedBox(height: 10),
              _field(
                apply: _applyDescription,
                onChanged: (v) =>
                    setState(() => _applyDescription = v ?? false),
                controller: _description,
                label: 'Description',
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _field(
                apply: _applyTags,
                onChanged: (v) => setState(() => _applyTags = v ?? false),
                controller: _tags,
                label: 'Tags',
                hint: 'Separate tags with commas',
              ),
              const SizedBox(height: 10),
              _field(
                apply: _applyNotes,
                onChanged: (v) => setState(() => _applyNotes = v ?? false),
                controller: _notes,
                label: 'Notes',
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Apply Changes'),
        ),
      ],
    );
  }
}

class _CachedVideoCatalog {
  final List<_VideoFile> videos;
  final Map<String, DateTime> embeddedDates;

  const _CachedVideoCatalog(this.videos, this.embeddedDates);
}

class _VideoFolderGroup {
  final String name;
  final String sourceRoot;
  final String relativeFolder;
  final String fullPath;
  final List<_VideoFile> videos = [];

  _VideoFolderGroup({
    required this.name,
    required this.sourceRoot,
    required this.relativeFolder,
    required this.fullPath,
  });
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

class _VideoSourceBrandIcon extends StatelessWidget {
  final String sourceType;
  final String? displayName;
  final double size;

  const _VideoSourceBrandIcon({
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
          child: CustomPaint(painter: _VideoGoogleDriveMarkPainter()),
        );
      case 'onedrive':
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _VideoOneDriveMarkPainter()),
        );
      case 'icloud':
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _VideoICloudMarkPainter()),
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

class _VideoOneDriveMarkPainter extends CustomPainter {
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4.2, 11.5, 15.6, 7.2),
        const Radius.circular(3.6),
      ),
      lightBlue,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VideoOneDriveMarkPainter oldDelegate) => false;
}

class _VideoICloudMarkPainter extends CustomPainter {
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
    final p = Path()
      ..moveTo(6.2, 17.7)
      ..cubicTo(4.3, 17.7, 2.8, 16.2, 2.8, 14.3)
      ..cubicTo(2.8, 12.5, 4.1, 11.0, 5.8, 10.7)
      ..cubicTo(6.5, 7.7, 9.0, 5.6, 12.0, 5.6)
      ..cubicTo(14.6, 5.6, 16.8, 7.1, 17.8, 9.4)
      ..cubicTo(20.0, 9.7, 21.7, 11.5, 21.7, 13.8)
      ..cubicTo(21.7, 16.0, 19.9, 17.7, 17.7, 17.7)
      ..close();
    canvas.drawPath(p, cloudPaint);
    canvas.drawPath(p, outlinePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VideoICloudMarkPainter oldDelegate) => false;
}

class _VideoGoogleDriveMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(scale, scale);
    final green = Paint()..color = const Color(0xFF0F9D58),
        yellow = Paint()..color = const Color(0xFFF4B400),
        blue = Paint()..color = const Color(0xFF4285F4);
    final gp = Path()
      ..moveTo(8.1, 2.0)
      ..lineTo(12.0, 2.0)
      ..lineTo(19.2, 14.4)
      ..lineTo(15.2, 14.4)
      ..close();
    final yp = Path()
      ..moveTo(8.1, 2.0)
      ..lineTo(2.2, 12.2)
      ..lineTo(4.2, 15.6)
      ..lineTo(10.1, 5.4)
      ..close();
    final bp = Path()
      ..moveTo(4.2, 15.6)
      ..lineTo(15.2, 15.6)
      ..lineTo(19.2, 14.4)
      ..lineTo(21.8, 18.8)
      ..lineTo(6.1, 18.8)
      ..close();
    canvas.drawPath(gp, green);
    canvas.drawPath(yp, yellow);
    canvas.drawPath(bp, blue);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VideoGoogleDriveMarkPainter oldDelegate) =>
      false;
}
