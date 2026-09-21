import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';

class FamilyVisualTreeScreen extends StatefulWidget {
  final FamilyPerson initialPerson;

  const FamilyVisualTreeScreen({super.key, required this.initialPerson});

  @override
  State<FamilyVisualTreeScreen> createState() => _FamilyVisualTreeScreenState();
}

class _FamilyVisualTreeScreenState extends State<FamilyVisualTreeScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _treeViewportKey = GlobalKey();

  late FamilyPerson _focus;
  FamilyPerson? _selectedPerson;
  double _currentScale = 1.0;

  final List<FamilyPerson> _navigationBackStack = <FamilyPerson>[];
  final List<FamilyPerson> _navigationForwardStack = <FamilyPerson>[];

  List<FamilyPerson> _parents = const [];
  List<FamilyPerson> _spouses = const [];
  List<FamilyPerson> _children = const [];

  final Map<int, List<FamilyPerson>> _grandparentsByParent = {};
  final Map<int, List<FamilyPerson>> _grandchildrenByChild = {};

  // For each child of the focused person, remember the other recorded parent
  // when that parent is also one of the focused person's spouses.
  final Map<int, int?> _coParentByChild = {};

  bool _showGrandparents = true;
  bool _showGrandchildren = true;
  bool _loading = true;

  static const double _cardWidth = 210;
  static const double _cardHeight = 145;
  static const double _rowGap = 185;
  static const double _horizontalGap = 250;

  @override
  void initState() {
    super.initState();
    _focus = widget.initialPerson;
    _selectedPerson = widget.initialPerson;
    _load();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _focus.id;
    if (id == null) return;

    setState(() => _loading = true);

    final refreshed = await _databaseHelper.getFamilyPerson(id);
    final parents = await _databaseHelper.getFamilyParents(id);
    final spouses = await _databaseHelper.getFamilySpouses(id);
    final children = await _databaseHelper.getFamilyChildren(id);

    final grandparents = <int, List<FamilyPerson>>{};
    if (_showGrandparents) {
      for (final parent in parents) {
        final parentId = parent.id;
        if (parentId == null) continue;
        grandparents[parentId] = await _databaseHelper.getFamilyParents(
          parentId,
        );
      }
    }

    final spouseIds = spouses
        .map((person) => person.id)
        .whereType<int>()
        .toSet();
    final coParentByChild = <int, int?>{};

    for (final child in children) {
      final childId = child.id;
      if (childId == null) continue;

      final childParents = await _databaseHelper.getFamilyParents(childId);
      int? coParentId;

      for (final parent in childParents) {
        final parentId = parent.id;
        if (parentId != null &&
            parentId != id &&
            spouseIds.contains(parentId)) {
          coParentId = parentId;
          break;
        }
      }

      coParentByChild[childId] = coParentId;
    }

    final grandchildren = <int, List<FamilyPerson>>{};
    if (_showGrandchildren) {
      for (final child in children) {
        final childId = child.id;
        if (childId == null) continue;
        grandchildren[childId] = await _databaseHelper.getFamilyChildren(
          childId,
        );
      }
    }

    if (!mounted) return;

    setState(() {
      if (refreshed != null) {
        _focus = refreshed;
      }
      _parents = parents;
      _spouses = spouses;
      _children = children;

      _coParentByChild
        ..clear()
        ..addAll(coParentByChild);

      _grandparentsByParent
        ..clear()
        ..addAll(grandparents);

      _grandchildrenByChild
        ..clear()
        ..addAll(grandchildren);

      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerTree();
    });
  }

  void _centerTree() {
    if (!mounted) return;

    final viewportContext = _treeViewportKey.currentContext;
    final renderBox = viewportContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final layout = _buildLayout();
    _TreeNode? focusNode;
    for (final node in layout.nodes) {
      if (node.isFocus) {
        focusNode = node;
        break;
      }
    }
    if (focusNode == null) return;

    final viewportSize = renderBox.size;
    final focusCenter = Offset(
      focusNode.position.dx + _cardWidth / 2,
      focusNode.position.dy + _cardHeight / 2,
    );

    // Center the highlighted person inside the actually visible tree area.
    // The inspector is a sibling of this viewport, so its width is naturally
    // excluded instead of allowing the focus card to sit underneath it.
    final dx = viewportSize.width / 2 - focusCenter.dx;
    var dy = viewportSize.height / 2 - focusCenter.dy;

    // Keep the highest visible generation comfortably below the top edge of
    // the tree viewport. Center the highlighted person normally, then shift
    // the whole tree down only when that centered position would clip the
    // top row.
    if (layout.nodes.isNotEmpty) {
      final topNodeY = layout.nodes
          .map((node) => node.position.dy)
          .reduce(math.min);
      const topPadding = 28.0;
      final transformedTopY = topNodeY + dy;
      if (transformedTopY < topPadding) {
        dy += topPadding - transformedTopY;
      }
    }

    _transformationController.value = Matrix4.translationValues(dx, dy, 0);
    setState(() => _currentScale = 1.0);
  }

  void _setZoom(double scale) {
    final next = scale.clamp(0.35, 2.5).toDouble();
    final matrix = Matrix4.identity()..scale(next);
    _transformationController.value = matrix;
    setState(() => _currentScale = next);
  }

  void _zoomIn() => _setZoom(_currentScale + 0.15);
  void _zoomOut() => _setZoom(_currentScale - 0.15);

  void _selectPerson(FamilyPerson person) {
    setState(() => _selectedPerson = person);
  }

  Future<void> _recenter(
    FamilyPerson person, {
    bool recordHistory = true,
  }) async {
    if (person.id == null || person.id == _focus.id) return;

    if (recordHistory) {
      _navigationBackStack.add(_focus);
      _navigationForwardStack.clear();
    }

    setState(() {
      _focus = person;
      _selectedPerson = person;
    });

    await _load();
  }

  Future<void> _goBackInTree() async {
    if (_navigationBackStack.isEmpty) return;

    final previous = _navigationBackStack.removeLast();
    _navigationForwardStack.add(_focus);

    setState(() {
      _focus = previous;
      _selectedPerson = previous;
    });

    await _load();
  }

  Future<void> _goForwardInTree() async {
    if (_navigationForwardStack.isEmpty) return;

    final next = _navigationForwardStack.removeLast();
    _navigationBackStack.add(_focus);

    setState(() {
      _focus = next;
      _selectedPerson = next;
    });

    await _load();
  }

  Future<void> _openProfile(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FamilyPersonScreen(person: person)),
    );

    await _load();
  }

  Future<void> _findPerson() async {
    final controller = TextEditingController();
    List<FamilyPerson> results = const [];
    List<FamilyPerson> recent = const [];
    bool loadingRecent = true;

    final recentSetting = await _databaseHelper.getSetting(
      'family_frequent_people',
    );
    if (recentSetting != null && recentSetting.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(recentSetting);
        if (decoded is Map) {
          final counts = decoded['counts'];
          final lastViewed = decoded['lastViewed'];

          final rankedIds = <int>{};
          if (counts is Map) {
            for (final entry in counts.entries) {
              final id = int.tryParse(entry.key.toString());
              final count = int.tryParse(entry.value.toString()) ?? 0;
              if (id != null && count > 0) rankedIds.add(id);
            }
          }

          final lastViewedById = <int, int>{};
          if (lastViewed is Map) {
            for (final entry in lastViewed.entries) {
              final id = int.tryParse(entry.key.toString());
              final millis = int.tryParse(entry.value.toString());
              if (id != null && millis != null) {
                lastViewedById[id] = millis;
                rankedIds.add(id);
              }
            }
          }

          final allPeople = await _databaseHelper.getFamilyPeople();
          final peopleById = <int, FamilyPerson>{
            for (final person in allPeople)
              if (person.id != null) person.id!: person,
          };

          final ids = rankedIds.toList()
            ..sort(
              (a, b) =>
                  (lastViewedById[b] ?? 0).compareTo(lastViewedById[a] ?? 0),
            );

          recent = ids
              .map((id) => peopleById[id])
              .whereType<FamilyPerson>()
              .take(5)
              .toList();
        }
      } catch (_) {}
    }
    loadingRecent = false;

    if (!mounted) {
      controller.dispose();
      return;
    }

    final chosen = await showDialog<FamilyPerson>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> search(String value) async {
              final query = value.trim();

              if (query.isEmpty) {
                setDialogState(() => results = const []);
                return;
              }

              final people = await _databaseHelper.getFamilyPeople(
                searchText: query,
              );

              if (!dialogContext.mounted) return;

              setDialogState(() {
                results = people.take(50).toList();
              });
            }

            final showingRecent = controller.text.trim().isEmpty;

            return AlertDialog(
              title: const Text('Find Person'),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search by name or place',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (showingRecent && !loadingRecent && recent.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 2, 4, 8),
                        child: Text(
                          'RECENTLY VIEWED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    Expanded(
                      child: showingRecent
                          ? loadingRecent
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : recent.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Recently viewed people will appear here.',
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: recent.length,
                                    itemBuilder: (context, index) {
                                      final person = recent[index];
                                      return ListTile(
                                        leading: const CircleAvatar(
                                          child: Icon(Icons.history_outlined),
                                        ),
                                        title: Text(person.displayName),
                                        subtitle: Text(
                                          [
                                            if (person.lifeSpan.isNotEmpty)
                                              person.lifeSpan,
                                            if (person.birthPlace.isNotEmpty)
                                              person.birthPlace,
                                          ].join(' • '),
                                        ),
                                        onTap: () => Navigator.pop(
                                          dialogContext,
                                          person,
                                        ),
                                      );
                                    },
                                  )
                          : results.isEmpty
                          ? const Center(
                              child: Text('No people match this search.'),
                            )
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (context, index) {
                                final person = results[index];

                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline),
                                  ),
                                  title: Text(person.displayName),
                                  subtitle: Text(
                                    [
                                      if (person.lifeSpan.isNotEmpty)
                                        person.lifeSpan,
                                      if (person.birthPlace.isNotEmpty)
                                        person.birthPlace,
                                    ].join(' • '),
                                  ),
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
        );
      },
    );

    controller.dispose();

    if (chosen != null) {
      await _recenter(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = _buildLayout();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Tree'),
        actions: [
          IconButton(
            tooltip: 'Find person',
            onPressed: _findPerson,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Center tree',
            onPressed: _centerTree,
            icon: const Icon(Icons.center_focus_strong),
          ),
          IconButton(
            tooltip: 'Open profile',
            onPressed: () => _openProfile(_focus),
            icon: const Icon(Icons.person_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildToolbar(),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox.expand(
                          key: _treeViewportKey,
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            minScale: 0.35,
                            maxScale: 2.5,
                            boundaryMargin: const EdgeInsets.all(1200),
                            constrained: false,
                            onInteractionEnd: (_) {
                              final scale = _transformationController.value
                                  .getMaxScaleOnAxis();
                              if (mounted) {
                                setState(() => _currentScale = scale);
                              }
                            },
                            child: SizedBox(
                              width: layout.canvasWidth,
                              height: layout.canvasHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _FamilyTreeLinePainter(
                                        edges: layout.edges,
                                      ),
                                    ),
                                  ),
                                  for (final node in layout.nodes)
                                    Positioned(
                                      left: node.position.dx,
                                      top: node.position.dy,
                                      child: _personCard(
                                        node.person,
                                        highlighted: node.isFocus,
                                        selected:
                                            _selectedPerson?.id ==
                                            node.person.id,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_selectedPerson != null)
                        _buildPersonInspector(_selectedPerson!),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildToolbar() {
    final percent = (_currentScale * 100).round();

    return Material(
      color: const Color(0xFF081E33),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x55C9A65A))),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.account_tree_outlined,
              size: 20,
              color: Color(0xFFC9A65A),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Back to previous person',
              onPressed: _navigationBackStack.isEmpty ? null : _goBackInTree,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: 'Forward',
              onPressed: _navigationForwardStack.isEmpty
                  ? null
                  : _goForwardInTree,
              icon: const Icon(Icons.arrow_forward),
            ),
            const SizedBox(width: 6),
            Text(
              _focus.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF3E9D1),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 16),
            FilterChip(
              selected: _showGrandparents,
              label: const Text('Grandparents'),
              onSelected: (value) async {
                setState(() => _showGrandparents = value);
                await _load();
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _showGrandchildren,
              label: const Text('Grandchildren'),
              onSelected: (value) async {
                setState(() => _showGrandchildren = value);
                await _load();
              },
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: _zoomOut,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 54,
              child: Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF3E9D1),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: _zoomIn,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 4),
            OutlinedButton.icon(
              onPressed: _centerTree,
              icon: const Icon(Icons.center_focus_strong, size: 18),
              label: const Text('Center'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _findPerson,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Find'),
            ),
          ],
        ),
      ),
    );
  }

  String? _relationshipToFocus(FamilyPerson person) {
    final personId = person.id;
    final focusId = _focus.id;
    if (personId == null || focusId == null) return null;
    if (personId == focusId) return 'Highlighted person';

    if (_parents.any((p) => p.id == personId)) return 'Parent';
    if (_spouses.any((p) => p.id == personId)) return 'Spouse';
    if (_children.any((p) => p.id == personId)) return 'Child';

    for (final grandparents in _grandparentsByParent.values) {
      if (grandparents.any((p) => p.id == personId)) return 'Grandparent';
    }
    for (final grandchildren in _grandchildrenByChild.values) {
      if (grandchildren.any((p) => p.id == personId)) return 'Grandchild';
    }
    return null;
  }

  Widget _buildPersonInspector(FamilyPerson person) {
    final path = person.profilePhotoPath;
    final hasPhoto = path.isNotEmpty && File(path).existsSync();
    final relationship = _relationshipToFocus(person);

    Widget detail(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFC9A65A)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: const Color(0xFFC9A65A).withValues(alpha: .78),
                      fontSize: 9,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFFF3E9D1),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 310,
      decoration: const BoxDecoration(
        color: Color(0xFF081E33),
        border: Border(left: BorderSide(color: Color(0x66C9A65A))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'PERSON',
                    style: TextStyle(
                      color: Color(0xFFC9A65A),
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => setState(() => _selectedPerson = null),
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 45,
                      backgroundImage: hasPhoto ? FileImage(File(path)) : null,
                      child: hasPhoto
                          ? null
                          : const Icon(Icons.person_outline, size: 42),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Center(
                    child: Text(
                      person.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFF3E9D1),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (person.lifeSpan.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        person.lifeSpan,
                        style: TextStyle(
                          color: const Color(0xFFF3E9D1).withValues(alpha: .68),
                        ),
                      ),
                    ),
                  ],
                  if (relationship != null) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC9A65A).withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(
                              0xFFC9A65A,
                            ).withValues(alpha: .55),
                          ),
                        ),
                        child: Text(
                          relationship,
                          style: const TextStyle(
                            color: Color(0xFFE3C575),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .35,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(color: Color(0x44C9A65A)),
                  const SizedBox(height: 14),
                  detail(
                    Icons.cake_outlined,
                    'Birth',
                    [
                      person.birthDate,
                      person.birthPlace,
                    ].where((v) => v.trim().isNotEmpty).join(' • '),
                  ),
                  detail(
                    Icons.church_outlined,
                    'Death',
                    [
                      person.deathDate,
                      person.deathPlace,
                    ].where((v) => v.trim().isNotEmpty).join(' • '),
                  ),
                  if (person.birthName.trim().isNotEmpty)
                    detail(
                      Icons.badge_outlined,
                      'Birth name',
                      person.birthName,
                    ),
                  if (person.biography.trim().isNotEmpty)
                    detail(
                      Icons.menu_book_outlined,
                      'Biography',
                      person.biography,
                    ),
                  if (person.notes.trim().isNotEmpty)
                    detail(Icons.notes_outlined, 'Notes', person.notes),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _recenter(person),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Center Tree Here'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openProfile(person),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Open Full Profile'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _TreeLayout _buildLayout() {
    final grandparents = _showGrandparents
        ? _grandparentsByParent.values.expand((items) => items).toList()
        : <FamilyPerson>[];

    final grandchildren = _showGrandchildren
        ? _grandchildrenByChild.values.expand((items) => items).toList()
        : <FamilyPerson>[];

    // Keep the focused person at the visual center. Spouses are arranged
    // around them so each couple can have its own child branch.
    final focusRowCount = math.max(1, 1 + _spouses.length);

    final largestRow = [
      grandparents.length,
      _parents.length,
      focusRowCount,
      _children.length,
      grandchildren.length,
    ].fold<int>(1, math.max);

    final spouseSpread = math.max(1, _spouses.length) * _horizontalGap;
    final canvasWidth = math.max(
      1500.0,
      math.max(largestRow * _horizontalGap + 600, spouseSpread + 1000),
    );

    final rowIndexes = <String, int>{};
    var row = 0;

    if (_showGrandparents) {
      rowIndexes['grandparents'] = row++;
    }

    rowIndexes['parents'] = row++;
    rowIndexes['focus'] = row++;
    rowIndexes['children'] = row++;

    if (_showGrandchildren) {
      rowIndexes['grandchildren'] = row++;
    }

    final canvasHeight = math.max(1000.0, row * _rowGap + 380);

    final nodes = <_TreeNode>[];
    final positions = <int, Offset>{};

    Offset addNodeAtX(
      FamilyPerson person,
      double centerX,
      int rowIndex, {
      bool isFocus = false,
    }) {
      final x = centerX - _cardWidth / 2;
      final y = 120.0 + rowIndex * _rowGap;
      final offset = Offset(x, y);

      if (person.id != null) {
        positions[person.id!] = offset;
      }

      nodes.add(_TreeNode(person: person, position: offset, isFocus: isFocus));
      return offset;
    }

    Offset addRowNode(
      FamilyPerson person,
      int index,
      int count,
      int rowIndex, {
      bool isFocus = false,
    }) {
      final totalWidth = count <= 1 ? 0.0 : (count - 1) * _horizontalGap;
      final centerX = canvasWidth / 2 - totalWidth / 2 + index * _horizontalGap;

      return addNodeAtX(person, centerX, rowIndex, isFocus: isFocus);
    }

    if (_showGrandparents && rowIndexes['grandparents'] != null) {
      for (var i = 0; i < grandparents.length; i++) {
        addRowNode(
          grandparents[i],
          i,
          grandparents.length,
          rowIndexes['grandparents']!,
        );
      }
    }

    for (var i = 0; i < _parents.length; i++) {
      addRowNode(_parents[i], i, _parents.length, rowIndexes['parents']!);
    }

    final focusCenterX = canvasWidth / 2;
    addNodeAtX(_focus, focusCenterX, rowIndexes['focus']!, isFocus: true);

    // One spouse sits to the right. With multiple spouses, alternate left and
    // right so separate family units remain visually distinct.
    final spouseCenterById = <int, double>{};
    for (var i = 0; i < _spouses.length; i++) {
      final spouse = _spouses[i];
      final pairNumber = i ~/ 2 + 1;
      final direction = _spouses.length == 1 ? 1.0 : (i.isEven ? -1.0 : 1.0);
      final centerX = focusCenterX + direction * pairNumber * _horizontalGap;

      addNodeAtX(spouse, centerX, rowIndexes['focus']!);
      if (spouse.id != null) {
        spouseCenterById[spouse.id!] = centerX;
      }
    }

    // Group children by the other recorded parent. A null key means no
    // spouse/co-parent is recorded for that child.
    final childrenByCoParent = <int?, List<FamilyPerson>>{};
    for (final child in _children) {
      final childId = child.id;
      final coParentId = childId == null ? null : _coParentByChild[childId];
      childrenByCoParent.putIfAbsent(coParentId, () => []).add(child);
    }

    // Position each child group beneath the midpoint of its parents. Keep a
    // minimum horizontal separation so sibling/family groups do not overlap.
    final desiredChildCenters = <FamilyPerson, double>{};
    for (final entry in childrenByCoParent.entries) {
      final coParentId = entry.key;
      final familyChildren = entry.value;

      final spouseCenter = coParentId == null
          ? null
          : spouseCenterById[coParentId];
      final familyCenter = spouseCenter == null
          ? focusCenterX
          : (focusCenterX + spouseCenter) / 2;

      final totalWidth = familyChildren.length <= 1
          ? 0.0
          : (familyChildren.length - 1) * _horizontalGap;

      for (var i = 0; i < familyChildren.length; i++) {
        desiredChildCenters[familyChildren[i]] =
            familyCenter - totalWidth / 2 + i * _horizontalGap;
      }
    }

    // Resolve any collisions created by neighboring family groups while
    // preserving their left-to-right family grouping.
    final orderedChildren = desiredChildCenters.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    const minimumChildSpacing = _horizontalGap;
    for (var i = 1; i < orderedChildren.length; i++) {
      final previous = orderedChildren[i - 1];
      final current = orderedChildren[i];
      final minimumX = previous.value + minimumChildSpacing;
      if (current.value < minimumX) {
        orderedChildren[i] = MapEntry(current.key, minimumX);
      }
    }

    if (orderedChildren.isNotEmpty) {
      final minX = orderedChildren.first.value;
      final maxX = orderedChildren.last.value;
      final groupCenter = (minX + maxX) / 2;
      final shift = focusCenterX - groupCenter;

      for (final entry in orderedChildren) {
        addNodeAtX(entry.key, entry.value + shift, rowIndexes['children']!);
      }
    }

    if (_showGrandchildren && rowIndexes['grandchildren'] != null) {
      for (var i = 0; i < grandchildren.length; i++) {
        addRowNode(
          grandchildren[i],
          i,
          grandchildren.length,
          rowIndexes['grandchildren']!,
        );
      }
    }

    final edges = <_TreeEdge>[];

    Offset? centerOf(int? id) {
      if (id == null) return null;
      final topLeft = positions[id];
      if (topLeft == null) return null;

      return Offset(topLeft.dx + _cardWidth / 2, topLeft.dy + _cardHeight / 2);
    }

    final focusCenter = centerOf(_focus.id);

    for (final parent in _parents) {
      final parentCenter = centerOf(parent.id);

      if (parentCenter != null && focusCenter != null) {
        edges.add(
          _TreeEdge(
            from: Offset(parentCenter.dx, parentCenter.dy + _cardHeight / 2),
            to: Offset(focusCenter.dx, focusCenter.dy - _cardHeight / 2),
          ),
        );
      }

      if (_showGrandparents && parent.id != null) {
        final list = _grandparentsByParent[parent.id!] ?? const [];

        for (final grandparent in list) {
          final grandCenter = centerOf(grandparent.id);

          if (grandCenter != null && parentCenter != null) {
            edges.add(
              _TreeEdge(
                from: Offset(grandCenter.dx, grandCenter.dy + _cardHeight / 2),
                to: Offset(parentCenter.dx, parentCenter.dy - _cardHeight / 2),
              ),
            );
          }
        }
      }
    }

    // Gold lines identify each spouse/couple. Children with both parents
    // recorded branch from that couple's midpoint rather than directly from
    // the focused person.
    final unionCenterBySpouseId = <int, Offset>{};

    for (final spouse in _spouses) {
      final spouseCenter = centerOf(spouse.id);

      if (spouseCenter != null && focusCenter != null) {
        edges.add(
          _TreeEdge(from: focusCenter, to: spouseCenter, isSpouse: true),
        );

        if (spouse.id != null) {
          unionCenterBySpouseId[spouse.id!] = Offset(
            (focusCenter.dx + spouseCenter.dx) / 2,
            focusCenter.dy,
          );
        }
      }
    }

    for (final child in _children) {
      final childCenter = centerOf(child.id);

      if (childCenter != null && focusCenter != null) {
        final childId = child.id;
        final coParentId = childId == null ? null : _coParentByChild[childId];
        final unionCenter = coParentId == null
            ? null
            : unionCenterBySpouseId[coParentId];

        final branchStart = unionCenter == null
            ? Offset(focusCenter.dx, focusCenter.dy + _cardHeight / 2)
            : unionCenter;

        edges.add(
          _TreeEdge(
            from: branchStart,
            to: Offset(childCenter.dx, childCenter.dy - _cardHeight / 2),
            isUnionBranch: unionCenter != null,
          ),
        );
      }

      if (_showGrandchildren && child.id != null) {
        final list = _grandchildrenByChild[child.id!] ?? const [];

        for (final grandchild in list) {
          final grandchildCenter = centerOf(grandchild.id);

          if (grandchildCenter != null && childCenter != null) {
            edges.add(
              _TreeEdge(
                from: Offset(childCenter.dx, childCenter.dy + _cardHeight / 2),
                to: Offset(
                  grandchildCenter.dx,
                  grandchildCenter.dy - _cardHeight / 2,
                ),
              ),
            );
          }
        }
      }
    }

    return _TreeLayout(
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      nodes: nodes,
      edges: edges,
    );
  }

  Widget _personCard(
    FamilyPerson person, {
    bool highlighted = false,
    bool selected = false,
  }) {
    final path = person.profilePhotoPath;
    final hasPhoto = path.isNotEmpty && File(path).existsSync();

    return SizedBox(
      width: _cardWidth,
      height: _cardHeight,
      child: Card(
        elevation: highlighted ? 8 : 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: highlighted
                ? const Color(0xFFC9A65A)
                : selected
                ? const Color(0xFF7F9CB5)
                : Colors.transparent,
            width: highlighted
                ? 2.2
                : selected
                ? 1.6
                : 0,
          ),
        ),
        child: InkWell(
          onTap: () => _selectPerson(person),
          onDoubleTap: () => _recenter(person),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: hasPhoto ? FileImage(File(path)) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person_outline, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: highlighted
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                      if (person.lifeSpan.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          person.lifeSpan,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (highlighted) ...[
                        const SizedBox(height: 5),
                        Text(
                          'HOME OF THIS VIEW',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeNode {
  final FamilyPerson person;
  final Offset position;
  final bool isFocus;

  const _TreeNode({
    required this.person,
    required this.position,
    required this.isFocus,
  });
}

class _TreeEdge {
  final Offset from;
  final Offset to;
  final bool isSpouse;
  final bool isUnionBranch;

  const _TreeEdge({
    required this.from,
    required this.to,
    this.isSpouse = false,
    this.isUnionBranch = false,
  });
}

class _TreeLayout {
  final double canvasWidth;
  final double canvasHeight;
  final List<_TreeNode> nodes;
  final List<_TreeEdge> edges;

  const _TreeLayout({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.nodes,
    required this.edges,
  });
}

class _FamilyTreeLinePainter extends CustomPainter {
  final List<_TreeEdge> edges;

  const _FamilyTreeLinePainter({required this.edges});

  @override
  void paint(Canvas canvas, Size size) {
    final normalPaint = Paint()
      ..color = const Color(0xFF6F8293)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final spousePaint = Paint()
      ..color = const Color(0xFFC9A65A)
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final paint = edge.isSpouse ? spousePaint : normalPaint;

      if (edge.isSpouse) {
        canvas.drawLine(edge.from, edge.to, paint);
        continue;
      }

      if (edge.isUnionBranch) {
        // Drop straight down from the couple's union point. Keep the
        // horizontal child run below the person cards so it never appears
        // to pass through the focused person's card.
        final cardBottomY =
            edge.from.dy + _FamilyVisualTreeScreenState._cardHeight / 2;
        final childTopY = edge.to.dy;
        final branchY =
            cardBottomY + math.max(26.0, (childTopY - cardBottomY) * .34);

        final path = Path()
          ..moveTo(edge.from.dx, edge.from.dy)
          ..lineTo(edge.from.dx, branchY)
          ..lineTo(edge.to.dx, branchY)
          ..lineTo(edge.to.dx, edge.to.dy);
        canvas.drawPath(path, paint);
        continue;
      }

      final midpointY = (edge.from.dy + edge.to.dy) / 2;

      final path = Path()
        ..moveTo(edge.from.dx, edge.from.dy)
        ..lineTo(edge.from.dx, midpointY)
        ..lineTo(edge.to.dx, midpointY)
        ..lineTo(edge.to.dx, edge.to.dy);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FamilyTreeLinePainter oldDelegate) {
    return oldDelegate.edges != edges;
  }
}
