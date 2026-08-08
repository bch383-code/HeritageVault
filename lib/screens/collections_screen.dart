import 'package:flutter/material.dart';

import 'coin_series_explorer_screen.dart';

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final collections = [
      const _CollectionItem(
        title: 'Coins',
        subtitle: 'Explore collection progress, needed coins, storage, and notes',
        icon: Icons.monetization_on_outlined,
        enabled: true,
      ),
      const _CollectionItem(
        title: 'Photographs',
        subtitle: 'People, dates, places, tags, and stories',
        icon: Icons.photo_library_outlined,
      ),
      const _CollectionItem(
        title: 'Documents',
        subtitle: 'Letters, records, certificates, and research',
        icon: Icons.description_outlined,
      ),
      const _CollectionItem(
        title: 'Family Tree',
        subtitle: 'People, relationships, events, and timelines',
        icon: Icons.account_tree_outlined,
      ),
      const _CollectionItem(
        title: 'Heirlooms',
        subtitle: 'Antiques and objects with family provenance',
        icon: Icons.museum_outlined,
      ),
      const _CollectionItem(
        title: 'Stories',
        subtitle: 'Memories and narratives connected to your archive',
        icon: Icons.auto_stories_outlined,
      ),
    ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collections',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your family museum, organized by collection.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(28),
          sliver: SliverGrid.builder(
            itemCount: collections.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 430,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              childAspectRatio: 1.55,
            ),
            itemBuilder: (context, index) {
              final item = collections[index];
              return _CollectionCard(
                item: item,
                onTap: item.enabled
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const CoinSeriesExplorerScreen(),
                          ),
                        )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CollectionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;

  const _CollectionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.enabled = false,
  });
}

class _CollectionCard extends StatelessWidget {
  final _CollectionItem item;
  final VoidCallback? onTap;

  const _CollectionCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surfaceContainerHighest,
                colors.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: colors.primaryContainer,
                      child: Icon(item.icon, color: colors.onPrimaryContainer),
                    ),
                    const Spacer(),
                    Chip(label: Text(item.enabled ? 'Explore' : 'Coming later')),
                  ],
                ),
                const Spacer(),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(item.subtitle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
