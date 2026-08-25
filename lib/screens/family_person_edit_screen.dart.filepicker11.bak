import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/family_person.dart';

class FamilyPersonEditScreen extends StatefulWidget {
  final FamilyPerson? person;

  const FamilyPersonEditScreen({
    super.key,
    this.person,
  });

  @override
  State<FamilyPersonEditScreen> createState() =>
      _FamilyPersonEditScreenState();
}

class _FamilyPersonEditScreenState extends State<FamilyPersonEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  late final List<TextEditingController> _controllers;
  String _sex = '';
  String _photoPath = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final person = widget.person;
    _controllers = [
      person?.firstName,
      person?.middleName,
      person?.lastName,
      person?.birthName,
      person?.birthDate,
      person?.birthPlace,
      person?.deathDate,
      person?.deathPlace,
      person?.biography,
      person?.notes,
    ].map((value) {
      return TextEditingController(text: value ?? '');
    }).toList();

    _sex = person?.sex ?? '';
    _photoPath = person?.profilePhotoPath ?? '';
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(
    int index,
    String label, {
    bool required = false,
    int lines = 1,
  }) {
    return TextFormField(
      controller: _controllers[index],
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Required';
              }
              return null;
            }
          : null,
    );
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    final pickedPath = result?.files.single.path;

    if (pickedPath != null && mounted) {
      setState(() => _photoPath = pickedPath);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = widget.person;

    final person = FamilyPerson(
      id: existing?.id,
      firstName: _controllers[0].text.trim(),
      middleName: _controllers[1].text.trim(),
      lastName: _controllers[2].text.trim(),
      birthName: _controllers[3].text.trim(),
      sex: _sex,
      birthDate: _controllers[4].text.trim(),
      birthPlace: _controllers[5].text.trim(),
      deathDate: _controllers[6].text.trim(),
      deathPlace: _controllers[7].text.trim(),
      biography: _controllers[8].text.trim(),
      notes: _controllers[9].text.trim(),
      profilePhotoPath: _photoPath,
      createdAtMilliseconds:
          existing == null || existing.createdAtMilliseconds == 0
              ? now
              : existing.createdAtMilliseconds,
      updatedAtMilliseconds: now,
    );

    final result = existing?.id == null
        ? await _databaseHelper.insertFamilyPerson(person)
        : await _databaseHelper.updateFamilyPerson(person);

    if (!mounted) {
      return;
    }

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        _photoPath.isNotEmpty && File(_photoPath).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.person == null ? 'Add Person' : 'Edit Person',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundImage:
                        hasPhoto ? FileImage(File(_photoPath)) : null,
                    child: hasPhoto
                        ? null
                        : const Icon(
                            Icons.person_outline,
                            size: 50,
                          ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_outlined),
                    label: Text(
                      _photoPath.isEmpty
                          ? 'Choose Profile Photo'
                          : 'Change Profile Photo',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _field(
                    0,
                    'First name',
                    required: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(1, 'Middle name'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    2,
                    'Last name',
                    required: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(3, 'Birth / maiden name'),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _sex,
              decoration: const InputDecoration(
                labelText: 'Sex',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: '',
                  child: Text('Not specified'),
                ),
                DropdownMenuItem(
                  value: 'Female',
                  child: Text('Female'),
                ),
                DropdownMenuItem(
                  value: 'Male',
                  child: Text('Male'),
                ),
                DropdownMenuItem(
                  value: 'Unknown',
                  child: Text('Unknown'),
                ),
              ],
              onChanged: (value) {
                setState(() => _sex = value ?? '');
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _field(4, 'Birth date'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(5, 'Birth place'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _field(6, 'Death date'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(7, 'Death place'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _field(
              8,
              'Biography',
              lines: 5,
            ),
            const SizedBox(height: 10),
            _field(
              9,
              'Research notes',
              lines: 4,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                _saving ? 'Saving...' : 'Save Person',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
