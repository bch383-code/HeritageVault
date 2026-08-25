import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';
import '../services/photo_metadata_reader.dart';
import '../services/photo_metadata_writer.dart';

class PhotoDetailScreen extends StatefulWidget {
  final List<VaultPhoto> photos;
  final int initialIndex;

  const PhotoDetailScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late int _index;
  PhotoMetadata? _embeddedMetadata;

  List<String> _people = [];
  List<String> _tags = [];
  List<String> _knownPeople = [];
  List<String> _knownTags = [];
  List<String> _knownLocations = [];
  List<FamilyPerson> _linkedFamilyPeople = [];

  String _dateType = 'Approximate';
  bool _loading = true;
  bool _saving = false;
  bool _writingToPhoto = false;
  String? _error;

  VaultPhoto get _photo => widget.photos[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _loadSuggestions();
    _loadPhoto();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final records = await _databaseHelper.getAllPhotoCatalogMetadata();
      final people = <String>{};
      final tags = <String>{};
      final locations = <String>{};

      for (final record in records) {
        people.addAll(record.people.where((e) => e.trim().isNotEmpty));
        tags.addAll(record.tags.where((e) => e.trim().isNotEmpty));
        if (record.location.trim().isNotEmpty) {
          locations.add(record.location.trim());
        }
      }

      if (!mounted) return;
      setState(() {
        _knownPeople = people.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _knownTags = tags.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _knownLocations = locations.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });
    } catch (_) {
      // Suggestions are a convenience; the editor still works without them.
    }
  }

  Future<void> _loadPhoto() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        PhotoMetadataReader.read(_photo.filePath),
        _databaseHelper.getPhotoCatalogMetadata(_photo.filePath),
        _databaseHelper.getFamilyPeopleForPhoto(_photo.filePath),
      ]);

      final embedded = results[0] as PhotoMetadata;
      final catalog = results[1] as PhotoCatalogMetadata;
      final linkedFamilyPeople = results[2] as List<FamilyPerson>;

      if (!mounted) return;

      _people = [...catalog.people];
      _tags = [...catalog.tags];

      final parsed = _parseStoredDate(catalog.approximateDate);
      _dateType = parsed.$1;
      _dateController.text = parsed.$2;

      _locationController.text = catalog.location;
      _descriptionController.text = catalog.description;
      _notesController.text = catalog.notes;

      setState(() {
        _embeddedMetadata = embedded;
        _linkedFamilyPeople = linkedFamilyPeople;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  (String, String) _parseStoredDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return ('Approximate', '');
    if (trimmed.toLowerCase() == 'unknown') return ('Unknown', '');
    if (trimmed.startsWith('c. ')) {
      return ('Approximate', trimmed.substring(3));
    }
    if (RegExp(r'^\d{4}s$').hasMatch(trimmed)) {
      return ('Decade', trimmed);
    }
    if (RegExp(r'^\d{4}$').hasMatch(trimmed)) {
      return ('Year only', trimmed);
    }
    return ('Exact', trimmed);
  }

  String _storedDate() {
    final value = _dateController.text.trim();
    switch (_dateType) {
      case 'Unknown':
        return 'Unknown';
      case 'Approximate':
        return value.isEmpty ? '' : 'c. $value';
      case 'Decade':
        if (value.isEmpty) return '';
        return value.endsWith('s') ? value : '${value}s';
      default:
        return value;
    }
  }

  PhotoCatalogMetadata _currentCatalogMetadata() {
    return PhotoCatalogMetadata(
      filePath: _photo.filePath,
      people: _people,
      tags: _tags,
      approximateDate: _storedDate(),
      location: _locationController.text.trim(),
      description: _descriptionController.text.trim(),
      notes: _notesController.text.trim(),
    );
  }

  Future<void> _save({bool showMessage = true}) async {
    setState(() => _saving = true);
    try {
      final metadata = _currentCatalogMetadata();
      await _databaseHelper.savePhotoCatalogMetadata(metadata);

      for (final person in metadata.people) {
        if (!_knownPeople.contains(person)) _knownPeople.add(person);
      }
      for (final tag in metadata.tags) {
        if (!_knownTags.contains(tag)) _knownTags.add(tag);
      }
      if (metadata.location.isNotEmpty &&
          !_knownLocations.contains(metadata.location)) {
        _knownLocations.add(metadata.location);
      }

      if (!mounted) return;
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Heirloom Atlas metadata saved.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save metadata: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _move(int direction) async {
    final next = _index + direction;
    if (next < 0 || next >= widget.photos.length) return;

    // Preserve edits before moving to the next image.
    await _save(showMessage: false);
    if (!mounted) return;

    setState(() => _index = next);
    await _loadPhoto();
  }

  Future<void> _writeToPhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Write metadata to original photo?'),
        content: const Text(
          'Heirloom Atlas will create a backup first, then write Description, '
          'Tags, People-as-keywords, and Location into the original image. '
          'Archival Date and Notes remain in Heirloom Atlas only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Write Metadata'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _writingToPhoto = true);
    try {
      final metadata = _currentCatalogMetadata();
      await _databaseHelper.savePhotoCatalogMetadata(metadata);

      final result = await PhotoMetadataWriter.write(
        filePath: _photo.filePath,
        metadata: metadata,
      );

      if (!mounted) return;

      if (result.success) {
        final refreshed = await PhotoMetadataReader.read(_photo.filePath);
        if (!mounted) return;
        setState(() => _embeddedMetadata = refreshed);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Metadata was not written'),
            content: SelectableText(result.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _writingToPhoto = false);
    }
  }

  Future<void> _chooseFamilyTreePeople() async {
    final allPeople = await _databaseHelper.getFamilyPeople();

    if (!mounted) return;

    final selectedIds = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => _FamilyTreePeoplePickerDialog(
        people: allPeople,
        initiallySelectedIds: _linkedFamilyPeople
            .where((person) => person.id != null)
            .map((person) => person.id!)
            .toSet(),
      ),
    );

    if (selectedIds == null) return;

    await _databaseHelper.replaceFamilyPeopleForPhoto(
      photoFilePath: _photo.filePath,
      personIds: selectedIds,
    );

    final linked =
        await _databaseHelper.getFamilyPeopleForPhoto(_photo.filePath);

    if (!mounted) return;

    setState(() {
      _linkedFamilyPeople = linked;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          linked.isEmpty
              ? 'Family Tree links cleared.'
              : '${linked.length} ${linked.length == 1 ? 'person' : 'people'} linked to this photo.',
        ),
      ),
    );
  }

  void _addPerson(String value) {
    final item = value.trim();
    if (item.isEmpty || _people.contains(item)) return;
    setState(() => _people.add(item));
  }

  void _addTag(String value) {
    final item = value.trim();
    if (item.isEmpty || _tags.contains(item)) return;
    setState(() => _tags.add(item));
  }

  @override
  Widget build(BuildContext context) {
    final file = File(_photo.filePath);

    return Scaffold(
      appBar: AppBar(
        title: Text(_photo.fileName),
        actions: [
          IconButton(
            tooltip: 'Save to Vault',
            onPressed: _saving || _loading ? null : () => _save(),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'Write Metadata to Photo',
            onPressed: _loading || _writingToPhoto ? null : _writeToPhoto,
            icon: _writingToPhoto
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_note_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load photo.\n\n$_error'))
              : Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Expanded(
                              child: file.existsSync()
                                  ? Image.file(file, fit: BoxFit.contain)
                                  : const Center(
                                      child: Text('Original file not found.'),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                  tooltip: 'Previous photo',
                                  onPressed: _index > 0
                                      ? () => _move(-1)
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      '${_index + 1} of ${widget.photos.length}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  tooltip: 'Next photo',
                                  onPressed: _index < widget.photos.length - 1
                                      ? () => _move(1)
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _photo.filePath,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 2,
                      child: ListView(
                        padding: const EdgeInsets.all(22),
                        children: [
                          Text(
                            'Photo Details',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 18),
                          _FamilyTreeLinksCard(
                            people: _linkedFamilyPeople,
                            onEdit: _chooseFamilyTreePeople,
                          ),
                          const SizedBox(height: 18),
                          _ChipEditor(
                            label: 'People / metadata keywords',
                            hint: 'Add a person',
                            values: _people,
                            suggestions: _knownPeople,
                            onAdd: _addPerson,
                            onRemove: (value) =>
                                setState(() => _people.remove(value)),
                          ),
                          const SizedBox(height: 18),
                          _ChipEditor(
                            label: 'Tags',
                            hint: 'Add a tag',
                            values: _tags,
                            suggestions: _knownTags,
                            onAdd: _addTag,
                            onRemove: (value) =>
                                setState(() => _tags.remove(value)),
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stackFields =
                                  constraints.maxWidth < 430;

                              final typeField = SizedBox(
                                width: stackFields
                                    ? constraints.maxWidth
                                    : 145,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _dateType,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Date type',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    'Exact',
                                    'Approximate',
                                    'Year only',
                                    'Decade',
                                    'Unknown',
                                  ]
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(
                                            value,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _dateType = value);
                                    }
                                  },
                                ),
                              );

                              final dateField = TextField(
                                controller: _dateController,
                                enabled: _dateType != 'Unknown',
                                decoration: InputDecoration(
                                  labelText: 'Archival date',
                                  hintText: _dateType == 'Decade'
                                      ? '1950'
                                      : _dateType == 'Year only'
                                          ? '1956'
                                          : '1956-07-04 or Summer 1948',
                                  border: const OutlineInputBorder(),
                                ),
                              );

                              if (stackFields) {
                                return Column(
                                  children: [
                                    typeField,
                                    const SizedBox(height: 10),
                                    dateField,
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  typeField,
                                  const SizedBox(width: 10),
                                  Expanded(child: dateField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          Autocomplete<String>(
                            initialValue:
                                TextEditingValue(text: _locationController.text),
                            optionsBuilder: (value) {
                              final query = value.text.trim().toLowerCase();
                              if (query.isEmpty) return const Iterable<String>.empty();
                              return _knownLocations.where(
                                (item) => item.toLowerCase().contains(query),
                              );
                            },
                            onSelected: (value) {
                              _locationController.text = value;
                            },
                            fieldViewBuilder: (
                              context,
                              controller,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              controller.addListener(() {
                                if (_locationController.text != controller.text) {
                                  _locationController.text = controller.text;
                                }
                              });
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Location',
                                  hintText: 'Rome, New York',
                                  border: OutlineInputBorder(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _descriptionController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _notesController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Heirloom Atlas Notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 26),
                          const Divider(),
                          const SizedBox(height: 10),
                          Text(
                            'Embedded Photo Metadata',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          if (_embeddedMetadata != null) ...[
                            _embeddedRow('Date', _embeddedMetadata!.dateTaken),
                            _embeddedRow(
                              'Description',
                              _embeddedMetadata!.description,
                            ),
                            if (_embeddedMetadata!.tags.isNotEmpty) ...[
                              const Text(
                                'Embedded Tags',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _embeddedMetadata!.tags
                                    .map((tag) => Chip(label: Text(tag)))
                                    .toList(),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _embeddedRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
  }
}


class _FamilyTreeLinksCard extends StatelessWidget {
  final List<FamilyPerson> people;
  final VoidCallback onEdit;

  const _FamilyTreeLinksCard({
    required this.people,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Family Tree Links',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.link),
                  label: Text(people.isEmpty ? 'Link People' : 'Edit Links'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              people.isEmpty
                  ? 'Connect this photo to people in your Family Tree. '
                      'Atlas Book will use these links to gather photos automatically.'
                  : 'This photo is connected to ${people.length} '
                      '${people.length == 1 ? 'person' : 'people'} in your Family Tree.',
            ),
            if (people.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: people
                    .map(
                      (person) => Chip(
                        avatar: const Icon(Icons.person_outline, size: 18),
                        label: Text(
                          person.lifeSpan.isEmpty
                              ? person.displayName
                              : '${person.displayName} • ${person.lifeSpan}',
                        ),
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
}

class _FamilyTreePeoplePickerDialog extends StatefulWidget {
  final List<FamilyPerson> people;
  final Set<int> initiallySelectedIds;

  const _FamilyTreePeoplePickerDialog({
    required this.people,
    required this.initiallySelectedIds,
  });

  @override
  State<_FamilyTreePeoplePickerDialog> createState() =>
      _FamilyTreePeoplePickerDialogState();
}

class _FamilyTreePeoplePickerDialogState
    extends State<_FamilyTreePeoplePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late Set<int> _selectedIds;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initiallySelectedIds};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visiblePeople = widget.people.where((person) {
      if (query.isEmpty) return true;

      return person.displayName.toLowerCase().contains(query) ||
          person.birthName.toLowerCase().contains(query) ||
          person.birthPlace.toLowerCase().contains(query) ||
          person.lifeSpan.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      title: const Text('Link Family Tree People'),
      content: SizedBox(
        width: 700,
        height: 600,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search Family Tree',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selectedIds.length} '
                '${_selectedIds.length == 1 ? 'person' : 'people'} selected',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visiblePeople.isEmpty
                  ? const Center(child: Text('No matching people found.'))
                  : ListView.builder(
                      itemCount: visiblePeople.length,
                      itemBuilder: (context, index) {
                        final person = visiblePeople[index];
                        final id = person.id;

                        if (id == null) return const SizedBox.shrink();

                        return CheckboxListTile(
                          value: _selectedIds.contains(id),
                          title: Text(person.displayName),
                          subtitle: Text(
                            [
                              if (person.lifeSpan.isNotEmpty) person.lifeSpan,
                              if (person.birthPlace.isNotEmpty)
                                person.birthPlace,
                            ].join(' • '),
                          ),
                          onChanged: (selected) {
                            setState(() {
                              if (selected ?? false) {
                                _selectedIds.add(id);
                              } else {
                                _selectedIds.remove(id);
                              }
                            });
                          },
                        );
                      },
                    ),
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
          onPressed: () => Navigator.pop(context, _selectedIds),
          icon: const Icon(Icons.link),
          label: const Text('Save Links'),
        ),
      ],
    );
  }
}

class _ChipEditor extends StatefulWidget {
  final String label;
  final String hint;
  final List<String> values;
  final List<String> suggestions;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  const _ChipEditor({
    required this.label,
    required this.hint,
    required this.values,
    required this.suggestions,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<_ChipEditor> createState() => _ChipEditorState();
}

class _ChipEditorState extends State<_ChipEditor> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? <String>[]
        : widget.suggestions
            .where(
              (item) =>
                  !widget.values.contains(item) &&
                  item.toLowerCase().contains(query),
            )
            .take(6)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.values
                .map(
                  (value) => InputChip(
                    label: Text(value),
                    onDeleted: () => widget.onRemove(value),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            widget.onAdd(value);
            _controller.clear();
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Add',
              onPressed: () {
                widget.onAdd(_controller.text);
                _controller.clear();
                setState(() {});
              },
              icon: const Icon(Icons.add),
            ),
          ),
        ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: matches
                .map(
                  (value) => ActionChip(
                    label: Text(value),
                    onPressed: () {
                      widget.onAdd(value);
                      _controller.clear();
                      setState(() {});
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
