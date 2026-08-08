import 'package:flutter/material.dart';

import '../reference/coin_series_reference.dart';
import '../widgets/series_museum_header.dart';

class SeriesDetailScreen extends StatelessWidget {
  final String seriesName;

  const SeriesDetailScreen({
    super.key,
    required this.seriesName,
  });

  @override
  Widget build(BuildContext context) {
    final reference = CoinSeriesLibrary.find(seriesName);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(seriesName),
        ),
        body: Column(
          children: [
SeriesMuseumHeader(
  seriesName: seriesName,
  reference: reference,
  completionRate: 0.82,
  owned: 143,
  needed: 31,
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