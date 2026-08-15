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

  int get goalTotal => owned + needed;

  double get completionRate {
    if (goalTotal == 0) return 0;
    return owned / goalTotal;
  }

  String? _thumbnailForTitle(String value) {
    final name = value.trim().toLowerCase();

    if (name.contains('half cent')) return 'assets/images/series/liberty_head_half_cent_thumb.png';
    if (name.contains('morgan')) return 'assets/images/series/morgan_dollar_thumb.png';
    if (name.contains('peace')) return 'assets/images/series/peace_dollar_thumb.png';
    if (name.contains('lincoln') || name.contains('wheat')) return 'assets/images/series/lincoln_wheat_cent_thumb.png';
    if (name.contains('indian') && name.contains('cent')) return 'assets/images/series/indian_head_cent_thumb.png';
    if (name.contains('buffalo')) return 'assets/images/series/buffalo_nickel_thumb.png';
    if (name.contains('jefferson')) return 'assets/images/series/jefferson_nickel_thumb.png';
    if (name.contains('mercury')) return 'assets/images/series/mercury_dime_thumb.png';
    if (name.contains('roosevelt')) return 'assets/images/series/roosevelt_dime_thumb.png';
    if (name.contains('standing') && name.contains('liberty')) return 'assets/images/series/standing_liberty_quarter_thumb.png';
    if (name.contains('washington')) return 'assets/images/series/washington_quarter_thumb.png';
    if (name.contains('barber') && name.contains('half')) return 'assets/images/series/barber_half_thumb.png';
    if (name.contains('walking') && name.contains('liberty')) return 'assets/images/series/walking_liberty_half_thumb.png';
    if (name.contains('franklin')) return 'assets/images/series/franklin_half_thumb.png';
    if (name.contains('kennedy')) return 'assets/images/series/kennedy_half_thumb.png';

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final percent = (completionRate * 100).round();
    final reference = CoinSeriesLibrary.find(title);

    final thumbnailAsset =
        reference?.thumbnailAsset.trim().isNotEmpty == true
            ? reference!.thumbnailAsset
            : _thumbnailForTitle(title);

    Widget imageWidget;

    if (representativeImage != null) {
      imageWidget = representativeImage!;
    } else if (thumbnailAsset != null && thumbnailAsset.isNotEmpty) {
      imageWidget = Padding(
        padding: const EdgeInsets.all(10),
        child: Image.asset(
          thumbnailAsset,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.broken_image_outlined,
              size: 52,
              color: colors.primary,
            );
          },
        ),
      );
    } else {
      imageWidget = Icon(
        Icons.monetization_on_outlined,
        size: 58,
        color: colors.primary,
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: colors.primaryContainer.withValues(alpha: 0.35),
                child: Center(child: imageWidget),
              ),
            ),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (reference != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        reference.denomination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reference.years,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '$percent%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('Goal completed'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: completionRate,
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '$owned Owned  •  $needed Needed'
                      '${untracked > 0 ? '  •  $untracked Untracked' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
