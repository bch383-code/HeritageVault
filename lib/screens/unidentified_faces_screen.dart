import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../services/face_recognition_service.dart';

class UnidentifiedFacesScreen extends StatefulWidget {
  const UnidentifiedFacesScreen({super.key});

  @override
  State<UnidentifiedFacesScreen> createState() =>
      _UnidentifiedFacesScreenState();
}

class _KnownSuggestion {
  final String personName;
  final double similarity;

  const _KnownSuggestion({
    required this.personName,
    required this.similarity,
  });
}

class _UnidentifiedFacesScreenState
    extends State<UnidentifiedFacesScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<List<DetectedFaceRecord>> _groups = const [];
  List<DetectedFaceRecord> _knownFaces = const [];
  int _groupIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _databaseHelper.getUnconfirmedFaces(),
        _databaseHelper.getConfirmedFaces(),
      ]);

      final unidentified = results[0];
      final known = results[1];

      final groups = FaceRecognitionService.groupSimilarFaces(
        unidentified,
      );

      if (!mounted) return;

      setState(() {
        _groups = groups;
        _knownFaces = known;
        _groupIndex = 0;
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

  List<DetectedFaceRecord> get _currentGroup =>
      _groups.isEmpty ? const [] : _groups[_groupIndex];

  _KnownSuggestion? get _suggestion {
    if (_currentGroup.isEmpty || _knownFaces.isEmpty) return null;

    final bestByPerson = <String, double>{};

    for (final candidate in _currentGroup) {
      for (final known in _knownFaces) {
        if (known.personName.trim().isEmpty) continue;

        final similarity = FaceRecognitionService.cosineSimilarity(
          candidate.embedding,
          known.embedding,
        );

        final previous = bestByPerson[known.personName] ?? -1;
        if (similarity > previous) {
          bestByPerson[known.personName] = similarity;
        }
      }
    }

    if (bestByPerson.isEmpty) return null;

    final best = bestByPerson.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    if (best.value < 0.65) return null;

    return _KnownSuggestion(
      personName: best.key,
      similarity: best.value,
    );
  }

  Future<void> _confirmGroup(String personName) async {
    final cleanName = personName.trim();
    if (cleanName.isEmpty || _currentGroup.isEmpty) return;

    setState(() => _saving = true);

    try {
      final group = [..._currentGroup];
      final ids = group.map((face) => face.id).whereType<int>().toList();

      await _databaseHelper.confirmFaceGroup(
        faceIds: ids,
        personName: cleanName,
      );

      for (final photoPath
          in group.map((face) => face.photoFilePath).toSet()) {
        final existing =
            await _databaseHelper.getPhotoCatalogMetadata(photoPath);

        await _databaseHelper.savePhotoCatalogMetadata(
          PhotoCatalogMetadata(
            filePath: existing.filePath,
            people: <String>{...existing.people, cleanName}.toList(),
            tags: existing.tags,
            approximateDate: existing.approximateDate,
            location: existing.location,
            description: existing.description,
            notes: existing.notes,
          ),
        );
      }

      final newKnown = group
          .map(
            (face) => DetectedFaceRecord(
              id: face.id,
              photoFilePath: face.photoFilePath,
              faceIndex: face.faceIndex,
              left: face.left,
              top: face.top,
              width: face.width,
              height: face.height,
              detectionScore: face.detectionScore,
              embedding: face.embedding,
              thumbnailPath: face.thumbnailPath,
              personName: cleanName,
              confirmed: true,
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _knownFaces = [..._knownFaces, ...newKnown];
        _groups.removeAt(_groupIndex);
        if (_groupIndex >= _groups.length && _groupIndex > 0) {
          _groupIndex--;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _nameGroup() async {
    final suggestion = _suggestion;
    final controller = TextEditingController(
      text: suggestion?.personName ?? '',
    );

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Identify this person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Person name',
            hintText: 'Fred Hoffman',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final clean = value.trim();
            if (clean.isNotEmpty) {
              Navigator.pop(dialogContext, clean);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final clean = controller.text.trim();
              if (clean.isNotEmpty) {
                Navigator.pop(dialogContext, clean);
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name != null) {
      await _confirmGroup(name);
    }
  }

  void _removeFromGroup(DetectedFaceRecord face) {
    if (_currentGroup.length <= 1) return;

    setState(() {
      final group = _currentGroup;
      group.remove(face);
      _groups.add([face]);
      _groups.sort((a, b) => b.length.compareTo(a.length));
      _groupIndex = 0;
    });
  }

  void _skipGroup() {
    if (_groups.length <= 1) return;

    setState(() {
      if (_groupIndex < _groups.length - 1) {
        _groupIndex++;
      } else {
        _groupIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unidentified Faces')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SelectableText(
              'Could not load unidentified faces.\n\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_groups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unidentified Faces')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.task_alt, size: 72),
              SizedBox(height: 16),
              Text(
                'No unidentified faces remain.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final group = _currentGroup;
    final suggestion = _suggestion;
    final totalFaces =
        _groups.fold<int>(0, (total, item) => total + item.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unidentified Faces'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '$totalFaces faces • ${_groups.length} groups',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_search_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Review Queue • Group ${_groupIndex + 1} of '
                          '${_groups.length} • ${group.length} similar '
                          'face${group.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _skipGroup,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Skip for Now'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving ? null : _nameGroup,
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Identify'),
                      ),
                    ],
                  ),
                  if (suggestion != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome),
                        title: Text(
                          'Possible match: ${suggestion.personName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          '${(suggestion.similarity * 100).toStringAsFixed(1)}% '
                          'similarity to a confirmed Known Person.',
                        ),
                        trailing: FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _confirmGroup(
                                    suggestion.personName,
                                  ),
                          child: const Text('Confirm'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: group.length,
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, index) {
                final face = group[index];
                final thumbnail = File(face.thumbnailPath);

                return Card(
                  clipBehavior: Clip.antiAlias,
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
                                    Icons.face_outlined,
                                    size: 58,
                                  ),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${(face.detectionScore * 100).toStringAsFixed(0)}% face',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (group.length > 1)
                              IconButton(
                                tooltip: 'Not the same person',
                                onPressed: () => _removeFromGroup(face),
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Material(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Previous group',
                    onPressed: _groupIndex > 0
                        ? () => setState(() => _groupIndex--)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      '${_groupIndex + 1} of ${_groups.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Next group',
                    onPressed: _groupIndex < _groups.length - 1
                        ? () => setState(() => _groupIndex++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
