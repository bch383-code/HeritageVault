import 'dart:io';

import 'package:flutter/material.dart';

import '../../../database/database_helper.dart';
import '../../../models/family_person.dart';

class FamilyPeoplePickerDialog extends StatefulWidget {
  final Set<int> initiallySelectedIds;

  const FamilyPeoplePickerDialog({
    super.key,
    required this.initiallySelectedIds,
  });

  @override
  State<FamilyPeoplePickerDialog> createState() =>
      _FamilyPeoplePickerDialogState();
}

class _FamilyPeoplePickerDialogState
    extends State<FamilyPeoplePickerDialog> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  List<FamilyPerson> _people = [];
  late Set<int> _selectedIds;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initiallySelectedIds};
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

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

  void _toggle(FamilyPerson person, bool selected) {
    final id = person.id;

    if (id == null) {
      return;
    }

    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose People'),
      content: SizedBox(
        width: 720,
        height: 620,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search family tree',
                hintText: 'Name, birth name, or place',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selectedIds.length} '
                '${_selectedIds.length == 1 ? 'person' : 'people'} selected',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _people.isEmpty
                      ? const Center(
                          child: Text('No matching people found.'),
                        )
                      : ListView.separated(
                          itemCount: _people.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final person = _people[index];
                            final id = person.id;
                            final path = person.profilePhotoPath;
                            final hasPhoto =
                                path.isNotEmpty && File(path).existsSync();

                            if (id == null) {
                              return const SizedBox.shrink();
                            }

                            return CheckboxListTile(
                              value: _selectedIds.contains(id),
                              onChanged: (value) =>
                                  _toggle(person, value ?? false),
                              secondary: CircleAvatar(
                                backgroundImage:
                                    hasPhoto ? FileImage(File(path)) : null,
                                child: hasPhoto
                                    ? null
                                    : const Icon(Icons.person_outline),
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
                              controlAffinity:
                                  ListTileControlAffinity.trailing,
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
          onPressed: () {
            Navigator.pop(context, _selectedIds);
          },
          icon: const Icon(Icons.check),
          label: Text(
            _selectedIds.isEmpty
                ? 'Save Selection'
                : 'Add ${_selectedIds.length} to Book',
          ),
        ),
      ],
    );
  }
}
