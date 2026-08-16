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

class _FaceReviewScreenState extends State<FaceReviewScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  late List<List<DetectedFaceRecord>> _groups;
  int _groupIndex = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groups = FaceRecognitionService.groupSimilarFaces(
      widget.faces.where((face) => !face.confirmed).toList(),
    );
  }

  List<DetectedFaceRecord> get _currentGroup =>
      _groups.isEmpty ? const [] : _groups[_groupIndex];

  Future<void> _nameCurrentGroup() async {
    if (_currentGroup.isEmpty) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Person name',
            hintText: 'Fred Hoffman',
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
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
            child: const Text('Confirm Group'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      final group = [..._currentGroup];
      final ids = group.map((face) => face.id).whereType<int>().toList();

      await _databaseHelper.confirmFaceGroup(
        faceIds: ids,
        personName: name.trim(),
      );

      for (final photoPath
          in group.map((face) => face.photoFilePath).toSet()) {
        final existing =
            await _databaseHelper.getPhotoCatalogMetadata(photoPath);

        await _databaseHelper.savePhotoCatalogMetadata(
          PhotoCatalogMetadata(
            filePath: existing.filePath,
            people: <String>{...existing.people, name.trim()}.toList(),
            tags: existing.tags,
            approximateDate: existing.approximateDate,
            location: existing.location,
            description: existing.description,
            notes: existing.notes,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _groups.removeAt(_groupIndex);
        if (_groupIndex >= _groups.length && _groupIndex > 0) {
          _groupIndex--;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
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
              child: Row(
                children: [
                  const Icon(Icons.groups_2_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${group.length} face${group.length == 1 ? '' : 's'} '
                      'look similar. Remove incorrect matches, then name '
                      'the person when you are confident.',
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
                              ? Image.file(thumbnail, fit: BoxFit.cover)
                              : const Center(
                                  child: Icon(Icons.face_outlined, size: 58),
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
