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

    Widget fallbackImage() => Icon(
          Icons.monetization_on_outlined,
          size: 90,
          color: colors.primary,
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final image = Container(
            width: compact ? 210 : 260,
            height: compact ? 210 : 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: colors.primaryContainer,
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                  color: colors.shadow.withValues(alpha: 0.18),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: reference != null && reference!.imageAsset.isNotEmpty
                ? Image.asset(
                    reference!.imageAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallbackImage(),
                  )
                : fallbackImage(),
          );

          final information = Column(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                'HERITAGE COLLECTION',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                seriesName,
                textAlign: compact ? TextAlign.center : TextAlign.left,
                style: theme.textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${reference?.denomination ?? 'Coin'}'
                '${reference?.years.isNotEmpty == true ? '  •  ${reference!.years}' : ''}'
                '${reference?.designer.isNotEmpty == true ? '  •  ${reference!.designer}' : ''}',
                style: theme.textTheme.titleMedium,
                textAlign: compact ? TextAlign.center : TextAlign.left,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$percent%',
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 7),
                    child: Text('complete'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: compact ? 300 : 520,
                child: LinearProgressIndicator(
                  value: completionRate,
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 28,
                runSpacing: 8,
                children: [
                  Text(
                    '$owned Owned',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '$needed Needed',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              children: [
                image,
                const SizedBox(height: 24),
                information,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              image,
              const SizedBox(width: 28),
              Expanded(child: information),
            ],
          );
        },
      ),
    );
  }
}
