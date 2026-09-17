import 'dart:io';

import 'package:flutter/material.dart';

class HelpGettingStartedScreen extends StatefulWidget {
  const HelpGettingStartedScreen({super.key});

  @override
  State<HelpGettingStartedScreen> createState() =>
      _HelpGettingStartedScreenState();
}

class _HelpGettingStartedScreenState extends State<HelpGettingStartedScreen> {
  static const Color _navy = Color(0xFF071A2B);
  static const Color _panel = Color(0xFF0B2742);
  static const Color _gold = Color(0xFFC9A65A);
  static const Color _cream = Color(0xFFF3E9D1);
  static const Color _muted = Color(0xFFAAB8C2);
  static const String _betaVersion = 'Private Beta 0.1.5';

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  static const List<_HelpSection> _sections = [
    _HelpSection(
      title: 'Getting Started',
      icon: Icons.flag_outlined,
      intro:
          'A simple path for building your Heirloom Atlas without trying to organize everything at once.',
      items: [
        _HelpItem(
          question: 'What should I do first?',
          answer:
              'Start with one area that matters most to you. Connect a photo source, import a GEDCOM family tree, or add a small collection. You do not need to set up everything before Heirloom Atlas becomes useful.',
        ),
        _HelpItem(
          question: 'What is a good first-week workflow?',
          answer:
              'Connect one photo source, import or begin your Family Tree, identify a few important people, connect a few meaningful objects or documents, then explore those people in their Person Hubs.',
        ),
        _HelpItem(
          question: 'Do I need to organize everything at once?',
          answer:
              'No. Work with the people, photos, and objects that matter most first. Heirloom Atlas is designed to improve gradually.',
        ),
      ],
    ),
    _HelpSection(
      title: 'Photos',
      icon: Icons.photo_library_outlined,
      intro:
          'Photo sources, people, metadata, duplicate review, and safe cleanup.',
      items: [
        _HelpItem(
          question: 'Does Heirloom Atlas move or delete my original photos?',
          answer:
              'Connecting a photo source does not move or delete your originals. Heirloom Atlas catalogs files where they already live. Moving items to Duplicate Trash is deliberate, and permanent deletion still requires confirmation.',
        ),
        _HelpItem(
          question: 'Where are my photos stored?',
          answer:
              'Your photos remain in the locations you choose, such as your computer, OneDrive, iCloud-accessible folders, an external drive, or another supported file location. Heirloom Atlas catalogs them without requiring one giant copied library. Connected photo folders are monitored for changes while Heirloom Atlas is running.',
        ),
        _HelpItem(
          question: 'What is Duplicate Review?',
          answer:
              'Duplicate Review separates Exact-looking and Similar matches. Exact-looking matches are byte-for-byte verified copies; Similar matches need visual review. Select Recommended can choose safe removal candidates, and you can review LEFT and RIGHT before moving selected copies to Duplicate Trash.',
        ),
        _HelpItem(
          question: 'Can I recover a photo from Duplicate Trash?',
          answer:
              'Yes. Photos moved to Duplicate Trash remain recoverable until you deliberately choose permanent deletion.',
        ),
        _HelpItem(
          question: 'Do I need to fill in every metadata field?',
          answer:
              'No. Add as much or as little as you know. Quick Details and batch editing can update dates, places, people, descriptions, and tags. Supported portable fields are also written to supported original photo files when saved so useful information can travel with the file. Heirloom Atlas-only notes and uncertain or approximate dates can remain catalog information.',
        ),
        _HelpItem(
          question:
              'Will new photos appear after I add them to a connected folder?',
          answer:
              'Yes. While Heirloom Atlas is running, connected photo folders are watched for image changes and the catalog is refreshed after changes are detected. You can also use Check for Changes from Files & Backup.',
        ),
        _HelpItem(
          question:
              'What happens when I use Quick Details or batch metadata editing?',
          answer:
              'Heirloom Atlas saves changes to its catalog. For supported photo formats, portable fields such as people, tags, an exact date, location, and description can also be written into the original file. Before writing embedded metadata, Heirloom Atlas creates a safety backup of that photo.',
        ),
      ],
    ),
    _HelpSection(
      title: 'Family Tree',
      icon: Icons.account_tree_outlined,
      intro:
          'Import family history, explore relationships, and connect people to the things they left behind.',
      items: [
        _HelpItem(
          question: 'Can I import an existing family tree?',
          answer:
              'Yes. Heirloom Atlas supports GEDCOM import so you can bring in an existing genealogy instead of rebuilding it by hand.',
        ),
        _HelpItem(
          question: 'What is a Person Hub?',
          answer:
              'A Person Hub brings together a person’s family information and the photos, documents, antiques, postcards, heirlooms, and other collection items connected to them.',
        ),
        _HelpItem(
          question: 'Can one item be connected to several people?',
          answer:
              'Yes. A photo, document, heirloom, or other record can be part of several people’s stories.',
        ),
        _HelpItem(
          question: 'Do I have to use the Family Tree?',
          answer:
              'No. Collections can stand on their own. Family connections are available when they add meaning.',
        ),
      ],
    ),
    _HelpSection(
      title: 'Collections & Heirlooms',
      icon: Icons.inventory_2_outlined,
      intro:
          'Catalog antiques, coins, postcards, sports cards, valuables, documents, and custom collections.',
      items: [
        _HelpItem(
          question: 'Can I create my own type of collection?',
          answer:
              'Yes. Custom collections let Heirloom Atlas adapt to the things your family actually preserves.',
        ),
        _HelpItem(
          question: 'Can I connect collection items to Family Tree people?',
          answer:
              'Yes. Connected items can automatically appear in that person’s Heirloom Atlas section inside the Person Hub.',
        ),
        _HelpItem(
          question: 'What should I record about an heirloom?',
          answer:
              'Start with what it is, who owned or used it, approximate dates, where it came from, photos, and any story your family knows. Unknown details can be added later.',
        ),
      ],
    ),
    _HelpSection(
      title: 'Atlas Book',
      icon: Icons.auto_stories_outlined,
      intro:
          'Turn selected people, photos, stories, and family history into a book.',
      items: [
        _HelpItem(
          question: 'What is Atlas Book?',
          answer:
              'Atlas Book is the book-building area of Heirloom Atlas. It can combine selected people, generations, photos, family-tree pages, stories, and collection material into a family keepsake.',
        ),
        _HelpItem(
          question: 'Can I make more than one book?',
          answer:
              'Yes. Books are meant to be saved separately, so you can create different books for branches of the family, people, events, or themes.',
        ),
      ],
    ),
    _HelpSection(
      title: 'Files, Privacy & Backups',
      icon: Icons.shield_outlined,
      intro:
          'Understand where your information lives and how Heirloom Atlas protects your control of it.',
      items: [
        _HelpItem(
          question: 'Who owns my collection?',
          answer:
              'You do. Your collection is yours. Not ours. Heirloom Atlas is being designed around portability and avoiding lock-in.',
        ),
        _HelpItem(
          question: 'What happens if I remove a file location?',
          answer:
              'Removing a file location removes that source and its Heirloom Atlas catalog mappings. It does not delete, move, or modify the original files or folder. You can add the location again later if needed.',
        ),
        _HelpItem(
          question: 'What does Back Up Now protect?',
          answer:
              'Back Up Now creates a safety copy of the Heirloom Atlas catalog database, including the app records used to organize your collection. It does not duplicate your original photos, videos, documents, or other source files. Keep a separate backup strategy for irreplaceable originals.',
        ),
        _HelpItem(
          question: 'What is Files & Backup?',
          answer:
              'Files & Backup shows the file locations Heirloom Atlas knows about, lets you add or remove locations, check for changes, create a catalog database backup, and access advanced sync details. Google Photos is a future source and is not yet directly connected in this beta.',
        ),
        _HelpItem(
          question: 'Can I move to another computer later?',
          answer:
              'That is part of the portability goal. Heirloom Atlas should let you move or restore your catalog without trapping your originals inside the app.',
        ),
      ],
    ),
  ];

