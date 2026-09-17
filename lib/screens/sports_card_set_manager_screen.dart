import 'package:flutter/material.dart';

import '../database/database_helper.dart';

class SportsCardSetManagerScreen extends StatefulWidget {
  const SportsCardSetManagerScreen({super.key});

  @override
  State<SportsCardSetManagerScreen> createState() =>
      _SportsCardSetManagerScreenState();
}

class _SportsCardSetManagerScreenState
    extends State<SportsCardSetManagerScreen> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  List<Map<String, Object?>> _sets = const [];
  bool _loading = true;

  static String _cleanText(String value) {
    return value
        .replaceAll('â€”', '—')
        .replaceAll('â€“', '–')
        .replaceAll('â€˜', '‘')
        .replaceAll('â€™', '’')
        .replaceAll('â€œ', '“')
        .replaceAll('â€\u009d', '”')
        .replaceAll('�', '')
        .trim();
  }

  Future<void> _load() async {
    final db = await _databaseHelper.database;
    final sets = await db.query(
      'sports_card_sets',
      orderBy:
          'sport COLLATE NOCASE, year DESC, brand COLLATE NOCASE, set_name COLLATE NOCASE',
    );
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _cleanExistingText() async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final sets = await txn.query('sports_card_sets');
      for (final row in sets) {
        final key = row['source_key'] as String? ?? '';
        if (key.isEmpty) continue;
        await txn.update(
          'sports_card_sets',
          {
            'source_name': _cleanText(row['source_name'] as String? ?? ''),
            'sport': _cleanText(row['sport'] as String? ?? ''),
            'year': _cleanText(row['year'] as String? ?? ''),
            'brand': _cleanText(row['brand'] as String? ?? ''),
            'set_name': _cleanText(row['set_name'] as String? ?? ''),
          },
          where: 'source_key = ?',
          whereArgs: [key],
        );
      }

      final catalog = await txn.query('sports_card_catalog');
      for (final row in catalog) {
        final id = row['id'];
        if (id == null) continue;
        await txn.update(
          'sports_card_catalog',
          {
            'sport': _cleanText(row['sport'] as String? ?? ''),
            'year': _cleanText(row['year'] as String? ?? ''),
            'brand': _cleanText(row['brand'] as String? ?? ''),
            'set_name': _cleanText(row['set_name'] as String? ?? ''),
            'card_number': _cleanText(row['card_number'] as String? ?? ''),
            'player': _cleanText(row['player'] as String? ?? ''),
            'team': _cleanText(row['team'] as String? ?? ''),
            'attributes': _cleanText(row['attributes'] as String? ?? ''),
            'catalog_notes': _cleanText(row['catalog_notes'] as String? ?? ''),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sports-card text cleanup complete.')),
    );
  }

  Future<void> _deleteSet(Map<String, Object?> set) async {
    final sourceKey = set['source_key'] as String? ?? '';
    if (sourceKey.isEmpty) return;

    final year = _cleanText(set['year'] as String? ?? '');
    final brand = _cleanText(set['brand'] as String? ?? '');
    final setName = _cleanText(set['set_name'] as String? ?? '');
    final display = [year, brand, setName]
        .where((value) => value.isNotEmpty)
        .join(' ');

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete card set?'),
            content: Text(
              'Delete "${display.isEmpty ? 'this card set' : display}" from '
              'Heirloom Atlas?\n\nThis removes the set catalog and your saved '
              'status/details for cards in this set. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Delete Set'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final catalogIds = await txn.query(
        'sports_card_catalog',
        columns: ['id'],
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );

      for (final row in catalogIds) {
        await txn.delete(
          'sports_card_collection',
          where: 'catalog_id = ?',
          whereArgs: [row['id']],
        );
      }

      await txn.delete(
        'sports_card_catalog',
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );
      await txn.delete(
        'sports_card_sets',
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );
    });

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _panel,
                border: Border.all(color: _gold.withValues(alpha: .42)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.style_outlined, color: _gold, size: 34),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MANAGE CARD SETS',
                          style: TextStyle(
                            color: _cream,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Clean imported text or remove card sets you no longer want.',
                          style: TextStyle(color: _muted),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _cleanExistingText,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Clean Text'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _sets.isEmpty
                      ? const Center(
                          child: Text(
                            'No card sets are installed.',
                            style: TextStyle(color: _muted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _sets.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final set = _sets[index];
                            final year =
                                _cleanText(set['year'] as String? ?? '');
                            final brand =
                                _cleanText(set['brand'] as String? ?? '');
                            final setName =
                                _cleanText(set['set_name'] as String? ?? '');
                            final sport =
                                _cleanText(set['sport'] as String? ?? '');

                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.collections_bookmark_outlined),
                                title: Text(
                                  [year, brand, setName]
                                      .where((value) => value.isNotEmpty)
                                      .join(' '),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  sport.isEmpty ? 'Sports Cards' : sport,
                                ),
                                trailing: IconButton(
                                  tooltip: 'Delete set',
                                  onPressed: () => _deleteSet(set),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
