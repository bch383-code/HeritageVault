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
    }
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
  final ValueChanged<AtlasBookPage> onDelete;
  final ValueChanged<int> onMoveUp;
  final ValueChanged<int> onMoveDown;

  const _BookPagesPanel({
    required this.loading,
    required this.pages,
    required this.people,
    required this.onAddPage,
    required this.onPreview,
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

              return Card(
                child: ListTile(
                  onTap: () => onPreview(page),
                  leading: Icon(
                    isFanChart
                        ? Icons.hub_outlined
                        : isFamilyGroup
                            ? Icons.family_restroom_outlined
                            : Icons.description_outlined,
                  ),
                  title: Text(
                    person?.displayName ??
                        (isFanChart
                            ? 'Ancestry Fan Chart'
                            : isFamilyGroup
                                ? 'Family Group Sheet'
                                : 'Person Profile'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    isFanChart
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

  const _FanChartSetupDialog({
    required this.people,
    required this.databaseHelper,
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
    _rootPerson = widget.people.first;
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
      title: const Text('Add Ancestry Fan Chart'),
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
          label: const Text('Add Fan Chart'),
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

  const _BookPreviewPageData({
    required this.page,
    this.person,
    this.fanNodes,
    this.familyGroupData,
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

  const _FamilyGroupSheetSetupDialog({
    required this.people,
    required this.databaseHelper,
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
    _primary = widget.people.first;
    _refresh();
  }

  Future<void> _refresh() async {
    final primaryId = _primary.id;
    if (primaryId == null) return;

    setState(() => _loading = true);

    final spouses =
        await widget.databaseHelper.getFamilySpouses(primaryId);

    FamilyPerson? selectedSpouse = _spouse;

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
      title: const Text('Add Family Group Sheet'),
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
          label: const Text('Add Family Group Sheet'),
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

  const _PersonProfilePageDialog({
    required this.people,
    required this.photoPaths,
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
    _person = widget.people.first;
    _heroPhotoPath =
        widget.photoPaths.isEmpty ? null : widget.photoPaths.first;
  }

  @override
  Widget build(BuildContext context) {
    final profilePath = _person.profilePhotoPath;
    final hasProfilePhoto =
        profilePath.isNotEmpty && File(profilePath).existsSync();
    final heroPath = _heroPhotoPath;
    final hasHero = heroPath != null && File(heroPath).existsSync();

    return AlertDialog(
      title: const Text('Add Person Profile Page'),
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
          label: const Text('Add Person Profile'),
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
