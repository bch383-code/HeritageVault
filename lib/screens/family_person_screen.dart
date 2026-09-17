import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import '../models/postcard.dart';
import '../models/sports_card.dart';
import '../models/custom_collection.dart';
import '../models/custom_collection_item.dart';
import '../models/antique.dart';
import 'family_person_edit_screen.dart';
import 'family_relationship_picker_screen.dart';
import 'family_visual_tree_screen.dart';
import 'family_fan_chart_screen.dart';
import 'photo_detail_screen.dart';
import 'postcard_edit_screen.dart';
import 'custom_collection_item_edit_screen.dart';
import 'sports_cards_screen.dart';
import 'antique_edit_screen.dart';

class FamilyPersonScreen extends StatefulWidget {
  final FamilyPerson person;

  const FamilyPersonScreen({super.key, required this.person});

  @override
  State<FamilyPersonScreen> createState() => _FamilyPersonScreenState();
}

class _FamilyPersonScreenState extends State<FamilyPersonScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final ScrollController _pageScrollController = ScrollController();

  final GlobalKey _photosSectionKey = GlobalKey();
  final GlobalKey _antiquesSectionKey = GlobalKey();
  final GlobalKey _postcardsSectionKey = GlobalKey();
  final GlobalKey _sportsCardsSectionKey = GlobalKey();
  final GlobalKey _documentsSectionKey = GlobalKey();
  final GlobalKey _heirloomsSectionKey = GlobalKey();
  final GlobalKey _groupsSectionKey = GlobalKey();
  final GlobalKey _otherSectionKey = GlobalKey();

  static const Color _heritageGold = Color(0xFFC9A65A);
  static const Color _heritageCream = Color(0xFFF3E9D1);
  static const Color _panelNavy = Color(0xFF081E33);

  late FamilyPerson _person;
  List<FamilyPerson> _parents = const [];
  List<FamilyPerson> _spouses = const [];
  List<FamilyPerson> _children = const [];
  Map<int, String> _parentRoles = const {};
  bool _loadingRelationships = true;

  String? _linkedPhotoPersonName;
  List<String> _linkedPhotoAliases = const [];
  String? _linkedFaceThumbnailPath;
  List<String> _linkedPhotoPaths = const [];
  Map<String, int> _linkedGroups = const {};
  List<_PersonCollectionLink> _linkedHeirlooms = const [];
  List<Postcard> _linkedPostcards = const [];
  List<SportsCard> _linkedSportsCards = const [];
  List<Antique> _linkedAntiques = const [];
  List<String> _linkedDocumentPaths = const [];
  List<_GenericFamilyConnection> _automaticConnections = const [];
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

    final legacyLinks = await _databaseHelper.getPhotoPersonFamilyTreeLinks();
    final savedAliases = await _databaseHelper
        .getPhotoPersonAliasesForFamilyPerson(id);

    final aliases = <String>{
      ...savedAliases
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty),
      ...legacyLinks.entries
          .where((entry) => entry.value == id)
          .map((entry) => entry.key.trim())
          .where((name) => name.isNotEmpty),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final linkedPhotoPersonName = aliases.isEmpty ? null : aliases.first;
    final aliasKeys = aliases.map((name) => name.toLowerCase()).toSet();

    final linkedPhotoPaths = <String>{};
    final linkedGroups = <String, int>{};
    String? linkedFaceThumbnailPath;

    if (aliasKeys.isNotEmpty) {
      final confirmedFaces = await _databaseHelper.getConfirmedFaces();
      for (final face in confirmedFaces) {
        if (aliasKeys.contains(face.personName.trim().toLowerCase())) {
          linkedPhotoPaths.add(face.photoFilePath);
          if (linkedFaceThumbnailPath == null &&
              face.thumbnailPath.trim().isNotEmpty &&
              File(face.thumbnailPath).existsSync()) {
            linkedFaceThumbnailPath = face.thumbnailPath;
          }
        }
      }

      final catalogRecords = await _databaseHelper.getAllPhotoCatalogMetadata();
      for (final record in catalogRecords) {
        if (record.people.any(
          (name) => aliasKeys.contains(name.trim().toLowerCase()),
        )) {
          linkedPhotoPaths.add(record.filePath);
        }
      }

      final groups = await _databaseHelper.getPersonGroups();
      for (final group in groups) {
        final groupId = (group['id'] as num?)?.toInt();
        final groupName = group['name'] as String? ?? '';
        if (groupId == null || groupName.isEmpty) continue;

        final names = await _databaseHelper.getPersonNamesForGroup(groupId);
        if (names.any(
          (name) => aliasKeys.contains(name.trim().toLowerCase()),
        )) {
          linkedGroups[groupName] = groupId;
        }
      }
    }

    // Also include direct Family Tree photo links, even if the photo has no alias.
    final directlyLinkedPhotoPaths = await _databaseHelper
        .getPhotoPathsForFamilyPeople([id]);
    linkedPhotoPaths.addAll(directlyLinkedPhotoPaths);

    final linkedItemKeys = await _databaseHelper.getItemKeysForFamilyPeople(
      personIds: [id],
      itemType: 'custom_collection_item',
    );
    final linkedItemIds = linkedItemKeys
        .map(int.tryParse)
        .whereType<int>()
        .toSet();

    final linkedHeirlooms = <_PersonCollectionLink>[];
    if (linkedItemIds.isNotEmpty) {
      final collections = await _databaseHelper.getCustomCollections();
      for (final collection in collections) {
        final collectionId = collection.id;
        if (collectionId == null) continue;
        final items = await _databaseHelper.getCustomCollectionItems(
          collectionId,
        );
        for (final item in items) {
          final itemId = item.id;
          if (itemId != null && linkedItemIds.contains(itemId)) {
            linkedHeirlooms.add(
              _PersonCollectionLink(collection: collection, item: item),
            );
          }
        }
      }
      linkedHeirlooms.sort(
        (a, b) =>
            a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase()),
      );
    }

    final postcardKeys = await _databaseHelper.getItemKeysForFamilyPeople(
      personIds: [id],
      itemType: 'postcard',
    );
    final postcardIds = postcardKeys.map(int.tryParse).whereType<int>().toSet();
    final allPostcards = await _databaseHelper.getPostcards();
    final linkedPostcards = allPostcards
        .where(
          (postcard) =>
              postcard.id != null && postcardIds.contains(postcard.id),
        )
        .toList();

    final documentKeys = await _databaseHelper.getItemKeysForFamilyPeople(
      personIds: [id],
      itemType: 'document',
    );
    final linkedDocumentPaths = documentKeys
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final sportsCardKeys = await _databaseHelper.getItemKeysForFamilyPeople(
      personIds: [id],
      itemType: 'sports_card',
    );
    final sportsCardIds = sportsCardKeys
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    final linkedSportsCards = <SportsCard>[];
    if (sportsCardIds.isNotEmpty) {
      final sets = await _databaseHelper.getInstalledSportsCardSets();
      for (final set in sets) {
        final sourceKey = set['source_key'] as String? ?? '';
        if (sourceKey.isEmpty) continue;
        final cards = await _databaseHelper.getSportsCards(
          sourceKey: sourceKey,
        );
        linkedSportsCards.addAll(
          cards.where(
            (card) => card.id != null && sportsCardIds.contains(card.id),
          ),
        );
      }
    }

    final antiqueKeys = await _databaseHelper.getItemKeysForFamilyPeople(
      personIds: [id],
      itemType: 'antique',
    );
    final antiqueIds = antiqueKeys.map(int.tryParse).whereType<int>().toSet();
    final allAntiques = await _databaseHelper.getAntiques();
    final linkedAntiques = allAntiques
        .where(
          (antique) =>
              antique.id != null && antiqueIds.contains(antique.id),
        )
        .toList()
      ..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );


    final rawFamilyLinks = await _databaseHelper.getFamilyItemLinksForPerson(id);
    const specializedTypes = <String>{
      'photo', 'document', 'postcard', 'sports_card', 'antique',
      'custom_collection_item', 'story',
    };
    final automaticConnections = rawFamilyLinks
        .where((link) => !specializedTypes.contains(link['itemType']))
        .map(
          (link) => _GenericFamilyConnection(
            itemType: link['itemType'] ?? '',
            itemKey: link['itemKey'] ?? '',
            role: link['role'] ?? DatabaseHelper.defaultFamilyItemRole,
          ),
        )
        .where((link) => link.itemType.isNotEmpty && link.itemKey.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final typeCompare = a.displayType.toLowerCase().compareTo(b.displayType.toLowerCase());
        if (typeCompare != 0) return typeCompare;
        return a.itemKey.toLowerCase().compareTo(b.itemKey.toLowerCase());
      });

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
      _linkedPhotoAliases = aliases;
      _linkedFaceThumbnailPath = linkedFaceThumbnailPath;
      _linkedPhotoPaths = linkedPhotoPaths.toList()..sort();
      final sortedGroupEntries = linkedGroups.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      _linkedGroups = {
        for (final entry in sortedGroupEntries) entry.key: entry.value,
      };
      _linkedHeirlooms = linkedHeirlooms;
      _linkedPostcards = linkedPostcards;
      _linkedSportsCards = linkedSportsCards;
      _linkedAntiques = linkedAntiques;
      _linkedDocumentPaths = linkedDocumentPaths;
      _automaticConnections = automaticConnections;
      _loadingConnections = false;
    });
  }

  String _encodeQueryComponent(String value) {
    return Uri.encodeQueryComponent(value.trim()).replaceAll('%20', '+');
  }

  Future<void> _searchNewspapersCom() async {
    final name = _person.displayName.trim();
    if (name.isEmpty) return;

    final url =
        'https://www.newspapers.com/results/?query=${_encodeQueryComponent(name)}';

    try {
      if (Platform.isWindows) {
        await Process.start(
          'cmd',
          ['/c', 'start', '', url],
          runInShell: true,
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Newspapers.com search launching is currently enabled on Windows.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open Newspapers.com: $error'),
        ),
      );
    }
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
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToSection(GlobalKey key) async {
    final sectionContext = key.currentContext;
    if (sectionContext == null) return;

    await Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: .08,
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = _person.profilePhotoPath;
    final hasProfilePhoto = path.isNotEmpty && File(path).existsSync();
    final fallbackPath = _linkedFaceThumbnailPath ?? '';
    final hasFallbackPhoto =
        fallbackPath.isNotEmpty && File(fallbackPath).existsSync();
    final displayPhotoPath = hasProfilePhoto
        ? path
        : (hasFallbackPhoto ? fallbackPath : '');
    final hasPhoto = displayPhotoPath.isNotEmpty;

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
        controller: _pageScrollController,
        padding: const EdgeInsets.all(28),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _panelNavy,
              border: Border.all(
                color: _heritageGold.withValues(alpha: .38),
                width: .8,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 72,
                  backgroundColor: const Color(0xFF102A40),
                  backgroundImage: hasPhoto
                      ? FileImage(File(displayPhotoPath))
                      : null,
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _heritageGold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                SizedBox(
                  width: 360,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF102A40),
                      border: Border.all(
                        color: _heritageGold.withValues(alpha: .28),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIFE EVENTS',
                          style: TextStyle(
                            color: _heritageCream.withValues(alpha: .72),
                            fontSize: 11,
                            letterSpacing: .9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _detail('Birth', _person.birthDate, _person.birthPlace),
                        _detail('Death', _person.deathDate, _person.deathPlace),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _personQuickActions(),
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

  Widget _personQuickActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .94),
        border: Border.all(color: _heritageGold.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            'PERSON HUB',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .72),
              fontSize: 11,
              letterSpacing: .9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit Person'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Add relationship',
            onSelected: _addRelationship,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'Father', child: Text('Add Father')),
              PopupMenuItem(value: 'Mother', child: Text('Add Mother')),
              PopupMenuItem(value: 'Spouse', child: Text('Add Spouse')),
              PopupMenuItem(value: 'Child', child: Text('Add Child')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group_add_outlined, size: 18),
                  SizedBox(width: 7),
                  Text('Add Relationship'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FamilyVisualTreeScreen(initialPerson: _person),
                ),
              );
              await _loadAll();
            },
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: const Text('View in Tree'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FamilyFanChartScreen(initialPerson: _person),
                ),
              );
              await _loadAll();
            },
            icon: const Icon(Icons.donut_large_outlined, size: 18),
            label: const Text('Fan Chart'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _searchNewspapersCom,
            icon: const Icon(Icons.newspaper_outlined, size: 18),
            label: const Text('Newspapers.com'),
          ),
        ],
      ),
    );
  }


  Future<void> _linkKnownPerson() async {
    final familyPersonId = _person.id;
    if (familyPersonId == null) return;

    final faces = await _databaseHelper.getConfirmedFaces();
    final links = await _databaseHelper.getPhotoPersonFamilyTreeLinks();
    if (!mounted) return;

    final names =
        faces
            .map((face) => face.personName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No Known People from Photos are available yet.'),
        ),
      );
      return;
    }

    var search = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = search.trim().toLowerCase();
          final visible = names.where((name) {
            return query.isEmpty || name.toLowerCase().contains(query);
          }).toList();

          return Dialog(
            child: SizedBox(
              width: 700,
              height: 680,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.link),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Link Known Person',
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
                        hintText: 'Search Known People...',
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
                              final name = visible[index];
                              final linkedFamilyId = links[name];
                              final linkedElsewhere =
                                  linkedFamilyId != null &&
                                  linkedFamilyId != familyPersonId;
                              final isCurrent =
                                  linkedFamilyId == familyPersonId;

                              return ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    isCurrent
                                        ? Icons.link
                                        : Icons.person_outline,
                                  ),
                                ),
                                title: Text(name),
                                subtitle: Text(
                                  isCurrent
                                      ? 'Currently linked to this person'
                                      : linkedElsewhere
                                      ? 'Already linked to another Family Tree person'
                                      : 'Available to link',
                                ),
                                enabled: !linkedElsewhere,
                                trailing: isCurrent
                                    ? const Icon(Icons.check_circle)
                                    : linkedElsewhere
                                    ? const Icon(Icons.lock_outline)
                                    : const Icon(Icons.chevron_right),
                                onTap: linkedElsewhere
                                    ? null
                                    : () => Navigator.pop(dialogContext, name),
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

    if (selected == null) return;

    await _databaseHelper.setPhotoPersonAlias(
      aliasName: selected,
      familyPersonId: familyPersonId,
    );

    await _loadAll();
  }

  Future<void> _showAllPhotos() async {
    if (_linkedPhotoPaths.isEmpty) return;

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
                    const Icon(Icons.photo_library_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_person.displayName} — Photos',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text('${_linkedPhotoPaths.length} photos'),
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
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _linkedPhotoPaths.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final photoPath = _linkedPhotoPaths[index];
                    final file = File(photoPath);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openPhotoDetails(index),
                        child: file.existsSync()
                            ? Image.file(
                                file,
                                fit: BoxFit.cover,
                                cacheWidth: 600,
                              )
                            : const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                ),
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

  Future<void> _openPhotoDetails(int initialIndex) async {
    if (_linkedPhotoPaths.isEmpty) return;

    final indexedPhotos = await _databaseHelper.getIndexedPhotos();
    if (!mounted) return;

    final linkedSet = _linkedPhotoPaths.toSet();
    final photos = indexedPhotos
        .where((photo) => linkedSet.contains(photo.filePath))
        .toList();

    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('These linked photos are not currently indexed.'),
        ),
      );
      return;
    }

    final requestedPath =
        _linkedPhotoPaths[initialIndex.clamp(0, _linkedPhotoPaths.length - 1)];
    final detailIndex = photos.indexWhere(
      (photo) => photo.filePath == requestedPath,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoDetailScreen(
          photos: photos,
          initialIndex: detailIndex < 0 ? 0 : detailIndex,
        ),
      ),
    );

    await _loadAll();
  }

  Future<void> _openPersonGroup({
    required int groupId,
    required String groupName,
  }) async {
    final results = await Future.wait([
      _databaseHelper.getPersonNamesForGroup(groupId),
      _databaseHelper.getPhotoPathsForPersonGroup(groupId),
    ]);
    if (!mounted) return;

    final names = results[0].toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final photoPaths = results[1].toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 1000,
          height: 720,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.groups_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        groupName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${names.length} people • ${photoPaths.length} photos',
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
                    if (names.isEmpty)
                      const Text('No people have been added to this group.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: names
                            .map(
                              (name) => Chip(
                                avatar: const Icon(
                                  Icons.person_outline,
                                  size: 18,
                                ),
                                label: Text(name),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Group Photos',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (photoPaths.isEmpty)
                      const Text('No photos are attached to this group.')
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: photoPaths.length,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                        itemBuilder: (context, index) {
                          final file = File(photoPaths[index]);
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: file.existsSync()
                                ? Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    cacheWidth: 500,
                                  )
                                : const ColoredBox(
                                    color: Colors.black12,
                                    child: Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
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

  Future<void> _addLinkedDocuments() async {
    final personId = _person.id;
    if (personId == null) return;

    // Multiple documents are intentionally supported here.
    final result = await FilePicker.pickFiles(
      // ignore: deprecated_member_use
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'txt',
        'rtf',
        'jpg',
        'jpeg',
        'png',
        'tif',
        'tiff',
      ],
    );

    if (result.isEmpty) return;

    var added = 0;
    for (final picked in result) {
      final path = picked.path?.trim() ?? '';
      if (path.isEmpty || _linkedDocumentPaths.contains(path)) continue;

      await _databaseHelper.linkFamilyPersonToItem(
        personId: personId,
        itemType: 'document',
        itemKey: path,
      );
      added++;
    }

    await _loadAll();
    if (!mounted || added == 0) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 1
              ? '1 document connected to ${_person.displayName}.'
              : '$added documents connected to ${_person.displayName}.',
        ),
      ),
    );
  }

  Future<void> _unlinkDocument(String path) async {
    final personId = _person.id;
    if (personId == null) return;

    await _databaseHelper.unlinkFamilyPersonFromItem(
      personId: personId,
      itemType: 'document',
      itemKey: path,
    );
    await _loadAll();
  }

  Future<void> _openLinkedDocument(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That document file can no longer be found.')),
      );
      return;
    }

    if (!Platform.isWindows) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Document location: $path')),
      );
      return;
    }

    try {
      await Process.start(
        'cmd',
        ['/c', 'start', '', path],
        runInShell: true,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open document: $path')),
      );
    }
  }

  Future<void> _manageLinkedDocuments() async {
    var dialogPaths = List<String>.from(_linkedDocumentPaths);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refreshDialog() async {
            await _loadAll();
            if (!mounted) return;
            setDialogState(() {
              dialogPaths = List<String>.from(_linkedDocumentPaths);
            });
          }

          return Dialog(
            child: SizedBox(
              width: 820,
              height: 650,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.description_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_person.displayName} — Documents',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            await _addLinkedDocuments();
                            await refreshDialog();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Files'),
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
                  Expanded(
                    child: dialogPaths.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.description_outlined, size: 58),
                                  SizedBox(height: 14),
                                  Text(
                                    'No documents connected yet.',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Add PDFs, Word files, text files, scans, or document images.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(14),
                            itemCount: dialogPaths.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final path = dialogPaths[index];
                              final fileName = path
                                  .replaceAll('\\', '/')
                                  .split('/')
                                  .last;
                              final exists = File(path).existsSync();

                              return ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    exists
                                        ? Icons.description_outlined
                                        : Icons.link_off_outlined,
                                  ),
                                ),
                                title: Text(
                                  fileName.isEmpty ? 'Document' : fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  exists ? path : 'File not found • $path',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: exists
                                    ? () => _openLinkedDocument(path)
                                    : null,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'open') {
                                      await _openLinkedDocument(path);
                                    } else if (value == 'remove') {
                                      await _unlinkDocument(path);
                                      await refreshDialog();
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (exists)
                                      const PopupMenuItem(
                                        value: 'open',
                                        child: Text('Open Document'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove Connection'),
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

    await _loadAll();
  }


  Future<void> _manageLinkedHeirlooms() async {
    final personId = _person.id;
    if (personId == null) return;

    final collections = await _databaseHelper.getCustomCollections();
    final all = <_PersonCollectionLink>[];
    for (final collection in collections) {
      final collectionId = collection.id;
      if (collectionId == null) continue;
      final items = await _databaseHelper.getCustomCollectionItems(
        collectionId,
      );
      for (final item in items) {
        if (item.id != null) {
          all.add(_PersonCollectionLink(collection: collection, item: item));
        }
      }
    }

    if (!mounted) return;

    if (all.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There are no custom collection items to connect yet.'),
        ),
      );
      return;
    }

    all.sort((a, b) {
      final collectionCompare = a.collection.name.toLowerCase().compareTo(
        b.collection.name.toLowerCase(),
      );
      if (collectionCompare != 0) return collectionCompare;
      return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    });

    final selected = _linkedHeirlooms
        .map((link) => link.item.id)
        .whereType<int>()
        .toSet();
    var query = '';

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final visible = all.where((link) {
            if (q.isEmpty) return true;
            return link.item.title.toLowerCase().contains(q) ||
                link.collection.name.toLowerCase().contains(q) ||
                link.item.values.values.any(
                  (value) => value.toLowerCase().contains(q),
                );
          }).toList();

          return Dialog(
            child: SizedBox(
              width: 820,
              height: 700,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Connect Heirlooms & Collection Items',
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
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search item or collection...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('No matching items.'))
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final link = visible[index];
                              final itemId = link.item.id!;
                              return CheckboxListTile(
                                value: selected.contains(itemId),
                                secondary: const CircleAvatar(
                                  child: Icon(Icons.inventory_2_outlined),
                                ),
                                title: Text(link.item.title),
                                subtitle: Text(link.collection.name),
                                onChanged: (checked) {
                                  setDialogState(() {
                                    if (checked ?? false) {
                                      selected.add(itemId);
                                    } else {
                                      selected.remove(itemId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text('${selected.length} selected'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () =>
                              Navigator.pop(dialogContext, selected),
                          icon: const Icon(Icons.link),
                          label: const Text('Save Connections'),
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

    if (result == null) return;

    final current = _linkedHeirlooms
        .map((link) => link.item.id)
        .whereType<int>()
        .toSet();

    for (final itemId in current.difference(result)) {
      await _databaseHelper.unlinkFamilyPersonFromItem(
        personId: personId,
        itemType: 'custom_collection_item',
        itemKey: itemId.toString(),
      );
    }
    for (final itemId in result.difference(current)) {
      await _databaseHelper.linkFamilyPersonToItem(
        personId: personId,
        itemType: 'custom_collection_item',
        itemKey: itemId.toString(),
      );
    }

    await _loadAll();
  }

  Future<void> _openPostcard(Postcard postcard) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostcardEditScreen(postcard: postcard)),
    );
    await _loadAll();
  }

  Future<void> _openCollectionItem(_PersonCollectionLink link) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomCollectionItemEditScreen(
          collection: link.collection,
          item: link.item,
        ),
      ),
    );
    await _loadAll();
  }

  Future<void> _openSportsCard(SportsCard card) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final imagePath = card.imagePath.trim();
        final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
        final details = <MapEntry<String, String>>[
          MapEntry('Player', card.player),
          MapEntry('Year', card.year),
          MapEntry('Set', card.setName),
          MapEntry('Card Number', card.cardNumber),
          MapEntry('Team', card.team),
          MapEntry('Sport', card.sport),
          MapEntry('Brand', card.brand),
          MapEntry('Grade', card.grade),
          MapEntry('Status', card.status),
          MapEntry('Storage', card.storageLocation),
          MapEntry('Notes', card.notes),
        ].where((entry) => entry.value.trim().isNotEmpty).toList();

        return Dialog(
          child: SizedBox(
            width: 760,
            height: 650,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.style_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          card.player.trim().isEmpty
                              ? 'Sports Card'
                              : card.player,
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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (hasImage) ...[
                        SizedBox(
                          height: 300,
                          child: Image.file(
                            File(imagePath),
                            fit: BoxFit.contain,
                            cacheWidth: 900,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      ...details.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 130,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Expanded(child: Text(entry.value)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SportsCardsScreen(),
                          ),
                        );
                        await _loadAll();
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Sports Cards'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAntique(Antique antique) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AntiqueEditScreen(antique: antique)),
    );
    await _loadAll();
  }

  Widget _connectionsCard() {
    final connectionTotal =
        _linkedPhotoPaths.length +
        _linkedGroups.length +
        _linkedPostcards.length +
        _linkedSportsCards.length +
        _linkedAntiques.length +
        _linkedDocumentPaths.length +
        _linkedHeirlooms.length +
        _automaticConnections.length;

    final categoryCount = [
      _linkedPhotoPaths.isNotEmpty,
      _linkedAntiques.isNotEmpty,
      _linkedPostcards.isNotEmpty,
      _linkedSportsCards.isNotEmpty,
      _linkedDocumentPaths.isNotEmpty,
      _linkedHeirlooms.isNotEmpty,
      _automaticConnections.isNotEmpty,
      _linkedGroups.isNotEmpty,
    ].where((value) => value).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _panelNavy,
                    border: Border.all(
                      color: _heritageGold.withValues(alpha: .30),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.auto_stories_outlined,
                    color: _heritageGold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _title('Their Heirloom Atlas'),
                      const SizedBox(height: 3),
                      Text(
                        'The photos, objects, documents, and collections connected to ${_person.displayName}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (connectionTotal > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _panelNavy.withValues(alpha: .72),
                      border: Border.all(
                        color: _heritageGold.withValues(alpha: .24),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$connectionTotal connected',
                          style: const TextStyle(
                            color: _heritageGold,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$categoryCount ${categoryCount == 1 ? 'category' : 'categories'}',
                          style: TextStyle(
                            color: _heritageCream.withValues(alpha: .58),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: _heritageGold.withValues(alpha: .14),
            ),
            const SizedBox(height: 14),
            if (_loadingConnections)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _compactConnectionStrip(),
              if (_linkedPhotoPersonName == null) ...[
                const SizedBox(height: 12),
                _compactPhotoIdentityPrompt(),
              ] else ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _showPhotoIdentityManager,
                    icon: const Icon(Icons.face_outlined, size: 17),
                    label: const Text('Photo Identity'),
                  ),
                ),
              ],
              if (connectionTotal == 0) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _panelNavy.withValues(alpha: .45),
                    border: Border.all(
                      color: _heritageGold.withValues(alpha: .16),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'No collection items are connected yet. Connections added from Photos or collection records will appear here automatically.',
                  ),
                ),
              ],
              if (_linkedPhotoPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactPhotoStrip(),
              ],
              if (_linkedAntiques.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactAntiqueStrip(),
              ],
              if (_linkedPostcards.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactPostcardStrip(),
              ],
              if (_linkedSportsCards.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactSportsCardStrip(),
              ],
              if (_linkedHeirlooms.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactHeirloomStrip(),
              ],
              if (_linkedDocumentPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactDocumentStrip(),
              ],
              if (_automaticConnections.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactAutomaticConnections(),
              ],
              if (_linkedGroups.isNotEmpty) ...[
                const SizedBox(height: 12),
                _compactGroupStrip(),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _compactConnectionStrip() {
    final items = <Widget>[];

    void add({
      required IconData icon,
      required int count,
      required String label,
      VoidCallback? onTap,
    }) {
      if (count <= 0) return;
      items.add(
        _compactConnectionPill(
          icon: icon,
          count: count,
          label: label,
          onTap: onTap,
        ),
      );
    }

    add(
      icon: Icons.photo_library_outlined,
      count: _linkedPhotoPaths.length,
      label: 'Photos',
      onTap: () => _scrollToSection(_photosSectionKey),
    );
    add(
      icon: Icons.chair_outlined,
      count: _linkedAntiques.length,
      label: 'Antiques',
      onTap: () => _scrollToSection(_antiquesSectionKey),
    );
    add(
      icon: Icons.markunread_mailbox_outlined,
      count: _linkedPostcards.length,
      label: 'Postcards',
      onTap: () => _scrollToSection(_postcardsSectionKey),
    );
    add(
      icon: Icons.style_outlined,
      count: _linkedSportsCards.length,
      label: 'Sports Cards',
      onTap: () => _scrollToSection(_sportsCardsSectionKey),
    );
    add(
      icon: Icons.description_outlined,
      count: _linkedDocumentPaths.length,
      label: 'Documents',
      onTap: () => _scrollToSection(_documentsSectionKey),
    );
    add(
      icon: Icons.inventory_2_outlined,
      count: _linkedHeirlooms.length,
      label: 'Heirlooms',
      onTap: () => _scrollToSection(_heirloomsSectionKey),
    );
    add(
      icon: Icons.groups_outlined,
      count: _linkedGroups.length,
      label: 'Groups',
      onTap: () => _scrollToSection(_groupsSectionKey),
    );
    add(
      icon: Icons.hub_outlined,
      count: _automaticConnections.length,
      label: 'Other',
      onTap: () => _scrollToSection(_otherSectionKey),
    );

    if (items.isEmpty) {
      return Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: _heritageGold, size: 19),
          const SizedBox(width: 8),
          Text(
            'No connected collection items yet',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .72),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }

  Widget _compactConnectionPill({
    required IconData icon,
    required int count,
    required String label,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: _panelNavy.withValues(alpha: .78),
            border: Border.all(color: _heritageGold.withValues(alpha: .24)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: _heritageGold),
              const SizedBox(width: 6),
              Text(
                count.toString(),
                style: const TextStyle(
                  color: _heritageCream,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: _heritageCream.withValues(alpha: .82),
                  fontSize: 12,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: _heritageGold.withValues(alpha: .72),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactPhotoIdentityPrompt() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .42),
        border: Border.all(color: _heritageGold.withValues(alpha: .16)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.face_outlined, size: 19),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Connect this person to a Known Person from Photos to bring recognized photos into this hub.',
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _linkKnownPerson,
            icon: const Icon(Icons.link, size: 17),
            label: const Text('Link'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPhotoIdentityManager() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.face_outlined),
            SizedBox(width: 9),
            Text('Photo Identity'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _linkedPhotoAliases.isEmpty
                    ? 'No photo names are linked.'
                    : 'Known Person names linked to ${_person.displayName}:',
              ),
              if (_linkedPhotoAliases.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _linkedPhotoAliases
                      .map((name) => Chip(label: Text(name)))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _linkKnownPerson();
            },
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Manage Link'),
          ),
        ],
      ),
    );
  }

  Widget _compactSectionShell({
    Key? key,
    required IconData icon,
    required String title,
    required int count,
    Widget? action,
    required Widget child,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .38),
        border: Border.all(color: _heritageGold.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _heritageGold),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: .15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _heritageGold.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    color: _heritageGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (action != null) const SizedBox(width: 6),
              ?action,
            ],
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }

  Widget _compactPhotoStrip() {
    final count = _linkedPhotoPaths.length > 8 ? 8 : _linkedPhotoPaths.length;
    return _compactSectionShell(
      key: _photosSectionKey,
      icon: Icons.photo_library_outlined,
      title: 'Photos',
      count: _linkedPhotoPaths.length,
      action: TextButton(onPressed: _showAllPhotos, child: const Text('View all')),
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(width: 7),
          itemBuilder: (context, index) {
            final path = _linkedPhotoPaths[index];
            final file = File(path);
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Material(
                color: _panelNavy,
                child: InkWell(
                  onTap: () => _openPhotoDetails(index),
                  child: SizedBox(
                    width: 92,
                    child: file.existsSync()
                        ? Image.file(file, fit: BoxFit.cover, cacheWidth: 300)
                        : const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _compactAntiqueStrip() => _compactObjectStrip<Antique>(
        key: _antiquesSectionKey,
        icon: Icons.chair_outlined,
        title: 'Antiques',
        items: _linkedAntiques,
        imagePath: (item) => item.imagePaths.isEmpty ? '' : item.imagePaths.first,
        itemTitle: (item) => item.title.trim().isEmpty ? 'Antique' : item.title,
        subtitle: (item) => item.year,
        onTap: _openAntique,
      );

  Widget _compactPostcardStrip() => _compactObjectStrip<Postcard>(
        key: _postcardsSectionKey,
        icon: Icons.markunread_mailbox_outlined,
        title: 'Postcards',
        items: _linkedPostcards,
        imagePath: (item) => item.frontImagePath,
        itemTitle: (item) => item.title.trim().isEmpty ? 'Postcard' : item.title,
        subtitle: (item) => item.year,
        onTap: _openPostcard,
      );

  Widget _compactSportsCardStrip() => _compactObjectStrip<SportsCard>(
        key: _sportsCardsSectionKey,
        icon: Icons.style_outlined,
        title: 'Sports Cards',
        items: _linkedSportsCards,
        imagePath: (item) => item.imagePath,
        itemTitle: (item) => item.player.trim().isEmpty ? 'Sports Card' : item.player,
        subtitle: (item) => [
          item.year,
          if (item.cardNumber.trim().isNotEmpty) '#${item.cardNumber}',
        ].where((value) => value.trim().isNotEmpty).join(' • '),
        onTap: _openSportsCard,
      );

  Widget _compactHeirloomStrip() {
    return _compactObjectStrip<_PersonCollectionLink>(
      key: _heirloomsSectionKey,
      icon: Icons.inventory_2_outlined,
      title: 'Heirlooms & Collections',
      items: _linkedHeirlooms,
      imagePath: (link) => link.item.photoPaths.isEmpty ? '' : link.item.photoPaths.first,
      itemTitle: (link) => link.item.title,
      subtitle: (link) => link.collection.name,
      onTap: _openCollectionItem,
      action: TextButton.icon(
        onPressed: _manageLinkedHeirlooms,
        icon: const Icon(Icons.link, size: 16),
        label: const Text('Manage'),
      ),
    );
  }

  Widget _compactObjectStrip<T>({
    Key? key,
    required IconData icon,
    required String title,
    required List<T> items,
    required String Function(T) imagePath,
    required String Function(T) itemTitle,
    required String Function(T) subtitle,
    required void Function(T) onTap,
    Widget? action,
  }) {
    final visible = items.take(5).toList();
    return _compactSectionShell(
      key: key,
      icon: icon,
      title: title,
      count: items.length,
      action: action,
      child: SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = visible[index];
            final path = imagePath(item).trim();
            final hasImage = path.isNotEmpty && File(path).existsSync();
            return SizedBox(
              width: 142,
              child: Material(
                color: _panelNavy.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: () => onTap(item),
                  borderRadius: BorderRadius.circular(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 78,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          child: hasImage
                              ? Image.file(File(path), fit: BoxFit.cover, cacheWidth: 360)
                              : Center(child: Icon(icon, size: 30, color: _heritageGold)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              itemTitle(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                            if (subtitle(item).trim().isNotEmpty)
                              Text(
                                subtitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _heritageCream.withValues(alpha: .62),
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
        ),
      ),
    );
  }

  Widget _compactDocumentStrip() {
    final visible = _linkedDocumentPaths.take(4).toList();
    return _compactSectionShell(
      key: _documentsSectionKey,
      icon: Icons.description_outlined,
      title: 'Documents',
      count: _linkedDocumentPaths.length,
      action: TextButton(onPressed: _manageLinkedDocuments, child: const Text('Manage')),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: visible.map((path) {
          final fileName = path.replaceAll('\\', '/').split('/').last;
          final exists = File(path).existsSync();
          return ActionChip(
            avatar: Icon(exists ? Icons.description_outlined : Icons.link_off_outlined, size: 17),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210),
              child: Text(fileName.isEmpty ? 'Document' : fileName, overflow: TextOverflow.ellipsis),
            ),
            onPressed: exists ? () => _openLinkedDocument(path) : null,
          );
        }).toList(),
      ),
    );
  }


  Widget _compactAutomaticConnections() {
    final visible = _automaticConnections.take(6).toList();
    return _compactSectionShell(
      key: _otherSectionKey,
      icon: Icons.hub_outlined,
      title: 'Other Collections',
      count: _automaticConnections.length,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: visible
            .map(
              (connection) => Chip(
                avatar: Icon(connection.icon, size: 17),
                label: Text(connection.displayType),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _compactGroupStrip() {
    return _compactSectionShell(
      key: _groupsSectionKey,
      icon: Icons.groups_outlined,
      title: 'Person Groups',
      count: _linkedGroups.length,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: _linkedGroups.entries
            .map(
              (entry) => ActionChip(
                avatar: const Icon(Icons.groups_outlined, size: 17),
                label: Text(entry.key),
                onPressed: () => _openPersonGroup(
                  groupId: entry.value,
                  groupName: entry.key,
                ),
              ),
            )
            .toList(),
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
            _relationshipSummary(),
            const SizedBox(height: 18),
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

  Widget _relationshipSummary() {
    final total = _parents.length + _spouses.length + _children.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .94),
        border: Border.all(color: _heritageGold.withValues(alpha: .24)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _relationshipSummaryItem(
            icon: Icons.arrow_upward,
            value: _parents.length,
            label: 'Parents',
          ),
          _relationshipSummaryDivider(),
          _relationshipSummaryItem(
            icon: Icons.favorite_border,
            value: _spouses.length,
            label: 'Spouses',
          ),
          _relationshipSummaryDivider(),
          _relationshipSummaryItem(
            icon: Icons.arrow_downward,
            value: _children.length,
            label: 'Children',
          ),
          const Spacer(),
          Text(
            total == 0 ? 'No relationships recorded' : '$total direct connections',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .62),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _relationshipSummaryItem({
    required IconData icon,
    required int value,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _heritageGold),
          const SizedBox(width: 7),
          Text(
            value.toString(),
            style: const TextStyle(
              color: _heritageCream,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .72),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _relationshipSummaryDivider() {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: _heritageGold.withValues(alpha: .18),
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
                leading: _relativeAvatar(person),
                title: Text(
                  person.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    labelFor(person),
                    ?(person.lifeSpan.isNotEmpty ? person.lifeSpan : null),
                  ].join(' • '),
                ),
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

  Widget _relativeAvatar(FamilyPerson person) {
    final photoPath = person.profilePhotoPath.trim();
    final hasPhoto = photoPath.isNotEmpty && File(photoPath).existsSync();

    return CircleAvatar(
      backgroundColor: _panelNavy,
      backgroundImage: hasPhoto ? FileImage(File(photoPath)) : null,
      child: hasPhoto
          ? null
          : const Icon(Icons.person_outline, color: _heritageCream),
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

class _GenericFamilyConnection {
  final String itemType;
  final String itemKey;
  final String role;

  const _GenericFamilyConnection({required this.itemType, required this.itemKey, required this.role});

  String get displayType {
    final words = itemType.replaceAll('-', '_').split('_').where((word) => word.trim().isNotEmpty).map(
      (word) => word.length == 1 ? word.toUpperCase() : '${word[0].toUpperCase()}${word.substring(1)}',
    ).toList();
    return words.isEmpty ? 'Collection Item' : words.join(' ');
  }

  IconData get icon {
    switch (itemType) {
      case 'valuable':
      case 'valuables': return Icons.diamond_outlined;
      case 'coin':
      case 'coins': return Icons.monetization_on_outlined;
      case 'artwork':
      case 'art': return Icons.palette_outlined;
      case 'video':
      case 'videos': return Icons.movie_outlined;
      default: return Icons.inventory_2_outlined;
    }
  }
}

class _PersonCollectionLink {
  final CustomCollection collection;
  final CustomCollectionItem item;

  const _PersonCollectionLink({required this.collection, required this.item});
}
