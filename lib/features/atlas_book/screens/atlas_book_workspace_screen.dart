import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../database/database_helper.dart';
import '../../../models/family_person.dart';
import '../data/atlas_book_repository.dart';
import '../theme/atlas_book_theme.dart';
import '../models/atlas_book_page.dart';
import '../models/atlas_book_project.dart';
import '../widgets/family_people_picker_dialog.dart';

class AtlasBookWorkspaceScreen extends StatefulWidget {
  final AtlasBookProject book;

  const AtlasBookWorkspaceScreen({super.key, required this.book});

  @override
  State<AtlasBookWorkspaceScreen> createState() =>
      _AtlasBookWorkspaceScreenState();
}

class _AtlasBookWorkspaceScreenState extends State<AtlasBookWorkspaceScreen> {
  final AtlasBookRepository _repository = AtlasBookRepository();
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  List<FamilyPerson> _selectedPeople = [];
  bool _loadingPeople = true;
  List<String> _connectedPhotoPaths = [];
  Set<String> _selectedPhotoPaths = <String>{};
  Set<String> _favoritePhotoPaths = <String>{};
  List<_AtlasGatherItem> _connectedStories = [];
  List<_AtlasGatherItem> _connectedDocuments = [];
  List<_AtlasGatherItem> _connectedCollectibles = [];
  Set<String> _selectedStoryKeys = <String>{};
  Set<String> _selectedDocumentKeys = <String>{};
  Set<String> _favoriteStoryKeys = <String>{};
  Set<String> _favoriteDocumentKeys = <String>{};
  Set<String> _selectedCollectibleKeys = <String>{};
  Set<String> _favoriteCollectibleKeys = <String>{};
  String _materialFilter = 'All';
  bool _loadingConnectedPhotos = false;
  List<AtlasBookPage> _bookPages = [];
  bool _loadingPages = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedPeople();
    _loadSavedBookPhotos();
    _loadAtlasBookPhotoFavorites();
    _loadSavedNonPhotoMaterials();
    _loadBookPages();
  }

  Future<void> _loadSelectedPeople() async {
    final bookId = widget.book.id;

    if (bookId == null) {
      setState(() => _loadingPeople = false);
      return;
    }

    final selectedIds = (await _repository.getBookPersonIds(bookId)).toSet();

    if (selectedIds.isEmpty) {
      if (!mounted) return;

      setState(() {
        _selectedPeople = [];
        _loadingPeople = false;
      });
      return;
    }

    final allPeople = await _databaseHelper.getFamilyPeople();

    if (!mounted) return;

    setState(() {
      _selectedPeople = allPeople
          .where(
            (person) => person.id != null && selectedIds.contains(person.id),
          )
          .toList();
      _loadingPeople = false;
    });
  }

  Future<void> _choosePeople() async {
    final bookId = widget.book.id;

    if (bookId == null) {
      return;
    }

    final currentIds = (await _repository.getBookPersonIds(bookId)).toSet();

    if (!mounted) return;

    final selectedIds = await showDialog<Set<int>>(
      context: context,
      builder: (_) =>
          FamilyPeoplePickerDialog(initiallySelectedIds: currentIds),
    );

    if (selectedIds == null) {
      return;
    }

    await _repository.replaceBookPeople(bookId, selectedIds);

    await _loadSelectedPeople();
    await _gatherConnectedPhotos(silent: true);
  }

  Future<void> _chooseFamilyBranch() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    final allPeople = await _databaseHelper.getFamilyPeople();
    if (!mounted) return;

    if (allPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add people to the Family Tree before choosing a branch.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<_FamilyBranchSelectionResult>(
      context: context,
      builder: (_) => _FamilyBranchPickerDialog(people: allPeople),
    );

    if (result == null) return;

    setState(() => _loadingPeople = true);

    final selectedIds = await _buildFamilyBranchPersonIds(
      rootPersonId: result.rootPersonId,
      direction: result.direction,
      generationDepth: result.generationDepth,
    );

    await _repository.replaceBookPeople(bookId, selectedIds);
    await _loadSelectedPeople();
    await _gatherConnectedPhotos(silent: true);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${selectedIds.length} '
          '${selectedIds.length == 1 ? 'person' : 'people'} added from this family branch.',
        ),
      ),
    );
  }

  Future<Set<int>> _buildFamilyBranchPersonIds({
    required int rootPersonId,
    required _FamilyBranchDirection direction,
    required int generationDepth,
  }) async {
    final selectedIds = <int>{rootPersonId};

    Future<void> walkAncestors(int personId, int depth) async {
      if (depth >= generationDepth) return;

      final parents = await _databaseHelper.getFamilyParents(personId);
      for (final parent in parents) {
        final parentId = parent.id;
        if (parentId == null) continue;

        final isNew = selectedIds.add(parentId);
        if (isNew) {
          await walkAncestors(parentId, depth + 1);
        }
      }
    }

    Future<void> walkDescendants(int personId, int depth) async {
      if (depth >= generationDepth) return;

      final children = await _databaseHelper.getFamilyChildren(personId);
      for (final child in children) {
        final childId = child.id;
        if (childId == null) continue;

        final isNew = selectedIds.add(childId);
        if (isNew) {
          await walkDescendants(childId, depth + 1);
        }
      }
    }

    if (direction == _FamilyBranchDirection.ancestors ||
        direction == _FamilyBranchDirection.both) {
      await walkAncestors(rootPersonId, 0);
    }

    if (direction == _FamilyBranchDirection.descendants ||
        direction == _FamilyBranchDirection.both) {
      await walkDescendants(rootPersonId, 0);
    }

    return selectedIds;
  }

  Future<void> _chooseGenerations() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    final allPeople = await _databaseHelper.getFamilyPeople();
    if (!mounted) return;

    if (allPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add people to the Family Tree before choosing generations.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<_GenerationSelectionResult>(
      context: context,
      builder: (_) => _GenerationPickerDialog(people: allPeople),
    );

    if (result == null) return;

    setState(() => _loadingPeople = true);

    final selectedIds = await _buildGenerationPersonIds(
      rootPersonId: result.rootPersonId,
      direction: result.direction,
      generationCount: result.generationCount,
    );

    await _repository.replaceBookPeople(bookId, selectedIds);
    await _loadSelectedPeople();
    await _gatherConnectedPhotos(silent: true);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${selectedIds.length} '
          '${selectedIds.length == 1 ? 'person' : 'people'} added from '
          '${result.generationCount} '
          '${result.generationCount == 1 ? 'generation' : 'generations'}.',
        ),
      ),
    );
  }

  Future<Set<int>> _buildGenerationPersonIds({
    required int rootPersonId,
    required _GenerationDirection direction,
    required int generationCount,
  }) async {
    final selectedIds = <int>{rootPersonId};

    // The starting person is generation 1, so a 3-generation book follows
    // relationships two steps away from that person.
    final relationshipDepth = generationCount - 1;
    if (relationshipDepth <= 0) return selectedIds;

    Future<void> walkAncestors(int personId, int depth) async {
      if (depth >= relationshipDepth) return;

      final parents = await _databaseHelper.getFamilyParents(personId);
      for (final parent in parents) {
        final parentId = parent.id;
        if (parentId == null) continue;

        selectedIds.add(parentId);
        await walkAncestors(parentId, depth + 1);
      }
    }

    Future<void> walkDescendants(int personId, int depth) async {
      if (depth >= relationshipDepth) return;

      final children = await _databaseHelper.getFamilyChildren(personId);
      for (final child in children) {
        final childId = child.id;
        if (childId == null) continue;

        selectedIds.add(childId);
        await walkDescendants(childId, depth + 1);
      }
    }

    if (direction == _GenerationDirection.ancestors) {
      await walkAncestors(rootPersonId, 0);
    } else {
      await walkDescendants(rootPersonId, 0);
    }

    return selectedIds;
  }

  Future<void> _loadSavedBookPhotos() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    final paths = await _repository.getBookPhotoPaths(bookId);

    if (!mounted) return;

    setState(() {
      _selectedPhotoPaths = paths.toSet();
    });
  }

  Future<void> _loadSavedNonPhotoMaterials() async {
    final bookId = widget.book.id;
    if (bookId == null) return;
    final stories = await _repository.getBookMaterialKeys(bookId, itemType: 'story');
    final documents = await _repository.getBookMaterialKeys(bookId, itemType: 'document');
    final collectibles = await _repository.getBookMaterialKeys(bookId, itemType: 'collectible');
    if (!mounted) return;
    setState(() {
      _selectedStoryKeys = stories.toSet();
      _selectedDocumentKeys = documents.toSet();
      _selectedCollectibleKeys = collectibles.toSet();
    });
  }

  Future<void> _saveBookMaterials() async {
    final bookId = widget.book.id;
    if (bookId == null) return;
    await _repository.replaceBookPhotos(bookId, _selectedPhotoPaths);
    await _repository.replaceBookMaterials(bookId, itemType: 'story', itemKeys: _selectedStoryKeys);
    await _repository.replaceBookMaterials(bookId, itemType: 'document', itemKeys: _selectedDocumentKeys);
    await _repository.replaceBookMaterials(bookId, itemType: 'collectible', itemKeys: _selectedCollectibleKeys);
    if (!mounted) return;
    final total = _selectedPhotoPaths.length + _selectedStoryKeys.length + _selectedDocumentKeys.length + _selectedCollectibleKeys.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$total selected ${total == 1 ? 'item' : 'items'} saved to this book.')));
  }

  Future<void> _setAtlasMaterialFavorite(String type, String key, bool favorite) async {
    var favoriteType = type;
    var favoriteKey = key;
    if (type == 'collectible') {
      final separator = key.indexOf(':');
      if (separator > 0 && separator < key.length - 1) {
        favoriteType = key.substring(0, separator);
        favoriteKey = key.substring(separator + 1);
      }
    }
    await _databaseHelper.setAtlasBookFavorite(itemType: favoriteType, itemKey: favoriteKey, favorite: favorite);
    if (!mounted) return;
    setState(() {
      final target = type == 'story'
          ? _favoriteStoryKeys
          : type == 'document'
              ? _favoriteDocumentKeys
              : type == 'collectible'
                  ? _favoriteCollectibleKeys
                  : _favoritePhotoPaths;
      favorite ? target.add(key) : target.remove(key);
    });
  }
  Future<void> _loadAtlasBookPhotoFavorites() async {
    final favorites = await _databaseHelper.getAtlasBookFavoriteKeys(
      itemType: 'photo',
    );
    if (!mounted) return;
    setState(() => _favoritePhotoPaths = favorites);
  }

  Future<List<String>> _findConnectedPhotosForPeople(
    Iterable<int> personIds,
  ) async {
    final ids = personIds.toSet();
    if (ids.isEmpty) return const [];

    final paths = <String>{
      ...await _databaseHelper.getPhotoPathsForFamilyPeople(ids),
    };

    final aliasesByFamily = await _databaseHelper
        .getPhotoAliasesGroupedByFamilyPerson();
    final legacyLinks = await _databaseHelper.getPhotoPersonFamilyTreeLinks();

    final aliasNames = <String>{};
    for (final id in ids) {
      aliasNames.addAll(aliasesByFamily[id] ?? const <String>[]);
    }
    for (final entry in legacyLinks.entries) {
      if (ids.contains(entry.value)) {
        aliasNames.add(entry.key);
      }
    }

    final aliasKeys = aliasNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();

    if (aliasKeys.isNotEmpty) {
      final catalog = await _databaseHelper.getAllPhotoCatalogMetadata();
      for (final record in catalog) {
        if (record.people.any(
          (name) => aliasKeys.contains(name.trim().toLowerCase()),
        )) {
          paths.add(record.filePath);
        }
      }

      final faces = await _databaseHelper.getConfirmedFaces();
      for (final face in faces) {
        if (aliasKeys.contains(face.personName.trim().toLowerCase())) {
          paths.add(face.photoFilePath);
        }
      }
    }

    // A person's Family Tree profile photo is also valid book material.
    for (final person in _selectedPeople) {
      final id = person.id;
      if (id == null || !ids.contains(id)) continue;
      final profilePath = person.profilePhotoPath.trim();
      if (profilePath.isNotEmpty) {
        paths.add(profilePath);
      }
    }

    final existing =
        paths
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty && File(path).existsSync())
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return existing;
  }

  Future<List<String>> _findConnectedPhotosForPerson(int personId) {
    return _findConnectedPhotosForPeople([personId]);
  }

  Future<void> _gatherConnectedPhotos({bool silent = false}) async {
    final personIds = _selectedPeople.where((person) => person.id != null).map((person) => person.id!).toSet();
    if (personIds.isEmpty) {
      if (!mounted) return;
      if (!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose at least one person for this book first.')));
      return;
    }
    setState(() => _loadingConnectedPhotos = true);
    final paths = await _findConnectedPhotosForPeople(personIds);
    final storyKeys = await _databaseHelper.getItemKeysForFamilyPeople(personIds: personIds, itemType: 'story');
    final documentKeys = await _databaseHelper.getItemKeysForFamilyPeople(personIds: personIds, itemType: 'document');
    final postcardKeys = await _databaseHelper.getItemKeysForFamilyPeople(personIds: personIds, itemType: 'postcard');
    final sportsCardKeys = await _databaseHelper.getItemKeysForFamilyPeople(personIds: personIds, itemType: 'sports_card');
    final customItemKeys = await _databaseHelper.getItemKeysForFamilyPeople(personIds: personIds, itemType: 'custom_collection_item');
    final antiqueKeys = await _databaseHelper.getItemKeysForFamilyPeople(personIds: personIds, itemType: 'antique');
    final valuableKeys = await _databaseHelper.getItemKeysForFamilyPeople(personIds: personIds, itemType: 'valuable');
    final db = await _databaseHelper.database;
    final stories = <_AtlasGatherItem>[];
    final storyIds = storyKeys.map(int.tryParse).whereType<int>().toList();
    if (storyIds.isNotEmpty) {
      final marks = List.filled(storyIds.length, '?').join(',');
      final rows = await db.rawQuery('SELECT id, title, story_text, date_text, place FROM heritage_stories WHERE id IN ($marks)', storyIds);
      for (final row in rows) {
        final id = (row['id'] as num).toInt().toString();
        final detail = [row['date_text'] as String? ?? '', row['place'] as String? ?? ''].where((v) => v.trim().isNotEmpty).join(' • ');
        stories.add(_AtlasGatherItem(
          type: 'story',
          key: id,
          title: row['title'] as String? ?? 'Untitled Story',
          subtitle: detail,
          body: row['story_text'] as String? ?? '',
        ));
      }
    }
    final documents = documentKeys.map((path) => _AtlasGatherItem(type: 'document', key: path, title: File(path).uri.pathSegments.isEmpty ? path : File(path).uri.pathSegments.last, subtitle: path)).toList();

    final collectibles = <_AtlasGatherItem>[];

    final postcardIds = postcardKeys.map(int.tryParse).whereType<int>().toList();
    if (postcardIds.isNotEmpty) {
      final marks = List.filled(postcardIds.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id, title, year, front_image_path FROM postcards WHERE id IN ($marks)',
        postcardIds,
      );
      for (final row in rows) {
        final id = (row['id'] as num).toInt().toString();
        final title = (row['title'] as String? ?? '').trim();
        final year = (row['year'] as String? ?? '').trim();
        collectibles.add(_AtlasGatherItem(
          type: 'collectible',
          key: 'postcard:$id',
          title: title.isEmpty ? 'Postcard #$id' : title,
          subtitle: year.isEmpty ? 'Postcard' : 'Postcard • $year',
          imagePath: row['front_image_path'] as String? ?? '',
        ));
      }
    }

    final sportsCardIds = sportsCardKeys.map(int.tryParse).whereType<int>().toList();
    if (sportsCardIds.isNotEmpty) {
      final marks = List.filled(sportsCardIds.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT c.id, c.player, c.year, c.brand, c.card_number,
               c.team, COALESCE(u.image_path, '') AS image_path
        FROM sports_card_catalog c
        LEFT JOIN sports_card_collection u ON u.catalog_id = c.id
        WHERE c.id IN ($marks)
      ''', sportsCardIds);
      for (final row in rows) {
        final id = (row['id'] as num).toInt().toString();
        final player = (row['player'] as String? ?? '').trim();
        final details = <String>[
          (row['year'] as String? ?? '').trim(),
          (row['brand'] as String? ?? '').trim(),
          (row['card_number'] as String? ?? '').trim().isEmpty
              ? ''
              : '#${(row['card_number'] as String).trim()}',
          (row['team'] as String? ?? '').trim(),
        ].where((value) => value.isNotEmpty).join(' • ');
        collectibles.add(_AtlasGatherItem(
          type: 'collectible',
          key: 'sports_card:$id',
          title: player.isEmpty ? 'Sports Card #$id' : player,
          subtitle: details.isEmpty ? 'Sports Card' : details,
          imagePath: row['image_path'] as String? ?? '',
        ));
      }
    }

    final customItemIds = customItemKeys.map(int.tryParse).whereType<int>().toList();
    if (customItemIds.isNotEmpty) {
      final marks = List.filled(customItemIds.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT i.id, i.values_json, i.photo_paths_json, c.name AS collection_name
        FROM custom_collection_items i
        LEFT JOIN custom_collections c ON c.id = i.collection_id
        WHERE i.id IN ($marks)
      ''', customItemIds);
      for (final row in rows) {
        final id = (row['id'] as num).toInt().toString();
        final collectionName = (row['collection_name'] as String? ?? 'Collection').trim();
        var title = 'Collection Item #$id';
        try {
          final values = jsonDecode(row['values_json'] as String? ?? '{}');
          if (values is Map) {
            for (final preferredKey in const ['Title', 'title', 'Name', 'name', 'Item', 'item']) {
              final value = values[preferredKey]?.toString().trim() ?? '';
              if (value.isNotEmpty) {
                title = value;
                break;
              }
            }
            if (title == 'Collection Item #$id') {
              for (final value in values.values) {
                final text = value?.toString().trim() ?? '';
                if (text.isNotEmpty) {
                  title = text;
                  break;
                }
              }
            }
          }
        } catch (_) {}
        var imagePath = '';
        try {
          final photos = jsonDecode(row['photo_paths_json'] as String? ?? '[]');
          if (photos is List && photos.isNotEmpty) {
            imagePath = photos.first?.toString() ?? '';
          }
        } catch (_) {}
        collectibles.add(_AtlasGatherItem(
          type: 'collectible',
          key: 'custom_collection_item:$id',
          title: title,
          subtitle: collectionName.isEmpty ? 'Collection Item' : collectionName,
          imagePath: imagePath,
        ));
      }
    }

    final antiqueIds = antiqueKeys.map(int.tryParse).whereType<int>().toList();
    if (antiqueIds.isNotEmpty) {
      final marks = List.filled(antiqueIds.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT a.id, a.title, a.year,
               COALESCE((
                 SELECT ai.image_path
                 FROM antique_images ai
                 WHERE ai.antique_id = a.id
                 ORDER BY ai.sort_order ASC, ai.id ASC
                 LIMIT 1
               ), '') AS image_path
        FROM antiques a
        WHERE a.id IN ($marks)
      ''', antiqueIds);
      for (final row in rows) {
        final id = (row['id'] as num).toInt().toString();
        final title = (row['title'] as String? ?? '').trim();
        final year = (row['year'] as String? ?? '').trim();
        collectibles.add(_AtlasGatherItem(
          type: 'collectible',
          key: 'antique:$id',
          title: title.isEmpty ? 'Antique #$id' : title,
          subtitle: year.isEmpty ? 'Antique' : 'Antique • $year',
          imagePath: row['image_path'] as String? ?? '',
        ));
      }
    }

    final valuableIds = valuableKeys.map(int.tryParse).whereType<int>().toList();
    if (valuableIds.isNotEmpty) {
      final marks = List.filled(valuableIds.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT v.id, v.title, v.year,
               COALESCE((
                 SELECT vi.image_path
                 FROM valuable_images vi
                 WHERE vi.valuable_id = v.id
                 ORDER BY vi.sort_order ASC, vi.id ASC
                 LIMIT 1
               ), '') AS image_path
        FROM valuables v
        WHERE v.id IN ($marks)
      ''', valuableIds);
      for (final row in rows) {
        final id = (row['id'] as num).toInt().toString();
        final title = (row['title'] as String? ?? '').trim();
        final year = (row['year'] as String? ?? '').trim();
        collectibles.add(_AtlasGatherItem(
          type: 'collectible',
          key: 'valuable:$id',
          title: title.isEmpty ? 'Valuable #$id' : title,
          subtitle: year.isEmpty ? 'Valuable' : 'Valuable • $year',
          imagePath: row['image_path'] as String? ?? '',
        ));
      }
    }

    final photoFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'photo');
    final storyFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'story');
    final docFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'document');
    final postcardFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'postcard');
    final sportsCardFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'sports_card');
    final customItemFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'custom_collection_item');
    final antiqueFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'antique');
    final valuableFav = await _databaseHelper.getAtlasBookFavoriteKeys(itemType: 'valuable');
    final collectibleFav = <String>{
      ...postcardFav.map((key) => 'postcard:$key'),
      ...sportsCardFav.map((key) => 'sports_card:$key'),
      ...customItemFav.map((key) => 'custom_collection_item:$key'),
      ...antiqueFav.map((key) => 'antique:$key'),
      ...valuableFav.map((key) => 'valuable:$key'),
    };
    if (!mounted) return;
    setState(() {
      _connectedPhotoPaths = paths;
      _connectedStories = stories..sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      _connectedDocuments = documents..sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      _connectedCollectibles = collectibles..sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      _favoritePhotoPaths = photoFav;
      _favoriteStoryKeys = storyFav;
      _favoriteDocumentKeys = docFav;
      _favoriteCollectibleKeys = collectibleFav;
      _loadingConnectedPhotos = false;
    });
  }

  Future<void> _loadBookPages() async {
    final bookId = widget.book.id;
    if (bookId == null) {
      setState(() => _loadingPages = false);
      return;
    }

    final pages = await _repository.getBookPages(bookId);
    if (!mounted) return;

    setState(() {
      _bookPages = pages;
      _loadingPages = false;
    });
  }

  Future<void> _openSmartBookBuilder() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    if (_selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose people for this book before building suggestions.',
          ),
        ),
      );
      return;
    }

    _showSmartBuilderProgress('Finding the best pages for your book...');

    try {
      // Reload Step 2's persisted photo links immediately before building.
      // This makes the Atlas Book repository the source of truth instead of
      // relying on possibly stale in-memory selection state.
      final savedPhotoPaths = await _repository.getBookPhotoPaths(bookId);
      final selectedPersonIds = _selectedPeople
          .where((person) => person.id != null)
          .map((person) => person.id!)
          .toSet();
      final connectedPhotoPaths = await _findConnectedPhotosForPeople(
        selectedPersonIds,
      );

      // Starter Book is intentionally curated: connected material is only a
      // browsing pool. Smart Builder uses material the user actually selected.
      final builderPhotoPaths = <String>{
        ...savedPhotoPaths,
        ..._selectedPhotoPaths,
      }.where((path) => path.trim().isNotEmpty).toSet();

      if (mounted) {
        setState(() {
          _connectedPhotoPaths = connectedPhotoPaths;
          _selectedPhotoPaths = builderPhotoPaths;
        });
      }

      await _loadSavedNonPhotoMaterials();
      await _gatherConnectedPhotos(silent: true);

      final suggestions = await _buildSmartBookSuggestions(
        builderPhotoPaths: builderPhotoPaths,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final chosen = await showDialog<Set<String>>(
        context: context,
        builder: (_) => _SmartBookBuilderDialog(suggestions: suggestions),
      );

      if (chosen == null || chosen.isEmpty) return;

      final selected = suggestions.where((s) => chosen.contains(s.id)).toList();

      _showSmartBuilderProgress(
        'Building ${selected.length} '
        '${selected.length == 1 ? 'page' : 'pages'}...',
      );

      final nextSortOrder = await _repository.getNextBookPageSortOrder(bookId);
      final now = DateTime.now();
      final pages = <AtlasBookPage>[];

      for (var index = 0; index < selected.length; index++) {
        final suggestion = selected[index];
        var heroPhotoPath = '';

        if (suggestion.pageType == 'person_profile' &&
            suggestion.personId != null) {
          FamilyPerson? person;
          for (final candidate in _selectedPeople) {
            if (candidate.id == suggestion.personId) {
              person = candidate;
              break;
            }
          }

          final profilePath = person?.profilePhotoPath ?? '';
          if (profilePath.isNotEmpty && File(profilePath).existsSync()) {
            heroPhotoPath = profilePath;
          } else if (suggestion.personId != null) {
            final personPhotos = await _findConnectedPhotosForPerson(
              suggestion.personId!,
            );
            if (personPhotos.isNotEmpty) {
              heroPhotoPath = personPhotos.first;
            }
          }
        }

        if ((suggestion.pageType == 'cover_page' ||
                suggestion.pageType == 'heirloom_feature') &&
            suggestion.photoPaths.isNotEmpty) {
          heroPhotoPath = suggestion.photoPaths.first;
        }

        final isMaterialPage = suggestion.pageType == 'story_page' ||
            suggestion.pageType == 'document_page' ||
            suggestion.pageType == 'heirloom_feature';

        pages.add(
          AtlasBookPage(
            bookId: bookId,
            pageType: suggestion.pageType,
            personId: suggestion.personId,
            relatedPersonId: suggestion.relatedPersonId,
            heroPhotoPath: heroPhotoPath,
            generationCount: suggestion.generationCount,
            collagePhotoPathsJson: suggestion.pageType == 'collage'
                ? jsonEncode(suggestion.photoPaths)
                : '[]',
            collageLayoutKey: suggestion.pageType == 'collage'
                ? 'balanced_grid'
                : '',
            collageLayoutSeed: 0,
            collageTitle: suggestion.pageType == 'collage'
                ? suggestion.title
                : suggestion.pageType == 'cover_page'
                    ? widget.book.title
                    : isMaterialPage
                        ? suggestion.title
                        : '',
            collageSubtitle: suggestion.pageType == 'cover_page'
                ? widget.book.subtitle
                : isMaterialPage
                    ? suggestion.subtitle
                    : '',
            collagePhotoLayoutJson: isMaterialPage
                ? jsonEncode({
                    'itemType': suggestion.materialType,
                    'itemKey': suggestion.materialKey,
                    'body': suggestion.materialBody,
                    'designKey': suggestion.pageType == 'heirloom_feature'
                        ? 'feature'
                        : suggestion.pageType == 'story_page'
                            ? 'narrative'
                            : 'classic',
                    'paperKey': 'ivory',
                  })
                : '',
            sortOrder: nextSortOrder + index,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      await _repository.insertBookPages(pages);
      await _loadBookPages();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${pages.length} '
            '${pages.length == 1 ? 'suggested page' : 'suggested pages'} '
            'added. You can edit, reorder, or delete any of them.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      // Close the progress dialog if it is still open.
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Smart Book Builder could not finish: $error')),
      );
    }
  }

  void _showSmartBuilderProgress(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<_SmartBookSuggestion>> _buildSmartBookSuggestions({
    required Set<String> builderPhotoPaths,
  }) async {
    final suggestions = <_SmartBookSuggestion>[];
    final existingKeys = _bookPages.map(_smartPageKey).toSet();

    final people = [..._selectedPeople]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

    final hasCoverPage = _bookPages.any((page) => page.pageType == 'cover_page');
    if (!hasCoverPage) {
      final coverPhotos = builderPhotoPaths
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty && File(path).existsSync())
          .take(1)
          .toList();
      suggestions.add(
        _SmartBookSuggestion(
          id: 'cover_page:starter',
          pageType: 'cover_page',
          title: widget.book.title,
          subtitle: 'Cover / Title Page',
          description: coverPhotos.isEmpty
              ? 'Start the book with its title and subtitle.'
              : 'Start the book with its title, subtitle, and a selected photo.',
          icon: Icons.menu_book_outlined,
          photoPaths: coverPhotos,
          recommended: true,
        ),
      );
    }

    // Person profiles require no additional database lookups.
    for (final person in people) {
      final id = person.id;
      if (id == null) continue;

      final key = 'person_profile:$id';
      if (existingKeys.contains(key)) continue;

      suggestions.add(
        _SmartBookSuggestion(
          id: key,
          pageType: 'person_profile',
          title: person.displayName,
          subtitle: 'Person Profile',
          description: person.lifeSpan.isEmpty
              ? 'Introduce ${person.displayName} with a profile page.'
              : '${person.lifeSpan} • profile page',
          icon: Icons.person_outline,
          personId: id,
          recommended: true,
        ),
      );
    }

    // Keep the relationship work bounded. We only need one fan chart and a
    // useful starter set of family-group pages; the user can add more later.
    var fanChartAdded = false;
    var familyGroupSuggestions = 0;
    const maxFamilyGroupSuggestions = 12;

    for (final person in people) {
      final id = person.id;
      if (id == null) continue;

      if (!fanChartAdded) {
        final parents = await _databaseHelper.getFamilyParents(id);
        if (parents.isNotEmpty) {
          final key = 'ancestry_fan_chart:$id';
          if (!existingKeys.contains(key)) {
            suggestions.add(
              _SmartBookSuggestion(
                id: key,
                pageType: 'ancestry_fan_chart',
                title: 'Ancestry of ${person.displayName}',
                subtitle: 'Ancestry Fan Chart',
                description:
                    'Show this family line visually across up to 4 generations.',
                icon: Icons.hub_outlined,
                personId: id,
                generationCount: 4,
                recommended: widget.book.scope != AtlasBookScope.people,
              ),
            );
          }
          fanChartAdded = true;
        }
      }

      if (familyGroupSuggestions >= maxFamilyGroupSuggestions) {
        if (fanChartAdded) break;
        continue;
      }

      final spouses = await _databaseHelper.getFamilySpouses(id);
      final children = await _databaseHelper.getFamilyChildren(id);

      if (spouses.isEmpty && children.isEmpty) continue;

      final spouse = spouses.isEmpty ? null : spouses.first;
      final spouseId = spouse?.id;

      final key = 'family_group_sheet:$id:${spouseId ?? 0}';
      final reverseKey = spouseId == null
          ? ''
          : 'family_group_sheet:$spouseId:$id';

      final alreadySuggested = suggestions.any(
        (suggestion) =>
            suggestion.id == key ||
            (reverseKey.isNotEmpty && suggestion.id == reverseKey),
      );

      if (existingKeys.contains(key) ||
          (reverseKey.isNotEmpty && existingKeys.contains(reverseKey)) ||
          alreadySuggested) {
        continue;
      }

      suggestions.add(
        _SmartBookSuggestion(
          id: key,
          pageType: 'family_group_sheet',
          title: spouse == null
              ? '${person.displayName} Family'
              : '${person.displayName} & ${spouse.displayName}',
          subtitle: 'Family Group Sheet',
          description: children.isEmpty
              ? 'Summarize this family relationship.'
              : '${children.length} '
                    '${children.length == 1 ? 'child' : 'children'} '
                    'connected in the tree.',
          icon: Icons.family_restroom_outlined,
          personId: id,
          relatedPersonId: spouseId,
          recommended: true,
        ),
      );

      familyGroupSuggestions++;
    }


    _AtlasGatherItem? selectedItem(
      List<_AtlasGatherItem> items,
      String key,
    ) {
      for (final item in items) {
        if (item.key == key) return item;
      }
      return null;
    }

    for (final key in _selectedStoryKeys) {
      final item = selectedItem(_connectedStories, key);
      if (item == null) continue;
      final suggestionId = 'story_page:story:$key';
      if (existingKeys.contains(suggestionId)) continue;
      suggestions.add(
        _SmartBookSuggestion(
          id: suggestionId,
          pageType: 'story_page',
          title: item.title,
          subtitle: item.subtitle.isEmpty ? 'Family Story' : item.subtitle,
          description: 'Feature this selected family story as a narrative page.',
          icon: Icons.auto_stories_outlined,
          materialType: 'story',
          materialKey: key,
          materialBody: item.body,
          recommended: true,
        ),
      );
    }

    for (final key in _selectedDocumentKeys) {
      final item = selectedItem(_connectedDocuments, key);
      if (item == null) continue;
      final suggestionId = 'document_page:document:$key';
      if (existingKeys.contains(suggestionId)) continue;
      suggestions.add(
        _SmartBookSuggestion(
          id: suggestionId,
          pageType: 'document_page',
          title: item.title,
          subtitle: 'Archive Document',
          description: 'Give this selected document its own archival feature page.',
          icon: Icons.description_outlined,
          materialType: 'document',
          materialKey: key,
          materialBody: item.subtitle,
          recommended: true,
        ),
      );
    }

    for (final key in _selectedCollectibleKeys) {
      final item = selectedItem(_connectedCollectibles, key);
      if (item == null) continue;
      final suggestionId = 'heirloom_feature:collectible:$key';
      if (existingKeys.contains(suggestionId)) continue;
      final imagePath = item.imagePath.trim();
      suggestions.add(
        _SmartBookSuggestion(
          id: suggestionId,
          pageType: 'heirloom_feature',
          title: item.title,
          subtitle: item.subtitle.isEmpty ? 'Heirloom Feature' : item.subtitle,
          description: 'Feature this selected heirloom or collection item in the book.',
          icon: Icons.museum_outlined,
          photoPaths: imagePath.isNotEmpty && File(imagePath).existsSync()
              ? [imagePath]
              : const [],
          materialType: 'collectible',
          materialKey: key,
          materialBody: item.subtitle,
          recommended: true,
        ),
      );
    }

    final photos = builderPhotoPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList();

    // Step 2 photos should always be available to Smart Builder as material.
    // Do not suppress them just because an older/failed collage page already
    // stored the same paths; the user may not actually have a usable photo page.
    if (photos.isNotEmpty) {
      final collagePhotos = photos.take(8).toList();
      final photoWord = collagePhotos.length == 1 ? 'photo' : 'photos';

      suggestions.add(
        _SmartBookSuggestion(
          id: 'collage:selected:${collagePhotos.join('|').hashCode}',
          pageType: 'collage',
          title: 'Family Photo Collage',
          subtitle: 'Photo Collage',
          description:
              '${collagePhotos.length} saved $photoWord from Step 2 will be '
              'used on this page.',
          icon: Icons.grid_view_outlined,
          photoPaths: collagePhotos,
          recommended: true,
        ),
      );
    }

    return suggestions;
  }

  String _smartPageKey(AtlasBookPage page) {
    switch (page.pageType) {
      case 'person_profile':
        return 'person_profile:${page.personId ?? 0}';
      case 'ancestry_fan_chart':
        return 'ancestry_fan_chart:${page.personId ?? 0}';
      case 'family_group_sheet':
        return 'family_group_sheet:${page.personId ?? 0}:'
            '${page.relatedPersonId ?? 0}';
      case 'collage':
        return 'collage:${page.id ?? 0}';
      case 'story_page':
      case 'document_page':
      case 'heirloom_feature':
        try {
          final data = jsonDecode(page.collagePhotoLayoutJson);
          if (data is Map) {
            final itemType = data['itemType']?.toString() ?? '';
            final itemKey = data['itemKey']?.toString() ?? '';
            if (itemType.isNotEmpty && itemKey.isNotEmpty) {
              return '${page.pageType}:$itemType:$itemKey';
            }
          }
        } catch (_) {}
        return '${page.pageType}:${page.id ?? 0}';
      default:
        return '${page.pageType}:${page.id ?? 0}';
    }
  }

  Future<void> _addPage() async {
    final pageType = await showDialog<String>(
      context: context,
      builder: (_) => const _AddPageTypeDialog(),
    );

    if (pageType == 'cover_page') {
      await _createCoverPage();
    } else if (pageType == 'person_profile') {
      await _createPersonProfilePage();
    } else if (pageType == 'ancestry_fan_chart') {
      await _createAncestryFanChartPage();
    } else if (pageType == 'family_group_sheet') {
      await _createFamilyGroupSheetPage();
    } else if (pageType == 'collage') {
      await _createCollagePage();
    }
  }

  Future<void> _createCoverPage() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    final result = await showDialog<_CoverPageResult>(
      context: context,
      builder: (_) => _CoverPageDialog(
        initialTitle: widget.book.title,
        initialSubtitle: widget.book.subtitle,
        photoPaths: _selectedPhotoPaths
            .where((path) => path.isNotEmpty && File(path).existsSync())
            .toList(),
      ),
    );
    if (result == null) return;

    final now = DateTime.now();
    await _repository.insertBookPage(
      AtlasBookPage(
        bookId: bookId,
        pageType: 'cover_page',
        heroPhotoPath: result.photoPath ?? '',
        collageTitle: result.title,
        collageSubtitle: result.subtitle,
        sortOrder: await _repository.getNextBookPageSortOrder(bookId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _loadBookPages();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cover / Title Page saved to this book.')),
    );
  }

  Future<void> _createCollagePage() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    final availablePhotos = _selectedPhotoPaths
        .where((path) => path.isNotEmpty && File(path).existsSync())
        .toList();

    if (availablePhotos.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Save at least two photos to this book before adding a collage.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<_CollagePageResult>(
      context: context,
      builder: (_) => _CollagePageDialog(photoPaths: availablePhotos),
    );

    if (result == null) return;

    final now = DateTime.now();

    await _repository.insertBookPage(
      AtlasBookPage(
        bookId: bookId,
        pageType: 'collage',
        collagePhotoPathsJson: jsonEncode(result.photoPaths),
        collageLayoutKey: result.layoutKey,
        collageLayoutSeed: result.layoutSeed,
        collageTitle: result.title,
        collageSubtitle: result.subtitle,
        collagePhotoLayoutJson: result.photoLayoutJson,
        sortOrder: await _repository.getNextBookPageSortOrder(bookId),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _loadBookPages();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Collage page saved to this book.')),
    );
  }

  Future<void> _createPersonProfilePage() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    if (_selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose at least one person for this book first.'),
        ),
      );
      return;
    }

    final result = await showDialog<_PersonProfilePageResult>(
      context: context,
      builder: (_) => _PersonProfilePageDialog(
        people: _selectedPeople,
        photoPaths: _selectedPhotoPaths
            .where((path) => path.isNotEmpty && File(path).existsSync())
            .toList(),
      ),
    );

    if (result == null) return;

    final now = DateTime.now();
    await _repository.insertBookPage(
      AtlasBookPage(
        bookId: bookId,
        pageType: 'person_profile',
        personId: result.personId,
        heroPhotoPath: result.heroPhotoPath ?? '',
        sortOrder: await _repository.getNextBookPageSortOrder(bookId),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _loadBookPages();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Person Profile page saved to this book.')),
    );
  }

  Future<void> _createAncestryFanChartPage() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    if (_selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose at least one person for this book first.'),
        ),
      );
      return;
    }

    final result = await showDialog<_FanChartPageResult>(
      context: context,
      builder: (_) => _FanChartSetupDialog(
        people: _selectedPeople,
        databaseHelper: _databaseHelper,
      ),
    );

    if (result == null) return;

    final now = DateTime.now();

    await _repository.insertBookPage(
      AtlasBookPage(
        bookId: bookId,
        pageType: 'ancestry_fan_chart',
        personId: result.personId,
        generationCount: result.generationCount,
        sortOrder: await _repository.getNextBookPageSortOrder(bookId),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _loadBookPages();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ancestry Fan Chart page saved to this book.'),
      ),
    );
  }

  Future<List<_FanAncestorNode>> _buildFanAncestors({
    required int rootPersonId,
    required int generationCount,
  }) async {
    final nodes = <_FanAncestorNode>[];
    final visited = <int>{};

    Future<void> walk(int personId, int generation, int slot) async {
      if (generation >= generationCount) return;
      if (!visited.add(personId)) return;

      final person = await _databaseHelper.getFamilyPerson(personId);
      if (person == null) return;

      nodes.add(
        _FanAncestorNode(person: person, generation: generation, slot: slot),
      );

      if (generation + 1 >= generationCount) return;

      final parents = await _databaseHelper.getFamilyParents(personId);

      for (final parent in parents) {
        final parentId = parent.id;
        if (parentId == null) continue;

        final role = await _databaseHelper.getFamilyParentRole(
          parentId: parentId,
          childId: personId,
        );

        final lowerRole = role.toLowerCase();
        final parentSlot = lowerRole.contains('mother')
            ? (slot * 2) + 1
            : slot * 2;

        await walk(parentId, generation + 1, parentSlot);
      }
    }

    await walk(rootPersonId, 0, 0);
    return nodes;
  }

  Future<void> _createFamilyGroupSheetPage() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    if (_selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose at least one person for this book first.'),
        ),
      );
      return;
    }

    final result = await showDialog<_FamilyGroupSheetResult>(
      context: context,
      builder: (_) => _FamilyGroupSheetSetupDialog(
        people: _selectedPeople,
        databaseHelper: _databaseHelper,
      ),
    );

    if (result == null) return;

    final now = DateTime.now();

    await _repository.insertBookPage(
      AtlasBookPage(
        bookId: bookId,
        pageType: 'family_group_sheet',
        personId: result.primaryPersonId,
        relatedPersonId: result.spousePersonId,
        sortOrder: await _repository.getNextBookPageSortOrder(bookId),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _loadBookPages();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Family Group Sheet saved to this book.')),
    );
  }

  Future<_FamilyGroupSheetData?> _buildFamilyGroupSheetData({
    required int primaryPersonId,
    int? spousePersonId,
  }) async {
    final primary = await _databaseHelper.getFamilyPerson(primaryPersonId);

    if (primary == null) return null;

    FamilyPerson? spouse;
    if (spousePersonId != null) {
      spouse = await _databaseHelper.getFamilyPerson(spousePersonId);
    }

    final primaryParents = await _databaseHelper.getFamilyParents(
      primaryPersonId,
    );

    final spouseParents = spousePersonId == null
        ? <FamilyPerson>[]
        : await _databaseHelper.getFamilyParents(spousePersonId);

    final primaryChildren = await _databaseHelper.getFamilyChildren(
      primaryPersonId,
    );

    final children = <FamilyPerson>[];

    if (spousePersonId == null) {
      children.addAll(primaryChildren);
    } else {
      for (final child in primaryChildren) {
        final childId = child.id;
        if (childId == null) continue;

        final parents = await _databaseHelper.getFamilyParents(childId);
        final sharesSelectedSpouse = parents.any(
          (parent) => parent.id == spousePersonId,
        );

        if (sharesSelectedSpouse) {
          children.add(child);
        }
      }
    }

    return _FamilyGroupSheetData(
      primary: primary,
      spouse: spouse,
      primaryParents: primaryParents,
      spouseParents: spouseParents,
      children: children,
    );
  }

  Future<void> _editPage(AtlasBookPage page) async {
    final pageId = page.id;
    if (pageId == null) return;

    final isMaterialPage = page.pageType == 'story_page' ||
        page.pageType == 'document_page' ||
        page.pageType == 'heirloom_feature';

    if (page.pageType != 'collage' &&
        page.pageType != 'cover_page' &&
        !isMaterialPage &&
        _selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose people for this book before editing pages.'),
        ),
      );
      return;
    }

    final now = DateTime.now();

    if (isMaterialPage) {
      var body = '';
      var designKey = 'classic';
      var paperKey = 'ivory';
      try {
        final data = jsonDecode(page.collagePhotoLayoutJson);
        if (data is Map) {
          body = data['body']?.toString() ?? '';
          designKey = data['designKey']?.toString() ?? 'classic';
          paperKey = data['paperKey']?.toString() ?? 'ivory';
        }
      } catch (_) {}

      final result = await showDialog<_MaterialPageEditResult>(
        context: context,
        builder: (_) => _MaterialPageEditDialog(
          initialTitle: page.collageTitle,
          initialSubtitle: page.collageSubtitle,
          initialBody: body,
          initialDesignKey: designKey,
          initialPaperKey: paperKey,
        ),
      );
      if (result == null) return;

      Map<String, dynamic> metadata = {};
      try {
        final decoded = jsonDecode(page.collagePhotoLayoutJson);
        if (decoded is Map) {
          metadata = decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
      metadata['body'] = result.body;
      metadata['designKey'] = result.designKey;
      metadata['paperKey'] = result.paperKey;

      await _repository.updateBookPage(
        AtlasBookPage(
          id: pageId,
          bookId: page.bookId,
          pageType: page.pageType,
          personId: page.personId,
          relatedPersonId: page.relatedPersonId,
          heroPhotoPath: page.heroPhotoPath,
          generationCount: page.generationCount,
          collagePhotoPathsJson: page.collagePhotoPathsJson,
          collageLayoutKey: page.collageLayoutKey,
          collageLayoutSeed: page.collageLayoutSeed,
          collageTitle: result.title,
          collageSubtitle: result.subtitle,
          collagePhotoLayoutJson: jsonEncode(metadata),
          sortOrder: page.sortOrder,
          createdAt: page.createdAt,
          updatedAt: now,
        ),
      );
    } else if (page.pageType == 'cover_page') {
      final result = await showDialog<_CoverPageResult>(
        context: context,
        builder: (_) => _CoverPageDialog(
          initialTitle: page.collageTitle.isEmpty ? widget.book.title : page.collageTitle,
          initialSubtitle: page.collageSubtitle,
          initialPhotoPath: page.heroPhotoPath,
          photoPaths: _selectedPhotoPaths
              .where((path) => path.isNotEmpty && File(path).existsSync())
              .toList(),
        ),
      );
      if (result == null) return;
      await _repository.updateBookPage(
        AtlasBookPage(
          id: pageId,
          bookId: page.bookId,
          pageType: page.pageType,
          heroPhotoPath: result.photoPath ?? '',
          collageTitle: result.title,
          collageSubtitle: result.subtitle,
          sortOrder: page.sortOrder,
          createdAt: page.createdAt,
          updatedAt: now,
        ),
      );
    } else if (page.pageType == 'collage') {
      final availablePhotos = _selectedPhotoPaths
          .where((path) => path.isNotEmpty && File(path).existsSync())
          .toList();

      if (availablePhotos.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Save at least two photos to this book before editing a collage.',
            ),
          ),
        );
        return;
      }

      List<String> initialPhotos = [];
      try {
        final decoded = jsonDecode(page.collagePhotoPathsJson);
        if (decoded is List) {
          initialPhotos = decoded
              .whereType<String>()
              .where((path) => File(path).existsSync())
              .toList();
        }
      } catch (_) {
        initialPhotos = [];
      }

      final result = await showDialog<_CollagePageResult>(
        context: context,
        builder: (_) => _CollagePageDialog(
          photoPaths: availablePhotos,
          initialSelectedPaths: initialPhotos,
          initialLayoutKey: page.collageLayoutKey,
          initialLayoutSeed: page.collageLayoutSeed,
          initialTitle: page.collageTitle,
          initialSubtitle: page.collageSubtitle,
          initialPhotoLayoutJson: page.collagePhotoLayoutJson,
          isEditing: true,
        ),
      );

      if (result == null) return;

      await _repository.updateBookPage(
        AtlasBookPage(
          id: pageId,
          bookId: page.bookId,
          pageType: page.pageType,
          personId: page.personId,
          relatedPersonId: page.relatedPersonId,
          heroPhotoPath: page.heroPhotoPath,
          generationCount: page.generationCount,
          collagePhotoPathsJson: jsonEncode(result.photoPaths),
          collageLayoutKey: result.layoutKey,
          collageLayoutSeed: result.layoutSeed,
          collageTitle: result.title,
          collageSubtitle: result.subtitle,
          collagePhotoLayoutJson: result.photoLayoutJson,
          sortOrder: page.sortOrder,
          createdAt: page.createdAt,
          updatedAt: now,
        ),
      );
    } else if (page.pageType == 'person_profile') {
      final result = await showDialog<_PersonProfilePageResult>(
        context: context,
        builder: (_) => _PersonProfilePageDialog(
          people: _selectedPeople,
          photoPaths: _selectedPhotoPaths
              .where((path) => path.isNotEmpty && File(path).existsSync())
              .toList(),
          initialPersonId: page.personId,
          initialHeroPhotoPath: page.heroPhotoPath,
          isEditing: true,
        ),
      );

      if (result == null) return;

      await _repository.updateBookPage(
        AtlasBookPage(
          id: pageId,
          bookId: page.bookId,
          pageType: page.pageType,
          personId: result.personId,
          relatedPersonId: page.relatedPersonId,
          heroPhotoPath: result.heroPhotoPath ?? '',
          generationCount: page.generationCount,
          collagePhotoPathsJson: page.collagePhotoPathsJson,
          collageLayoutKey: page.collageLayoutKey,
          collageLayoutSeed: page.collageLayoutSeed,
          collageTitle: page.collageTitle,
          collageSubtitle: page.collageSubtitle,
          collagePhotoLayoutJson: page.collagePhotoLayoutJson,
          sortOrder: page.sortOrder,
          createdAt: page.createdAt,
          updatedAt: now,
        ),
      );
    } else if (page.pageType == 'ancestry_fan_chart') {
      final result = await showDialog<_FanChartPageResult>(
        context: context,
        builder: (_) => _FanChartSetupDialog(
          people: _selectedPeople,
          databaseHelper: _databaseHelper,
          initialPersonId: page.personId,
          initialGenerationCount: page.generationCount,
          isEditing: true,
        ),
      );

      if (result == null) return;

      await _repository.updateBookPage(
        AtlasBookPage(
          id: pageId,
          bookId: page.bookId,
          pageType: page.pageType,
          personId: result.personId,
          relatedPersonId: page.relatedPersonId,
          heroPhotoPath: page.heroPhotoPath,
          generationCount: result.generationCount,
          collagePhotoPathsJson: page.collagePhotoPathsJson,
          collageLayoutKey: page.collageLayoutKey,
          collageLayoutSeed: page.collageLayoutSeed,
          collageTitle: page.collageTitle,
          collageSubtitle: page.collageSubtitle,
          collagePhotoLayoutJson: page.collagePhotoLayoutJson,
          sortOrder: page.sortOrder,
          createdAt: page.createdAt,
          updatedAt: now,
        ),
      );
    } else if (page.pageType == 'family_group_sheet') {
      final result = await showDialog<_FamilyGroupSheetResult>(
        context: context,
        builder: (_) => _FamilyGroupSheetSetupDialog(
          people: _selectedPeople,
          databaseHelper: _databaseHelper,
          initialPrimaryPersonId: page.personId,
          initialSpousePersonId: page.relatedPersonId,
          isEditing: true,
        ),
      );

      if (result == null) return;

      await _repository.updateBookPage(
        AtlasBookPage(
          id: pageId,
          bookId: page.bookId,
          pageType: page.pageType,
          personId: result.primaryPersonId,
          relatedPersonId: result.spousePersonId,
          heroPhotoPath: page.heroPhotoPath,
          generationCount: page.generationCount,
          collagePhotoPathsJson: page.collagePhotoPathsJson,
          collageLayoutKey: page.collageLayoutKey,
          collageLayoutSeed: page.collageLayoutSeed,
          collageTitle: page.collageTitle,
          collageSubtitle: page.collageSubtitle,
          collagePhotoLayoutJson: page.collagePhotoLayoutJson,
          sortOrder: page.sortOrder,
          createdAt: page.createdAt,
          updatedAt: now,
        ),
      );
    }

    await _loadBookPages();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Page changes saved.')));
  }

  Future<void> _deletePage(AtlasBookPage page) async {
    if (page.id == null) return;
    await _repository.deleteBookPage(page.id!);
    await _loadBookPages();
  }

  Future<void> _movePage(int index, int direction) async {
    final target = index + direction;
    if (target < 0 || target >= _bookPages.length) return;

    final reordered = [..._bookPages];
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);

    final bookId = widget.book.id;
    if (bookId == null) return;

    setState(() => _bookPages = reordered);

    await _repository.reorderBookPages(
      bookId,
      reordered
          .where((page) => page.id != null)
          .map((page) => page.id!)
          .toList(),
    );

    await _loadBookPages();
  }

  Future<void> _previewSavedPage(AtlasBookPage page) async {
    if (page.pageType == 'cover_page') {
      await showDialog<void>(
        context: context,
        builder: (_) => _SavedCoverPagePreviewDialog(page: page),
      );
      return;
    }

    if (page.pageType == 'story_page' ||
        page.pageType == 'document_page' ||
        page.pageType == 'heirloom_feature') {
      await showDialog<void>(
        context: context,
        builder: (_) => _SavedMaterialPagePreviewDialog(page: page),
      );
      return;
    }

    if (page.pageType == 'collage') {
      List<String> photoPaths = [];

      try {
        final decoded = jsonDecode(page.collagePhotoPathsJson);
        if (decoded is List) {
          photoPaths = decoded
              .whereType<String>()
              .where((path) => File(path).existsSync())
              .toList();
        }
      } catch (_) {
        photoPaths = [];
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _SavedCollagePreviewDialog(
          photoPaths: photoPaths,
          layoutKey: page.collageLayoutKey,
          layoutSeed: page.collageLayoutSeed,
          title: page.collageTitle,
          subtitle: page.collageSubtitle,
          photoLayoutJson: page.collagePhotoLayoutJson,
        ),
      );
      return;
    }

    if (page.personId == null) return;

    if (page.pageType == 'family_group_sheet') {
      final data = await _buildFamilyGroupSheetData(
        primaryPersonId: page.personId!,
        spousePersonId: page.relatedPersonId,
      );

      if (data == null || !mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _SavedFamilyGroupSheetPreviewDialog(data: data),
      );
      return;
    }

    if (page.pageType == 'ancestry_fan_chart') {
      final nodes = await _buildFanAncestors(
        rootPersonId: page.personId!,
        generationCount: page.generationCount,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _SavedFanChartPreviewDialog(
          nodes: nodes,
          generationCount: page.generationCount,
        ),
      );
      return;
    }

    final person = await _databaseHelper.getFamilyPerson(page.personId!);
    if (person == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _SavedPersonProfilePreviewDialog(
        person: person,
        heroPhotoPath: page.heroPhotoPath,
      ),
    );
  }

  Future<void> _previewBook() async {
    if (_bookPages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one page before previewing the book.'),
        ),
      );
      return;
    }

    final previewPages = <_BookPreviewPageData>[];

    for (final page in _bookPages) {
      if (page.pageType == 'cover_page') {
        previewPages.add(_BookPreviewPageData(page: page));
        continue;
      }

      if (page.pageType == 'story_page' ||
          page.pageType == 'document_page' ||
          page.pageType == 'heirloom_feature') {
        previewPages.add(_BookPreviewPageData(page: page));
        continue;
      }

      if (page.pageType == 'collage') {
        List<String> photoPaths = [];

        try {
          final decoded = jsonDecode(page.collagePhotoPathsJson);
          if (decoded is List) {
            photoPaths = decoded
                .whereType<String>()
                .where((path) => File(path).existsSync())
                .toList();
          }
        } catch (_) {
          photoPaths = [];
        }

        previewPages.add(
          _BookPreviewPageData(page: page, collagePhotoPaths: photoPaths),
        );
        continue;
      }

      if (page.personId == null) continue;

      if (page.pageType == 'ancestry_fan_chart') {
        final nodes = await _buildFanAncestors(
          rootPersonId: page.personId!,
          generationCount: page.generationCount,
        );

        previewPages.add(_BookPreviewPageData(page: page, fanNodes: nodes));
        continue;
      }

      if (page.pageType == 'family_group_sheet') {
        final data = await _buildFamilyGroupSheetData(
          primaryPersonId: page.personId!,
          spousePersonId: page.relatedPersonId,
        );

        if (data != null) {
          previewPages.add(
            _BookPreviewPageData(page: page, familyGroupData: data),
          );
        }
        continue;
      }

      final person = await _databaseHelper.getFamilyPerson(page.personId!);

      if (person != null) {
        previewPages.add(_BookPreviewPageData(page: page, person: person));
      }
    }

    if (!mounted || previewPages.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _WholeBookPreviewDialog(
        bookTitle: widget.book.title,
        pages: previewPages,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFF071A2B).withValues(alpha: 0.54),
        surfaceTintColor: Colors.transparent,
        title: Text(
          book.title,
          style: const TextStyle(
            color: Color(0xFFF3E9D1),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF071A2B).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFC9A65A).withValues(alpha: 0.46),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FractionallySizedBox(
                            widthFactor: 0.55,
                            child: Opacity(
                              opacity: 0.46,
                              child: Image.asset(
                                'assets/branding/heirloom_atlas_beta_heritage_atmosphere.png',
                                fit: BoxFit.cover,
                                alignment: Alignment.bottomRight,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFC071A2B),
                                Color(0xE9071A2B),
                                Color(0x9A071A2B),
                                Color(0x30071A2B),
                              ],
                              stops: [0.0, 0.43, 0.72, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 22, 20),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF103451,
                                ).withValues(alpha: 0.86),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: const Color(
                                    0xFFC9A65A,
                                  ).withValues(alpha: 0.34),
                                ),
                              ),
                              child: Icon(
                                book.scope.icon,
                                color: const Color(0xFFC9A65A),
                                size: 29,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    book.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(
                                          color: const Color(0xFFF3E9D1),
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  if (book.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      book.subtitle,
                                      style: AtlasBookTheme.subtitle(context),
                                    ),
                                  ],
                                  const SizedBox(height: 7),
                                  Text(
                                    'Shape the people, photographs, and memories into a book your family can keep.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(
                                            0xFFF3E9D1,
                                          ).withValues(alpha: 0.86),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Chip(
                              avatar: Icon(book.scope.icon, size: 18),
                              label: Text(book.scope.label),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Icon(
                      Icons.history_edu_outlined,
                      color: Color(0xFFC9A65A),
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'Build Your Book',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: const Color(0xFFF3E9D1),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _BookProgressOverview(
                  peopleCount: _selectedPeople.length,
                  photoCount: _selectedPhotoPaths.length,
                  pageCount: _bookPages.length,
                  readyToPreview: _bookPages.isNotEmpty,
                ),
                const SizedBox(height: 14),
                _WorkspaceStep(
                  number: '1',
                  title: _selectionTitle(book.scope),
                  description: _selectionDescription(book.scope),
                  icon: book.scope.icon,
                  onTap: switch (book.scope) {
                    AtlasBookScope.people => _choosePeople,
                    AtlasBookScope.branch => _chooseFamilyBranch,
                    AtlasBookScope.generations => _chooseGenerations,
                  },
                  actionLabel: switch (book.scope) {
                    AtlasBookScope.people => 'Choose People',
                    AtlasBookScope.branch => 'Choose Branch',
                    AtlasBookScope.generations => 'Choose Generations',
                  },
                ),
                const SizedBox(height: 12),
                _SelectedPeoplePanel(
                  loading: _loadingPeople,
                  people: _selectedPeople,
                  onChoosePeople: switch (book.scope) {
                    AtlasBookScope.people => _choosePeople,
                    AtlasBookScope.branch => _chooseFamilyBranch,
                    AtlasBookScope.generations => _chooseGenerations,
                  },
                  emptyMessage: switch (book.scope) {
                    AtlasBookScope.people =>
                      'No people have been added to this book yet.',
                    AtlasBookScope.branch =>
                      'No family branch has been selected yet.',
                    AtlasBookScope.generations =>
                      'No generations have been selected yet.',
                  },
                  actionLabel: switch (book.scope) {
                    AtlasBookScope.people => 'Choose People',
                    AtlasBookScope.branch => 'Choose Branch',
                    AtlasBookScope.generations => 'Choose Generations',
                  },
                  editLabel: switch (book.scope) {
                    AtlasBookScope.people => 'Edit',
                    AtlasBookScope.branch => 'Change Branch',
                    AtlasBookScope.generations => 'Change Generations',
                  },
                ),
                const SizedBox(height: 12),
                _WorkspaceStep(
                  number: '2',
                  title: 'Gather connected material',
                  description:
                      'Find photos, stories, documents, heirlooms, and other '
                      'items connected to the people in this book.',
                  icon: Icons.collections_bookmark_outlined,
                  onTap: _gatherConnectedPhotos,
                  actionLabel: 'Gather Material',
                ),
                if (_loadingConnectedPhotos ||
                    _connectedPhotoPaths.isNotEmpty ||
                    _connectedStories.isNotEmpty ||
                    _connectedDocuments.isNotEmpty ||
                    _connectedCollectibles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _GatherMaterialPanel(
                    loading: _loadingConnectedPhotos,
                    photoPaths: _connectedPhotoPaths,
                    stories: _connectedStories,
                    documents: _connectedDocuments,
                    collectibles: _connectedCollectibles,
                    selectedPhotoPaths: _selectedPhotoPaths,
                    selectedStoryKeys: _selectedStoryKeys,
                    selectedDocumentKeys: _selectedDocumentKeys,
                    selectedCollectibleKeys: _selectedCollectibleKeys,
                    favoritePhotoPaths: _favoritePhotoPaths,
                    favoriteStoryKeys: _favoriteStoryKeys,
                    favoriteDocumentKeys: _favoriteDocumentKeys,
                    favoriteCollectibleKeys: _favoriteCollectibleKeys,
                    filter: _materialFilter,
                    onFilterChanged: (value) => setState(() => _materialFilter = value),
                    onSelectionChanged: (type, key, selected) {
                      setState(() {
                        final target = type == 'story'
                          ? _selectedStoryKeys
                          : type == 'document'
                              ? _selectedDocumentKeys
                              : type == 'collectible'
                                  ? _selectedCollectibleKeys
                                  : _selectedPhotoPaths;
                        selected ? target.add(key) : target.remove(key);
                      });
                    },
                    onFavoriteChanged: _setAtlasMaterialFavorite,
                    onSave: _saveBookMaterials,
                  )
                ],
                const SizedBox(height: 12),
                _WorkspaceStep(
                  number: '3',
                  title: 'Build the story',
                  description:
                      'Let Heirloom Atlas suggest a starter book from the '
                      'people, relationships, and material you selected — or '
                      'continue adding pages manually.',
                  icon: Icons.auto_awesome_outlined,
                  onTap: _openSmartBookBuilder,
                  actionLabel: 'Build Starter Book',
                ),
                const SizedBox(height: 12),
                _SmartBookBuilderPanel(
                  peopleCount: _selectedPeople.length,
                  photoCount: _selectedPhotoPaths.length,
                  storyCount: _selectedStoryKeys.length,
                  documentCount: _selectedDocumentKeys.length,
                  collectibleCount: _selectedCollectibleKeys.length,
                  pageCount: _bookPages.length,
                  onBuild: _openSmartBookBuilder,
                  onAddPage: _addPage,
                ),
                const SizedBox(height: 12),
                _BookPagesPanel(
                  loading: _loadingPages,
                  pages: _bookPages,
                  people: _selectedPeople,
                  onAddPage: _addPage,
                  onPreview: _previewSavedPage,
                  onEdit: _editPage,
                  onDelete: _deletePage,
                  onMoveUp: (index) => _movePage(index, -1),
                  onMoveDown: (index) => _movePage(index, 1),
                ),
                const SizedBox(height: 12),
                _WorkspaceStep(
                  number: '4',
                  title: 'Preview your Atlas Book',
                  description: _bookPages.isEmpty
                      ? 'Add at least one saved page, then preview the whole book.'
                      : 'Flip through all ${_bookPages.length} saved '
                            '${_bookPages.length == 1 ? 'page' : 'pages'} in book order.',
                  icon: Icons.preview_outlined,
                  onTap: _bookPages.isEmpty ? null : _previewBook,
                  actionLabel: _bookPages.isEmpty ? null : 'Preview Book',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _selectionTitle(AtlasBookScope scope) {
    switch (scope) {
      case AtlasBookScope.people:
        return 'Choose people';
      case AtlasBookScope.branch:
        return 'Choose a family branch';
      case AtlasBookScope.generations:
        return 'Choose generations';
    }
  }

  static String _selectionDescription(AtlasBookScope scope) {
    switch (scope) {
      case AtlasBookScope.people:
        return 'Select one or more people from your family tree.';
      case AtlasBookScope.branch:
        return 'Choose the family branch this book will follow.';
      case AtlasBookScope.generations:
        return 'Choose which generations you want represented in the book.';
    }
  }
}

class _BookProgressOverview extends StatelessWidget {
  final int peopleCount;
  final int photoCount;
  final int pageCount;
  final bool readyToPreview;

  const _BookProgressOverview({
    required this.peopleCount,
    required this.photoCount,
    required this.pageCount,
    required this.readyToPreview,
  });

  @override
  Widget build(BuildContext context) {
    final completed = <bool>[
      peopleCount > 0,
      photoCount > 0,
      pageCount > 0,
      readyToPreview,
    ].where((value) => value).length;
    final progress = completed / 4;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF071A2B).withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFC9A65A).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_stories_outlined,
                color: Color(0xFFC9A65A),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Book Progress',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF3E9D1),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xFFF3E9D1),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProgressChip(
                icon: Icons.people_outline,
                label: '$peopleCount ${peopleCount == 1 ? 'person' : 'people'}',
                complete: peopleCount > 0,
              ),
              _ProgressChip(
                icon: Icons.photo_library_outlined,
                label: '$photoCount saved ${photoCount == 1 ? 'photo' : 'photos'}',
                complete: photoCount > 0,
              ),
              _ProgressChip(
                icon: Icons.menu_book_outlined,
                label: '$pageCount ${pageCount == 1 ? 'page' : 'pages'}',
                complete: pageCount > 0,
              ),
              _ProgressChip(
                icon: Icons.preview_outlined,
                label: readyToPreview ? 'Ready to preview' : 'Preview not ready',
                complete: readyToPreview,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool complete;

  const _ProgressChip({
    required this.icon,
    required this.label,
    required this.complete,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        complete ? Icons.check_circle_outline : icon,
        size: 17,
        color: complete ? const Color(0xFFC9A65A) : null,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SmartBookSuggestion {
  final String id, pageType, title, subtitle, description;
  final IconData icon;
  final int? personId, relatedPersonId;
  final int generationCount;
  final List<String> photoPaths;
  final String materialType;
  final String materialKey;
  final String materialBody;
  final bool recommended;
  const _SmartBookSuggestion({
    required this.id,
    required this.pageType,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    this.personId,
    this.relatedPersonId,
    this.generationCount = 3,
    this.photoPaths = const [],
    this.materialType = '',
    this.materialKey = '',
    this.materialBody = '',
    this.recommended = false,
  });
}

class _SmartBookBuilderDialog extends StatefulWidget {
  final List<_SmartBookSuggestion> suggestions;
  const _SmartBookBuilderDialog({required this.suggestions});
  @override
  State<_SmartBookBuilderDialog> createState() =>
      _SmartBookBuilderDialogState();
}

class _SmartBookBuilderDialogState extends State<_SmartBookBuilderDialog> {
  late Set<String> _selectedIds;
  @override
  void initState() {
    super.initState();
    _selectedIds = widget.suggestions
        .where((s) => s.recommended)
        .map((s) => s.id)
        .toSet();
    if (_selectedIds.isEmpty && widget.suggestions.isNotEmpty) {
      _selectedIds.add(widget.suggestions.first.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 820,
        height: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Build Starter Book',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Create an editable first draft from the people and material '
                          'you selected. Nothing here is permanent—you can edit, reorder, '
                          'add, or remove pages afterward.',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.suggestions.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No new page suggestions are available right now. Try adding people, relationships, or saved photos.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.suggestions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final s = widget.suggestions[index];
                        return Card(
                          child: CheckboxListTile(
                            value: _selectedIds.contains(s.id),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _selectedIds.add(s.id)
                                  : _selectedIds.remove(s.id),
                            ),
                            secondary: CircleAvatar(child: Icon(s.icon)),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (s.recommended)
                                  const Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text('Recommended'),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${s.subtitle}\n${s.description}'),
                            ),
                            isThreeLine: true,
                            controlAffinity: ListTileControlAffinity.trailing,
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: widget.suggestions.isEmpty
                        ? null
                        : () => setState(
                            () => _selectedIds = widget.suggestions
                                .map((s) => s.id)
                                .toSet(),
                          ),
                    child: const Text('Select All'),
                  ),
                  TextButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => setState(_selectedIds.clear),
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selectedIds),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      'Add ${_selectedIds.length} ${_selectedIds.length == 1 ? 'Page' : 'Pages'}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartBookBuilderPanel extends StatelessWidget {
  final int peopleCount;
  final int photoCount;
  final int storyCount;
  final int documentCount;
  final int collectibleCount;
  final int pageCount;
  final VoidCallback onBuild, onAddPage;
  const _SmartBookBuilderPanel({
    required this.peopleCount,
    required this.photoCount,
    required this.storyCount,
    required this.documentCount,
    required this.collectibleCount,
    required this.pageCount,
    required this.onBuild,
    required this.onAddPage,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0B2742).withValues(alpha: 0.54),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFFC9A65A).withValues(alpha: 0.44),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              size: 38,
              color: Color(0xFFC9A65A),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Book Builder',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFF3E9D1),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$peopleCount ${peopleCount == 1 ? 'person' : 'people'} • '
                    '${photoCount + storyCount + documentCount + collectibleCount} selected '
                    '${photoCount + storyCount + documentCount + collectibleCount == 1 ? 'item' : 'items'} • '
                    '$pageCount existing ${pageCount == 1 ? 'page' : 'pages'}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$photoCount photos • $storyCount stories • '
                    '$documentCount documents • $collectibleCount collectibles',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Build an editable first draft from the people and material you deliberately selected.',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: onAddPage,
              icon: const Icon(Icons.add),
              label: const Text('Add Manually'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: peopleCount == 0 ? null : onBuild,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Build Starter Book'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _GenerationDirection { ancestors, descendants }

extension on _GenerationDirection {
  String get label {
    switch (this) {
      case _GenerationDirection.ancestors:
        return 'Ancestor generations';
      case _GenerationDirection.descendants:
        return 'Descendant generations';
    }
  }

  String get description {
    switch (this) {
      case _GenerationDirection.ancestors:
        return 'Start with this person and move backward through parents, grandparents, and earlier generations.';
      case _GenerationDirection.descendants:
        return 'Start with this person and move forward through children, grandchildren, and later generations.';
    }
  }

  IconData get icon {
    switch (this) {
      case _GenerationDirection.ancestors:
        return Icons.arrow_upward;
      case _GenerationDirection.descendants:
        return Icons.arrow_downward;
    }
  }
}

class _GenerationSelectionResult {
  final int rootPersonId;
  final _GenerationDirection direction;
  final int generationCount;

  const _GenerationSelectionResult({
    required this.rootPersonId,
    required this.direction,
    required this.generationCount,
  });
}

class _GenerationPickerDialog extends StatefulWidget {
  final List<FamilyPerson> people;

  const _GenerationPickerDialog({required this.people});

  @override
  State<_GenerationPickerDialog> createState() =>
      _GenerationPickerDialogState();
}

class _GenerationPickerDialogState extends State<_GenerationPickerDialog> {
  int? _rootPersonId;
  _GenerationDirection _direction = _GenerationDirection.ancestors;
  int _generationCount = 3;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final visiblePeople =
        widget.people.where((person) {
          if (query.isEmpty) return true;
          return [
            person.displayName,
            person.lifeSpan,
            person.birthPlace,
          ].join(' ').toLowerCase().contains(query);
        }).toList()..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

    FamilyPerson? selectedRoot;
    for (final person in widget.people) {
      if (person.id == _rootPersonId) {
        selectedRoot = person;
        break;
      }
    }

    return Dialog(
      child: SizedBox(
        width: 900,
        height: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.layers_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Generations',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Choose a starting person, a direction, and how many generations should be included.',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _search = value),
                            decoration: const InputDecoration(
                              labelText: 'Choose the starting person',
                              hintText: 'Search your Family Tree...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: visiblePeople.isEmpty
                              ? const Center(
                                  child: Text('No matching people found.'),
                                )
                              : ListView.separated(
                                  itemCount: visiblePeople.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final person = visiblePeople[index];
                                    final personId = person.id;
                                    if (personId == null) {
                                      return const SizedBox.shrink();
                                    }

                                    final selected = personId == _rootPersonId;
                                    final path = person.profilePhotoPath;
                                    final hasPhoto =
                                        path.isNotEmpty &&
                                        File(path).existsSync();

                                    return ListTile(
                                      selected: selected,
                                      leading: CircleAvatar(
                                        backgroundImage: hasPhoto
                                            ? FileImage(File(path))
                                            : null,
                                        child: hasPhoto
                                            ? null
                                            : const Icon(Icons.person_outline),
                                      ),
                                      title: Text(
                                        person.displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          if (person.lifeSpan.isNotEmpty)
                                            person.lifeSpan,
                                          if (person.birthPlace.isNotEmpty)
                                            person.birthPlace,
                                        ].join(' • '),
                                      ),
                                      trailing: selected
                                          ? const Icon(Icons.check_circle)
                                          : null,
                                      onTap: () => setState(
                                        () => _rootPersonId = personId,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 4,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          'Generation Settings',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        if (selectedRoot == null)
                          const Text(
                            'Select a starting person from the Family Tree.',
                          )
                        else
                          Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.person_pin_circle_outlined,
                              ),
                              title: Text(selectedRoot.displayName),
                              subtitle: const Text('Generation 1'),
                            ),
                          ),
                        const SizedBox(height: 20),
                        const Text(
                          'Direction',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        ..._GenerationDirection.values.map(
                          (direction) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(direction.icon),
                            title: Text(direction.label),
                            subtitle: Text(direction.description),
                            trailing: Icon(
                              _direction == direction
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                            ),
                            onTap: () => setState(() => _direction = direction),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Generations in the book',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '$_generationCount',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _generationCount.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          label: '$_generationCount',
                          onChanged: (value) =>
                              setState(() => _generationCount = value.round()),
                        ),
                        Text(_generationExplanation()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('The starting person counts as generation 1.'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _rootPersonId == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            _GenerationSelectionResult(
                              rootPersonId: _rootPersonId!,
                              direction: _direction,
                              generationCount: _generationCount,
                            ),
                          ),
                    icon: const Icon(Icons.layers_outlined),
                    label: const Text('Use These Generations'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _generationExplanation() {
    if (_generationCount == 1) {
      return 'Generation 1: the starting person only.';
    }

    if (_direction == _GenerationDirection.ancestors) {
      switch (_generationCount) {
        case 2:
          return 'Generation 1 + parents.';
        case 3:
          return 'Generation 1 + parents + grandparents.';
        case 4:
          return 'Generation 1 through great-grandparents.';
        default:
          return 'Generation 1 through 2× great-grandparents.';
      }
    }

    switch (_generationCount) {
      case 2:
        return 'Generation 1 + children.';
      case 3:
        return 'Generation 1 + children + grandchildren.';
      case 4:
        return 'Generation 1 through great-grandchildren.';
      default:
        return 'Generation 1 through great-great-grandchildren.';
    }
  }
}

enum _FamilyBranchDirection { ancestors, descendants, both }

extension on _FamilyBranchDirection {
  String get label {
    switch (this) {
      case _FamilyBranchDirection.ancestors:
        return 'Ancestors';
      case _FamilyBranchDirection.descendants:
        return 'Descendants';
      case _FamilyBranchDirection.both:
        return 'Both directions';
    }
  }

  String get description {
    switch (this) {
      case _FamilyBranchDirection.ancestors:
        return 'Parents, grandparents, and earlier generations.';
      case _FamilyBranchDirection.descendants:
        return 'Children, grandchildren, and later generations.';
      case _FamilyBranchDirection.both:
        return 'Follow this person both backward and forward in the tree.';
    }
  }

  IconData get icon {
    switch (this) {
      case _FamilyBranchDirection.ancestors:
        return Icons.account_tree_outlined;
      case _FamilyBranchDirection.descendants:
        return Icons.family_restroom_outlined;
      case _FamilyBranchDirection.both:
        return Icons.hub_outlined;
    }
  }
}

class _FamilyBranchSelectionResult {
  final int rootPersonId;
  final _FamilyBranchDirection direction;
  final int generationDepth;

  const _FamilyBranchSelectionResult({
    required this.rootPersonId,
    required this.direction,
    required this.generationDepth,
  });
}

class _FamilyBranchPickerDialog extends StatefulWidget {
  final List<FamilyPerson> people;

  const _FamilyBranchPickerDialog({required this.people});

  @override
  State<_FamilyBranchPickerDialog> createState() =>
      _FamilyBranchPickerDialogState();
}

class _FamilyBranchPickerDialogState extends State<_FamilyBranchPickerDialog> {
  int? _rootPersonId;
  _FamilyBranchDirection _direction = _FamilyBranchDirection.ancestors;
  int _generationDepth = 3;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final visiblePeople =
        widget.people.where((person) {
          if (query.isEmpty) return true;
          return [
            person.displayName,
            person.lifeSpan,
            person.birthPlace,
          ].join(' ').toLowerCase().contains(query);
        }).toList()..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

    FamilyPerson? selectedRoot;
    for (final person in widget.people) {
      if (person.id == _rootPersonId) {
        selectedRoot = person;
        break;
      }
    }

    return Dialog(
      child: SizedBox(
        width: 900,
        height: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose a Family Branch',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Choose one person, then decide which direction and how many generations Atlas Book should follow.',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _search = value),
                            decoration: const InputDecoration(
                              labelText: 'Find the starting person',
                              hintText: 'Search your Family Tree...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: visiblePeople.isEmpty
                              ? const Center(
                                  child: Text('No matching people found.'),
                                )
                              : ListView.separated(
                                  itemCount: visiblePeople.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final person = visiblePeople[index];
                                    final personId = person.id;
                                    if (personId == null) {
                                      return const SizedBox.shrink();
                                    }

                                    final selected = personId == _rootPersonId;
                                    final path = person.profilePhotoPath;
                                    final hasPhoto =
                                        path.isNotEmpty &&
                                        File(path).existsSync();

                                    return ListTile(
                                      selected: selected,
                                      leading: CircleAvatar(
                                        backgroundImage: hasPhoto
                                            ? FileImage(File(path))
                                            : null,
                                        child: hasPhoto
                                            ? null
                                            : const Icon(Icons.person_outline),
                                      ),
                                      title: Text(
                                        person.displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          if (person.lifeSpan.isNotEmpty)
                                            person.lifeSpan,
                                          if (person.birthPlace.isNotEmpty)
                                            person.birthPlace,
                                        ].join(' • '),
                                      ),
                                      trailing: selected
                                          ? const Icon(Icons.check_circle)
                                          : null,
                                      onTap: () => setState(
                                        () => _rootPersonId = personId,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 4,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          'Branch Settings',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        if (selectedRoot == null)
                          const Text(
                            'Select a starting person from the Family Tree.',
                          )
                        else
                          Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.person_pin_circle_outlined,
                              ),
                              title: Text(selectedRoot.displayName),
                              subtitle: const Text('Starting person'),
                            ),
                          ),
                        const SizedBox(height: 20),
                        const Text(
                          'Direction',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        ..._FamilyBranchDirection.values.map(
                          (direction) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(direction.icon),
                            title: Text(direction.label),
                            subtitle: Text(direction.description),
                            trailing: Icon(
                              _direction == direction
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                            ),
                            onTap: () => setState(() => _direction = direction),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Generation depth',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '$_generationDepth',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _generationDepth.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          label: '$_generationDepth',
                          onChanged: (value) =>
                              setState(() => _generationDepth = value.round()),
                        ),
                        Text(
                          _generationDepth == 1
                              ? 'Follow 1 generation from the starting person.'
                              : 'Follow $_generationDepth generations from the starting person.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'The starting person is always included in the book.',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _rootPersonId == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            _FamilyBranchSelectionResult(
                              rootPersonId: _rootPersonId!,
                              direction: _direction,
                              generationDepth: _generationDepth,
                            ),
                          ),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Use This Branch'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedPeoplePanel extends StatelessWidget {
  final bool loading;
  final List<FamilyPerson> people;
  final VoidCallback onChoosePeople;
  final String emptyMessage;
  final String actionLabel;
  final String editLabel;

  const _SelectedPeoplePanel({
    required this.loading,
    required this.people,
    required this.onChoosePeople,
    this.emptyMessage = 'No people have been added to this book yet.',
    this.actionLabel = 'Choose People',
    this.editLabel = 'Edit',
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (people.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              const Icon(Icons.people_outline, size: 34),
              const SizedBox(width: 16),
              Expanded(child: Text(emptyMessage)),
              FilledButton(onPressed: onChoosePeople, child: Text(actionLabel)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${people.length} '
                    '${people.length == 1 ? 'Person' : 'People'} in This Book',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onChoosePeople,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(editLabel),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...people.map((person) {
              final path = person.profilePhotoPath;
              final hasPhoto = path.isNotEmpty && File(path).existsSync();

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: hasPhoto ? FileImage(File(path)) : null,
                  child: hasPhoto ? null : const Icon(Icons.person_outline),
                ),
                title: Text(
                  person.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (person.lifeSpan.isNotEmpty) person.lifeSpan,
                    if (person.birthPlace.isNotEmpty) person.birthPlace,
                  ].join(' • '),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _AtlasGatherItem {
  final String type;
  final String key;
  final String title;
  final String subtitle;
  final String imagePath;
  final String body;
  const _AtlasGatherItem({
    required this.type,
    required this.key,
    required this.title,
    this.subtitle = '',
    this.imagePath = '',
    this.body = '',
  });
}

class _GatherMaterialPanel extends StatelessWidget {
  final bool loading;
  final List<String> photoPaths;
  final List<_AtlasGatherItem> stories;
  final List<_AtlasGatherItem> documents;
  final List<_AtlasGatherItem> collectibles;
  final Set<String> selectedPhotoPaths, selectedStoryKeys, selectedDocumentKeys, selectedCollectibleKeys;
  final Set<String> favoritePhotoPaths, favoriteStoryKeys, favoriteDocumentKeys, favoriteCollectibleKeys;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final void Function(String type, String key, bool selected) onSelectionChanged;
  final void Function(String type, String key, bool favorite) onFavoriteChanged;
  final VoidCallback onSave;
  const _GatherMaterialPanel({required this.loading, required this.photoPaths, required this.stories, required this.documents, required this.collectibles, required this.selectedPhotoPaths, required this.selectedStoryKeys, required this.selectedDocumentKeys, required this.selectedCollectibleKeys, required this.favoritePhotoPaths, required this.favoriteStoryKeys, required this.favoriteDocumentKeys, required this.favoriteCollectibleKeys, required this.filter, required this.onFilterChanged, required this.onSelectionChanged, required this.onFavoriteChanged, required this.onSave});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
    // The normal material views stay scoped to the people selected for this
    // book. Favorites is different: photo favorites are global Atlas Book
    // favorites, so include every starred photo that still exists on disk.
    final photoSourcePaths = filter == 'Favorites'
        ? <String>{
            ...photoPaths,
            ...favoritePhotoPaths.where((path) =>
                path.trim().isNotEmpty && File(path).existsSync()),
          }.toList()
        : photoPaths;

    final all = <_AtlasGatherItem>[
      ...photoSourcePaths.map((p) => _AtlasGatherItem(type: 'photo', key: p, title: File(p).uri.pathSegments.isEmpty ? p : File(p).uri.pathSegments.last)),
      ...stories, ...documents, ...collectibles,
    ];
    bool favorite(_AtlasGatherItem i) => i.type == 'photo'
        ? favoritePhotoPaths.contains(i.key)
        : i.type == 'story'
            ? favoriteStoryKeys.contains(i.key)
            : i.type == 'document'
                ? favoriteDocumentKeys.contains(i.key)
                : favoriteCollectibleKeys.contains(i.key);
    bool selected(_AtlasGatherItem i) => i.type == 'photo'
        ? selectedPhotoPaths.contains(i.key)
        : i.type == 'story'
            ? selectedStoryKeys.contains(i.key)
            : i.type == 'document'
                ? selectedDocumentKeys.contains(i.key)
                : selectedCollectibleKeys.contains(i.key);
    final visible = all.where((i) => switch(filter) { 'Favorites' => favorite(i), 'Photos' => i.type == 'photo', 'Stories' => i.type == 'story', 'Documents' => i.type == 'document', 'Collectibles' => i.type == 'collectible', _ => true }).toList()
      ..sort((a,b) { final f=(favorite(b)?1:0).compareTo(favorite(a)?1:0); return f != 0 ? f : a.title.toLowerCase().compareTo(b.title.toLowerCase()); });
    final selectedCount = all.where(selected).length;
    final favoriteCount = all.where(favorite).length;
    final filters = ['All','Favorites','Photos','Stories','Documents','Collectibles'];
    return Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children:[Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text('Gather Material', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height:4), Text('$selectedCount selected • $favoriteCount Atlas favorites • ${all.length} connected items', style: AtlasBookTheme.subtitle(context))])), if(all.isNotEmpty) FilledButton.icon(onPressed:onSave, icon:const Icon(Icons.bookmark_add_outlined), label:const Text('Save Selected Material'))]),
      const SizedBox(height:10), const Text('Connected items are suggestions. Select only what belongs in this book. A star marks an Atlas Favorite globally; the checkbox selects it only for this book.'),
      const SizedBox(height:16), Wrap(spacing:8, runSpacing:8, children:filters.map((v)=>FilterChip(selected:filter==v,label:Text(v),avatar:v=='Favorites'?const Icon(Icons.star_outline,size:18):null,onSelected:(_)=>onFilterChanged(v))).toList()), const SizedBox(height:16),
      if(visible.isEmpty) Text(filter=='Favorites' ? 'No Atlas favorites found yet.' : 'No connected ${filter == 'All' ? 'material' : filter.toLowerCase()} found for these people.')
      else GridView.builder(shrinkWrap:true, physics:const NeverScrollableScrollPhysics(), gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:4,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:.92), itemCount:visible.length, itemBuilder:(context,index){
        final item=visible[index], isSelected=selected(item), isFavorite=favorite(item);
        return Card(clipBehavior:Clip.antiAlias, child:InkWell(onTap:()=>onSelectionChanged(item.type,item.key,!isSelected), child:Stack(fit:StackFit.expand, children:[
          if(item.type=='photo')
            Image.file(File(item.key),fit:BoxFit.cover,errorBuilder:(_,_,_)=>const Center(child:Icon(Icons.broken_image_outlined)))
          else if(item.imagePath.isNotEmpty && File(item.imagePath).existsSync())
            Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(item.imagePath), fit: BoxFit.cover),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: .88),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (item.subtitle.isNotEmpty)
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else Container(padding:const EdgeInsets.fromLTRB(14,48,14,14), child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[Icon(item.type=='story'?Icons.auto_stories_outlined:item.type=='collectible'?Icons.inventory_2_outlined:Icons.description_outlined,size:42),const SizedBox(height:10),Text(item.title,maxLines:3,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w700)),if(item.subtitle.isNotEmpty)...[const SizedBox(height:6),Text(item.subtitle,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodySmall)]])),
          Positioned(top:8,left:8,child:Material(color:Theme.of(context).colorScheme.surface,shape:const CircleBorder(),elevation:2,child:IconButton(tooltip:isFavorite?'Remove Atlas favorite':'Favorite for Atlas Book',visualDensity:VisualDensity.compact,icon:Icon(isFavorite?Icons.star:Icons.star_outline),onPressed:()=>onFavoriteChanged(item.type,item.key,!isFavorite)))),
          Positioned(top:8,right:8,child:Material(color:Theme.of(context).colorScheme.surface,shape:const CircleBorder(),elevation:2,child:Checkbox(value:isSelected,onChanged:(v)=>onSelectionChanged(item.type,item.key,v??false)))),
          if(isSelected) Positioned.fill(child:IgnorePointer(child:DecoratedBox(decoration:BoxDecoration(border:Border.all(color:Theme.of(context).colorScheme.primary,width:4)))))
        ])));
      })
    ])));
  }
}

class _CoverPageResult {
  final String title;
  final String subtitle;
  final String? photoPath;
  const _CoverPageResult({required this.title, required this.subtitle, this.photoPath});
}

class _CoverPageDialog extends StatefulWidget {
  final String initialTitle;
  final String initialSubtitle;
  final String initialPhotoPath;
  final List<String> photoPaths;
  const _CoverPageDialog({
    required this.initialTitle,
    required this.initialSubtitle,
    required this.photoPaths,
    this.initialPhotoPath = '',
  });
  @override
  State<_CoverPageDialog> createState() => _CoverPageDialogState();
}

class _CoverPageDialogState extends State<_CoverPageDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  String? _photoPath;
  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _subtitleController = TextEditingController(text: widget.initialSubtitle);
    _photoPath = widget.initialPhotoPath.isEmpty ? null : widget.initialPhotoPath;
  }
  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cover / Title Page'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Book title')),
              const SizedBox(height: 12),
              TextField(controller: _subtitleController, decoration: const InputDecoration(labelText: 'Subtitle (optional)')),
              if (widget.photoPaths.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Cover photo (optional)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.photoPaths.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final path = widget.photoPaths[index];
                      final selected = path == _photoPath;
                      return InkWell(
                        onTap: () => setState(() => _photoPath = selected ? null : path),
                        child: Container(
                          width: 110,
                          decoration: BoxDecoration(
                            border: Border.all(color: selected ? const Color(0xFFC9A65A) : Colors.transparent, width: 3),
                          ),
                          child: Image.file(File(path), fit: BoxFit.cover),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(context, _CoverPageResult(title: title, subtitle: _subtitleController.text.trim(), photoPath: _photoPath));
          },
          child: const Text('Save Page'),
        ),
      ],
    );
  }
}

