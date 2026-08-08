import 'package:flutter/material.dart';

import '../reference/coin_series_reference.dart';
import '../widgets/series_live_header.dart';
import '../widgets/series_overview_tab.dart';
import '../widgets/history_timeline.dart';
import '../widgets/series_collection_tab.dart';

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
SeriesLiveHeader(
  seriesName: seriesName,
  reference: reference,
),
            const TabBar(
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Collection'),
                Tab(text: 'History'),
                Tab(text: 'My Story'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                 SeriesOverviewTab(
                reference: reference,
                ),
                  SeriesCollectionTab(
                seriesName: seriesName,
                ),
                 HistoryTimeline(
                    events: seriesName.toLowerCase().contains('morgan')
                     ? morganTimeline
                     : const [],
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