import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../models/document_record.dart';
import '../models/family_person.dart';

class DocumentsScreen extends StatefulWidget {
  final String? initialFilePath;
  final VoidCallback? onInitialFileConsumed;

  const DocumentsScreen({
    super.key,
    this.initialFilePath,
    this.onInitialFileConsumed,
  });

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  List<DocumentRecord> _documents = const [];
  bool _loading = true;
  bool _initialFileHandled = false;
  String _query = '';
  String _typeFilter = 'All';
  String? _reviewFilter;
  final Set<int> _selectedDocumentIds = <int>{};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadDocuments();
    if (!mounted) return;
    await _handleInitialFile();
  }

  Future<void> _loadDocuments() async {
    try {
      final documents = await _databaseHelper.getDocuments();
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load documents: $error')),
      );
    }
  }

  Future<void> _handleInitialFile() async {
    if (_initialFileHandled) return;
    final initialPath = widget.initialFilePath?.trim() ?? '';
    if (initialPath.isEmpty) return;
    _initialFileHandled = true;

    final file = File(initialPath);
    if (!await file.exists()) {
      widget.onInitialFileConsumed?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The selected document could not be found.'),
        ),
      );
      return;
    }

    await _showDocumentEditor(initialFilePath: initialPath);
    widget.onInitialFileConsumed?.call();
  }

  Future<void> _pickAndAddDocument() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'txt',
        'rtf',
        'jpg',
        'jpeg',
        'png',
        'tif',
        'tiff',
        'heic',
      ],
    );
    final filePath = picked?.path;
    if (!mounted || filePath == null || filePath.trim().isEmpty) return;
    await _showDocumentEditor(initialFilePath: filePath);
  }

  Future<List<FamilyPerson>?> _chooseFamilyTreePeople(
    List<FamilyPerson> initiallySelected,
  ) async {
    final allPeople = await _databaseHelper.getFamilyPeople();
    if (!mounted) return null;

    final selectedIds = <int>{
      for (final person in initiallySelected)
        if (person.id != null) person.id!,
    };
    var search = '';

    return showDialog<List<FamilyPerson>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = search.trim().toLowerCase();
          final visible = allPeople.where((person) {
            if (query.isEmpty) return true;
            return person.displayName.toLowerCase().contains(query) ||
                person.birthName.toLowerCase().contains(query) ||
                person.birthPlace.toLowerCase().contains(query) ||
                person.deathPlace.toLowerCase().contains(query) ||
                person.lifeSpan.toLowerCase().contains(query);
          }).toList();

          return Dialog(
            child: SizedBox(
              width: 720,
              height: 680,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.family_restroom_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Link Family Tree People',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          '${selectedIds.length} selected',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Close',
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
                      onChanged: (value) =>
                          setDialogState(() => search = value),
                      decoration: const InputDecoration(
                        hintText: 'Search Family Tree...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: allPeople.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Text(
                                'There are no people in the Family Tree yet.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : visible.isEmpty
                        ? const Center(
                            child: Text('No matching Family Tree people.'),
                          )
                        : ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final person = visible[index];
                              final personId = person.id;
                              final selected =
                                  personId != null &&
                                  selectedIds.contains(personId);
                              final photoPath = person.profilePhotoPath.trim();
                              final hasPhoto =
                                  photoPath.isNotEmpty &&
                                  File(photoPath).existsSync();

                              return CheckboxListTile(
                                value: selected,
                                onChanged: personId == null
                                    ? null
                                    : (value) {
                                        setDialogState(() {
                                          if (value == true) {
                                            selectedIds.add(personId);
                                          } else {
                                            selectedIds.remove(personId);
                                          }
                                        });
                                      },
                                secondary: CircleAvatar(
                                  backgroundImage: hasPhoto
                                      ? FileImage(File(photoPath))
                                      : null,
                                  child: hasPhoto
                                      ? null
                                      : const Icon(Icons.person_outline),
                                ),
                                title: Text(person.displayName),
                                subtitle: Text(
                                  [
                                    if (person.lifeSpan.isNotEmpty)
                                      person.lifeSpan,
                                    if (person.birthPlace.isNotEmpty)
                                      person.birthPlace,
                                  ].join(' • '),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        if (selectedIds.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => setDialogState(selectedIds.clear),
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Clear All'),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () {
                            final selected = allPeople
                                .where(
                                  (person) =>
                                      person.id != null &&
                                      selectedIds.contains(person.id),
                                )
                                .toList();
                            Navigator.pop(dialogContext, selected);
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Use Selected People'),
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
  }

  Future<void> _showDocumentEditor({
    DocumentRecord? document,
    String? initialFilePath,
  }) async {
    final filePath = initialFilePath ?? document?.filePath ?? '';
    final initialTitle = document?.title.trim().isNotEmpty == true
        ? document!.title
        : path.basenameWithoutExtension(filePath);

    final titleController = TextEditingController(text: initialTitle);
    final dateController = TextEditingController(
      text: document?.documentDate ?? '',
    );
    final peopleController = TextEditingController(
      text: document?.people ?? '',
    );
    final initiallyLinkedFamilyPeople = filePath.trim().isEmpty
        ? <FamilyPerson>[]
        : await _databaseHelper.getFamilyPeopleForItem(
            itemType: 'document',
            itemKey: filePath,
          );
    if (!mounted) {
      titleController.dispose();
      dateController.dispose();
      peopleController.dispose();
      return;
    }
    var linkedFamilyPeople = List<FamilyPerson>.from(
      initiallyLinkedFamilyPeople,
    );

    final descriptionController = TextEditingController(
      text: document?.description ?? '',
    );
    final sourceController = TextEditingController(
      text: document?.source ?? '',
    );
    String documentType = document?.documentType.trim().isNotEmpty == true
        ? document!.documentType
        : _guessDocumentType(filePath);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _panel,
              surfaceTintColor: Colors.transparent,
              title: Text(
                document == null ? 'Add Document' : 'Edit Document',
                style: const TextStyle(color: _cream),
              ),
              content: SizedBox(
                width: 650,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FileSummary(filePath: filePath),
                      const SizedBox(height: 18),
                      TextField(
                        controller: titleController,
                        style: const TextStyle(color: _cream),
                        decoration: _inputDecoration('Title'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: dateController,
                              style: const TextStyle(color: _cream),
                              decoration: _inputDecoration('Date'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: documentType,
                              dropdownColor: _panel,
                              style: const TextStyle(color: _cream),
                              decoration: _inputDecoration('Document Type'),
                              items:
                                  const [
                                        'Letter',
                                        'Certificate',
                                        'Record',
                                        'Newspaper',
                                        'Legal',
                                        'Military',
                                        'School',
                                        'Church',
                                        'Photo / Scan',
                                        'Other',
                                      ]
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => documentType = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: .45),
                          border: Border.all(
                            color: _gold.withValues(alpha: .30),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.family_restroom_outlined,
                                  color: _gold,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'FAMILY TREE PEOPLE',
                                    style: TextStyle(
                                      color: _cream,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .6,
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final selected =
                                        await _chooseFamilyTreePeople(
                                          linkedFamilyPeople,
                                        );
                                    if (selected == null ||
                                        !dialogContext.mounted) {
                                      return;
                                    }
                                    setDialogState(
                                      () => linkedFamilyPeople = selected,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.person_search_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    linkedFamilyPeople.isEmpty
                                        ? 'Link People'
                                        : 'Change',
                                  ),
                                ),
                              ],
                            ),
                            if (linkedFamilyPeople.isEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'No Family Tree people linked yet.',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                            ] else ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: linkedFamilyPeople
                                    .map(
                                      (person) => Chip(
                                        avatar: const Icon(
                                          Icons.person_outline,
                                          size: 16,
                                        ),
                                        label: Text(person.displayName),
                                        onDeleted: () {
                                          setDialogState(
                                            () =>
                                                linkedFamilyPeople.removeWhere(
                                                  (candidate) =>
                                                      candidate.id == person.id,
                                                ),
                                          );
                                        },
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: peopleController,
                        style: const TextStyle(color: _cream),
                        decoration: _inputDecoration(
                          'Other People / Names (not linked to Family Tree)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sourceController,
                        style: const TextStyle(color: _cream),
                        decoration: _inputDecoration('Source / Provenance'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 4,
                        style: const TextStyle(color: _cream),
                        decoration: _inputDecoration('Description / Notes'),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Heirloom Atlas stores this file location and catalog information. '
                        'The original file is not moved or deleted.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
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
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    final now = DateTime.now().millisecondsSinceEpoch;
                    final record = DocumentRecord(
                      id: document?.id,
                      title: title,
                      documentDate: dateController.text.trim(),
                      documentType: documentType,
                      people: peopleController.text.trim(),
                      description: descriptionController.text.trim(),
                      source: sourceController.text.trim(),
                      filePath: filePath,
                      createdAtMilliseconds:
                          document?.createdAtMilliseconds ?? now,
                      updatedAtMilliseconds: now,
                    );
                    if (document?.id == null) {
                      await _databaseHelper.insertDocument(record);
                    } else {
                      await _databaseHelper.updateDocument(record);
                    }

                    await _databaseHelper.replaceFamilyPeopleForItem(
                      itemType: 'document',
                      itemKey: filePath,
                      personIds: linkedFamilyPeople
                          .map((person) => person.id)
                          .whereType<int>(),
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Document'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    dateController.dispose();
    peopleController.dispose();
    descriptionController.dispose();
    sourceController.dispose();

    if (saved == true) {
      await _loadDocuments();
    }
  }

  Future<void> _openDocument(DocumentRecord document) async {
    final filePath = document.filePath.trim();
    if (filePath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file location is saved for this document.'),
        ),
      );
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('The document file could not be found:\n$filePath'),
        ),
      );
      return;
    }

    try {
      final opened = await launchUrl(
        Uri.file(filePath),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Windows could not open this document.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open document: $error')),
      );
    }
  }

  Future<Directory> _documentTrashDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      path.join(docs.path, 'Heirloom Atlas', 'Document Trash'),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _documentTrashManifestFile() async {
    final dir = await _documentTrashDirectory();
    return File(path.join(dir.path, 'document_trash_manifest.json'));
  }

  Future<List<Map<String, dynamic>>> _readDocumentTrashManifest() async {
    try {
      final file = await _documentTrashManifestFile();
      if (!await file.exists()) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _writeDocumentTrashManifest(
    List<Map<String, dynamic>> entries,
  ) async {
    final file = await _documentTrashManifestFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entries),
      flush: true,
    );
  }

  Future<String> _uniqueDocumentTrashPath(
    Directory trash,
    String fileName,
  ) async {
    var candidate = path.join(trash.path, fileName);
    if (!await File(candidate).exists()) return candidate;
    final extension = path.extension(fileName);
    final stem = path.basenameWithoutExtension(fileName);
    var index = 2;
    while (await File(candidate).exists()) {
      candidate = path.join(trash.path, '$stem ($index)$extension');
      index++;
    }
    return candidate;
  }

  Future<void> _moveFileSafely(File source, String destination) async {
    try {
      await source.rename(destination);
      return;
    } on FileSystemException {
      // rename() can fail when the original and trash are on different drives.
      final copied = await source.copy(destination);
      final sourceLength = await source.length();
      final copiedLength = await copied.length();
      if (sourceLength != copiedLength) {
        if (await copied.exists()) await copied.delete();
        throw FileSystemException('Copied file size did not match source.');
      }
      await source.delete();
    }
  }

  Map<String, dynamic> _documentTrashEntry(
    DocumentRecord document,
    String trashPath,
  ) {
    return <String, dynamic>{
      'originalPath': document.filePath,
      'trashPath': trashPath,
      'movedAt': DateTime.now().toIso8601String(),
      'title': document.title,
      'documentDate': document.documentDate,
      'documentType': document.documentType,
      'people': document.people,
      'description': document.description,
      'source': document.source,
      'createdAtMilliseconds': document.createdAtMilliseconds,
      'updatedAtMilliseconds': document.updatedAtMilliseconds,
    };
  }

  Future<void> _deleteDocument(DocumentRecord document) async {
    final filePath = document.filePath.trim();
    final fileExists = filePath.isNotEmpty && await File(filePath).exists();
    if (!mounted) return;
    if (!fileExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The original file could not be found, so it was not moved to Document Trash.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move Document to Trash?'),
        content: Text(
          'Move "${document.title}" to Heirloom Atlas Document Trash?\n\n'
          'The physical file will be moved from its current folder. You can restore it later. Permanent deletion is only available from Document Trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Move to Document Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final trash = await _documentTrashDirectory();
      final destination = await _uniqueDocumentTrashPath(
        trash,
        path.basename(filePath),
      );
      await _moveFileSafely(File(filePath), destination);

      final manifest = await _readDocumentTrashManifest();
      manifest.add(_documentTrashEntry(document, destination));
      try {
        await _writeDocumentTrashManifest(manifest);
      } catch (_) {
        // If the manifest cannot be saved, put the file back so nothing is lost.
        await _moveFileSafely(File(destination), filePath);
        rethrow;
      }

      if (document.id != null) {
        await _databaseHelper.deleteDocument(document.id!);
      }
      _DocumentThumbnailState.clearPreviewFor(filePath);
      await _loadDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document moved to Document Trash.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not move document to trash: $error')),
      );
    }
  }

  Future<void> _openDocumentTrash() async {
    var entries = await _readDocumentTrashManifest();
    entries = entries.where((entry) {
      final trashPath = entry['trashPath']?.toString() ?? '';
      return trashPath.isNotEmpty && File(trashPath).existsSync();
    }).toList();
    await _writeDocumentTrashManifest(entries);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _DocumentTrashDialog(
        entries: entries,
        onRestore: _restoreDocumentTrashEntry,
        onDeletePermanently: _deleteDocumentTrashEntryPermanently,
      ),
    );
    if (mounted) await _loadDocuments();
  }

  Future<bool> _restoreDocumentTrashEntry(Map<String, dynamic> entry) async {
    final trashPath = entry['trashPath']?.toString() ?? '';
    final originalPath = entry['originalPath']?.toString() ?? '';
    if (trashPath.isEmpty || originalPath.isEmpty) return false;

    final source = File(trashPath);
    if (!await source.exists()) return false;

    String? destination;
    try {
      final parent = Directory(path.dirname(originalPath));
      if (!await parent.exists()) await parent.create(recursive: true);
      destination = originalPath;
      if (await File(destination).exists()) {
        final extension = path.extension(originalPath);
        final stem = path.basenameWithoutExtension(originalPath);
        var index = 2;
        do {
          destination = path.join(
            parent.path,
            '$stem (Restored $index)$extension',
          );
          index++;
        } while (await File(destination).exists());
      }

      await _moveFileSafely(source, destination);
      final now = DateTime.now().millisecondsSinceEpoch;
      final restored = DocumentRecord(
        title:
            entry['title']?.toString() ??
            path.basenameWithoutExtension(destination),
        documentDate: entry['documentDate']?.toString() ?? '',
        documentType: entry['documentType']?.toString() ?? 'Other',
        people: entry['people']?.toString() ?? '',
        description: entry['description']?.toString() ?? '',
        source: entry['source']?.toString() ?? '',
        filePath: destination,
        createdAtMilliseconds:
            (entry['createdAtMilliseconds'] as num?)?.toInt() ?? now,
        updatedAtMilliseconds: now,
      );
      await _databaseHelper.insertDocument(restored);

      if (destination != originalPath) {
        final linkedPeople = await _databaseHelper.getFamilyPeopleForItem(
          itemType: 'document',
          itemKey: originalPath,
        );
        await _databaseHelper.replaceFamilyPeopleForItem(
          itemType: 'document',
          itemKey: destination,
          personIds: linkedPeople.map((person) => person.id).whereType<int>(),
        );
        await _databaseHelper.replaceFamilyPeopleForItem(
          itemType: 'document',
          itemKey: originalPath,
          personIds: const <int>[],
        );
      }

      final manifest = await _readDocumentTrashManifest();
      manifest.removeWhere(
        (item) => item['trashPath']?.toString() == trashPath,
      );
      await _writeDocumentTrashManifest(manifest);
      _DocumentThumbnailState.clearPreviewFor(trashPath);
      return true;
    } catch (_) {
      // If the file moved but catalog restoration failed, try to return it to
      // Document Trash so the manifest remains a valid recovery record.
      if (destination != null && await File(destination).exists()) {
        try {
          await _moveFileSafely(File(destination), trashPath);
        } catch (_) {}
      }
      return false;
    }
  }

  Future<bool> _deleteDocumentTrashEntryPermanently(
    Map<String, dynamic> entry,
  ) async {
    final trashPath = entry['trashPath']?.toString() ?? '';
    final originalPath = entry['originalPath']?.toString() ?? '';
    if (trashPath.isEmpty) return false;
    try {
      final file = File(trashPath);
      if (await file.exists()) await file.delete();
      if (originalPath.isNotEmpty) {
        await _databaseHelper.replaceFamilyPeopleForItem(
          itemType: 'document',
          itemKey: originalPath,
          personIds: const <int>[],
        );
      }
      final manifest = await _readDocumentTrashManifest();
      manifest.removeWhere(
        (item) => item['trashPath']?.toString() == trashPath,
      );
      await _writeDocumentTrashManifest(manifest);
      _DocumentThumbnailState.clearPreviewFor(trashPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _editSelectedDocuments() async {
    final selected = _documents
        .where(
          (document) =>
              document.id != null && _selectedDocumentIds.contains(document.id),
        )
        .toList();
    if (selected.isEmpty) return;

    final result = await showDialog<_DocumentBatchEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DocumentBatchEditDialog(count: selected.length),
    );
    if (result == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final document in selected) {
      final updated = DocumentRecord(
        id: document.id,
        title: document.title,
        documentDate: result.changeDate
            ? result.documentDate
            : document.documentDate,
        documentType: result.changeType
            ? result.documentType
            : document.documentType,
        people: result.changePeople ? result.people : document.people,
        description: result.changeDescription
            ? result.description
            : document.description,
        source: result.changeSource ? result.source : document.source,
        filePath: document.filePath,
        createdAtMilliseconds: document.createdAtMilliseconds,
        updatedAtMilliseconds: now,
      );
      await _databaseHelper.updateDocument(updated);
    }

    if (!mounted) return;
    setState(() => _selectedDocumentIds.clear());
    await _loadDocuments();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Updated ${selected.length} document${selected.length == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  void _selectAllShown(List<DocumentRecord> documents) {
    setState(() {
      for (final document in documents) {
        if (document.id != null) {
          _selectedDocumentIds.add(document.id!);
        }
      }
    });
  }

  void _clearDocumentSelection() {
    setState(() => _selectedDocumentIds.clear());
  }

  String _guessDocumentType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    if ([
      '.jpg',
      '.jpeg',
      '.png',
      '.tif',
      '.tiff',
      '.heic',
    ].contains(extension)) {
      return 'Photo / Scan';
    }
    return 'Other';
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _gold.withValues(alpha: .35)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _gold),
      ),
    );
  }

  List<DocumentRecord> get _filteredDocuments {
    final query = _query.trim().toLowerCase();
    return _documents.where((document) {
      if (_typeFilter != 'All' && document.documentType != _typeFilter) {
        return false;
      }

      switch (_reviewFilter) {
        case 'no_people':
          if (document.people.trim().isNotEmpty) return false;
        case 'no_date':
          if (document.documentDate.trim().isNotEmpty) return false;
        case 'no_source':
          if (document.source.trim().isNotEmpty) return false;
        case 'no_description':
          if (document.description.trim().isNotEmpty) return false;
      }

      if (query.isEmpty) return true;
      return document.title.toLowerCase().contains(query) ||
          document.people.toLowerCase().contains(query) ||
          document.description.toLowerCase().contains(query) ||
          document.source.toLowerCase().contains(query) ||
          document.filePath.toLowerCase().contains(query);
    }).toList();
  }

  int get _datedCount =>
      _documents.where((d) => d.documentDate.trim().isNotEmpty).length;
  int get _peopleCount =>
      _documents.where((d) => d.people.trim().isNotEmpty).length;
  int get _sourceCount =>
      _documents.where((d) => d.source.trim().isNotEmpty).length;
  int get _descriptionCount =>
      _documents.where((d) => d.description.trim().isNotEmpty).length;

  int _percent(int value) =>
      _documents.isEmpty ? 0 : ((value / _documents.length) * 100).round();

  Map<String, int> get _typeCounts {
    final result = <String, int>{};
    for (final document in _documents) {
      final type = document.documentType.trim().isEmpty
          ? 'Other'
          : document.documentType.trim();
      result[type] = (result[type] ?? 0) + 1;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final documents = _filteredDocuments;
    return Scaffold(
      backgroundColor: _navy,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              children: [
                _buildBanner(),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 980) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHealth(),
                          const SizedBox(height: 10),
                          _buildSearchBar(),
                        ],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: _buildHealth()),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: _buildSearchBar()),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 900) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTypesPanel(),
                          const SizedBox(height: 10),
                          _buildReviewPanel(),
                          const SizedBox(height: 10),
                          _buildQuickActionsPanel(),
                          const SizedBox(height: 12),
                          _buildLibraryPanel(documents),
                        ],
                      );
                    }
                    const gap = 14.0;
                    final leftWidth = (constraints.maxWidth - gap) / 3;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: leftWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTypesPanel(),
                              const SizedBox(height: 10),
                              _buildReviewPanel(),
                              const SizedBox(height: 10),
                              _buildQuickActionsPanel(),
                            ],
                          ),
                        ),
                        const SizedBox(width: gap),
                        Expanded(child: _buildLibraryPanel(documents)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _buildSafetyNote(),
              ],
            ),
    );
  }

  Widget _buildBanner() {
    return Container(
      height: 170,
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 10),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: const Color(0xFF071A2B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withValues(alpha: .55), width: .8),
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              border: Border.all(color: _gold.withValues(alpha: .55)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Icon(
              Icons.history_edu_outlined,
              color: _gold,
              size: 42,
            ),
          ),
          const SizedBox(width: 24),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Documents',
                  style: TextStyle(
                    color: _cream,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Preserve the records behind the story.',
                  style: TextStyle(color: _gold, fontSize: 17),
                ),
                SizedBox(height: 5),
                Text(
                  'Letters, certificates, military papers, newspapers, scans, and family records — cataloged without moving the originals.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _pickAndAddDocument,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('ADD DOCUMENT'),
          ),
        ],
      ),
    );
  }

  Widget _buildHealth() {
    final total = _documents.length;
    final peoplePct = _percent(_peopleCount);
    final datesPct = _percent(_datedCount);
    final sourcesPct = _percent(_sourceCount);
    final describedPct = _percent(_descriptionCount);
    final organizationPct = total == 0
        ? 0
        : ((peoplePct + datesPct + sourcesPct + describedPct) / 4).round();

    Color gaugeColor(int value) {
      if (value >= 75) return const Color(0xFF8FCB78);
      if (value >= 45) return const Color(0xFFE6C766);
      return const Color(0xFFE28A7A);
    }

    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _cream,
              fontWeight: FontWeight.w900,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _cream.withValues(alpha: .50),
              fontWeight: FontWeight.w700,
              fontSize: 8.5,
              letterSpacing: .75,
            ),
          ),
        ],
      ),
    );

    Widget gauge(
      String label,
      int value, {
      double size = 54,
      bool overall = false,
    }) {
      final color = gaugeColor(value);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: size,
                    height: size,
                    child: CircularProgressIndicator(
                      value: value / 100,
                      strokeWidth: overall ? 5 : 4,
                      strokeCap: StrokeCap.round,
                      backgroundColor: _cream.withValues(alpha: .09),
                      color: color,
                    ),
                  ),
                  Text(
                    '$value%',
                    style: TextStyle(
                      color: color,
                      fontSize: overall ? 13 : 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: overall ? _gold : _cream.withValues(alpha: .70),
                fontSize: overall ? 9.5 : 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF071B2D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withValues(alpha: .48), width: .9),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'DOCUMENT COLLECTION',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.2,
                    letterSpacing: 1.05,
                  ),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    stat('$total', 'Documents'),
                    stat('${_typeCounts.length}', 'Document Types'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 70, color: _gold.withValues(alpha: .20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ORGANIZATION',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.2,
                    letterSpacing: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  alignment: WrapAlignment.spaceAround,
                  runSpacing: 8,
                  children: [
                    gauge('OVERALL', organizationPct, size: 60, overall: true),
                    gauge('People', peoplePct),
                    gauge('Dates', datesPct),
                    gauge('Sources', sourcesPct),
                    gauge('Descriptions', describedPct),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final types = <String>['All', ..._typeCounts.keys.toList()..sort()];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF081E33).withValues(alpha: .97),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _gold.withValues(alpha: .48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: _cream, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF071A2B),
              hintText: 'Search your documents…',
              hintStyle: TextStyle(color: _cream.withValues(alpha: .48)),
              prefixIcon: const Icon(Icons.search, color: _gold),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: _gold.withValues(alpha: .30)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: types.contains(_typeFilter) ? _typeFilter : 'All',
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Document Type',
              prefixIcon: Icon(Icons.filter_list),
              border: OutlineInputBorder(),
            ),
            items: types
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(
                      type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _typeFilter = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTypesPanel() {
    final counts = _typeCounts;
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return _sidePanel(
      title: 'DOCUMENT TYPES',
      child: Column(
        children: [
          _sideRow(
            label: 'All Documents',
            value: '${_documents.length}',
            selected: _typeFilter == 'All',
            onTap: () => setState(() => _typeFilter = 'All'),
          ),
          for (final entry in entries)
            _sideRow(
              label: entry.key,
              value: '${entry.value}',
              selected: _typeFilter == entry.key,
              onTap: () => setState(() => _typeFilter = entry.key),
            ),
        ],
      ),
    );
  }

  Widget _buildReviewPanel() {
    return _sidePanel(
      title: 'REVIEW & ORGANIZE',
      child: Column(
        children: [
          _sideRow(
            label: 'No People',
            value: '${_documents.length - _peopleCount}',
            selected: _reviewFilter == 'no_people',
            onTap: () => setState(() {
              _reviewFilter = _reviewFilter == 'no_people' ? null : 'no_people';
              _selectedDocumentIds.clear();
            }),
          ),
          _sideRow(
            label: 'No Date',
            value: '${_documents.length - _datedCount}',
            selected: _reviewFilter == 'no_date',
            onTap: () => setState(() {
              _reviewFilter = _reviewFilter == 'no_date' ? null : 'no_date';
              _selectedDocumentIds.clear();
            }),
          ),
          _sideRow(
            label: 'No Source',
            value: '${_documents.length - _sourceCount}',
            selected: _reviewFilter == 'no_source',
            onTap: () => setState(() {
              _reviewFilter = _reviewFilter == 'no_source' ? null : 'no_source';
              _selectedDocumentIds.clear();
            }),
          ),
          _sideRow(
            label: 'No Description',
            value: '${_documents.length - _descriptionCount}',
            selected: _reviewFilter == 'no_description',
            onTap: () => setState(() {
              _reviewFilter = _reviewFilter == 'no_description'
                  ? null
                  : 'no_description';
              _selectedDocumentIds.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsPanel() {
    return _sidePanel(
      title: 'QUICK ACTIONS',
      child: Column(
        children: [
          _sideRow(label: 'Add Document', onTap: _pickAndAddDocument),
          _sideRow(label: 'Document Trash', onTap: _openDocumentTrash),
          if (_reviewFilter != null)
            _sideRow(
              label: 'Clear Review Filter',
              onTap: () => setState(() {
                _reviewFilter = null;
                _selectedDocumentIds.clear();
              }),
            ),
          _sideRow(
            label: 'Clear Search',
            onTap: _query.isEmpty
                ? null
                : () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
          ),
          _sideRow(
            label: 'Show All Documents',
            onTap: () => setState(() {
              _typeFilter = 'All';
              _reviewFilter = null;
              _query = '';
              _selectedDocumentIds.clear();
              _searchController.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _sidePanel({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF081E33).withValues(alpha: .97),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _gold.withValues(alpha: .30), width: .8),
      ),
      child: Column(
        children: [
          Container(
            height: 37,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF091F34),
              border: Border(
                bottom: BorderSide(
                  color: _gold.withValues(alpha: .26),
                  width: .8,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 1,
                  color: _gold.withValues(alpha: .82),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    fontSize: 10.8,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _sideRow({
    required String label,
    String? value,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _gold.withValues(alpha: .09) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: _gold.withValues(alpha: .18)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: .80),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _cream,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
            if (value != null)
              Text(
                value,
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: _gold.withValues(alpha: .8),
                size: 17,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryPanel(List<DocumentRecord> documents) {
    final reviewTitle = switch (_reviewFilter) {
      'no_people' => 'NEEDS PEOPLE',
      'no_date' => 'NEEDS DATE',
      'no_source' => 'NEEDS SOURCE',
      'no_description' => 'NEEDS DESCRIPTION',
      _ => null,
    };
    final selectableIds = documents
        .where((d) => d.id != null)
        .map((d) => d.id!)
        .toSet();
    final selectedShownCount = selectableIds
        .intersection(_selectedDocumentIds)
        .length;
    final allShownSelected =
        selectableIds.isNotEmpty && selectedShownCount == selectableIds.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 13),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _gold.withValues(alpha: .23)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          reviewTitle ??
                              (_typeFilter == 'All'
                                  ? 'DOCUMENTS'
                                  : _typeFilter.toUpperCase()),
                          style: const TextStyle(
                            color: _cream,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .45,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '${documents.length} documents',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      TextButton.icon(
                        onPressed: documents.isEmpty
                            ? null
                            : () {
                                if (allShownSelected) {
                                  setState(() {
                                    _selectedDocumentIds.removeAll(
                                      selectableIds,
                                    );
                                  });
                                } else {
                                  _selectAllShown(documents);
                                }
                              },
                        icon: Icon(
                          allShownSelected
                              ? Icons.deselect_outlined
                              : Icons.select_all_outlined,
                          size: 17,
                        ),
                        label: Text(
                          allShownSelected ? 'Deselect All' : 'Select All',
                        ),
                      ),
                      if (_selectedDocumentIds.isNotEmpty)
                        Text(
                          '${_selectedDocumentIds.length} selected',
                          style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      if (_selectedDocumentIds.isNotEmpty)
                        FilledButton.icon(
                          onPressed: _editSelectedDocuments,
                          icon: const Icon(Icons.edit_note_outlined, size: 18),
                          label: const Text('Edit Selected'),
                        ),
                      if (_selectedDocumentIds.isNotEmpty)
                        TextButton(
                          onPressed: _clearDocumentSelection,
                          child: const Text('Clear'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _pickAndAddDocument,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Document'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (documents.isEmpty)
            _EmptyDocuments(onAdd: _pickAndAddDocument)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: documents.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final document = documents[index];
                final selected =
                    document.id != null &&
                    _selectedDocumentIds.contains(document.id);
                return _DocumentCard(
                  document: document,
                  selected: selected,
                  onSelectionChanged: document.id == null
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _selectedDocumentIds.add(document.id!);
                            } else {
                              _selectedDocumentIds.remove(document.id);
                            }
                          });
                        },
                  onOpen: () => _openDocument(document),
                  onEdit: () => _showDocumentEditor(document: document),
                  onDelete: document.id == null
                      ? null
                      : () => _deleteDocument(document),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSafetyNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: .58),
        border: Border.all(color: _gold.withValues(alpha: .18)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: _gold, size: 19),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your collection is yours. Not ours. Documents stay in their original locations. Heirloom Atlas catalogs them in place.',
              style: TextStyle(color: _muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileSummary extends StatelessWidget {
  final String filePath;

  const _FileSummary({required this.filePath});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFC9A65A);
    const cream = Color(0xFFF3E9D1);
    const muted = Color(0xFFAAB8C2);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.attach_file, color: gold),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                path.basename(filePath),
                style: const TextStyle(
                  color: cream,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                filePath,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentRecord document;
  final bool selected;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _DocumentCard({
    required this.document,
    required this.selected,
    required this.onSelectionChanged,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const panel = Color(0xFF0B2742);
    const gold = Color(0xFFC9A65A);
    const cream = Color(0xFFF3E9D1);
    const muted = Color(0xFFAAB8C2);

    final detailParts = <String>[
      if (document.documentType.trim().isNotEmpty) document.documentType,
      if (document.documentDate.trim().isNotEmpty) document.documentDate,
      if (document.people.trim().isNotEmpty) document.people,
    ];

    return Material(
      color: selected
          ? gold.withValues(alpha: .12)
          : panel.withValues(alpha: .84),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: selected ? gold : gold.withValues(alpha: .22),
          width: selected ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: onSelectionChanged,
                activeColor: gold,
                checkColor: const Color(0xFF071A2B),
              ),
              const SizedBox(width: 6),
              _DocumentThumbnail(filePath: document.filePath),

              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: const TextStyle(
                        color: cream,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    if (detailParts.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        detailParts.join('  •  '),
                        style: const TextStyle(color: muted),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      path.basename(document.filePath),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open document',
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, color: gold),
              ),
              IconButton(
                tooltip: 'Edit details',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, color: gold),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Move to Document Trash',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentThumbnail extends StatefulWidget {
  final String filePath;

  const _DocumentThumbnail({required this.filePath});

  @override
  State<_DocumentThumbnail> createState() => _DocumentThumbnailState();
}

class _DocumentThumbnailState extends State<_DocumentThumbnail> {
  static const _gold = Color(0xFFC9A65A);
  static const _panel = Color(0xFF071A2B);
  static final Map<String, Future<Uint8List?>> _pdfPreviewCache = {};

  static void clearPreviewFor(String filePath) {
    _pdfPreviewCache.remove(filePath);
  }

  String get _extension => path.extension(widget.filePath).toLowerCase();

  @override
  Widget build(BuildContext context) {
    final extension = _extension;
    final canPreviewImage = {
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.bmp',
    }.contains(extension);

    return Container(
      width: 64,
      height: 78,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _gold.withValues(alpha: .35)),
      ),
      child: extension == '.pdf'
          ? FutureBuilder<Uint8List?>(
              future: _pdfPreviewCache.putIfAbsent(
                widget.filePath,
                () => _renderPdfFirstPage(widget.filePath),
              ),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes != null && bytes.isNotEmpty) {
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => _fallback(extension),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return _fallback(extension);
              },
            )
          : canPreviewImage && widget.filePath.trim().isNotEmpty
          ? Image.file(
              File(widget.filePath),
              fit: BoxFit.cover,
              cacheWidth: 160,
              errorBuilder: (_, _, _) => _fallback(extension),
            )
          : _fallback(extension),
    );
  }

  Future<Uint8List?> _renderPdfFirstPage(String filePath) async {
    if (filePath.trim().isEmpty) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;

    pdfx.PdfDocument? document;
    pdfx.PdfPage? page;
    try {
      document = await pdfx.PdfDocument.openFile(filePath);
      page = await document.getPage(1);

      const targetWidth = 180.0;
      final aspectRatio = page.height / page.width;
      final targetHeight = (targetWidth * aspectRatio).roundToDouble();
      final image = await page.render(
        width: targetWidth,
        height: targetHeight,
        format: pdfx.PdfPageImageFormat.png,
      );
      return image?.bytes;
    } catch (_) {
      return null;
    } finally {
      await page?.close();
      await document?.close();
    }
  }

  Widget _fallback(String extension) {
    final isPdf = extension == '.pdf';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isPdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined,
          color: _gold,
          size: 29,
        ),
        const SizedBox(height: 4),
        Text(
          extension.isEmpty ? 'FILE' : extension.substring(1).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _gold.withValues(alpha: .8),
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DocumentTrashDialog extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final Future<bool> Function(Map<String, dynamic>) onRestore;
  final Future<bool> Function(Map<String, dynamic>) onDeletePermanently;

  const _DocumentTrashDialog({
    required this.entries,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  @override
  State<_DocumentTrashDialog> createState() => _DocumentTrashDialogState();
}

class _DocumentTrashDialogState extends State<_DocumentTrashDialog> {
  late final List<Map<String, dynamic>> _entries =
      List<Map<String, dynamic>>.from(widget.entries);
  bool _busy = false;

  Future<void> _restore(Map<String, dynamic> entry) async {
    setState(() => _busy = true);
    final ok = await widget.onRestore(entry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _entries.remove(entry);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Document restored to its original folder.'
              : 'Could not restore document.',
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final trashPath = entry['trashPath']?.toString() ?? '';
    final name = path.basename(trashPath.isEmpty ? 'document' : trashPath);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Document Permanently?'),
        content: Text(
          '$name will be permanently deleted from this computer. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await widget.onDeletePermanently(entry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _entries.remove(entry);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Document permanently deleted.' : 'Could not delete document.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          const Expanded(child: Text('Document Trash')),
          Text(
            '${_entries.length} ${_entries.length == 1 ? 'document' : 'documents'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
      content: SizedBox(
        width: 950,
        height: 600,
        child: _entries.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline, size: 52),
                    SizedBox(height: 10),
                    Text('Document Trash is empty.'),
                  ],
                ),
              )
            : ListView.separated(
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final trashPath = entry['trashPath']?.toString() ?? '';
                  final originalPath = entry['originalPath']?.toString() ?? '';
                  final title = entry['title']?.toString().trim();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _DocumentThumbnail(filePath: trashPath),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title == null || title.isEmpty
                                    ? path.basename(trashPath)
                                    : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Tooltip(
                                message: originalPath,
                                child: Text(
                                  'Original: $originalPath',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: _busy ? null : () => _restore(entry),
                              icon: const Icon(Icons.restore),
                              label: const Text('Restore'),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : () => _delete(entry),
                              icon: const Icon(Icons.delete_forever_outlined),
                              label: const Text('Delete Permanently'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DocumentBatchEditResult {
  final bool changeType;
  final String documentType;
  final bool changeDate;
  final String documentDate;
  final bool changePeople;
  final String people;
  final bool changeSource;
  final String source;
  final bool changeDescription;
  final String description;

  const _DocumentBatchEditResult({
    required this.changeType,
    required this.documentType,
    required this.changeDate,
    required this.documentDate,
    required this.changePeople,
    required this.people,
    required this.changeSource,
    required this.source,
    required this.changeDescription,
    required this.description,
  });
}

class _DocumentBatchEditDialog extends StatefulWidget {
  final int count;

  const _DocumentBatchEditDialog({required this.count});

  @override
  State<_DocumentBatchEditDialog> createState() =>
      _DocumentBatchEditDialogState();
}

class _DocumentBatchEditDialogState extends State<_DocumentBatchEditDialog> {
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  bool _changeType = false;
  bool _changeDate = false;
  bool _changePeople = false;
  bool _changeSource = false;
  bool _changeDescription = false;

  String _documentType = 'Other';
  final _date = TextEditingController();
  final _people = TextEditingController();
  final _source = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _date.dispose();
    _people.dispose();
    _source.dispose();
    _description.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: _gold.withValues(alpha: .35)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: _gold),
    ),
  );

  Widget _fieldToggle({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String label,
  }) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeColor: _gold,
      checkColor: const Color(0xFF071A2B),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        label,
        style: const TextStyle(color: _cream, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _panel,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Edit ${widget.count} Selected Document${widget.count == 1 ? '' : 's'}',
        style: const TextStyle(color: _cream),
      ),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Check only the fields you want to change. Unchecked fields stay exactly as they are. A checked field left blank will clear that field.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _fieldToggle(
                value: _changeType,
                onChanged: (v) => setState(() => _changeType = v ?? false),
                label: 'Document Type',
              ),
              if (_changeType)
                DropdownButtonFormField<String>(
                  initialValue: _documentType,
                  dropdownColor: _panel,
                  style: const TextStyle(color: _cream),
                  decoration: _decoration('Document Type'),
                  items:
                      const [
                            'Letter',
                            'Certificate',
                            'Record',
                            'Newspaper',
                            'Legal',
                            'Military',
                            'School',
                            'Church',
                            'Photo / Scan',
                            'Other',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _documentType = value);
                    }
                  },
                ),
              _fieldToggle(
                value: _changeDate,
                onChanged: (v) => setState(() => _changeDate = v ?? false),
                label: 'Date',
              ),
              if (_changeDate)
                TextField(
                  controller: _date,
                  style: const TextStyle(color: _cream),
                  decoration: _decoration('Date'),
                ),
              _fieldToggle(
                value: _changePeople,
                onChanged: (v) => setState(() => _changePeople = v ?? false),
                label: 'People',
              ),
              if (_changePeople)
                TextField(
                  controller: _people,
                  style: const TextStyle(color: _cream),
                  decoration: _decoration('People'),
                ),
              _fieldToggle(
                value: _changeSource,
                onChanged: (v) => setState(() => _changeSource = v ?? false),
                label: 'Source / Provenance',
              ),
              if (_changeSource)
                TextField(
                  controller: _source,
                  style: const TextStyle(color: _cream),
                  decoration: _decoration('Source / Provenance'),
                ),
              _fieldToggle(
                value: _changeDescription,
                onChanged: (v) =>
                    setState(() => _changeDescription = v ?? false),
                label: 'Description / Notes',
              ),
              if (_changeDescription)
                TextField(
                  controller: _description,
                  maxLines: 4,
                  style: const TextStyle(color: _cream),
                  decoration: _decoration('Description / Notes'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            final hasChange =
                _changeType ||
                _changeDate ||
                _changePeople ||
                _changeSource ||
                _changeDescription;
            if (!hasChange) return;
            Navigator.pop(
              context,
              _DocumentBatchEditResult(
                changeType: _changeType,
                documentType: _documentType,
                changeDate: _changeDate,
                documentDate: _date.text.trim(),
                changePeople: _changePeople,
                people: _people.text.trim(),
                changeSource: _changeSource,
                source: _source.text.trim(),
                changeDescription: _changeDescription,
                description: _description.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Apply Changes'),
        ),
      ],
    );
  }
}

class _EmptyDocuments extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyDocuments({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFC9A65A);
    const cream = Color(0xFFF3E9D1);
    const muted = Color(0xFFAAB8C2);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, color: gold, size: 52),
          const SizedBox(height: 14),
          const Text(
            'No documents cataloged yet',
            style: TextStyle(
              color: cream,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add a PDF, Word document, image, or scan.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Document'),
          ),
        ],
      ),
    );
  }
}