class _CoverPagePreview extends StatelessWidget {
  final AtlasBookPage page;
  const _CoverPagePreview({required this.page});
  @override
  Widget build(BuildContext context) {
    final hasPhoto = page.heroPhotoPath.isNotEmpty && File(page.heroPhotoPath).existsSync();
    return Container(
      decoration: AtlasBookTheme.pageDecoration,
      padding: const EdgeInsets.all(54),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasPhoto) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 360),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFF8A6A2F), width: 2)),
              child: Image.file(File(page.heroPhotoPath), fit: BoxFit.contain),
            ),
            const SizedBox(height: 36),
          ],
          Text(
            page.collageTitle.isEmpty ? 'Atlas Book' : page.collageTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Color(0xFF3B2D1C)),
          ),
          if (page.collageSubtitle.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(page.collageSubtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontStyle: FontStyle.italic, color: Color(0xFF6A5131))),
          ],
          const SizedBox(height: 28),
          Container(width: 120, height: 1, color: const Color(0xFFB08A45)),
          const SizedBox(height: 12),
          const Text('HEIRLOOM ATLAS', style: TextStyle(letterSpacing: 3, fontSize: 11, color: Color(0xFF8A6A2F))),
        ],
      ),
    );
  }
}

class _SavedCoverPagePreviewDialog extends StatelessWidget {
  final AtlasBookPage page;
  const _SavedCoverPagePreviewDialog({required this.page});
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(width: 900, height: 760, child: _CoverPagePreview(page: page)),
    );
  }
}

