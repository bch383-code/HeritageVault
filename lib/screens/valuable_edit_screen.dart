import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../models/valuable.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';

class ValuableEditScreen extends StatefulWidget {
  final Valuable? valuable;
  final List<String> initialImagePaths;

  const ValuableEditScreen({
    super.key,
    this.valuable,
    this.initialImagePaths = const [],
  });

  @override
  State<ValuableEditScreen> createState() => _ValuableEditScreenState();
}

class _ValuableEditScreenState extends State<ValuableEditScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _yearController;
  late final TextEditingController _acquiredFromController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _estimatedValueController;
  late final TextEditingController _notesController;
  late final TextEditingController _conditionNotesController;
  late final TextEditingController _provenanceController;
  late final TextEditingController _appraisalSourceController;
  late final TextEditingController _valuationDateController;
  late final TextEditingController _researchController;

  late List<String> _imagePaths;
  late List<String> _supportingDocumentPaths;
  String _condition = '';
  bool _isSaving = false;
  List<FamilyPerson> _familyPeople = const [];
  Set<int> _selectedFamilyPersonIds = <int>{};

  bool get _isEditing => widget.valuable?.id != null;

  @override
  void initState() {
    super.initState();
    final valuable = widget.valuable;

    _titleController = TextEditingController(text: valuable?.title ?? '');
    _descriptionController = TextEditingController(
      text: valuable?.description ?? '',
    );
    _yearController = TextEditingController(text: valuable?.year ?? '');
    _acquiredFromController = TextEditingController(
      text: valuable?.acquiredFrom ?? '',
    );
    _purchasePriceController = TextEditingController(
      text: valuable?.purchasePrice?.toStringAsFixed(2) ?? '',
    );
    _estimatedValueController = TextEditingController(
      text: valuable?.estimatedValue?.toStringAsFixed(2) ?? '',
    );
    _notesController = TextEditingController(text: valuable?.notes ?? '');
    _conditionNotesController = TextEditingController(
      text: valuable?.conditionNotes ?? '',
    );
    _provenanceController = TextEditingController(
      text: valuable?.provenance ?? '',
    );
    _appraisalSourceController = TextEditingController(
      text: valuable?.appraisalSource ?? '',
    );
    _valuationDateController = TextEditingController(
      text: valuable?.valuationDate ?? '',
    );
    _condition = valuable?.condition ?? '';
    _imagePaths = List<String>.from(valuable?.imagePaths ?? const []);
    _supportingDocumentPaths = List<String>.from(
      valuable?.supportingDocumentPaths ?? const [],
    );
    _researchController = TextEditingController(text: _buildResearchQuery());
    _loadFamilyConnections();
    _importInitialImages();
  }

  Future<void> _importInitialImages() async {
    if (widget.initialImagePaths.isEmpty) return;

    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(
      path.join(root.path, 'Heirloom Atlas', 'Valuables', 'Images'),
    );
    await dir.create(recursive: true);

    final added = <String>[];
    for (var i = 0; i < widget.initialImagePaths.length; i++) {
      final sourcePath = widget.initialImagePaths[i];
      final source = File(sourcePath);
      if (!await source.exists()) continue;

      final destination = path.join(
        dir.path,
        'valuable_quick_${DateTime.now().microsecondsSinceEpoch}_$i'
        '${path.extension(sourcePath)}',
      );
      await source.copy(destination);
      added.add(destination);
    }

    if (!mounted || added.isEmpty) return;
    setState(() => _imagePaths.addAll(added));
  }

  Future<void> _loadFamilyConnections() async {
    final people = await _databaseHelper.getFamilyPeople();
    final itemId = widget.valuable?.id;
    final linked = itemId == null
        ? <FamilyPerson>[]
        : await _databaseHelper.getFamilyPeopleForItem(
            itemType: 'valuable',
            itemKey: itemId.toString(),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
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
            Text(
              'Connect this valuable to the people who owned it, used it, '
              'made it, inherited it, or are part of its story.',
            ),
            if (selectedPeople.isNotEmpty) ...[
              const SizedBox(height: 12),
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _yearController.dispose();
    _acquiredFromController.dispose();
    _purchasePriceController.dispose();
    _estimatedValueController.dispose();
    _notesController.dispose();
    _conditionNotesController.dispose();
    _provenanceController.dispose();
    _appraisalSourceController.dispose();
    _valuationDateController.dispose();
    _researchController.dispose();
    super.dispose();
  }

  double? _parseMoney(String value) {
    final cleaned = value.replaceAll(r'$', '').replaceAll(',', '').trim();

    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  String _buildResearchQuery() {
    final words = _descriptionController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(10)
        .join(' ');
    return [
      _titleController.text.trim(),
      _yearController.text.trim(),
      words,
    ].where((part) => part.isNotEmpty).join(' ').trim();
  }

  void _refreshResearchQuery() {
    final query = _buildResearchQuery();
    setState(() {
      _researchController.text = query;
      _researchController.selection =
          TextSelection.collapsed(offset: query.length);
    });
  }

  String? _researchQuery() {
    if (_researchController.text.trim().isEmpty) {
      _refreshResearchQuery();
    }
    final query = _researchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter identifying details first.')),
      );
      return null;
    }
    return query;
  }

  Future<void> _launchResearch(Uri uri, String label) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $label.')),
      );
    }
  }

  Future<void> _searchResearchSite(String kind) async {
    final query = _researchQuery();
    if (query == null) return;

    late Uri uri;
    switch (kind) {
      case 'images':
        uri = Uri.https('www.google.com', '/search', {
          'q': query,
          'tbm': 'isch',
        });
      case 'ebay':
        uri = Uri.https('www.ebay.com', '/sch/i.html', {
          '_nkw': query,
          '_sacat': '0',
        });
      case 'sold':
        uri = Uri.https('www.ebay.com', '/sch/i.html', {
          '_nkw': query,
          '_sacat': '0',
          'LH_Complete': '1',
          'LH_Sold': '1',
        });
      case 'etsy':
        uri = Uri.https('www.etsy.com', '/search', {'q': query});
      case 'auction':
        uri = Uri.https('www.google.com', '/search', {
          'q':
              '$query (site:liveauctioneers.com OR site:invaluable.com OR site:worthpoint.com)',
        });
      default:
        uri = Uri.https('www.google.com', '/search', {'q': query});
    }
    await _launchResearch(uri, kind);
  }

  Future<void> _researchOnline() async {
    final query = _researchQuery();
    if (query == null) return;

    final urls = <Uri>[
      Uri.https('www.google.com', '/search', {'q': query}),
      Uri.https('www.google.com', '/search', {'q': query, 'tbm': 'isch'}),
      Uri.https('www.ebay.com', '/sch/i.html', {
        '_nkw': query,
        '_sacat': '0',
      }),
      Uri.https('www.ebay.com', '/sch/i.html', {
        '_nkw': query,
        '_sacat': '0',
        'LH_Complete': '1',
        'LH_Sold': '1',
      }),
    ];

    for (final uri in urls) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _addSupportingDocuments() async {
    // ignore: deprecated_member_use
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result.isEmpty) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(
      path.join(
        documentsDirectory.path,
        'Heirloom Atlas',
        'Valuables',
        'Documents',
      ),
    );
    await targetDirectory.create(recursive: true);

    final copied = <String>[];
    for (final pickedFile in result) {
      final sourcePath = pickedFile.path;
      if (sourcePath == null || sourcePath.isEmpty) continue;
      final destination = path.join(
        targetDirectory.path,
        'valuable_${DateTime.now().microsecondsSinceEpoch}_${copied.length}${path.extension(sourcePath)}',
      );
      await File(sourcePath).copy(destination);
      copied.add(destination);
    }

    if (mounted && copied.isNotEmpty) {
      setState(() => _supportingDocumentPaths.addAll(copied));
    }
  }

  Future<void> _openSupportingFile(String filePath) async {
    if (!File(filePath).existsSync()) return;
    await Process.start('explorer.exe', [filePath], runInShell: true);
  }

  Widget _sectionHeading(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _researchSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Research & Identification',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Compare identifying details and sold prices. Outside results are research clues, not confirmed facts.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _researchController,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _searchResearchSite('google'),
              decoration: InputDecoration(
                labelText: 'Identification search',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _researchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () =>
                            setState(() => _researchController.clear()),
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _refreshResearchQuery,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Build Search from Record'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _researchOnline,
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: const Text('Research Online'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _searchResearchSite('google'),
                  icon: const Icon(Icons.public),
                  label: const Text('Google'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _searchResearchSite('images'),
                  icon: const Icon(Icons.image_search_outlined),
                  label: const Text('Google Images'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _searchResearchSite('ebay'),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('eBay'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _searchResearchSite('sold'),
                  icon: const Icon(Icons.price_check_outlined),
                  label: const Text('eBay Sold'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _searchResearchSite('etsy'),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Etsy'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _searchResearchSite('auction'),
                  icon: const Icon(Icons.gavel_outlined),
                  label: const Text('Auction / Reference Sites'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _supportingMaterialsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Supporting Materials',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _addSupportingDocuments,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Add Files'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Receipts, appraisals, certificates, insurance records, research PDFs, and provenance documents.',
            ),
            if (_supportingDocumentPaths.isEmpty) ...[
              const SizedBox(height: 10),
              const Text('No supporting materials attached.'),
            ] else
              ..._supportingDocumentPaths.asMap().entries.map(
                (entry) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(path.basename(entry.value)),
                  onTap: () => _openSupportingFile(entry.value),
                  trailing: IconButton(
                    tooltip: 'Remove from record',
                    onPressed: () => setState(
                      () => _supportingDocumentPaths.removeAt(entry.key),
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      // Multiple photos are intentionally supported.
      // ignore: deprecated_member_use
      allowMultiple: true,
    );

    if (result.isEmpty) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      path.join(
        documentsDirectory.path,
        'Heirloom Atlas',
        'Valuables',
        'Images',
      ),
    );

    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    final copied = <String>[];

    for (final pickedFile in result) {
      final sourcePath = pickedFile.path;
      if (sourcePath == null || sourcePath.isEmpty) continue;

      final extension = path.extension(sourcePath);
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final destination = path.join(
        imageDirectory.path,
        'valuable_${timestamp}_${copied.length}$extension',
      );

      await File(sourcePath).copy(destination);
      copied.add(destination);
    }

    if (!mounted || copied.isEmpty) return;
    setState(() => _imagePaths.addAll(copied));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final valuable = Valuable(
        id: widget.valuable?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        year: _yearController.text.trim(),
        acquiredFrom: _acquiredFromController.text.trim(),
        purchasePrice: _parseMoney(_purchasePriceController.text),
        estimatedValue: _parseMoney(_estimatedValueController.text),
        notes: _notesController.text.trim(),
        imagePaths: _imagePaths,
        condition: _condition,
        conditionNotes: _conditionNotesController.text.trim(),
        provenance: _provenanceController.text.trim(),
        appraisalSource: _appraisalSourceController.text.trim(),
        valuationDate: _valuationDateController.text.trim(),
        supportingDocumentPaths: _supportingDocumentPaths,
      );

      await _databaseHelper.createDatabaseBackup(
        reason: _isEditing ? 'before_valuable_update' : 'before_valuable_add',
      );

      final int itemId;
      if (_isEditing) {
        await _databaseHelper.updateValuable(valuable);
        itemId = valuable.id!;
      } else {
        itemId = await _databaseHelper.insertValuable(valuable);
      }

      final existingPeople = await _databaseHelper.getFamilyPeopleForItem(
        itemType: 'valuable',
        itemKey: itemId.toString(),
      );
      final existingIds = existingPeople
          .map((person) => person.id)
          .whereType<int>()
          .toSet();

      for (final personId in existingIds.difference(_selectedFamilyPersonIds)) {
        await _databaseHelper.unlinkFamilyPersonFromItem(
          personId: personId,
          itemType: 'valuable',
          itemKey: itemId.toString(),
        );
      }
      for (final personId in _selectedFamilyPersonIds.difference(existingIds)) {
        await _databaseHelper.linkFamilyPersonToItem(
          personId: personId,
          itemType: 'valuable',
          itemKey: itemId.toString(),
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save valuable: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final valuable = widget.valuable;
    if (valuable?.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete valuable?'),
        content: const Text(
          'This removes the valuable record from Heirloom Atlas. '
          'Copied image and supporting files will remain in the Heirloom Atlas Valuables folders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _databaseHelper.createDatabaseBackup(
      reason: 'before_valuable_delete',
    );
    await _databaseHelper.deleteValuable(valuable!.id!);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _imagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Photos',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _addImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add Photos'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_imagePaths.isEmpty)
          Container(
            height: 180,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined, size: 54),
                SizedBox(height: 8),
                Text('No photos added yet'),
              ],
            ),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final imagePath = _imagePaths[index];
                final file = File(imagePath);

                return SizedBox(
                  width: 260,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        file.existsSync()
                            ? Image.file(file, fit: BoxFit.cover)
                            : const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filledTonal(
                            tooltip: 'Remove from record',
                            onPressed: () {
                              setState(() => _imagePaths.removeAt(index));
                            },
                            icon: const Icon(Icons.close),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Valuable' : 'Add Valuable'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete Valuable',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _imagesSection(),
                  const SizedBox(height: 20),
                  _researchSection(),
                  const SizedBox(height: 24),
                  _sectionHeading(
                    'Identification & Description',
                    'Record what the item is and the details that distinguish it.',
                  ),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title / Identification',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description / Identifying Details',
                      hintText:
                          'Maker, model, serial number, material, markings, dimensions...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _yearController,
                          decoration: const InputDecoration(
                            labelText: 'Year / Date',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _acquiredFromController,
                          decoration: const InputDecoration(
                            labelText: 'Acquired From',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionHeading(
                    'Condition',
                    'Track physical condition separately from the general description.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _condition.isEmpty ? null : _condition,
                    items: const [
                      'Excellent',
                      'Very Good',
                      'Good',
                      'Fair',
                      'Poor',
                      'Unknown',
                    ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _condition = value ?? ''),
                    decoration: const InputDecoration(
                      labelText: 'Condition',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _conditionNotesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Condition Notes',
                      hintText:
                          'Wear, damage, repairs, missing parts, restoration...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeading(
                    'Provenance & Family History',
                    'Preserve ownership history and why this item matters to the family.',
                  ),
                  TextFormField(
                    controller: _provenanceController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Ownership / Provenance History',
                      hintText:
                          'Who owned it, how it passed through the family, where it came from...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _familyConnectionsSection(),
                  const SizedBox(height: 24),
                  _sectionHeading(
                    'Value & Appraisal',
                    'Track the current estimate and the evidence behind it.',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePriceController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return null;
                            return _parseMoney(text) == null
                                ? 'Enter a valid amount'
                                : null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Purchase Price',
                            prefixText: r'$',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _estimatedValueController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return null;
                            return _parseMoney(text) == null
                                ? 'Enter a valid amount'
                                : null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Estimated / Appraised Value',
                            prefixText: r'$',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _appraisalSourceController,
                          decoration: const InputDecoration(
                            labelText: 'Value / Appraisal Source',
                            hintText:
                                'Appraiser, eBay sold comps, auction house...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _valuationDateController,
                          decoration: const InputDecoration(
                            labelText: 'Valuation Date',
                            hintText: '2026-08-30 or Aug 2026',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _supportingMaterialsSection(),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'History / Research Notes',
                      hintText:
                          'Family story, research findings, comparable sales, insurance notes, uncertainties...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Save Valuable'),
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
