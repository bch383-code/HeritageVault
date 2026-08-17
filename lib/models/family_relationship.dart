class FamilyRelationship {
  final int id;
  final int relatedPersonId;
  final String relationship;
  final String relatedName;

  const FamilyRelationship({
    required this.id,
    required this.relatedPersonId,
    required this.relationship,
    required this.relatedName,
  });
}