class _AddPageTypeDialog extends StatelessWidget {
  const _AddPageTypeDialog();

  @override
  Widget build(BuildContext context) {
    const templates = <_PageTemplateChoice>[
      _PageTemplateChoice(
        value: 'cover_page',
        title: 'Cover / Title Page',
        description: 'Create the opening page with a title, subtitle, and optional family photo.',
        icon: Icons.auto_stories_outlined,
        available: true,
      ),
      _PageTemplateChoice(
        value: 'person_profile',
        title: 'Person Profile',
        description: 'Featured person, portrait, dates, birthplace, and biography.',
        icon: Icons.person_outline,
        available: true,
      ),
      _PageTemplateChoice(
        value: 'family_group_sheet',
        title: 'Family Group Sheet',
        description: 'Couple, parents, children, and core family details.',
        icon: Icons.family_restroom_outlined,
        available: true,
      ),
      _PageTemplateChoice(
        value: 'ancestry_fan_chart',
        title: 'Ancestry Fan Chart',
        description: 'A visual ancestry chart generated from your Family Tree.',
        icon: Icons.hub_outlined,
        available: true,
      ),
      _PageTemplateChoice(
        value: 'collage',
        title: 'Photo Collage',
        description: 'Arrange several saved photos into a heritage album page.',
        icon: Icons.grid_view_outlined,
        available: true,
      ),
      _PageTemplateChoice(
        value: 'photo_story',
        title: 'Photo Story',
        description: 'Photos with captions and a short family narrative.',
        icon: Icons.photo_library_outlined,
        available: false,
      ),
      _PageTemplateChoice(
        value: 'timeline',
        title: 'Timeline',
        description: 'Chronological family events and milestones.',
        icon: Icons.timeline_outlined,
        available: false,
      ),
      _PageTemplateChoice(
        value: 'heirloom_spotlight',
        title: 'Heirloom Spotlight',
        description: 'Feature a keepsake, its history, and the people connected to it.',
        icon: Icons.inventory_2_outlined,
        available: false,
      ),
    ];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.library_books_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a Book Page',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Choose a page template. Every page stays editable after you add it.',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: templates.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: template.available
                          ? () => Navigator.pop(context, template.value)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: template.available
                              ? const Color(0xFF0B2742).withValues(alpha: 0.54)
                              : Colors.black.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: template.available
                                ? const Color(0xFFC9A65A).withValues(alpha: 0.40)
                                : Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 23,
                              child: Icon(template.icon),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          template.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      if (!template.available)
                                        const Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text('Coming later'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    template.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

class _PageTemplateChoice {
  final String value;
  final String title;
  final String description;
  final IconData icon;
  final bool available;

  const _PageTemplateChoice({
    required this.value,
    required this.title,
    required this.description,
    required this.icon,
    required this.available,
  });
}

class _BookPagesPanel extends StatelessWidget {
  final bool loading;
  final List<AtlasBookPage> pages;
  final List<FamilyPerson> people;
  final VoidCallback onAddPage;
  final ValueChanged<AtlasBookPage> onPreview;
  final ValueChanged<AtlasBookPage> onEdit;
  final ValueChanged<AtlasBookPage> onDelete;
  final ValueChanged<int> onMoveUp;
  final ValueChanged<int> onMoveDown;

  const _BookPagesPanel({
    required this.loading,
    required this.pages,
    required this.people,
    required this.onAddPage,
    required this.onPreview,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  FamilyPerson? _personFor(int? id) {
    if (id == null) return null;
    for (final person in people) {
      if (person.id == id) return person;
    }
    return null;
  }

  int _collagePhotoCount(AtlasBookPage page) {
    try {
      final decoded = jsonDecode(page.collagePhotoPathsJson);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (pages.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, size: 36),
              const SizedBox(width: 16),
              const Expanded(
                child: Text('No pages yet. Start with a Person Profile.'),
              ),
              FilledButton.icon(
                onPressed: onAddPage,
                icon: const Icon(Icons.add),
                label: const Text('Add First Page'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${pages.length} ${pages.length == 1 ? 'Page' : 'Pages'} in This Book',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onAddPage,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Page'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(pages.length, (index) {
              final page = pages[index];
              final person = _personFor(page.personId);
              final isCover = page.pageType == 'cover_page';
              final isFanChart = page.pageType == 'ancestry_fan_chart';
              final isFamilyGroup = page.pageType == 'family_group_sheet';
              final isCollage = page.pageType == 'collage';
              final isStory = page.pageType == 'story_page';
              final isDocument = page.pageType == 'document_page';
              final isHeirloom = page.pageType == 'heirloom_feature';

              return Card(
                child: ListTile(
                  onTap: () => onPreview(page),
                  leading: SizedBox(
                    width: 58,
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFC9A65A)
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Icon(
                          isCover
                              ? Icons.auto_stories_outlined
                              : isFanChart
                              ? Icons.hub_outlined
                              : isFamilyGroup
                              ? Icons.family_restroom_outlined
                              : isCollage
                              ? Icons.grid_view_outlined
                              : isStory
                              ? Icons.auto_stories_outlined
                              : isHeirloom
                              ? Icons.museum_outlined
                              : Icons.description_outlined,
                          size: 21,
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    isCover
                        ? (page.collageTitle.isEmpty ? 'Cover / Title Page' : page.collageTitle)
                        : isCollage
                        ? 'Photo Collage'
                        : isStory || isDocument || isHeirloom
                        ? (page.collageTitle.isEmpty
                            ? (isStory
                                ? 'Story Page'
                                : isDocument
                                    ? 'Document Page'
                                    : 'Heirloom Feature')
                            : page.collageTitle)
                        : person?.displayName ??
                              (isFanChart
                                  ? 'Ancestry Fan Chart'
                                  : isFamilyGroup
                                  ? 'Family Group Sheet'
                                  : 'Person Profile'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    isCover
                        ? 'Cover / Title Page'
                        : isCollage
                        ? 'Collage • ${_collagePhotoCount(page)} photos'
                        : isStory
                        ? 'Story Page'
                        : isDocument
                        ? 'Document / Archive Page'
                        : isHeirloom
                        ? 'Heirloom / Collection Feature'
                        : isFanChart
                        ? 'Ancestry Fan Chart • ${page.generationCount} generations'
                        : isFamilyGroup
                        ? 'Family Group Sheet'
                        : 'Person Profile',
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Move page up',
                        onPressed: index == 0 ? null : () => onMoveUp(index),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Move page down',
                        onPressed: index == pages.length - 1
                            ? null
                            : () => onMoveDown(index),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: 'Edit page',
                        onPressed: () => onEdit(page),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Remove page',
                        onPressed: () => onDelete(page),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _HeritageDivider extends StatelessWidget {
  const _HeritageDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: AtlasBookTheme.antiqueGoldSoft, thickness: 1),
        ),
        const SizedBox(width: 12),
        Icon(
          Icons.local_florist_outlined,
          size: 18,
          color: AtlasBookTheme.antiqueGold.withValues(alpha: 0.50),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Divider(color: AtlasBookTheme.antiqueGoldSoft, thickness: 1),
        ),
      ],
    );
  }
}

class _FanChartPageResult {
  final int personId;
  final int generationCount;

  const _FanChartPageResult({
    required this.personId,
    required this.generationCount,
  });
}

class _FanAncestorNode {
  final FamilyPerson person;
  final int generation;
  final int slot;

  const _FanAncestorNode({
    required this.person,
    required this.generation,
    required this.slot,
  });
}

class _FanChartSetupDialog extends StatefulWidget {
  final List<FamilyPerson> people;
  final DatabaseHelper databaseHelper;
  final int? initialPersonId;
  final int? initialGenerationCount;
  final bool isEditing;

  const _FanChartSetupDialog({
    required this.people,
    required this.databaseHelper,
    this.initialPersonId,
    this.initialGenerationCount,
    this.isEditing = false,
  });

  @override
  State<_FanChartSetupDialog> createState() => _FanChartSetupDialogState();
}

class _FanChartSetupDialogState extends State<_FanChartSetupDialog> {
  late FamilyPerson _rootPerson;
  int _generationCount = 4;
  List<_FanAncestorNode> _nodes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _rootPerson = widget.people.firstWhere(
      (person) => person.id == widget.initialPersonId,
      orElse: () => widget.people.first,
    );
    _generationCount = widget.initialGenerationCount ?? 4;
    _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final rootId = _rootPerson.id;
    if (rootId == null) return;

    setState(() => _loading = true);

    final nodes = <_FanAncestorNode>[];
    final visited = <int>{};

    Future<void> walk(int personId, int generation, int slot) async {
      if (generation >= _generationCount) return;
      if (!visited.add(personId)) return;

      final person = await widget.databaseHelper.getFamilyPerson(personId);
      if (person == null) return;

      nodes.add(
        _FanAncestorNode(person: person, generation: generation, slot: slot),
      );

      if (generation + 1 >= _generationCount) return;

      final parents = await widget.databaseHelper.getFamilyParents(personId);

      for (final parent in parents) {
        final parentId = parent.id;
        if (parentId == null) continue;

        final role = await widget.databaseHelper.getFamilyParentRole(
          parentId: parentId,
          childId: personId,
        );

        final lowerRole = role.toLowerCase();
        final parentSlot = lowerRole.contains('mother')
            ? (slot * 2) + 1
            : slot * 2;

        await walk(parentId, generation + 1, parentSlot);
      }
    }

    await walk(rootId, 0, 0);

    if (!mounted) return;

    setState(() {
      _nodes = nodes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isEditing ? 'Edit Ancestry Fan Chart' : 'Add Ancestry Fan Chart',
      ),
      content: SizedBox(
        width: 980,
        height: 720,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 270,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Starting person',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _rootPerson.id,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: widget.people
                        .where((person) => person.id != null)
                        .map(
                          (person) => DropdownMenuItem<int>(
                            value: person.id!,
                            child: Text(person.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (id) async {
                      if (id == null) return;

                      setState(() {
                        _rootPerson = widget.people.firstWhere(
                          (person) => person.id == id,
                        );
                      });

                      await _refreshPreview();
                    },
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Generations',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _generationCount,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [3, 4, 5]
                        .map(
                          (value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value generations'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;

                      setState(() {
                        _generationCount = value;
                      });

                      await _refreshPreview();
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${_nodes.length} known people will appear on this chart.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Blank branches remain open when an ancestor is not yet '
                    'in your Family Tree.',
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 32),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _FanChartPagePreview(
                      nodes: _nodes,
                      generationCount: _generationCount,
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _rootPerson.id == null
              ? null
              : () => Navigator.pop(
                  context,
                  _FanChartPageResult(
                    personId: _rootPerson.id!,
                    generationCount: _generationCount,
                  ),
                ),
          icon: const Icon(Icons.add),
          label: Text(widget.isEditing ? 'Save Changes' : 'Add Fan Chart'),
        ),
      ],
    );
  }
}

class _SavedFanChartPreviewDialog extends StatelessWidget {
  final List<_FanAncestorNode> nodes;
  final int generationCount;

  const _SavedFanChartPreviewDialog({
    required this.nodes,
    required this.generationCount,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ancestry Fan Chart Preview'),
      content: SizedBox(
        width: 900,
        height: 680,
        child: _FanChartPagePreview(
          nodes: nodes,
          generationCount: generationCount,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _FanChartPagePreview extends StatelessWidget {
  final List<_FanAncestorNode> nodes;
  final int generationCount;

  const _FanChartPagePreview({
    required this.nodes,
    required this.generationCount,
  });

  @override
  Widget build(BuildContext context) {
    FamilyPerson? root;

    for (final node in nodes) {
      if (node.generation == 0) {
        root = node.person;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
      decoration: AtlasBookTheme.pageDecoration,

      child: Column(
        children: [
          Text(
            root == null
                ? 'Ancestry Fan Chart'
                : '${root.displayName} — Ancestry',
            textAlign: TextAlign.center,
            style: AtlasBookTheme.displayTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            '$generationCount generations',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 70),
            child: _HeritageDivider(),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _FanChartPainter(
                    nodes: nodes,
                    generationCount: generationCount,
                    textColor: AtlasBookTheme.espresso,
                    lineColor: AtlasBookTheme.antiqueGoldSoft,
                    accentColor: AtlasBookTheme.antiqueGold,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FanChartPainter extends CustomPainter {
  final List<_FanAncestorNode> nodes;
  final int generationCount;
  final Color textColor;
  final Color lineColor;
  final Color accentColor;

  const _FanChartPainter({
    required this.nodes,
    required this.generationCount,
    required this.textColor,
    required this.lineColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height - 24);
    final maxRadius = math.min(size.width * 0.47, size.height - 34);
    final ringWidth = maxRadius / generationCount;

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var generation = 1; generation <= generationCount; generation++) {
      final radius = ringWidth * generation;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi,
        math.pi,
        false,
        linePaint,
      );
    }

    for (var generation = 1; generation < generationCount; generation++) {
      final slots = 1 << generation;

      for (var i = 0; i <= slots; i++) {
        final angle = math.pi + (math.pi * i / slots);
        final startRadius = ringWidth * generation;
        final endRadius = ringWidth * generationCount;

        canvas.drawLine(
          Offset(
            center.dx + math.cos(angle) * startRadius,
            center.dy + math.sin(angle) * startRadius,
          ),
          Offset(
            center.dx + math.cos(angle) * endRadius,
            center.dy + math.sin(angle) * endRadius,
          ),
          linePaint,
        );
      }
    }

    for (final node in nodes) {
      if (node.generation == 0) {
        _drawRoot(canvas, center, ringWidth, node.person);
        continue;
      }

      final slotCount = 1 << node.generation;
      final startAngle = math.pi + math.pi * node.slot / slotCount;
      final endAngle = math.pi + math.pi * (node.slot + 1) / slotCount;
      final midAngle = (startAngle + endAngle) / 2;
      final innerRadius = ringWidth * node.generation;
      final outerRadius = ringWidth * (node.generation + 1);
      final textRadius = (innerRadius + outerRadius) / 2;

      final point = Offset(
        center.dx + math.cos(midAngle) * textRadius,
        center.dy + math.sin(midAngle) * textRadius,
      );

      _paintText(
        canvas,
        node.person.displayName,
        point,
        math.max(42.0, ringWidth * 1.7),
        fontSize: node.generation >= 4 ? 7.5 : 9.2,
        fontWeight: FontWeight.w700,
      );

      if (node.person.lifeSpan.isNotEmpty && node.generation <= 3) {
        _paintText(
          canvas,
          node.person.lifeSpan,
          Offset(point.dx, point.dy + 15),
          math.max(42.0, ringWidth * 1.7),
          fontSize: 7.2,
          maxLines: 1,
        );
      }
    }
  }

  void _drawRoot(
    Canvas canvas,
    Offset center,
    double ringWidth,
    FamilyPerson person,
  ) {
    final rect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - ringWidth * 0.48),
      width: ringWidth * 1.6,
      height: ringWidth * 0.76,
    );

    final fillPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    _paintText(
      canvas,
      person.displayName,
      rect.center,
      rect.width - 12,
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
    );

    if (person.lifeSpan.isNotEmpty) {
      _paintText(
        canvas,
        person.lifeSpan,
        Offset(rect.center.dx, rect.center.dy + 18),
        rect.width - 12,
        fontSize: 9,
        maxLines: 1,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset center,
    double maxWidth, {
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    int maxLines = 2,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: maxLines,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _FanChartPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.generationCount != generationCount ||
        oldDelegate.textColor != textColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _BookPreviewPageData {
  final AtlasBookPage page;
  final FamilyPerson? person;
  final List<_FanAncestorNode>? fanNodes;
  final _FamilyGroupSheetData? familyGroupData;
  final List<String>? collagePhotoPaths;

  const _BookPreviewPageData({
    required this.page,
    this.person,
    this.fanNodes,
    this.familyGroupData,
    this.collagePhotoPaths,
  });
}


class _MaterialPageEditResult {
  final String title;
  final String subtitle;
  final String body;
  final String designKey;
  final String paperKey;
  const _MaterialPageEditResult({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.designKey,
    required this.paperKey,
  });
}

class _MaterialPageEditDialog extends StatefulWidget {
  final String initialTitle;
  final String initialSubtitle;
  final String initialBody;
  final String initialDesignKey;
  final String initialPaperKey;
  const _MaterialPageEditDialog({
    required this.initialTitle,
    required this.initialSubtitle,
    required this.initialBody,
    this.initialDesignKey = 'classic',
    this.initialPaperKey = 'ivory',
  });

  @override
  State<_MaterialPageEditDialog> createState() => _MaterialPageEditDialogState();
}

class _MaterialPageEditDialogState extends State<_MaterialPageEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _bodyController;
  late String _designKey;
  late String _paperKey;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _subtitleController = TextEditingController(text: widget.initialSubtitle);
    _bodyController = TextEditingController(text: widget.initialBody);
    _designKey = widget.initialDesignKey;
    _paperKey = widget.initialPaperKey;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Book Page'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Page title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subtitleController,
                decoration: const InputDecoration(labelText: 'Subtitle'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Page text / caption',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Page Design',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    ('classic', 'Classic'),
                    ('feature', 'Photo Feature'),
                    ('narrative', 'Narrative'),
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: _designKey == option.$1,
                      onSelected: (_) => setState(() => _designKey = option.$1),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Paper',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    ('ivory', 'Warm Ivory'),
                    ('parchment', 'Parchment'),
                    ('clean', 'Clean'),
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: _paperKey == option.$1,
                      onSelected: (_) => setState(() => _paperKey = option.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _MaterialPageEditResult(
              title: _titleController.text.trim(),
              subtitle: _subtitleController.text.trim(),
              body: _bodyController.text.trim(),
              designKey: _designKey,
              paperKey: _paperKey,
            ),
          ),
          child: const Text('Save Page'),
        ),
      ],
    );
  }
}

class _SavedMaterialPagePreviewDialog extends StatelessWidget {
  final AtlasBookPage page;
  const _SavedMaterialPagePreviewDialog({required this.page});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 900,
        height: 720,
        child: _MaterialPagePreview(page: page),
      ),
    );
  }
}

class _MaterialPagePreview extends StatelessWidget {
  final AtlasBookPage page;
  const _MaterialPagePreview({required this.page});

  Map<String, dynamic> _metadata() {
    try {
      final data = jsonDecode(page.collagePhotoLayoutJson);
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return {};
  }

  String _kindLabel() {
    if (page.pageType == 'story_page') return 'FAMILY STORY';
    if (page.pageType == 'document_page') return 'ARCHIVE DOCUMENT';
    return 'HEIRLOOM FEATURE';
  }

  IconData _kindIcon() {
    if (page.pageType == 'story_page') return Icons.auto_stories_outlined;
    if (page.pageType == 'document_page') return Icons.description_outlined;
    return Icons.museum_outlined;
  }

  Color _paperColor(String paperKey) {
    switch (paperKey) {
      case 'parchment':
        return const Color(0xFFF1E3BF);
      case 'clean':
        return const Color(0xFFF9F7F2);
      default:
        return const Color(0xFFF5EEDC);
    }
  }

  Widget _textBlock(String body) {
    return SingleChildScrollView(
      child: Text(
        body.isEmpty
            ? (page.pageType == 'document_page'
                ? 'This archival document is preserved as part of the family record.'
                : 'Add text to tell the story behind this material.')
            : body,
        style: const TextStyle(
          height: 1.6,
          fontSize: 17,
          color: Color(0xFF3D382F),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata();
    final body = (metadata['body']?.toString() ?? '').trim();
    final designKey = metadata['designKey']?.toString() ?? 'classic';
    final paperKey = metadata['paperKey']?.toString() ?? 'ivory';
    final imagePath = page.heroPhotoPath.trim();
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_kindIcon(), size: 22, color: const Color(0xFF8B6B2E)),
            const SizedBox(width: 10),
            Text(
              _kindLabel(),
              style: const TextStyle(
                letterSpacing: 2.0,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8B6B2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          page.collageTitle.isEmpty ? 'Untitled Page' : page.collageTitle,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2D2A24),
          ),
        ),
        if (page.collageSubtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            page.collageSubtitle,
            style: const TextStyle(
              fontSize: 17,
              fontStyle: FontStyle.italic,
              color: Color(0xFF675B49),
            ),
          ),
        ],
      ],
    );

    Widget content;
    if (designKey == 'feature' && hasImage) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(File(imagePath), fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 22),
          Expanded(flex: 3, child: _textBlock(body)),
        ],
      );
    } else if (designKey == 'narrative') {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: _textBlock(body)),
          if (hasImage) ...[
            const SizedBox(width: 28),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ],
        ],
      );
    } else {
      content = hasImage
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                const SizedBox(width: 30),
                Expanded(flex: 4, child: _textBlock(body)),
              ],
            )
          : _textBlock(body);
    }

    return Container(
      decoration: BoxDecoration(
        color: _paperColor(paperKey),
        border: Border.all(color: const Color(0xFFC9A65A), width: 1.1),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 5),
            color: Color(0x22000000),
          ),
        ],
      ),
      padding: const EdgeInsets.all(42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 24),
          Container(height: 1, color: const Color(0xFFC9A65A)),
          const SizedBox(height: 28),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _WholeBookPreviewDialog extends StatefulWidget {
  final String bookTitle;
  final List<_BookPreviewPageData> pages;

  const _WholeBookPreviewDialog({required this.bookTitle, required this.pages});

  @override
  State<_WholeBookPreviewDialog> createState() =>
      _WholeBookPreviewDialogState();
}

class _WholeBookPreviewDialogState extends State<_WholeBookPreviewDialog> {
  int _pageIndex = 0;
  bool _spreadMode = true;

  bool get _coverIsFirst =>
      widget.pages.isNotEmpty && widget.pages.first.page.pageType == 'cover_page';

  List<int> _visibleIndices() {
    if (!_spreadMode) return [_pageIndex];

    if (_coverIsFirst && _pageIndex == 0) return [0];

    var left = _pageIndex;
    if (_coverIsFirst) {
      if (left < 1) left = 1;
      if ((left - 1).isOdd) left -= 1;
    } else if (left.isOdd) {
      left -= 1;
    }

    final result = <int>[left];
    if (left + 1 < widget.pages.length) result.add(left + 1);
    return result;
  }

  void _previousPage() {
    if (_pageIndex <= 0) return;
    if (!_spreadMode) {
      setState(() => _pageIndex--);
      return;
    }
    if (_coverIsFirst && _pageIndex <= 1) {
      setState(() => _pageIndex = 0);
      return;
    }
    setState(() => _pageIndex = (_pageIndex - 2).clamp(0, widget.pages.length - 1));
  }

  void _nextPage() {
    if (_pageIndex >= widget.pages.length - 1) return;
    if (!_spreadMode) {
      setState(() => _pageIndex++);
      return;
    }
    if (_coverIsFirst && _pageIndex == 0) {
      setState(() => _pageIndex = widget.pages.length > 1 ? 1 : 0);
      return;
    }
    setState(() => _pageIndex = (_pageIndex + 2).clamp(0, widget.pages.length - 1));
  }

  Widget _buildPage(_BookPreviewPageData data) {
    if (data.page.pageType == 'cover_page') {
      return _CoverPagePreview(page: data.page);
    }
    if (data.page.pageType == 'story_page' ||
        data.page.pageType == 'document_page' ||
        data.page.pageType == 'heirloom_feature') {
      return _MaterialPagePreview(page: data.page);
    }
    if (data.page.pageType == 'collage') {
      return _CollagePagePreview(
        photoPaths: data.collagePhotoPaths ?? const [],
        layoutKey: data.page.collageLayoutKey,
        layoutSeed: data.page.collageLayoutSeed,
        title: data.page.collageTitle,
        subtitle: data.page.collageSubtitle,
        photoLayoutJson: data.page.collagePhotoLayoutJson,
      );
    }
    if (data.page.pageType == 'ancestry_fan_chart') {
      return _FanChartPagePreview(
        nodes: data.fanNodes ?? const [],
        generationCount: data.page.generationCount,
      );
    }
    if (data.page.pageType == 'family_group_sheet' &&
        data.familyGroupData != null) {
      return _FamilyGroupSheetPreview(data: data.familyGroupData!);
    }
    if (data.person != null) {
      final profilePath = data.person!.profilePhotoPath;
      final heroPath = data.page.heroPhotoPath;
      final imagePath = heroPath.isNotEmpty && File(heroPath).existsSync()
          ? heroPath
          : profilePath.isNotEmpty && File(profilePath).existsSync()
              ? profilePath
              : null;
      return _PersonProfilePagePreview(person: data.person!, imagePath: imagePath);
    }
    return Container(
      decoration: AtlasBookTheme.pageDecoration,
      child: const Center(child: Text('This page could not be previewed.')),
    );
  }

  Widget _pageShell(int index) {
    return Column(
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: 8.5 / 11,
            child: _buildPage(widget.pages[index]),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Page ${index + 1}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleIndices();

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: SizedBox(
        width: 1460,
        height: 900,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 12, 14, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.menu_book_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.bookTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.description_outlined),
                        label: Text('Single Page'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.menu_book_outlined),
                        label: Text('Two-Page Spread'),
                      ),
                    ],
                    selected: {_spreadMode},
                    onSelectionChanged: (selection) {
                      setState(() => _spreadMode = selection.first);
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: visible.length == 1
                            ? ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 720,
                                  maxHeight: 700,
                                ),
                                child: _pageShell(visible.first),
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1200,
                                  maxHeight: 700,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(child: _pageShell(visible[0])),
                                    Container(
                                      width: 20,
                                      margin: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0x05000000),
                                            Color(0x25000000),
                                            Color(0x05000000),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(child: _pageShell(visible[1])),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: 106,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.pages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final selected = visible.contains(index);
                  return InkWell(
                    onTap: () => setState(() => _pageIndex = index),
                    child: Container(
                      width: 62,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFC9A65A)
                              : Theme.of(context).dividerColor,
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Icon(
                              widget.pages[index].page.pageType == 'cover_page'
                                  ? Icons.menu_book_outlined
                                  : widget.pages[index].page.pageType == 'story_page'
                                      ? Icons.auto_stories_outlined
                                      : widget.pages[index].page.pageType == 'heirloom_feature'
                                          ? Icons.museum_outlined
                                          : Icons.description_outlined,
                              size: 28,
                            ),
                          ),
                          Text(
                            '${index + 1}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
              child: Row(
                children: [
                  Text(
                    visible.length == 1
                        ? 'Page ${visible.first + 1} of ${widget.pages.length}'
                        : 'Pages ${visible.first + 1}–${visible.last + 1} of ${widget.pages.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _pageIndex == 0 ? null : _previousPage,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: visible.last >= widget.pages.length - 1
                        ? null
                        : _nextPage,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyGroupSheetResult {
  final int primaryPersonId;
  final int? spousePersonId;

  const _FamilyGroupSheetResult({
    required this.primaryPersonId,
    required this.spousePersonId,
  });
}

class _FamilyGroupSheetData {
  final FamilyPerson primary;
  final FamilyPerson? spouse;
  final List<FamilyPerson> primaryParents;
  final List<FamilyPerson> spouseParents;
  final List<FamilyPerson> children;

  const _FamilyGroupSheetData({
    required this.primary,
    required this.spouse,
    required this.primaryParents,
    required this.spouseParents,
    required this.children,
  });
}

class _FamilyGroupSheetSetupDialog extends StatefulWidget {
  final List<FamilyPerson> people;
  final DatabaseHelper databaseHelper;
  final int? initialPrimaryPersonId;
  final int? initialSpousePersonId;
  final bool isEditing;

  const _FamilyGroupSheetSetupDialog({
    required this.people,
    required this.databaseHelper,
    this.initialPrimaryPersonId,
    this.initialSpousePersonId,
    this.isEditing = false,
  });

  @override
  State<_FamilyGroupSheetSetupDialog> createState() =>
      _FamilyGroupSheetSetupDialogState();
}

class _FamilyGroupSheetSetupDialogState
    extends State<_FamilyGroupSheetSetupDialog> {
  late FamilyPerson _primary;
  List<FamilyPerson> _spouses = [];
  FamilyPerson? _spouse;
  _FamilyGroupSheetData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _primary = widget.people.firstWhere(
      (person) => person.id == widget.initialPrimaryPersonId,
      orElse: () => widget.people.first,
    );
    _refresh(initialSpousePersonId: widget.initialSpousePersonId);
  }

  Future<void> _refresh({int? initialSpousePersonId}) async {
    final primaryId = _primary.id;
    if (primaryId == null) return;

    setState(() => _loading = true);

    final spouses = await widget.databaseHelper.getFamilySpouses(primaryId);

    FamilyPerson? selectedSpouse = _spouse;

    if (initialSpousePersonId != null) {
      for (final person in spouses) {
        if (person.id == initialSpousePersonId) {
          selectedSpouse = person;
          break;
        }
      }
    }

    if (selectedSpouse == null ||
        !spouses.any((person) => person.id == selectedSpouse?.id)) {
      selectedSpouse = spouses.isEmpty ? null : spouses.first;
    }

    final primaryParents = await widget.databaseHelper.getFamilyParents(
      primaryId,
    );

    final spouseId = selectedSpouse?.id;

    final spouseParents = spouseId == null
        ? <FamilyPerson>[]
        : await widget.databaseHelper.getFamilyParents(spouseId);

    final primaryChildren = await widget.databaseHelper.getFamilyChildren(
      primaryId,
    );

    final children = <FamilyPerson>[];

    if (spouseId == null) {
      children.addAll(primaryChildren);
    } else {
      for (final child in primaryChildren) {
        final childId = child.id;
        if (childId == null) continue;

        final parents = await widget.databaseHelper.getFamilyParents(childId);

        if (parents.any((parent) => parent.id == spouseId)) {
          children.add(child);
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _spouses = spouses;
      _spouse = selectedSpouse;
      _data = _FamilyGroupSheetData(
        primary: _primary,
        spouse: selectedSpouse,
        primaryParents: primaryParents,
        spouseParents: spouseParents,
        children: children,
      );
      _loading = false;
    });
  }

  Future<void> _changeSpouse(int? spouseId) async {
    setState(() {
      _spouse = spouseId == null
          ? null
          : _spouses.firstWhere((person) => person.id == spouseId);
    });

    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isEditing ? 'Edit Family Group Sheet' : 'Add Family Group Sheet',
      ),
      content: SizedBox(
        width: 1040,
        height: 720,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 285,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Primary person',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _primary.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: widget.people
                        .where((person) => person.id != null)
                        .map(
                          (person) => DropdownMenuItem<int>(
                            value: person.id!,
                            child: Text(
                              person.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (id) async {
                      if (id == null) return;

                      setState(() {
                        _primary = widget.people.firstWhere(
                          (person) => person.id == id,
                        );
                        _spouse = null;
                      });

                      await _refresh();
                    },
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Spouse',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    initialValue: _spouse?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('No spouse'),
                      ),
                      ..._spouses
                          .where((person) => person.id != null)
                          .map(
                            (person) => DropdownMenuItem<int?>(
                              value: person.id,
                              child: Text(
                                person.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    onChanged: _changeSpouse,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'This page pulls the couple, their parents, and shared '
                    'children directly from your Family Tree.',
                  ),
                  const SizedBox(height: 12),
                  if (_data != null)
                    Text(
                      '${_data!.children.length} '
                      '${_data!.children.length == 1 ? 'child' : 'children'} found',
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 32),
            Expanded(
              child: _loading || _data == null
                  ? const Center(child: CircularProgressIndicator())
                  : _FamilyGroupSheetPreview(data: _data!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _primary.id == null
              ? null
              : () => Navigator.pop(
                  context,
                  _FamilyGroupSheetResult(
                    primaryPersonId: _primary.id!,
                    spousePersonId: _spouse?.id,
                  ),
                ),
          icon: const Icon(Icons.add),
          label: Text(
            widget.isEditing ? 'Save Changes' : 'Add Family Group Sheet',
          ),
        ),
      ],
    );
  }
}

class _SavedFamilyGroupSheetPreviewDialog extends StatelessWidget {
  final _FamilyGroupSheetData data;

  const _SavedFamilyGroupSheetPreviewDialog({required this.data});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Family Group Sheet Preview'),
      content: SizedBox(
        width: 920,
        height: 680,
        child: _FamilyGroupSheetPreview(data: data),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _FamilyGroupSheetPreview extends StatelessWidget {
  final _FamilyGroupSheetData data;

  const _FamilyGroupSheetPreview({required this.data});

  String _parentsText(List<FamilyPerson> parents) {
    if (parents.isEmpty) return 'Parents not recorded';

    return parents.map((person) => person.displayName).join('  •  ');
  }

  String _birthText(FamilyPerson person) {
    final value = [
      person.birthDate,
      person.birthPlace,
    ].where((item) => item.trim().isNotEmpty).join(' • ');

    return value.isEmpty ? 'Not recorded' : value;
  }

  Widget _portrait(BuildContext context, FamilyPerson person) {
    final path = person.profilePhotoPath.trim();
    final hasPhoto = path.isNotEmpty && File(path).existsSync();

    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AtlasBookTheme.antiqueGold, width: 1.4),
          ),
          child: ClipOval(
            child: hasPhoto
                ? Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    width: 96,
                    height: 96,
                    errorBuilder: (_, _, _) => Container(
                      color: AtlasBookTheme.ivoryLight,
                      child: const Icon(
                        Icons.person_outline,
                        size: 48,
                        color: AtlasBookTheme.warmBrown,
                      ),
                    ),
                  )
                : Container(
                    color: AtlasBookTheme.ivoryLight,
                    child: const Icon(
                      Icons.person_outline,
                      size: 48,
                      color: AtlasBookTheme.warmBrown,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          person.displayName,
          textAlign: TextAlign.center,
          style: AtlasBookTheme.sectionTitle(context),
        ),
        if (person.lifeSpan.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            person.lifeSpan,
            textAlign: TextAlign.center,
            style: AtlasBookTheme.subtitle(context).copyWith(fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _personDetails(
    BuildContext context,
    FamilyPerson person,
    List<FamilyPerson> parents,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AtlasBookTheme.ivoryLight.withValues(alpha: 0.42),
        border: Border.all(
          color: AtlasBookTheme.antiqueGoldSoft.withValues(alpha: 0.65),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            person.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AtlasBookTheme.sectionTitle(context).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 9),
          _personDetailLine(context, 'Birth', _birthText(person)),
          const SizedBox(height: 7),
          _personDetailLine(context, 'Parents', _parentsText(parents)),
        ],
      ),
    );
  }

  Widget _personDetailLine(BuildContext context, String label, String value) {
    return RichText(
      text: TextSpan(
        style: AtlasBookTheme.body(context).copyWith(fontSize: 12.5),
        children: [
          TextSpan(
            text: '$label: ',
            style: AtlasBookTheme.sectionTitle(
              context,
            ).copyWith(fontSize: 12.5),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spouse = data.spouse;

    return Container(
      padding: const EdgeInsets.fromLTRB(34, 26, 34, 28),
      decoration: AtlasBookTheme.pageDecoration,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Text(
              'Family Group Sheet',
              style: AtlasBookTheme.displayTitle(context),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 100),
              child: _HeritageDivider(),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _portrait(context, data.primary)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 36, 16, 0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.favorite_border,
                        color: AtlasBookTheme.antiqueGold,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        spouse == null ? '' : 'Family',
                        style: AtlasBookTheme.subtitle(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: spouse == null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: Text(
                            'No spouse selected',
                            textAlign: TextAlign.center,
                            style: AtlasBookTheme.subtitle(context),
                          ),
                        )
                      : _portrait(context, spouse),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _personDetails(
                    context,
                    data.primary,
                    data.primaryParents,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: spouse == null
                      ? Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AtlasBookTheme.antiqueGoldSoft.withValues(
                                alpha: 0.45,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'No spouse selected',
                            textAlign: TextAlign.center,
                            style: AtlasBookTheme.subtitle(context),
                          ),
                        )
                      : _personDetails(context, spouse, data.spouseParents),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Children',
                style: AtlasBookTheme.sectionTitle(
                  context,
                ).copyWith(fontSize: 20),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: AtlasBookTheme.antiqueGoldSoft),
            if (data.children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No children are currently linked to this family.',
                  style: AtlasBookTheme.body(context),
                ),
              )
            else
              ...List.generate(data.children.length, (index) {
                final child = data.children[index];

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${index + 1}.',
                          style: AtlasBookTheme.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          child.displayName,
                          style: AtlasBookTheme.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          [child.birthDate, child.birthPlace]
                              .where((value) => value.trim().isNotEmpty)
                              .join(' • '),
                          style: AtlasBookTheme.body(
                            context,
                          ).copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CollagePageResult {
  final List<String> photoPaths;
  final String layoutKey;
  final int layoutSeed;
  final String title;
  final String subtitle;
  final String photoLayoutJson;

  const _CollagePageResult({
    required this.photoPaths,
    required this.layoutKey,
    required this.layoutSeed,
    required this.title,
    required this.subtitle,
    required this.photoLayoutJson,
  });
}

class _CollagePageDialog extends StatefulWidget {
  final List<String> photoPaths;
  final List<String> initialSelectedPaths;
  final String initialLayoutKey;
  final int initialLayoutSeed;
  final String initialTitle;
  final String initialSubtitle;
  final String initialPhotoLayoutJson;
  final bool isEditing;

  const _CollagePageDialog({
    required this.photoPaths,
    this.initialSelectedPaths = const [],
    this.initialLayoutKey = 'balanced',
    this.initialLayoutSeed = 0,
    this.initialTitle = 'Family Memories',
    this.initialSubtitle = '',
    this.initialPhotoLayoutJson = '{}',
    this.isEditing = false,
  });

  @override
  State<_CollagePageDialog> createState() => _CollagePageDialogState();
}

class _CollagePageDialogState extends State<_CollagePageDialog> {
  late Set<String> _selectedPaths;
  late String _layoutKey;
  late int _layoutSeed;
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late Map<String, _ManualCollageTransform> _manualTransforms;

  @override
  void initState() {
    super.initState();

    _selectedPaths = widget.initialSelectedPaths.isNotEmpty
        ? widget.initialSelectedPaths.where(widget.photoPaths.contains).toSet()
        : widget.photoPaths.take(4).toSet();

    _layoutKey =
        const {
          'balanced',
          'featured',
          'filmstrip',
          'corkboard',
        }.contains(widget.initialLayoutKey)
        ? widget.initialLayoutKey
        : 'balanced';

    _layoutSeed = widget.initialLayoutSeed == 0
        ? DateTime.now().microsecondsSinceEpoch & 0x7fffffff
        : widget.initialLayoutSeed;

    _titleController = TextEditingController(text: widget.initialTitle);
    _subtitleController = TextEditingController(text: widget.initialSubtitle);
    _manualTransforms = _decodeManualTransforms(widget.initialPhotoLayoutJson);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  List<String> get _orderedSelectedPaths =>
      widget.photoPaths.where(_selectedPaths.contains).toList();

  void _togglePhoto(String path, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedPaths.length < 8) {
          _selectedPaths.add(path);
        }
      } else {
        _selectedPaths.remove(path);
      }
    });
  }

  void _shuffleCorkboard() {
    setState(() {
      _layoutSeed = math.Random().nextInt(0x7fffffff);
      _manualTransforms = {};
    });
  }

  void _updateManualTransforms(
    Map<String, _ManualCollageTransform> transforms,
  ) {
    setState(() {
      _manualTransforms = transforms;
    });
  }

  String _encodeCurrentTransforms() {
    return jsonEncode({
      for (final entry in _manualTransforms.entries)
        entry.key: entry.value.toJson(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _orderedSelectedPaths;
    final canSave = selected.length >= 2;

    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit Collage Page' : 'Add Collage Page'),
      content: SizedBox(
        width: 1080,
        height: 720,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 315,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Page title',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Family Memories',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Subtitle',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _subtitleController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Optional',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Choose photos',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text('${selected.length} selected • choose 2–8'),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                      itemCount: widget.photoPaths.length,
                      itemBuilder: (context, index) {
                        final path = widget.photoPaths[index];
                        final isSelected = _selectedPaths.contains(path);
                        final atLimit =
                            _selectedPaths.length >= 8 && !isSelected;

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: atLimit
                                ? null
                                : () => _togglePhoto(path, !isSelected),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(File(path), fit: BoxFit.cover),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Material(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    shape: const CircleBorder(),
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: atLimit
                                          ? null
                                          : (value) => _togglePhoto(
                                              path,
                                              value ?? false,
                                            ),
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
                  const SizedBox(height: 16),
                  const Text(
                    'Layout',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _layoutKey,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'balanced',
                        child: Text('Balanced Grid'),
                      ),
                      DropdownMenuItem(
                        value: 'featured',
                        child: Text('Featured Photo'),
                      ),
                      DropdownMenuItem(
                        value: 'filmstrip',
                        child: Text('Heritage Filmstrip'),
                      ),
                      DropdownMenuItem(
                        value: 'corkboard',
                        child: Text('Corkboard / Random'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _layoutKey = value);
                    },
                  ),
                  if (_layoutKey == 'corkboard') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _shuffleCorkboard,
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Shuffle Layout'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Shuffle until you find an arrangement you like. '
                      'The saved page will keep that arrangement.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const VerticalDivider(width: 32),
            Expanded(
              child: selected.length < 2
                  ? Center(
                      child: Text(
                        'Choose at least two photos to preview the collage.',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _layoutKey == 'corkboard'
                  ? _EditableCorkboardPagePreview(
                      photoPaths: selected,
                      layoutSeed: _layoutSeed,
                      title: _titleController.text,
                      subtitle: _subtitleController.text,
                      initialTransforms: _manualTransforms,
                      onTransformsChanged: _updateManualTransforms,
                    )
                  : _CollagePagePreview(
                      photoPaths: selected,
                      layoutKey: _layoutKey,
                      layoutSeed: _layoutSeed,
                      title: _titleController.text,
                      subtitle: _subtitleController.text,
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: canSave
              ? () => Navigator.pop(
                  context,
                  _CollagePageResult(
                    photoPaths: selected,
                    layoutKey: _layoutKey,
                    layoutSeed: _layoutSeed,
                    title: _titleController.text.trim(),
                    subtitle: _subtitleController.text.trim(),
                    photoLayoutJson: _layoutKey == 'corkboard'
                        ? _encodeCurrentTransforms()
                        : '{}',
                  ),
                )
              : null,
          icon: const Icon(Icons.grid_view_outlined),
          label: Text(widget.isEditing ? 'Save Changes' : 'Add Collage'),
        ),
      ],
    );
  }
}

class _SavedCollagePreviewDialog extends StatelessWidget {
  final List<String> photoPaths;
  final String layoutKey;
  final int layoutSeed;
  final String title;
  final String subtitle;
  final String photoLayoutJson;

  const _SavedCollagePreviewDialog({
    required this.photoPaths,
    required this.layoutKey,
    required this.layoutSeed,
    required this.title,
    required this.subtitle,
    required this.photoLayoutJson,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Collage Preview'),
      content: SizedBox(
        width: 820,
        height: 680,
        child: _CollagePagePreview(
          photoPaths: photoPaths,
          layoutKey: layoutKey,
          layoutSeed: layoutSeed,
          title: title,
          subtitle: subtitle,
          photoLayoutJson: photoLayoutJson,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ManualCollageTransform {
  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final double rotation;
  final int zIndex;

  const _ManualCollageTransform({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.rotation,
    required this.zIndex,
  });

  Map<String, Object?> toJson() => {
    'centerX': centerX,
    'centerY': centerY,
    'width': width,
    'height': height,
    'rotation': rotation,
    'zIndex': zIndex,
  };

  factory _ManualCollageTransform.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return _ManualCollageTransform(
      centerX: number('centerX', 0.5),
      centerY: number('centerY', 0.5),
      width: number('width', 0.3),
      height: number('height', 0.3),
      rotation: number('rotation', 0),
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
    );
  }

  _ManualCollageTransform copyWith({
    double? centerX,
    double? centerY,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
  }) {
    return _ManualCollageTransform(
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}

Map<String, _ManualCollageTransform> _decodeManualTransforms(String jsonText) {
  try {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) return {};

    final result = <String, _ManualCollageTransform>{};
    decoded.forEach((key, value) {
      if (key is String && value is Map) {
        result[key] = _ManualCollageTransform.fromJson(
          Map<String, Object?>.from(value),
        );
      }
    });
    return result;
  } catch (_) {
    return {};
  }
}

class _EditableCorkboardPagePreview extends StatefulWidget {
  final List<String> photoPaths;
  final int layoutSeed;
  final String title;
  final String subtitle;
  final Map<String, _ManualCollageTransform> initialTransforms;
  final ValueChanged<Map<String, _ManualCollageTransform>> onTransformsChanged;

  const _EditableCorkboardPagePreview({
    required this.photoPaths,
    required this.layoutSeed,
    required this.title,
    required this.subtitle,
    required this.initialTransforms,
    required this.onTransformsChanged,
  });

  @override
  State<_EditableCorkboardPagePreview> createState() =>
      _EditableCorkboardPagePreviewState();
}

class _EditableCorkboardPagePreviewState
    extends State<_EditableCorkboardPagePreview> {
  late Map<String, _ManualCollageTransform> _transforms;
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _transforms = Map<String, _ManualCollageTransform>.from(
      widget.initialTransforms,
    );
  }

  @override
  void didUpdateWidget(covariant _EditableCorkboardPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.layoutSeed != widget.layoutSeed) {
      _transforms = {};
      _selectedPath = null;
    } else {
      for (final path in _transforms.keys.toList()) {
        if (!widget.photoPaths.contains(path)) {
          _transforms.remove(path);
        }
      }
    }
  }

  void _publish() {
    widget.onTransformsChanged(
      Map<String, _ManualCollageTransform>.from(_transforms),
    );
  }

  void _selectPhoto(String path) {
    if (_selectedPath == path) return;
    setState(() => _selectedPath = path);
  }

  void _bringForward() {
    final path = _selectedPath;
    if (path == null || !_transforms.containsKey(path)) return;

    final current = _transforms[path]!;
    final topZ = _transforms.values.fold<int>(
      0,
      (maxZ, item) => math.max(maxZ, item.zIndex),
    );

    setState(() {
      _transforms[path] = current.copyWith(zIndex: topZ + 1);
    });
    _publish();
  }

  void _sendBackward() {
    final path = _selectedPath;
    if (path == null || !_transforms.containsKey(path)) return;

    final current = _transforms[path]!;
    final bottomZ = _transforms.values.fold<int>(
      0,
      (minZ, item) => math.min(minZ, item.zIndex),
    );

    setState(() {
      _transforms[path] = current.copyWith(zIndex: bottomZ - 1);
    });
    _publish();
  }

  void _rotateSelected(double degrees) {
    final path = _selectedPath;
    if (path == null || !_transforms.containsKey(path)) return;

    final current = _transforms[path]!;
    final radians = degrees * math.pi / 180;
    final nextRotation = (current.rotation + radians).clamp(-0.60, 0.60);

    setState(() {
      _transforms[path] = current.copyWith(rotation: nextRotation);
    });
    _publish();
  }

  void _resetSelectedPhoto() {
    final path = _selectedPath;
    if (path == null) return;

    setState(() {
      _transforms.remove(path);
      _selectedPath = null;
    });
    _publish();
  }

  void _resetAllPhotos() {
    setState(() {
      _transforms = {};
      _selectedPath = null;
    });
    _publish();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      decoration: AtlasBookTheme.pageDecoration,
      child: Column(
        children: [
          if (widget.title.trim().isNotEmpty)
            Text(
              widget.title.trim(),
              style: AtlasBookTheme.displayTitle(context),
              textAlign: TextAlign.center,
            ),
          if (widget.subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              widget.subtitle.trim(),
              style: AtlasBookTheme.subtitle(
                context,
              ).copyWith(fontSize: 13, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
          if (widget.title.trim().isNotEmpty ||
              widget.subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 80),
              child: _HeritageDivider(),
            ),
            const SizedBox(height: 20),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final helper = _CollagePagePreview(
                  photoPaths: widget.photoPaths,
                  layoutKey: 'corkboard',
                  layoutSeed: widget.layoutSeed,
                  title: widget.title,
                  subtitle: widget.subtitle,
                );
                final autoSpecs = helper._corkboardSpecs(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );

                for (var index = 0; index < widget.photoPaths.length; index++) {
                  final path = widget.photoPaths[index];
                  if (_transforms.containsKey(path)) continue;

                  final spec = autoSpecs[index];
                  _transforms[path] = _ManualCollageTransform(
                    centerX:
                        (spec.left + spec.width / 2) / constraints.maxWidth,
                    centerY:
                        (spec.top + spec.height / 2) / constraints.maxHeight,
                    width: spec.width / constraints.maxWidth,
                    height: spec.height / constraints.maxHeight,
                    rotation: spec.rotation,
                    zIndex: index,
                  );
                }

                final ordered = [...widget.photoPaths]
                  ..sort((a, b) {
                    final az = _transforms[a]?.zIndex ?? 0;
                    final bz = _transforms[b]?.zIndex ?? 0;
                    return az.compareTo(bz);
                  });

                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFB9895A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AtlasBookTheme.warmBrown.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CorkTexturePainter(seed: widget.layoutSeed),
                        ),
                      ),
                      for (final path in ordered)
                        _buildDraggablePhoto(context, path, constraints),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: _selectedPath == null ? null : _bringForward,
                icon: const Icon(Icons.flip_to_front, size: 18),
                label: const Text('Bring Forward'),
              ),
              OutlinedButton.icon(
                onPressed: _selectedPath == null ? null : _sendBackward,
                icon: const Icon(Icons.flip_to_back, size: 18),
                label: const Text('Send Back'),
              ),
              OutlinedButton.icon(
                onPressed: _selectedPath == null
                    ? null
                    : () => _rotateSelected(-5),
                icon: const Icon(Icons.rotate_left, size: 18),
                label: const Text('Rotate Left'),
              ),
              OutlinedButton.icon(
                onPressed: _selectedPath == null
                    ? null
                    : () => _rotateSelected(5),
                icon: const Icon(Icons.rotate_right, size: 18),
                label: const Text('Rotate Right'),
              ),
              OutlinedButton.icon(
                onPressed: _selectedPath == null ? null : _resetSelectedPhoto,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset Photo'),
              ),
              TextButton.icon(
                onPressed: _resetAllPhotos,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset All'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectedPath == null
                ? 'Click a photo to select it, then drag to move.'
                : 'Drag to move • bottom-right resizes • top-right rotates • buttons rotate 5°',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDraggablePhoto(
    BuildContext context,
    String path,
    BoxConstraints constraints,
  ) {
    final transform = _transforms[path]!;
    final itemWidth = transform.width * constraints.maxWidth;
    final itemHeight = transform.height * constraints.maxHeight;
    final left = transform.centerX * constraints.maxWidth - itemWidth / 2;
    final top = transform.centerY * constraints.maxHeight - itemHeight / 2;
    final selected = _selectedPath == path;

    return Positioned(
      left: left,
      top: top,
      width: itemWidth,
      height: itemHeight,
      child: Transform.rotate(
        angle: transform.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _selectPhoto(path);
                  _bringForward();
                },
                onPanStart: (_) => _selectPhoto(path),
                onPanUpdate: (details) {
                  final current = _transforms[path]!;
                  final dx = details.delta.dx / constraints.maxWidth;
                  final dy = details.delta.dy / constraints.maxHeight;

                  final halfW = current.width / 2;
                  final halfH = current.height / 2;

                  final nextX = (current.centerX + dx).clamp(
                    halfW,
                    1.0 - halfW,
                  );
                  final nextY = (current.centerY + dy).clamp(
                    halfH,
                    1.0 - halfH,
                  );

                  setState(() {
                    _transforms[path] = current.copyWith(
                      centerX: nextX,
                      centerY: nextY,
                    );
                  });
                  _publish();
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBF1),
                    border: Border.all(
                      color: selected
                          ? AtlasBookTheme.antiqueGold
                          : AtlasBookTheme.antiqueGoldSoft,
                      width: selected ? 2.4 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 7,
                        offset: const Offset(2, 3),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: const Color(0xFFFFFCF5),
                          padding: const EdgeInsets.all(3),
                          child: Image.file(
                            File(path),
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Color(0xFFE9E0CB),
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: AtlasBookTheme.warmBrown,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -14,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5A3C),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE2C3A6),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (selected) ...[
              Positioned(
                right: -12,
                bottom: -12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final current = _transforms[path]!;
                    final aspect = current.height <= 0
                        ? 1.0
                        : current.width / current.height;

                    final delta = (details.delta.dx + details.delta.dy) / 2;
                    final widthDelta = delta / constraints.maxWidth;

                    final newWidth = (current.width + widthDelta).clamp(
                      0.14,
                      0.70,
                    );
                    final newHeight = (newWidth / aspect).clamp(0.12, 0.70);

                    setState(() {
                      _transforms[path] = current.copyWith(
                        width: newWidth,
                        height: newHeight,
                      );
                    });
                    _publish();
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AtlasBookTheme.antiqueGold,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFFBF1),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -12,
                top: -12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final current = _transforms[path]!;
                    final rotationDelta =
                        (details.delta.dx - details.delta.dy) * 0.018;
                    final newRotation = (current.rotation + rotationDelta)
                        .clamp(-0.60, 0.60);

                    setState(() {
                      _transforms[path] = current.copyWith(
                        rotation: newRotation,
                      );
                    });
                    _publish();
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AtlasBookTheme.warmBrown,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFFBF1),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.rotate_right,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CorkboardPhotoSpec {
  final double left;
  final double top;
  final double width;
  final double height;
  final double rotation;

  const _CorkboardPhotoSpec({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.rotation,
  });
}

class _CollagePagePreview extends StatelessWidget {
  final List<String> photoPaths;
  final String layoutKey;
  final int layoutSeed;
  final String title;
  final String subtitle;
  final String photoLayoutJson;

  const _CollagePagePreview({
    required this.photoPaths,
    required this.layoutKey,
    this.layoutSeed = 0,
    this.title = 'Family Memories',
    this.subtitle = '',
    this.photoLayoutJson = '{}',
  });

  Widget _photo(String path) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF5),
        border: Border.all(color: AtlasBookTheme.antiqueGoldSoft, width: 1.2),
      ),
      padding: const EdgeInsets.all(4),
      child: ClipRect(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFFE9E0CB),
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AtlasBookTheme.warmBrown,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _balancedLayout() {
    final count = photoPaths.length;
    final columns = count <= 4 ? 2 : 3;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: count <= 4 ? 1.05 : 0.9,
      ),
      itemCount: count,
      itemBuilder: (_, index) => _photo(photoPaths[index]),
    );
  }

  Widget _featuredLayout() {
    final remaining = photoPaths.skip(1).toList();

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: SizedBox(
            width: double.infinity,
            child: _photo(photoPaths.first),
          ),
        ),
        if (remaining.isNotEmpty) ...[
          const SizedBox(height: 10),
          Expanded(
            flex: 2,
            child: Row(
              children: List.generate(
                remaining.length,
                (index) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : 5,
                      right: index == remaining.length - 1 ? 0 : 5,
                    ),
                    child: _photo(remaining[index]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _filmstripLayout() {
    return Column(
      children: [
        for (var index = 0; index < photoPaths.length; index++) ...[
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AtlasBookTheme.antiqueGold,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(child: _photo(photoPaths[index])),
              ],
            ),
          ),
          if (index != photoPaths.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  double _photoAspectRatio(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      if (bytes.isEmpty) return 1.35;
    } catch (_) {
      return 1.35;
    }
    return _imageAspectFromBytes(path);
  }

  double _imageAspectFromBytes(String path) {
    try {
      final data = File(path).readAsBytesSync();

      // JPEG
      if (data.length > 10 && data[0] == 0xFF && data[1] == 0xD8) {
        var offset = 2;
        while (offset + 9 < data.length) {
          if (data[offset] != 0xFF) {
            offset++;
            continue;
          }
          final marker = data[offset + 1];
          if (marker == 0xD8 || marker == 0xD9) {
            offset += 2;
            continue;
          }
          if (offset + 3 >= data.length) break;
          final length = (data[offset + 2] << 8) + data[offset + 3];
          if (length < 2 || offset + length + 2 > data.length) break;

          final isSof =
              marker >= 0xC0 &&
              marker <= 0xCF &&
              !{0xC4, 0xC8, 0xCC}.contains(marker);
          if (isSof && offset + 8 < data.length) {
            final h = (data[offset + 5] << 8) + data[offset + 6];
            final w = (data[offset + 7] << 8) + data[offset + 8];
            if (w > 0 && h > 0) return w / h;
          }
          offset += length + 2;
        }
      }

      // PNG
      if (data.length >= 24 &&
          data[0] == 0x89 &&
          data[1] == 0x50 &&
          data[2] == 0x4E &&
          data[3] == 0x47) {
        final w =
            (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19];
        final h =
            (data[20] << 24) | (data[21] << 16) | (data[22] << 8) | data[23];
        if (w > 0 && h > 0) return w / h;
      }
    } catch (_) {}

    return 1.35;
  }

  List<_CorkboardPhotoSpec> _corkboardSpecs(double width, double height) {
    final random = math.Random(layoutSeed);
    final count = photoPaths.length;

    final anchorsByCount = <int, List<Offset>>{
      2: const [Offset(0.30, 0.30), Offset(0.70, 0.70)],
      3: const [Offset(0.28, 0.27), Offset(0.72, 0.34), Offset(0.48, 0.73)],
      4: const [
        Offset(0.27, 0.27),
        Offset(0.73, 0.28),
        Offset(0.30, 0.72),
        Offset(0.72, 0.72),
      ],
      5: const [
        Offset(0.25, 0.23),
        Offset(0.73, 0.25),
        Offset(0.49, 0.49),
        Offset(0.26, 0.76),
        Offset(0.73, 0.75),
      ],
      6: const [
        Offset(0.23, 0.22),
        Offset(0.51, 0.23),
        Offset(0.78, 0.25),
        Offset(0.24, 0.73),
        Offset(0.51, 0.70),
        Offset(0.78, 0.74),
      ],
      7: const [
        Offset(0.21, 0.21),
        Offset(0.50, 0.20),
        Offset(0.79, 0.23),
        Offset(0.34, 0.49),
        Offset(0.67, 0.49),
        Offset(0.24, 0.78),
        Offset(0.75, 0.77),
      ],
      8: const [
        Offset(0.20, 0.20),
        Offset(0.50, 0.20),
        Offset(0.80, 0.21),
        Offset(0.32, 0.47),
        Offset(0.68, 0.48),
        Offset(0.20, 0.78),
        Offset(0.50, 0.76),
        Offset(0.80, 0.78),
      ],
    };

    final anchors = List<Offset>.from(
      anchorsByCount[count] ?? anchorsByCount[8]!,
    )..shuffle(random);

    final specs = <_CorkboardPhotoSpec>[];

    for (var index = 0; index < count; index++) {
      final anchor = anchors[index];
      final aspect = _photoAspectRatio(photoPaths[index]).clamp(0.55, 1.9);

      final baseWidth = count <= 2
          ? 0.43
          : count <= 4
          ? 0.35
          : count <= 6
          ? 0.29
          : 0.25;

      var itemWidth = width * (baseWidth + (random.nextDouble() - 0.5) * 0.05);

      // Thin mat + modest caption-like lower margin, rather than a large
      // Polaroid blank area.
      const horizontalFrame = 18.0;
      const verticalFrame = 30.0;
      var photoWidth = math.max(40.0, itemWidth - horizontalFrame);
      var photoHeight = photoWidth / aspect;
      var itemHeight = photoHeight + verticalFrame;

      final maxHeight = height * (count <= 2 ? 0.42 : 0.34);
      if (itemHeight > maxHeight) {
        final scale = maxHeight / itemHeight;
        itemWidth *= scale;
        photoWidth = math.max(40.0, itemWidth - horizontalFrame);
        photoHeight = photoWidth / aspect;
        itemHeight = photoHeight + verticalFrame;
      }

      final jitterX = (random.nextDouble() - 0.5) * width * 0.07;
      final jitterY = (random.nextDouble() - 0.5) * height * 0.07;

      var centerX = anchor.dx * width + jitterX;
      var centerY = anchor.dy * height + jitterY;

      centerX = centerX.clamp(itemWidth / 2 + 10, width - itemWidth / 2 - 10);
      centerY = centerY.clamp(
        itemHeight / 2 + 10,
        height - itemHeight / 2 - 10,
      );

      final rotation = (random.nextDouble() * 7.0 - 3.5) * math.pi / 180;

      specs.add(
        _CorkboardPhotoSpec(
          left: centerX - itemWidth / 2,
          top: centerY - itemHeight / 2,
          width: itemWidth,
          height: itemHeight,
          rotation: rotation,
        ),
      );
    }

    return specs;
  }

  Widget _corkboardLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final autoSpecs = _corkboardSpecs(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final savedTransforms = _decodeManualTransforms(photoLayoutJson);
        final specs = List<_CorkboardPhotoSpec>.generate(photoPaths.length, (
          index,
        ) {
          final saved = savedTransforms[photoPaths[index]];
          if (saved == null) return autoSpecs[index];

          return _CorkboardPhotoSpec(
            left:
                saved.centerX * constraints.maxWidth -
                saved.width * constraints.maxWidth / 2,
            top:
                saved.centerY * constraints.maxHeight -
                saved.height * constraints.maxHeight / 2,
            width: saved.width * constraints.maxWidth,
            height: saved.height * constraints.maxHeight,
            rotation: saved.rotation,
          );
        });

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFB9895A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AtlasBookTheme.warmBrown.withValues(alpha: 0.55),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CorkTexturePainter(seed: layoutSeed),
                ),
              ),
              for (final index in List<int>.generate(
                photoPaths.length,
                (index) => index,
              )..shuffle(math.Random(layoutSeed ^ 0x2F31)))
                Positioned(
                  left: specs[index].left,
                  top: specs[index].top,
                  width: specs[index].width,
                  height: specs[index].height,
                  child: Transform.rotate(
                    angle: specs[index].rotation,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBF1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 6,
                            offset: const Offset(2, 3),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(child: _photo(photoPaths[index])),
                          Positioned(
                            top: -14,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5A3C),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFE2C3A6),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.20,
                                      ),
                                      blurRadius: 2,
                                      offset: const Offset(1, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      decoration: AtlasBookTheme.pageDecoration,
      child: Column(
        children: [
          if (title.trim().isNotEmpty)
            Text(
              title.trim(),
              style: AtlasBookTheme.displayTitle(context),
              textAlign: TextAlign.center,
            ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              subtitle.trim(),
              style: AtlasBookTheme.subtitle(
                context,
              ).copyWith(fontSize: 13, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
          if (title.trim().isNotEmpty || subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 80),
              child: _HeritageDivider(),
            ),
            const SizedBox(height: 20),
          ],
          Expanded(
            child: photoPaths.isEmpty
                ? Center(
                    child: Text(
                      'No photos selected.',
                      style: AtlasBookTheme.body(context),
                    ),
                  )
                : switch (layoutKey) {
                    'featured' => _featuredLayout(),
                    'filmstrip' => _filmstripLayout(),
                    'corkboard' => _corkboardLayout(),
                    _ => _balancedLayout(),
                  },
          ),
        ],
      ),
    );
  }
}

class _CorkTexturePainter extends CustomPainter {
  final int seed;

  const _CorkTexturePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed ^ 0x5A17);
    final paint = Paint();

    for (var i = 0; i < 320; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = 0.35 + random.nextDouble() * 1.2;
      final dark = random.nextBool();

      paint.color = (dark ? const Color(0xFF6F472C) : const Color(0xFFE0B47D))
          .withValues(alpha: 0.20 + random.nextDouble() * 0.18);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CorkTexturePainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}

class _PersonProfilePageResult {
  final int personId;
  final String? heroPhotoPath;

  const _PersonProfilePageResult({required this.personId, this.heroPhotoPath});
}

class _PersonProfilePageDialog extends StatefulWidget {
  final List<FamilyPerson> people;
  final List<String> photoPaths;
  final int? initialPersonId;
  final String? initialHeroPhotoPath;
  final bool isEditing;

  const _PersonProfilePageDialog({
    required this.people,
    required this.photoPaths,
    this.initialPersonId,
    this.initialHeroPhotoPath,
    this.isEditing = false,
  });

  @override
  State<_PersonProfilePageDialog> createState() =>
      _PersonProfilePageDialogState();
}

class _PersonProfilePageDialogState extends State<_PersonProfilePageDialog> {
  late FamilyPerson _person;
  String? _heroPhotoPath;

  @override
  void initState() {
    super.initState();
    _person = widget.people.firstWhere(
      (person) => person.id == widget.initialPersonId,
      orElse: () => widget.people.first,
    );

    final initialHero = widget.initialHeroPhotoPath;
    _heroPhotoPath =
        initialHero != null &&
            initialHero.isNotEmpty &&
            widget.photoPaths.contains(initialHero)
        ? initialHero
        : widget.photoPaths.isEmpty
        ? null
        : widget.photoPaths.first;
  }

  @override
  Widget build(BuildContext context) {
    final profilePath = _person.profilePhotoPath;
    final hasProfilePhoto =
        profilePath.isNotEmpty && File(profilePath).existsSync();
    final heroPath = _heroPhotoPath;
    final hasHero = heroPath != null && File(heroPath).existsSync();

    return AlertDialog(
      title: Text(
        widget.isEditing
            ? 'Edit Person Profile Page'
            : 'Add Person Profile Page',
      ),
      content: SizedBox(
        width: 850,
        height: 650,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Person',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _person.id,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: widget.people
                        .where((person) => person.id != null)
                        .map(
                          (person) => DropdownMenuItem<int>(
                            value: person.id!,
                            child: Text(person.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() {
                        _person = widget.people.firstWhere(
                          (person) => person.id == id,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Featured photo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (widget.photoPaths.isEmpty)
                    const Text(
                      'No saved book photos yet. The Family Tree profile photo '
                      'will be used when available.',
                    )
                  else
                    Expanded(
                      child: ListView(
                        children: [
                          RadioGroup<String>(
                            groupValue: _heroPhotoPath,
                            onChanged: (value) {
                              setState(() => _heroPhotoPath = value);
                            },
                            child: Column(
                              children: widget.photoPaths.map((path) {
                                return RadioListTile<String>(
                                  value: path,
                                  title: Text(
                                    path.split(Platform.pathSeparator).last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 32),
            Expanded(
              child: _PersonProfilePagePreview(
                person: _person,
                imagePath: hasHero
                    ? heroPath
                    : hasProfilePhoto
                    ? profilePath
                    : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _person.id == null
              ? null
              : () => Navigator.pop(
                  context,
                  _PersonProfilePageResult(
                    personId: _person.id!,
                    heroPhotoPath: _heroPhotoPath,
                  ),
                ),
          icon: const Icon(Icons.add),
          label: Text(widget.isEditing ? 'Save Changes' : 'Add Person Profile'),
        ),
      ],
    );
  }
}

class _SavedPersonProfilePreviewDialog extends StatelessWidget {
  final FamilyPerson person;
  final String heroPhotoPath;

  const _SavedPersonProfilePreviewDialog({
    required this.person,
    required this.heroPhotoPath,
  });

  @override
  Widget build(BuildContext context) {
    final profilePath = person.profilePhotoPath;
    final imagePath =
        heroPhotoPath.isNotEmpty && File(heroPhotoPath).existsSync()
        ? heroPhotoPath
        : profilePath.isNotEmpty && File(profilePath).existsSync()
        ? profilePath
        : null;

    return AlertDialog(
      title: const Text('Person Profile Preview'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: _PersonProfilePagePreview(person: person, imagePath: imagePath),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PersonProfilePagePreview extends StatelessWidget {
  final FamilyPerson person;
  final String? imagePath;

  const _PersonProfilePagePreview({
    required this.person,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && File(imagePath!).existsSync();

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: AtlasBookTheme.pageDecoration,

      child: SingleChildScrollView(
        child: Column(
          children: [
            Text(
              person.displayName,
              textAlign: TextAlign.center,
              style: AtlasBookTheme.displayTitle(context),
            ),
            if (person.lifeSpan.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                person.lifeSpan,
                style: AtlasBookTheme.sectionTitle(context),
              ),
            ],
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 60),
              child: _HeritageDivider(),
            ),
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 260,
                width: double.infinity,
                child: hasImage
                    ? Image.file(File(imagePath!), fit: BoxFit.cover)
                    : const ColoredBox(
                        color: Color(0x11000000),
                        child: Center(
                          child: Icon(Icons.person_outline, size: 72),
                        ),
                      ),
              ),
            ),
            if (person.birthPlace.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Born in ${person.birthPlace}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            if (person.biography.trim().isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                person.biography.trim(),
                style: AtlasBookTheme.body(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final String? actionLabel;

  const _WorkspaceStep({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    this.onTap,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              CircleAvatar(child: Text(number)),
              const SizedBox(width: 18),
              Icon(
                icon,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(width: 16),
                FilledButton(onPressed: onTap, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
