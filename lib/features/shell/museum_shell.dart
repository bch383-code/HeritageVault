import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../screens/antique_edit_screen.dart';
import '../../screens/valuable_edit_screen.dart';

import '../../screens/coin_series_explorer_screen.dart';
import '../../screens/coins_screen.dart';
import '../../screens/coin_collection_import_screen.dart';
import '../../screens/documents_screen.dart';
import '../../screens/sports_card_set_manager_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/help_getting_started_screen.dart';
import '../../screens/need_list_screen.dart';
import '../../screens/postcards_screen.dart';
import '../../screens/valuables_screen.dart';
import '../../screens/antiques_screen.dart';
import '../../screens/photos_screen.dart';
import '../../screens/videos_screen.dart';
import '../../screens/sports_cards_screen.dart';
import '../../screens/family_tree_screen.dart';
import '../../screens/stories_screen.dart';
import '../../screens/sync_storage_screen.dart';
import '../../widgets/custom_collections_sidebar.dart';
import '../atlas_book/screens/atlas_book_screen.dart';
import '../settings/settings_screen.dart';
import '../collections/screens/all_collections_screen.dart';

class MuseumShell extends StatefulWidget {
  const MuseumShell({super.key});

  @override
  State<MuseumShell> createState() => _MuseumShellState();
}

enum _VaultPage {
  home,
  allCollections,
  coinSeries,
  collection,
  coinImport,
  needList,
  postcards,
  valuables,
  photos,
  videos,
  documents,
  familyTree,
  atlasBook,
  antiques,
  sportsCards,
  sportsCardSets,
  stories,
  quickCapture,
  syncStorage,
  help,
  settings,
}

class _MuseumShellState extends State<MuseumShell> {
  _VaultPage _selectedPage = _VaultPage.home;
  bool _allCollectionsExpanded = false;
  bool _coinsExpanded = true;
  String? _sportsCardQuickCaptureImagePath;

  void _select(_VaultPage page) {
    setState(() => _selectedPage = page);
  }

