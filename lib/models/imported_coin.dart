class ImportedCoin {
  final String category;
  final String series;
  final String year;
  final String mint;
  final String variety;
  final String status;
  final String storageLocation;
  final String grade;
  final String notes;

  const ImportedCoin({
    required this.category,
    required this.series,
    required this.year,
    required this.mint,
    required this.variety,
    required this.status,
    required this.storageLocation,
    required this.grade,
    required this.notes,
  });

  bool get isNeeded => status.toUpperCase() == 'NEED';

  bool get isOwned => status.toUpperCase() == 'OWNED';

  String get displayName {
    return [
      year,
      mint,
      variety,
    ].where((value) => value.trim().isNotEmpty).join(' ');
  }
}