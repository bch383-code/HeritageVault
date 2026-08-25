import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../database/database_helper.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';
import '../services/face_recognition_service.dart';

class _PersonMatchCandidate {
  final DetectedFaceRecord face;
  final double similarity;

  const _PersonMatchCandidate({
    required this.face,
    required this.similarity,
  });
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

  final TextEditingController _peopleSearchController =
      TextEditingController();
  String _peopleSort = 'Name';

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

  List<MapEntry<String, List<DetectedFaceRecord>>> get _visiblePeople {
    final query = _peopleSearchController.text.trim().toLowerCase();

    final entries = _people.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query);
    }).toList();

    switch (_peopleSort) {
      case 'Most Photos':
        entries.sort((a, b) {
          final aPhotos =
              a.value.map((face) => face.photoFilePath).toSet().length;
          final bPhotos =
              b.value.map((face) => face.photoFilePath).toSet().length;
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
                  : Column(
                      children: [
                        Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _peopleSearchController,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      hintText: 'Search known people...',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon:
                                          _peopleSearchController.text.isEmpty
                                              ? null
                                              : IconButton(
                                                  tooltip: 'Clear',
                                                  onPressed: () {
                                                    _peopleSearchController
                                                        .clear();
                                                    setState(() {});
                                                  },
                                                  icon:
                                                      const Icon(Icons.close),
                                                ),
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
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
                                    items: const [
                                      'Name',
                                      'Most Photos',
                                      'Most Faces',
                                    ]
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
                        Expanded(
                          child: GridView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _visiblePeople.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.15,
                      ),
                      itemBuilder: (context, index) {
                        final entry = _visiblePeople[index];
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
                        ),
                      ],
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

  Future<List<_PersonMatchCandidate>> _findPossibleMatches(
    List<DetectedFaceRecord> referenceFaces,
  ) async {
    if (referenceFaces.isEmpty) return const [];

    final unidentified = await _databaseHelper.getUnconfirmedFaces();
    final matches = <_PersonMatchCandidate>[];

    for (final candidate in unidentified) {
      var bestSimilarity = -1.0;

      for (final reference in referenceFaces) {
        final similarity = FaceRecognitionService.cosineSimilarity(
          candidate.embedding,
          reference.embedding,
        );

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
        }
      }

      // Lower than the automatic suggestion threshold so the user can
      // manually review plausible candidates.
      if (bestSimilarity >= 0.55) {
        matches.add(
          _PersonMatchCandidate(
            face: candidate,
            similarity: bestSimilarity,
          ),
        );
      }
    }

    matches.sort(
      (a, b) => b.similarity.compareTo(a.similarity),
    );

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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
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
                          child: Text(
                            'No more candidates in this search.',
                          ),
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
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

    final folders = allPhotos
        .map((photo) => photo.relativeFolder.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final locations = allPhotos
        .map((photo) => _catalogByPath[photo.filePath]?.location.trim() ?? '')
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

            if (tag != 'All' &&
                !(metadata?.tags.contains(tag) ?? false)) {
              return false;
            }

            if (decade != 'All') {
              final date = metadata?.approximateDate ?? '';
              final decadeStart =
                  int.tryParse(decade.replaceAll('s', '')) ?? -1;
              final yearMatch =
                  RegExp(r'(18|19|20)\d{2}').firstMatch(date);
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
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${allPhotos.length} photos • '
                                '${faces.length} confirmed faces • '
                                '$knownDates dated • '
                                '$knownLocations locations',
                              ),
                            ],
                          ),
                        ),
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
                          label: const Text('Search Possible Matches'),
                        ),
                        const SizedBox(width: 8),
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
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextField(
                            onChanged: (value) {
                              setDialogState(() => search = value);
                            },
                            decoration: const InputDecoration(
                              hintText:
                                  'Search this person’s photos...',
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
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 12),
                                child: Text(
                                  '${filtered.length} matching photos',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
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
                            child: Text(
                              'No photos match these filters.',
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1,
                            ),
                            itemBuilder: (context, index) {
                              final photo = filtered[index];
                              final file = File(photo.filePath);
                              final metadata =
                                  _catalogByPath[photo.filePath];

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
                                                      (_, _, _) =>
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
                                        padding:
                                            const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              photo.fileName,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                            if ((metadata
                                                        ?.approximateDate
                                                        .trim() ??
                                                    '')
                                                .isNotEmpty)
                                              Text(
                                                metadata!.approximateDate,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            if ((metadata?.location
                                                        .trim() ??
                                                    '')
                                                .isNotEmpty)
                                              Text(
                                                metadata!.location,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
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
