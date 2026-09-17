import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../services/face_recognition_service.dart';
import '../services/sface_recognition_service.dart';

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
    if (similarity >= 0.88) return 'High confidence';
    if (similarity >= 0.78) return 'Review';
    return 'Low confidence';
  }
}

class _SFaceLiveDecision {
  final String personName;
  final double score;
  final double margin;
  final String bucket;

  const _SFaceLiveDecision({
    required this.personName,
    required this.score,
    required this.margin,
    required this.bucket,
  });

  bool get isHigh => bucket == 'high';
  bool get isPossible => bucket == 'possible';

  String get label => isHigh ? 'Likely match' : 'Possible match';
}

class _RecognitionDiagnostic {
  final String correctName;
  final String? topName;
  final double? correctScore;
  final double? topScore;
  final double? runnerUpScore;
  final int correctReferences;
  final int topReferences;

  const _RecognitionDiagnostic({
    required this.correctName,
    required this.topName,
    required this.correctScore,
    required this.topScore,
    required this.runnerUpScore,
    required this.correctReferences,
    required this.topReferences,
  });

  bool get topWasCorrect => topName == correctName;
}

class _SFaceDecisionCase {
  final bool topWasCorrect;
  final double topScore;
  final double margin;

  const _SFaceDecisionCase({
    required this.topWasCorrect,
    required this.topScore,
    required this.margin,
  });
}

class _SFaceBenchmarkMiss {
  final String correctName;
  final String wrongName;
  final double correctScore;
  final double wrongScore;
  final double margin;
  final int? testedFaceId;
  final int? strongestWrongReferenceFaceId;

  const _SFaceBenchmarkMiss({
    required this.correctName,
    required this.wrongName,
    required this.correctScore,
    required this.wrongScore,
    required this.margin,
    required this.testedFaceId,
    required this.strongestWrongReferenceFaceId,
  });
}

class _IdentityConflict {
  final int faceIdA;
  final int faceIdB;
  final String nameA;
  final String nameB;
  final double similarity;

  const _IdentityConflict({
    required this.faceIdA,
    required this.faceIdB,
    required this.nameA,
    required this.nameB,
    required this.similarity,
  });
}

class _SFaceBenchmarkResult {
  final int tested;
  final int correct;
  final int wrong;
  final int people;
  final double averageCorrectScore;
  final double averageWrongTopScore;
  final double averageCorrectMargin;
  final double minCorrectScore;
  final double maxWrongTopScore;
  final List<_SFaceBenchmarkMiss> misses;
  final List<_SFaceDecisionCase> decisionCases;

  const _SFaceBenchmarkResult({
    required this.tested,
    required this.correct,
    required this.wrong,
    required this.people,
    required this.averageCorrectScore,
    required this.averageWrongTopScore,
    required this.averageCorrectMargin,
    required this.minCorrectScore,
    required this.maxWrongTopScore,
    required this.misses,
    required this.decisionCases,
  });

  double get accuracy => tested == 0 ? 0 : correct / tested;
}

