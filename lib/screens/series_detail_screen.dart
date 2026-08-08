import 'package:flutter/material.dart';

import '../reference/coin_series_reference.dart';

class SeriesDetailScreen extends StatelessWidget {
  final String seriesName;

  const SeriesDetailScreen({
    super.key,
    required this.seriesName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = CoinSeriesLibrary.find(seriesName);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(seriesName),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer,
                    ),
                    child: Icon(
                      Icons.monetization_on_outlined,
                      size: 88,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    seriesName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${reference?.denomination ?? ''} • '
                    '${reference?.years ?? ''}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reference?.designer ?? '',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 340,
                    child: LinearProgressIndicator(
                      value: 0.82,
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('82% Complete'),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Collection'),
                Tab(text: 'History'),
                Tab(text: 'My Story'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _PlaceholderTab(
                    title: 'Overview',
                    text:
                        'Series facts, collection progress, and albums will appear here.',
                  ),
                  _PlaceholderTab(
                    title: 'Collection',
                    text:
                        'Your owned and needed coins will appear here.',
                  ),
                  _PlaceholderTab(
                    title: 'History',
                    text:
                        'The history, key dates, and major varieties of this series will appear here.',
                  ),
                  _PlaceholderTab(
                    title: 'My Story',
                    text:
                        'Your personal memories and collecting stories will appear here.',
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

class _PlaceholderTab extends StatelessWidget {
  final String title;
  final String text;

  const _PlaceholderTab({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}