import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_edit_screen.dart';
import 'family_person_screen.dart';
import 'gedcom_import_screen.dart';

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