  Widget _currentPage() {
    switch (_selectedPage) {
      case _VaultPage.home:
        return HomeScreen(
          onOpenCollections: () => _select(_VaultPage.allCollections),
          onOpenPhotos: () => _select(_VaultPage.photos),
          onOpenFamilyTree: () => _select(_VaultPage.familyTree),
          onOpenAtlasBook: () => _select(_VaultPage.atlasBook),
        );
      case _VaultPage.allCollections:
        return AllCollectionsScreen(
          onOpenCoins: () => _select(_VaultPage.coinSeries),
          onOpenPostcards: () => _select(_VaultPage.postcards),
          onOpenValuables: () => _select(_VaultPage.valuables),
          onOpenAntiques: () => _select(_VaultPage.antiques),
          onOpenSportsCards: () => _select(_VaultPage.sportsCards),
          onOpenDocuments: () => _select(_VaultPage.documents),
          onOpenStories: () => _select(_VaultPage.stories),
        );
      case _VaultPage.coinSeries:
        return const CoinSeriesExplorerScreen();
      case _VaultPage.collection:
        return const CoinsScreen();
      case _VaultPage.coinImport:
        return const CoinCollectionImportScreen();
      case _VaultPage.needList:
        return const NeedListScreen();
      case _VaultPage.postcards:
        return const PostcardsScreen();
      case _VaultPage.valuables:
        return const ValuablesScreen();
      case _VaultPage.photos:
        return const PhotosScreen();
      case _VaultPage.videos:
        return const VideosScreen();
      case _VaultPage.documents:
        return const DocumentsScreen();
      case _VaultPage.familyTree:
        return const FamilyTreeScreen();
      case _VaultPage.atlasBook:
        return const AtlasBookScreen();
      case _VaultPage.antiques:
        return const AntiquesScreen();
      case _VaultPage.sportsCards:
        return SportsCardsScreen(
          initialImagePath: _sportsCardQuickCaptureImagePath,
          onInitialImageConsumed: () {
            _sportsCardQuickCaptureImagePath = null;
          },
        );
      case _VaultPage.sportsCardSets:
        return const SportsCardSetManagerScreen();
      case _VaultPage.stories:
        return const StoriesScreen();
      case _VaultPage.quickCapture:
        return _QuickCapturePage(
          onOpenPhotos: () => _select(_VaultPage.photos),
          onOpenSportsCards: (imagePath) {
            setState(() {
              _sportsCardQuickCaptureImagePath = imagePath;
              _selectedPage = _VaultPage.sportsCards;
            });
          },
          onOpenCoins: () => _select(_VaultPage.coinSeries),
          onOpenDocuments: () => _select(_VaultPage.documents),
        );
      case _VaultPage.syncStorage:
        return const SyncStorageScreen();
      case _VaultPage.help:
        return const HelpGettingStartedScreen();
      case _VaultPage.settings:
        return const SettingsScreen();
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
      selectedPage == _VaultPage.coinImport ||
      selectedPage == _VaultPage.needList;

  bool get _builtInCollectionPage =>
      selectedPage == _VaultPage.allCollections ||
      _coinPage ||
      selectedPage == _VaultPage.postcards ||
      selectedPage == _VaultPage.valuables ||
      selectedPage == _VaultPage.antiques ||
      selectedPage == _VaultPage.sportsCards ||
      selectedPage == _VaultPage.sportsCardSets;

  @override
  Widget build(BuildContext context) {
    const sidebarNavy = Color(0xFF061725);
    const antiqueGold = Color(0xFFC9A65A);

    return Material(
      color: sidebarNavy,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: SizedBox(
              height: 108,
              width: double.infinity,
              child: Image.asset(
                'assets/branding/heirloom_atlas_logo.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.account_balance_outlined,
                  size: 64,
                  color: antiqueGold,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: antiqueGold.withValues(alpha: .22)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              children: [
                _SidebarItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_outlined,
                  label: 'Home',
                  selected: selectedPage == _VaultPage.home,
                  onTap: () => onSelect(_VaultPage.home),
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  icon: Icons.photo_library_outlined,
                  selectedIcon: Icons.photo_library_outlined,
                  label: 'Photos',
                  selected: selectedPage == _VaultPage.photos,
                  onTap: () => onSelect(_VaultPage.photos),
                ),
                _SidebarItem(
                  icon: Icons.video_library_outlined,
                  selectedIcon: Icons.video_library_outlined,
                  label: 'Videos',
                  selected: selectedPage == _VaultPage.videos,
                  onTap: () => onSelect(_VaultPage.videos),
                ),
                _SidebarItem(
                  icon: Icons.account_tree_outlined,
                  selectedIcon: Icons.account_tree_outlined,
                  label: 'Family Tree',
                  selected: selectedPage == _VaultPage.familyTree,
                  onTap: () => onSelect(_VaultPage.familyTree),
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  icon: Icons.auto_stories_outlined,
                  selectedIcon: Icons.auto_stories_outlined,
                  label: 'Atlas Book',
                  selected: selectedPage == _VaultPage.atlasBook,
                  onTap: () => onSelect(_VaultPage.atlasBook),
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2_outlined,
                  label: 'All Collections',
                  selected: _builtInCollectionPage,
                  trailing: IconButton(
                    tooltip: allCollectionsExpanded ? 'Collapse' : 'Expand',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: Icon(
                      allCollectionsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                    onPressed: () => onAllCollectionsExpandedChanged(
                      !allCollectionsExpanded,
                    ),
                  ),
                  onTap: () => onSelect(_VaultPage.allCollections),
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
                          selectedIcon: Icons.monetization_on_outlined,
                          label: 'Coins',
                          selected: _coinPage,
                          trailing: Icon(
                            coinsExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                          ),
                          onTap: () => onCoinsExpandedChanged(!coinsExpanded),
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
                                  selectedIcon: Icons.grid_view_outlined,
                                  label: 'Coin Series',
                                  selected:
                                      selectedPage == _VaultPage.coinSeries,
                                  onTap: () => onSelect(_VaultPage.coinSeries),
                                  compact: true,
                                ),
                                _SidebarItem(
                                  icon: Icons.folder_outlined,
                                  selectedIcon: Icons.folder_outlined,
                                  label: 'Collection',
                                  selected:
                                      selectedPage == _VaultPage.collection,
                                  onTap: () => onSelect(_VaultPage.collection),
                                  compact: true,
                                ),
                                _SidebarItem(
                                  icon: Icons.upload_file_outlined,
                                  selectedIcon: Icons.upload_file_outlined,
                                  label: 'Import Collection',
                                  selected:
                                      selectedPage == _VaultPage.coinImport,
                                  onTap: () => onSelect(_VaultPage.coinImport),
                                  compact: true,
                                ),
                                _SidebarItem(
                                  icon: Icons.checklist_outlined,
                                  selectedIcon: Icons.checklist_outlined,
                                  label: 'Need List',
                                  selected: selectedPage == _VaultPage.needList,
                                  onTap: () => onSelect(_VaultPage.needList),
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                          secondChild: const SizedBox.shrink(),
                        ),
                        _SidebarItem(
                          icon: Icons.markunread_mailbox_outlined,
                          selectedIcon: Icons.markunread_mailbox_outlined,
                          label: 'Postcards',
                          selected: selectedPage == _VaultPage.postcards,
                          onTap: () => onSelect(_VaultPage.postcards),
                          compact: true,
                        ),
                        _SidebarItem(
                          icon: Icons.diamond_outlined,
                          selectedIcon: Icons.diamond_outlined,
                          label: 'Valuables',
                          selected: selectedPage == _VaultPage.valuables,
                          onTap: () => onSelect(_VaultPage.valuables),
                          compact: true,
                        ),
                        _SidebarItem(
                          icon: Icons.inventory_2_outlined,
                          selectedIcon: Icons.inventory_2_outlined,
                          label: 'Antiques',
                          selected: selectedPage == _VaultPage.antiques,
                          onTap: () => onSelect(_VaultPage.antiques),
                          compact: true,
                        ),
                        _SidebarItem(
                          icon: Icons.sports_baseball_outlined,
                          selectedIcon: Icons.sports_baseball_outlined,
                          label: 'Sports Cards',
                          selected: selectedPage == _VaultPage.sportsCards,
                          onTap: () => onSelect(_VaultPage.sportsCards),
                          compact: true,
                        ),
                        _SidebarItem(
                          icon: Icons.settings_suggest_outlined,
                          selectedIcon: Icons.settings_suggest_outlined,
                          label: 'Manage Card Sets',
                          selected: selectedPage == _VaultPage.sportsCardSets,
                          onTap: () => onSelect(_VaultPage.sportsCardSets),
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
                  selectedIcon: Icons.description_outlined,
                  label: 'Documents',
                  selected: selectedPage == _VaultPage.documents,
                  onTap: () => onSelect(_VaultPage.documents),
                ),
                _SidebarItem(
                  icon: Icons.menu_book_outlined,
                  selectedIcon: Icons.menu_book_outlined,
                  label: 'Stories',
                  selected: selectedPage == _VaultPage.stories,
                  onTap: () => onSelect(_VaultPage.stories),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFA68B4F)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: _SidebarItem(
              icon: Icons.add_a_photo_outlined,
              selectedIcon: Icons.add_a_photo_outlined,
              label: 'Quick Capture',
              selected: selectedPage == _VaultPage.quickCapture,
              onTap: () => onSelect(_VaultPage.quickCapture),
              compact: true,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: AddCollectionSidebarButton(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: _SidebarItem(
              icon: Icons.sync_outlined,
              selectedIcon: Icons.sync_outlined,
              label: 'Sync & Storage',
              selected: selectedPage == _VaultPage.syncStorage,
              onTap: () => onSelect(_VaultPage.syncStorage),
              compact: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: _SidebarItem(
              icon: Icons.help_outline,
              selectedIcon: Icons.help_outline,
              label: 'Help & Getting Started',
              selected: selectedPage == _VaultPage.help,
              onTap: () => onSelect(_VaultPage.help),
              compact: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: _SidebarItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_outlined,
              label: 'Settings',
              selected: selectedPage == _VaultPage.settings,
              onTap: () => onSelect(_VaultPage.settings),
              compact: true,
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
    const antiqueGold = Color(0xFFC9A65A);
    const cream = Color(0xFFF3E9D1);
    const textColor = Color(0xFFD6E0E7);
    const mutedColor = Color(0xFF91A4B0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? const Color(0xFF0A2943) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: selected
              ? BorderSide(color: antiqueGold.withValues(alpha: .44), width: .8)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 12,
            ),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: compact ? 18 : 20,
                  color: selected ? antiqueGold : Colors.transparent,
                ),
                const SizedBox(width: 9),
                Icon(
                  selected ? selectedIcon : icon,
                  size: compact ? 18 : 20,
                  color: selected ? antiqueGold : mutedColor,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cream : textColor,
                      letterSpacing: selected ? .18 : 0,
                    ),
                  ),
                ),
                if (trailing != null)
                  IconTheme(
                    data: IconThemeData(
                      color: selected ? antiqueGold : mutedColor,
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

class _QuickCapturePage extends StatefulWidget {
  final VoidCallback onOpenPhotos;
  final ValueChanged<String?> onOpenSportsCards;
  final VoidCallback onOpenCoins;
  final VoidCallback onOpenDocuments;

  const _QuickCapturePage({
    required this.onOpenPhotos,
    required this.onOpenSportsCards,
    required this.onOpenCoins,
    required this.onOpenDocuments,
  });

  @override
  State<_QuickCapturePage> createState() => _QuickCapturePageState();
}

class _QuickCapturePageState extends State<_QuickCapturePage> {
  String? _selectedCollection;

  static const _collections = <({String name, IconData icon, String note})>[
    (
      name: 'Photos',
      icon: Icons.photo_library_outlined,
      note: 'Add family photos or images to the photo archive.',
    ),
    (
      name: 'Antiques',
      icon: Icons.inventory_2_outlined,
      note: 'Capture an antique and document its history.',
    ),
    (
      name: 'Valuables',
      icon: Icons.diamond_outlined,
      note: 'Add a valuable with photos and descriptive details.',
    ),
    (
      name: 'Coins',
      icon: Icons.monetization_on_outlined,
      note: 'Capture a coin for identification or cataloging.',
    ),
    (
      name: 'Sports Cards',
      icon: Icons.sports_baseball_outlined,
      note: 'Capture the front and back of a sports card.',
    ),
    (
      name: 'Documents',
      icon: Icons.description_outlined,
      note: 'Scan or add a family document.',
    ),
  ];

  void _showMobileMessage(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$action is reserved for the mobile capture pass. '
          'Choose Files is working on desktop now.',
        ),
      ),
    );
  }

  Future<List<String>> _pickImages() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    final filePath = file?.path;
    if (filePath == null || filePath.trim().isEmpty) {
      return const <String>[];
    }
    return <String>[filePath];
  }

  Future<void> _chooseSportsCardImage() async {
    String? selectedPath;

    final imagePath = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final fileName = selectedPath?.split(Platform.pathSeparator).last;

            return AlertDialog(
              title: const Text('Choose Sports Card Image'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose a photo or scan of the card first. After that, '
                      'Heirloom Atlas will open your card list so you can select '
                      'the matching card.',
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final paths = await _pickImages();
                        if (paths.isEmpty || !dialogContext.mounted) return;
                        setDialogState(() => selectedPath = paths.first);
                      },
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Choose Card Image'),
                    ),
                    if (fileName != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(fileName)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: selectedPath == null
                      ? null
                      : () => Navigator.pop(dialogContext, selectedPath),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Select Matching Card'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || imagePath == null || imagePath.trim().isEmpty) return;
    widget.onOpenSportsCards(imagePath);
  }

  Future<void> _chooseFiles() async {
    final collection = _selectedCollection;
    if (collection == null) return;

    if (collection == 'Antiques' || collection == 'Valuables') {
      final paths = await _pickImages();
      if (!mounted || paths.isEmpty) return;

      if (collection == 'Antiques') {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AntiqueEditScreen(initialImagePaths: paths),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ValuableEditScreen(initialImagePaths: paths),
          ),
        );
      }
      return;
    }

    // These modules already have specialized catalog/source workflows.
    // Route into those workflows instead of creating duplicate editors.
    switch (collection) {
      case 'Photos':
        widget.onOpenPhotos();
        break;
      case 'Sports Cards':
        await _chooseSportsCardImage();
        break;
      case 'Coins':
        widget.onOpenCoins();
        break;
      case 'Documents':
        widget.onOpenDocuments();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF071A2B);
    const panel = Color(0xFF0B2742);
    const gold = Color(0xFFC9A65A);
    const cream = Color(0xFFF3E9D1);
    const muted = Color(0xFFAAB8C2);

    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(
        backgroundColor: navy,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Quick Capture',
          style: TextStyle(color: cream, fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: panel,
              border: Border.all(color: gold.withValues(alpha: .42)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.add_a_photo_outlined, color: gold, size: 38),
                SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADD TO HEIRLOOM ATLAS',
                        style: TextStyle(
                          color: cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Choose what you are adding first. Heirloom Atlas can '
                        'then present the right capture and cataloging tools.',
                        style: TextStyle(color: muted, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '1  CHOOSE A COLLECTION',
            style: TextStyle(
              color: gold,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050
                  ? 3
                  : constraints.maxWidth >= 680
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 12)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _collections.map((item) {
                  final selected = _selectedCollection == item.name;
                  return SizedBox(
                    width: width,
                    child: Material(
                      color: selected
                          ? const Color(0xFF123A59)
                          : panel.withValues(alpha: .82),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(
                          color: selected ? gold : gold.withValues(alpha: .24),
                        ),
                      ),
                      child: InkWell(
                        onTap: () =>
                            setState(() => _selectedCollection = item.name),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Icon(item.icon, color: gold, size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        color: cream,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item.note,
                                      style: const TextStyle(color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: gold,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 28),
          const Text(
            '2  CHOOSE HOW TO ADD IT',
            style: TextStyle(
              color: gold,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: _selectedCollection == null ? .46 : 1,
            child: IgnorePointer(
              ignoring: _selectedCollection == null,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _CaptureAction(
                    icon: Icons.camera_alt_outlined,
                    title: 'Camera',
                    subtitle: 'Take a new picture',
                    badge: 'MOBILE',
                    onTap: () => _showMobileMessage('Camera capture'),
                  ),
                  _CaptureAction(
                    icon: Icons.photo_outlined,
                    title: 'Camera Roll',
                    subtitle: 'Choose a recent phone photo',
                    badge: 'MOBILE',
                    onTap: () => _showMobileMessage('Camera Roll'),
                  ),
                  _CaptureAction(
                    icon: Icons.folder_open_outlined,
                    title: 'Choose Files',
                    subtitle: 'Select existing files from this device',
                    badge: 'DESKTOP + MOBILE',
                    onTap: _chooseFiles,
                  ),
                ],
              ),
            ),
          ),
          if (_selectedCollection == null) ...[
            const SizedBox(height: 12),
            const Text(
              'Select a collection to continue.',
              style: TextStyle(color: muted),
            ),
          ] else ...[
            const SizedBox(height: 18),
            Text(
              'Adding to: $_selectedCollection',
              style: const TextStyle(color: cream, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose Files now uses the collection’s existing workflow. '
              'Antiques and Valuables open a new item with the selected images; '
              'specialized catalogs open their existing module.',
              style: TextStyle(color: muted),
            ),
          ],
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: panel.withValues(alpha: .55),
              border: Border.all(color: gold.withValues(alpha: .20)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: gold),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Safe by default: Quick Capture will add to the catalog. '
                    'It will not automatically move, rename, or delete your originals.',
                    style: TextStyle(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  const _CaptureAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const panel = Color(0xFF0B2742);
    const gold = Color(0xFFC9A65A);
    const cream = Color(0xFFF3E9D1);
    const muted = Color(0xFFAAB8C2);

    return SizedBox(
      width: 290,
      child: Material(
        color: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: gold.withValues(alpha: .28)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(icon, color: gold, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: cream,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(color: muted)),
                      const SizedBox(height: 8),
                      Text(
                        badge,
                        style: const TextStyle(
                          color: gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ],
                  ),
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
    const gold = Color(0xFFC9A65A);

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
                  Container(width: 42, height: 1, color: gold),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'COMING LATER',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: gold,
                      letterSpacing: 1.1,
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