  static const List<_Tip> _tips = [
    _Tip(
      icon: Icons.favorite_border,
      title: 'Start with the people who matter most',
      text:
          'Identifying a few important family members makes Person Hubs and connected photos useful very quickly.',
    ),
    _Tip(
      icon: Icons.layers_outlined,
      title: 'Do one source at a time',
      text:
          'Connect and understand one photo source before adding every drive and cloud account you own.',
    ),
    _Tip(
      icon: Icons.delete_sweep_outlined,
      title: 'Review before deleting',
      text:
          'Use Duplicate Review and recoverable trash rather than making large permanent deletions all at once.',
    ),
    _Tip(
      icon: Icons.edit_note_outlined,
      title: 'Imperfect information is still useful',
      text:
          'An approximate year, likely place, or partial story is better than leaving an important item disconnected.',
    ),
    _Tip(
      icon: Icons.sell_outlined,
      title: 'Add details where they are useful',
      text:
          'Quick Details is ideal for one photo; batch editing is faster for groups. Portable metadata can travel with supported original photo files.',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSection(_HelpSection section) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (section.title.toLowerCase().contains(q) ||
        section.intro.toLowerCase().contains(q)) {
      return true;
    }
    return section.items.any(
      (item) =>
          item.question.toLowerCase().contains(q) ||
          item.answer.toLowerCase().contains(q),
    );
  }

  List<_HelpItem> _visibleItems(_HelpSection section) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty ||
        section.title.toLowerCase().contains(q) ||
        section.intro.toLowerCase().contains(q)) {
      return section.items;
    }
    return section.items
        .where(
          (item) =>
              item.question.toLowerCase().contains(q) ||
              item.answer.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleSections = _sections.where(_matchesSection).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: _navy.withValues(alpha: .94),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Help & Getting Started',
          style: TextStyle(color: _cream, fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _panel.withValues(alpha: .92),
              border: Border.all(color: _gold.withValues(alpha: .38)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.explore_outlined, color: _gold, size: 40),
                SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW TO HEIRLOOM ATLAS?',
                        style: TextStyle(
                          color: _cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Start small. Organize what matters first, connect the people when it adds meaning, and build your family archive over time.',
                        style: TextStyle(color: _muted, fontSize: 15),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Your collection is yours. Not ours.',
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search help, tips, and FAQs...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          if (_query.isEmpty) ...[
            const Text(
              'START HERE',
              style: TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            _startHereCard(),
            const SizedBox(height: 24),
            const Text(
              'HANDY TIPS',
              style: TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            _tipGrid(),
            const SizedBox(height: 24),
          ],
          const Text(
            'HELP & FAQ',
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          if (visibleSections.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _panel.withValues(alpha: .6),
                border: Border.all(color: _gold.withValues(alpha: .18)),
              ),
              child: Text(
                'No help topics matched “$_query”. Try another word.',
                style: const TextStyle(color: _muted),
              ),
            )
          else
            ...visibleSections.map(_sectionCard),
          const SizedBox(height: 30),
          _betaFeedbackCard(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _panel.withValues(alpha: .58),
              border: Border.all(color: _gold.withValues(alpha: .20)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, color: _gold),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Heirloom Atlas is built around a simple principle: your collection is yours. Not ours. Keep your originals, keep your options, and avoid lock-in.',
                    style: TextStyle(color: _muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _betaFeedbackCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: .72),
        border: Border.all(color: _gold.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.bug_report_outlined, color: _gold, size: 28),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEND BETA FEEDBACK',
                  style: TextStyle(
                    color: _cream,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Found a problem or have an idea? Send feedback from this beta build. The app version is included automatically.',
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          OutlinedButton.icon(
            onPressed: _showBetaFeedbackDialog,
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('SEND FEEDBACK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBetaFeedbackDialog() async {
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send Beta Feedback'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tell us what happened, what you expected, or what would make Heirloom Atlas better.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 5,
                maxLines: 9,
                decoration: const InputDecoration(
                  hintText: 'Type your feedback here...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Version: $_betaVersion',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final feedback = controller.text.trim();
              if (feedback.isEmpty) return;

              final emailUri = Uri(
                scheme: 'mailto',
                path: 'bch383@gmail.com',
                queryParameters: {
                  'subject': 'Heirloom Atlas $_betaVersion Feedback',
                  'body': 'Heirloom Atlas $_betaVersion\n\n$feedback',
                },
              );

              try {
                if (Platform.isWindows) {
                  await Process.start('cmd', [
                    '/c',
                    'start',
                    '',
                    emailUri.toString(),
                  ], runInShell: true);
                } else {
                  await Process.start(
                    emailUri.toString(),
                    const [],
                    runInShell: true,
                  );
                }

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
              } catch (error) {
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Could not open your email app. Please send beta feedback to bch383@gmail.com. Error: $error',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.send_outlined),
            label: const Text('SEND'),
          ),
        ],
      ),
    );

    controller.dispose();
  }

  Widget _startHereCard() {
    const steps = [
      ('1', 'Choose one area', 'Photos, Family Tree, or a collection.'),
      (
        '2',
        'Add a source',
        'Add one file location, GEDCOM, or collection and learn that workflow first.',
      ),
      (
        '3',
        'Identify key people',
        'Start with a few family members you know well.',
      ),
      (
        '4',
        'Connect the stories',
        'Link photos, documents, and heirlooms to people.',
      ),
      (
        '5',
        'Build from there',
        'Add detail gradually and create an Atlas Book when ready.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: .78),
        border: Border.all(color: _gold.withValues(alpha: .24)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: _gold.withValues(alpha: .16),
                  child: Text(
                    steps[i].$1,
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i].$2,
                        style: const TextStyle(
                          color: _cream,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(steps[i].$3, style: const TextStyle(color: _muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (i != steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tipGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 950 ? 2 : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _tips
              .map(
                (tip) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _panel.withValues(alpha: .62),
                      border: Border.all(color: _gold.withValues(alpha: .18)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(tip.icon, color: _gold, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tip.title,
                                style: const TextStyle(
                                  color: _cream,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                tip.text,
                                style: const TextStyle(color: _muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _sectionCard(_HelpSection section) {
    final items = _visibleItems(section);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: _panel.withValues(alpha: .70),
          border: Border.all(color: _gold.withValues(alpha: .18)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ExpansionTile(
          leading: Icon(section.icon, color: _gold),
          iconColor: _gold,
          collapsedIconColor: _muted,
          initiallyExpanded: _query.isNotEmpty,
          title: Text(
            section.title,
            style: const TextStyle(color: _cream, fontWeight: FontWeight.w900),
          ),
          subtitle: Text(section.intro, style: const TextStyle(color: _muted)),
          children: [
            const Divider(height: 1),
            for (final item in items)
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                title: Text(
                  item.question,
                  style: const TextStyle(
                    color: _cream,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.answer,
                      style: const TextStyle(color: _muted, height: 1.45),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection {
  final String title;
  final IconData icon;
  final String intro;
  final List<_HelpItem> items;

  const _HelpSection({
    required this.title,
    required this.icon,
    required this.intro,
    required this.items,
  });
}

class _HelpItem {
  final String question;
  final String answer;

  const _HelpItem({required this.question, required this.answer});
}

class _Tip {
  final IconData icon;
  final String title;
  final String text;

  const _Tip({required this.icon, required this.title, required this.text});
}
