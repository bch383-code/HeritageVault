import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import '../reference/coin_series_reference.dart';
import 'series_museum_header.dart';

class SeriesLiveHeader extends StatelessWidget {
  final String seriesName;
  final CoinSeriesReference? reference;

  const SeriesLiveHeader({
    super.key,
    required this.seriesName,
    required this.reference,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ImportedCoin>>(
      future: DatabaseHelper.instance.getImportedCoins(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SeriesMuseumHeader(
            seriesName: seriesName,
            reference: reference,
          );
        }

        final normalized = seriesName.trim().toLowerCase();

        final seriesCoins = snapshot.data!.where((coin) {
          final coinSeries = coin.series.trim().toLowerCase();

          return coinSeries == normalized ||
              coinSeries.contains(normalized) ||
              normalized.contains(coinSeries);
        }).toList();

        final owned = seriesCoins
            .where((coin) => coin.status == 'Owned')
            .length;

        final needed = seriesCoins
            .where((coin) => coin.status == 'Need')
            .length;

        final tracked = owned + needed;

        final completionRate =
            tracked == 0 ? 0.0 : owned / tracked;

        return SeriesMuseumHeader(
          seriesName: seriesName,
          reference: reference,
          completionRate: completionRate,
          owned: owned,
          needed: needed,
        );
      },
    );
  }
}