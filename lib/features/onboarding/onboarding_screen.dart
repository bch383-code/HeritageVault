import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/help_getting_started_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();

  int _page = 0;
  String _helpLevel = 'guided';
  final Set<String> _interests = {'photos'};
  final Set<String> _photoSources = {};
  String _changePolicy = 'ask';

  static const _pages = 7;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onboarding_help_level', _helpLevel);
    await prefs.setStringList('onboarding_interests', _interests.toList());
    await prefs.setStringList(
      'onboarding_photo_sources',
      _photoSources.toList(),
    );
    await prefs.setString('onboarding_change_policy', _changePolicy);
    await prefs.setBool('onboarding_completed', true);
    widget.onComplete();
  }

  void _next() {
    if (_page == _pages - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_page == 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
              child: Row(
                children: [
                  Text(
                    'HEIRLOOM ATLAS',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  Text('${_page + 1} of $_pages'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: LinearProgressIndicator(value: (_page + 1) / _pages),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) => setState(() => _page = value),
                children: [
                  _welcome(),
                  _helpChoice(),
                  _interestsChoice(),
                  _photoSourcesChoice(),
                  _changePolicyChoice(),
                  _optionalGuide(),
                  _ready(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 22),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _page == 0 ? null : _back,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  if (_page == 5) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _next,
                      child: const Text('Skip for now'),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _next,
                    icon: Icon(
                      _page == _pages - 1
                          ? Icons.explore_outlined
                          : Icons.arrow_forward,
                    ),
                    label: Text(
                      _page == _pages - 1 ? 'Start Exploring' : 'Continue',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageFrame({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    return _pageFrame(
      title: 'Welcome to Heirloom Atlas',
      subtitle:
          'Bring your family photos, collections, documents, stories, and '
          'family tree together.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 38),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your collection is yours. Not ours.',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Heirloom Atlas helps organize what you already have. '
                      'Your originals remain yours, and your family history '
                      'should never be locked into one app.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpChoice() {
    return _pageFrame(
      title: 'How much help would you like?',
      subtitle: 'You can change this later.',
      child: Column(
        children: [
          _radioCard(
            value: 'simple',
            groupValue: _helpLevel,
            icon: Icons.folder_outlined,
            title: 'Simple',
            description:
                'Just help me organize. Keep advanced tools mostly '
                'out of the way.',
            onChanged: (value) => setState(() => _helpLevel = value),
          ),
          _radioCard(
            value: 'guided',
            groupValue: _helpLevel,
            icon: Icons.auto_awesome_outlined,
            title: 'Guided — Recommended',
            description:
                'Suggest people, duplicates, missing information, '
                'and useful cleanup tasks while I stay in control.',
            onChanged: (value) => setState(() => _helpLevel = value),
          ),
          _radioCard(
            value: 'advanced',
            groupValue: _helpLevel,
            icon: Icons.tune,
            title: 'Advanced',
            description:
                'Show detailed organization, metadata, batch tools, '
                'recognition controls, and advanced options.',
            onChanged: (value) => setState(() => _helpLevel = value),
          ),
        ],
      ),
    );
  }

  Widget _interestsChoice() {
    return _pageFrame(
      title: 'What do you want to organize?',
      subtitle: 'Choose as many as you like. You can add anything later.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _checkCard('photos', Icons.photo_library_outlined, 'Photos & Videos'),
          _checkCard('tree', Icons.account_tree_outlined, 'Family Tree'),
          _checkCard('collections', Icons.inventory_2_outlined, 'Collections'),
          _checkCard(
            'stories',
            Icons.description_outlined,
            'Documents & Stories',
          ),
        ],
      ),
    );
  }

  Widget _photoSourcesChoice() {
    if (!_interests.contains('photos')) {
      return _pageFrame(
        title: 'Photo sources',
        subtitle: 'You did not select Photos & Videos, so you can skip this.',
        child: const Text(
          'Photo sources can be added at any time from the Photos area.',
        ),
      );
    }

    return _pageFrame(
      title: 'Where are your photos and videos?',
      subtitle:
          'Choose the places you may want to connect. Nothing is connected yet, '
          'and you do not need to move everything into one location.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _checkCard('computer', Icons.computer, 'This Computer'),
          _checkCard('onedrive', Icons.cloud_outlined, 'OneDrive'),
          _checkCard('google_drive', Icons.cloud_queue, 'Google Drive'),
          _checkCard(
            'google_photos',
            Icons.photo_library_outlined,
            'Google Photos — Coming Soon',
          ),
          _checkCard('icloud', Icons.cloud_circle_outlined, 'iCloud Photos'),
          _checkCard('external', Icons.usb_outlined, 'External Drive / USB'),
        ],
      ),
    );
  }

  Widget _changePolicyChoice() {
    return _pageFrame(
      title: 'How should Heirloom Atlas handle changes?',
      subtitle:
          'Analyzing your collection is different from changing your files.',
      child: Column(
        children: [
          _radioCard(
            value: 'ask',
            groupValue: _changePolicy,
            icon: Icons.shield_outlined,
            title: 'Protect originals — Recommended',
            description:
                'Analyze and organize the catalog freely, but ask '
                'without moving or deleting them. When you save supported portable '
                'photo metadata, those details can also be written into the original '
                'photo file so they travel with it.',
            onChanged: (value) => setState(() => _changePolicy = value),
          ),
          _radioCard(
            value: 'approved_automation',
            groupValue: _changePolicy,
            icon: Icons.settings_suggest_outlined,
            title: 'Allow approved automatic organization',
            description:
                'Use automation only for actions I have specifically '
                'approved.',
            onChanged: (value) => setState(() => _changePolicy = value),
          ),
        ],
      ),
    );
  }

  Widget _optionalGuide() {
    return _pageFrame(
      title: 'Want a quick tour before you start?',
      subtitle:
          'This is optional. You can always open Help & Getting Started later.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.help_outline, size: 38),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Read the Getting Started guide',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'See a simple five-step starting path, photo source monitoring, '
                      'metadata and duplicate guidance, Family Tree basics, collection '
                      'help, Atlas Book information, Files & Backup, privacy, and FAQs.',
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const HelpGettingStartedScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Read Getting Started'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Not ready? Choose “Skip for now” below. Nothing is lost.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ready() {
    String helpLabel = switch (_helpLevel) {
      'simple' => 'Simple',
      'advanced' => 'Advanced',
      _ => 'Guided',
    };

    final interestLabel = _interests.isEmpty
        ? 'Nothing selected yet'
        : _interests.map(_interestName).join(', ');

    final sourceLabel = _photoSources.isEmpty
        ? 'Add photo sources later'
        : _photoSources.map(_sourceName).join(', ');

    return _pageFrame(
      title: 'You’re ready to start building your Atlas.',
      subtitle: 'Here is the setup we’ll start with.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow(Icons.auto_awesome_outlined, 'Help', helpLabel),
              _summaryRow(
                Icons.inventory_2_outlined,
                'Organize',
                interestLabel,
              ),
              if (_interests.contains('photos'))
                _summaryRow(
                  Icons.photo_library_outlined,
                  'Photo sources',
                  sourceLabel,
                ),
              _summaryRow(
                Icons.shield_outlined,
                'Original files',
                _changePolicy == 'ask'
                    ? 'Protect originals; portable metadata may be written when saved'
                    : 'Approved automation allowed',
              ),
              const Divider(height: 30),
              const Text(
                'Heirloom Atlas can analyze your collection without moving '
                'or deleting your original files.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _radioCard({
    required String value,
    required String groupValue,
    required IconData icon,
    required String title,
    required String description,
    required ValueChanged<String> onChanged,
  }) {
    final selected = value == groupValue;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Radio<String>(
                value: value,
                groupValue: groupValue,
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkCard(String value, IconData icon, String label) {
    final selected = value == 'photos'
        ? _interests.contains(value)
        : _page == 2
        ? _interests.contains(value)
        : _photoSources.contains(value);

    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 205,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              final target = _page == 2 ? _interests : _photoSources;
              if (target.contains(value)) {
                target.remove(value);
              } else {
                target.add(value);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _interestName(String value) => switch (value) {
    'photos' => 'Photos & Videos',
    'tree' => 'Family Tree',
    'collections' => 'Collections',
    'stories' => 'Documents & Stories',
    _ => value,
  };

  String _sourceName(String value) => switch (value) {
    'computer' => 'This Computer',
    'onedrive' => 'OneDrive',
    'google_drive' => 'Google Drive',
    'google_photos' => 'Google Photos — Coming Soon',
    'icloud' => 'iCloud Photos',
    'external' => 'External Drive / USB',
    _ => value,
  };
}
