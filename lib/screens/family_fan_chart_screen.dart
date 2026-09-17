import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';

class FamilyFanChartScreen extends StatefulWidget {
  final FamilyPerson initialPerson;

  const FamilyFanChartScreen({
    super.key,
    required this.initialPerson,
  });

  @override
  State<FamilyFanChartScreen> createState() => _FamilyFanChartScreenState();
}

class _FamilyFanChartScreenState extends State<FamilyFanChartScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  late FamilyPerson _focus;
  bool _loading = true;
  int _generations = 4;
  final Map<String, FamilyPerson> _people = {};

  static const _navy = Color(0xFF071C30);
  static const _navy2 = Color(0xFF102A40);
  static const _cream = Color(0xFFF3E9D1);
  static const _gold = Color(0xFFC9A65A);

  @override
  void initState() {
    super.initState();
    _focus = widget.initialPerson;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _people.clear();
    _people[''] = _focus;
    await _loadAncestors(_focus, '', 1);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAncestors(
    FamilyPerson person,
    String key,
    int generation,
  ) async {
    if (generation >= _generations || person.id == null) return;
    final parents = await _databaseHelper.getFamilyParents(person.id!);

    FamilyPerson? father;
    FamilyPerson? mother;
    for (final parent in parents) {
      final role = (await _databaseHelper.getFamilyParentRole(
        parentId: parent.id!,
        childId: person.id!,
      )).toLowerCase();
      if (role == 'father' && father == null) {
        father = parent;
      } else if (role == 'mother' && mother == null) {
        mother = parent;
      }
    }
    for (final parent in parents) {
      if (father == null && parent.id != mother?.id) {
        father = parent;
      } else if (mother == null && parent.id != father?.id) {
        mother = parent;
      }
    }

    if (father != null) {
      final fatherKey = '${key}0';
      _people[fatherKey] = father;
      await _loadAncestors(father, fatherKey, generation + 1);
    }
    if (mother != null) {
      final motherKey = '${key}1';
      _people[motherKey] = mother;
      await _loadAncestors(mother, motherKey, generation + 1);
    }
  }

  Future<void> _openPerson(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FamilyPersonScreen(person: person)),
    );
    final refreshed =
        person.id == null ? null : await _databaseHelper.getFamilyPerson(person.id!);
    if (refreshed != null && person.id == _focus.id) _focus = refreshed;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        title: Text('Fan Chart — ${_focus.displayName}'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Generations',
            initialValue: _generations,
            onSelected: (value) async {
              _generations = value;
              await _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 3, child: Text('3 generations')),
              PopupMenuItem(value: 4, child: Text('4 generations')),
              PopupMenuItem(value: 5, child: Text('5 generations')),
            ],
            icon: const Icon(Icons.layers_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = math.max(1000.0, constraints.maxWidth);
                final height = math.max(720.0, constraints.maxHeight);
                final chartWidth = math.min(width * .94, height * 1.72);
                final chartHeight = chartWidth * .58;

                return InteractiveViewer(
                  minScale: .55,
                  maxScale: 3,
                  boundaryMargin: const EdgeInsets.all(500),
                  constrained: false,
                  child: SizedBox(
                    width: chartWidth,
                    height: chartHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) =>
                          _handleChartTap(details.localPosition, chartWidth, chartHeight),
                      child: CustomPaint(
                        painter: _FanPainter(
                          generations: _generations,
                          people: _people,
                          focus: _focus,
                          navy: _navy,
                          navy2: _navy2,
                          cream: _cream,
                          gold: _gold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _handleChartTap(Offset point, double width, double height) {
    final center = Offset(width / 2, height * .90);
    final maxRadius = math.min(width * .47, height * .82);
    final centerRadius = maxRadius * .155;

    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final radius = math.sqrt(dx * dx + dy * dy);

    if (radius <= centerRadius) {
      _openPerson(_focus);
      return;
    }

    final usable = maxRadius - centerRadius;
    final ringWidth = usable / (_generations - 1);
    final generation = ((radius - centerRadius) / ringWidth).floor() + 1;
    if (generation < 1 || generation >= _generations) return;

    var angle = math.atan2(dy, dx);
    if (angle < -math.pi) angle += math.pi * 2;
    if (angle > 0) return;

    final normalized = (angle + math.pi) / math.pi;
    final slots = 1 << generation;
    var slot = (normalized * slots).floor();
    slot = slot.clamp(0, slots - 1);

    final key = slot.toRadixString(2).padLeft(generation, '0');
    final person = _people[key];
    if (person != null) _openPerson(person);
  }
}

class _FanPainter extends CustomPainter {
  final int generations;
  final Map<String, FamilyPerson> people;
  final FamilyPerson focus;
  final Color navy;
  final Color navy2;
  final Color cream;
  final Color gold;

  const _FanPainter({
    required this.generations,
    required this.people,
    required this.focus,
    required this.navy,
    required this.navy2,
    required this.cream,
    required this.gold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .90);
    final maxRadius = math.min(size.width * .47, size.height * .82);
    final centerRadius = maxRadius * .155;
    final usable = maxRadius - centerRadius;
    final ringWidth = usable / (generations - 1);

    canvas.drawRect(Offset.zero & size, Paint()..color = navy);

    final border = Paint()
      ..color = gold.withValues(alpha: .68)
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;

    for (var generation = generations - 1; generation >= 1; generation--) {
      final inner = centerRadius + ringWidth * (generation - 1);
      final outer = centerRadius + ringWidth * generation;
      final slots = 1 << generation;
      final sweep = math.pi / slots;

      for (var slot = 0; slot < slots; slot++) {
        final start = -math.pi + slot * sweep;
        final path = Path()
          ..arcTo(
            Rect.fromCircle(center: center, radius: outer),
            start,
            sweep,
            false,
          )
          ..arcTo(
            Rect.fromCircle(center: center, radius: inner),
            start + sweep,
            -sweep,
            false,
          )
          ..close();

        final base = generation.isEven ? navy2 : const Color(0xFF0C253B);
        final shade = slot.isEven ? .98 : .88;
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = base.withValues(alpha: shade),
        );
        canvas.drawPath(path, border);

        final key = slot.toRadixString(2).padLeft(generation, '0');
        final person = people[key];
        if (person != null) {
          _paintPersonInSegment(
            canvas,
            center,
            person,
            generation,
            start,
            sweep,
            inner,
            outer,
          );
        }
      }
    }

    // Center medallion.
    canvas.drawCircle(
      center,
      centerRadius,
      Paint()..color = const Color(0xFF17364D),
    );
    canvas.drawCircle(
      center,
      centerRadius,
      Paint()
        ..color = gold
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(
      center,
      centerRadius * .86,
      Paint()
        ..color = gold.withValues(alpha: .72)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke,
    );

    _paintCenteredText(
      canvas,
      focus.displayName,
      focus.lifeSpan,
      center,
      centerRadius * 1.55,
      14,
      10,
    );

  }

  void _paintPersonInSegment(
    Canvas canvas,
    Offset center,
    FamilyPerson person,
    int generation,
    double start,
    double sweep,
    double inner,
    double outer,
  ) {
    final angle = start + sweep / 2;
    final radius = (inner + outer) / 2;
    final position = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );

    // Labels follow the radial direction of their wedge, similar to a
    // traditional genealogy fan chart. Flip labels on the left half so
    // every name remains upright and readable.
    var rotation = angle;
    if (math.cos(angle) < 0) {
      rotation += math.pi;
    }

    final radialSpace = (outer - inner) * .84;
    final arcSpace = math.max(34.0, radius * sweep * .78);

    final baseNameSize = switch (generation) {
      1 => 14.5,
      2 => 12.5,
      3 => 10.5,
      _ => 8.6,
    };

    var nameSize = baseNameSize;
    final minNameSize = generation >= 4 ? 6.8 : 8.2;
    final maxLines = generation >= 3 ? 3 : 2;

    while (nameSize > minNameSize) {
      final test = TextPainter(
        text: TextSpan(
          text: person.displayName,
          style: TextStyle(
            fontSize: nameSize,
            height: 1.02,
            fontWeight: FontWeight.w800,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: radialSpace);

      if (!test.didExceedMaxLines && test.height <= arcSpace * .72) break;
      nameSize -= .4;
    }

    final lifeSize = math.max(6.4, nameSize - 2.2);

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);

    _paintCenteredText(
      canvas,
      person.displayName,
      person.lifeSpan,
      Offset.zero,
      radialSpace,
      nameSize,
      lifeSize,
      maxNameLines: maxLines,
    );

    canvas.restore();
  }

  void _paintCenteredText(
    Canvas canvas,
    String name,
    String lifeSpan,
    Offset center,
    double width,
    double nameSize,
    double lifeSize, {
    int maxNameLines = 3,
  }) {
    final namePainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: cream,
          fontSize: nameSize,
          height: 1.08,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: maxNameLines,
      ellipsis: '…',
    )..layout(maxWidth: width);

    TextPainter? lifePainter;
    if (lifeSpan.isNotEmpty) {
      lifePainter = TextPainter(
        text: TextSpan(
          text: lifeSpan,
          style: TextStyle(
            color: cream.withValues(alpha: .64),
            fontSize: lifeSize,
            height: 1.1,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: width);
    }

    final totalHeight =
        namePainter.height + (lifePainter == null ? 0 : lifePainter.height + 4);
    var y = center.dy - totalHeight / 2;

    namePainter.paint(canvas, Offset(center.dx - namePainter.width / 2, y));
    y += namePainter.height + 4;

    if (lifePainter != null) {
      lifePainter.paint(canvas, Offset(center.dx - lifePainter.width / 2, y));
    }
  }

  @override
  bool shouldRepaint(covariant _FanPainter oldDelegate) =>
      oldDelegate.generations != generations ||
      oldDelegate.people != people ||
      oldDelegate.focus.id != focus.id;
}
