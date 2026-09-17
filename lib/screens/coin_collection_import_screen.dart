import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import '../services/coin_import_service.dart';

class CoinCollectionImportScreen extends StatefulWidget {
  const CoinCollectionImportScreen({super.key});

  @override
  State<CoinCollectionImportScreen> createState() =>
      _CoinCollectionImportScreenState();
}

class _CoinCollectionImportScreenState extends State<CoinCollectionImportScreen> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final CoinImportService _importService = CoinImportService();

  CoinImportResult? _result;
  String? _error;
  bool _busy = false;

  Future<void> _chooseWorkbook() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await _importService.chooseAndReadWorkbook();
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = null;
        _error = e.toString();
      });
    }
  }

  String _coinKey(ImportedCoin coin) => [
        coin.category.trim().toLowerCase(),
        coin.series.trim().toLowerCase(),
        coin.year.trim().toLowerCase(),
        coin.mint.trim().toLowerCase(),
        coin.variety.trim().toLowerCase(),
      ].join('|');

  Future<void> _import({required bool replace}) async {
    final result = _result;
    if (result == null || result.coins.isEmpty || _busy) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              replace
                  ? 'Replace current coin collection?'
                  : 'Merge coin collection?',
            ),
            content: Text(
              replace
                  ? 'This will replace the current imported coin list with '
                      '${result.coins.length} entries from ${result.fileName}. '
                      'Manual coin records are not affected. A database backup '
                      'will be created first.'
                  : 'This will merge ${result.coins.length} workbook entries '
                      'with the current imported coin list. Existing Heirloom '
                      'Atlas information wins when the same coin already exists. '
                      'A database backup will be created first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(replace ? 'Replace & Import' : 'Merge & Import'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _databaseHelper.createDatabaseBackup(
        reason: replace
            ? 'before_spreadsheet_replace'
            : 'before_spreadsheet_merge',
      );

      late final int savedCount;
      var addedCount = 0;
      var preservedCount = 0;

      if (replace) {
        savedCount = await _databaseHelper.replaceImportedCoins(result.coins);
        await _databaseHelper.replaceStorageLocations(
          result.storageLocations
              .map(
                (location) => <String, Object?>{
                  'brand': location.brand,
                  'color': location.color,
                  'number': location.number,
                  'title': location.title,
                  'year': location.year,
                  'notes': location.notes,
                },
              )
              .toList(),
        );
      } else {
        final currentCoins = await _databaseHelper.getImportedCoins();
        final merged = <String, ImportedCoin>{};

        for (final coin in result.coins) {
          merged[_coinKey(coin)] = coin;
        }
        for (final coin in currentCoins) {
          final key = _coinKey(coin);
          if (merged.containsKey(key)) preservedCount++;
          merged[key] = coin;
        }

        final incomingKeys = result.coins.map(_coinKey).toSet();
        final currentKeys = currentCoins.map(_coinKey).toSet();
        addedCount =
            incomingKeys.where((key) => !currentKeys.contains(key)).length;

        savedCount = await _databaseHelper.replaceImportedCoins(
          merged.values.toList(),
        );
      }

      if (!mounted) return;
      setState(() => _busy = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(replace ? 'Coin Collection Replaced' : 'Coin Collection Merged'),
          content: Text(
            replace
                ? 'Saved $savedCount coin entries.\n'
                    'Storage locations: ${result.storageLocations.length}'
                : 'Saved $savedCount coin entries.\n'
                    'New workbook entries added: $addedCount\n'
                    'Existing matching entries preserved: $preservedCount\n\n'
                    'Existing storage locations were left unchanged.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      backgroundColor: _navy,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _panel,
              border: Border.all(color: _gold.withValues(alpha: .42)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Icon(Icons.upload_file_outlined, color: _gold, size: 34),
                SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IMPORT COIN COLLECTION',
                        style: TextStyle(
                          color: _cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Import your Heirloom Atlas Excel coin workbook (.xlsx).',
                        style: TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _chooseWorkbook,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose Coin Workbook (.xlsx)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
          ],
          if (result != null) ...[
            const SizedBox(height: 18),
            Text(
              result.fileName,
              style: const TextStyle(color: _cream, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${result.coins.length} coin entries ready to import • '
              'Owned: ${result.ownedCount} • Needed: ${result.neededCount} • '
              'Untracked: ${result.untrackedCount}',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 360),
              decoration: BoxDecoration(
                color: _panel.withValues(alpha: .75),
                border: Border.all(color: _gold.withValues(alpha: .2)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: result.coins.length.clamp(0, 100),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final coin = result.coins[index];
                  final details = [coin.year, coin.mint, coin.variety]
                      .where((value) => value.trim().isNotEmpty)
                      .join(' ');
                  return ListTile(
                    dense: true,
                    title: Text(
                      coin.series.trim().isEmpty ? coin.category : coin.series,
                    ),
                    subtitle: Text(
                      '${details.isEmpty ? 'Coin' : details} • ${coin.status}',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _import(replace: false),
                  icon: const Icon(Icons.merge_type),
                  label: const Text('Merge with Existing Collection'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _import(replace: true),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Replace Imported Coin List'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Expected workbook sheets include Main List and, when present, '
            'Type Binder, Sets, and Albums-Bins.',
            style: TextStyle(color: _muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
