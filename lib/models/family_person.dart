class FamilyPerson {
  final int? id;
  final String firstName, middleName, lastName, birthName, sex;
  final String birthDate, birthPlace, deathDate, deathPlace;
  final String biography, notes, profilePhotoPath;
  final int createdAtMilliseconds, updatedAtMilliseconds;

  const FamilyPerson({this.id, this.firstName='', this.middleName='', this.lastName='', this.birthName='', this.sex='', this.birthDate='', this.birthPlace='', this.deathDate='', this.deathPlace='', this.biography='', this.notes='', this.profilePhotoPath='', this.createdAtMilliseconds=0, this.updatedAtMilliseconds=0});

  String get displayName => [firstName,middleName,lastName].where((e)=>e.trim().isNotEmpty).join(' ').isEmpty ? 'Unnamed Person' : [firstName,middleName,lastName].where((e)=>e.trim().isNotEmpty).join(' ');
  String get lifeSpan {
    String y(String s) => RegExp(r'\b(\d{4})\b').firstMatch(s)?.group(1) ?? '';
    final b=y(birthDate), d=y(deathDate); if(b.isEmpty&&d.isEmpty)return '';
    return '${b.isEmpty?'?':b} – ${d.isEmpty?'':d}';
  }
  Map<String,Object?> toMap()=>{'id':id,'first_name':firstName,'middle_name':middleName,'last_name':lastName,'birth_name':birthName,'sex':sex,'birth_date':birthDate,'birth_place':birthPlace,'death_date':deathDate,'death_place':deathPlace,'biography':biography,'notes':notes,'profile_photo_path':profilePhotoPath,'created_at_milliseconds':createdAtMilliseconds,'updated_at_milliseconds':updatedAtMilliseconds};
  factory FamilyPerson.fromMap(Map<String,Object?> m)=>FamilyPerson(id:m['id'] as int?,firstName:m['first_name'] as String? ?? '',middleName:m['middle_name'] as String? ?? '',lastName:m['last_name'] as String? ?? '',birthName:m['birth_name'] as String? ?? '',sex:m['sex'] as String? ?? '',birthDate:m['birth_date'] as String? ?? '',birthPlace:m['birth_place'] as String? ?? '',deathDate:m['death_date'] as String? ?? '',deathPlace:m['death_place'] as String? ?? '',biography:m['biography'] as String? ?? '',notes:m['notes'] as String? ?? '',profilePhotoPath:m['profile_photo_path'] as String? ?? '',createdAtMilliseconds:(m['created_at_milliseconds'] as num?)?.toInt()??0,updatedAtMilliseconds:(m['updated_at_milliseconds'] as num?)?.toInt()??0);
}
