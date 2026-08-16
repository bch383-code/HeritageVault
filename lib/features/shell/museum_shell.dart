import 'package:flutter/material.dart';

import '../../screens/coin_series_explorer_screen.dart';
import '../../screens/coins_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/need_list_screen.dart';
import '../../screens/postcards_screen.dart';
import '../../screens/valuables_screen.dart';
import '../../screens/antiques_screen.dart';
import '../../screens/photos_screen.dart';
import '../../widgets/custom_collections_sidebar.dart';

class MuseumShell extends StatefulWidget {
  const MuseumShell({super.key});

  @override
  State<MuseumShell> createState() => _MuseumShellState();
}

enum _VaultPage {
  home,
  coinSeries,
  collection,
  needList,
  postcards,
  valuables,
  photos,
  documents,
  familyTree,
  antiques,
  stories,
  settings,
}

class _MuseumShellState extends State<MuseumShell> {
  _VaultPage _selectedPage = _VaultPage.home;
  bool _allCollectionsExpanded = true;
  bool _coinsExpanded = true;

  void _select(_VaultPage page) {
    setState(() => _selectedPage = page);
  }

  Widget _currentPage() {
    switch (_selectedPage) {
      case _VaultPage.home:
        return HomeScreen(
          onOpenCollections: () => _select(_VaultPage.coinSeries),
        );
      case _VaultPage.coinSeries:
        return const CoinSeriesExplorerScreen();
      case _VaultPage.collection:
        return const CoinsScreen();
      case _VaultPage.needList:
        return const NeedListScreen();
      case _VaultPage.postcards:
        return const PostcardsScreen();
      case _VaultPage.valuables:
        return const ValuablesScreen();
      case _VaultPage.photos:
        return const PhotosScreen();
      case _VaultPage.documents:
        return const _ComingSoonPage(
          title: 'Documents',
          subtitle: 'Archive letters, records, certificates, and family papers.',
          icon: Icons.description_outlined,
        );
      case _VaultPage.familyTree:
        return const _ComingSoonPage(
          title: 'Family Tree',
          subtitle: 'Connect people, relationships, and generations.',
          icon: Icons.account_tree_outlined,
        );
      case _VaultPage.antiques:
        return const AntiquesScreen();
      case _VaultPage.stories:
        return const _ComingSoonPage(
          title: 'Stories',
          subtitle: 'Record the memories and stories behind your collection.',
          icon: Icons.menu_book_outlined,
        );
      case _VaultPage.settings:
        return const _ComingSoonPage(
          title: 'Settings',
          subtitle: 'Heritage Vault preferences and collection settings.',
          icon: Icons.settings_outlined,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 250,
              child: _VaultSidebar(
                selectedPage: _selectedPage,
                allCollectionsExpanded: _allCollectionsExpanded,
                coinsExpanded: _coinsExpanded,
                onAllCollectionsExpandedChanged: (value) {
                  setState(() => _allCollectionsExpanded = value);
                },
                onCoinsExpandedChanged: (value) {
                  setState(() => _coinsExpanded = value);
                },
                onSelect: _select,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(_selectedPage),
                  child: _currentPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultSidebar extends StatelessWidget {
  final _VaultPage selectedPage;
  final bool allCollectionsExpanded;
  final bool coinsExpanded;
  final ValueChanged<bool> onAllCollectionsExpandedChanged;
  final ValueChanged<bool> onCoinsExpandedChanged;
  final ValueChanged<_VaultPage> onSelect;

  const _VaultSidebar({
    required this.selectedPage,
    required this.allCollectionsExpanded,
    required this.coinsExpanded,
    required this.onAllCollectionsExpandedChanged,
    required this.onCoinsExpandedChanged,
    required this.onSelect,
  });

  bool get _coinPage =>
      selectedPage == _VaultPage.coinSeries ||
      selectedPage == _VaultPage.collection ||
      selectedPage == _VaultPage.needList;

  bool get _builtInCollectionPage =>
      _coinPage ||
      selectedPage == _VaultPage.postcards ||
      selectedPage == _VaultPage.valuables ||
      selectedPage == _VaultPage.antiques;

  @override
  Widget build(BuildContext context) {
    const sidebarNavy = Color(0xFF071A2B);
    const antiqueGold = Color(0xFFC9A65A);

    return Material(
      color: sidebarNavy,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              children: [
                SizedBox(
                  height: 118,
                  child: Image.asset(
                    'assets/images/heritage_vault_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.account_balance_outlined,
                      size: 72,
                      color: antiqueGold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'HERITAGE VAULT',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: antiqueGold,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF21405A)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
              children: [
                _SidebarItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Home',
                  selected: selectedPage == _VaultPage.home,
                  onTap: () => onSelect(_VaultPage.home),
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  icon: Icons.photo_library_outlined,
                  selectedIcon: Icons.photo_library,
                  label: 'Photos',
                  selected: selectedPage == _VaultPage.photos,
                  onTap: () => onSelect(_VaultPage.photos),
                ),
                _SidebarItem(
                  icon: Icons.account_tree_outlined,
                  selectedIcon: Icons.account_tree,
                  label: 'Family Tree',
                  selected: selectedPage == _VaultPage.familyTree,
                  onTap: () => onSelect(_VaultPage.familyTree),
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2,
                  label: 'All Collections',
                  selected: _builtInCollectionPage,
                  trailing: Icon(
                    allCollectionsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  onTap: () => onAllCollectionsExpandedChanged(
                    !allCollectionsExpanded,
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 160),
                  crossFadeState: allCollectionsExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Column(
                      children: [
                        _SidebarItem(
                          icon: Icons.monetization_on_outlined,
                          selectedIcon: Icons.monetization_on,
                          label: 'Coins',
                          selected: _coinPage,
                          trailing: Icon(
                            coinsExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                          ),
                          onTap: () =>
                              onCoinsExpandedChanged(!coinsExpanded),
                          compact: true,
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 160),
                          crossFadeState: coinsExpanded
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Column(
                              children: [
                                _SidebarItem(
                                  icon: Icons.grid_view_outlined,
                                  selectedIcon: Icons.grid_view_rounded,
                                  label: 'Coin Series',
                                  selected:
                                      selectedPage == _VaultPage.coinSeries,
                                  onTap: () =>
                                      onSelect(_VaultPage.coinSeries),
                                  compact: true,
                                ),
                                _SidebarItem(
                                  icon: Icons.folder_outlined,
                                  selectedIcon: Icons.folder,
                                  label: 'Collection',
                                  selected:
                                      selectedPage == _VaultPage.collection,
                                  onTap: () =>
                                      onSelect(_VaultPage.collection),
                                  compact: true,
                                ),
                                _SidebarItem(
                                  icon: Icons.checklist_outlined,
                                  selectedIcon: Icons.checklist_rounded,
                                  label: 'Need List',
                                  selected:
                                      selectedPage == _VaultPage.needList,
                                  onTap: () =>
                                      onSelect(_VaultPage.needList),
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                          secondChild: const SizedBox.shrink(),
                        ),
                        _SidebarItem(
                          icon: Icons.markunread_mailbox_outlined,
                          selectedIcon: Icons.markunread_mailbox,
                          label: 'Postcards',
                          selected: selectedPage == _VaultPage.postcards,
                          onTap: () => onSelect(_VaultPage.postcards),
                          compact: true,
                        ),
                        _SidebarItem(
                          icon: Icons.diamond_outlined,
                          selectedIcon: Icons.diamond,
                          label: 'Valuables',
                          selected: selectedPage == _VaultPage.valuables,
                          onTap: () => onSelect(_VaultPage.valuables),
                          compact: true,
                        ),
                        _SidebarItem(
                          icon: Icons.inventory_2_outlined,
                          selectedIcon: Icons.inventory_2,
                          label: 'Antiques',
                          selected: selectedPage == _VaultPage.antiques,
                          onTap: () => onSelect(_VaultPage.antiques),
                          compact: true,
                        ),
                        const CustomCollectionsSidebar(),
                      ],
                    ),
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
                _SidebarItem(
                  icon: Icons.description_outlined,
                  selectedIcon: Icons.description,
                  label: 'Documents',
                  selected: selectedPage == _VaultPage.documents,
                  onTap: () => onSelect(_VaultPage.documents),
                ),
                _SidebarItem(
                  icon: Icons.menu_book_outlined,
                  selectedIcon: Icons.menu_book,
                  label: 'Stories',
                  selected: selectedPage == _VaultPage.stories,
                  onTap: () => onSelect(_VaultPage.stories),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF21405A)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: const AddCollectionSidebarButton(),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: _SidebarItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: 'Settings',
              selected: selectedPage == _VaultPage.settings,
              onTap: () => onSelect(_VaultPage.settings),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool compact;

  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const selectedBlue = Color(0xFF0B5EA8);
    const textColor = Color(0xFFD8E4F0);
    const mutedColor = Color(0xFF91A9BF);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? selectedBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 12,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: compact ? 20 : 22,
                  color: selected ? Colors.white : mutedColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : textColor,
                    ),
                  ),
                ),
                if (trailing != null)
                  IconTheme(
                    data: IconThemeData(
                      color: selected ? Colors.white : mutedColor,
                    ),
                    child: trailing!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoonPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ComingSoonPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Coming later',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
