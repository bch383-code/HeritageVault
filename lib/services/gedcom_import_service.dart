import 'dart:io';

import 'package:path/path.dart' as path;

import '../database/database_helper.dart';
import '../models/family_person.dart';

enum GedcomImportMode { fullImport, repairRelationships }

class GedcomPreview {
  final String filePath;
  final String importKey;
  final int individualCount;
  final int familyCount;
  final int parentChildLinks;
  final int spouseLinks;

  const GedcomPreview({
    required this.filePath,
    required this.importKey,
    required this.individualCount,
    required this.familyCount,
    required this.parentChildLinks,
    required this.spouseLinks,
  });
}

class GedcomImportProgress {
  final String stage;
  final int completed;
  final int total;
  final String message;

  const GedcomImportProgress({
    required this.stage,
    required this.completed,
    required this.total,
    required this.message,
  });

  double get fraction => total <= 0 ? 0 : completed / total;
}

class GedcomImportResult {
  final int peopleCreated;
  final int peopleMatched;
  final int linkedXrefs;
  final int parentChildLinksWritten;
  final int spouseLinksWritten;
  final int unresolvedIndividuals;

  const GedcomImportResult({
    required this.peopleCreated,
    required this.peopleMatched,
    required this.linkedXrefs,
    required this.parentChildLinksWritten,
    required this.spouseLinksWritten,
    required this.unresolvedIndividuals,
  });
}

class _Individual {
  final String xref;
  String name = '';
  String given = '';
  String surname = '';
  String sex = '';
  String birthDate = '';
  String birthPlace = '';
  String deathDate = '';
  String deathPlace = '';

  _Individual(this.xref);

  FamilyPerson toPerson() {
    var first = given.trim();
    var middle = '';
    var last = surname.trim();

    if (first.isEmpty && last.isEmpty) {
      final cleaned = name.replaceAll('/', '').trim();
      final parts = cleaned.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) first = parts.first;
      if (parts.length > 1) last = parts.last;
      if (parts.length > 2) middle = parts.sublist(1, parts.length - 1).join(' ');
    } else {
      final givenParts = first.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (givenParts.isNotEmpty) {
        first = givenParts.first;
        if (givenParts.length > 1) middle = givenParts.sublist(1).join(' ');
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    return FamilyPerson(
      firstName: first,
      middleName: middle,
      lastName: last,
      sex: sex == 'M' ? 'Male' : sex == 'F' ? 'Female' : '',
      birthDate: birthDate,
      birthPlace: birthPlace,
      deathDate: deathDate,
      deathPlace: deathPlace,
      createdAtMilliseconds: now,
      updatedAtMilliseconds: now,
    );
  }
}

class _Family {
  String? husband;
  String? wife;
  final List<String> children = [];
}

class _Parsed {
  final Map<String, _Individual> individuals;
  final List<_Family> families;

  const _Parsed(this.individuals, this.families);
}

class GedcomImportService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<GedcomPreview> preview(String filePath) async {
    final parsed = await _parse(filePath);
    final stat = await File(filePath).stat();

    var parentChild = 0;
    var spouses = 0;

    for (final family in parsed.families) {
      final parents = [family.husband, family.wife].whereType<String>().length;
      parentChild += parents * family.children.length;
      if (family.husband != null && family.wife != null) spouses++;
    }

    return GedcomPreview(
      filePath: filePath,
      importKey: _key(filePath, stat.size, stat.modified.millisecondsSinceEpoch),
      individualCount: parsed.individuals.length,
      familyCount: parsed.families.length,
      parentChildLinks: parentChild,
      spouseLinks: spouses,
    );
  }

