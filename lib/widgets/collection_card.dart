import 'package:flutter/material.dart';

class CollectionCard extends StatelessWidget {
  final String title;
  final int owned;
  final int needed;
  final int untracked;
  final IconData icon;
  final VoidCallback? onTap;

  const CollectionCard({
    super.key,
    required this.title,
    required this.owned,
    required this.needed,
    required this.untracked,
    required this.icon,
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
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
                  Expanded(
                    child: Text(
                      '$owned of $trackedTotal tracked coins owned',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: completionRate,
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _CountLabel(label: 'Owned', value: owned),
                  _CountLabel(label: 'Need', value: needed),
                  if (untracked > 0)
                    _CountLabel(label: 'Untracked', value: untracked),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountLabel extends StatelessWidget {
  final String label;
  final int value;

  const _CountLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $value',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
