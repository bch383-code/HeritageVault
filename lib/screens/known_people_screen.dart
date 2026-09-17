import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../database/database_helper.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';
import '../models/family_person.dart';
import '../services/face_recognition_service.dart';

class _PersonMatchCandidate {
  final DetectedFaceRecord face;
  final double similarity;

  const _PersonMatchCandidate({required this.face, required this.similarity});
}

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

  final TextEditingController _peopleSearchController = TextEditingController();
  String _peopleSort = 'Name';
  List<Map<String, Object?>> _personGroups = const [];
  String _selectedGroupFilter = 'All';
  Map<String, FamilyPerson> _familyTreeLinks = <String, FamilyPerson>{};
  Map<String, int> _likelyCounts = <String, int>{};
  Map<String, int> _possibleCounts = <String, int>{};
  int _unidentifiedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _peopleSearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _databaseHelper.getConfirmedFaces(),
        _databaseHelper.getIndexedPhotos(),
        _databaseHelper.getAllPhotoCatalogMetadata(),
        _databaseHelper.getPersonGroups(),
        _databaseHelper.getPhotoPersonFamilyTreeLinks(),
        _databaseHelper.getUnconfirmedFaces(),
      ]);

      final faces = results[0] as List<DetectedFaceRecord>;
      final photos = results[1] as List<VaultPhoto>;
      final catalogRecords = results[2] as List<PhotoCatalogMetadata>;
      final personGroups = results[3] as List<Map<String, Object?>>;
      final linkIds = results[4] as Map<String, int>;
      final unidentifiedFaces = results[5] as List<DetectedFaceRecord>;
      final familyLinks = <String, FamilyPerson>{};
      for (final entry in linkIds.entries) {
        final familyPerson = await _databaseHelper.getFamilyPerson(entry.value);
        if (familyPerson != null) {
          familyLinks[entry.key] = familyPerson;
        }
      }

      final grouped = <String, List<DetectedFaceRecord>>{};
      for (final face in faces) {
        grouped.putIfAbsent(face.personName, () => []).add(face);
      }

      final sortedEntries = grouped.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

      final likelyCounts = <String, int>{};
      final possibleCounts = <String, int>{};

      for (final entry in grouped.entries) {
        final rejectedIds = await _databaseHelper.getRejectedFaceIdsForPerson(
          entry.key,
        );
        var likely = 0;
        var possible = 0;
        for (final candidate in unidentifiedFaces) {
          final candidateId = candidate.id;
          if (candidateId != null && rejectedIds.contains(candidateId)) {
            continue;
          }

          final similarity = FaceRecognitionService.consensusSimilarity(
            candidate.embedding,
            entry.value,
          );
          if (similarity >= 0.78) {
            likely++;
          } else if (similarity >= 0.64) {
            possible++;
          }
        }
        likelyCounts[entry.key] = likely;
        possibleCounts[entry.key] = possible;
      }

      if (!mounted) return;

      setState(() {
        _people = {for (final entry in sortedEntries) entry.key: entry.value};
        _photos = photos;
        _catalogByPath = {
          for (final record in catalogRecords) record.filePath: record,
        };
        _personGroups = personGroups;
        _familyTreeLinks = familyLinks;
        _likelyCounts = likelyCounts;
        _possibleCounts = possibleCounts;
        _unidentifiedCount = unidentifiedFaces.length;
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

  List<MapEntry<String, List<DetectedFaceRecord>>> get _visiblePeople {
    final query = _peopleSearchController.text.trim().toLowerCase();

    final entries = _people.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query);
    }).toList();

    switch (_peopleSort) {
      case 'Most Photos':
        entries.sort((a, b) {
          final aPhotos = a.value
              .map((face) => face.photoFilePath)
              .toSet()
              .length;
          final bPhotos = b.value
              .map((face) => face.photoFilePath)
              .toSet()
              .length;
          final countCompare = bPhotos.compareTo(aPhotos);
          if (countCompare != 0) return countCompare;
          return a.key.toLowerCase().compareTo(b.key.toLowerCase());
        });
        break;
      case 'Most Faces':
        entries.sort((a, b) {
          final countCompare = b.value.length.compareTo(a.value.length);
          if (countCompare != 0) return countCompare;
          return a.key.toLowerCase().compareTo(b.key.toLowerCase());
        });
        break;
      default:
        entries.sort(
          (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
        );
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: 'Refresh People',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: SelectableText(
                  'Could not load people.\n\n$_error',
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
                    'No identified people yet.',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Identify faces to start building your People collection.',
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _peopleSearchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Search people...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _peopleSearchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear',
                                      onPressed: () {
                                        _peopleSearchController.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _createGroupFlow,
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Create Group'),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String>(
                            initialValue: _peopleSort,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Sort',
                              border: OutlineInputBorder(),
                            ),
                            items: const ['Name', 'Most Photos', 'Most Faces']
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _peopleSort = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_personGroups.isNotEmpty)
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SizedBox(
                      width: double.infinity,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text(
                                'Groups:',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('All People'),
                              selected: _selectedGroupFilter == 'All',
                              onSelected: (_) {
                                setState(() => _selectedGroupFilter = 'All');
                              },
                            ),
                            const SizedBox(width: 6),
                            ..._personGroups.map((group) {
                              final id = (group['id'] as num).toInt();
                              final name = group['name'] as String? ?? 'Group';
                              final peopleCount =
                                  (group['people_count'] as num?)?.toInt() ?? 0;
                              final photoCount =
                                  (group['photo_count'] as num?)?.toInt() ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  avatar: const Icon(
                                    Icons.groups_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    '$name ($peopleCount • $photoCount photos)',
                                  ),
                                  onPressed: () =>
                                      _openGroup(id: id, name: name),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: [
                      _overviewStat(
                        context,
                        icon: Icons.people_outline,
                        label: 'People',
                        value: '${_people.length}',
                      ),
                      const SizedBox(width: 10),
                      _overviewStat(
                        context,
                        icon: Icons.check_circle_outline,
                        label: 'Confirmed Faces',
                        value:
                            '${_people.values.fold<int>(0, (sum, faces) => sum + faces.length)}',
                      ),
                      const SizedBox(width: 10),
                      _overviewStat(
                        context,
                        icon: Icons.person_search_outlined,
                        label: 'Likely',
                        value:
                            '${_likelyCounts.values.fold<int>(0, (sum, value) => sum + value)}',
                        accent: const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 10),
                      _overviewStat(
                        context,
                        icon: Icons.help_outline,
                        label: 'Possible',
                        value:
                            '${_possibleCounts.values.fold<int>(0, (sum, value) => sum + value)}',
                        accent: const Color(0xFFF9A825),
                      ),
                      const SizedBox(width: 10),
                      _overviewStat(
                        context,
                        icon: Icons.face_retouching_off_outlined,
                        label: 'Unidentified',
                        value: '$_unidentifiedCount',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _visiblePeople.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 320,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.02,
                        ),
                    itemBuilder: (context, index) {
                      final entry = _visiblePeople[index];
                      final name = entry.key;
                      final faces = entry.value;
                      final photoCount = faces
                          .map((face) => face.photoFilePath)
                          .toSet()
                          .length;

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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  child: thumbnail.existsSync()
                                      ? Image.file(thumbnail, fit: BoxFit.cover)
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
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 7),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              _reviewCountChip(
                                                label: 'Likely',
                                                count: _likelyCounts[name] ?? 0,
                                                color: const Color(0xFF2E7D32),
                                                onTap:
                                                    (_likelyCounts[name] ??
                                                            0) ==
                                                        0
                                                    ? null
                                                    : () =>
                                                          _showPersonRecommendationQueue(
                                                            personName: name,
                                                            referenceFaces:
                                                                faces,
                                                            likelyOnly: true,
                                                          ),
                                              ),
                                              _reviewCountChip(
                                                label: 'Possible',
                                                count:
                                                    _possibleCounts[name] ?? 0,
                                                color: const Color(0xFFF9A825),
                                                onTap:
                                                    (_possibleCounts[name] ??
                                                            0) ==
                                                        0
                                                    ? null
                                                    : () =>
                                                          _showPersonRecommendationQueue(
                                                            personName: name,
                                                            referenceFaces:
                                                                faces,
                                                            likelyOnly: false,
                                                          ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 7),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.account_tree_outlined,
                                                size: 14,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  _familyTreeLinks[name] == null
                                                      ? 'Family Tree link: not set'
                                                      : 'Family Tree: ${_familyPersonDisplayName(_familyTreeLinks[name]!)}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                              ),
                                            ],
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
                ),
              ],
            ),
    );
  }

  Widget _overviewStat(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? accent,
  }) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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

  Widget _reviewCountChip({
    required String label,
    required int count,
    required Color color,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (onTap == null) return child;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: child,
    );
  }

  Future<void> _showPersonRecommendationQueue({
    required String personName,
    required List<DetectedFaceRecord> referenceFaces,
    required bool likelyOnly,
  }) async {
    var currentReferenceFaces = [...referenceFaces];
    final selectedFaceIds = <int>{};
    var remaining = <_PersonMatchCandidate>[];
    var changed = false;

    Future<List<_PersonMatchCandidate>> refreshCandidates() async {
      final unidentified = await _databaseHelper.getUnconfirmedFaces();
      final rejectedIds = await _databaseHelper.getRejectedFaceIdsForPerson(
        personName,
      );

      final refreshed = <_PersonMatchCandidate>[];

      for (final candidate in unidentified) {
        final candidateId = candidate.id;
        if (candidateId != null && rejectedIds.contains(candidateId)) {
          continue;
        }

        final similarity = FaceRecognitionService.consensusSimilarity(
          candidate.embedding,
          currentReferenceFaces,
        );

        final matchesBucket = likelyOnly
            ? similarity >= 0.78
            : similarity >= 0.64 && similarity < 0.78;

        if (matchesBucket) {
          refreshed.add(
            _PersonMatchCandidate(face: candidate, similarity: similarity),
          );
        }
      }

      refreshed.sort((a, b) => b.similarity.compareTo(a.similarity));
      return refreshed;
    }

    remaining = await refreshCandidates();

    if (!mounted) return;

    if (remaining.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No ${likelyOnly ? 'likely' : 'possible'} matches remain for $personName.',
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bucketLabel = likelyOnly
              ? 'Likely Matches'
              : 'Possible Matches';
          final bucketColor = likelyOnly
              ? const Color(0xFF2E7D32)
              : const Color(0xFFF9A825);

          Future<void> refreshQueue() async {
            final latestConfirmed = await _databaseHelper.getConfirmedFaces();
            currentReferenceFaces = latestConfirmed
                .where((face) => face.personName == personName)
                .toList();

            final refreshed = await refreshCandidates();

            if (!mounted || !dialogContext.mounted) return;

            setDialogState(() {
              remaining = refreshed;
              selectedFaceIds.removeWhere(
                (id) => !remaining.any((candidate) => candidate.face.id == id),
              );
            });
          }

          return Dialog(
            child: SizedBox(
              width: 1050,
              height: 760,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                    child: Row(
                      children: [
                        Icon(
                          likelyOnly
                              ? Icons.check_circle_outline
                              : Icons.help_outline,
                          color: bucketColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$bucketLabel for $personName',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${remaining.length} face'
                                '${remaining.length == 1 ? '' : 's'} to review • '
                                'updates automatically as matches are confirmed',
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh matches',
                          onPressed: refreshQueue,
                          icon: const Icon(Icons.refresh),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          '${selectedFaceIds.length} selected',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: remaining.isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    selectedFaceIds
                                      ..clear()
                                      ..addAll(
                                        remaining
                                            .map(
                                              (candidate) => candidate.face.id,
                                            )
                                            .whereType<int>(),
                                      );
                                  });
                                },
                          child: const Text('Select All'),
                        ),
                        TextButton(
                          onPressed: selectedFaceIds.isEmpty
                              ? null
                              : () => setDialogState(selectedFaceIds.clear),
                          child: const Text('Clear'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: selectedFaceIds.isEmpty
                              ? null
                              : () async {
                                  final selected = remaining
                                      .where(
                                        (candidate) =>
                                            candidate.face.id != null &&
                                            selectedFaceIds.contains(
                                              candidate.face.id,
                                            ),
                                      )
                                      .toList();

                                  for (final candidate in selected) {
                                    final faceId = candidate.face.id;
                                    if (faceId == null) continue;

                                    await _databaseHelper.rejectFaceMatch(
                                      personName: personName,
                                      faceId: faceId,
                                    );
                                  }

                                  selectedFaceIds.clear();
                                  changed = true;
                                  await _load();
                                  await refreshQueue();
                                },
                          icon: const Icon(Icons.person_off_outlined),
                          label: Text(
                            'Not This Person (${selectedFaceIds.length})',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: selectedFaceIds.isEmpty
                              ? null
                              : () async {
                                  final selected = remaining
                                      .where(
                                        (candidate) =>
                                            candidate.face.id != null &&
                                            selectedFaceIds.contains(
                                              candidate.face.id,
                                            ),
                                      )
                                      .toList();

                                  for (final candidate in selected) {
                                    await _confirmPossibleMatch(
                                      personName: personName,
                                      candidate: candidate,
                                    );
                                    final faceId = candidate.face.id;
                                    if (faceId != null) {
                                      await _databaseHelper
                                          .clearFaceMatchRejection(
                                            personName: personName,
                                            faceId: faceId,
                                          );
                                    }
                                  }

                                  selectedFaceIds.clear();
                                  changed = true;
                                  await _load();
                                  await refreshQueue();
                                },
                          icon: const Icon(Icons.done_all),
                          label: Text(
                            'Confirm Selected (${selectedFaceIds.length})',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: remaining.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 54,
                                  color: bucketColor,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No additional matches right now.',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'If another confirmation changes the model '
                                  'consensus, new matches will appear here automatically.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: remaining.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 250,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  childAspectRatio: 0.74,
                                ),
                            itemBuilder: (context, index) {
                              final candidate = remaining[index];
                              final face = candidate.face;
                              final thumb = File(face.thumbnailPath);
                              final source = File(face.photoFilePath);
                              final faceId = face.id;
                              final selected =
                                  faceId != null &&
                                  selectedFaceIds.contains(faceId);

                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: InkWell(
                                              onTap: faceId == null
                                                  ? null
                                                  : () {
                                                      setDialogState(() {
                                                        if (selected) {
                                                          selectedFaceIds
                                                              .remove(faceId);
                                                        } else {
                                                          selectedFaceIds.add(
                                                            faceId,
                                                          );
                                                        }
                                                      });
                                                    },
                                              child: Container(
                                                width: double.infinity,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                child: thumb.existsSync()
                                                    ? Image.file(
                                                        thumb,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : const Center(
                                                        child: Icon(
                                                          Icons.face_outlined,
                                                          size: 60,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  '${(candidate.similarity * 100).toStringAsFixed(1)}% similarity',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: bucketColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  path.basename(source.path),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                const SizedBox(height: 8),
                                                FilledButton.icon(
                                                  onPressed: () async {
                                                    await _confirmPossibleMatch(
                                                      personName: personName,
                                                      candidate: candidate,
                                                    );

                                                    final candidateFaceId =
                                                        candidate.face.id;
                                                    if (candidateFaceId !=
                                                        null) {
                                                      await _databaseHelper
                                                          .clearFaceMatchRejection(
                                                            personName:
                                                                personName,
                                                            faceId:
                                                                candidateFaceId,
                                                          );
                                                      selectedFaceIds.remove(
                                                        candidateFaceId,
                                                      );
                                                    }

                                                    changed = true;
                                                    await _load();
                                                    await refreshQueue();
                                                  },
                                                  icon: const Icon(
                                                    Icons.check_circle_outline,
                                                  ),
                                                  label: const Text(
                                                    'Confirm Match',
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    final candidateFaceId =
                                                        candidate.face.id;
                                                    if (candidateFaceId !=
                                                        null) {
                                                      await _databaseHelper
                                                          .rejectFaceMatch(
                                                            personName:
                                                                personName,
                                                            faceId:
                                                                candidateFaceId,
                                                          );
                                                      selectedFaceIds.remove(
                                                        candidateFaceId,
                                                      );
                                                    }

                                                    changed = true;
                                                    await _load();
                                                    await refreshQueue();
                                                  },
                                                  icon: const Icon(
                                                    Icons.close,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Not This Person',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Checkbox(
                                          value: selected,
                                          onChanged: faceId == null
                                              ? null
                                              : (checked) {
                                                  setDialogState(() {
                                                    if (checked == true) {
                                                      selectedFaceIds.add(
                                                        faceId,
                                                      );
                                                    } else {
                                                      selectedFaceIds.remove(
                                                        faceId,
                                                      );
                                                    }
                                                  });
                                                },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (changed) {
      await _load();
    }
  }

  Future<void> _createGroupFlow() async {
    final nameController = TextEditingController();
    final selectedPeople = <String>{};
    final selectedPhotoPaths = <String>{};
    var step = 0;
    var personSearch = '';
    var photoSearch = '';

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final people =
              _people.keys.where((name) {
                  final query = personSearch.trim().toLowerCase();
                  return query.isEmpty || name.toLowerCase().contains(query);
                }).toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final candidatePhotos = <VaultPhoto>[];
          final seenPaths = <String>{};
          for (final personName in selectedPeople) {
            for (final photo in _photosForPerson(personName)) {
              if (seenPaths.add(photo.filePath)) {
                candidatePhotos.add(photo);
              }
            }
          }
          candidatePhotos.sort(
            (a, b) =>
                a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
          );

          final visiblePhotos = candidatePhotos.where((photo) {
            final query = photoSearch.trim().toLowerCase();
            if (query.isEmpty) return true;
            final metadata = _catalogByPath[photo.filePath];
            return [
              photo.fileName,
              photo.relativeFolder,
              metadata?.approximateDate ?? '',
              metadata?.location ?? '',
              metadata?.description ?? '',
            ].join(' ').toLowerCase().contains(query);
          }).toList();

          String title() {
            switch (step) {
              case 0:
                return 'Create Group — Name';
              case 1:
                return 'Create Group — Select People';
              case 2:
                return 'Create Group — Select Photos';
              default:
                return 'Create Group — Review';
            }
          }

          Future<void> next() async {
            if (step == 0 && nameController.text.trim().isEmpty) return;
            if (step < 3) {
              setDialogState(() => step++);
              return;
            }

            try {
              await _databaseHelper.createPersonGroup(
                name: nameController.text.trim(),
                personNames: selectedPeople,
                photoFilePaths: selectedPhotoPaths,
              );
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            } catch (error) {
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('Could not create group: $error')),
              );
            }
          }

          Widget content;
          if (step == 0) {
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Give this group a name such as College, Childhood, '
                  'Friends, Parents, Family, Kids, Work, or anything you want.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => next(),
                ),
              ],
            );
          } else if (step == 1) {
            content = Column(
              children: [
                TextField(
                  onChanged: (value) {
                    setDialogState(() => personSearch = value);
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search identified people...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${selectedPeople.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          selectedPeople.addAll(people);
                        });
                      },
                      child: const Text('Select All Shown'),
                    ),
                    TextButton(
                      onPressed: selectedPeople.isEmpty
                          ? null
                          : () => setDialogState(selectedPeople.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.builder(
                    itemCount: people.length,
                    itemBuilder: (context, index) {
                      final name = people[index];
                      final faces =
                          _people[name] ?? const <DetectedFaceRecord>[];
                      final thumb = faces.isEmpty
                          ? null
                          : File(faces.first.thumbnailPath);
                      return CheckboxListTile(
                        value: selectedPeople.contains(name),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              selectedPeople.add(name);
                            } else {
                              selectedPeople.remove(name);
                            }
                          });
                        },
                        secondary: CircleAvatar(
                          backgroundImage: thumb != null && thumb.existsSync()
                              ? FileImage(thumb)
                              : null,
                          child: thumb != null && thumb.existsSync()
                              ? null
                              : const Icon(Icons.person_outline),
                        ),
                        title: Text(name),
                        subtitle: Text(
                          '${_photosForPerson(name).length} photos',
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          } else if (step == 2) {
            content = Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selectedPeople.isEmpty
                        ? 'No people selected. You can skip photos and add '
                              'them later.'
                        : 'Choose any photos you want attached to this group. '
                              'This step is optional.',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) {
                    setDialogState(() => photoSearch = value);
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search photos...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${selectedPhotoPaths.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: visiblePhotos.isEmpty
                          ? null
                          : () {
                              setDialogState(() {
                                selectedPhotoPaths.addAll(
                                  visiblePhotos.map((photo) => photo.filePath),
                                );
                              });
                            },
                      child: const Text('Select All Shown'),
                    ),
                    TextButton(
                      onPressed: selectedPhotoPaths.isEmpty
                          ? null
                          : () => setDialogState(selectedPhotoPaths.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: visiblePhotos.isEmpty
                      ? const Center(
                          child: Text(
                            'Select one or more people to see their photos.',
                          ),
                        )
                      : GridView.builder(
                          itemCount: visiblePhotos.length,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 190,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.9,
                              ),
                          itemBuilder: (context, index) {
                            final photo = visiblePhotos[index];
                            final file = File(photo.filePath);
                            final selected = selectedPhotoPaths.contains(
                              photo.filePath,
                            );
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedPhotoPaths.remove(photo.filePath);
                                    } else {
                                      selectedPhotoPaths.add(photo.filePath);
                                    }
                                  });
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Column(
                                      children: [
                                        Expanded(
                                          child: file.existsSync()
                                              ? Image.file(
                                                  file,
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 400,
                                                )
                                              : const Center(
                                                  child: Icon(
                                                    Icons
                                                        .image_not_supported_outlined,
                                                  ),
                                                ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Text(
                                            photo.fileName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: CircleAvatar(
                                        radius: 15,
                                        child: Icon(
                                          selected ? Icons.check : Icons.add,
                                          size: 18,
                                        ),
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
            );
          } else {
            final selectedNames = selectedPeople.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            content = ListView(
              children: [
                Text(
                  nameController.text.trim(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${selectedNames.length} people',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (selectedNames.isEmpty)
                  const Text('No people selected yet.')
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selectedNames
                        .map((name) => Chip(label: Text(name)))
                        .toList(),
                  ),
                const SizedBox(height: 18),
                Text(
                  '${selectedPhotoPaths.length} photos',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'You can add or change group members and photos later.',
                ),
              ],
            );
          }

          return Dialog(
            child: SizedBox(
              width: 980,
              height: 720,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title(),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text('${step + 1} of 4'),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Cancel',
                          onPressed: () => Navigator.pop(dialogContext, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: content,
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        if (step > 0)
                          OutlinedButton.icon(
                            onPressed: () => setDialogState(() => step--),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Back'),
                          ),
                        const Spacer(),
                        if (step == 2)
                          TextButton(
                            onPressed: () => setDialogState(() => step++),
                            child: const Text('Skip Photos'),
                          ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed:
                              step == 0 && nameController.text.trim().isEmpty
                              ? null
                              : next,
                          icon: Icon(
                            step == 3 ? Icons.check : Icons.arrow_forward,
                          ),
                          label: Text(step == 3 ? 'Save Group' : 'Next'),
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

    nameController.dispose();

    if (saved == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Person group created.')));
    }
  }

  Future<void> _openGroup({required int id, required String name}) async {
    final results = await Future.wait([
      _databaseHelper.getPersonNamesForGroup(id),
      _databaseHelper.getPhotoPathsForPersonGroup(id),
    ]);
    if (!mounted) return;

    final personNames = results[0];
    final photoPaths = results[1].toSet();
    final groupPhotos =
        _photos.where((photo) => photoPaths.contains(photo.filePath)).toList()
          ..sort(
            (a, b) =>
                a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
          );

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
                    const Icon(Icons.groups_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '${personNames.length} people • '
                            '${groupPhotos.length} photos',
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
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Text(
                      'People',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (personNames.isEmpty)
                      const Text('No people have been added to this group.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: personNames.map((personName) {
                          return ActionChip(
                            avatar: const Icon(Icons.person_outline, size: 18),
                            label: Text(personName),
                            onPressed: () {
                              final faces = _people[personName];
                              if (faces == null || faces.isEmpty) return;
                              Navigator.pop(dialogContext);
                              _showPersonPhotos(personName, faces);
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Selected Photos',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (groupPhotos.isEmpty)
                      const Text('No photos were selected for this group.')
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: groupPhotos.length,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 230,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                        itemBuilder: (context, index) {
                          final photo = groupPhotos[index];
                          final file = File(photo.filePath);
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                Expanded(
                                  child: file.existsSync()
                                      ? Image.file(
                                          file,
                                          fit: BoxFit.cover,
                                          cacheWidth: 500,
                                        )
                                      : const Center(
                                          child: Icon(
                                            Icons.image_not_supported_outlined,
                                          ),
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    photo.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

  List<VaultPhoto> _photosForPerson(String name) {
    final matchedPaths = <String>{};

    // Primary source: Heirloom Atlas People metadata.
    for (final entry in _catalogByPath.entries) {
      if (entry.value.people.contains(name)) {
        matchedPaths.add(entry.key);
      }
    }

    // Also include any photo with a confirmed face for this person.
    final confirmedFaces = _people[name] ?? const <DetectedFaceRecord>[];
    matchedPaths.addAll(confirmedFaces.map((face) => face.photoFilePath));

    final result = _photos
        .where((photo) => matchedPaths.contains(photo.filePath))
        .toList();

    result.sort(
      (a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
    );

    return result;
  }

  Future<List<_PersonMatchCandidate>> _findPossibleMatches(
    List<DetectedFaceRecord> referenceFaces,
  ) async {
    if (referenceFaces.isEmpty) return const [];

    final unidentified = await _databaseHelper.getUnconfirmedFaces();
    final matches = <_PersonMatchCandidate>[];

    for (final candidate in unidentified) {
      final similarity = FaceRecognitionService.consensusSimilarity(
        candidate.embedding,
        referenceFaces,
      );

      // Keep this broad enough for manual review, but require agreement
      // across confirmed examples when more than one is available.
      if (similarity >= 0.64) {
        matches.add(
          _PersonMatchCandidate(face: candidate, similarity: similarity),
        );
      }
    }

    matches.sort((a, b) => b.similarity.compareTo(a.similarity));

    return matches;
  }

  Future<void> _confirmPossibleMatch({
    required String personName,
    required _PersonMatchCandidate candidate,
  }) async {
    final id = candidate.face.id;
    if (id == null) return;

    await _databaseHelper.confirmFaceGroup(
      faceIds: [id],
      personName: personName,
    );

    final existing = await _databaseHelper.getPhotoCatalogMetadata(
      candidate.face.photoFilePath,
    );

    final updated = PhotoCatalogMetadata(
      filePath: existing.filePath,
      people: <String>{...existing.people, personName}.toList(),
      tags: existing.tags,
      approximateDate: existing.approximateDate,
      location: existing.location,
      description: existing.description,
      notes: existing.notes,
    );

    await _databaseHelper.savePhotoCatalogMetadata(updated);

    final confirmedFace = DetectedFaceRecord(
      id: candidate.face.id,
      photoFilePath: candidate.face.photoFilePath,
      faceIndex: candidate.face.faceIndex,
      left: candidate.face.left,
      top: candidate.face.top,
      width: candidate.face.width,
      height: candidate.face.height,
      detectionScore: candidate.face.detectionScore,
      embedding: candidate.face.embedding,
      thumbnailPath: candidate.face.thumbnailPath,
      personName: personName,
      confirmed: true,
    );

    if (!mounted) return;

    setState(() {
      _catalogByPath[candidate.face.photoFilePath] = updated;
      _people.putIfAbsent(personName, () => []).add(confirmedFace);
    });
  }

  Future<bool> _showPossibleMatches(
    String personName,
    List<DetectedFaceRecord> referenceFaces,
  ) async {
    final matches = await _findPossibleMatches(referenceFaces);

    if (!mounted) return false;

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No plausible unidentified matches were found for $personName.',
          ),
        ),
      );
      return false;
    }

    var changed = false;
    final remaining = [...matches];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: SizedBox(
            width: 1050,
            height: 760,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.person_search_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Possible Matches for $personName',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${remaining.length} unidentified face'
                              '${remaining.length == 1 ? '' : 's'} at 55%+ similarity',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'These are suggestions only. Confirm a face only when '
                      'you recognize the person.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: remaining.isEmpty
                      ? const Center(
                          child: Text('No more candidates in this search.'),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: remaining.length,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 240,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.76,
                              ),
                          itemBuilder: (context, index) {
                            final candidate = remaining[index];
                            final face = candidate.face;
                            final thumbnail = File(face.thumbnailPath);
                            final source = File(face.photoFilePath);

                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Container(
                                      width: double.infinity,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      child: thumbnail.existsSync()
                                          ? Image.file(
                                              thumbnail,
                                              fit: BoxFit.cover,
                                            )
                                          : const Center(
                                              child: Icon(
                                                Icons.face_outlined,
                                                size: 60,
                                              ),
                                            ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          '${(candidate.similarity * 100).toStringAsFixed(1)}% similarity',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          path.basename(source.path),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 8),
                                        FilledButton.icon(
                                          onPressed: () async {
                                            await _confirmPossibleMatch(
                                              personName: personName,
                                              candidate: candidate,
                                            );

                                            if (!mounted) return;

                                            setDialogState(() {
                                              remaining.remove(candidate);
                                              changed = true;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                          label: const Text('Confirm Match'),
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
            ),
          ),
        ),
      ),
    );

    return changed;
  }

  String _familyPersonDisplayName(FamilyPerson person) {
    final parts = <String>[
      person.firstName.trim(),
      person.middleName.trim(),
      person.lastName.trim(),
    ].where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? 'Unnamed person' : parts.join(' ');
  }

  String _familyPersonLifeText(FamilyPerson person) {
    final birth = person.birthDate.trim();
    final death = person.deathDate.trim();
    if (birth.isEmpty && death.isEmpty) return '';
    return '${birth.isEmpty ? '?' : birth}–${death.isEmpty ? 'present' : death}';
  }

  Future<bool> _manageFamilyTreeLink(String photoPersonName) async {
    final current = _familyTreeLinks[photoPersonName];

    if (current != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Family Tree Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$photoPersonName is linked to:'),
              const SizedBox(height: 8),
              Text(
                _familyPersonDisplayName(current),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (_familyPersonLifeText(current).isNotEmpty)
                Text(_familyPersonLifeText(current)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'remove'),
              child: const Text('Remove Link'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'change'),
              child: const Text('Change Link'),
            ),
          ],
        ),
      );

      if (action == null) return false;
      if (action == 'remove') {
        await _databaseHelper.removeFamilyTreeLinkForPhotoPerson(
          photoPersonName,
        );
        if (mounted) {
          setState(() => _familyTreeLinks.remove(photoPersonName));
        }
        return true;
      }
    }

    final selected = await _pickFamilyTreePerson(
      title: current == null
          ? 'Link $photoPersonName to Family Tree'
          : 'Change Family Tree Link',
    );
    if (selected == null || selected.id == null) return false;

    await _databaseHelper.setFamilyTreeLinkForPhotoPerson(
      personName: photoPersonName,
      familyPersonId: selected.id!,
    );
    if (mounted) {
      setState(() => _familyTreeLinks[photoPersonName] = selected);
    }
    return true;
  }

  Future<FamilyPerson?> _pickFamilyTreePerson({required String title}) async {
    final familyPeople = await _databaseHelper.getFamilyPeople();
    if (!mounted) return null;

    if (familyPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No people are in the Family Tree yet.')),
      );
      return null;
    }

    var search = '';
    return showDialog<FamilyPerson>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = search.trim().toLowerCase();
          final visible = familyPeople.where((person) {
            if (query.isEmpty) return true;
            return [
              _familyPersonDisplayName(person),
              person.birthName,
              person.birthDate,
              person.birthPlace,
              person.deathDate,
              person.deathPlace,
            ].join(' ').toLowerCase().contains(query);
          }).toList();

          return Dialog(
            child: SizedBox(
              width: 720,
              height: 680,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.account_tree_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
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
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) =>
                          setDialogState(() => search = value),
                      decoration: const InputDecoration(
                        hintText: 'Search Family Tree people...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('No matching people.'))
                        : ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final person = visible[index];
                              final life = _familyPersonLifeText(person);
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person_outline),
                                ),
                                title: Text(_familyPersonDisplayName(person)),
                                subtitle: Text(
                                  [
                                    if (life.isNotEmpty) life,
                                    if (person.birthPlace.trim().isNotEmpty)
                                      person.birthPlace.trim(),
                                  ].join(' • '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    Navigator.pop(dialogContext, person),
                              );
                            },
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

  Future<void> _showPersonPhotos(
    String name,
    List<DetectedFaceRecord> faces,
  ) async {
    var allPhotos = _photosForPerson(name);

    String search = '';
    String decade = 'All';
    String folder = 'All';
    String location = 'All';
    String tag = 'All';

    List<String> decadesFor(List<VaultPhoto> photos) {
      final values = <String>{};
      for (final photo in photos) {
        final date = _catalogByPath[photo.filePath]?.approximateDate ?? '';
        final match = RegExp(r'(18|19|20)\d0s?').firstMatch(date);
        if (match != null) {
          var value = match.group(0)!;
          if (!value.endsWith('s')) value = '${value}s';
          values.add(value);
        } else {
          final yearMatch = RegExp(r'(18|19|20)\d{2}').firstMatch(date);
          if (yearMatch != null) {
            final year = int.tryParse(yearMatch.group(0)!);
            if (year != null) values.add('${(year ~/ 10) * 10}s');
          }
        }
      }
      final list = values.toList()..sort();
      return list;
    }

    final decades = decadesFor(allPhotos);

    final folders =
        allPhotos
            .map((photo) => photo.relativeFolder.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final locations =
        allPhotos
            .map(
              (photo) => _catalogByPath[photo.filePath]?.location.trim() ?? '',
            )
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final tags = <String>{};
    for (final photo in allPhotos) {
      tags.addAll(_catalogByPath[photo.filePath]?.tags ?? const []);
    }
    final sortedTags = tags.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final activeFaces = _people[name] ?? faces;
          final filtered = allPhotos.where((photo) {
            final metadata = _catalogByPath[photo.filePath];
            final query = search.trim().toLowerCase();

            if (query.isNotEmpty) {
              final haystack = [
                photo.fileName,
                photo.relativeFolder,
                metadata?.approximateDate ?? '',
                metadata?.location ?? '',
                metadata?.description ?? '',
                metadata?.tags.join(' ') ?? '',
              ].join(' ').toLowerCase();

              if (!haystack.contains(query)) return false;
            }

            if (folder != 'All' && photo.relativeFolder != folder) {
              return false;
            }

            if (location != 'All' &&
                (metadata?.location.trim() ?? '') != location) {
              return false;
            }

            if (tag != 'All' && !(metadata?.tags.contains(tag) ?? false)) {
              return false;
            }

            if (decade != 'All') {
              final date = metadata?.approximateDate ?? '';
              final decadeStart =
                  int.tryParse(decade.replaceAll('s', '')) ?? -1;
              final yearMatch = RegExp(r'(18|19|20)\d{2}').firstMatch(date);
              if (yearMatch == null) return false;
              final year = int.tryParse(yearMatch.group(0)!) ?? -1;
              if ((year ~/ 10) * 10 != decadeStart) return false;
            }

            return true;
          }).toList();

          final knownLocations = locations.length;
          final knownDates = allPhotos.where((photo) {
            return (_catalogByPath[photo.filePath]?.approximateDate.trim() ??
                    '')
                .isNotEmpty;
          }).length;

          return Dialog(
            child: SizedBox(
              width: 1220,
              height: 820,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 10, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundImage:
                              activeFaces.isNotEmpty &&
                                  File(
                                    activeFaces.first.thumbnailPath,
                                  ).existsSync()
                              ? FileImage(File(activeFaces.first.thumbnailPath))
                              : null,
                          child:
                              activeFaces.isNotEmpty &&
                                  File(
                                    activeFaces.first.thumbnailPath,
                                  ).existsSync()
                              ? null
                              : const Icon(Icons.person_outline, size: 34),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_familyTreeLinks[name] != null)
                                    Tooltip(
                                      message:
                                          'Linked to ${_familyPersonDisplayName(_familyTreeLinks[name]!)}',
                                      child: Icon(
                                        Icons.account_tree,
                                        size: 20,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _profileStatPill(
                                    icon: Icons.photo_library_outlined,
                                    label:
                                        '${allPhotos.length} photo${allPhotos.length == 1 ? '' : 's'}',
                                  ),
                                  _profileStatPill(
                                    icon: Icons.check_circle_outline,
                                    label:
                                        '${faces.length} confirmed face${faces.length == 1 ? '' : 's'}',
                                  ),
                                  _profileStatPill(
                                    icon: Icons.event_outlined,
                                    label: '$knownDates dated',
                                  ),
                                  _profileStatPill(
                                    icon: Icons.place_outlined,
                                    label: '$knownLocations locations',
                                  ),
                                  if ((_likelyCounts[name] ?? 0) > 0)
                                    _profileStatPill(
                                      icon: Icons.person_search_outlined,
                                      label: '${_likelyCounts[name]} likely',
                                      color: const Color(0xFF2E7D32),
                                      onTap: () =>
                                          _showPersonRecommendationQueue(
                                            personName: name,
                                            referenceFaces:
                                                _people[name] ?? faces,
                                            likelyOnly: true,
                                          ),
                                    ),
                                  if ((_possibleCounts[name] ?? 0) > 0)
                                    _profileStatPill(
                                      icon: Icons.help_outline,
                                      label:
                                          '${_possibleCounts[name]} possible',
                                      color: const Color(0xFFF9A825),
                                      onTap: () =>
                                          _showPersonRecommendationQueue(
                                            personName: name,
                                            referenceFaces:
                                                _people[name] ?? faces,
                                            likelyOnly: false,
                                          ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                final changed = await _manageFamilyTreeLink(
                                  name,
                                );
                                if (!context.mounted) return;
                                if (changed) setDialogState(() {});
                              },
                              icon: const Icon(Icons.account_tree_outlined),
                              label: Text(
                                _familyTreeLinks[name] == null
                                    ? 'Link Family Tree'
                                    : 'Family Tree',
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final changed = await _showPossibleMatches(
                                  name,
                                  _people[name] ?? faces,
                                );

                                if (!context.mounted) return;

                                if (changed) {
                                  setDialogState(() {
                                    allPhotos = _photosForPerson(name);
                                  });
                                }
                              },
                              icon: const Icon(Icons.person_search_outlined),
                              label: const Text('Review Matches'),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Photo Gallery',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const Spacer(),
                              Text(
                                '${filtered.length} shown',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            onChanged: (value) {
                              setDialogState(() => search = value);
                            },
                            decoration: const InputDecoration(
                              hintText: 'Search this person’s photos...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _dialogFilter(
                                label: 'Decade',
                                value: decade,
                                values: ['All', ...decades],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() => decade = value);
                                  }
                                },
                              ),
                              _dialogFilter(
                                label: 'Folder',
                                value: folder,
                                values: ['All', ...folders],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() => folder = value);
                                  }
                                },
                              ),
                              _dialogFilter(
                                label: 'Location',
                                value: location,
                                values: ['All', ...locations],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() => location = value);
                                  }
                                },
                              ),
                              _dialogFilter(
                                label: 'Tag',
                                value: tag,
                                values: ['All', ...sortedTags],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() => tag = value);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No photos match these filters.'),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 260,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.92,
                                ),
                            itemBuilder: (context, index) {
                              final photo = filtered[index];
                              final file = File(photo.filePath);
                              final metadata = _catalogByPath[photo.filePath];

                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _openFullPhoto(
                                    dialogContext,
                                    name,
                                    filtered,
                                    index,
                                  ),
                                  child: Column(
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
                                                  cacheWidth: 600,
                                                  errorBuilder: (_, _, _) =>
                                                      const Center(
                                                        child: Icon(
                                                          Icons
                                                              .broken_image_outlined,
                                                          size: 48,
                                                        ),
                                                      ),
                                                )
                                              : const Center(
                                                  child: Icon(
                                                    Icons
                                                        .image_not_supported_outlined,
                                                    size: 48,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          8,
                                          10,
                                          10,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              photo.fileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 5,
                                              children: [
                                                if ((metadata?.approximateDate
                                                            .trim() ??
                                                        '')
                                                    .isNotEmpty)
                                                  _profileStatPill(
                                                    icon: Icons
                                                        .calendar_today_outlined,
                                                    label: metadata!
                                                        .approximateDate,
                                                  ),
                                                if ((metadata?.location
                                                            .trim() ??
                                                        '')
                                                    .isNotEmpty)
                                                  _profileStatPill(
                                                    icon: Icons.place_outlined,
                                                    label: metadata!.location,
                                                  ),
                                              ],
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _profileStatPill({
    required IconData icon,
    required String label,
    Color? color,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedColor = color ?? scheme.primary;

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: resolvedColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: resolvedColor,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: child,
    );
  }

  Widget _dialogFilter({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(
                  item == 'All' ? 'All' : path.basename(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _openFullPhoto(
    BuildContext parentDialogContext,
    String personName,
    List<VaultPhoto> photos,
    int initialIndex,
  ) async {
    if (photos.isEmpty) return;

    var currentIndex = initialIndex.clamp(0, photos.length - 1);
    final focusNode = FocusNode();

    await showDialog<void>(
      context: parentDialogContext,
      builder: (photoDialogContext) => StatefulBuilder(
        builder: (context, setPhotoDialogState) {
          final photo = photos[currentIndex];
          final file = File(photo.filePath);
          final metadata = _catalogByPath[photo.filePath];

          void previousPhoto() {
            if (currentIndex <= 0) return;
            setPhotoDialogState(() => currentIndex--);
          }

          void nextPhoto() {
            if (currentIndex >= photos.length - 1) return;
            setPhotoDialogState(() => currentIndex++);
          }

          return FutureBuilder<List<DetectedFaceRecord>>(
            future: _databaseHelper.getFacesForPhotoPaths([photo.filePath]),
            builder: (context, snapshot) {
              final faces = snapshot.data ?? const <DetectedFaceRecord>[];
              final confirmedFaces = faces
                  .where(
                    (face) =>
                        face.confirmed && face.personName.trim().isNotEmpty,
                  )
                  .toList();
              final unidentifiedCount = faces
                  .where((face) => !face.confirmed)
                  .length;

              Future<void> changeName(DetectedFaceRecord face) async {
                final faceId = face.id;
                if (faceId == null) return;

                final existingNames = _people.keys.toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                var typedName = face.personName;

                final newName = await showDialog<String>(
                  context: photoDialogContext,
                  builder: (nameContext) => StatefulBuilder(
                    builder: (context, setNameState) {
                      final query = typedName.trim().toLowerCase();
                      final suggestions = existingNames
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
                        if (clean.isEmpty || clean == face.personName) return;
                        FocusScope.of(nameContext).unfocus();
                        Navigator.pop(nameContext, clean);
                      }

                      return AlertDialog(
                        title: const Text('Change face identity'),
                        content: SizedBox(
                          width: 440,
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
                                          onPressed: () =>
                                              Navigator.pop(nameContext, name),
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
                            onPressed: () => Navigator.pop(nameContext),
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
                await _load();
                if (!mounted) return;
                setPhotoDialogState(() {});
              }

              Future<void> markUnidentified(DetectedFaceRecord face) async {
                final faceId = face.id;
                if (faceId == null) return;

                final ok =
                    await showDialog<bool>(
                      context: photoDialogContext,
                      builder: (confirmContext) => AlertDialog(
                        title: const Text('Mark face unidentified?'),
                        content: Text(
                          'Remove "${face.personName}" from this face and '
                          'return it to the Unidentified Faces queue?',
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

                if (!ok) return;

                await _databaseHelper.markFaceUnidentified(faceId);

                final remaining = confirmedFaces.any(
                  (other) =>
                      other.id != face.id &&
                      other.personName == face.personName,
                );

                if (!remaining && metadata != null) {
                  final people = metadata.people.toSet()
                    ..remove(face.personName);
                  final updated = PhotoCatalogMetadata(
                    filePath: metadata.filePath,
                    people: people.toList(),
                    tags: metadata.tags,
                    approximateDate: metadata.approximateDate,
                    location: metadata.location,
                    description: metadata.description,
                    notes: metadata.notes,
                  );
                  await _databaseHelper.savePhotoCatalogMetadata(updated);
                  _catalogByPath[photo.filePath] = updated;
                }

                await _load();
                if (!mounted) return;
                setPhotoDialogState(() {});
              }

              Future<void> removePersonFromPhoto(String name) async {
                final current = _catalogByPath[photo.filePath];
                if (current == null || !current.people.contains(name)) return;

                final ok =
                    await showDialog<bool>(
                      context: photoDialogContext,
                      builder: (confirmContext) => AlertDialog(
                        title: const Text('Remove person from this photo?'),
                        content: Text(
                          'Remove "$name" from this photo’s People metadata? '
                          'This does not delete the photo. If a confirmed face '
                          'is still identified as $name, that face identity will '
                          'remain until you change it or mark it unidentified.',
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
                            child: const Text('Remove from Photo'),
                          ),
                        ],
                      ),
                    ) ??
                    false;

                if (!ok) return;

                final updated = PhotoCatalogMetadata(
                  filePath: current.filePath,
                  people: current.people.where((p) => p != name).toList(),
                  tags: current.tags,
                  approximateDate: current.approximateDate,
                  location: current.location,
                  description: current.description,
                  notes: current.notes,
                );

                await _databaseHelper.savePhotoCatalogMetadata(updated);
                _catalogByPath[photo.filePath] = updated;

                if (!mounted) return;
                setPhotoDialogState(() {});
              }

              return KeyboardListener(
                focusNode: focusNode,
                autofocus: true,
                onKeyEvent: (event) {
                  if (event is! KeyDownEvent) return;
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    previousPhoto();
                  } else if (event.logicalKey ==
                      LogicalKeyboardKey.arrowRight) {
                    nextPhoto();
                  }
                },
                child: Dialog(
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
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Previous photo (Left Arrow)',
                                onPressed: currentIndex > 0
                                    ? previousPhoto
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  '${currentIndex + 1} of ${photos.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next photo (Right Arrow)',
                                onPressed: currentIndex < photos.length - 1
                                    ? nextPhoto
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () =>
                                    Navigator.pop(photoDialogContext),
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  child: file.existsSync()
                                      ? Image.file(file, fit: BoxFit.contain)
                                      : const Center(
                                          child: Text(
                                            'Original photo not found.',
                                          ),
                                        ),
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              SizedBox(
                                width: 380,
                                child: ListView(
                                  padding: const EdgeInsets.all(18),
                                  children: [
                                    Text(
                                      personName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Faces in this Photo',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (snapshot.connectionState !=
                                        ConnectionState.done)
                                      const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    else if (confirmedFaces.isEmpty)
                                      const Text(
                                        'No confirmed faces in this photo.',
                                      )
                                    else
                                      ...confirmedFaces.map((face) {
                                        final thumb = File(face.thumbnailPath);
                                        return Card(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 22,
                                                  backgroundImage:
                                                      thumb.existsSync()
                                                      ? FileImage(thumb)
                                                      : null,
                                                  child: thumb.existsSync()
                                                      ? null
                                                      : const Icon(
                                                          Icons.person_outline,
                                                        ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    face.personName,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    TextButton.icon(
                                                      onPressed: () =>
                                                          changeName(face),
                                                      icon: const Icon(
                                                        Icons.edit_outlined,
                                                        size: 16,
                                                      ),
                                                      label: const Text(
                                                        'Change',
                                                      ),
                                                    ),
                                                    TextButton.icon(
                                                      onPressed: () =>
                                                          markUnidentified(
                                                            face,
                                                          ),
                                                      icon: const Icon(
                                                        Icons
                                                            .person_off_outlined,
                                                        size: 16,
                                                      ),
                                                      label: const Text(
                                                        'Unidentify',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    if (unidentifiedCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '$unidentifiedCount unidentified '
                                          '${unidentifiedCount == 1 ? 'face' : 'faces'} '
                                          'also detected in this photo.',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    const SizedBox(height: 18),
                                    if (metadata != null) ...[
                                      if (metadata.people.isNotEmpty) ...[
                                        Text(
                                          'People',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: metadata.people
                                              .map(
                                                (name) => InputChip(
                                                  label: Text(name),
                                                  deleteIcon: const Icon(
                                                    Icons.close,
                                                    size: 16,
                                                  ),
                                                  deleteButtonTooltipMessage:
                                                      'Remove from this photo',
                                                  onDeleted: () =>
                                                      removePersonFromPhoto(
                                                        name,
                                                      ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                        const SizedBox(height: 14),
                                      ],
                                      if (metadata.approximateDate
                                          .trim()
                                          .isNotEmpty)
                                        _detailField(
                                          'Date',
                                          metadata.approximateDate,
                                        ),
                                      if (metadata.location.trim().isNotEmpty)
                                        _detailField(
                                          'Location',
                                          metadata.location,
                                        ),
                                      if (metadata.description
                                          .trim()
                                          .isNotEmpty)
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      photo.filePath,
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
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    focusNode.dispose();
  }

  Widget _detailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
  }
}