  Future<GedcomImportResult> import(
    String filePath, {
    required GedcomImportMode mode,
    void Function(GedcomImportProgress progress)? onProgress,
  }) async {
    final parsed = await _parse(filePath);
    final stat = await File(filePath).stat();
    final importKey = _key(filePath, stat.size, stat.modified.millisecondsSinceEpoch);

    final xrefToId = await _db.getGedcomPersonLinks(importKey);
    var created = 0;
    var matched = 0;

    if (xrefToId.length < parsed.individuals.length) {
      final existing = await _db.getFamilyPeople();

      String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      String exact(FamilyPerson p) =>
          '${norm(p.firstName)}|${norm(p.middleName)}|${norm(p.lastName)}|${norm(p.birthDate)}';
      String loose(FamilyPerson p) =>
          '${norm(p.firstName)}|${norm(p.lastName)}|${norm(p.birthDate)}';

      final exactMap = <String, List<FamilyPerson>>{};
      final looseMap = <String, List<FamilyPerson>>{};

      for (final p in existing) {
        if (p.id == null) continue;
        exactMap.putIfAbsent(exact(p), () => []).add(p);
        looseMap.putIfAbsent(loose(p), () => []).add(p);
      }

      var i = 0;
      for (final entry in parsed.individuals.entries) {
        i++;
        if (xrefToId.containsKey(entry.key)) continue;

        final candidate = entry.value.toPerson();
        FamilyPerson? found;

        final exactMatches = exactMap[exact(candidate)] ?? const [];
        if (exactMatches.length == 1) {
          found = exactMatches.first;
        } else {
          final looseMatches = looseMap[loose(candidate)] ?? const [];
          if (looseMatches.length == 1) found = looseMatches.first;
        }

        if (found?.id != null) {
          xrefToId[entry.key] = found!.id!;
          matched++;
        } else if (mode == GedcomImportMode.fullImport) {
          final id = await _db.insertFamilyPerson(candidate);
          xrefToId[entry.key] = id;
          created++;
        }

        if (i % 250 == 0 || i == parsed.individuals.length) {
          onProgress?.call(GedcomImportProgress(
            stage: 'People',
            completed: i,
            total: parsed.individuals.length,
            message: 'Resolving people $i / ${parsed.individuals.length}',
          ));
        }
      }

      await _db.saveGedcomPersonLinks(
        importKey: importKey,
        links: xrefToId,
      );
    }

    final parentRows = <Map<String, Object?>>[];
    final spouseRows = <Map<String, Object?>>[];

    for (var i = 0; i < parsed.families.length; i++) {
      final family = parsed.families[i];
      final husbandId = family.husband == null ? null : xrefToId[family.husband!];
      final wifeId = family.wife == null ? null : xrefToId[family.wife!];

      if (husbandId != null && wifeId != null) {
        final low = husbandId < wifeId ? husbandId : wifeId;
        final high = husbandId < wifeId ? wifeId : husbandId;
        spouseRows.add({'person1_id': low, 'person2_id': high});
      }

      for (final childRef in family.children) {
        final childId = xrefToId[childRef];
        if (childId == null) continue;

        if (husbandId != null) {
          parentRows.add({
            'parent_id': husbandId,
            'child_id': childId,
            'parent_role': 'Father',
          });
        }
        if (wifeId != null) {
          parentRows.add({
            'parent_id': wifeId,
            'child_id': childId,
            'parent_role': 'Mother',
          });
        }
      }

      final done = i + 1;
      if (done % 500 == 0 || done == parsed.families.length) {
        onProgress?.call(GedcomImportProgress(
          stage: 'Relationships',
          completed: done,
          total: parsed.families.length,
          message: 'Preparing relationships $done / ${parsed.families.length}',
        ));
      }
    }

    onProgress?.call(const GedcomImportProgress(
      stage: 'Writing',
      completed: 0,
      total: 1,
      message: 'Writing relationships in batches...',
    ));

    await _db.importFamilyRelationshipsBatch(
      parentChildLinks: parentRows,
      spouseLinks: spouseRows,
    );

    await _db.saveGedcomImportRecord(
      importKey: importKey,
      fileName: path.basename(filePath),
      fileSize: stat.size,
      modifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
      individualCount: parsed.individuals.length,
      familyCount: parsed.families.length,
    );

    return GedcomImportResult(
      peopleCreated: created,
      peopleMatched: matched,
      linkedXrefs: xrefToId.length,
      parentChildLinksWritten: parentRows.length,
      spouseLinksWritten: spouseRows.length,
      unresolvedIndividuals: parsed.individuals.length - xrefToId.length,
    );
  }

  String _key(String filePath, int size, int modifiedMs) =>
      '${path.basename(filePath)}|$size|$modifiedMs';

  Future<_Parsed> _parse(String filePath) async {
    final lines = await File(filePath).readAsLines();
    final individuals = <String, _Individual>{};
    final families = <_Family>[];

    _Individual? currentIndividual;
    _Family? currentFamily;
    String event = '';

    for (var raw in lines) {
      raw = raw.replaceFirst('\uFEFF', '');
      final line = raw.trim();
      if (line.isEmpty) continue;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final level = int.tryParse(parts[0]);
      if (level == null) continue;

      String? xref;
      late String tag;
      var value = '';

      if (level == 0 && parts.length >= 3 && parts[1].startsWith('@')) {
        xref = parts[1];
        tag = parts[2];
        if (parts.length > 3) value = parts.sublist(3).join(' ');
      } else {
        tag = parts[1];
        if (parts.length > 2) value = parts.sublist(2).join(' ');
      }

      if (level == 0) {
        currentIndividual = null;
        currentFamily = null;
        event = '';

        if (xref != null && tag == 'INDI') {
          currentIndividual = _Individual(xref);
          individuals[xref] = currentIndividual;
        } else if (xref != null && tag == 'FAM') {
          currentFamily = _Family();
          families.add(currentFamily);
        }
        continue;
      }

      if (currentIndividual != null) {
        if (level == 1) {
          event = '';
          if (tag == 'NAME') currentIndividual.name = value;
          if (tag == 'SEX') currentIndividual.sex = value;
          if (tag == 'BIRT') event = 'BIRT';
          if (tag == 'DEAT') event = 'DEAT';
        } else if (level == 2) {
          if (tag == 'GIVN') currentIndividual.given = value;
          if (tag == 'SURN') currentIndividual.surname = value;
          if (tag == 'DATE' && event == 'BIRT') currentIndividual.birthDate = value;
          if (tag == 'DATE' && event == 'DEAT') currentIndividual.deathDate = value;
          if (tag == 'PLAC' && event == 'BIRT') currentIndividual.birthPlace = value;
          if (tag == 'PLAC' && event == 'DEAT') currentIndividual.deathPlace = value;
        }
      } else if (currentFamily != null && level == 1) {
        if (tag == 'HUSB') currentFamily.husband = value.trim();
        if (tag == 'WIFE') currentFamily.wife = value.trim();
        if (tag == 'CHIL') currentFamily.children.add(value.trim());
      }
    }

    return _Parsed(individuals, families);
  }
}
