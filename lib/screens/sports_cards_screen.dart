import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../models/sports_card.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';
import '../services/sports_card_price_provider.dart';

class SportsCardsScreen extends StatefulWidget {
  final String? initialImagePath;
  final VoidCallback? onInitialImageConsumed;

  const SportsCardsScreen({
    super.key,
    this.initialImagePath,
    this.onInitialImageConsumed,
  });

  @override
  State<SportsCardsScreen> createState() => _SportsCardsScreenState();
}

class _SportsCardsScreenState extends State<SportsCardsScreen> {
  final _search = TextEditingController();

  List<Map<String, Object?>> _sets = const [];
  List<SportsCard> _cards = const [];
  Map<String, int> _summary = const {};

  String? _selectedSourceKey;
  String _filter = 'All';
  bool _loading = true;
  final SportsCardPriceProvider _priceProvider = SportsCardsProPriceProvider();
  String _pricingToken = '';
  String? _pendingQuickCaptureImagePath;

  @override
  void initState() {
    super.initState();
    _pendingQuickCaptureImagePath = widget.initialImagePath;
    _loadSets();

    if (_pendingQuickCaptureImagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Quick Capture image ready. Select the matching card to attach it.',
            ),
          ),
        );
      });
    }
  }

  Future<void> _loadSets({String? preferSourceKey}) async {
    final sets = await DatabaseHelper.instance.getInstalledSportsCardSets();

    if (!mounted) return;

    String? selected = preferSourceKey ?? _selectedSourceKey;

    if (sets.isNotEmpty && !sets.any((set) => set['source_key'] == selected)) {
      selected = sets.first['source_key'] as String?;
    }

    setState(() {
      _sets = sets;
      _selectedSourceKey = selected;
      _loading = false;
    });

    await _loadCards();
  }

  Future<void> _loadCards() async {
    final sourceKey = _selectedSourceKey;

    if (sourceKey == null) {
      if (!mounted) return;
      setState(() {
        _cards = const [];
        _summary = const {};
      });
      return;
    }

    final cards = await DatabaseHelper.instance.getSportsCards(
      sourceKey: sourceKey,
      searchText: _search.text,
      status: _filter,
    );

    final summary = await DatabaseHelper.instance.getSportsCardSummary(
      sourceKey: sourceKey,
    );

    if (!mounted) return;

    setState(() {
      _cards = cards;
      _summary = summary;
    });
  }

  Map<String, Object?>? get _selectedSet {
    final sourceKey = _selectedSourceKey;
    if (sourceKey == null) return null;

    for (final set in _sets) {
      if (set['source_key'] == sourceKey) return set;
    }
    return null;
  }

  Future<void> _browseChecklists() async {
    final result = await showDialog<_ImportedSetResult>(
      context: context,
      builder: (_) => const _AddSportsCardSetDialog(),
    );

    if (result == null) return;

    final count = await DatabaseHelper.instance.importSportsCardSet(
      sourceKey: result.sourceKey,
      sourceName: 'CardLists',
      sport: result.sport,
      year: result.year,
      brand: result.brand,
      setName: result.setName,
      cards: result.cards,
    );

    await _loadSets(preferSourceKey: result.sourceKey);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${result.year} ${result.brand} ${result.setName} '
          '($count cards) to My Sets.',
        ),
      ),
    );
  }

  Future<void> _removeSelectedSet() async {
    final selectedSet = _selectedSet;
    final sourceKey = _selectedSourceKey;
    if (selectedSet == null || sourceKey == null) return;

    final year = selectedSet['year']?.toString() ?? '';
    final brand = selectedSet['brand']?.toString() ?? '';
    final setName = selectedSet['set_name']?.toString() ?? '';
    final displayName = [year, brand, setName]
        .where((part) => part.trim().isNotEmpty)
        .join(' ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Card Set?'),
        content: Text(
          'Remove "$displayName" from Heirloom Atlas?\n\n'
          'This removes this set and its card records from your collection. '
          'It does not affect any original photos or files on your computer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove Set'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = await DatabaseHelper.instance.database;

    await DatabaseHelper.instance.createDatabaseBackup(
      reason: 'before_remove_sports_card_set',
    );

    await db.transaction((txn) async {
      final catalogIds = await txn.query(
        'sports_card_catalog',
        columns: ['id'],
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );

      for (final row in catalogIds) {
        await txn.delete(
          'sports_card_collection',
          where: 'catalog_id = ?',
          whereArgs: [row['id']],
        );
      }

      await txn.delete(
        'sports_card_catalog',
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );

      await txn.delete(
        'sports_card_sets',
        where: 'source_key = ?',
        whereArgs: [sourceKey],
      );
    });

    await _loadSets();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$displayName removed.')),
    );
  }

  Future<void> _changeStatus(SportsCard card, String status) async {
    await DatabaseHelper.instance.updateSportsCard(
      card.copyWith(
        status: status,
        quantityOwned: status == 'Owned'
            ? (card.quantityOwned == 0 ? 1 : card.quantityOwned)
            : status == 'Need'
            ? 0
            : card.quantityOwned,
      ),
    );

    await _loadCards();
  }

  Future<void> _openCardDetails(SportsCard card) async {
    final pendingImagePath = _pendingQuickCaptureImagePath;
    final cardForEditor = pendingImagePath == null
        ? card
        : card.copyWith(imagePath: pendingImagePath);

    final updated = await showDialog<SportsCard>(
      context: context,
      builder: (_) => _SportsCardDetailDialog(
        card: cardForEditor,
        onOpenEbay: () => _searchEbay(card),
      ),
    );

    if (updated == null) return;

    if (_pendingQuickCaptureImagePath != null) {
      _pendingQuickCaptureImagePath = null;
      widget.onInitialImageConsumed?.call();
    }
    await DatabaseHelper.instance.updateSportsCard(updated);
    await _loadCards();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${updated.player} updated.')));
  }

  Future<void> _searchEbay(SportsCard card) async {
    final query = [
      card.year,
      card.brand,
      card.player,
      '#${card.cardNumber}',
      if (card.attributes.trim().isNotEmpty) card.attributes.trim(),
    ].join(' ');

    final uri = Uri.https('www.ebay.com', '/sch/i.html', {
      '_nkw': query,
      '_sacat': '0',
    });

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the eBay search.')),
      );
    }
  }

  Future<void> _lookupValue(SportsCard card) async {
    final result = await showDialog<_CardValueLookupResult>(
      context: context,
      builder: (_) => _CardValueLookupDialog(
        card: card,
        provider: _priceProvider,
        initialToken: _pricingToken,
      ),
    );

    if (result == null) return;

    _pricingToken = result.token;

    await DatabaseHelper.instance.updateSportsCard(
      card.copyWith(
        value: result.value,
        valueSource: result.source,
        valueUpdatedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await _loadCards();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved ${result.source} value '
          '\$${result.value.toStringAsFixed(2)} for ${card.player}.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owned = _summary['owned'] ?? 0;
    final need = _summary['needed'] ?? 0;
    final tracked = owned + need;
    final percent = tracked == 0 ? 0 : (owned / tracked * 100).round();
    final selectedSet = _selectedSet;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Cards'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _browseChecklists,
              icon: const Icon(Icons.add),
              label: const Text('Browse Checklists'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedSourceKey,
                          decoration: const InputDecoration(
                            labelText: 'My Sets',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(
                              Icons.collections_bookmark_outlined,
                            ),
                          ),
                          items: _sets.map((set) {
                            final key = set['source_key'] as String;
                            final year = set['year'] as String? ?? '';
                            final brand = set['brand'] as String? ?? '';
                            final name = set['set_name'] as String? ?? '';

                            return DropdownMenuItem(
                              value: key,
                              child: Text('$year $brand — $name'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSourceKey = value;
                              _filter = 'All';
                              _search.clear();
                            });
                            _loadCards();
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      OutlinedButton.icon(
                        onPressed: _browseChecklists,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Add Set'),
                      ),
                      if (selectedSet != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _removeSelectedSet,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove Set'),
                        ),
                      ],
                    ],
                  ),
                  if (_sets.isEmpty) ...[
                    const SizedBox(height: 40),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.sports_baseball_outlined,
                                size: 72,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Build Your Sports Card Collection',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Browse an online checklist, choose a set, and '
                                'add its complete master list to Heirloom Atlas.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _browseChecklists,
                                icon: const Icon(Icons.add),
                                label: const Text('Browse Checklists'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    if (selectedSet != null)
                      Text(
                        '${selectedSet['sport']} • ${selectedSet['year']} • '
                        '${selectedSet['brand']} • ${selectedSet['set_name']}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _Stat('Owned', '$owned', Icons.check_circle_outline),
                        _Stat('Need', '$need', Icons.playlist_add_check),
                        _Stat(
                          'Untracked',
                          '${_summary['untracked'] ?? 0}',
                          Icons.remove_circle_outline,
                        ),
                        _Stat('Completion', '$percent%', Icons.donut_large),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => _loadCards(),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText:
                                  'Search player, card #, attributes, year...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        DropdownButton<String>(
                          value: _filter,
                          items: const ['All', 'Owned', 'Need', 'Untracked']
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _filter = value);
                            _loadCards();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Row(
                                children: [
                                  SizedBox(width: 75, child: Text('Card #')),
                                  Expanded(flex: 3, child: Text('Player')),
                                  Expanded(flex: 2, child: Text('Attributes')),
                                  SizedBox(width: 105, child: Text('Status')),
                                  SizedBox(
                                    width: 185,
                                    child: Text('Quick update'),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text('Market Research'),
                                  ),
                                  SizedBox(width: 110, child: Text('Value')),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                itemCount: _cards.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final card = _cards[index];

                                  return InkWell(
                                    onTap: () => _openCardDetails(card),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 75,
                                            child: Text(card.cardNumber),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Row(
                                              children: [
                                                if (card.imagePath.isNotEmpty &&
                                                    File(
                                                      card.imagePath,
                                                    ).existsSync()) ...[
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    child: Image.file(
                                                      File(card.imagePath),
                                                      width: 34,
                                                      height: 46,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                ],
                                                Expanded(
                                                  child: Text(card.player),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(card.attributes),
                                          ),
                                          SizedBox(
                                            width: 105,
                                            child: Text(
                                              card.status,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 185,
                                            child: SegmentedButton<String>(
                                              segments: const [
                                                ButtonSegment(
                                                  value: 'Owned',
                                                  label: Text('Owned'),
                                                ),
                                                ButtonSegment(
                                                  value: 'Need',
                                                  label: Text('Need'),
                                                ),
                                                ButtonSegment(
                                                  value: 'Untracked',
                                                  label: Text('—'),
                                                ),
                                              ],
                                              selected: {card.status},
                                              showSelectedIcon: false,
                                              onSelectionChanged: (values) =>
                                                  _changeStatus(
                                                    card,
                                                    values.first,
                                                  ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: TextButton.icon(
                                              onPressed: () =>
                                                  _searchEbay(card),
                                              icon: const Icon(
                                                Icons.open_in_new,
                                                size: 17,
                                              ),
                                              label: const Text('eBay'),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 110,
                                            child: card.value == null
                                                ? TextButton.icon(
                                                    onPressed: () =>
                                                        _lookupValue(card),
                                                    icon: const Icon(
                                                      Icons.price_check,
                                                      size: 17,
                                                    ),
                                                    label: const Text('Lookup'),
                                                  )
                                                : InkWell(
                                                    onTap: () =>
                                                        _lookupValue(card),
                                                    child: Tooltip(
                                                      message:
                                                          card
                                                              .valueSource
                                                              .isEmpty
                                                          ? 'Click to refresh value'
                                                          : '${card.valueSource} • click to refresh',
                                                      child: Text(
                                                        '\$${card.value!.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${_summary['total'] ?? 0} cards in this set • '
                      'eBay opens current listings for market research; '
                      'your recorded value remains separate.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ImportedSetResult {
  final String sourceKey;
  final String sport;
  final String year;
  final String brand;
  final String setName;
  final List<SportsCard> cards;

  const _ImportedSetResult({
    required this.sourceKey,
    required this.sport,
    required this.year,
    required this.brand,
    required this.setName,
    required this.cards,
  });
}

class _RemoteChecklistFile {
  final String name;
  final String path;
  final String downloadUrl;

  const _RemoteChecklistFile({
    required this.name,
    required this.path,
    required this.downloadUrl,
  });

  String brandForYear(String year) {
    var value = name.replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
    value = value.replaceFirst('$year-', '');
    return value.replaceAll('-', ' ').trim();
  }
}

class _RemoteSet {
  final String name;
  final Map<String, dynamic> json;

  const _RemoteSet({required this.name, required this.json});
}

class _AddSportsCardSetDialog extends StatefulWidget {
  const _AddSportsCardSetDialog();

  @override
  State<_AddSportsCardSetDialog> createState() =>
      _AddSportsCardSetDialogState();
}

class _AddSportsCardSetDialogState extends State<_AddSportsCardSetDialog> {
  final HttpClient _client = HttpClient();

  String _sport = 'Baseball';
  List<String> _years = const [];
  String? _year;

  List<_RemoteChecklistFile> _files = const [];
  _RemoteChecklistFile? _file;

  List<_RemoteSet> _sets = const [];
  _RemoteSet? _set;

  bool _loadingYears = true;
  bool _loadingFiles = false;
  bool _loadingSets = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _client.userAgent = 'HeirloomAtlas/1.0';
    _loadYears();
  }

  @override
  void dispose() {
    _client.close(force: true);
    super.dispose();
  }

  Future<dynamic> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );

    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }

    return jsonDecode(await response.transform(utf8.decoder).join());
  }

  Future<void> _loadYears() async {
    try {
      final decoded = await _getJson(
        Uri.parse(
          'https://api.github.com/repos/robert-porter/CardLists/'
          'contents/baseball?ref=main',
        ),
      );

      if (decoded is! List) {
        throw const FormatException('Unexpected year listing.');
      }

      final years =
          decoded
              .whereType<Map>()
              .where((item) => item['type'] == 'dir')
              .map((item) => item['name']?.toString() ?? '')
              .where((name) => RegExp(r'^\d{4}$').hasMatch(name))
              .toList()
            ..sort((a, b) => b.compareTo(a));

      if (!mounted) return;

      setState(() {
        _years = years;
        _year = years.isEmpty ? null : years.first;
        _loadingYears = false;
      });

      if (_year != null) {
        await _loadFiles();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingYears = false;
        _error = 'Could not load years: $error';
      });
    }
  }

  Future<void> _loadFiles() async {
    final year = _year;
    if (year == null) return;

    setState(() {
      _loadingFiles = true;
      _files = const [];
      _file = null;
      _sets = const [];
      _set = null;
      _error = '';
    });

    try {
      final decoded = await _getJson(
        Uri.parse(
          'https://api.github.com/repos/robert-porter/CardLists/'
          'contents/baseball/$year?ref=main',
        ),
      );

      if (decoded is! List) {
        throw const FormatException('Unexpected checklist listing.');
      }

      final files =
          decoded
              .whereType<Map>()
              .where(
                (item) =>
                    item['type'] == 'file' &&
                    (item['name']?.toString().toLowerCase().endsWith('.json') ??
                        false),
              )
              .map(
                (item) => _RemoteChecklistFile(
                  name: item['name']?.toString() ?? '',
                  path: item['path']?.toString() ?? '',
                  downloadUrl: item['download_url']?.toString() ?? '',
                ),
              )
              .where((file) => file.downloadUrl.isNotEmpty)
              .toList()
            ..sort(
              (a, b) => a
                  .brandForYear(year)
                  .toLowerCase()
                  .compareTo(b.brandForYear(year).toLowerCase()),
            );

      if (!mounted) return;

      setState(() {
        _files = files;
        _file = files.isEmpty ? null : files.first;
        _loadingFiles = false;
      });

      if (_file != null) {
        await _loadSets();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingFiles = false;
        _error = 'Could not load checklists: $error';
      });
    }
  }

  Future<void> _loadSets() async {
    final file = _file;
    if (file == null) return;

    setState(() {
      _loadingSets = true;
      _sets = const [];
      _set = null;
      _error = '';
    });

    try {
      final decoded = await _getJson(Uri.parse(file.downloadUrl));

      if (decoded is! Map) {
        throw const FormatException('Unexpected checklist file.');
      }

      final root = Map<String, dynamic>.from(decoded);
      final rawSets = root['sets'];

      if (rawSets is! List || rawSets.isEmpty) {
        throw const FormatException('No sets found in this checklist.');
      }

      final sets = rawSets.whereType<Map>().map((raw) {
        final json = Map<String, dynamic>.from(raw);
        return _RemoteSet(
          name: json['name']?.toString() ?? 'Base Set',
          json: json,
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        _sets = sets;
        _set = sets.first;
        _loadingSets = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSets = false;
        _error = 'Could not read checklist: $error';
      });
    }
  }

  List<SportsCard> _buildCards() {
    final year = _year!;
    final file = _file!;
    final selectedSet = _set!;
    final brand = file.brandForYear(year);

    final rawCards = selectedSet.json['cards'];
    if (rawCards is! List) return const [];

    final cards = <SportsCard>[];

    for (final raw in rawCards) {
      if (raw is! Map) continue;

      final card = Map<String, dynamic>.from(raw);
      final number = card['number']?.toString().trim() ?? '';
      final name = card['name']?.toString().trim() ?? '';

      if (number.isEmpty || name.isEmpty) continue;

      final attributes = card['attributes'] is List
          ? (card['attributes'] as List)
                .map((value) => value.toString())
                .where((value) => value.trim().isNotEmpty)
                .join(', ')
          : '';

      final noteParts = <String>[];

      final note = card['note']?.toString().trim() ?? '';
      if (note.isNotEmpty) {
        noteParts.add(note);
      }

      final variations = card['variations'];
      if (variations is List && variations.isNotEmpty) {
        final names = variations
            .whereType<Map>()
            .map((value) => value['variation']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toList();

        if (names.isNotEmpty) {
          noteParts.add('Variations: ${names.join(' | ')}');
        }
      }

      final parallels = card['parallels'];
      if (parallels is List && parallels.isNotEmpty) {
        final names = parallels
            .whereType<Map>()
            .map((value) => value['name']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toList();

        if (names.isNotEmpty) {
          noteParts.add('Parallels: ${names.join(' | ')}');
        }
      }

      cards.add(
        SportsCard(
          sport: _sport,
          year: year,
          brand: brand,
          setName: selectedSet.name,
          cardNumber: number,
          player: name,
          attributes: attributes,
          notes: noteParts.join(' • '),
        ),
      );
    }

    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final year = _year;
    final file = _file;
    final selectedSet = _set;

    final cards = year == null || file == null || selectedSet == null
        ? const <SportsCard>[]
        : _buildCards();

    return AlertDialog(
      title: const Text('Add Sports Card Set'),
      content: SizedBox(
        width: 700,
        height: 520,
        child: _loadingYears
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _sport,
                    decoration: const InputDecoration(
                      labelText: 'Sport',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Baseball',
                        child: Text('Baseball'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sport = value);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _year,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                    items: _years
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _year = value);
                      _loadFiles();
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_loadingFiles)
                    const LinearProgressIndicator()
                  else
                    DropdownButtonFormField<_RemoteChecklistFile>(
                      initialValue: _file,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Brand / Checklist',
                        border: OutlineInputBorder(),
                      ),
                      items: _files
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.brandForYear(_year ?? ''),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _file = value);
                        _loadSets();
                      },
                    ),
                  const SizedBox(height: 14),
                  if (_loadingSets)
                    const LinearProgressIndicator()
                  else
                    DropdownButtonFormField<_RemoteSet>(
                      initialValue: _set,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Set',
                        border: OutlineInputBorder(),
                      ),
                      items: _sets
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _set = value),
                    ),
                  const SizedBox(height: 20),
                  if (_error.isNotEmpty)
                    Text(
                      _error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else if (selectedSet != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            const Icon(Icons.sports_baseball, size: 42),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$year '
                                    '${file!.brandForYear(year!)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(selectedSet.name),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${cards.length} cards available to import',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    'Checklist source: CardLists. Downloaded catalog data is '
                    'kept separate from your Owned/Need, grade, storage, and value data.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: cards.isEmpty
              ? null
              : () {
                  final year = _year!;
                  final file = _file!;
                  final set = _set!;
                  final brand = file.brandForYear(year);

                  Navigator.pop(
                    context,
                    _ImportedSetResult(
                      sourceKey: 'cardlists:${file.path}#${set.name}',
                      sport: _sport,
                      year: year,
                      brand: brand,
                      setName: set.name,
                      cards: cards,
                    ),
                  );
                },
          icon: const Icon(Icons.add),
          label: Text(cards.isEmpty ? 'Add Set' : 'Add ${cards.length} Cards'),
        ),
      ],
    );
  }
}

class _SportsCardDetailDialog extends StatefulWidget {
  final SportsCard card;
  final VoidCallback onOpenEbay;

  const _SportsCardDetailDialog({required this.card, required this.onOpenEbay});

  @override
  State<_SportsCardDetailDialog> createState() =>
      _SportsCardDetailDialogState();
}

class _SportsCardDetailDialogState extends State<_SportsCardDetailDialog> {
  late String _status;
  late String _imagePath;
  late String _backImagePath;

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  List<FamilyPerson> _familyPeople = const [];
  Set<int> _selectedFamilyPersonIds = <int>{};

  late final TextEditingController _quantityController;
  late final TextEditingController _gradeController;
  late final TextEditingController _storageController;
  late final TextEditingController _valueController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();

    _status = widget.card.status;
    _imagePath = widget.card.imagePath;
    _backImagePath = _extractBackImagePath(widget.card.notes);

    _quantityController = TextEditingController(
      text: widget.card.quantityOwned.toString(),
    );
    _gradeController = TextEditingController(text: widget.card.grade);
    _storageController = TextEditingController(
      text: widget.card.storageLocation,
    );
    _valueController = TextEditingController(
      text: widget.card.value == null
          ? ''
          : widget.card.value!.toStringAsFixed(2),
    );
    _notesController = TextEditingController(
      text: _notesWithoutBackImageMarker(widget.card.notes),
    );
    _loadFamilyConnections();
  }

  Future<void> _loadFamilyConnections() async {
    final people = await _databaseHelper.getFamilyPeople();
    final cardId = widget.card.id;
    final linked = cardId == null
        ? <FamilyPerson>[]
        : await _databaseHelper.getFamilyPeopleForItem(
            itemType: 'sports_card',
            itemKey: cardId.toString(),
          );

    if (!mounted) return;
    setState(() {
      _familyPeople = people;
      _selectedFamilyPersonIds = linked
          .map((person) => person.id)
          .whereType<int>()
          .toSet();
    });
  }

  Future<void> _chooseFamilyPeople() async {
    if (_familyPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add people to the Family Tree first.')),
      );
      return;
    }

    final selected = <int>{..._selectedFamilyPersonIds};
    var query = '';

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final visible = _familyPeople.where((person) {
            return q.isEmpty || person.displayName.toLowerCase().contains(q);
          }).toList();

          return Dialog(
            child: SizedBox(
              width: 700,
              height: 650,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.account_tree_outlined),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Family Connections',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search Family Tree...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: visible.map((person) {
                        final id = person.id!;
                        return CheckboxListTile(
                          value: selected.contains(id),
                          title: Text(person.displayName),
                          secondary: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked ?? false) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text('${selected.length} connected'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () =>
                              Navigator.pop(dialogContext, selected),
                          icon: const Icon(Icons.check),
                          label: const Text('Use People'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _selectedFamilyPersonIds = result);
  }

  Future<void> _saveFamilyConnections() async {
    final cardId = widget.card.id;
    if (cardId == null) return;

    final existingPeople = await _databaseHelper.getFamilyPeopleForItem(
      itemType: 'sports_card',
      itemKey: cardId.toString(),
    );
    final existingIds = existingPeople
        .map((person) => person.id)
        .whereType<int>()
        .toSet();

    for (final personId in existingIds.difference(_selectedFamilyPersonIds)) {
      await _databaseHelper.unlinkFamilyPersonFromItem(
        personId: personId,
        itemType: 'sports_card',
        itemKey: cardId.toString(),
      );
    }
    for (final personId in _selectedFamilyPersonIds.difference(existingIds)) {
      await _databaseHelper.linkFamilyPersonToItem(
        personId: personId,
        itemType: 'sports_card',
        itemKey: cardId.toString(),
      );
    }
  }

  Future<void> _openFamilyPerson(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FamilyPersonScreen(person: person)),
    );

    await _loadFamilyConnections();
  }

  Widget _familyConnectionsSection() {
    final selectedPeople = _familyPeople
        .where(
          (person) =>
              person.id != null && _selectedFamilyPersonIds.contains(person.id),
        )
        .toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Family Connections',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _chooseFamilyPeople,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    selectedPeople.isEmpty ? 'Choose People' : 'Manage',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect this card to a family member whose collection, '
              'memory, gift, or story it belongs to.',
            ),
            if (selectedPeople.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selectedPeople
                    .map(
                      (person) => ActionChip(
                        avatar: const Icon(Icons.person_outline, size: 17),
                        label: Text(person.displayName),
                        tooltip: 'Open Family Tree person',
                        onPressed: () => _openFamilyPerson(person),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _extractBackImagePath(String notes) {
    for (final line in notes.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('back image:')) {
        return trimmed.substring('back image:'.length).trim();
      }
    }
    return '';
  }

  String _notesWithoutBackImageMarker(String notes) {
    return notes
        .split(RegExp(r'\r?\n'))
        .where(
          (line) => !line.trim().toLowerCase().startsWith('back image:'),
        )
        .join('\n')
        .trim();
  }

  String _notesForSave() {
    final cleanNotes = _notesWithoutBackImageMarker(_notesController.text);
    return [
      if (cleanNotes.isNotEmpty) cleanNotes,
      if (_backImagePath.trim().isNotEmpty)
        'Back image: ${_backImagePath.trim()}',
    ].join('\n');
  }

  Future<void> _chooseBackImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty) return;

    final selectedPath = result.single.path;
    if (selectedPath == null || selectedPath.isEmpty) return;

    setState(() => _backImagePath = selectedPath);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _gradeController.dispose();
    _storageController.dispose();
    _valueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
    );

    if (result.isEmpty) return;

    final path = result.single.path;
    if (path == null || path.isEmpty) return;

    setState(() => _imagePath = path);
  }

  SportsCard _buildUpdatedCard() {
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;

    final valueText = _valueController.text
        .trim()
        .replaceAll('\$', '')
        .replaceAll(',', '');

    final parsedValue = valueText.isEmpty ? null : double.tryParse(valueText);

    return widget.card.copyWith(
      status: _status,
      quantityOwned: quantity < 0 ? 0 : quantity,
      grade: _gradeController.text.trim(),
      storageLocation: _storageController.text.trim(),
      value: parsedValue,
      valueSource: parsedValue == null
          ? widget.card.valueSource
          : widget.card.valueSource.isEmpty
          ? 'Manual'
          : widget.card.valueSource,
      valueUpdatedAtMilliseconds: parsedValue == null
          ? widget.card.valueUpdatedAtMilliseconds
          : DateTime.now().millisecondsSinceEpoch,
      imagePath: _imagePath,
      notes: _notesForSave(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final hasImage = _imagePath.isNotEmpty && File(_imagePath).existsSync();
    final hasBackImage =
        _backImagePath.isNotEmpty && File(_backImagePath).existsSync();

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 980,
        height: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(
                children: [
                  const Icon(Icons.style_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.player,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${card.year} ${card.brand} '
                          '${card.setName} • #${card.cardNumber}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 310,
                      child: Column(
                        children: [
                          Expanded(
                            child: DefaultTabController(
                              length: 2,
                              child: Column(
                                children: [
                                  const TabBar(
                                    tabs: [
                                      Tab(text: 'Front'),
                                      Tab(text: 'Back'),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: TabBarView(
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerLowest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color:
                                                  Theme.of(context).dividerColor,
                                            ),
                                          ),
                                          child: hasImage
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(11),
                                                  child: Image.file(
                                                    File(_imagePath),
                                                    fit: BoxFit.contain,
                                                  ),
                                                )
                                              : const Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .photo_library_outlined,
                                                      size: 72,
                                                    ),
                                                    SizedBox(height: 12),
                                                    Text('No front image yet'),
                                                  ],
                                                ),
                                        ),
                                        Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerLowest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color:
                                                  Theme.of(context).dividerColor,
                                            ),
                                          ),
                                          child: hasBackImage
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(11),
                                                  child: Image.file(
                                                    File(_backImagePath),
                                                    fit: BoxFit.contain,
                                                  ),
                                                )
                                              : const Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.flip_to_back_outlined,
                                                      size: 72,
                                                    ),
                                                    SizedBox(height: 12),
                                                    Text('No back image yet'),
                                                  ],
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _chooseImage,
                                  icon: const Icon(Icons.add_a_photo_outlined),
                                  label: Text(
                                    hasImage ? 'Change Front' : 'Choose Front',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _chooseBackImage,
                                  icon: const Icon(Icons.flip_to_back_outlined),
                                  label: Text(
                                    hasBackImage
                                        ? 'Change Back'
                                        : 'Choose Back',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (hasImage || hasBackImage) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (hasImage)
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _imagePath = ''),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Remove Front'),
                                  ),
                                if (hasBackImage)
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _backImagePath = ''),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Remove Back'),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: widget.onOpenEbay,
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Research on eBay'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 34),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Collection Details',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'Owned',
                                  label: Text('Owned'),
                                ),
                                ButtonSegment(
                                  value: 'Need',
                                  label: Text('Need'),
                                ),
                                ButtonSegment(
                                  value: 'Untracked',
                                  label: Text('Untracked'),
                                ),
                              ],
                              selected: {_status},
                              onSelectionChanged: (values) {
                                setState(() => _status = values.first);
                              },
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _quantityController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Quantity',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _gradeController,
                                    decoration: const InputDecoration(
                                      labelText: 'Grade',
                                      hintText: 'Raw, PSA 8, SGC 9...',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _storageController,
                              decoration: const InputDecoration(
                                labelText: 'Storage location',
                                hintText: 'Binder 2, Box A...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _valueController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Recorded value',
                                prefixText: '\$ ',
                                border: const OutlineInputBorder(),
                                helperText: card.valueSource.isEmpty
                                    ? 'Enter your own current value.'
                                    : 'Current source: ${card.valueSource}',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Catalog Information',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            _DetailLine(label: 'Sport', value: card.sport),
                            _DetailLine(label: 'Year', value: card.year),
                            _DetailLine(label: 'Brand', value: card.brand),
                            _DetailLine(label: 'Set', value: card.setName),
                            _DetailLine(
                              label: 'Card #',
                              value: card.cardNumber,
                            ),
                            _DetailLine(label: 'Player', value: card.player),
                            if (card.team.isNotEmpty)
                              _DetailLine(label: 'Team', value: card.team),
                            if (card.attributes.isNotEmpty)
                              _DetailLine(
                                label: 'Attributes',
                                value: card.attributes,
                              ),
                            const SizedBox(height: 16),
                            _familyConnectionsSection(),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _notesController,
                              minLines: 4,
                              maxLines: 7,
                              decoration: const InputDecoration(
                                labelText: 'Notes',
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () async {
                      await _saveFamilyConnections();
                      if (!context.mounted) return;
                      Navigator.pop(context, _buildUpdatedCard());
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Card'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

class _CardValueLookupResult {
  final String token;
  final double value;
  final String source;

  const _CardValueLookupResult({
    required this.token,
    required this.value,
    required this.source,
  });
}

class _CardValueLookupDialog extends StatefulWidget {
  final SportsCard card;
  final SportsCardPriceProvider provider;
  final String initialToken;

  const _CardValueLookupDialog({
    required this.card,
    required this.provider,
    required this.initialToken,
  });

  @override
  State<_CardValueLookupDialog> createState() => _CardValueLookupDialogState();
}

class _CardValueLookupDialogState extends State<_CardValueLookupDialog> {
  late final TextEditingController _tokenController;
  late final TextEditingController _queryController;

  SportsCardPriceQuote? _quote;
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();

    _tokenController = TextEditingController(text: widget.initialToken);

    final card = widget.card;
    _queryController = TextEditingController(
      text: '${card.year} ${card.brand} ${card.player} #${card.cardNumber}',
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = '';
      _quote = null;
    });

    try {
      final quote = await widget.provider.lookup(
        token: _tokenController.text,
        query: _queryController.text,
      );

      if (!mounted) return;

      setState(() {
        _quote = quote;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;

    return AlertDialog(
      title: Text('Look Up Value — ${widget.card.player}'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.card.year} ${widget.card.brand} '
              '#${widget.card.cardNumber}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'SportsCardsPro API token',
                border: OutlineInputBorder(),
                helperText: 'Used only for this running app session.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              decoration: const InputDecoration(
                labelText: 'Search query',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _search,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('Search Prices'),
            ),
            const SizedBox(height: 16),
            if (_error.isNotEmpty)
              Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (quote != null) ...[
              Text(
                quote.productName.isEmpty ? 'Matched card' : quote.productName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (quote.setName.isNotEmpty)
                Text(
                  quote.setName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              Expanded(
                child: quote.prices.isEmpty
                    ? const Center(
                        child: Text(
                          'A card matched, but no current price fields were returned.',
                        ),
                      )
                    : ListView(
                        children: quote.prices.entries.map((entry) {
                          return Card(
                            child: ListTile(
                              title: Text(entry.key),
                              trailing: Text(
                                '\$${entry.value.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onTap: () => Navigator.pop(
                                context,
                                _CardValueLookupResult(
                                  token: _tokenController.text.trim(),
                                  value: entry.value,
                                  source: widget.provider.name,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ] else
              const Expanded(
                child: Center(
                  child: Text(
                    'Search for current price-guide values, then click the '
                    'condition/grade you want to save to this card.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Prototype note: SportsCardsPro price data is for personal/internal '
              'testing here. A commercial/public release would require provider permission.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Stat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(label),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
