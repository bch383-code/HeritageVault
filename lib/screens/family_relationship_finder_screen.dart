import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';

class FamilyRelationshipFinderScreen extends StatefulWidget {
  const FamilyRelationshipFinderScreen({super.key});

  @override
  State<FamilyRelationshipFinderScreen> createState() =>
      _FamilyRelationshipFinderScreenState();
}

class _FamilyRelationshipFinderScreenState
    extends State<FamilyRelationshipFinderScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  static const Color _heritageGold = Color(0xFFC9A65A);
  static const Color _heritageCream = Color(0xFFF3E9D1);
  static const Color _panelNavy = Color(0xFF081E33);
  static const Color _panelNavyLight = Color(0xFF102A40);

  FamilyPerson? _personOne;
  FamilyPerson? _personTwo;
  _RelationshipResult? _result;
  List<_RelationshipResult> _results = const [];
  int _resultIndex = 0;
  bool _finding = false;

  Future<FamilyPerson?> _choosePerson({
    required String title,
    int? excludeId,
  }) async {
    final controller = TextEditingController();
    List<FamilyPerson> results = const [];
    bool searching = false;

    final selected = await showDialog<FamilyPerson>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> search(String value) async {
            final query = value.trim();
            if (query.length < 2) {
              setDialogState(() {
                results = const [];
                searching = false;
              });
              return;
            }

            setDialogState(() => searching = true);
            final matches =
                await _databaseHelper.getFamilyPeople(searchText: query);
            if (!dialogContext.mounted) return;

            setDialogState(() {
              results = matches
                  .where((person) => person.id != excludeId)
                  .take(75)
                  .toList();
              searching = false;
            });
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 620,
              height: 500,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search family tree',
                      hintText: 'Type at least 2 letters',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: searching
                        ? const Center(child: CircularProgressIndicator())
                        : results.isEmpty
                            ? const Center(
                                child: Text('Search for a family person.'),
                              )
                            : ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final person = results[index];
                                  return ListTile(
                                    leading: _avatar(person),
                                    title: Text(person.displayName),
                                    subtitle: person.lifeSpan.isEmpty
                                        ? null
                                        : Text(person.lifeSpan),
                                    onTap: () =>
                                        Navigator.pop(dialogContext, person),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();
    return selected;
  }

  Widget _avatar(FamilyPerson person, {double radius = 22}) {
    final photoPath = person.profilePhotoPath.trim();
    final hasPhoto = photoPath.isNotEmpty && File(photoPath).existsSync();

    return CircleAvatar(
      radius: radius,
      backgroundColor: _panelNavyLight,
      backgroundImage: hasPhoto ? FileImage(File(photoPath)) : null,
      child: hasPhoto
          ? null
          : const Icon(Icons.person_outline, color: _heritageCream),
    );
  }

  Future<void> _selectFirst() async {
    final person = await _choosePerson(
      title: 'Choose First Person',
      excludeId: _personTwo?.id,
    );
    if (person == null || !mounted) return;
    setState(() {
      _personOne = person;
      _result = null;
      _results = const [];
      _resultIndex = 0;
    });
  }

  Future<void> _selectSecond() async {
    final person = await _choosePerson(
      title: 'Choose Second Person',
      excludeId: _personOne?.id,
    );
    if (person == null || !mounted) return;
    setState(() {
      _personTwo = person;
      _result = null;
      _results = const [];
      _resultIndex = 0;
    });
  }

  Future<void> _findRelationship() async {
    final first = _personOne;
    final second = _personTwo;
    if (first?.id == null || second?.id == null) return;

    setState(() => _finding = true);
    try {
      final results = await _buildRelationships(first!, second!);
      if (!mounted) return;
      setState(() {
        _results = results;
        _resultIndex = 0;
        _result = results.isEmpty ? null : results.first;
      });
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<List<_RelationshipResult>> _buildRelationships(
    FamilyPerson start,
    FamilyPerson target,
  ) async {
    final bloodResults = await _buildBloodRelationshipPaths(start, target);
    if (bloodResults.isNotEmpty) {
      return bloodResults.take(8).toList();
    }

    // If there is no direct blood relationship path, keep the existing
    // parent/child/spouse graph search as the fallback.
    return [await _buildRelationship(start, target)];
  }

  Future<List<_RelationshipResult>> _buildBloodRelationshipPaths(
    FamilyPerson start,
    FamilyPerson target,
  ) async {
    final startId = start.id!;
    final targetId = target.id!;

    final startPaths = await _ancestorPaths(start, maxDepth: 9);
    final targetPaths = await _ancestorPaths(target, maxDepth: 9);

    final commonIds =
        startPaths.keys.toSet().intersection(targetPaths.keys.toSet()).toList();

    if (commonIds.isEmpty) return const [];

    final candidates = <_RelationshipCandidate>[];

    for (final commonId in commonIds) {
      final leftPaths = startPaths[commonId] ?? const <_AncestorPath>[];
      final rightPaths = targetPaths[commonId] ?? const <_AncestorPath>[];

      for (final left in leftPaths) {
        for (final right in rightPaths) {
          // Do not use a path that loops through the same person on both
          // branches below the common ancestor.
          final leftBelow =
              left.people.take(left.people.length - 1).map((p) => p.id).toSet();
          final rightBelow =
              right.people.take(right.people.length - 1).map((p) => p.id).toSet();
          if (leftBelow.intersection(rightBelow).isNotEmpty &&
              startId != targetId) {
            continue;
          }

          final combined = <_RelationshipPathItem>[];

          for (var i = 0; i < left.people.length; i++) {
            combined.add(
              _RelationshipPathItem(
                person: left.people[i],
                relation: i == 0 ? '' : left.parentRoles[i - 1],
              ),
            );
          }

          final reversedRight = right.people.reversed.toList();
          for (var i = 1; i < reversedRight.length; i++) {
            combined.add(
              _RelationshipPathItem(
                person: reversedRight[i],
                relation: 'Child',
              ),
            );
          }

          final signature =
              combined.map((item) => item.person.id ?? -1).join('>');
          final title = _relationshipTitle(combined) ??
              '${combined.length - 1} relationship steps apart';

          candidates.add(
            _RelationshipCandidate(
              commonAncestorId: commonId,
              path: combined,
              signature: signature,
              title: title,
              score: combined.length,
            ),
          );
        }
      }
    }

    // Deduplicate exact routes.
    final bySignature = <String, _RelationshipCandidate>{};
    for (final candidate in candidates) {
      final existing = bySignature[candidate.signature];
      if (existing == null || candidate.score < existing.score) {
        bySignature[candidate.signature] = candidate;
      }
    }

    var unique = bySignature.values.toList();

    // Suppress distant shared ancestors when a closer common ancestor already
    // lies on both sides of that same route. This prevents a single cousin
    // relationship from also appearing again through every earlier ancestor.
    unique = unique.where((candidate) {
      final commonIndex = _commonAncestorIndex(candidate.path);
      if (commonIndex == null) return true;

      final leftIds = candidate.path
          .take(commonIndex)
          .map((item) => item.person.id)
          .whereType<int>()
          .toSet();
      final rightIds = candidate.path
          .skip(commonIndex + 1)
          .map((item) => item.person.id)
          .whereType<int>()
          .toSet();

      return !unique.any((other) {
        if (identical(other, candidate)) return false;
        return leftIds.contains(other.commonAncestorId) &&
            rightIds.contains(other.commonAncestorId);
      });
    }).toList();

    unique.sort((a, b) {
      final scoreCompare = a.score.compareTo(b.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.title.compareTo(b.title);
    });

    final results = <_RelationshipResult>[];
    for (final candidate in unique) {
      final title = candidate.title;
      results.add(
        _RelationshipResult(
          title: title,
          description:
              '${target.displayName} is ${_articleFor(title)} $title of '
              '${start.displayName}.',
          path: candidate.path,
        ),
      );
    }

    return results;
  }

  Future<Map<int, List<_AncestorPath>>> _ancestorPaths(
    FamilyPerson source, {
    required int maxDepth,
  }) async {
    final sourceId = source.id;
    if (sourceId == null) return const {};

    final results = <int, List<_AncestorPath>>{
      sourceId: [
        _AncestorPath(
          people: [source],
          parentRoles: const [],
        ),
      ],
    };

    final queue = Queue<_AncestorPath>()
      ..add(
        _AncestorPath(
          people: [source],
          parentRoles: const [],
        ),
      );

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final depth = current.people.length - 1;
      if (depth >= maxDepth) continue;

      final child = current.people.last;
      final childId = child.id;
      if (childId == null) continue;

      final parents = await _databaseHelper.getFamilyParents(childId);
      for (final parent in parents) {
        final parentId = parent.id;
        if (parentId == null) continue;

        // Protect against malformed cycles in imported trees.
        if (current.people.any((person) => person.id == parentId)) continue;

        final role = await _databaseHelper.getFamilyParentRole(
          parentId: parentId,
          childId: childId,
        );

        final next = _AncestorPath(
          people: [...current.people, parent],
          parentRoles: [...current.parentRoles, role],
        );

        final bucket = results.putIfAbsent(parentId, () => []);
        final signature = next.people.map((p) => p.id ?? -1).join('>');
        final alreadyStored = bucket.any(
          (path) => path.people.map((p) => p.id ?? -1).join('>') == signature,
        );

        // Keep a few distinct routes to the same ancestor so pedigree
        // collapse/endogamy can produce multiple legitimate relationships.
        if (!alreadyStored && bucket.length < 3) {
          bucket.add(next);
          queue.add(next);
        }
      }
    }

    return results;
  }

  Future<_RelationshipResult> _buildRelationship(
    FamilyPerson start,
    FamilyPerson target,
  ) async {
    final startId = start.id!;
    final targetId = target.id!;

    final peopleById = <int, FamilyPerson>{
      startId: start,
      targetId: target,
    };
    final queue = Queue<int>()..add(startId);
    final visited = <int>{startId};
    final previous = <int, _PathStep>{};

    while (queue.isNotEmpty) {
      final currentId = queue.removeFirst();
      if (currentId == targetId) break;

      final parents = await _databaseHelper.getFamilyParents(currentId);
      final children = await _databaseHelper.getFamilyChildren(currentId);
      final spouses = await _databaseHelper.getFamilySpouses(currentId);

      for (final parent in parents) {
        final id = parent.id;
        if (id == null) continue;
        peopleById[id] = parent;
        if (visited.add(id)) {
          final role = await _databaseHelper.getFamilyParentRole(
            parentId: id,
            childId: currentId,
          );
          previous[id] = _PathStep(
            previousId: currentId,
            relationFromPrevious: role,
          );
          queue.add(id);
        }
      }

      for (final child in children) {
        final id = child.id;
        if (id == null) continue;
        peopleById[id] = child;
        if (visited.add(id)) {
          previous[id] = _PathStep(
            previousId: currentId,
            relationFromPrevious: 'Child',
          );
          queue.add(id);
        }
      }

      for (final spouse in spouses) {
        final id = spouse.id;
        if (id == null) continue;
        peopleById[id] = spouse;
        if (visited.add(id)) {
          previous[id] = _PathStep(
            previousId: currentId,
            relationFromPrevious: 'Spouse',
          );
          queue.add(id);
        }
      }
    }

    if (!visited.contains(targetId)) {
      return _RelationshipResult(
        title: 'No recorded relationship found',
        description:
            'Heirloom Atlas could not connect these two people using the '
            'parent, child, and spouse relationships currently recorded.',
        path: const [],
      );
    }

    final reversedIds = <int>[targetId];
    var cursor = targetId;
    while (cursor != startId) {
      final step = previous[cursor];
      if (step == null) break;
      cursor = step.previousId;
      reversedIds.add(cursor);
    }
    final ids = reversedIds.reversed.toList();

    final path = <_RelationshipPathItem>[];
    for (var index = 0; index < ids.length; index++) {
      final id = ids[index];
      var person = peopleById[id];
      person ??= await _databaseHelper.getFamilyPerson(id);
      if (person == null) continue;

      String relation = '';
      if (index > 0) {
        relation = previous[id]?.relationFromPrevious ?? '';
      }
      path.add(_RelationshipPathItem(person: person, relation: relation));
    }

    final relationshipTitle = _relationshipTitle(path);
    return _RelationshipResult(
      title: relationshipTitle ?? '${path.length - 1} relationship steps apart',
      description: relationshipTitle != null
          ? '${target.displayName} is ${_articleFor(relationshipTitle)} '
              '$relationshipTitle of ${start.displayName}.'
          : 'This is the shortest recorded path between '
              '${start.displayName} and ${target.displayName}.',
      path: path,
    );
  }

  String _articleFor(String relationship) {
    final first = relationship.trim().toLowerCase();
    if (first.isEmpty) return 'a';
    return 'aeiou'.contains(first[0]) ? 'an' : 'a';
  }

  bool _isParentRelation(String relation) {
    final value = relation.toLowerCase();
    return value == 'parent' || value == 'father' || value == 'mother';
  }

  bool _isChildRelation(String relation) =>
      relation.toLowerCase() == 'child';

  String _gendered(
    FamilyPerson person, {
    required String male,
    required String female,
    required String neutral,
  }) {
    final sex = person.sex.trim().toLowerCase();
    if (sex == 'm' || sex == 'male') return male;
    if (sex == 'f' || sex == 'female') return female;
    return neutral;
  }

  String _ancestorTitle(FamilyPerson person, int generations) {
    if (generations == 1) {
      return _gendered(
        person,
        male: 'father',
        female: 'mother',
        neutral: 'parent',
      );
    }
    if (generations == 2) {
      return _gendered(
        person,
        male: 'grandfather',
        female: 'grandmother',
        neutral: 'grandparent',
      );
    }
    final prefix = List.filled(generations - 2, 'great').join('-');
    return _gendered(
      person,
      male: '$prefix-grandfather',
      female: '$prefix-grandmother',
      neutral: '$prefix-grandparent',
    );
  }

  String _descendantTitle(FamilyPerson person, int generations) {
    if (generations == 1) {
      return _gendered(
        person,
        male: 'son',
        female: 'daughter',
        neutral: 'child',
      );
    }
    if (generations == 2) {
      return _gendered(
        person,
        male: 'grandson',
        female: 'granddaughter',
        neutral: 'grandchild',
      );
    }
    final prefix = List.filled(generations - 2, 'great').join('-');
    return _gendered(
      person,
      male: '$prefix-grandson',
      female: '$prefix-granddaughter',
      neutral: '$prefix-grandchild',
    );
  }

  String? _relationshipTitle(List<_RelationshipPathItem> path) {
    if (path.isEmpty) return null;
    if (path.length == 1) return 'same person';

    final target = path.last.person;
    final relations = path.skip(1).map((item) => item.relation).toList();

    if (relations.every(_isParentRelation)) {
      return _ancestorTitle(target, relations.length);
    }

    if (relations.every(_isChildRelation)) {
      return _descendantTitle(target, relations.length);
    }

    if (relations.length == 1 &&
        relations.first.toLowerCase() == 'spouse') {
      return _gendered(
        target,
        male: 'husband',
        female: 'wife',
        neutral: 'spouse',
      );
    }

    // Start -> parent -> child means the target is a sibling.
    if (relations.length == 2 &&
        _isParentRelation(relations[0]) &&
        _isChildRelation(relations[1])) {
      return _gendered(
        target,
        male: 'brother',
        female: 'sister',
        neutral: 'sibling',
      );
    }

    // Start -> parent -> sibling -> child means aunt/uncle.
    if (relations.length == 3 &&
        _isParentRelation(relations[0]) &&
        _isParentRelation(relations[1]) &&
        _isChildRelation(relations[2])) {
      return _gendered(
        target,
        male: 'uncle',
        female: 'aunt',
        neutral: 'aunt/uncle',
      );
    }

    // Start -> child -> sibling -> parent means niece/nephew.
    if (relations.length == 3 &&
        _isChildRelation(relations[0]) &&
        _isChildRelation(relations[1]) &&
        _isParentRelation(relations[2])) {
      return _gendered(
        target,
        male: 'nephew',
        female: 'niece',
        neutral: 'niece/nephew',
      );
    }

    // Cousin paths rise through parents to a shared ancestor, then descend.
    var up = 0;
    while (up < relations.length && _isParentRelation(relations[up])) {
      up++;
    }
    var down = 0;
    var index = up;
    while (index < relations.length && _isChildRelation(relations[index])) {
      down++;
      index++;
    }

    if (up >= 2 && down >= 2 && index == relations.length) {
      final degree = (up < down ? up : down) - 1;
      final removed = (up - down).abs();
      final ordinal = _ordinal(degree);
      if (removed == 0) return '$ordinal cousin';
      return '$ordinal cousin ${_removedText(removed)}';
    }

    return null;
  }

  String _ordinal(int number) {
    const words = <int, String>{
      1: 'first',
      2: 'second',
      3: 'third',
      4: 'fourth',
      5: 'fifth',
      6: 'sixth',
      7: 'seventh',
      8: 'eighth',
      9: 'ninth',
      10: 'tenth',
    };
    return words[number] ?? '${number}th';
  }

  String _removedText(int removed) {
    const words = <int, String>{
      1: 'once removed',
      2: 'twice removed',
      3: 'three times removed',
      4: 'four times removed',
    };
    return words[removed] ?? '$removed times removed';
  }

  Future<void> _openPerson(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FamilyPersonScreen(person: person)),
    );
  }

  int? _commonAncestorIndex(List<_RelationshipPathItem> path) {
    if (path.length < 3) return null;
    final relations = path.skip(1).map((item) => item.relation).toList();

    var up = 0;
    while (up < relations.length && _isParentRelation(relations[up])) {
      up++;
    }
    if (up == 0 || up >= relations.length) return null;

    var i = up;
    while (i < relations.length && _isChildRelation(relations[i])) {
      i++;
    }
    return i == relations.length ? up : null;
  }

  Widget _relationshipTree(List<_RelationshipPathItem> path) {
    final commonIndex = _commonAncestorIndex(path);
    if (commonIndex == null) return _linearRelationshipPath(path);

    final common = path[commonIndex].person;
    final leftBranch = path.sublist(0, commonIndex).reversed.toList();
    final rightBranch = path.sublist(commonIndex + 1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: _panelNavyLight.withValues(alpha: .24),
        border: Border.all(
          color: _heritageGold.withValues(alpha: .18),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Text(
            'COMMON ANCESTOR',
            style: TextStyle(
              color: _heritageGold.withValues(alpha: .88),
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: 390,
            child: _treePersonCard(common, emphasized: true),
          ),
          const SizedBox(height: 2),
          Container(
            width: 1,
            height: 24,
            color: _heritageGold.withValues(alpha: .60),
          ),
          SizedBox(
            width: double.infinity,
            height: 28,
            child: CustomPaint(
              painter: _RelationshipForkPainter(
                color: _heritageGold.withValues(alpha: .60),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _branchColumn(
                  leftBranch,
                  sideLabel: _personOne?.displayName ?? 'First person',
                ),
              ),
              const SizedBox(width: 44),
              Expanded(
                child: _branchColumn(
                  rightBranch,
                  sideLabel: _personTwo?.displayName ?? 'Second person',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _branchColumn(
    List<_RelationshipPathItem> branch, {
    required String sideLabel,
  }) {
    return Column(
      children: [
        for (var i = 0; i < branch.length; i++) ...[
          if (i > 0) ...[
            Container(
              width: 1,
              height: 10,
              color: _heritageGold.withValues(alpha: .48),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: _heritageGold,
            ),
            Container(
              width: 1,
              height: 6,
              color: _heritageGold.withValues(alpha: .48),
            ),
          ],
          _treePersonCard(
            branch[i].person,
            emphasized: i == branch.length - 1,
          ),
        ],
      ],
    );
  }

  Widget _treePersonCard(FamilyPerson person, {bool emphasized = false}) {
    return InkWell(
      onTap: () => _openPerson(person),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: emphasized
              ? _panelNavyLight
              : _panelNavyLight.withValues(alpha: .58),
          border: Border.all(
            color: _heritageGold.withValues(alpha: emphasized ? .48 : .22),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            _avatar(person, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (person.lifeSpan.isNotEmpty)
                    Text(
                      person.lifeSpan,
                      style: TextStyle(
                        color: _heritageCream.withValues(alpha: .58),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: _heritageGold),
          ],
        ),
      ),
    );
  }

  Widget _linearRelationshipPath(List<_RelationshipPathItem> path) {
    return Column(
      children: [
        for (var i = 0; i < path.length; i++) ...[
          if (i > 0) ...[
            const Icon(Icons.arrow_downward, size: 16, color: _heritageGold),
            const SizedBox(height: 4),
            Text(
              path[i].relation,
              style: const TextStyle(
                color: _heritageGold,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
          ],
          _treePersonCard(path[i].person),
          if (i < path.length - 1) const SizedBox(height: 5),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relationships')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _panelNavy,
              border: Border.all(
                color: _heritageGold.withValues(alpha: .38),
                width: .8,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RELATIONSHIP FINDER',
                  style: TextStyle(
                    color: _heritageGold.withValues(alpha: .88),
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'How are they related?',
                  style: TextStyle(
                    color: _heritageCream,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose any two people in the family tree. Heirloom Atlas '
                  'will trace the shortest recorded path between them.',
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .68),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _personPicker(
                        label: 'FIRST PERSON',
                        person: _personOne,
                        onTap: _selectFirst,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Icon(
                        Icons.compare_arrows,
                        color: _heritageGold.withValues(alpha: .8),
                        size: 30,
                      ),
                    ),
                    Expanded(
                      child: _personPicker(
                        label: 'SECOND PERSON',
                        person: _personTwo,
                        onTap: _selectSecond,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _personOne != null &&
                            _personTwo != null &&
                            !_finding
                        ? _findRelationship
                        : null,
                    icon: _finding
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.route_outlined),
                    label: Text(
                      _finding ? 'Finding Relationship...' : 'Find Relationship',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_result != null) _resultCard(_result!),
        ],
      ),
    );
  }

  Widget _personPicker({
    required String label,
    required FamilyPerson? person,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panelNavyLight,
          border: Border.all(
            color: _heritageGold.withValues(alpha: .24),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (person != null) _avatar(person) else
              const CircleAvatar(
                backgroundColor: _panelNavy,
                child: Icon(Icons.person_search_outlined,
                    color: _heritageCream),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: _heritageGold.withValues(alpha: .8),
                      fontSize: 10,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    person?.displayName ?? 'Choose a person',
                    style: const TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (person != null && person.lifeSpan.isNotEmpty)
                    Text(
                      person.lifeSpan,
                      style: TextStyle(
                        color: _heritageCream.withValues(alpha: .58),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _heritageGold),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(_RelationshipResult result) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _panelNavy,
        border: Border.all(
          color: _heritageGold.withValues(alpha: .32),
          width: .8,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'RELATIONSHIP',
                  style: TextStyle(
                    color: _heritageGold.withValues(alpha: .84),
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_results.length > 1) ...[
                Text(
                  '${_resultIndex + 1} of ${_results.length}',
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .62),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Previous relationship',
                  onPressed: _resultIndex == 0
                      ? null
                      : () {
                          setState(() {
                            _resultIndex--;
                            _result = _results[_resultIndex];
                          });
                        },
                  icon: const Icon(Icons.chevron_left),
                  color: _heritageGold,
                ),
                IconButton(
                  tooltip: 'Next relationship',
                  onPressed: _resultIndex >= _results.length - 1
                      ? null
                      : () {
                          setState(() {
                            _resultIndex++;
                            _result = _results[_resultIndex];
                          });
                        },
                  icon: const Icon(Icons.chevron_right),
                  color: _heritageGold,
                ),
              ],
            ],
          ),
          if (_results.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              '${_results.length} relationship paths found',
              style: TextStyle(
                color: _heritageGold.withValues(alpha: .72),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            result.title,
            style: const TextStyle(
              color: _heritageCream,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            result.description,
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .65),
            ),
          ),
          if (result.path.isNotEmpty) ...[
            const SizedBox(height: 22),
            _relationshipTree(result.path),
          ],
        ],
      ),
    );
  }
}

class _RelationshipForkPainter extends CustomPainter {
  final Color color;

  const _RelationshipForkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final leftX = size.width * .25;
    final rightX = size.width * .75;
    final midY = size.height * .40;

    final path = Path()
      ..moveTo(centerX, 0)
      ..lineTo(centerX, midY)
      ..lineTo(leftX, midY)
      ..lineTo(leftX, size.height)
      ..moveTo(centerX, midY)
      ..lineTo(rightX, midY)
      ..lineTo(rightX, size.height);

    canvas.drawPath(path, paint);

    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(centerX, midY), 2.2, dot);
  }

  @override
  bool shouldRepaint(covariant _RelationshipForkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _AncestorPath {
  final List<FamilyPerson> people;
  final List<String> parentRoles;

  const _AncestorPath({
    required this.people,
    required this.parentRoles,
  });
}

class _RelationshipCandidate {
  final int commonAncestorId;
  final List<_RelationshipPathItem> path;
  final String signature;
  final String title;
  final int score;

  const _RelationshipCandidate({
    required this.commonAncestorId,
    required this.path,
    required this.signature,
    required this.title,
    required this.score,
  });
}

class _PathStep {
  final int previousId;
  final String relationFromPrevious;

  const _PathStep({
    required this.previousId,
    required this.relationFromPrevious,
  });
}

class _RelationshipPathItem {
  final FamilyPerson person;
  final String relation;

  const _RelationshipPathItem({
    required this.person,
    required this.relation,
  });
}

class _RelationshipResult {
  final String title;
  final String description;
  final List<_RelationshipPathItem> path;

  const _RelationshipResult({
    required this.title,
    required this.description,
    required this.path,
  });
}