class _UnidentifiedFacesScreenState extends State<_UnidentifiedFacesBody> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final SFaceRecognitionService _sfaceService = SFaceRecognitionService();
  bool _loading = true;
  bool _comparing = false;
  bool _buildingSFaceIndex = false;
  bool _runningBenchmark = false;
  bool _reviewingIdentityConflicts = false;
  // Kept for the hidden SFace maintenance tools.
  // ignore: unused_field
  int _sfaceProcessed = 0;
  // ignore: unused_field
  int _sfaceTotal = 0;
  bool _saving = false;
  String? _error;

  List<DetectedFaceRecord> _unidentified = const [];
  List<DetectedFaceRecord> _missingSourceFaces = const [];
  List<DetectedFaceRecord> _knownFaces = const [];
  Map<int, List<double>> _sfaceByFaceId = <int, List<double>>{};
  Map<String, List<List<double>>> _sfaceConfirmedByPerson =
      <String, List<List<double>>>{};
  final Set<String> _dismissedIdentityConflictKeys = <String>{};
  static const String _dismissedIdentityConflictsSettingKey =
      'dismissed_identity_conflicts_v1';

  // Selected from the held-out SFace benchmark on 2026-08-27.
  // High: 171/171 correct. Possible: 51/52 correct.
  static const double _liveHighScore = 0.62;
  static const double _liveHighMargin = 0.16;
  static const double _livePossibleScore = 0.48;
  static const double _livePossibleMargin = 0.06;
  String _search = '';
  String _recommendationFilter = 'all';
  final List<_RecognitionDiagnostic> _diagnostics = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Repair stale face-to-photo paths before loading faces. A path is
      // changed only when the old file is gone and exactly one indexed photo
      // has the same filename.
      await _databaseHelper.repairStaleFacePhotoPaths();

      final results = await Future.wait([
        _databaseHelper.getUnconfirmedFaces(),
        _databaseHelper.getConfirmedFaces(),
        _databaseHelper.getAllSFaceEmbeddingRows(),
        _databaseHelper.getSetting(_dismissedIdentityConflictsSettingKey),
      ]);

      if (!mounted) return;

      setState(() {
        final loadedUnidentified = List<DetectedFaceRecord>.from(
          results[0] as List<DetectedFaceRecord>,
        );
        _unidentified = loadedUnidentified
            .where((face) => File(face.photoFilePath).existsSync())
            .toList();
        _missingSourceFaces = loadedUnidentified
            .where((face) => !File(face.photoFilePath).existsSync())
            .toList();

        _knownFaces = List<DetectedFaceRecord>.from(
          results[1] as List<DetectedFaceRecord>,
        );

        final rows = List<Map<String, Object?>>.from(results[2] as List);

        final byId = <int, List<double>>{};
        final confirmedByPerson = <String, List<List<double>>>{};

        for (final row in rows) {
          final id = row['id'];
          if (id is! int) continue;

          final embedding = _decodeSFaceEmbedding(
            row['sface_embedding_json'] as String? ?? '[]',
          );
          if (embedding.isEmpty) continue;

          byId[id] = embedding;

          final confirmedValue = row['confirmed'];
          final confirmed = confirmedValue is int
              ? confirmedValue == 1
              : confirmedValue == true;
          final personName = (row['person_name'] as String? ?? '').trim();

          if (confirmed && personName.isNotEmpty) {
            confirmedByPerson
                .putIfAbsent(personName, () => <List<double>>[])
                .add(embedding);
          }
        }

        _sfaceByFaceId = byId;
        _sfaceConfirmedByPerson = confirmedByPerson;

        _dismissedIdentityConflictKeys.clear();
        final dismissedJson = results[3] as String?;
        if (dismissedJson != null && dismissedJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(dismissedJson);
            if (decoded is List) {
              _dismissedIdentityConflictKeys.addAll(
                decoded.whereType<String>(),
              );
            }
          } catch (_) {
            // Ignore malformed legacy setting and start with an empty set.
          }
        }

        _loading = false;
        _error = null;
      });

      // Keep recognition ready automatically. Any newly detected or legacy
      // unidentified face that does not yet have an SFace embedding is indexed
      // when Face Review loads.
      if (mounted) {
        final missingUnidentified = _unidentified.where((face) {
          final id = face.id;
          return id != null && !_sfaceByFaceId.containsKey(id);
        }).toList();
        if (missingUnidentified.isNotEmpty && !_buildingSFaceIndex) {
          await _buildSFaceIndex(unidentifiedOnly: true);
        }
      }
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

  static List<double> _decodeSFaceEmbedding(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded.map((item) => (item as num).toDouble()).toList();
    } catch (_) {
      return const [];
    }
  }

  _SFaceLiveDecision? _liveSFaceDecision(DetectedFaceRecord face) {
    final faceId = face.id;
    if (faceId == null) return null;

    final candidate = _sfaceByFaceId[faceId];
    if (candidate == null || candidate.isEmpty) return null;

    final scored = <MapEntry<String, double>>[];
    for (final entry in _sfaceConfirmedByPerson.entries) {
      final score = _benchmarkPersonScore(candidate, entry.value);
      if (score >= 0) {
        scored.add(MapEntry(entry.key, score));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    if (scored.isEmpty) return null;

    final best = scored.first;
    final runnerUp = scored.length > 1 ? scored[1].value : -1.0;
    final margin = runnerUp < 0 ? 1.0 : best.value - runnerUp;

    final bucket = _decisionBucket(
      topScore: best.value,
      margin: margin,
      highScore: _liveHighScore,
      highMargin: _liveHighMargin,
      possibleScore: _livePossibleScore,
      possibleMargin: _livePossibleMargin,
    );

    // Low-confidence results deliberately produce no named suggestion.
    if (bucket == 'review') return null;

    return _SFaceLiveDecision(
      personName: best.key,
      score: best.value,
      margin: margin,
      bucket: bucket,
    );
  }

  MapEntry<String, double>? _bestKnownMatch(DetectedFaceRecord face) {
    final decision = _liveSFaceDecision(face);
    if (decision == null) return null;
    return MapEntry(decision.personName, decision.score);
  }

  Map<String, List<double>> _sfaceScoresByPerson(DetectedFaceRecord face) {
    final faceId = face.id;
    if (faceId == null) return const {};

    final candidate = _sfaceByFaceId[faceId];
    if (candidate == null || candidate.isEmpty) return const {};

    final scores = <String, List<double>>{};

    // Diagnostics intentionally use the confirmed SFace references loaded
    // directly from photo_faces, rather than rebuilding them from UI state.
    for (final entry in _sfaceConfirmedByPerson.entries) {
      final personScores = <double>[];

      for (final embedding in entry.value) {
        final score = SFaceRecognitionService.cosineSimilarity(
          candidate,
          embedding,
        );
        if (score >= 0) {
          personScores.add(score);
        }
      }

      if (personScores.isNotEmpty) {
        personScores.sort((a, b) => b.compareTo(a));
        scores[entry.key] = personScores;
      }
    }

    return scores;
  }

  double? _rawPersonDiagnosticScore(List<double>? scores) {
    if (scores == null || scores.isEmpty) return null;
    final top = scores.take(3).toList();
    return top.reduce((a, b) => a + b) / top.length;
  }

  _RecognitionDiagnostic _makeDiagnostic(
    DetectedFaceRecord face,
    String correctName,
  ) {
    final byPerson = _sfaceScoresByPerson(face);
    final ranked =
        byPerson.entries
            .map(
              (entry) => MapEntry(
                entry.key,
                _rawPersonDiagnosticScore(entry.value) ?? -1,
              ),
            )
            .where((entry) => entry.value >= 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final top = ranked.isEmpty ? null : ranked.first;
    final runnerUp = ranked.length > 1 ? ranked[1] : null;
    final correctScores = byPerson[correctName];

    return _RecognitionDiagnostic(
      correctName: correctName,
      topName: top?.key,
      correctScore: _rawPersonDiagnosticScore(correctScores),
      topScore: top?.value,
      runnerUpScore: runnerUp?.value,
      correctReferences: correctScores?.length ?? 0,
      topReferences: top == null ? 0 : (byPerson[top.key]?.length ?? 0),
    );
  }

  int? _faceIdForEmbedding(List<double> target) {
    for (final entry in _sfaceByFaceId.entries) {
      if (identical(entry.value, target)) return entry.key;
    }

    // Confirmed-person lists and by-id lists are decoded separately in some
    // builds, so fall back to exact vector comparison.
    for (final entry in _sfaceByFaceId.entries) {
      final value = entry.value;
      if (value.length != target.length) continue;
      var same = true;
      for (var i = 0; i < value.length; i++) {
        if (value[i] != target[i]) {
          same = false;
          break;
        }
      }
      if (same) return entry.key;
    }
    return null;
  }

  List<double>? _strongestReferenceFor(
    List<double> candidate,
    Iterable<List<double>> references,
  ) {
    List<double>? best;
    var bestScore = -1.0;
    for (final embedding in references) {
      if (embedding.isEmpty) continue;
      final score = SFaceRecognitionService.cosineSimilarity(
        candidate,
        embedding,
      );
      if (score > bestScore) {
        bestScore = score;
        best = embedding;
      }
    }
    return best;
  }

  static double _benchmarkPersonScore(
    List<double> candidate,
    Iterable<List<double>> references,
  ) {
    final scores =
        references
            .where((embedding) => embedding.isNotEmpty)
            .map(
              (embedding) => SFaceRecognitionService.cosineSimilarity(
                candidate,
                embedding,
              ),
            )
            .where((score) => score >= 0)
            .toList()
          ..sort((a, b) => b.compareTo(a));

    if (scores.isEmpty) return -1;
    final top = scores.take(3).toList();
    return top.reduce((a, b) => a + b) / top.length;
  }

  DetectedFaceRecord? _benchmarkFaceById(int? faceId) {
    if (faceId == null) return null;
    for (final face in _knownFaces) {
      if (face.id == faceId) return face;
    }
    return null;
  }

  Widget _benchmarkFacePreview({
    required int? faceId,
    required String heading,
    required String personName,
  }) {
    final face = _benchmarkFaceById(faceId);
    final thumbnail = face == null ? null : File(face.thumbnailPath);
    final exists = thumbnail != null && thumbnail.existsSync();

    return Expanded(
      child: Column(
        children: [
          Text(
            heading,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: exists
                    ? Image.file(thumbnail, fit: BoxFit.contain)
                    : const Center(child: Icon(Icons.face_outlined, size: 56)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            personName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            'Face ID ${faceId?.toString() ?? "n/a"}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _identityConflictKey(int faceIdA, int faceIdB) {
    final low = faceIdA < faceIdB ? faceIdA : faceIdB;
    final high = faceIdA < faceIdB ? faceIdB : faceIdA;
    return '$low:$high';
  }

  Future<void> _persistDismissedIdentityConflicts() async {
    final values = _dismissedIdentityConflictKeys.toList()..sort();
    await _databaseHelper.setSetting(
      _dismissedIdentityConflictsSettingKey,
      jsonEncode(values),
    );
  }

  Future<void> _dismissIdentityConflict(_IdentityConflict conflict) async {
    _dismissedIdentityConflictKeys.add(
      _identityConflictKey(conflict.faceIdA, conflict.faceIdB),
    );
    await _persistDismissedIdentityConflicts();
  }

  Future<void> _relabelConflictFace({
    required int faceId,
    required String newPersonName,
  }) async {
    await _databaseHelper.reassignConfirmedFace(
      faceId: faceId,
      newPersonName: newPersonName,
    );
    await _load();
  }

  Future<bool> _confirmConflictRelabel({
    required BuildContext dialogContext,
    required String faceCurrentName,
    required String newPersonName,
  }) async {
    return await showDialog<bool>(
          context: dialogContext,
          builder: (confirmContext) => AlertDialog(
            title: const Text('Change identity?'),
            content: Text(
              'Change this face from $faceCurrentName to $newPersonName?\\n\\n'
              'The face record and the source photo’s People metadata will '
              'be updated.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(confirmContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(confirmContext, true),
                child: Text('Change to $newPersonName'),
              ),
            ],
          ),
        ) ??
        false;
  }

  List<_IdentityConflict> _findIdentityConflicts() {
    final confirmed = _knownFaces.where((face) {
      final id = face.id;
      return id != null &&
          face.personName.trim().isNotEmpty &&
          _sfaceByFaceId.containsKey(id);
    }).toList();

    final conflicts = <_IdentityConflict>[];

    // This is intentionally a review tool, not an automatic relabeler.
    // A fairly broad threshold catches suspicious cross-name references while
    // leaving the user in control of whether the labels are actually wrong.
    const conflictThreshold = 0.60;

    for (var i = 0; i < confirmed.length; i++) {
      final a = confirmed[i];
      final aId = a.id!;
      final aName = a.personName.trim();
      final aEmbedding = _sfaceByFaceId[aId];
      if (aEmbedding == null || aEmbedding.isEmpty) continue;

      for (var j = i + 1; j < confirmed.length; j++) {
        final b = confirmed[j];
        final bId = b.id!;
        final bName = b.personName.trim();
        if (aName == bName) continue;
        if (_dismissedIdentityConflictKeys.contains(
          _identityConflictKey(aId, bId),
        )) {
          continue;
        }

        final bEmbedding = _sfaceByFaceId[bId];
        if (bEmbedding == null || bEmbedding.isEmpty) continue;

        final similarity = SFaceRecognitionService.cosineSimilarity(
          aEmbedding,
          bEmbedding,
        );
        if (similarity < conflictThreshold) continue;

        conflicts.add(
          _IdentityConflict(
            faceIdA: aId,
            faceIdB: bId,
            nameA: aName,
            nameB: bName,
            similarity: similarity,
          ),
        );
      }
    }

    conflicts.sort((a, b) => b.similarity.compareTo(a.similarity));

    // Keep the review queue useful if a large library contains many relatives.
    return conflicts.take(100).toList();
  }

  Widget _identityConflictFacePreview({
    required int faceId,
    required String personName,
  }) {
    final face = _benchmarkFaceById(faceId);
    final thumbnail = face == null ? null : File(face.thumbnailPath);
    final exists = thumbnail != null && thumbnail.existsSync();

    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 190,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: exists
                    ? Image.file(thumbnail, fit: BoxFit.contain)
                    : const Center(child: Icon(Icons.face_outlined, size: 56)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            personName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            'Face ID $faceId',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (face != null)
            TextButton.icon(
              onPressed: () => _showSourcePhoto(face),
              icon: const Icon(Icons.photo_outlined, size: 17),
              label: const Text('View Source'),
            ),
        ],
      ),
    );
  }

  // Hidden developer/maintenance tool retained for future use.
  // ignore: unused_element
  Future<void> _showIdentityConflicts() async {
    if (_reviewingIdentityConflicts) return;

    setState(() => _reviewingIdentityConflicts = true);
    try {
      var conflicts = _findIdentityConflicts();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            child: SizedBox(
              width: 1100,
              height: 820,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.rule_folder_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Identity Conflict Review (${conflicts.length})',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'These confirmed faces have different names but '
                                'look unusually similar to SFace. Use the source '
                                'photos when needed, then correct the bad label '
                                'or confirm that they really are different people.',
                              ),
                            ],
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
                  if (conflicts.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_user_outlined, size: 64),
                              SizedBox(height: 14),
                              Text(
                                'No unresolved cross-name conflicts found.',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Corrected conflicts and pairs confirmed as '
                                'different people are no longer in this queue.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: conflicts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final conflict = conflicts[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${conflict.nameA} ↔ ${conflict.nameB}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 17,
                                          ),
                                        ),
                                      ),
                                      Chip(
                                        avatar: const Icon(
                                          Icons.warning_amber_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'SFace ${conflict.similarity.toStringAsFixed(3)}',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _identityConflictFacePreview(
                                        faceId: conflict.faceIdA,
                                        personName: conflict.nameA,
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          16,
                                          82,
                                          16,
                                          0,
                                        ),
                                        child: Icon(
                                          Icons.compare_arrows,
                                          size: 30,
                                        ),
                                      ),
                                      _identityConflictFacePreview(
                                        faceId: conflict.faceIdB,
                                        personName: conflict.nameB,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: _saving
                                            ? null
                                            : () async {
                                                final confirmed =
                                                    await _confirmConflictRelabel(
                                                      dialogContext:
                                                          dialogContext,
                                                      faceCurrentName:
                                                          conflict.nameB,
                                                      newPersonName:
                                                          conflict.nameA,
                                                    );
                                                if (!confirmed || !mounted) {
                                                  return;
                                                }

                                                setState(() => _saving = true);
                                                try {
                                                  await _relabelConflictFace(
                                                    faceId: conflict.faceIdB,
                                                    newPersonName:
                                                        conflict.nameA,
                                                  );
                                                  conflicts =
                                                      _findIdentityConflicts();
                                                  if (dialogContext.mounted) {
                                                    setDialogState(() {});
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(
                                                      () => _saving = false,
                                                    );
                                                  }
                                                }
                                              },
                                        icon: const Icon(
                                          Icons.arrow_back_rounded,
                                        ),
                                        label: Text(
                                          '${conflict.nameA} is correct',
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: _saving
                                            ? null
                                            : () async {
                                                final confirmed =
                                                    await _confirmConflictRelabel(
                                                      dialogContext:
                                                          dialogContext,
                                                      faceCurrentName:
                                                          conflict.nameA,
                                                      newPersonName:
                                                          conflict.nameB,
                                                    );
                                                if (!confirmed || !mounted) {
                                                  return;
                                                }

                                                setState(() => _saving = true);
                                                try {
                                                  await _relabelConflictFace(
                                                    faceId: conflict.faceIdA,
                                                    newPersonName:
                                                        conflict.nameB,
                                                  );
                                                  conflicts =
                                                      _findIdentityConflicts();
                                                  if (dialogContext.mounted) {
                                                    setDialogState(() {});
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(
                                                      () => _saving = false,
                                                    );
                                                  }
                                                }
                                              },
                                        icon: const Icon(
                                          Icons.arrow_forward_rounded,
                                        ),
                                        label: Text(
                                          '${conflict.nameB} is correct',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _saving
                                            ? null
                                            : () async {
                                                await _dismissIdentityConflict(
                                                  conflict,
                                                );
                                                conflicts =
                                                    _findIdentityConflicts();
                                                if (dialogContext.mounted) {
                                                  setDialogState(() {});
                                                }
                                              },
                                        icon: const Icon(Icons.people_outline),
                                        label: const Text(
                                          'They are different people',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Identity changes update the confirmed face and its '
                            'source-photo People metadata. “Different people” '
                            'is remembered so that exact face pair stays out '
                            'of future conflict reviews.',
                          ),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _reviewingIdentityConflicts = false);
      }
    }
  }

  String _decisionBucket({
    required double topScore,
    required double margin,
    required double highScore,
    required double highMargin,
    required double possibleScore,
    required double possibleMargin,
  }) {
    if (topScore >= highScore && margin >= highMargin) {
      return 'high';
    }
    if (topScore >= possibleScore && margin >= possibleMargin) {
      return 'possible';
    }
    return 'review';
  }

  Widget _decisionRuleRow({
    required String label,
    required double highScore,
    required double highMargin,
    required double possibleScore,
    required double possibleMargin,
    required List<_SFaceDecisionCase> cases,
  }) {
    var high = 0;
    var highCorrect = 0;
    var possible = 0;
    var possibleCorrect = 0;
    var review = 0;

    for (final item in cases) {
      final bucket = _decisionBucket(
        topScore: item.topScore,
        margin: item.margin,
        highScore: highScore,
        highMargin: highMargin,
        possibleScore: possibleScore,
        possibleMargin: possibleMargin,
      );

      if (bucket == 'high') {
        high++;
        if (item.topWasCorrect) highCorrect++;
      } else if (bucket == 'possible') {
        possible++;
        if (item.topWasCorrect) possibleCorrect++;
      } else {
        review++;
      }
    }

    String precision(int correct, int total) =>
        total == 0 ? '—' : '${(correct / total * 100).toStringAsFixed(1)}%';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(
              'High: score ≥ ${highScore.toStringAsFixed(2)}, '
              'margin ≥ ${highMargin.toStringAsFixed(2)}  •  '
              '$high faces  •  ${precision(highCorrect, high)} correct',
            ),
            Text(
              'Possible: score ≥ ${possibleScore.toStringAsFixed(2)}, '
              'margin ≥ ${possibleMargin.toStringAsFixed(2)}  •  '
              '$possible faces  •  '
              '${precision(possibleCorrect, possible)} correct',
            ),
            Text('Needs review / no guess: $review faces'),
          ],
        ),
      ),
    );
  }

  // Hidden developer/maintenance tool retained for future use.
  // ignore: unused_element
  Future<void> _runSFaceBenchmark() async {
    if (_runningBenchmark) return;

    final eligible = _sfaceConfirmedByPerson.entries
        .where((entry) => entry.value.length >= 3)
        .toList();

    if (eligible.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Need at least two people with 3+ indexed confirmed faces.',
          ),
        ),
      );
      return;
    }

    setState(() => _runningBenchmark = true);

    try {
      var tested = 0;
      var correct = 0;
      var wrong = 0;
      final correctScores = <double>[];
      final wrongTopScores = <double>[];
      final correctMargins = <double>[];
      final misses = <_SFaceBenchmarkMiss>[];
      final decisionCases = <_SFaceDecisionCase>[];

      // Cap each person so one heavily photographed relative does not dominate.
      const maxTestsPerPerson = 12;

      for (final person in eligible) {
        final samples = person.value.take(maxTestsPerPerson).toList();

        for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
          final candidate = samples[sampleIndex];
          final ranked = <MapEntry<String, double>>[];

          for (final other in eligible) {
            Iterable<List<double>> references = other.value;

            // Leave the test face out of its own person's reference set.
            if (other.key == person.key) {
              final heldOut = samples[sampleIndex];
              references = other.value.where(
                (embedding) => !identical(embedding, heldOut),
              );
            }

            final score = _benchmarkPersonScore(candidate, references);
            if (score >= 0) {
              ranked.add(MapEntry(other.key, score));
            }
          }

          ranked.sort((a, b) => b.value.compareTo(a.value));
          if (ranked.isEmpty) continue;

          tested++;
          final top = ranked.first;
          MapEntry<String, double>? correctEntry;
          for (final entry in ranked) {
            if (entry.key == person.key) {
              correctEntry = entry;
              break;
            }
          }

          if (correctEntry != null) {
            correctScores.add(correctEntry.value);
            MapEntry<String, double>? bestWrong;
            for (final entry in ranked) {
              if (entry.key != person.key) {
                bestWrong = entry;
                break;
              }
            }
            if (bestWrong != null) {
              correctMargins.add(correctEntry.value - bestWrong.value);
            }
          }

          final runnerUpScore = ranked.length > 1 ? ranked[1].value : -1.0;
          final topMargin = runnerUpScore < 0 ? 1.0 : top.value - runnerUpScore;
          decisionCases.add(
            _SFaceDecisionCase(
              topWasCorrect: top.key == person.key,
              topScore: top.value,
              margin: topMargin,
            ),
          );

          if (top.key == person.key) {
            correct++;
          } else {
            wrong++;
            wrongTopScores.add(top.value);
            if (correctEntry != null) {
              final wrongPerson = eligible
                  .where((entry) => entry.key == top.key)
                  .first;
              final strongestWrongReference = _strongestReferenceFor(
                candidate,
                wrongPerson.value,
              );

              misses.add(
                _SFaceBenchmarkMiss(
                  correctName: person.key,
                  wrongName: top.key,
                  correctScore: correctEntry.value,
                  wrongScore: top.value,
                  margin: correctEntry.value - top.value,
                  testedFaceId: _faceIdForEmbedding(candidate),
                  strongestWrongReferenceFaceId: strongestWrongReference == null
                      ? null
                      : _faceIdForEmbedding(strongestWrongReference),
                ),
              );
            }
          }
        }
      }

      double average(List<double> values) =>
          values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

      misses.sort((a, b) => b.wrongScore.compareTo(a.wrongScore));

      final result = _SFaceBenchmarkResult(
        tested: tested,
        correct: correct,
        wrong: wrong,
        people: eligible.length,
        averageCorrectScore: average(correctScores),
        averageWrongTopScore: average(wrongTopScores),
        averageCorrectMargin: average(correctMargins),
        minCorrectScore: correctScores.isEmpty
            ? 0
            : correctScores.reduce((a, b) => a < b ? a : b),
        maxWrongTopScore: wrongTopScores.isEmpty
            ? 0
            : wrongTopScores.reduce((a, b) => a > b ? a : b),
        misses: misses,
        decisionCases: decisionCases,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('SFace Benchmark'),
          content: SizedBox(
            width: 820,
            height: 720,
            child: ListView(
              children: [
                Text(
                  '${result.tested} held-out faces tested across '
                  '${result.people} people.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Top-name accuracy: '
                  '${(result.accuracy * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text('Correct top choice: ${result.correct}'),
                Text('Wrong top choice: ${result.wrong}'),
                const Divider(height: 28),
                Text(
                  'Average correct-person score: '
                  '${result.averageCorrectScore.toStringAsFixed(3)}',
                ),
                Text(
                  'Lowest correct-person score: '
                  '${result.minCorrectScore.toStringAsFixed(3)}',
                ),
                Text(
                  'Average wrong top score: '
                  '${result.averageWrongTopScore.toStringAsFixed(3)}',
                ),
                Text(
                  'Highest wrong top score: '
                  '${result.maxWrongTopScore.toStringAsFixed(3)}',
                ),
                Text(
                  'Average correct-vs-best-wrong margin: '
                  '${result.averageCorrectMargin.toStringAsFixed(3)}',
                ),
                const SizedBox(height: 14),
                const Text(
                  'This is a leave-one-out test. Each known face is tested '
                  'against the other confirmed SFace references, so no manual '
                  'identification is needed.',
                ),
                const Divider(height: 32),
                const Text(
                  'Confidence rule analysis',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 6),
                const Text(
                  'These rules are only simulations. Nothing is saved or '
                  'changed. “Margin” means the top person’s score minus the '
                  'runner-up score.',
                ),
                const SizedBox(height: 10),
                _decisionRuleRow(
                  label: 'Very conservative',
                  highScore: 0.62,
                  highMargin: 0.16,
                  possibleScore: 0.48,
                  possibleMargin: 0.06,
                  cases: result.decisionCases,
                ),
                _decisionRuleRow(
                  label: 'Conservative',
                  highScore: 0.58,
                  highMargin: 0.14,
                  possibleScore: 0.44,
                  possibleMargin: 0.04,
                  cases: result.decisionCases,
                ),
                _decisionRuleRow(
                  label: 'Balanced',
                  highScore: 0.55,
                  highMargin: 0.10,
                  possibleScore: 0.40,
                  possibleMargin: 0.02,
                  cases: result.decisionCases,
                ),
                const Text(
                  'For High and Possible, the percentage shown is precision: '
                  'how often that bucket’s top suggestion was actually the '
                  'correct person in this held-out benchmark.',
                ),
                const Divider(height: 32),
                Text(
                  'Wrong top choices (${result.misses.length})',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (result.misses.isEmpty)
                  const Text('None.')
                else
                  ...result.misses.map(
                    (miss) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${miss.correctName} → ${miss.wrongName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Correct '
                                '${miss.correctScore.toStringAsFixed(3)}  •  '
                                'Wrong '
                                '${miss.wrongScore.toStringAsFixed(3)}  •  '
                                'Margin ${miss.margin.toStringAsFixed(3)}',
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _benchmarkFacePreview(
                                    faceId: miss.testedFaceId,
                                    heading: 'Test face',
                                    personName: miss.correctName,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(12, 80, 12, 0),
                                    child: Icon(Icons.arrow_forward, size: 28),
                                  ),
                                  _benchmarkFacePreview(
                                    faceId: miss.strongestWrongReferenceFaceId,
                                    heading: 'Strongest wrong reference',
                                    personName: miss.wrongName,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _runningBenchmark = false);
      }
    }
  }

  // Hidden developer/maintenance tool retained for future use.
  // ignore: unused_element
  Future<void> _showDiagnostics() async {
    final items = List<_RecognitionDiagnostic>.from(_diagnostics);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 760,
          height: 620,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.analytics_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recognition Diagnostics (${items.length})',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
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
              if (items.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Identify some faces manually first.\n'
                      'Each identification will record what SFace thought '
                      'before you supplied the answer.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final correct = item.correctScore;
                      final top = item.topScore;
                      final margin =
                          correct == null || top == null || item.topWasCorrect
                          ? null
                          : correct - top;
                      return ListTile(
                        leading: Icon(
                          item.topWasCorrect
                              ? Icons.check_circle_outline
                              : Icons.cancel_outlined,
                        ),
                        title: Text(
                          'Correct: ${item.correctName}  •  '
                          'Top: ${item.topName ?? "No result"}',
                        ),
                        subtitle: Text(
                          'Correct score: '
                          '${correct?.toStringAsFixed(3) ?? "n/a"} '
                          '(${item.correctReferences} refs)\n'
                          'Top score: ${top?.toStringAsFixed(3) ?? "n/a"} '
                          '(${item.topReferences} refs)'
                          '${item.runnerUpScore == null ? "" : "  •  "
                                    "Runner-up: ${item.runnerUpScore!.toStringAsFixed(3)}"}'
                          '${margin == null ? "" : "  •  "
                                    "Correct-minus-wrong: ${margin.toStringAsFixed(3)}"}',
                        ),
                        isThreeLine: true,
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

  Future<String?> _askForName(DetectedFaceRecord face) async {
    final liveDecision = _liveSFaceDecision(face);
    final suggestion = liveDecision?.personName;
    final suggestionScore = liveDecision?.score;

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
                        leading: Icon(
                          liveDecision!.isHigh
                              ? Icons.verified_outlined
                              : Icons.auto_awesome,
                        ),
                        title: Text('${liveDecision.label}: $suggestion'),
                        subtitle: Text(
                          'SFace ${suggestionScore.toStringAsFixed(3)}  •  '
                          'margin ${liveDecision.margin.toStringAsFixed(3)}',
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

  List<_FaceMatchCandidate> _findCandidates(
    String personName,
    DetectedFaceRecord reference,
  ) {
    final candidates = <_FaceMatchCandidate>[];
    final references = <DetectedFaceRecord>[
      ..._knownFaces.where((known) => known.personName == personName),
    ];
    if (!references.any((known) => known.id == reference.id)) {
      references.add(reference);
    }

    for (final face in _unidentified) {
      if (face.id == reference.id) continue;

      // The old follow-up search used a broad legacy similarity cutoff and
      // could flood the review dialog with unrelated people. For beta, require
      // the same benchmark-backed SFace decision used by the main Face Review
      // screen, and require that it independently names this exact person.
      final sfaceDecision = _liveSFaceDecision(face);
      if (sfaceDecision == null || sfaceDecision.personName != personName) {
        continue;
      }

      final similarity = FaceRecognitionService.consensusSimilarity(
        face.embedding,
        references,
      );

      candidates.add(_FaceMatchCandidate(face: face, similarity: similarity));
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
        if (candidate.similarity >= 0.88 && candidate.face.id != null)
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

    // Capture SFace's opinion BEFORE this manual answer becomes training data.
    final diagnostic = _makeDiagnostic(face, cleanName);
    _diagnostics.add(diagnostic);

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

        // Make this newly confirmed face available to SFace immediately so
        // the follow-up search can use it without requiring a reload.
        final referenceSFace = _sfaceByFaceId[faceId];
        if (referenceSFace != null && referenceSFace.isNotEmpty) {
          _sfaceConfirmedByPerson
              .putIfAbsent(cleanName, () => <List<double>>[])
              .add(referenceSFace);
        }

        _unidentified.removeWhere((item) => item.id == faceId);
      });

      final candidates = _findCandidates(cleanName, reference);

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

  Future<void> _buildSFaceIndex({bool unidentifiedOnly = false}) async {
    if (_buildingSFaceIndex) return;

    var rows = await _databaseHelper.getFacesMissingSFaceEmbeddings();

    if (unidentifiedOnly) {
      final unidentifiedIds = _unidentified
          .map((face) => face.id)
          .whereType<int>()
          .toSet();

      rows = rows.where((row) {
        final id = row['id'];
        return id is int && unidentifiedIds.contains(id);
      }).toList();
    }

    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SFace index is already up to date.')),
      );
      return;
    }

    setState(() {
      _buildingSFaceIndex = true;
      _sfaceProcessed = 0;
      _sfaceTotal = rows.length;
    });

    final detectorHelper = FaceRecognitionService();
    var saved = 0;
    var skipped = 0;

    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final record = DetectedFaceRecord.fromMap(row);
        final faceId = record.id;

        try {
          if (faceId == null) {
            skipped++;
          } else {
            final file = File(record.photoFilePath);
            if (!await file.exists()) {
              skipped++;
            } else {
              final bytes = await file.readAsBytes();
              final detected = await detectorHelper.detectFacesWithMesh(bytes);

              if (detected.isEmpty) {
                skipped++;
              } else {
                final matched = detectorHelper.closestFaceToRecord(
                  detected,
                  record,
                );
                final embedding = await _sfaceService.embeddingForFaceBytes(
                  bytes,
                  matched,
                );

                await _databaseHelper.saveSFaceEmbedding(
                  faceId: faceId,
                  embeddingJson: jsonEncode(embedding),
                );
                saved++;
              }
            }
          }
        } catch (error) {
          skipped++;
          debugPrint(
            'SFace indexing failed for face ${faceId ?? "n/a"}: $error',
          );
        }

        if (!mounted) return;
        setState(() => _sfaceProcessed = i + 1);
      }

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${unidentifiedOnly ? "Face recognition preparation" : "SFace index"} '
            'complete: $saved saved'
            '${skipped == 0 ? '' : ', $skipped skipped'}.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _buildingSFaceIndex = false);
      }
    }
  }

  Future<String?> _recoverMissingSourcePhoto(
    DetectedFaceRecord face,
  ) async {
    final faceId = face.id;
    if (faceId == null) return null;

    var targetEmbedding = _sfaceByFaceId[faceId];

    // If this older face record never received an SFace embedding, try to
    // recover one from its saved face thumbnail. This avoids scanning the
    // entire photo library just to identify the missing source.
    if (targetEmbedding == null || targetEmbedding.isEmpty) {
      final thumbnail = File(face.thumbnailPath);
      if (await thumbnail.exists()) {
        try {
          final bytes = await thumbnail.readAsBytes();
          final detector = FaceRecognitionService();
          final detected = await detector.detectFacesWithMesh(bytes);
          if (detected.isNotEmpty) {
            targetEmbedding = await _sfaceService.embeddingForFaceBytes(
              bytes,
              detected.first,
            );
          }
        } catch (_) {
          // Fall through to "no safe match" below.
        }
      }
    }

    if (targetEmbedding == null || targetEmbedding.isEmpty) return null;

    final rows = await _databaseHelper.getIndexedSFaceRecoveryRows(
      excludeFaceId: faceId,
    );

    // Keep only the strongest matching face for each current source photo.
    final bestByPath = <String, double>{};
    for (final row in rows) {
      final currentPath = (row['photo_file_path'] as String? ?? '').trim();
      if (currentPath.isEmpty) continue;
      if (!await File(currentPath).exists()) continue;

      final embedding = _decodeSFaceEmbedding(
        row['sface_embedding_json'] as String? ?? '[]',
      );
      if (embedding.isEmpty) continue;

      final score = SFaceRecognitionService.cosineSimilarity(
        targetEmbedding,
        embedding,
      );
      final previous = bestByPath[currentPath];
      if (previous == null || score > previous) {
        bestByPath[currentPath] = score;
      }
    }

    if (bestByPath.isEmpty) return null;

    final ranked = bestByPath.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final best = ranked.first;
    final runnerUp = ranked.length > 1 ? ranked[1].value : -1.0;
    final margin = best.value - runnerUp;

    // This is intentionally much stricter than person identification.
    // We are trying to prove that this is the same saved face/photo, not just
    // the same person in another photograph.
    const minimumSamePhotoScore = 0.92;
    const minimumSamePhotoMargin = 0.08;

    if (best.value < minimumSamePhotoScore ||
        (ranked.length > 1 && margin < minimumSamePhotoMargin)) {
      return null;
    }

    // Try to persist the repair. If the destination already contains a face
    // with the same face index, leave the database untouched; Compare
    // Recognition can still safely use the recovered source photo now.
    await _databaseHelper.relinkFacePhotoPath(
      oldPath: face.photoFilePath,
      newPath: best.key,
    );

    return best.key;
  }

  Future<void> _compareRecognition(DetectedFaceRecord face) async {
    if (_comparing) return;

    final oldMatch = _bestKnownMatch(face);
    if (_knownFaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identify at least one person first.')),
      );
      return;
    }

    var sourcePath = face.photoFilePath;
    if (!await File(sourcePath).exists()) {
      setState(() => _comparing = true);
      try {
        final recovered = await _recoverMissingSourcePhoto(face);
        if (!mounted) return;

        if (recovered == null) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Source photo not recovered yet'),
              content: const Text(
                'Heirloom Atlas searched the currently indexed face library '
                'but did not find a match strong enough to reconnect this '
                'photo safely. Nothing was changed.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }

        sourcePath = recovered;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Heirloom Atlas found the current source photo automatically.',
            ),
          ),
        );
      } finally {
        if (mounted) setState(() => _comparing = false);
      }
    }

    setState(() => _comparing = true);

    try {
      final detectorHelper = FaceRecognitionService();
      final targetBytes = await File(sourcePath).readAsBytes();
      final targetFaces = await detectorHelper.detectFacesWithMesh(targetBytes);
      if (targetFaces.isEmpty) {
        throw StateError('Could not re-detect the selected face.');
      }

      final targetFace = detectorHelper.closestFaceToRecord(targetFaces, face);
      final targetEmbedding = await _sfaceService.embeddingForFaceBytes(
        targetBytes,
        targetFace,
      );

      final scores = <MapEntry<String, double>>[];

      for (final name in _knownNames) {
        final references = _knownFaces
            .where((known) => known.personName == name)
            .take(5);
        final similarities = <double>[];

        for (final reference in references) {
          try {
            final bytes = await File(reference.photoFilePath).readAsBytes();
            final detected = await detectorHelper.detectFacesWithMesh(bytes);
            if (detected.isEmpty) continue;

            final referenceFace = detectorHelper.closestFaceToRecord(
              detected,
              reference,
            );
            final embedding = await _sfaceService.embeddingForFaceBytes(
              bytes,
              referenceFace,
            );

            similarities.add(
              SFaceRecognitionService.cosineSimilarity(
                targetEmbedding,
                embedding,
              ),
            );
          } catch (_) {
            // Skip an unusable reference rather than failing the whole test.
          }
        }

        if (similarities.isEmpty) continue;
        similarities.sort((a, b) => b.compareTo(a));
        final top = similarities.take(3).toList();
        final score = top.reduce((a, b) => a + b) / top.length;
        scores.add(MapEntry(name, score));
      }

      scores.sort((a, b) => b.value.compareTo(a.value));
      final sfaceBest = scores.isEmpty ? null : scores.first;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recognition Engine Comparison'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Test only — nothing will be saved or identified.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                Text('Current engine: ${oldMatch?.key ?? "No recommendation"}'),
                if (oldMatch != null)
                  Text('Score: ${(oldMatch.value * 100).toStringAsFixed(1)}%'),
                const SizedBox(height: 14),
                Text('SFace: ${sfaceBest?.key ?? "No result"}'),
                if (sfaceBest != null)
                  Text('Cosine score: ${sfaceBest.value.toStringAsFixed(3)}'),
                if (scores.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    'SFace runner-up: ${scores[1].key} '
                    '(${scores[1].value.toStringAsFixed(3)})',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Comparison could not run'),
          content: SelectableText(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _comparing = false);
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
      final query = _search.trim().toLowerCase();
      if (query.isNotEmpty &&
          !face.photoFilePath.toLowerCase().contains(query)) {
        return false;
      }

      final liveDecision = _liveSFaceDecision(face);
      switch (_recommendationFilter) {
        case 'likely':
          return liveDecision?.isHigh == true;
        case 'possible':
          return liveDecision?.isPossible == true;
        case 'review':
          return liveDecision == null;
        default:
          return true;
      }
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
              if (_missingSourceFaces.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.photo_library_outlined, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_missingSourceFaces.length} face'
                          '${_missingSourceFaces.length == 1 ? '' : 's'} '
                          'from missing source photos are preserved but hidden '
                          'from recognition review.',
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                margin: EdgeInsets.fromLTRB(
                  18,
                  _missingSourceFaces.isNotEmpty ? 10 : 14,
                  18,
                  0,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 1120;

                    final intro = Row(
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
                      ],
                    );

                    final controls = Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _recommendationFilter,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.filter_alt_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  'All recommendations',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'likely',
                                child: Text('Likely matches'),
                              ),
                              DropdownMenuItem(
                                value: 'possible',
                                child: Text('Possible matches'),
                              ),
                              DropdownMenuItem(
                                value: 'review',
                                child: Text('Needs review'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _recommendationFilter = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
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
                    );

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          intro,
                          const SizedBox(height: 12),
                          controls,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: intro),
                        const SizedBox(width: 16),
                        SizedBox(width: 500, child: controls),
                      ],
                    );
                  },
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
                    final liveDecision = _liveSFaceDecision(face);
                    final suggestion = liveDecision?.personName;
                    final suggestionScore = liveDecision?.score;

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
                                  Row(
                                    children: [
                                      Icon(
                                        liveDecision!.isHigh
                                            ? Icons.verified_outlined
                                            : Icons.auto_awesome,
                                        size: 18,
                                        color: liveDecision.isHigh
                                            ? Colors.green
                                            : Colors.amber,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${liveDecision.label}: $suggestion',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: liveDecision.isHigh
                                                ? Colors.green
                                                : Colors.amber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'SFace ${suggestionScore.toStringAsFixed(3)}  •  '
                                    'margin ${liveDecision.margin.toStringAsFixed(3)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 7),
                                ] else ...[
                                  const Row(
                                    children: [
                                      Icon(Icons.help_outline, size: 18),
                                      SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Needs review — no recommendation',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
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
