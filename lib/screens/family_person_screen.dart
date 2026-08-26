import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_edit_screen.dart';
import 'family_relationship_picker_screen.dart';
import 'family_visual_tree_screen.dart';

class FamilyPersonScreen extends StatefulWidget {
  final FamilyPerson person;

  const FamilyPersonScreen({super.key, required this.person});

  @override
  State<FamilyPersonScreen> createState() => _FamilyPersonScreenState();
}

class _FamilyPersonScreenState extends State<FamilyPersonScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  late FamilyPerson _person;
  List<FamilyPerson> _parents = const [];
  List<FamilyPerson> _spouses = const [];
  List<FamilyPerson> _children = const [];
  Map<int, String> _parentRoles = const {};
  bool _loadingRelationships = true;

  String? _linkedPhotoPersonName;
  List<String> _linkedPhotoPaths = const [];
  List<String> _linkedGroups = const [];
  bool _loadingConnections = true;

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final id = _person.id;
    if (id == null) return;

    final refreshed = await _databaseHelper.getFamilyPerson(id);
    final parents = await _databaseHelper.getFamilyParents(id);
    final spouses = await _databaseHelper.getFamilySpouses(id);
    final children = await _databaseHelper.getFamilyChildren(id);

    final photoPersonLinks = await _databaseHelper
        .getPhotoPersonFamilyTreeLinks();
    String? linkedPhotoPersonName;
    for (final entry in photoPersonLinks.entries) {
      if (entry.value == id) {
        linkedPhotoPersonName = entry.key;
        break;
      }
    }

    final linkedPhotoPaths = <String>{};
    final linkedGroups = <String>[];

    if (linkedPhotoPersonName != null) {
      final confirmedFaces = await _databaseHelper.getConfirmedFaces();
      for (final face in confirmedFaces) {
        if (face.personName.trim().toLowerCase() ==
            linkedPhotoPersonName.toLowerCase()) {
          linkedPhotoPaths.add(face.photoFilePath);
        }
      }

      final groups = await _databaseHelper.getPersonGroups();
      for (final group in groups) {
        final groupId = group['id'] as int?;
        final groupName = group['name'] as String? ?? '';
        if (groupId == null || groupName.isEmpty) continue;

        final names = await _databaseHelper.getPersonNamesForGroup(groupId);
        if (names.any(
          (name) =>
              name.trim().toLowerCase() == linkedPhotoPersonName!.toLowerCase(),
        )) {
          linkedGroups.add(groupName);
        }
      }
    }

    final roles = <int, String>{};
    for (final parent in parents) {
      final parentId = parent.id;
      if (parentId == null) continue;
      roles[parentId] = await _databaseHelper.getFamilyParentRole(
        parentId: parentId,
        childId: id,
      );
    }

    if (!mounted) return;

    setState(() {
      if (refreshed != null) _person = refreshed;
      _parents = parents;
      _spouses = spouses;
      _children = children;
      _parentRoles = roles;
      _loadingRelationships = false;
      _linkedPhotoPersonName = linkedPhotoPersonName;
      _linkedPhotoPaths = linkedPhotoPaths.toList()..sort();
      _linkedGroups = linkedGroups
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _loadingConnections = false;
    });
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyPersonEditScreen(person: _person),
      ),
    );

    await _loadAll();
  }

  Future<void> _addRelationship(String type) async {
    final selected = await Navigator.push<FamilyPerson>(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyRelationshipPickerScreen(
          currentPerson: _person,
          relationshipType: type,
        ),
      ),
    );

    if (selected == null || selected.id == null || _person.id == null) {
      return;
    }

    switch (type) {
      case 'Father':
        await _databaseHelper.addFamilyParentChild(
          parentId: selected.id!,
          childId: _person.id!,
          parentRole: 'Father',
        );
        break;
      case 'Mother':
        await _databaseHelper.addFamilyParentChild(
          parentId: selected.id!,
          childId: _person.id!,
          parentRole: 'Mother',
        );
        break;
      case 'Spouse':
        await _databaseHelper.addFamilySpouse(
          person1Id: _person.id!,
          person2Id: selected.id!,
        );
        break;
      case 'Child':
        String role = 'Parent';
        if (_person.sex == 'Male') role = 'Father';
        if (_person.sex == 'Female') role = 'Mother';

        await _databaseHelper.addFamilyParentChild(
          parentId: _person.id!,
          childId: selected.id!,
          parentRole: role,
        );
        break;
    }

    await _loadAll();
  }

  Future<void> _openRelative(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FamilyPersonScreen(person: person)),
    );

    await _loadAll();
  }

  Future<void> _removeParent(FamilyPerson parent) async {
    if (_person.id == null || parent.id == null) return;

    await _databaseHelper.removeFamilyParentChild(
      parentId: parent.id!,
      childId: _person.id!,
    );

    await _loadAll();
  }

  Future<void> _removeSpouse(FamilyPerson spouse) async {
    if (_person.id == null || spouse.id == null) return;

    await _databaseHelper.removeFamilySpouse(
      person1Id: _person.id!,
      person2Id: spouse.id!,
    );

    await _loadAll();
  }

  Future<void> _removeChild(FamilyPerson child) async {
    if (_person.id == null || child.id == null) return;

    await _databaseHelper.removeFamilyParentChild(
      parentId: _person.id!,
      childId: child.id!,
    );

    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final path = _person.profilePhotoPath;
    final hasPhoto = path.isNotEmpty && File(path).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(_person.displayName),
        actions: [
          IconButton(
            tooltip: 'View family tree',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FamilyVisualTreeScreen(initialPerson: _person),
                ),
              );
              await _loadAll();
            },
            icon: const Icon(Icons.account_tree_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Add relationship',
            icon: const Icon(Icons.group_add_outlined),
            onSelected: _addRelationship,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'Father', child: Text('Add Father')),
              PopupMenuItem(value: 'Mother', child: Text('Add Mother')),
              PopupMenuItem(value: 'Spouse', child: Text('Add Spouse')),
              PopupMenuItem(value: 'Child', child: Text('Add Child')),
            ],
          ),
          IconButton(
            tooltip: 'Edit person',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 72,
                backgroundImage: hasPhoto ? FileImage(File(path)) : null,
                child: hasPhoto
                    ? null
                    : const Icon(Icons.person_outline, size: 70),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _person.displayName,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (_person.birthName.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text('Birth name: ${_person.birthName}'),
                    ],
                    if (_person.lifeSpan.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        _person.lifeSpan,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                    if (_person.sex.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(_person.sex),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          _lifeEventsCard(),
          const SizedBox(height: 18),
          _connectionsCard(),
          const SizedBox(height: 18),
          _relationshipsCard(),
          if (_person.biography.isNotEmpty)
            _textCard('Biography', _person.biography),
          if (_person.notes.isNotEmpty)
            _textCard('Research Notes', _person.notes),
        ],
      ),
    );
  }

  Widget _lifeEventsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Life Events'),
            const SizedBox(height: 14),
            _detail('Birth', _person.birthDate, _person.birthPlace),
            _detail('Death', _person.deathDate, _person.deathPlace),
          ],
        ),
      ),
    );
  }

  Widget _connectionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _title('Heirloom Atlas Connections')),
                if (_linkedPhotoPersonName != null)
                  const Chip(
                    avatar: Icon(Icons.link, size: 18),
                    label: Text('Linked'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Photos, groups, stories, documents, and heirlooms connected '
              'to this person will come together here.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            if (_loadingConnections)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_linkedPhotoPersonName == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person_search_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This Family Tree person is not linked to a Known '
                        'Person from Photos yet. Open Known People and link '
                        'the matching person to this Family Tree record.',
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.face_outlined)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Known Person',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(_linkedPhotoPersonName!),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _connectionStat(
                    icon: Icons.photo_library_outlined,
                    value: _linkedPhotoPaths.length.toString(),
                    label: _linkedPhotoPaths.length == 1 ? 'Photo' : 'Photos',
                  ),
                  _connectionStat(
                    icon: Icons.groups_outlined,
                    value: _linkedGroups.length.toString(),
                    label: _linkedGroups.length == 1 ? 'Group' : 'Groups',
                  ),
                  _connectionStat(
                    icon: Icons.auto_stories_outlined,
                    value: '—',
                    label: 'Stories',
                    muted: true,
                  ),
                  _connectionStat(
                    icon: Icons.description_outlined,
                    value: '—',
                    label: 'Documents',
                    muted: true,
                  ),
                  _connectionStat(
                    icon: Icons.inventory_2_outlined,
                    value: '—',
                    label: 'Heirlooms',
                    muted: true,
                  ),
                ],
              ),
              if (_linkedGroups.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Person Groups',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _linkedGroups
                      .map(
                        (group) => Chip(
                          avatar: const Icon(Icons.groups_outlined, size: 18),
                          label: Text(group),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (_linkedPhotoPaths.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Photos',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _linkedPhotoPaths.length > 12
                        ? 12
                        : _linkedPhotoPaths.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final photoPath = _linkedPhotoPaths[index];
                      final file = File(photoPath);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 132,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: file.existsSync()
                              ? Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  cacheWidth: 360,
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 36,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                if (_linkedPhotoPaths.length > 12) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Showing 12 of ${_linkedPhotoPaths.length} photos.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectionStat({
    required IconData icon,
    required String value,
    required String label,
    bool muted = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: muted
            ? scheme.surfaceContainerLow
            : scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(label),
        ],
      ),
    );
  }

  Widget _relationshipsCard() {
    if (_loadingRelationships) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _title('Family Relationships')),
                PopupMenuButton<String>(
                  tooltip: 'Add relationship',
                  onSelected: _addRelationship,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'Father', child: Text('Add Father')),
                    PopupMenuItem(value: 'Mother', child: Text('Add Mother')),
                    PopupMenuItem(value: 'Spouse', child: Text('Add Spouse')),
                    PopupMenuItem(value: 'Child', child: Text('Add Child')),
                  ],
                  child: const Chip(
                    avatar: Icon(Icons.add, size: 18),
                    label: Text('Add'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _relationshipSection(
              'Parents',
              _parents,
              labelFor: (person) {
                final id = person.id;
                return id == null ? 'Parent' : _parentRoles[id] ?? 'Parent';
              },
              onRemove: _removeParent,
            ),
            _relationshipSection(
              'Spouse(s)',
              _spouses,
              labelFor: (_) => 'Spouse',
              onRemove: _removeSpouse,
            ),
            _relationshipSection(
              'Children',
              _children,
              labelFor: (_) => 'Child',
              onRemove: _removeChild,
            ),
          ],
        ),
      ),
    );
  }

  Widget _relationshipSection(
    String title,
    List<FamilyPerson> people, {
    required String Function(FamilyPerson) labelFor,
    required Future<void> Function(FamilyPerson) onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (people.isEmpty)
            const Text('None recorded')
          else
            for (final person in people)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(person.displayName),
                subtitle: Text(labelFor(person)),
                onTap: () => _openRelative(person),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'remove') {
                      onRemove(person);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove Relationship'),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _title(String value) {
    return Text(
      value,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _detail(String label, String date, String place) {
    final value = [date, place].where((item) => item.isNotEmpty).join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? 'Not recorded' : value)),
        ],
      ),
    );
  }

  Widget _textCard(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_title(title), const SizedBox(height: 10), Text(text)],
          ),
        ),
      ),
    );
  }
}
