import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import '../models/detected_face_record.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';
import '../services/photo_metadata_reader.dart';
import '../services/photo_metadata_writer.dart';
import '../services/sync_service.dart';

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
  final SyncService _syncService = SyncService();

  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _backWritingController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late int _index;
  PhotoMetadata? _embeddedMetadata;
  PhotoCatalogMetadata? _loadedCatalogMetadata;

  List<String> _people = [];
  List<String> _tags = [];
  List<String> _knownPeople = [];
  List<String> _knownTags = [];
  List<String> _knownLocations = [];
  List<FamilyPerson> _linkedFamilyPeople = [];
  List<DetectedFaceRecord> _confirmedFaces = [];
  Map<String, int> _photoPersonAliases = <String, int>{};

  String _dateType = 'Approximate';
  bool _loading = true;
  bool _saving = false;
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
    _backWritingController.dispose();
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
        _databaseHelper.getFacesForPhotoPaths([_photo.filePath]),
        _databaseHelper.getPhotoPersonAliases(),
      ]);

      final embedded = results[0] as PhotoMetadata;
      final catalog = results[1] as PhotoCatalogMetadata;
      final linkedFamilyPeople = results[2] as List<FamilyPerson>;
      final faces = (results[3] as List<DetectedFaceRecord>)
          .where((face) => face.confirmed && face.personName.trim().isNotEmpty)
          .toList();
      final aliases = results[4] as Map<String, int>;

      if (!mounted) return;

      _loadedCatalogMetadata = catalog;
      _people = [...catalog.people];
      _tags = [...catalog.tags];

      final parsed = _parseStoredDate(catalog.approximateDate);
      _dateType = parsed.$1;
      _dateController.text = parsed.$2;

      _locationController.text = catalog.location;
      _descriptionController.text = catalog.description;
      _backWritingController.text = catalog.backWriting;
      _notesController.text = catalog.notes;

      setState(() {
        _embeddedMetadata = embedded;
        _linkedFamilyPeople = linkedFamilyPeople;
        _confirmedFaces = faces;
        _photoPersonAliases = aliases;
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
      backWriting: _backWritingController.text.trim(),
      notes: _notesController.text.trim(),
    );
  }

  List<String> _changedMetadataFields(PhotoCatalogMetadata metadata) {
    final loaded = _loadedCatalogMetadata;
    if (loaded == null) return const ['Photo details'];

    final changed = <String>[];
    if (loaded.people.join('\u001f') != metadata.people.join('\u001f')) {
      changed.add('People');
    }
    if (loaded.tags.join('\u001f') != metadata.tags.join('\u001f')) {
      changed.add('Tags');
    }
    if (loaded.approximateDate.trim() != metadata.approximateDate.trim()) {
      changed.add('Date');
    }
    if (loaded.location.trim() != metadata.location.trim()) {
      changed.add('Location');
    }
    if (loaded.description.trim() != metadata.description.trim()) {
      changed.add('Description');
    }
    if (loaded.backWriting.trim() != metadata.backWriting.trim()) {
      changed.add('Back writing');
    }
    if (loaded.notes.trim() != metadata.notes.trim()) changed.add('Notes');
    return changed;
  }

  Future<bool> _saveCatalogMetadataWithSync(
    PhotoCatalogMetadata metadata,
  ) async {
    final changedFields = _changedMetadataFields(metadata);
    final changed = changedFields.isNotEmpty;
    await _databaseHelper.savePhotoCatalogMetadata(metadata);

    if (changed) {
      await _syncService.recordLocalChange(
        entityType: 'photo',
        localKey: metadata.filePath,
        operation: 'update',
        changedFields: changedFields,
      );

      _loadedCatalogMetadata = metadata;
    }
    return changed;
  }

  Future<void> _save({bool showMessage = true}) async {
    setState(() => _saving = true);
    try {
      final metadata = _currentCatalogMetadata();
      final changedFields = _changedMetadataFields(metadata);
      await _saveCatalogMetadataWithSync(metadata);

      PhotoMetadataWriteResult? writeResult;
      if (changedFields.any(_isPortableMetadataField)) {
        writeResult = await PhotoMetadataWriter.write(
          filePath: _photo.filePath,
          metadata: metadata,
        );

        if (writeResult.success) {
          final refreshed = await PhotoMetadataReader.read(_photo.filePath);
          if (mounted) {
            setState(() => _embeddedMetadata = refreshed);
          }
        }
      }

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
        final portableChanged = changedFields.any(_isPortableMetadataField);
        final message = !portableChanged
            ? 'Photo details saved.'
            : writeResult?.success == true
            ? 'Photo details saved and written to the original file.'
            : 'Photo details saved to Heirloom Atlas. The original file could not be updated.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save photo details: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isPortableMetadataField(String field) {
    return const {
      'People',
      'Tags',
      'Date',
      'Location',
      'Description',
    }.contains(field);
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

  Future<void> _changeFacePerson(DetectedFaceRecord face) async {
    final faceId = face.id;
    if (faceId == null) return;

    var typedName = face.personName;

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = typedName.trim().toLowerCase();
          final suggestions = _knownPeople
              .where(
                (name) =>
                    name != face.personName &&
                    (query.isEmpty || name.toLowerCase().contains(query)),
              )
              .take(8)
              .toList();

          void submit() {
            final clean = typedName.trim();
            if (clean.isEmpty || clean == face.personName) return;
            FocusScope.of(dialogContext).unfocus();
            Navigator.pop(dialogContext, clean);
          }

          return AlertDialog(
            title: const Text('Change face identity'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Currently identified as ${face.personName}'),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: face.personName,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Correct person',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      typedName = value;
                      setDialogState(() {});
                    },
                    onFieldSubmitted: (_) => submit(),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: suggestions
                          .map(
                            (name) => ActionChip(
                              label: Text(name),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, name),
                            ),
                          )
                          .toList(),
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
              FilledButton(onPressed: submit, child: const Text('Update Name')),
            ],
          );
        },
      ),
    );

    if (newName == null || newName.trim().isEmpty) return;

    await _databaseHelper.reassignConfirmedFace(
      faceId: faceId,
      newPersonName: newName,
    );
    await _loadPhoto();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Face changed from ${face.personName} to ${newName.trim()}.',
        ),
      ),
    );
  }

  Future<void> _markFaceUnidentified(DetectedFaceRecord face) async {
    final faceId = face.id;
    if (faceId == null) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Mark face unidentified?'),
            content: Text(
              'Heirloom Atlas will stop treating this face as '
              '"${face.personName}". The face will return to Unidentified '
              'Faces for review. The original photo will not be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Mark Unidentified'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _databaseHelper.markFaceUnidentified(faceId);

    final remainingFaces = _confirmedFaces
        .where((item) => item.id != faceId)
        .toList();
    final stillHasPerson = remainingFaces.any(
      (item) => item.personName == face.personName,
    );

    if (!stillHasPerson) {
      _people.remove(face.personName);
      await _saveCatalogMetadataWithSync(_currentCatalogMetadata());
    }

    if (!mounted) return;
    setState(() {
      _confirmedFaces = remainingFaces;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${face.personName} was removed from this face. '
          'It is unidentified again.',
        ),
      ),
    );
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

    final linked = await _databaseHelper.getFamilyPeopleForPhoto(
      _photo.filePath,
    );

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

  Future<void> _matchPhotoNamesToFamilyTree() async {
    final photoNames = <String>{
      ..._people.map((name) => name.trim()).where((name) => name.isNotEmpty),
      ..._confirmedFaces
          .map((face) => face.personName.trim())
          .where((name) => name.isNotEmpty),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (photoNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no photo names to match yet.')),
      );
      return;
    }

    if (_linkedFamilyPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Link the Family Tree people in this photo first, then match '
            'their everyday photo names.',
          ),
        ),
      );
      return;
    }

    final linkedById = <int, FamilyPerson>{
      for (final person in _linkedFamilyPeople)
        if (person.id != null) person.id!: person,
    };

    final selections = <String, int?>{
      for (final name in photoNames) name: _photoPersonAliases[name],
    };

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Match Photo Names to Family Tree'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose who each everyday photo name refers to. '
                      'Heirloom Atlas will remember the alias and show the '
                      'person only once.',
                    ),
                    const SizedBox(height: 18),
                    for (final name in photoNames) ...[
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int?>(
                        initialValue: selections[name],
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Family Tree person',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Not matched'),
                          ),
                          ...linkedById.entries.map(
                            (entry) => DropdownMenuItem<int?>(
                              value: entry.key,
                              child: Text(entry.value.displayName),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() => selections[name] = value);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.link),
                label: const Text('Save Matches'),
              ),
            ],
          );
        },
      ),
    );

    if (save != true) return;

    for (final name in photoNames) {
      final selectedId = selections[name];
      final existingId = _photoPersonAliases[name];

      if (selectedId == null) {
        if (existingId != null) {
          await _databaseHelper.removePhotoPersonAlias(name);
        }
      } else {
        await _databaseHelper.setPhotoPersonAlias(
          aliasName: name,
          familyPersonId: selectedId,
        );
      }
    }

    final aliases = await _databaseHelper.getPhotoPersonAliases();
    if (!mounted) return;

    setState(() {
      _photoPersonAliases = aliases;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo names matched. Linked aliases now count as one person.',
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
      appBar: AppBar(title: Text(_photo.fileName), actions: []),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Could not load photo.\n\n$_error'))
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                              onPressed: _index > 0 ? () => _move(-1) : null,
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
                        'Tell the Story of This Photo',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Answer what you know. Heirloom Atlas keeps the '
                        'cataloging details organized behind the scenes.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 22),

                      Text(
                        'Who is in this photo?',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _PeopleIdentityCard(
                        people: _people,
                        suggestions: _knownPeople,
                        familyPeople: _linkedFamilyPeople,
                        faces: _confirmedFaces,
                        aliases: _photoPersonAliases,
                        onAddPerson: _addPerson,
                        onRemovePerson: (value) =>
                            setState(() => _people.remove(value)),
                        onEditFamilyLinks: _chooseFamilyTreePeople,
                        onMatchNames: _matchPhotoNamesToFamilyTree,
                        onChangeFacePerson: _changeFacePerson,
                        onUnidentifyFace: _markFaceUnidentified,
                      ),

                      const SizedBox(height: 24),
                      Text(
                        'When was it taken?',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stackFields = constraints.maxWidth < 430;
                          final typeField = SizedBox(
                            width: stackFields ? constraints.maxWidth : 145,
                            child: DropdownButtonFormField<String>(
                              initialValue: _dateType,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'How certain?',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  const [
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
                              labelText: 'Date',
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              typeField,
                              const SizedBox(width: 10),
                              Expanded(child: dateField),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 24),
                      Text(
                        'Where was it taken?',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Autocomplete<String>(
                        initialValue: TextEditingValue(
                          text: _locationController.text,
                        ),
                        optionsBuilder: (value) {
                          final query = value.text.trim().toLowerCase();
                          if (query.isEmpty) return _knownLocations;
                          return _knownLocations.where(
                            (item) => item.toLowerCase().contains(query),
                          );
                        },
                        onSelected: (value) {
                          _locationController.text = value;
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                              controller.addListener(() {
                                if (_locationController.text !=
                                    controller.text) {
                                  _locationController.text = controller.text;
                                }
                              });
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  hintText: 'Rome, New York',
                                  border: OutlineInputBorder(),
                                ),
                              );
                            },
                      ),

                      const SizedBox(height: 24),
                      Text(
                        "What's happening?",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _descriptionController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText:
                              'Describe the people, event, place, or story shown here.',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 24),
                      Text(
                        'Tags / Keywords',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _ChipEditor(
                        label: 'Organize this photo',
                        hint: 'Add a tag',
                        values: _tags,
                        suggestions: _knownTags,
                        onAdd: _addTag,
                        onRemove: (value) =>
                            setState(() => _tags.remove(value)),
                      ),

                      const SizedBox(height: 24),
                      Text(
                        "What's written on the back?",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Transcribe handwriting, captions, dates, names, '
                        'studio marks, or other writing exactly as you see it.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _backWritingController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Example: “Grandma Rita, summer 1952”',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 24),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 12),
                        title: const Text(
                          'More details',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          'Private notes and embedded file metadata',
                        ),
                        children: [
                          TextField(
                            controller: _notesController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Heirloom Atlas Notes',
                              hintText:
                                  'Research notes, uncertainties, or reminders.',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Embedded Photo Metadata',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_embeddedMetadata != null) ...[
                            _embeddedRow('Date', _embeddedMetadata!.dateTaken),
                            _embeddedRow(
                              'Description',
                              _embeddedMetadata!.description,
                            ),
                            if (_embeddedMetadata!.tags.isNotEmpty) ...[
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Embedded Tags',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _embeddedMetadata!.tags
                                      .map((tag) => Chip(label: Text(tag)))
                                      .toList(),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving || _loading ? null : () => _save(),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      ),
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

class _PersonIdentityLabel {
  final String displayName;
  final String canonicalName;
  final bool linkedToTree;
  final bool hasFace;

  const _PersonIdentityLabel({
    required this.displayName,
    required this.canonicalName,
    required this.linkedToTree,
    required this.hasFace,
  });
}

class _PeopleIdentityCard extends StatelessWidget {
  final List<String> people;
  final List<String> suggestions;
  final List<FamilyPerson> familyPeople;
  final List<DetectedFaceRecord> faces;
  final Map<String, int> aliases;
  final ValueChanged<String> onAddPerson;
  final ValueChanged<String> onRemovePerson;
  final VoidCallback onEditFamilyLinks;
  final VoidCallback onMatchNames;
  final ValueChanged<DetectedFaceRecord> onChangeFacePerson;
  final ValueChanged<DetectedFaceRecord> onUnidentifyFace;

  const _PeopleIdentityCard({
    required this.people,
    required this.suggestions,
    required this.familyPeople,
    required this.faces,
    required this.aliases,
    required this.onAddPerson,
    required this.onRemovePerson,
    required this.onEditFamilyLinks,
    required this.onMatchNames,
    required this.onChangeFacePerson,
    required this.onUnidentifyFace,
  });

  @override
  Widget build(BuildContext context) {
    final familyById = <int, FamilyPerson>{
      for (final person in familyPeople)
        if (person.id != null) person.id!: person,
    };
    final photoNames = <String>{
      ...people.map((name) => name.trim()).where((name) => name.isNotEmpty),
      ...faces
          .map((face) => face.personName.trim())
          .where((name) => name.isNotEmpty),
    };

    final matchedAliasesByFamily = <int, List<String>>{};
    final unmatchedNames = <String>[];

    for (final name in photoNames) {
      final familyId = aliases[name];
      if (familyId != null && familyById.containsKey(familyId)) {
        matchedAliasesByFamily
            .putIfAbsent(familyId, () => <String>[])
            .add(name);
      } else {
        unmatchedNames.add(name);
      }
    }

    final identityLabels = <_PersonIdentityLabel>[];

    for (final entry in familyById.entries) {
      final matched = matchedAliasesByFamily[entry.key] ?? const <String>[];
      final display = matched.isNotEmpty
          ? matched.first
          : entry.value.displayName;
      identityLabels.add(
        _PersonIdentityLabel(
          displayName: display,
          canonicalName: entry.value.displayName,
          linkedToTree: true,
          hasFace: matched.any(
            (alias) => faces.any(
              (face) =>
                  face.personName.trim().toLowerCase() == alias.toLowerCase(),
            ),
          ),
        ),
      );
    }

    for (final name in unmatchedNames) {
      identityLabels.add(
        _PersonIdentityLabel(
          displayName: name,
          canonicalName: '',
          linkedToTree: false,
          hasFace: faces.any(
            (face) =>
                face.personName.trim().toLowerCase() == name.toLowerCase(),
          ),
        ),
      );
    }

    identityLabels.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    identityLabels.isEmpty
                        ? 'No people identified yet'
                        : '${identityLabels.length} ${identityLabels.length == 1 ? 'person' : 'people'} identified',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onMatchNames,
                  icon: const Icon(Icons.link_outlined, size: 18),
                  label: const Text('Match Names'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onEditFamilyLinks,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('Family Tree'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Add a name once. Heirloom Atlas can also connect that person '
              'to the Family Tree and recognized faces.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (identityLabels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: identityLabels.map((identity) {
                  final chip = Chip(
                    avatar: Icon(
                      identity.hasFace
                          ? Icons.face_outlined
                          : identity.linkedToTree
                          ? Icons.account_tree_outlined
                          : Icons.person_outline,
                      size: 18,
                    ),
                    label: Text(identity.displayName),
                  );

                  if (identity.linkedToTree &&
                      identity.canonicalName.isNotEmpty &&
                      identity.canonicalName != identity.displayName) {
                    return Tooltip(
                      message: 'Family Tree: ${identity.canonicalName}',
                      child: chip,
                    );
                  }
                  return chip;
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            _ChipEditor(
              label: 'Add or correct a person',
              hint: 'Type a name',
              values: people,
              suggestions: suggestions,
              onAdd: onAddPerson,
              onRemove: onRemovePerson,
            ),
            if (familyPeople.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Family Tree',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: familyPeople
                    .map(
                      (person) => Chip(
                        avatar: const Icon(
                          Icons.account_tree_outlined,
                          size: 17,
                        ),
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
            if (faces.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Recognized in this photo',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...faces.map((face) {
                final thumbnail = File(face.thumbnailPath);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: thumbnail.existsSync()
                            ? FileImage(thumbnail)
                            : null,
                        child: thumbnail.existsSync()
                            ? null
                            : const Icon(Icons.person_outline),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          face.personName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => onChangeFacePerson(face),
                        child: const Text('Change'),
                      ),
                      TextButton(
                        onPressed: () => onUnidentifyFace(face),
                        child: const Text('Unidentify'),
                      ),
                    ],
                  ),
                );
              }),
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
