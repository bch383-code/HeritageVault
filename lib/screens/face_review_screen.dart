import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../services/face_recognition_service.dart';

class FaceReviewScreen extends StatefulWidget {
  final List<DetectedFaceRecord> faces;

  const FaceReviewScreen({
    super.key,
    required this.faces,
  });

  @override
  State<FaceReviewScreen> createState() => _FaceReviewScreenState();
}

class _KnownMatch {
  final String personName;
  final double similarity;

  const _KnownMatch({
    required this.personName,
    required this.similarity,
  });
}

class _FaceReviewScreenState extends State<FaceReviewScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  late List<List<DetectedFaceRecord>> _groups;
  List<DetectedFaceRecord> _knownFaces = const [];
  int _groupIndex = 0;
  bool _saving = false;
  bool _loadingKnown = true;

  @override
  void initState() {
    super.initState();
    _groups = FaceRecognitionService.groupSimilarFaces(
      widget.faces.where((face) => !face.confirmed).toList(),
    );
    _loadKnownFaces();
  }

  Future<void> _loadKnownFaces() async {
    final faces = await _databaseHelper.getConfirmedFaces();
    if (!mounted) return;

    setState(() {
      _knownFaces = faces;
      _loadingKnown = false;
    });
  }

  List<String> get _knownNames {
    final names = _knownFaces
        .map((face) => face.personName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return names;
  }

  List<DetectedFaceRecord> get _currentGroup =>
      _groups.isEmpty ? const [] : _groups[_groupIndex];

  _KnownMatch? get _currentSuggestion {
    if (_loadingKnown || _knownFaces.isEmpty || _currentGroup.isEmpty) {
      return null;
    }

    final scoresByPerson = <String, double>{};

    for (final candidate in _currentGroup) {
      for (final known in _knownFaces) {
        if (known.personName.trim().isEmpty) continue;

        final similarity = FaceRecognitionService.cosineSimilarity(
          candidate.embedding,
          known.embedding,
        );

        final previous = scoresByPerson[known.personName] ?? -1;
        if (similarity > previous) {
          scoresByPerson[known.personName] = similarity;
        }
      }
    }

    if (scoresByPerson.isEmpty) return null;

    final best = scoresByPerson.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    // Conservative threshold for an automatic suggestion. User confirmation
    // is still required.
    if (best.value < 0.65) return null;

    return _KnownMatch(
      personName: best.key,
      similarity: best.value,
    );
  }

  Future<void> _confirmCurrentGroup(String personName) async {
    if (_currentGroup.isEmpty || personName.trim().isEmpty) return;

    setState(() => _saving = true);

    try {
      final group = [..._currentGroup];
      final ids = group.map((face) => face.id).whereType<int>().toList();
      final cleanName = personName.trim();

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

      // Newly confirmed examples immediately become part of the known-person
      // reference library for later groups in this same review session.
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

  Future<void> _nameCurrentGroup() async {
    if (_currentGroup.isEmpty) return;

    final suggestion = _currentSuggestion;
    String enteredName = suggestion?.personName ?? '';

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Name this person'),
          content: SizedBox(
            width: 420,
            child: _KnownPersonAutocomplete(
              knownNames: _knownNames,
              initialValue: enteredName,
              onSubmitted: (value) {
                enteredName = value.trim();
                setDialogState(() {});
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: enteredName.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        enteredName.trim(),
                      ),
              child: const Text('Confirm Group'),
            ),
          ],
        ),
      ),
    );

    if (name != null) {
      await _confirmCurrentGroup(name);
    }
  }

  void _removeFace(DetectedFaceRecord face) {
    if (_currentGroup.length <= 1) return;

    setState(() {
      final group = _currentGroup;
      group.remove(face);
      _groups.add([face]);
      _groups.sort((a, b) => b.length.compareTo(a.length));
      _groupIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face Review')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 72),
              SizedBox(height: 16),
              Text(
                'No face groups left to review.',
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
    final suggestion = _currentSuggestion;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Face Review • Group ${_groupIndex + 1} of ${_groups.length}',
        ),
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
                      const Icon(Icons.groups_2_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${group.length} face${group.length == 1 ? '' : 's'} '
                          'look similar. Remove incorrect matches before '
                          'confirming the person.',
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _nameCurrentGroup,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Name Person'),
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
                          '${(suggestion.similarity * 100).toStringAsFixed(1)}% similarity '
                          'to a confirmed face. Heirloom Atlas will not assign '
                          'the name until you confirm it.',
                        ),
                        trailing: FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _confirmCurrentGroup(
                                    suggestion.personName,
                                  ),
                          child: const Text('Confirm'),
                        ),
                      ),
                    ),
                  ] else if (!_loadingKnown && _knownFaces.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No confident match to a known person.',
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
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.85,
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
                                tooltip: 'Not this person',
                                onPressed: () => _removeFace(face),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
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

class _KnownPersonAutocomplete extends StatelessWidget {
  final List<String> knownNames;
  final String initialValue;
  final ValueChanged<String> onSubmitted;

  const _KnownPersonAutocomplete({
    required this.knownNames,
    required this.initialValue,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return const Iterable<String>.empty();
        }

        final startsWith = knownNames.where(
          (name) => name.toLowerCase().startsWith(query),
        );

        final contains = knownNames.where(
          (name) =>
              !name.toLowerCase().startsWith(query) &&
              name.toLowerCase().contains(query),
        );

        return [...startsWith, ...contains].take(8);
      },
      onSelected: onSubmitted,
      fieldViewBuilder: (
        context,
        controller,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Person name',
            hintText: 'Start typing a known name...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final clean = value.trim();
            if (clean.isNotEmpty) {
              onSubmitted(clean);
            }
          },
        );
      },
    );
  }
}

