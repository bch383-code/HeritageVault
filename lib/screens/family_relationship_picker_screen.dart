import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';
import 'family_person_edit_screen.dart';

class FamilyRelationshipPickerScreen extends StatefulWidget {
  final FamilyPerson currentPerson;
  final String relationshipType;

  const FamilyRelationshipPickerScreen({
    super.key,
    required this.currentPerson,
    required this.relationshipType,
  });

  @override
  State<FamilyRelationshipPickerScreen> createState() =>
      _FamilyRelationshipPickerScreenState();
}

class _FamilyRelationshipPickerScreenState
    extends State<FamilyRelationshipPickerScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  List<FamilyPerson> _people = const [];
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

    final currentId = widget.currentPerson.id;

    if (!mounted) return;

    setState(() {
      _people = people
          .where((person) => person.id != null && person.id != currentId)
          .toList();
      _loading = false;
    });
  }

  Future<void> _createNew() async {
    final result = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => const FamilyPersonEditScreen(),
      ),
    );

    if (result == null) return;

    final person = await _databaseHelper.getFamilyPerson(result);

    if (!mounted || person == null) return;

    Navigator.pop(context, person);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Choose ${widget.relationshipType}'),
        actions: [
          TextButton.icon(
            onPressed: _createNew,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Create New Person'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search people',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _people.isEmpty
                    ? const Center(
                        child: Text('No matching people found.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _people.length,
                        itemBuilder: (context, index) {
                          final person = _people[index];

                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_outline),
                              ),
                              title: Text(
                                person.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (person.lifeSpan.isNotEmpty)
                                    person.lifeSpan,
                                  if (person.birthPlace.isNotEmpty)
                                    person.birthPlace,
                                ].join(' • '),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.pop(
                                context,
                                person,
                              ),
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
