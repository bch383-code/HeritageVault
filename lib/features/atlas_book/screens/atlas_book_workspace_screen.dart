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

  const AtlasBookWorkspaceScreen({
    super.key,
    required this.book,
  });

  @override
  State<AtlasBookWorkspaceScreen> createState() =>
      _AtlasBookWorkspaceScreenState();
}

class _AtlasBookWorkspaceScreenState
    extends State<AtlasBookWorkspaceScreen> {
  final AtlasBookRepository _repository = AtlasBookRepository();
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  List<FamilyPerson> _selectedPeople = [];
  bool _loadingPeople = true;
  List<String> _connectedPhotoPaths = [];
  Set<String> _selectedPhotoPaths = <String>{};
  bool _loadingConnectedPhotos = false;
  List<AtlasBookPage> _bookPages = [];
  bool _loadingPages = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedPeople();
    _loadSavedBookPhotos();
    _loadBookPages();
  }

  Future<void> _loadSelectedPeople() async {
    final bookId = widget.book.id;

    if (bookId == null) {
      setState(() => _loadingPeople = false);
      return;
    }

    final selectedIds =
        (await _repository.getBookPersonIds(bookId)).toSet();

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
          .where((person) =>
              person.id != null && selectedIds.contains(person.id))
          .toList();
      _loadingPeople = false;
    });
  }

  Future<void> _choosePeople() async {
    final bookId = widget.book.id;

    if (bookId == null) {
      return;
    }

    final currentIds =
        (await _repository.getBookPersonIds(bookId)).toSet();

    if (!mounted) return;

    final selectedIds = await showDialog<Set<int>>(
      context: context,
      builder: (_) => FamilyPeoplePickerDialog(
        initiallySelectedIds: currentIds,
      ),
    );

    if (selectedIds == null) {
      return;
    }

    await _repository.replaceBookPeople(
      bookId,
      selectedIds,
    );

    await _loadSelectedPeople();
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

  Future<void> _saveBookPhotos() async {
    final bookId = widget.book.id;
    if (bookId == null) return;

    await _repository.replaceBookPhotos(
      bookId,
      _selectedPhotoPaths,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_selectedPhotoPaths.length} '
          '${_selectedPhotoPaths.length == 1 ? 'photo' : 'photos'} saved to this book.',
        ),
      ),
    );
  }

  Future<void> _gatherConnectedPhotos() async {
    final personIds = _selectedPeople
        .where((person) => person.id != null)
        .map((person) => person.id!)
        .toSet();

    if (personIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose at least one person for this book first.'),
        ),
      );
      return;
    }

    setState(() => _loadingConnectedPhotos = true);

    final paths =
        await _databaseHelper.getPhotoPathsForFamilyPeople(personIds);

    if (!mounted) return;

    setState(() {
      _connectedPhotoPaths = paths
          .where((path) => path.isNotEmpty && File(path).existsSync())
          .toList();
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

  Future<void> _addPage() async {
    final pageType = await showDialog<String>(
      context: context,
      builder: (_) => const _AddPageTypeDialog(),
    );

    if (pageType == 'person_profile') {
      await _createPersonProfilePage();
    } else if (pageType == 'ancestry_fan_chart') {
      await _createAncestryFanChartPage();
    } else if (pageType == 'family_group_sheet') {
      await _createFamilyGroupSheetPage();
    } else if (pageType == 'collage') {
      await _createCollagePage();
    }
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
      builder: (_) => _CollagePageDialog(
        photoPaths: availablePhotos,
      ),
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
      const SnackBar(
        content: Text('Collage page saved to this book.'),
      ),
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

    Future<void> walk(
      int personId,
      int generation,
      int slot,
    ) async {
      if (generation >= generationCount) return;
      if (!visited.add(personId)) return;

      final person = await _databaseHelper.getFamilyPerson(personId);
      if (person == null) return;

      nodes.add(
        _FanAncestorNode(
          person: person,
          generation: generation,
          slot: slot,
        ),
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

        await walk(
          parentId,
          generation + 1,
          parentSlot,
        );
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
      const SnackBar(
        content: Text('Family Group Sheet saved to this book.'),
      ),
    );
  }

  Future<_FamilyGroupSheetData?> _buildFamilyGroupSheetData({
    required int primaryPersonId,
    int? spousePersonId,
  }) async {
    final primary =
        await _databaseHelper.getFamilyPerson(primaryPersonId);

    if (primary == null) return null;

    FamilyPerson? spouse;
    if (spousePersonId != null) {
      spouse = await _databaseHelper.getFamilyPerson(spousePersonId);
    }

    final primaryParents =
        await _databaseHelper.getFamilyParents(primaryPersonId);

    final spouseParents = spousePersonId == null
        ? <FamilyPerson>[]
        : await _databaseHelper.getFamilyParents(spousePersonId);

    final primaryChildren =
        await _databaseHelper.getFamilyChildren(primaryPersonId);

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

    if (page.pageType != 'collage' && _selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose people for this book before editing pages.'),
        ),
      );
      return;
    }

    final now = DateTime.now();

    if (page.pageType == 'collage') {
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page changes saved.')),
    );
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
        builder: (_) => _SavedFamilyGroupSheetPreviewDialog(
          data: data,
        ),
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
          _BookPreviewPageData(
            page: page,
            collagePhotoPaths: photoPaths,
          ),
        );
        continue;
      }

      if (page.personId == null) continue;

      if (page.pageType == 'ancestry_fan_chart') {
        final nodes = await _buildFanAncestors(
          rootPersonId: page.personId!,
          generationCount: page.generationCount,
        );

        previewPages.add(
          _BookPreviewPageData(
            page: page,
            fanNodes: nodes,
          ),
        );
        continue;
      }

      if (page.pageType == 'family_group_sheet') {
        final data = await _buildFamilyGroupSheetData(
          primaryPersonId: page.personId!,
          spousePersonId: page.relatedPersonId,
        );

        if (data != null) {
          previewPages.add(
            _BookPreviewPageData(
              page: page,
              familyGroupData: data,
            ),
          );
        }
        continue;
      }

      final person =
          await _databaseHelper.getFamilyPerson(page.personId!);

      if (person != null) {
        previewPages.add(
          _BookPreviewPageData(
            page: page,
            person: person,
          ),
        );
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
      appBar: AppBar(
        title: Text(book.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (book.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    book.subtitle,
                    style: AtlasBookTheme.subtitle(context),
                  ),
                ],
                const SizedBox(height: 12),
                Chip(
                  avatar: Icon(book.scope.icon, size: 18),
                  label: Text(book.scope.label),
                ),
                const SizedBox(height: 32),
                Text(
                  'Build Your Book',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 18),
                _WorkspaceStep(
                  number: '1',
                  title: _selectionTitle(book.scope),
                  description: _selectionDescription(book.scope),
                  icon: book.scope.icon,
                  onTap: book.scope == AtlasBookScope.people
                      ? _choosePeople
                      : null,
                  actionLabel: book.scope == AtlasBookScope.people
                      ? 'Choose People'
                      : null,
                ),
                if (book.scope == AtlasBookScope.people) ...[
                  const SizedBox(height: 12),
                  _SelectedPeoplePanel(
                    loading: _loadingPeople,
                    people: _selectedPeople,
                    onChoosePeople: _choosePeople,
                  ),
                ],
                const SizedBox(height: 12),
                _WorkspaceStep(
                  number: '2',
                  title: 'Gather connected material',
                  description:
                      'Find photos, stories, documents, heirlooms, and other '
                      'items connected to the people in this book.',
                  icon: Icons.collections_bookmark_outlined,
                  onTap: _gatherConnectedPhotos,
                  actionLabel: 'Find Connected Photos',
                ),
                if (_loadingConnectedPhotos ||
                    _connectedPhotoPaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ConnectedPhotosPanel(
                    loading: _loadingConnectedPhotos,
                    photoPaths: _connectedPhotoPaths,
                    selectedPhotoPaths: _selectedPhotoPaths,
                    onSelectionChanged: (path, selected) {
                      setState(() {
                        if (selected) {
                          _selectedPhotoPaths.add(path);
                        } else {
                          _selectedPhotoPaths.remove(path);
                        }
                      });
                    },
                    onSave: _saveBookPhotos,
                  ),
                ],
                const SizedBox(height: 12),
                _WorkspaceStep(
                  number: '3',
                  title: 'Build the story',
                  description:
                      'Turn the people and material you selected into actual '
                      'Atlas Book pages.',
                  icon: Icons.menu_book_outlined,
                  onTap: _addPage,
                  actionLabel: 'Add Page',
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
                  description:
                      _bookPages.isEmpty
                          ? 'Add at least one saved page, then preview the whole book.'
                          : 'Flip through all ${_bookPages.length} saved '
                              '${_bookPages.length == 1 ? 'page' : 'pages'} in book order.',
                  icon: Icons.preview_outlined,
                  onTap: _bookPages.isEmpty ? null : _previewBook,
                  actionLabel:
                      _bookPages.isEmpty ? null : 'Preview Book',
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

class _SelectedPeoplePanel extends StatelessWidget {
  final bool loading;
  final List<FamilyPerson> people;
  final VoidCallback onChoosePeople;

  const _SelectedPeoplePanel({
    required this.loading,
    required this.people,
    required this.onChoosePeople,
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
              const Expanded(
                child: Text(
                  'No people have been added to this book yet.',
                ),
              ),
              FilledButton(
                onPressed: onChoosePeople,
                child: const Text('Choose People'),
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
                  label: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...people.map(
              (person) {
                final path = person.profilePhotoPath;
                final hasPhoto =
                    path.isNotEmpty && File(path).existsSync();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundImage:
                        hasPhoto ? FileImage(File(path)) : null,
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
                      if (person.lifeSpan.isNotEmpty) person.lifeSpan,
                      if (person.birthPlace.isNotEmpty)
                        person.birthPlace,
                    ].join(' • '),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedPhotosPanel extends StatelessWidget {
  final bool loading;
  final List<String> photoPaths;
  final Set<String> selectedPhotoPaths;
  final void Function(String path, bool selected) onSelectionChanged;
  final VoidCallback onSave;

  const _ConnectedPhotosPanel({
    required this.loading,
    required this.photoPaths,
    required this.selectedPhotoPaths,
    required this.onSelectionChanged,
    required this.onSave,
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

    final selectedCount =
        photoPaths.where(selectedPhotoPaths.contains).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${photoPaths.length} Connected '
                        '${photoPaths.length == 1 ? 'Photo' : 'Photos'} Found',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$selectedCount selected for this book',
                        style: AtlasBookTheme.subtitle(context),
                      ),
                    ],
                  ),
                ),
                if (photoPaths.isNotEmpty)
                  FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Book Photos'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Connected photos are suggestions. Check only the photos you '
              'want to include in this Atlas Book.',
            ),
            const SizedBox(height: 16),
            if (photoPaths.isEmpty)
              const Text(
                'No linked photos were found yet. Link photos to these people '
                'from the Photos section, then search again.',
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: photoPaths.length,
                itemBuilder: (context, index) {
                  final path = photoPaths[index];
                  final selected = selectedPhotoPaths.contains(path);

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSelectionChanged(path, !selected),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Color(0x11000000),
                              child: Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Theme.of(context).colorScheme.surface,
                              shape: const CircleBorder(),
                              elevation: 2,
                              child: Checkbox(
                                value: selected,
                                onChanged: (value) => onSelectionChanged(
                                  path,
                                  value ?? false,
                                ),
                              ),
                            ),
                          ),
                          if (selected)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              color: Colors.black54,
                              child: Text(
                                path.split(Platform.pathSeparator).last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
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
          ],
        ),
      ),
    );
  }
}

class _AddPageTypeDialog extends StatelessWidget {
  const _AddPageTypeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Page'),
      content: SizedBox(
        width: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline, size: 34),
              title: const Text(
                'Person Profile',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Featured person, photo, dates, birthplace, and biography.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, 'person_profile'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.hub_outlined, size: 34),
              title: const Text(
                'Ancestry Fan Chart',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'A semicircular ancestry chart built from your Family Tree.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, 'ancestry_fan_chart'),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.family_restroom_outlined, size: 34),
              title: const Text(
                'Family Group Sheet',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'A classic family page with couple, parents, and children.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, 'family_group_sheet'),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.grid_view_outlined, size: 34),
              title: const Text(
                'Collage',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Arrange several saved photos into a themed heritage page.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, 'collage'),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.photo_library_outlined, size: 34),
              title: Text(
                'Photo Story',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('Photos with captions and narrative — coming later.'),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.timeline_outlined, size: 34),
              title: Text(
                'Timeline',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('Chronological family events — coming later.'),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.inventory_2_outlined, size: 34),
              title: Text(
                'Heirloom Spotlight',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('Feature a keepsake and its story — coming later.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
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
              final isFanChart =
                  page.pageType == 'ancestry_fan_chart';
              final isFamilyGroup =
                  page.pageType == 'family_group_sheet';
              final isCollage =
                  page.pageType == 'collage';

              return Card(
                child: ListTile(
                  onTap: () => onPreview(page),
                  leading: Icon(
                    isFanChart
                        ? Icons.hub_outlined
                        : isFamilyGroup
                            ? Icons.family_restroom_outlined
                            : isCollage
                                ? Icons.grid_view_outlined
                                : Icons.description_outlined,
                  ),
                  title: Text(
                    isCollage
                        ? 'Photo Collage'
                        : person?.displayName ??
                            (isFanChart
                                ? 'Ancestry Fan Chart'
                                : isFamilyGroup
                                    ? 'Family Group Sheet'
                                    : 'Person Profile'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    isCollage
                        ? 'Collage • ${_collagePhotoCount(page)} photos'
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
          child: Divider(
            color: AtlasBookTheme.antiqueGoldSoft,
            thickness: 1,
          ),
        ),
        const SizedBox(width: 12),
        Icon(
          Icons.local_florist_outlined,
          size: 18,
          color: AtlasBookTheme.antiqueGold.withValues(alpha: 0.72),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Divider(
            color: AtlasBookTheme.antiqueGoldSoft,
            thickness: 1,
          ),
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
  State<_FanChartSetupDialog> createState() =>
      _FanChartSetupDialogState();
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

    Future<void> walk(
      int personId,
      int generation,
      int slot,
    ) async {
      if (generation >= _generationCount) return;
      if (!visited.add(personId)) return;

      final person =
          await widget.databaseHelper.getFamilyPerson(personId);
      if (person == null) return;

      nodes.add(
        _FanAncestorNode(
          person: person,
          generation: generation,
          slot: slot,
        ),
      );

      if (generation + 1 >= _generationCount) return;

      final parents =
          await widget.databaseHelper.getFamilyParents(personId);

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

        await walk(
          parentId,
          generation + 1,
          parentSlot,
        );
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
      title: Text(widget.isEditing ? 'Edit Ancestry Fan Chart' : 'Add Ancestry Fan Chart'),
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
                  size: Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
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
    final maxRadius = math.min(
      size.width * 0.47,
      size.height - 34,
    );
    final ringWidth = maxRadius / generationCount;

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var generation = 1;
        generation <= generationCount;
        generation++) {
      final radius = ringWidth * generation;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi,
        math.pi,
        false,
        linePaint,
      );
    }

    for (var generation = 1;
        generation < generationCount;
        generation++) {
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
        _drawRoot(
          canvas,
          center,
          ringWidth,
          node.person,
        );
        continue;
      }

      final slotCount = 1 << node.generation;
      final startAngle =
          math.pi + math.pi * node.slot / slotCount;
      final endAngle =
          math.pi + math.pi * (node.slot + 1) / slotCount;
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

      if (node.person.lifeSpan.isNotEmpty &&
          node.generation <= 3) {
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
      center: Offset(
        center.dx,
        center.dy - ringWidth * 0.48,
      ),
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

    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(12),
    );

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
      Offset(
        center.dx - painter.width / 2,
        center.dy - painter.height / 2,
      ),
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

class _WholeBookPreviewDialog extends StatefulWidget {
  final String bookTitle;
  final List<_BookPreviewPageData> pages;

  const _WholeBookPreviewDialog({
    required this.bookTitle,
    required this.pages,
  });

  @override
  State<_WholeBookPreviewDialog> createState() =>
      _WholeBookPreviewDialogState();
}

class _WholeBookPreviewDialogState
    extends State<_WholeBookPreviewDialog> {
  int _pageIndex = 0;

  void _previousPage() {
    if (_pageIndex <= 0) return;
    setState(() => _pageIndex--);
  }

  void _nextPage() {
    if (_pageIndex >= widget.pages.length - 1) return;
    setState(() => _pageIndex++);
  }

  Widget _buildPage(_BookPreviewPageData data) {
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
      return _FamilyGroupSheetPreview(
        data: data.familyGroupData!,
      );
    }

    if (data.person != null) {
      final profilePath = data.person!.profilePhotoPath;
      final heroPath = data.page.heroPhotoPath;
      final imagePath = heroPath.isNotEmpty && File(heroPath).existsSync()
          ? heroPath
          : profilePath.isNotEmpty && File(profilePath).existsSync()
              ? profilePath
              : null;

      return _PersonProfilePagePreview(
        person: data.person!,
        imagePath: imagePath,
      );
    }

    return Container(
      decoration: AtlasBookTheme.pageDecoration,
      child: const Center(
        child: Text('This page could not be previewed.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages[_pageIndex];

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1180,
        height: 820,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.menu_book_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.bookTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    'Page ${_pageIndex + 1} of ${widget.pages.length}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 16),
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
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerLowest,
                padding: const EdgeInsets.all(26),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 820,
                      maxHeight: 690,
                    ),
                    child: AspectRatio(
                      aspectRatio: 8.5 / 11,
                      child: _buildPage(page),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _pageIndex == 0 ? null : _previousPage,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                  ),
                  const Spacer(),
                  Text(
                    '${_pageIndex + 1} / ${widget.pages.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed:
                        _pageIndex == widget.pages.length - 1
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

    final spouses =
        await widget.databaseHelper.getFamilySpouses(primaryId);

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

    final primaryParents =
        await widget.databaseHelper.getFamilyParents(primaryId);

    final spouseId = selectedSpouse?.id;

    final spouseParents = spouseId == null
        ? <FamilyPerson>[]
        : await widget.databaseHelper.getFamilyParents(spouseId);

    final primaryChildren =
        await widget.databaseHelper.getFamilyChildren(primaryId);

    final children = <FamilyPerson>[];

    if (spouseId == null) {
      children.addAll(primaryChildren);
    } else {
      for (final child in primaryChildren) {
        final childId = child.id;
        if (childId == null) continue;

        final parents =
            await widget.databaseHelper.getFamilyParents(childId);

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
          : _spouses.firstWhere(
              (person) => person.id == spouseId,
            );
    });

    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit Family Group Sheet' : 'Add Family Group Sheet'),
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
          label: Text(widget.isEditing ? 'Save Changes' : 'Add Family Group Sheet'),
        ),
      ],
    );
  }
}

class _SavedFamilyGroupSheetPreviewDialog extends StatelessWidget {
  final _FamilyGroupSheetData data;

  const _SavedFamilyGroupSheetPreviewDialog({
    required this.data,
  });

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

  const _FamilyGroupSheetPreview({
    required this.data,
  });

  String _parentsText(List<FamilyPerson> parents) {
    if (parents.isEmpty) return 'Parents not recorded';

    return parents
        .map((person) => person.displayName)
        .join('  •  ');
  }

  Widget _portrait(
    BuildContext context,
    FamilyPerson person,
  ) {
    final path = person.profilePhotoPath;
    final hasPhoto =
        path.isNotEmpty && File(path).existsSync();

    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AtlasBookTheme.antiqueGold,
              width: 1.4,
            ),
          ),
          child: ClipOval(
            child: hasPhoto
                ? Image.file(
                    File(path),
                    fit: BoxFit.cover,
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
            style: AtlasBookTheme.subtitle(context).copyWith(
              fontSize: 12,
            ),
          ),
        ],
      ],
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
                Expanded(
                  child: _portrait(context, data.primary),
                ),
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
            const SizedBox(height: 26),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(125),
                1: FlexColumnWidth(),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: AtlasBookTheme.antiqueGoldSoft
                      .withValues(alpha: 0.55),
                ),
              ),
              children: [
                _detailRow(
                  context,
                  'Birth',
                  [
                    data.primary.birthDate,
                    data.primary.birthPlace,
                  ].where((value) => value.trim().isNotEmpty).join(' • '),
                ),
                _detailRow(
                  context,
                  'Parents',
                  _parentsText(data.primaryParents),
                ),
                if (spouse != null)
                  _detailRow(
                    context,
                    'Spouse birth',
                    [
                      spouse.birthDate,
                      spouse.birthPlace,
                    ].where((value) => value.trim().isNotEmpty).join(' • '),
                  ),
                if (spouse != null)
                  _detailRow(
                    context,
                    'Spouse parents',
                    _parentsText(data.spouseParents),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Children',
                style: AtlasBookTheme.sectionTitle(context).copyWith(
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(
              color: AtlasBookTheme.antiqueGoldSoft,
            ),
            if (data.children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No children are currently linked to this family.',
                  style: AtlasBookTheme.body(context),
                ),
              )
            else
              ...List.generate(
                data.children.length,
                (index) {
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
                            style: AtlasBookTheme.body(context).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            child.displayName,
                            style: AtlasBookTheme.body(context).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            [
                              child.birthDate,
                              child.birthPlace,
                            ]
                                .where(
                                  (value) =>
                                      value.trim().isNotEmpty,
                                )
                                .join(' • '),
                            style: AtlasBookTheme.body(context).copyWith(
                              fontSize: 13,
                            ),
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
    );
  }

  TableRow _detailRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 8,
          ),
          child: Text(
            label,
            style: AtlasBookTheme.sectionTitle(context).copyWith(
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 8,
          ),
          child: Text(
            value.trim().isEmpty ? 'Not recorded' : value,
            style: AtlasBookTheme.body(context).copyWith(
              fontSize: 13,
            ),
          ),
        ),
      ],
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

    _layoutKey = const {
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
    _manualTransforms = _decodeManualTransforms(
      widget.initialPhotoLayoutJson,
    );
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
                                    color:
                                        Theme.of(context).colorScheme.surface,
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
  final ValueChanged<Map<String, _ManualCollageTransform>>
      onTransformsChanged;

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
    final nextRotation =
        (current.rotation + radians).clamp(-0.60, 0.60);

    setState(() {
      _transforms[path] = current.copyWith(
        rotation: nextRotation,
      );
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
              style: AtlasBookTheme.subtitle(context).copyWith(
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
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

                for (var index = 0;
                    index < widget.photoPaths.length;
                    index++) {
                  final path = widget.photoPaths[index];
                  if (_transforms.containsKey(path)) continue;

                  final spec = autoSpecs[index];
                  _transforms[path] = _ManualCollageTransform(
                    centerX: (spec.left + spec.width / 2) /
                        constraints.maxWidth,
                    centerY: (spec.top + spec.height / 2) /
                        constraints.maxHeight,
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
                          painter:
                              _CorkTexturePainter(seed: widget.layoutSeed),
                        ),
                      ),
                      for (final path in ordered)
                        _buildDraggablePhoto(
                          context,
                          path,
                          constraints,
                        ),
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
    final left =
        transform.centerX * constraints.maxWidth - itemWidth / 2;
    final top =
        transform.centerY * constraints.maxHeight - itemHeight / 2;
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

                  final nextX =
                      (current.centerX + dx).clamp(halfW, 1.0 - halfW);
                  final nextY =
                      (current.centerY + dy).clamp(halfH, 1.0 - halfH);

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
                    final aspect =
                        current.height <= 0 ? 1.0 : current.width / current.height;

                    final delta =
                        (details.delta.dx + details.delta.dy) / 2;
                    final widthDelta = delta / constraints.maxWidth;

                    final newWidth =
                        (current.width + widthDelta).clamp(0.14, 0.70);
                    final newHeight =
                        (newWidth / aspect).clamp(0.12, 0.70);

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
                    final newRotation =
                        (current.rotation + rotationDelta).clamp(-0.60, 0.60);

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
        border: Border.all(
          color: AtlasBookTheme.antiqueGoldSoft,
          width: 1.2,
        ),
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
          if (index != photoPaths.length - 1)
            const SizedBox(height: 8),
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

          final isSof = marker >= 0xC0 &&
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
        final w = (data[16] << 24) |
            (data[17] << 16) |
            (data[18] << 8) |
            data[19];
        final h = (data[20] << 24) |
            (data[21] << 16) |
            (data[22] << 8) |
            data[23];
        if (w > 0 && h > 0) return w / h;
      }
    } catch (_) {}

    return 1.35;
  }

  List<_CorkboardPhotoSpec> _corkboardSpecs(
    double width,
    double height,
  ) {
    final random = math.Random(layoutSeed);
    final count = photoPaths.length;

    final anchorsByCount = <int, List<Offset>>{
      2: const [
        Offset(0.30, 0.30),
        Offset(0.70, 0.70),
      ],
      3: const [
        Offset(0.28, 0.27),
        Offset(0.72, 0.34),
        Offset(0.48, 0.73),
      ],
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

      var itemWidth =
          width * (baseWidth + (random.nextDouble() - 0.5) * 0.05);

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

      centerX = centerX.clamp(
        itemWidth / 2 + 10,
        width - itemWidth / 2 - 10,
      );
      centerY = centerY.clamp(
        itemHeight / 2 + 10,
        height - itemHeight / 2 - 10,
      );

      final rotation =
          (random.nextDouble() * 7.0 - 3.5) * math.pi / 180;

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
        final specs = List<_CorkboardPhotoSpec>.generate(
          photoPaths.length,
          (index) {
            final saved = savedTransforms[photoPaths[index]];
            if (saved == null) return autoSpecs[index];

            return _CorkboardPhotoSpec(
              left: saved.centerX * constraints.maxWidth -
                  saved.width * constraints.maxWidth / 2,
              top: saved.centerY * constraints.maxHeight -
                  saved.height * constraints.maxHeight / 2,
              width: saved.width * constraints.maxWidth,
              height: saved.height * constraints.maxHeight,
              rotation: saved.rotation,
            );
          },
        );

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
                          Positioned.fill(
                            child: _photo(photoPaths[index]),
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
              style: AtlasBookTheme.subtitle(context).copyWith(
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
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

  const _CorkTexturePainter({
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed ^ 0x5A17);
    final paint = Paint();

    for (var i = 0; i < 320; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = 0.35 + random.nextDouble() * 1.2;
      final dark = random.nextBool();

      paint.color = (dark
              ? const Color(0xFF6F472C)
              : const Color(0xFFE0B47D))
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

  const _PersonProfilePageResult({
    required this.personId,
    this.heroPhotoPath,
  });
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
    _heroPhotoPath = initialHero != null &&
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
      title: Text(widget.isEditing ? 'Edit Person Profile Page' : 'Add Person Profile Page'),
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
    final imagePath = heroPhotoPath.isNotEmpty &&
            File(heroPhotoPath).existsSync()
        ? heroPhotoPath
        : profilePath.isNotEmpty && File(profilePath).existsSync()
            ? profilePath
            : null;

    return AlertDialog(
      title: const Text('Person Profile Preview'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: _PersonProfilePagePreview(
          person: person,
          imagePath: imagePath,
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

class _PersonProfilePagePreview extends StatelessWidget {
  final FamilyPerson person;
  final String? imagePath;

  const _PersonProfilePagePreview({
    required this.person,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage =
        imagePath != null && File(imagePath!).existsSync();

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
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
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
                FilledButton(
                  onPressed: onTap,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
