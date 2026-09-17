import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/custom_collection.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenCollections;
  final VoidCallback? onOpenPhotos;
  final VoidCallback? onOpenFamilyTree;
  final VoidCallback? onOpenAtlasBook;

  const HomeScreen({
    super.key,
    this.onOpenCollections,
    this.onOpenPhotos,
    this.onOpenFamilyTree,
    this.onOpenAtlasBook,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _loading = true;
  List<CustomCollection> _customCollections = const [];
  int _photoCount = 0;
  int _photoSourceCount = 0;
  int _familyPeopleCount = 0;

  static const _navy = Color(0xFF061725);
  static const _panel = Color(0xE6081E33);
  static const _panelDeep = Color(0xF2071A2B);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFF91A4B0);
  static const _archiveBlue = Color(0xFF4EA3E3);
  static const _archiveGreen = Color(0xFF63B58B);
  static const _archiveRed = Color(0xFFC96565);
  static const _archiveWhite = Color(0xFFF4F1E8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _databaseHelper.getCustomCollections(),
        _databaseHelper.getIndexedPhotos(),
        _databaseHelper.getPhotoSources(),
        _databaseHelper.getFamilyPeople(),
      ]);

      final collections = results[0] as List<CustomCollection>;

      if (!mounted) return;
      setState(() {
        _customCollections = collections;
        _photoCount = (results[1] as List).length;
        _photoSourceCount = (results[2] as List).length;
        _familyPeopleCount = (results[3] as List).length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _collectionCategoryCount => 6 + _customCollections.length;

  BoxDecoration _panelDecoration({double opacity = .94}) {
    return BoxDecoration(
      color: _panel.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: _gold.withValues(alpha: .34), width: .8),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .16),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }


  Widget _shadowArtPair({
    required IconData primary,
    required IconData secondary,
    Color primaryColor = _archiveWhite,
    Color secondaryColor = _gold,
  }) {
    return IgnorePointer(
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(1.04, .10),
            child: Icon(
              primary,
              size: 185,
              color: primaryColor.withValues(alpha: .035),
            ),
          ),
          Align(
            alignment: const Alignment(.78, .88),
            child: Transform.rotate(
              angle: -.18,
              child: Icon(
                secondary,
                size: 92,
                color: secondaryColor.withValues(alpha: .035),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _navy.withValues(alpha: .52),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
            children: [
              _buildHero(),
              const SizedBox(height: 14),
              _buildArchiveAtGlance(),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, inner) {
                  if (inner.maxWidth < 900) {
                    return Column(
                      children: [
                        _buildContinueExploring(),
                        const SizedBox(height: 14),
                        _buildPurposePanel(),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildContinueExploring()),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: _buildPurposePanel()),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      height: 184,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _panelDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withValues(alpha: .52), width: .9),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/heirloom_atlas_banner.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF061725).withValues(alpha: .90),
                  const Color(0xFF061725).withValues(alpha: .58),
                  const Color(0xFF061725).withValues(alpha: .20),
                ],
                stops: const [0, .52, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOME',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Your family archive, in one place.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: _cream,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Organize the things. Connect the people. Pass the story forward.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _cream.withValues(alpha: .78),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(width: 38, height: 1, color: _gold),
                    const SizedBox(width: 10),
                    Text(
                      'HEIRLOOM ATLAS',
                      style: TextStyle(
                        color: _gold.withValues(alpha: .88),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveAtGlance() {
    return Container(
      decoration: _panelDecoration(),
      child: Stack(
        children: [
          Positioned.fill(
            child: _shadowArtPair(
              primary: Icons.photo_library_outlined,
              secondary: Icons.camera_alt_outlined,
              primaryColor: _archiveBlue,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          _sectionTitle(
            'YOUR ARCHIVE AT A GLANCE',
            'A live snapshot of what Heirloom Atlas is preserving.',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = 10.0;
              final columns = constraints.maxWidth < 760 ? 2 : 4;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              final cards = [
                _statCard(
                  width: width,
                  icon: Icons.photo_library_outlined,
                  value: _loading ? '—' : '$_photoCount',
                  label: 'Photos',
                  detail: _loading
                      ? 'Loading archive'
                      : '$_photoSourceCount ${_photoSourceCount == 1 ? 'source' : 'sources'} connected',
                  onTap: widget.onOpenPhotos,
                  accent: _archiveBlue,
                ),
                _statCard(
                  width: width,
                  icon: Icons.account_tree_outlined,
                  value: _loading ? '—' : '$_familyPeopleCount',
                  label: 'People',
                  detail: 'In your Family Tree',
                  onTap: widget.onOpenFamilyTree,
                  accent: _archiveGreen,
                ),
                _statCard(
                  width: width,
                  icon: Icons.inventory_2_outlined,
                  value: _loading ? '—' : '$_collectionCategoryCount',
                  label: 'Collections',
                  detail: _customCollections.isEmpty
                      ? 'Built-in collection areas'
                      : '${_customCollections.length} custom added',
                  onTap: widget.onOpenCollections,
                  accent: _archiveRed,
                ),
                _statCard(
                  width: width,
                  icon: Icons.auto_stories_outlined,
                  value: 'Atlas',
                  label: 'Book',
                  detail: 'Turn your archive into a legacy',
                  onTap: widget.onOpenAtlasBook,
                  accent: _archiveWhite,
                ),
              ];

              if (columns == 4) {
                return Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      cards[i],
                      if (i != cards.length - 1) SizedBox(width: gap),
                    ],
                  ],
                );
              }

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: cards,
              );
            },
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required double width,
    required IconData icon,
    required String value,
    required String label,
    required String detail,
    required VoidCallback? onTap,
    Color accent = _gold,
  }) {
    return SizedBox(
      width: width,
      height: 112,
      child: Material(
        color: const Color(0xFF0A2943).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(3),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: _gold.withValues(alpha: .24)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: accent.withValues(alpha: .72)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .10),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: accent, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _cream,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          color: _gold,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: _gold.withValues(alpha: .62),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueExploring() {
    return Container(
      decoration: _panelDecoration(),
      child: Stack(
        children: [
          Positioned.fill(
            child: _shadowArtPair(
              primary: Icons.explore_outlined,
              secondary: Icons.account_tree_outlined,
              primaryColor: _archiveGreen,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          _sectionTitle(
            'CONTINUE EXPLORING',
            'The main places where your family history comes together.',
          ),
          const SizedBox(height: 11),
          _exploreRow(
            icon: Icons.photo_library_outlined,
            title: 'Photos',
            detail: 'Browse, identify, organize, and preserve your photo archive.',
            onTap: widget.onOpenPhotos,
            accent: _archiveBlue,
          ),
          _exploreRow(
            icon: Icons.account_tree_outlined,
            title: 'Family Tree',
            detail: 'Explore people, generations, and family relationships.',
            onTap: widget.onOpenFamilyTree,
            accent: _archiveGreen,
          ),
          _exploreRow(
            icon: Icons.inventory_2_outlined,
            title: 'All Collections',
            detail: 'Coins, antiques, postcards, valuables, cards, and more.',
            onTap: widget.onOpenCollections,
            accent: _archiveRed,
          ),
          _exploreRow(
            icon: Icons.auto_stories_outlined,
            title: 'Atlas Book',
            detail: 'Build the keepsake that brings the archive together.',
            onTap: widget.onOpenAtlasBook,
            accent: _archiveWhite,
            last: true,
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _exploreRow({
    required IconData icon,
    required String title,
    required String detail,
    required VoidCallback? onTap,
    Color accent = _gold,
    bool last = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: BorderSide(color: _gold.withValues(alpha: .14)),
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: accent.withValues(alpha: .62)),
              ),
              child: Icon(icon, size: 19, color: accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _cream,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 10.8),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _gold.withValues(alpha: .62)),
          ],
        ),
      ),
    );
  }

  Widget _buildPurposePanel() {
    return Container(
      constraints: const BoxConstraints(minHeight: 292),
      decoration: _panelDecoration(),
      child: Stack(
        children: [
          Positioned.fill(
            child: _shadowArtPair(
              primary: Icons.public_outlined,
              secondary: Icons.auto_stories_outlined,
              primaryColor: _archiveWhite,
              secondaryColor: _archiveRed,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          _sectionTitle(
            'THE ARCHIVE HAS A PURPOSE',
            'More than storage — a legacy you can hand forward.',
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A2946),
                border: Border.all(
                  color: _archiveGreen.withValues(alpha: .70),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _archiveGreen.withValues(alpha: .10),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Icon(
                Icons.explore_outlined,
                color: _archiveGreen,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 17),
          Text(
            'Collection management first.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _cream,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Family connections when they matter. A legacy to pass forward.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _cream.withValues(alpha: .68),
              height: 1.4,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 17),
          Container(height: 1, color: _gold.withValues(alpha: .18)),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(Icons.lock_open_outlined, color: _gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your collection is yours. Not ours.',
                  style: TextStyle(
                    color: _cream,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _gold,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.15,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _cream.withValues(alpha: .58),
            fontSize: 10.8,
          ),
        ),
      ],
    );
  }
}
