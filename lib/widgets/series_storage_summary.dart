import 'package:flutter/material.dart';

import '../models/imported_coin.dart';
import '../screens/storage_detail_screen.dart';

class SeriesStorageSummary extends StatelessWidget {
  final List<ImportedCoin> coins;

  const SeriesStorageSummary({
    super.key,
    required this.coins,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final grouped = <String, List<ImportedCoin>>{};

    for (final coin in coins) {
      final rawLocation = coin.storageLocation.trim();

      final location =
          rawLocation.isEmpty ? 'No Location' : rawLocation;

      grouped.putIfAbsent(location, () => []).add(coin);
    }

    final locations = grouped.keys.toList()
      ..sort(
        (a, b) =>
            a.toLowerCase().compareTo(b.toLowerCase()),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Albums & Binders',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        for (final location in locations) ...[
          _StorageCard(
            location: location,
            coins: grouped[location]!,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StorageCard extends StatelessWidget {
  final String location;
  final List<ImportedCoin> coins;

  const _StorageCard({
    required this.location,
    required this.coins,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final owned =
        coins.where((coin) => coin.isOwned).length;

    final needed =
        coins.where((coin) => coin.isNeeded).length;

    final tracked = owned + needed;

    final completionRate =
        tracked == 0 ? 0.0 : owned / tracked;

    final percent = (completionRate * 100).round();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StorageDetailScreen(
                location: location,
                seriesName: coins.first.series,
                coins: coins,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      location,
                      style:
                          theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${coins.length} coins',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: completionRate,
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  Text('$percent% complete'),
                  Text('$owned Owned'),
                  Text('$needed Needed'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}