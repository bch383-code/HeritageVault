import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_edit_screen.dart';
import 'family_person_screen.dart';
import 'gedcom_import_screen.dart';
import 'family_visual_tree_screen.dart';

class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({super.key});

  @override
  State<FamilyTreeScreen> createState() =>
      _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController =
      TextEditingController();

  List<FamilyPerson> _people = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final people = await _databaseHelper.getFamilyPeople(
      searchText: _searchController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _people = people;
      _loading = false;
    });
  }

  Future<void> _addPerson() async {
    final result = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => const FamilyPersonEditScreen(),
      ),
    );

    if (result != null) {
      await _load();
    }
  }

  Future<void> _openPerson(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyPersonScreen(
          person: person,
        ),
      ),
    );

    await _load();
  }

  Future<void> _openVisualTree() async {
    final searchController = TextEditingController();
    List<FamilyPerson> results = const [];
    bool searching = false;

    final person = await showDialog<FamilyPerson>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> search(String value) async {
            final query = value.trim();

            if (query.length < 2) {
              setDialogState(() {
                results = const [];
                searching = false;
              });
              return;
            }

            setDialogState(() => searching = true);

            final matches = await _databaseHelper.getFamilyPeople(
              searchText: query,
            );

            if (!dialogContext.mounted) return;

            setDialogState(() {
              results = matches.take(75).toList();
              searching = false;
            });
          }

          return AlertDialog(
            title: const Text('Choose Starting Person'),
            content: SizedBox(
              width: 620,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search family tree',
                      hintText: 'Type at least 2 letters',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: searching
                        ? const Center(
                            child: CircularProgressIndicator(),
                          )
                        : results.isEmpty
                            ? const Center(
                                child: Text(
                                  'Search for the person you want '
                                  'to center the tree on.',
                                ),
                              )
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (context, index) {
                                  final candidate = results[index];

                                  return ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(
                                        Icons.person_outline,
                                      ),
                                    ),
                                    title: Text(
                                      candidate.displayName,
                                    ),
                                    subtitle: Text(
                                      [
                                        if (candidate.lifeSpan.isNotEmpty)
                                          candidate.lifeSpan,
                                        if (candidate.birthPlace.isNotEmpty)
                                          candidate.birthPlace,
                                      ].join(' • '),
                                    ),
                                    onTap: () => Navigator.pop(
                                      dialogContext,
                                      candidate,
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );

    searchController.dispose();

    if (person == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyVisualTreeScreen(
          initialPerson: person,
        ),
      ),
    );

    await _load();
  }

  Future<void> _showDiagnostics() async {
    try {
      final diagnostics = await _databaseHelper.getFamilyDiagnostics();
      if (!mounted) return;

      final backups =
          (diagnostics['backup_paths'] as List?)?.cast<String>() ?? const [];

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Family Tree Diagnostics'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: SelectableText(
                [
                  'Database:',
                  diagnostics['database_path']?.toString() ?? '',
                  '',
                  'People: ${diagnostics['family_people']}',
                  'Parent/child links: ${diagnostics['parent_child_links']}',
                  'Spouse links: ${diagnostics['spouse_links']}',
                  'GEDCOM import records: ${diagnostics['gedcom_imports']}',
                  'GEDCOM person links: ${diagnostics['gedcom_person_links']}',
                  '',
                  'Database backups found: ${backups.length}',
                  if (backups.isNotEmpty) ...[
                    '',
                    ...backups.take(10),
                  ],
                ].join('\n'),
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Diagnostics failed: $error')),
      );
    }
  }



  Future<void> _showBackupInspector() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Inspecting Backups'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Text('Reading all backup databases...'),
          ],
        ),
      ),
    );

    try {
      final backups = await _databaseHelper.inspectDatabaseBackups();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Backup Inspector — ${backups.length} backups'),
          content: SizedBox(
            width: 1050,
            height: 650,
            child: backups.isEmpty
                ? const Center(child: Text('No backups found.'))
                : ListView.separated(
                    itemCount: backups.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = backups[index];
                      final dt = DateTime.fromMillisecondsSinceEpoch(
                        item['modified'] as int? ?? 0,
                      );
                      String two(int n) => n.toString().padLeft(2, '0');
                      final date =
                          '${dt.year}-${two(dt.month)}-${two(dt.day)} '
                          '${two(dt.hour)}:${two(dt.minute)}';
                      final people = item['people'] as int? ?? 0;
                      final pc = item['parent_child'] as int? ?? 0;
                      final spouses = item['spouses'] as int? ?? 0;
                      final links = item['gedcom_links'] as int? ?? 0;
                      final error = item['error']?.toString() ?? '';

                      return ListTile(
                        leading: Icon(
                          error.isNotEmpty
                              ? Icons.error_outline
                              : people > 0
                                  ? Icons.check_circle_outline
                                  : Icons.remove_circle_outline,
                        ),
                        title: Text(
                          item['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: people > 0
                                ? FontWeight.w800
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          error.isNotEmpty
                              ? 'Inspection error: $error'
                              : '$date\nPeople: $people  •  '
                                  'Parent/child: $pc  •  Spouses: $spouses  •  '
                                  'GEDCOM links: $links',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup inspection failed: $error')),
      );
    }
  }


  Future<void> _createVerifiedBackup() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Creating Verified Backup'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Text('Saving and verifying the Family Tree...'),
          ],
        ),
      ),
    );

    try {
      final result = await _databaseHelper.createVerifiedFamilyBackup(
        label: 'after_gedcom_import',
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final backup =
          (result['backup'] as Map?)?.cast<String, Object?>() ?? const {};
      final verified = result['verified'] == true;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            verified ? 'Backup Verified' : 'Backup Verification Failed',
          ),
          content: SelectableText(
            [
              'Backup:',
              result['path']?.toString() ?? '',
              '',
              'People: ${backup['family_people']}',
              'Parent/child links: ${backup['parent_child_links']}',
              'Spouse links: ${backup['spouse_links']}',
              'GEDCOM person links: ${backup['gedcom_person_links']}',
              '',
              verified
                  ? 'VERIFIED — this backup matches the live Family Tree.'
                  : 'FAILED — do not rely on this backup.',
            ].join('\n'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $error')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              28,
              26,
              28,
              18,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Family Tree',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        '${_people.length} '
                        '${_people.length == 1 ? 'person' : 'people'} '
                        'in your family archive',
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showDiagnostics,
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Diagnostics'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _showBackupInspector,
                  icon: const Icon(Icons.manage_search_outlined),
                  label: const Text('Backup Inspector'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _createVerifiedBackup,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Create Backup'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _openVisualTree,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Tree View'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final imported = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GedcomImportScreen(),
                      ),
                    );

                    if (imported == true) {
                      await _load();
                    }
                  },
                  icon: const Icon(
                    Icons.upload_file_outlined,
                  ),
                  label: const Text('Import GEDCOM'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _addPerson,
                  icon: const Icon(
                    Icons.person_add_alt_1_outlined,
                  ),
                  label: const Text('Add Person'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search people',
                hintText: 'Name, birth name, or place',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _people.isEmpty
                    ? Center(
                        child: FilledButton.icon(
                          onPressed: _addPerson,
                          icon: const Icon(
                            Icons.person_add_alt_1_outlined,
                          ),
                          label: const Text(
                            'Add First Person',
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          28,
                          0,
                          28,
                          28,
                        ),
                        itemCount: _people.length,
                        separatorBuilder: (_, _) {
                          return const SizedBox(height: 8);
                        },
                        itemBuilder: (context, index) {
                          final person = _people[index];
                          final path =
                              person.profilePhotoPath;
                          final hasPhoto =
                              path.isNotEmpty &&
                              File(path).existsSync();

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: hasPhoto
                                    ? FileImage(File(path))
                                    : null,
                                child: hasPhoto
                                    ? null
                                    : const Icon(
                                        Icons.person_outline,
                                      ),
                              ),
                              title: Text(
                                person.displayName,
                                style: const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  person.lifeSpan,
                                  person.birthPlace,
                                ]
                                    .where(
                                      (value) =>
                                          value.isNotEmpty,
                                    )
                                    .join(' • '),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                              ),
                              onTap: () {
                                _openPerson(person);
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
