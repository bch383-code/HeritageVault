import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';

class KnownPeopleScreen extends StatefulWidget {
  const KnownPeopleScreen({super.key});

  @override
  State<KnownPeopleScreen> createState() => _KnownPeopleScreenState();
}

class _KnownPeopleScreenState extends State<KnownPeopleScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _loading = true;
  String? _error;
  Map<String, List<DetectedFaceRecord>> _people = {};
  List<VaultPhoto> _photos = const [];
  Map<String, PhotoCatalogMetadata> _catalogByPath =
      <String, PhotoCatalogMetadata>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _databaseHelper.getConfirmedFaces(),
        _databaseHelper.getIndexedPhotos(),
        _databaseHelper.getAllPhotoCatalogMetadata(),
      ]);

      final faces = results[0] as List<DetectedFaceRecord>;
      final photos = results[1] as List<VaultPhoto>;
      final catalogRecords = results[2] as List<PhotoCatalogMetadata>;

      final grouped = <String, List<DetectedFaceRecord>>{};
      for (final face in faces) {
        grouped.putIfAbsent(face.personName, () => []).add(face);
      }

      final sortedEntries = grouped.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

      if (!mounted) return;

      setState(() {
        _people = {
          for (final entry in sortedEntries) entry.key: entry.value,
        };
        _photos = photos;
        _catalogByPath = {
          for (final record in catalogRecords) record.filePath: record,
        };
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

  Future<void> _renamePerson(String oldName) async {
    final controller = TextEditingController(text: oldName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName == null || newName == oldName) return;

    await _databaseHelper.renameConfirmedPerson(
      oldName: oldName,
      newName: newName,
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Known People'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: SelectableText(
                      'Could not load known people.\n\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _people.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline, size: 72),
                          SizedBox(height: 16),
                          Text(
                            'No confirmed people yet.',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Scan and review faces to start building your known people library.',
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _people.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.15,
                      ),
                      itemBuilder: (context, index) {
                        final entry = _people.entries.elementAt(index);
                        final name = entry.key;
                        final faces = entry.value;
                        final photoCount =
                            faces.map((face) => face.photoFilePath).toSet().length;

                        final representative = faces.first;
                        final thumbnail = File(representative.thumbnailPath);

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _showPersonPhotos(name, faces),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: thumbnail.existsSync()
                                        ? Image.file(
                                            thumbnail,
                                            fit: BoxFit.cover,
                                          )
                                        : const Center(
                                            child: Icon(
                                              Icons.person_outline,
                                              size: 64,
                                            ),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    8,
                                    10,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$photoCount photo${photoCount == 1 ? '' : 's'} • '
                                              '${faces.length} confirmed face${faces.length == 1 ? '' : 's'}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Rename',
                                        onPressed: () => _renamePerson(name),
                                        icon: const Icon(Icons.edit_outlined),
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
  }

  List<VaultPhoto> _photosForPerson(String name) {
    final matchedPaths = <String>{};

    // Primary source: Heritage Vault People metadata.
    for (final entry in _catalogByPath.entries) {
      if (entry.value.people.contains(name)) {
        matchedPaths.add(entry.key);
      }
    }

    // Also include any photo with a confirmed face for this person.
    final confirmedFaces = _people[name] ?? const <DetectedFaceRecord>[];
    matchedPaths.addAll(
      confirmedFaces.map((face) => face.photoFilePath),
    );

    final result = _photos
        .where((photo) => matchedPaths.contains(photo.filePath))
        .toList();

    result.sort(
      (a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
    );

    return result;
  }

  Future<void> _showPersonPhotos(
    String name,
    List<DetectedFaceRecord> faces,
  ) async {
    final photos = _photosForPerson(name);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 1100,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${photos.length} full photo'
                            '${photos.length == 1 ? '' : 's'} • '
                            '${faces.length} confirmed face'
                            '${faces.length == 1 ? '' : 's'}',
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
                child: photos.isEmpty
                    ? const Center(
                        child: Text(
                          'No full photos are currently linked to this person.',
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: photos.length,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1,
                        ),
                        itemBuilder: (context, index) {
                          final photo = photos[index];
                          final file = File(photo.filePath);

                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _openFullPhoto(
                                dialogContext,
                                name,
                                photo,
                              ),
                              child: Column(
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
                                              cacheWidth: 600,
                                              errorBuilder:
                                                  (_, _, _) => const Center(
                                                child: Icon(
                                                  Icons.broken_image_outlined,
                                                  size: 48,
                                                ),
                                              ),
                                            )
                                          : const Center(
                                              child: Icon(
                                                Icons.image_not_supported_outlined,
                                                size: 48,
                                              ),
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
  }

  Future<void> _openFullPhoto(
    BuildContext parentDialogContext,
    String personName,
    VaultPhoto photo,
  ) async {
    final file = File(photo.filePath);
    final metadata = _catalogByPath[photo.filePath];

    await showDialog<void>(
      context: parentDialogContext,
      builder: (photoDialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1200,
            maxHeight: 850,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        photo.fileName,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(photoDialogContext),
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
                        width: double.infinity,
                        height: double.infinity,
                        padding: const EdgeInsets.all(18),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: file.existsSync()
                            ? Image.file(
                                file,
                                fit: BoxFit.contain,
                              )
                            : const Center(
                                child: Text('Original photo not found.'),
                              ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          Text(
                            personName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 14),
                          if (metadata != null) ...[
                            if (metadata.people.isNotEmpty)
                              _detailField(
                                'People',
                                metadata.people.join(', '),
                              ),
                            if (metadata.approximateDate.trim().isNotEmpty)
                              _detailField(
                                'Date',
                                metadata.approximateDate,
                              ),
                            if (metadata.location.trim().isNotEmpty)
                              _detailField(
                                'Location',
                                metadata.location,
                              ),
                            if (metadata.description.trim().isNotEmpty)
                              _detailField(
                                'Description',
                                metadata.description,
                              ),
                            if (metadata.tags.isNotEmpty)
                              _detailField(
                                'Tags',
                                metadata.tags.join(', '),
                              ),
                          ],
                          const SizedBox(height: 12),
                          const Text(
                            'Original file',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            photo.filePath,
                            style: Theme.of(context).textTheme.bodySmall,
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

  Widget _detailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
  }

}
