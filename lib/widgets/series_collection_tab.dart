import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import 'series_storage_summary.dart';

class SeriesCollectionTab extends StatefulWidget {
  final String seriesName;

  const SeriesCollectionTab({
    super.key,
    required this.seriesName,
  });

  @override
  State<SeriesCollectionTab> createState() => _SeriesCollectionTabState();
}

class _SeriesCollectionTabState extends State<SeriesCollectionTab> {
  int _refreshKey = 0;

  Future<void> _openCoin(ImportedCoin coin) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CoinDetailDialog(coin: coin),
    );
    if (mounted) setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ImportedCoin>>(
      key: ValueKey(_refreshKey),
      future: DatabaseHelper.instance.getImportedCoins(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Could not load this collection.\n\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final normalizedSeries = widget.seriesName.trim().toLowerCase();
        final seriesCoins = (snapshot.data ?? []).where((coin) {
          final coinSeries = coin.series.trim().toLowerCase();
          return coinSeries == normalizedSeries ||
              coinSeries.contains(normalizedSeries) ||
              normalizedSeries.contains(coinSeries);
        }).toList();

        if (seriesCoins.isEmpty) {
          return const Center(child: Text('No coins were found for this series.'));
        }

        final needed = seriesCoins.where((c) => c.status == 'Need').toList();
        final owned = seriesCoins.where((c) => c.status == 'Owned').toList();
        final untracked =
            seriesCoins.where((c) => c.status == 'Untracked').toList();

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            _CollectionSummary(
              total: seriesCoins.length,
              owned: owned.length,
              needed: needed.length,
              untracked: untracked.length,
            ),
            const SizedBox(height: 28),
            SeriesStorageSummary(coins: seriesCoins),
            const SizedBox(height: 28),
            if (needed.isNotEmpty)
              _CoinSection(
                title: 'Need',
                icon: Icons.star_border_rounded,
                coins: needed,
                onCoinTap: _openCoin,
              ),
            if (needed.isNotEmpty && owned.isNotEmpty)
              const SizedBox(height: 28),
            if (owned.isNotEmpty)
              _CoinSection(
                title: 'Owned',
                icon: Icons.check_circle_outline,
                coins: owned,
                onCoinTap: _openCoin,
              ),
            if (untracked.isNotEmpty) ...[
              const SizedBox(height: 28),
              _CoinSection(
                title: 'Untracked',
                icon: Icons.help_outline,
                coins: untracked,
                onCoinTap: _openCoin,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CollectionSummary extends StatelessWidget {
  final int total;
  final int owned;
  final int needed;
  final int untracked;

  const _CollectionSummary({
    required this.total,
    required this.owned,
    required this.needed,
    required this.untracked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracked = owned + needed;
    final completionRate = tracked == 0 ? 0.0 : owned / tracked;
    final percent = (completionRate * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Collection',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('$percent%',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                const Text('complete'),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: completionRate,
              minHeight: 9,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 22,
              runSpacing: 8,
              children: [
                Text('$owned Owned'),
                Text('$needed Needed'),
                Text('$total Total'),
                if (untracked > 0) Text('$untracked Untracked'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ImportedCoin> coins;
  final ValueChanged<ImportedCoin> onCoinTap;

  const _CoinSection({
    required this.title,
    required this.icon,
    required this.coins,
    required this.onCoinTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Text(title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${coins.length} coins'),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < coins.length; index++) ...[
                _CoinRow(
                  coin: coins[index],
                  onTap: () => onCoinTap(coins[index]),
                ),
                if (index != coins.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CoinRow extends StatelessWidget {
  final ImportedCoin coin;
  final VoidCallback onTap;

  const _CoinRow({required this.coin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      if (coin.mint.trim().isNotEmpty) coin.mint.trim(),
      if (coin.variety.trim().isNotEmpty) coin.variety.trim(),
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                coin.year.isEmpty ? '—' : coin.year,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Text(details.isEmpty ? coin.series : details.join(' • ')),
            ),
            if (coin.storageLocation.trim().isNotEmpty)
              Text(coin.storageLocation, style: theme.textTheme.bodySmall),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _CoinDetailDialog extends StatelessWidget {
  final ImportedCoin coin;

  const _CoinDetailDialog({required this.coin});

  String get _backImagePath {
    for (final line in coin.notes.split('\n')) {
      if (line.trim().toLowerCase().startsWith('back image:')) {
        return line.substring(line.indexOf(':') + 1).trim();
      }
    }
    return '';
  }

  String get _visibleNotes => coin.notes
      .split('\n')
      .where((line) =>
          !line.trim().toLowerCase().startsWith('back image:') &&
          line.trim() != 'Captured with Heirloom Atlas mobile companion.')
      .join('\n')
      .trim();

  Widget _imagePanel(BuildContext context, String label, String imagePath) {
    final file = imagePath.trim().isEmpty ? null : File(imagePath.trim());
    final exists = file != null && file.existsSync();
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: exists
                ? Image.file(file, fit: BoxFit.contain)
                : const Center(
                    child: Icon(Icons.monetization_on_outlined, size: 72),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final back = _backImagePath;
    return AlertDialog(
      title: Text(
        '${coin.year.isEmpty ? '' : '${coin.year} '}${coin.series}'.trim(),
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _imagePanel(context, 'Front', coin.imagePath),
                  if (back.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    _imagePanel(context, 'Back', back),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              _detail('Category', coin.category),
              _detail('Series', coin.series),
              _detail('Year', coin.year),
              _detail('Mint', coin.mint),
              _detail('Variety', coin.variety),
              _detail('Status', coin.status),
              _detail('Quantity', coin.quantityOwned.toString()),
              _detail('Grade', coin.grade),
              _detail('Storage', coin.storageLocation),
              if (coin.value != null)
                _detail('Value', '\$${coin.value!.toStringAsFixed(2)}'),
              if (_visibleNotes.isNotEmpty) _detail('Notes', _visibleNotes),
            ],
          ),
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
