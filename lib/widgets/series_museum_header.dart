import 'package:flutter/material.dart';

import '../reference/coin_series_reference.dart';

class SeriesMuseumHeader extends StatelessWidget {
  final String seriesName;
  final CoinSeriesReference? reference;
  final double completionRate;
  final int owned;
  final int needed;

  const SeriesMuseumHeader({
    super.key,
    required this.seriesName,
    required this.reference,
    this.completionRate = 0,
    this.owned = 0,
    this.needed = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final percent = (completionRate * 100).round();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 14, 24, 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;

          final museumImage = Container(
            width: compact ? double.infinity : 300,
            height: compact ? 150 : 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: colors.surfaceContainerLow,
            ),
            clipBehavior: Clip.antiAlias,
            child: reference != null && reference!.imageAsset.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      reference!.imageAsset,
                      fit: BoxFit.contain,
                    ),
                  )
                : Icon(
                    Icons.monetization_on_outlined,
                    size: 72,
                    color: colors.primary,
                  ),
          );

          final information = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'HERITAGE COLLECTION',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                seriesName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: compact ? TextAlign.center : TextAlign.left,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${reference?.denomination ?? 'Coin'}'
                '${reference?.years.isNotEmpty == true ? '  •  ${reference!.years}' : ''}'
                '${reference?.designer.isNotEmpty == true ? '  •  ${reference!.designer}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: compact ? TextAlign.center : TextAlign.left,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$percent%',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text('complete'),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: LinearProgressIndicator(
                  value: completionRate,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 20,
                runSpacing: 4,
                alignment: compact ? WrapAlignment.center : WrapAlignment.start,
                children: [
                  Text(
                    '$owned Owned',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$needed Needed',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                museumImage,
                const SizedBox(height: 14),
                information,
              ],
            );
          }

          return SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                museumImage,
                const SizedBox(width: 22),
                Expanded(child: information),
              ],
            ),
          );
        },
      ),
    );
  }
}
