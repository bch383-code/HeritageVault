import 'package:flutter/material.dart';
import '../reference/coin_series_reference.dart';

class SeriesCard extends StatelessWidget {
  final String title;
  final int owned;
  final int needed;
  final int untracked;
  final Widget? representativeImage;
  final VoidCallback? onTap;

  const SeriesCard({
    super.key,
    required this.title,
    required this.owned,
    required this.needed,
    required this.untracked,
    this.representativeImage,
    this.onTap,
  });

  int get trackedTotal => owned + needed;

  double get completionRate {
    if (trackedTotal == 0) return 0;
    return owned / trackedTotal;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final percent = (completionRate * 100).round();
    final reference = CoinSeriesLibrary.find(title);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                color: colors.primaryContainer.withValues(alpha: 0.35),
                child: representativeImage ??
                    Icon(
                      Icons.monetization_on_outlined,
                      size: 72,
                      color: colors.primary,
                    ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
Text(
  title,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: theme.textTheme.titleLarge?.copyWith(
    fontWeight: FontWeight.w800,
  ),
),

if (reference != null) ...[
  const SizedBox(height: 6),
  Row(
    children: [
      Chip(
        label: Text(reference.denomination),
        visualDensity: VisualDensity.compact,
      ),
      const SizedBox(width: 8),
      Text(
        reference.years,
        style: theme.textTheme.bodySmall,
      ),
    ],
  ),
],

const Spacer(),
                    Row(
                      children: [
                        Text(
                          '$percent%',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('complete'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: completionRate,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$owned Owned  •  $needed Needed'
                      '${untracked > 0 ? '  •  $untracked Untracked' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}