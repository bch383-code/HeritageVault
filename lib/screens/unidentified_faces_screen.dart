import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../services/face_recognition_service.dart';

class UnidentifiedFacesScreen extends StatelessWidget {
  const UnidentifiedFacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Face Review'),
          bottom: TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.person_search_outlined),
                text: 'Needs Identification',
              ),
              Tab(
                icon: Icon(Icons.do_not_disturb_on_outlined),
                text: 'Never Identifiable',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [_UnidentifiedFacesBody(), _UnknownFacesBody()],
        ),
      ),
    );
  }
}

class _UnidentifiedFacesBody extends StatefulWidget {
  const _UnidentifiedFacesBody();

  @override
  State<_UnidentifiedFacesBody> createState() =>
      _UnidentifiedFacesScreenState();
}

class _FaceMatchCandidate {
  final DetectedFaceRecord face;
  final double similarity;

  const _FaceMatchCandidate({required this.face, required this.similarity});

  String get confidenceLabel {
    if (similarity >= 0.82) return 'Strong match';
    if (similarity >= 0.72) return 'Possible match';
    return 'Low confidence';
  }
}

class _UnidentifiedFacesScreenState extends State<_UnidentifiedFacesBody> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<DetectedFaceRecord> _unidentified = const [];
  List<DetectedFaceRecord> _knownFaces = const [];
  String _search = '';

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

      if (!mounted) return;

      setState(() {
        _unidentified = List<DetectedFaceRecord>.from(results[0]);
        _knownFaces = List<DetectedFaceRecord>.from(results[1]);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<String> get _knownNames {
    final names =
        _knownFaces
            .map((face) => face.personName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Iterable<String> _matchingNames(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const <String>[];
    return _knownNames
        .where((name) => name.toLowerCase().contains(clean))
        .take(8);
  }

  String? _bestKnownSuggestion(DetectedFaceRecord face) {
    if (_knownFaces.isEmpty) return null;

    String? bestName;
    var bestScore = -1.0;

    for (final known in _knownFaces) {
      final name = known.personName.trim();
      if (name.isEmpty) continue;

      final score = FaceRecognitionService.cosineSimilarity(
        face.embedding,
        known.embedding,
      );
      if (score > bestScore) {
        bestScore = score;
        bestName = name;
      }
    }

    if (bestName == null || bestScore < 0.72) return null;
    return bestName;
  }

  double? _bestKnownSimilarity(DetectedFaceRecord face, String personName) {
    final matches = _knownFaces
        .where((known) => known.personName == personName)
        .toList();
    if (matches.isEmpty) return null;

    var best = -1.0;
    for (final known in matches) {
      final score = FaceRecognitionService.cosineSimilarity(
        face.embedding,
        known.embedding,
      );
      if (score > best) best = score;
    }
    return best < 0 ? null : best;
  }

  Future<String?> _askForName(DetectedFaceRecord face) async {
    final suggestion = _bestKnownSuggestion(face);
    final suggestionScore = suggestion == null
        ? null
        : _bestKnownSimilarity(face, suggestion);

    String currentText = '';

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches = _matchingNames(currentText).toList();

          void submit(String value) {
            final clean = value.trim();
            if (clean.isEmpty) return;
            FocusScope.of(dialogContext).unfocus();
            Navigator.of(dialogContext).pop(clean);
          }

          return AlertDialog(
            title: const Text('Who is this?'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Person name',
                      hintText: 'Start typing a name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      currentText = value;
                      setDialogState(() {});
                    },
                    onSubmitted: submit,
                  ),
                  if (suggestion != null && suggestionScore != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome),
                        title: Text('Suggested: $suggestion'),
                        subtitle: Text(
                          '${(suggestionScore * 100).toStringAsFixed(1)}% similarity',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(suggestion),
                          child: const Text('Use'),
                        ),
                      ),
                    ),
                  ],
                  if (matches.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Existing people',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: matches
                          .map(
                            (name) => ActionChip(
                              label: Text(name),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(name),
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: currentText.trim().isEmpty
                    ? null
                    : () => submit(currentText),
                child: const Text('Identify'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addPersonToPhoto(String photoPath, String personName) async {
    final existing = await _databaseHelper.getPhotoCatalogMetadata(photoPath);

    if (existing.people.contains(personName)) return;

    await _databaseHelper.savePhotoCatalogMetadata(
      PhotoCatalogMetadata(
        filePath: existing.filePath,
        people: <String>{...existing.people, personName}.toList(),
        tags: existing.tags,
        approximateDate: existing.approximateDate,
        location: existing.location,
        description: existing.description,
        notes: existing.notes,
      ),
    );
  }

  DetectedFaceRecord _asConfirmed(DetectedFaceRecord face, String personName) {
    return DetectedFaceRecord(
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
      personName: personName,
      confirmed: true,
    );
  }

  List<_FaceMatchCandidate> _findCandidates(DetectedFaceRecord reference) {
    final candidates = <_FaceMatchCandidate>[];

    for (final face in _unidentified) {
      if (face.id == reference.id) continue;

      final similarity = FaceRecognitionService.cosineSimilarity(
        reference.embedding,
        face.embedding,
      );

      // Deliberately conservative. Lower-confidence faces can still be
      // reviewed later from the unidentified queue.
      if (similarity >= 0.66) {
        candidates.add(_FaceMatchCandidate(face: face, similarity: similarity));
      }
    }

    candidates.sort((a, b) => b.similarity.compareTo(a.similarity));
    return candidates.take(60).toList();
  }

  Future<Set<int>> _reviewMatches(
    String personName,
    List<_FaceMatchCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return <int>{};

    final selected = <int>{
      for (final candidate in candidates)
        if (candidate.similarity >= 0.82 && candidate.face.id != null)
          candidate.face.id!,
    };

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            child: SizedBox(
              width: 1050,
              height: 760,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.manage_search_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Possible matches for $personName',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                '${candidates.length} possible '
                                '${candidates.length == 1 ? 'match' : 'matches'} • '
                                '${selected.length} selected',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(<int>{}),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Strong matches are preselected. Review every '
                            'selection before confirming. Unselected faces '
                            'remain unidentified.',
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(() => selected.clear());
                          },
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: candidates.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                      itemBuilder: (context, index) {
                        final candidate = candidates[index];
                        final face = candidate.face;
                        final faceId = face.id;
                        final checked =
                            faceId != null && selected.contains(faceId);
                        final thumbnail = File(face.thumbnailPath);

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: faceId == null
                                ? null
                                : () {
                                    setDialogState(() {
                                      if (checked) {
                                        selected.remove(faceId);
                                      } else {
                                        selected.add(faceId);
                                      }
                                    });
                                  },
                            child: Column(
                              children: [
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                        child: thumbnail.existsSync()
                                            ? Image.file(
                                                thumbnail,
                                                fit: BoxFit.cover,
                                              )
                                            : const Icon(
                                                Icons.face_outlined,
                                                size: 48,
                                              ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Checkbox(
                                          value: checked,
                                          onChanged: faceId == null
                                              ? null
                                              : (_) {
                                                  setDialogState(() {
                                                    if (checked) {
                                                      selected.remove(faceId);
                                                    } else {
                                                      selected.add(faceId);
                                                    }
                                                  });
                                                },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        candidate.confidenceLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${(candidate.similarity * 100).toStringAsFixed(1)}% similarity',
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
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(<int>{}),
                          child: const Text('Skip Matches'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.of(
                                  dialogContext,
                                ).pop(Set<int>.from(selected)),
                          icon: const Icon(Icons.check),
                          label: Text(
                            'Confirm ${selected.length} '
                            '${selected.length == 1 ? 'Match' : 'Matches'}',
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

    return result ?? <int>{};
  }

  Future<void> _markUnknown(DetectedFaceRecord face) async {
    final faceId = face.id;
    if (faceId == null || _saving) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Mark as Never Identifiable?'),
            content: const Text(
              'Use this when you have reviewed the face and do not expect to '
              'ever identify the person. It will leave the active '
              'Needs Identification queue, but can be restored later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Never Identifiable'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _saving = true);
    try {
      await _databaseHelper.markFaceUnknown(faceId);
      if (!mounted) return;
      setState(() {
        _unidentified.removeWhere((item) => item.id == faceId);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _identifyFace(DetectedFaceRecord face) async {
    if (_saving) return;

    final personName = await _askForName(face);
    if (personName == null || personName.trim().isEmpty) return;

    final cleanName = personName.trim();
    final faceId = face.id;
    if (faceId == null) return;

    setState(() => _saving = true);

    try {
      // Confirm the reference face first. The user's identification is the
      // source of truth; similarity is only used afterward to find candidates.
      await _databaseHelper.confirmFaceGroup(
        faceIds: [faceId],
        personName: cleanName,
      );
      await _addPersonToPhoto(face.photoFilePath, cleanName);

      final reference = _asConfirmed(face, cleanName);

      if (!mounted) return;
      setState(() {
        _knownFaces = [..._knownFaces, reference];
        _unidentified.removeWhere((item) => item.id == faceId);
      });

      final candidates = _findCandidates(reference);

      if (!mounted) return;
      setState(() => _saving = false);

      final selectedIds = await _reviewMatches(cleanName, candidates);
      if (selectedIds.isEmpty) return;

      final selectedFaces = _unidentified
          .where(
            (candidate) =>
                candidate.id != null && selectedIds.contains(candidate.id),
          )
          .toList();

      setState(() => _saving = true);

      await _databaseHelper.confirmFaceGroup(
        faceIds: selectedIds.toList(),
        personName: cleanName,
      );

      for (final photoPath
          in selectedFaces.map((item) => item.photoFilePath).toSet()) {
        await _addPersonToPhoto(photoPath, cleanName);
      }

      final confirmedMatches = selectedFaces
          .map((item) => _asConfirmed(item, cleanName))
          .toList();

      if (!mounted) return;

      setState(() {
        _knownFaces = [..._knownFaces, ...confirmedMatches];
        _unidentified.removeWhere(
          (item) => item.id != null && selectedIds.contains(item.id),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selectedIds.length + 1} faces identified as $cleanName.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSourcePhoto(DetectedFaceRecord face) async {
    final file = File(face.photoFilePath);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 1000,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.photo_outlined),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Source Photo',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
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
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : const Center(child: Text('Original photo not found.')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  face.photoFilePath,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
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

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SelectableText(
            'Could not load unidentified faces.\n\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final visible = _unidentified.where((face) {
      if (_search.trim().isEmpty) return true;
      final query = _search.trim().toLowerCase();
      return face.photoFilePath.toLowerCase().contains(query);
    }).toList();

    return _unidentified.isEmpty
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.task_alt, size: 72),
                SizedBox(height: 16),
                Text(
                  'Face review complete.',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text('There are no unidentified faces waiting for review.'),
              ],
            ),
          )
        : Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.face_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Identify one face, then find matches',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'You choose the identity first. Heirloom Atlas '
                            'then searches the remaining unidentified faces '
                            'for possible matches for you to approve.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: (value) => setState(() => _search = value),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search photo path',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(18),
                  itemCount: visible.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.74,
                  ),
                  itemBuilder: (context, index) {
                    final face = visible[index];
                    final thumbnail = File(face.thumbnailPath);
                    final suggestion = _bestKnownSuggestion(face);
                    final suggestionScore = suggestion == null
                        ? null
                        : _bestKnownSimilarity(face, suggestion);

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _showSourcePhoto(face),
                              child: Container(
                                width: double.infinity,
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: thumbnail.existsSync()
                                    ? Image.file(thumbnail, fit: BoxFit.cover)
                                    : const Center(
                                        child: Icon(
                                          Icons.face_outlined,
                                          size: 58,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (suggestion != null &&
                                    suggestionScore != null) ...[
                                  Text(
                                    'Possible: $suggestion',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${(suggestionScore * 100).toStringAsFixed(1)}% similarity',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 7),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: _saving
                                            ? null
                                            : () => _identifyFace(face),
                                        icon: const Icon(
                                          Icons.badge_outlined,
                                          size: 18,
                                        ),
                                        label: const Text('Identify'),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message:
                                          'I do not expect to identify this person',
                                      child: IconButton.outlined(
                                        onPressed: _saving
                                            ? null
                                            : () => _markUnknown(face),
                                        icon: const Icon(
                                          Icons.do_not_disturb_on_outlined,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                TextButton.icon(
                                  onPressed: () => _showSourcePhoto(face),
                                  icon: const Icon(
                                    Icons.photo_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('View Source Photo'),
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
            ],
          );
  }
}

class _UnknownFacesBody extends StatefulWidget {
  const _UnknownFacesBody();

  @override
  State<_UnknownFacesBody> createState() => _UnknownFacesBodyState();
}

class _UnknownFacesBodyState extends State<_UnknownFacesBody> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<DetectedFaceRecord> _unknown = const [];
  List<DetectedFaceRecord> _knownFaces = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _databaseHelper.getUnknownFaces(),
        _databaseHelper.getConfirmedFaces(),
      ]);
      if (!mounted) return;
      setState(() {
        _unknown = List<DetectedFaceRecord>.from(results[0]);
        _knownFaces = List<DetectedFaceRecord>.from(results[1]);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _restore(DetectedFaceRecord face) async {
    final faceId = face.id;
    if (faceId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _databaseHelper.markFaceUnidentified(faceId);
      if (!mounted) return;
      setState(() => _unknown.removeWhere((item) => item.id == faceId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face restored to Needs Identification.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> get _knownNames {
    final names =
        _knownFaces
            .map((face) => face.personName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<String?> _askForName() async {
    String typed = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = typed.trim().toLowerCase();
          final suggestions = _knownNames
              .where(
                (name) => query.isEmpty || name.toLowerCase().contains(query),
              )
              .take(8)
              .toList();

          void submit() {
            final clean = typed.trim();
            if (clean.isEmpty) return;
            FocusScope.of(dialogContext).unfocus();
            Navigator.pop(dialogContext, clean);
          }

          return AlertDialog(
            title: const Text('Identify person'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Person name',
                      hintText: 'Start typing a name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      typed = value;
                      setDialogState(() {});
                    },
                    onSubmitted: (_) => submit(),
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
                              onPressed: () =>
                                  Navigator.pop(dialogContext, name),
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: typed.trim().isEmpty ? null : submit,
                child: const Text('Identify'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _identify(DetectedFaceRecord face) async {
    final faceId = face.id;
    if (faceId == null || _saving) return;
    final name = await _askForName();
    if (name == null || name.trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      final cleanName = name.trim();
      await _databaseHelper.confirmFaceGroup(
        faceIds: [faceId],
        personName: cleanName,
      );

      final metadata = await _databaseHelper.getPhotoCatalogMetadata(
        face.photoFilePath,
      );
      if (!metadata.people.contains(cleanName)) {
        await _databaseHelper.savePhotoCatalogMetadata(
          PhotoCatalogMetadata(
            filePath: metadata.filePath,
            people: <String>{...metadata.people, cleanName}.toList(),
            tags: metadata.tags,
            approximateDate: metadata.approximateDate,
            location: metadata.location,
            description: metadata.description,
            notes: metadata.notes,
          ),
        );
      }

      if (!mounted) return;
      setState(() => _unknown.removeWhere((item) => item.id == faceId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Face identified as $cleanName.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSourcePhoto(DetectedFaceRecord face) async {
    final file = File(face.photoFilePath);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 1000,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.photo_outlined),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Source Photo',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
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
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : const Center(child: Text('Original photo not found.')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  face.photoFilePath,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SelectableText(
            'Could not load Never Identifiable faces.\n\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_unknown.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 72),
            SizedBox(height: 16),
            Text(
              'No Never Identifiable faces.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'People you deliberately mark Never Identifiable will appear here.',
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Row(
            children: [
              const Icon(Icons.help_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_unknown.length} reviewed ${_unknown.length == 1 ? 'face' : 'faces'} '
                  'marked Never Identifiable. These do not count as people who still need identification.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(18),
            itemCount: _unknown.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.68,
            ),
            itemBuilder: (context, index) {
              final face = _unknown[index];
              final thumbnail = File(face.thumbnailPath);
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showSourcePhoto(face),
                        child: Container(
                          width: double.infinity,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: thumbnail.existsSync()
                              ? Image.file(thumbnail, fit: BoxFit.cover)
                              : const Center(
                                  child: Icon(Icons.face_outlined, size: 58),
                                ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Never Identifiable',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : () => _identify(face),
                            icon: const Icon(Icons.badge_outlined, size: 18),
                            label: const Text('Identify'),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : () => _restore(face),
                            icon: const Icon(Icons.undo, size: 18),
                            label: const Text('Needs Identification'),
                          ),
                          TextButton.icon(
                            onPressed: () => _showSourcePhoto(face),
                            icon: const Icon(Icons.photo_outlined, size: 18),
                            label: const Text('View Source Photo'),
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
      ],
    );
  }
}
