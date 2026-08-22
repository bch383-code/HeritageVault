import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';

class FamilyVisualTreeScreen extends StatefulWidget {
  final FamilyPerson initialPerson;

  const FamilyVisualTreeScreen({
    super.key,
    required this.initialPerson,
  });

  @override
  State<FamilyVisualTreeScreen> createState() =>
      _FamilyVisualTreeScreenState();
}

class _FamilyVisualTreeScreenState
    extends State<FamilyVisualTreeScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TransformationController _transformationController =
      TransformationController();

  late FamilyPerson _focus;

  List<FamilyPerson> _parents = const [];
  List<FamilyPerson> _spouses = const [];
  List<FamilyPerson> _children = const [];

  final Map<int, List<FamilyPerson>> _grandparentsByParent = {};
  final Map<int, List<FamilyPerson>> _grandchildrenByChild = {};

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
        grandparents[parentId] =
            await _databaseHelper.getFamilyParents(parentId);
      }
    }

    final grandchildren = <int, List<FamilyPerson>>{};
    if (_showGrandchildren) {
      for (final child in children) {
        final childId = child.id;
        if (childId == null) continue;
        grandchildren[childId] =
            await _databaseHelper.getFamilyChildren(childId);
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
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _recenter(FamilyPerson person) async {
    if (person.id == null) return;

    setState(() {
      _focus = person;
    });

    await _load();
  }

  Future<void> _openProfile(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyPersonScreen(person: person),
      ),
    );

    await _load();
  }

  Future<void> _findPerson() async {
    final controller = TextEditingController();
    List<FamilyPerson> results = const [];

    final chosen = await showDialog<FamilyPerson>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> search(String value) async {
              final people = await _databaseHelper.getFamilyPeople(
                searchText: value,
              );

              if (!dialogContext.mounted) return;

              setDialogState(() {
                results = people.take(50).toList();
              });
            }

            return AlertDialog(
              title: const Text('Find Person'),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
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
                    Expanded(
                      child: results.isEmpty
                          ? const Center(
                              child: Text('Type to search the family tree.'),
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
                                  onTap: () => Navigator.pop(
                                    dialogContext,
                                    person,
                                  ),
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
        title: Text('Family Tree — ${_focus.displayName}'),
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
                  child: InteractiveViewer(
                    transformationController:
                        _transformationController,
                    minScale: 0.35,
                    maxScale: 2.5,
                    boundaryMargin: const EdgeInsets.all(1200),
                    constrained: false,
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
  }

  Widget _buildToolbar() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Generations',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 14),
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
            const Text(
              'Click a person to recenter • Double-click opens profile',
            ),
          ],
        ),
      ),
    );
  }

  _TreeLayout _buildLayout() {
    final grandparents = _showGrandparents
        ? _grandparentsByParent.values
            .expand((items) => items)
            .toList()
        : <FamilyPerson>[];

    final grandchildren = _showGrandchildren
        ? _grandchildrenByChild.values
            .expand((items) => items)
            .toList()
        : <FamilyPerson>[];

    final focusRowCount = math.max(1, 1 + _spouses.length);

    final largestRow = [
      grandparents.length,
      _parents.length,
      focusRowCount,
      _children.length,
      grandchildren.length,
    ].fold<int>(1, math.max);

    final canvasWidth = math.max(
      1400.0,
      largestRow * _horizontalGap + 500,
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

    final canvasHeight = math.max(
      1000.0,
      row * _rowGap + 380,
    );

    final nodes = <_TreeNode>[];
    final positions = <int, Offset>{};

    Offset addRowNode(
      FamilyPerson person,
      int index,
      int count,
      int rowIndex, {
      bool isFocus = false,
    }) {
      final totalWidth =
          count <= 1 ? 0.0 : (count - 1) * _horizontalGap;

      final x =
          (canvasWidth - _cardWidth) / 2 -
          totalWidth / 2 +
          index * _horizontalGap;

      final y = 120.0 + rowIndex * _rowGap;

      final offset = Offset(x, y);

      if (person.id != null) {
        positions[person.id!] = offset;
      }

      nodes.add(
        _TreeNode(
          person: person,
          position: offset,
          isFocus: isFocus,
        ),
      );

      return offset;
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
      addRowNode(
        _parents[i],
        i,
        _parents.length,
        rowIndexes['parents']!,
      );
    }

    final focusPeople = [_focus, ..._spouses];
    for (var i = 0; i < focusPeople.length; i++) {
      addRowNode(
        focusPeople[i],
        i,
        focusPeople.length,
        rowIndexes['focus']!,
        isFocus: i == 0,
      );
    }

    for (var i = 0; i < _children.length; i++) {
      addRowNode(
        _children[i],
        i,
        _children.length,
        rowIndexes['children']!,
      );
    }

    if (_showGrandchildren &&
        rowIndexes['grandchildren'] != null) {
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

      return Offset(
        topLeft.dx + _cardWidth / 2,
        topLeft.dy + _cardHeight / 2,
      );
    }

    final focusCenter = centerOf(_focus.id);

    for (final parent in _parents) {
      final parentCenter = centerOf(parent.id);

      if (parentCenter != null && focusCenter != null) {
        edges.add(
          _TreeEdge(
            from: Offset(
              parentCenter.dx,
              parentCenter.dy + _cardHeight / 2,
            ),
            to: Offset(
              focusCenter.dx,
              focusCenter.dy - _cardHeight / 2,
            ),
          ),
        );
      }

      if (_showGrandparents && parent.id != null) {
        final list =
            _grandparentsByParent[parent.id!] ?? const [];

        for (final grandparent in list) {
          final grandCenter = centerOf(grandparent.id);

          if (grandCenter != null && parentCenter != null) {
            edges.add(
              _TreeEdge(
                from: Offset(
                  grandCenter.dx,
                  grandCenter.dy + _cardHeight / 2,
                ),
                to: Offset(
                  parentCenter.dx,
                  parentCenter.dy - _cardHeight / 2,
                ),
              ),
            );
          }
        }
      }
    }

    for (final spouse in _spouses) {
      final spouseCenter = centerOf(spouse.id);

      if (spouseCenter != null && focusCenter != null) {
        edges.add(
          _TreeEdge(
            from: focusCenter,
            to: spouseCenter,
            isSpouse: true,
          ),
        );
      }
    }

    for (final child in _children) {
      final childCenter = centerOf(child.id);

      if (childCenter != null && focusCenter != null) {
        edges.add(
          _TreeEdge(
            from: Offset(
              focusCenter.dx,
              focusCenter.dy + _cardHeight / 2,
            ),
            to: Offset(
              childCenter.dx,
              childCenter.dy - _cardHeight / 2,
            ),
          ),
        );
      }

      if (_showGrandchildren && child.id != null) {
        final list =
            _grandchildrenByChild[child.id!] ?? const [];

        for (final grandchild in list) {
          final grandchildCenter = centerOf(grandchild.id);

          if (grandchildCenter != null && childCenter != null) {
            edges.add(
              _TreeEdge(
                from: Offset(
                  childCenter.dx,
                  childCenter.dy + _cardHeight / 2,
                ),
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
  }) {
    final path = person.profilePhotoPath;
    final hasPhoto = path.isNotEmpty && File(path).existsSync();

    return SizedBox(
      width: _cardWidth,
      height: _cardHeight,
      child: Card(
        elevation: highlighted ? 8 : 2,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _recenter(person),
          onDoubleTap: () => _openProfile(person),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage:
                      hasPhoto ? FileImage(File(path)) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(
                          Icons.person_outline,
                          size: 30,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
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
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                      ],
                      if (highlighted) ...[
                        const SizedBox(height: 5),
                        Text(
                          'Focused',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
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

  const _TreeEdge({
    required this.from,
    required this.to,
    this.isSpouse = false,
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

  const _FamilyTreeLinePainter({
    required this.edges,
  });

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
