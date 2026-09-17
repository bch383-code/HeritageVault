import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_edit_screen.dart';
import 'family_person_screen.dart';
import 'family_relationship_finder_screen.dart';
import 'family_fan_chart_screen.dart';
import 'gedcom_import_screen.dart';
import 'family_visual_tree_screen.dart';

class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({super.key});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<FamilyPerson> _people = [];
  final Map<int, int> _personViewCounts = <int, int>{};
  final Map<int, DateTime> _personLastViewed = <int, DateTime>{};
  bool _loading = true;
  bool _searchFocused = false;

  static const Color _heritageGold = Color(0xFFC9A65A);
  static const Color _heritageCream = Color(0xFFF3E9D1);
  static const Color _panelNavy = Color(0xFF081E33);

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocus);
    _initializeFamilyTreeScreen();
  }

  Future<void> _initializeFamilyTreeScreen() async {
    await _loadFrequentPeople();
    await _load();
  }

  Future<void> _loadFrequentPeople() async {
    try {
      final raw = await _databaseHelper.getSetting('family_frequent_people');
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final counts = decoded['counts'];
      final lastViewed = decoded['lastViewed'];

      if (!mounted) return;
      setState(() {
        _personViewCounts.clear();
        _personLastViewed.clear();

        if (counts is Map) {
          for (final entry in counts.entries) {
            final id = int.tryParse(entry.key.toString());
            final count = int.tryParse(entry.value.toString());
            if (id != null && count != null && count > 0) {
              _personViewCounts[id] = count;
            }
          }
        }

        if (lastViewed is Map) {
          for (final entry in lastViewed.entries) {
            final id = int.tryParse(entry.key.toString());
            final millis = int.tryParse(entry.value.toString());
            if (id != null && millis != null) {
              _personLastViewed[id] =
                  DateTime.fromMillisecondsSinceEpoch(millis);
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _saveFrequentPeople() async {
    final payload = jsonEncode({
      'counts': {
        for (final entry in _personViewCounts.entries)
          entry.key.toString(): entry.value,
      },
      'lastViewed': {
        for (final entry in _personLastViewed.entries)
          entry.key.toString(): entry.value.millisecondsSinceEpoch,
      },
    });

    await _databaseHelper.setSetting('family_frequent_people', payload);
  }

  void _handleSearchFocus() {
    if (!mounted) return;
    setState(() => _searchFocused = _searchFocusNode.hasFocus);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocus);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final people = await _databaseHelper.getFamilyPeople(
      searchText: _searchController.text,
    );

    if (!mounted) return;

    setState(() {
      _people = people;
      _loading = false;
    });
  }

  Future<void> _addPerson() async {
    final result = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const FamilyPersonEditScreen()),
    );

    if (result != null) {
      await _load();
    }
  }

  Future<void> _openPerson(FamilyPerson person) async {
    final id = person.id;
    if (id != null) {
      setState(() {
        _personViewCounts[id] = (_personViewCounts[id] ?? 0) + 1;
        _personLastViewed[id] = DateTime.now();
      });
      await _saveFrequentPeople();
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FamilyPersonScreen(person: person)),
    );

    await _load();
  }

  Future<void> _importGedcom() async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const GedcomImportScreen(),
      ),
    );

    if (imported == true) {
      await _load();
    }
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
                        ? const Center(child: CircularProgressIndicator())
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
                                      child: Icon(Icons.person_outline),
                                    ),
                                    title: Text(candidate.displayName),
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
        builder: (_) => FamilyVisualTreeScreen(initialPerson: person),
      ),
    );

    await _load();
  }


  Future<FamilyPerson?> _chooseGenealogyPerson(String title) async {
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
            final matches =
                await _databaseHelper.getFamilyPeople(searchText: query);
            if (!dialogContext.mounted) return;
            setDialogState(() {
              results = matches.take(75).toList();
              searching = false;
            });
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 620,
              height: 500,
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
                        ? const Center(child: CircularProgressIndicator())
                        : results.isEmpty
                            ? const Center(
                                child: Text('Search for a starting person.'),
                              )
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (context, index) {
                                  final candidate = results[index];
                                  return ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.person_outline),
                                    ),
                                    title: Text(candidate.displayName),
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
    return person;
  }

  Future<void> _openRelationships() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FamilyRelationshipFinderScreen(),
      ),
    );
    await _load();
  }

  Future<void> _openFanChart() async {
    final person = await _chooseGenealogyPerson('Choose Fan Chart Person');
    if (person == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyFanChartScreen(initialPerson: person),
      ),
    );
    await _load();
  }

  Future<void> _exportGedcom() async {
    if (_people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no Family Tree people to export.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export GEDCOM'),
        content: Text(
          'Export the entire Family Tree (${_people.length} '
          '${_people.length == 1 ? 'person' : 'people'}) as a standard GEDCOM file?\n\n'
          'The export includes people, birth/death details, notes, and family relationships.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Export'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final people = await _databaseHelper.getFamilyPeople();
      final peopleById = <int, FamilyPerson>{
        for (final person in people)
          if (person.id != null) person.id!: person,
      };

      String clean(String value) => value
          .replaceAll('\r\n', ' ')
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ')
          .trim();

      String xref(int id) => '@I$id@';
      String familyXref(int number) => '@F$number@';

      final familyGroups = <String, _GedcomExportFamily>{};

      // Build families from each child's recorded parents. This preserves
      // parent/child relationships even when only one parent is known.
      for (final child in people) {
        final childId = child.id;
        if (childId == null) continue;

        final parents = await _databaseHelper.getFamilyParents(childId);
        final parentIds = parents
            .map((person) => person.id)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();

        if (parentIds.isEmpty) continue;

        final key = parentIds.join(':');
        final family = familyGroups.putIfAbsent(
          key,
          () => _GedcomExportFamily(parentIds: parentIds),
        );
        family.childIds.add(childId);
      }

      // Also preserve spouse relationships that do not have children.
      for (final person in people) {
        final personId = person.id;
        if (personId == null) continue;

        final spouses = await _databaseHelper.getFamilySpouses(personId);
        for (final spouse in spouses) {
          final spouseId = spouse.id;
          if (spouseId == null || spouseId == personId) continue;
          final pair = [personId, spouseId]..sort();
          final key = pair.join(':');
          familyGroups.putIfAbsent(
            key,
            () => _GedcomExportFamily(parentIds: pair),
          );
        }
      }

      final families = familyGroups.values.toList();
      final familyIdsByPerson = <int, List<int>>{};
      final childFamilyByPerson = <int, int>{};

      for (var index = 0; index < families.length; index++) {
        final familyNumber = index + 1;
        final family = families[index];

        for (final parentId in family.parentIds) {
          familyIdsByPerson.putIfAbsent(parentId, () => <int>[]).add(familyNumber);
        }
        for (final childId in family.childIds) {
          childFamilyByPerson[childId] = familyNumber;
        }
      }

      final lines = <String>[
        '0 HEAD',
        '1 SOUR Heirloom Atlas',
        '2 NAME Heirloom Atlas',
        '1 GEDC',
        '2 VERS 5.5.1',
        '2 FORM LINEAGE-LINKED',
        '1 CHAR UTF-8',
      ];

      for (final person in people) {
        final id = person.id;
        if (id == null) continue;

        final given = clean(
          [person.firstName, person.middleName]
              .where((part) => part.trim().isNotEmpty)
              .join(' '),
        );
        final surname = clean(person.lastName);

        lines.add('0 ${xref(id)} INDI');
        lines.add('1 NAME $given /$surname/');

        final sex = person.sex.trim().toLowerCase();
        if (sex == 'male' || sex == 'm') {
          lines.add('1 SEX M');
        } else if (sex == 'female' || sex == 'f') {
          lines.add('1 SEX F');
        } else if (sex.isNotEmpty) {
          lines.add('1 SEX U');
        }

        if (person.birthName.trim().isNotEmpty) {
          lines.add('1 _BIRTHNAME ${clean(person.birthName)}');
        }

        if (person.birthDate.trim().isNotEmpty ||
            person.birthPlace.trim().isNotEmpty) {
          lines.add('1 BIRT');
          if (person.birthDate.trim().isNotEmpty) {
            lines.add('2 DATE ${clean(person.birthDate)}');
          }
          if (person.birthPlace.trim().isNotEmpty) {
            lines.add('2 PLAC ${clean(person.birthPlace)}');
          }
        }

        if (person.deathDate.trim().isNotEmpty ||
            person.deathPlace.trim().isNotEmpty) {
          lines.add('1 DEAT');
          if (person.deathDate.trim().isNotEmpty) {
            lines.add('2 DATE ${clean(person.deathDate)}');
          }
          if (person.deathPlace.trim().isNotEmpty) {
            lines.add('2 PLAC ${clean(person.deathPlace)}');
          }
        }

        if (person.biography.trim().isNotEmpty) {
          lines.add('1 NOTE ${clean(person.biography)}');
        }
        if (person.notes.trim().isNotEmpty) {
          lines.add('1 NOTE ${clean(person.notes)}');
        }

        final childFamily = childFamilyByPerson[id];
        if (childFamily != null) {
          lines.add('1 FAMC ${familyXref(childFamily)}');
        }
        for (final familyNumber in familyIdsByPerson[id] ?? const <int>[]) {
          lines.add('1 FAMS ${familyXref(familyNumber)}');
        }
      }

      for (var index = 0; index < families.length; index++) {
        final familyNumber = index + 1;
        final family = families[index];
        lines.add('0 ${familyXref(familyNumber)} FAM');

        final parents = family.parentIds
            .map((id) => peopleById[id])
            .whereType<FamilyPerson>()
            .toList();

        FamilyPerson? husband;
        FamilyPerson? wife;
        final unassigned = <FamilyPerson>[];

        for (final parent in parents) {
          final sex = parent.sex.trim().toLowerCase();
          if (husband == null && (sex == 'male' || sex == 'm')) {
            husband = parent;
          } else if (wife == null && (sex == 'female' || sex == 'f')) {
            wife = parent;
          } else {
            unassigned.add(parent);
          }
        }

        for (final parent in unassigned) {
          husband ??= parent;
          if (husband != parent && wife == null) {
            wife = parent;
          }
        }

        if (husband?.id != null) lines.add('1 HUSB ${xref(husband!.id!)}');
        if (wife?.id != null) lines.add('1 WIFE ${xref(wife!.id!)}');

        for (final childId in family.childIds) {
          lines.add('1 CHIL ${xref(childId)}');
        }
      }

      lines.add('0 TRLR');

      final documents = await getApplicationDocumentsDirectory();
      final exportDirectory = Directory(
        '${documents.path}${Platform.pathSeparator}Heirloom Atlas'
        '${Platform.pathSeparator}Exports',
      );
      await exportDirectory.create(recursive: true);

      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final stamp =
          '${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final file = File(
        '${exportDirectory.path}${Platform.pathSeparator}'
        'Heirloom_Atlas_Family_Tree_$stamp.ged',
      );
      await file.writeAsString('${lines.join('\r\n')}\r\n', flush: true);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('GEDCOM Export Complete'),
          content: SizedBox(
            width: 650,
            child: SelectableText(
              'Exported ${people.length} people and ${families.length} '
              'family groups.\n\nSaved to:\n${file.path}',
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Process.start(
                  'explorer.exe',
                  ['/select,', file.path],
                  runInShell: true,
                );
              },
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Show in Folder'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GEDCOM export failed: $error')),
      );
    }
  }

  Future<void> _openTreeHealthTools() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tree Health & Backups'),
        content: const Text(
          'Choose a maintenance tool for your Family Tree.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, 'diagnostics'),
            child: const Text('Diagnostics'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, 'inspect'),
            child: const Text('Backup Inspector'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'backup'),
            child: const Text('Create Verified Backup'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case 'diagnostics':
        await _showDiagnostics();
        break;
      case 'inspect':
        await _showBackupInspector();
        break;
      case 'backup':
        await _createVerifiedBackup();
        break;
    }
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
                  if (backups.isNotEmpty) ...['', ...backups.take(10)],
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

  Widget _buildBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 210,
          width: double.infinity,
          decoration: BoxDecoration(
            color: _panelNavy,
            border: Border.all(
              color: _heritageGold.withValues(alpha: .42),
              width: .8,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/family_tree_decor/family_tree_banner.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: _panelNavy,
                    alignment: Alignment.center,
                    child: const Text(
                      'Family Tree banner image not found',
                      style: TextStyle(color: _heritageCream),
                    ),
                  );
                },
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF04111C).withValues(alpha: .22),
                      Colors.transparent,
                      const Color(0xFF04111C).withValues(alpha: .08),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _panelNavy.withValues(alpha: .92),
          border: Border.all(
            color: _heritageGold.withValues(alpha: .25),
            width: .8,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Text(
              '${_people.length} ${_people.length == 1 ? 'PERSON' : 'PEOPLE'}',
              style: TextStyle(
                color: _heritageCream.withValues(alpha: .82),
                fontSize: 11,
                letterSpacing: .8,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'FAMILY ARCHIVE',
              style: TextStyle(
                color: _heritageGold.withValues(alpha: .72),
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _importGedcom,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Import GEDCOM'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _addPerson,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add Person'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _genealogyToolButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF102A40),
          border: Border.all(
            color: _heritageGold.withValues(alpha: .22),
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Icon(icon, color: _heritageGold, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _heritageCream.withValues(alpha: .60),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: _heritageCream.withValues(alpha: .42),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenealogyToolsPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .94),
        border: Border.all(
          color: _heritageGold.withValues(alpha: .30),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hub_outlined, color: _heritageGold, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GENEALOGY TOOLS',
                    style: TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .9,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Explore your family across people, relationships, and generations.',
              style: TextStyle(
                color: _heritageCream.withValues(alpha: .60),
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'EXPLORE',
              style: TextStyle(
                color: _heritageGold.withValues(alpha: .78),
                fontSize: 10,
                letterSpacing: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            _genealogyToolButton(
              icon: Icons.account_tree_outlined,
              title: 'Tree View',
              subtitle: 'Browse connected ancestors and descendants.',
              onTap: _openVisualTree,
            ),
            const SizedBox(height: 8),
            _genealogyToolButton(
              icon: Icons.people_alt_outlined,
              title: 'Relationships',
              subtitle: 'Choose a person and review their family connections.',
              onTap: _openRelationships,
            ),
            const SizedBox(height: 8),
            _genealogyToolButton(
              icon: Icons.hub_outlined,
              title: 'Fan Chart',
              subtitle: 'Choose a person and explore their ancestry.',
              onTap: _openFanChart,
            ),
            const SizedBox(height: 18),
            Divider(
              height: 1,
              color: _heritageGold.withValues(alpha: .18),
            ),
            const SizedBox(height: 14),
            Text(
              'MANAGE',
              style: TextStyle(
                color: _heritageGold.withValues(alpha: .78),
                fontSize: 10,
                letterSpacing: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            _genealogyToolButton(
              icon: Icons.upload_file_outlined,
              title: 'Import GEDCOM',
              subtitle: 'Bring an existing genealogy file into Heirloom Atlas.',
              onTap: _importGedcom,
            ),
            const SizedBox(height: 8),
            _genealogyToolButton(
              icon: Icons.download_outlined,
              title: 'Export GEDCOM',
              subtitle: 'Save your Family Tree as a portable GEDCOM file.',
              onTap: _exportGedcom,
            ),
            const SizedBox(height: 8),
            _genealogyToolButton(
              icon: Icons.health_and_safety_outlined,
              title: 'Tree Health & Backups',
              subtitle: 'Review diagnostics and safeguard your family tree.',
              onTap: _openTreeHealthTools,
            ),
          ],
        ),
      ),
    );
  }

  List<FamilyPerson> _frequentlyViewedPeople() {
    final ranked = _people.where((person) {
      final id = person.id;
      return id != null && (_personViewCounts[id] ?? 0) > 0;
    }).toList();

    ranked.sort((a, b) {
      final aId = a.id!;
      final bId = b.id!;
      final countCompare =
          (_personViewCounts[bId] ?? 0).compareTo(_personViewCounts[aId] ?? 0);
      if (countCompare != 0) return countCompare;

      final aTime =
          _personLastViewed[aId] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          _personLastViewed[bId] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return ranked.take(5).toList();
  }

  Widget _buildFrequentPeople() {
    final frequent = _frequentlyViewedPeople();
    if (frequent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Text(
          'Frequently viewed people will appear here as you use the Family Tree.',
          style: TextStyle(
            color: _heritageCream.withValues(alpha: .58),
            fontSize: 11,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(11, 0, 11, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF102A40),
        border: Border.all(color: _heritageGold.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 5),
            child: Text(
              'FREQUENTLY VIEWED',
              style: TextStyle(
                color: _heritageGold.withValues(alpha: .82),
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final person in frequent)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.history_outlined,
                color: _heritageGold,
                size: 18,
              ),
              title: Text(
                person.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _heritageCream,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: person.lifeSpan.isEmpty
                  ? null
                  : Text(
                      person.lifeSpan,
                      style: TextStyle(
                        color: _heritageCream.withValues(alpha: .58),
                        fontSize: 11,
                      ),
                    ),
              onTap: () {
                _searchFocusNode.unfocus();
                _openPerson(person);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPeoplePanel() {
    return Container(
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .94),
        border: Border.all(
          color: _heritageGold.withValues(alpha: .30),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.people_outline,
                  color: _heritageGold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'FAMILY PEOPLE',
                    style: TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .9,
                    ),
                  ),
                ),
                Text(
                  '${_people.length}',
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .58),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: _heritageGold.withValues(alpha: .20),
          ),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (_) {
                      setState(() {});
                      _load();
                    },
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name, place, or family detail...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                      _load();
                      _searchFocusNode.requestFocus();
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ),
          if (_searchFocused && _searchController.text.trim().isEmpty)
            _buildFrequentPeople(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _people.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.family_restroom_outlined,
                                size: 42,
                                color: _heritageGold.withValues(alpha: .72),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchController.text.trim().isEmpty
                                    ? 'Your family archive is ready for its first person.'
                                    : 'No people match this search.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _heritageCream.withValues(alpha: .72),
                                ),
                              ),
                              if (_searchController.text.trim().isEmpty) ...[
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: _addPerson,
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: const Text('Add First Person'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(9, 0, 9, 10),
                        itemCount: _people.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: _heritageGold.withValues(alpha: .12),
                        ),
                        itemBuilder: (context, index) {
                          final person = _people[index];
                          final photoPath = person.profilePhotoPath;
                          final hasPhoto = photoPath.isNotEmpty &&
                              File(photoPath).existsSync();

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundImage: hasPhoto
                                  ? FileImage(File(photoPath))
                                  : null,
                              child: hasPhoto
                                  ? null
                                  : const Icon(
                                      Icons.person_outline,
                                      size: 18,
                                    ),
                            ),
                            title: Text(
                              person.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                person.lifeSpan,
                                person.birthPlace,
                              ].where((value) => value.isNotEmpty).join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              size: 18,
                            ),
                            onTap: () => _openPerson(person),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildBanner(),
          _buildActionBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 820) {
                    return Column(
                      children: [
                        SizedBox(
                          height: 330,
                          child: _buildGenealogyToolsPanel(),
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: _buildPeoplePanel()),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 1,
                        child: _buildGenealogyToolsPanel(),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: _buildPeoplePanel(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _GedcomExportFamily {
  final List<int> parentIds;
  final Set<int> childIds = <int>{};

  _GedcomExportFamily({required this.parentIds});
}
