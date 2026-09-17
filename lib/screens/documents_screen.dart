import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../models/document_record.dart';

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
        const SnackBar(content: Text('The selected document could not be found.')),
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

  Future<void> _showDocumentEditor({
    DocumentRecord? document,
    String? initialFilePath,
  }) async {
    final filePath = initialFilePath ?? document?.filePath ?? '';
    final initialTitle = document?.title.trim().isNotEmpty == true
        ? document!.title
        : path.basenameWithoutExtension(filePath);

    final titleController = TextEditingController(text: initialTitle);
    final dateController = TextEditingController(text: document?.documentDate ?? '');
    final peopleController = TextEditingController(text: document?.people ?? '');
    final descriptionController = TextEditingController(text: document?.description ?? '');
    final sourceController = TextEditingController(text: document?.source ?? '');
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
                              items: const [
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
                      TextField(
                        controller: peopleController,
                        style: const TextStyle(color: _cream),
                        decoration: _inputDecoration('People'),
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
        const SnackBar(content: Text('No file location is saved for this document.')),
      );
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The document file could not be found:\n$filePath')),
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
          const SnackBar(content: Text('Windows could not open this document.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open document: $error')),
      );
    }
  }

  Future<void> _deleteDocument(DocumentRecord document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Document?'),
        content: Text(
          'Remove "${document.title}" from Heirloom Atlas?\n\n'
          'The original file will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _databaseHelper.deleteDocument(document.id!);
    await _loadDocuments();
  }

  String _guessDocumentType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.tif', '.tiff', '.heic'].contains(extension)) {
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
      if (query.isEmpty) return true;
      return document.title.toLowerCase().contains(query) ||
          document.people.toLowerCase().contains(query) ||
          document.description.toLowerCase().contains(query) ||
          document.source.toLowerCase().contains(query) ||
          document.filePath.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final documents = _filteredDocuments;
    final types = <String>{
      'All',
      ..._documents
          .map((document) => document.documentType)
          .where((value) => value.trim().isNotEmpty),
    }.toList();

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Documents',
          style: TextStyle(color: _cream, fontWeight: FontWeight.w800),
        ),
        actions: [
          FilledButton.icon(
            onPressed: _pickAndAddDocument,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('ADD DOCUMENT'),
          ),
          const SizedBox(width: 18),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _panel.withValues(alpha: .88),
                border: Border.all(color: _gold.withValues(alpha: .28)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.description_outlined, color: _gold, size: 38),
                  SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Family Document Archive',
                          style: TextStyle(
                            color: _cream,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Catalog letters, certificates, records, scans, PDFs, and family papers without moving the originals.',
                          style: TextStyle(color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(color: _cream),
                    decoration: InputDecoration(
                      hintText: 'Search documents, people, notes, or sources...',
                      hintStyle: const TextStyle(color: _muted),
                      prefixIcon: const Icon(Icons.search, color: _gold),
                      filled: true,
                      fillColor: _panel.withValues(alpha: .72),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: _gold.withValues(alpha: .25)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: types.contains(_typeFilter) ? _typeFilter : 'All',
                    dropdownColor: _panel,
                    style: const TextStyle(color: _cream),
                    decoration: _inputDecoration('Type'),
                    items: types
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _typeFilter = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : documents.isEmpty
                      ? _EmptyDocuments(onAdd: _pickAndAddDocument)
                      : ListView.separated(
                          itemCount: documents.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final document = documents[index];
                            return _DocumentCard(
                              document: document,
                              onOpen: () => _openDocument(document),
                              onEdit: () => _showDocumentEditor(document: document),
                              onDelete: document.id == null
                                  ? null
                                  : () => _deleteDocument(document),
                            );
                          },
                        ),
            ),
          ],
        ),
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
                style: const TextStyle(color: cream, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(filePath, style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentRecord document;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _DocumentCard({
    required this.document,
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
      color: panel.withValues(alpha: .84),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: gold.withValues(alpha: .22)),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.description_outlined, color: gold, size: 32),
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
                      Text(detailParts.join('  •  '), style: const TextStyle(color: muted)),
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
                  tooltip: 'Remove from archive',
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
            style: TextStyle(color: cream, fontWeight: FontWeight.w900, fontSize: 18),
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
