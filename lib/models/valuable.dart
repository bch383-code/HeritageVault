class Valuable {
  final int? id;
  final String title;
  final String description;
  final String year;
  final String acquiredFrom;
  final double? purchasePrice;
  final double? estimatedValue;
  final String notes;
  final List<String> imagePaths;
  final String condition;
  final String conditionNotes;
  final String provenance;
  final String appraisalSource;
  final String valuationDate;
  final List<String> supportingDocumentPaths;

  const Valuable({
    this.id,
    this.title = '',
    this.description = '',
    this.year = '',
    this.acquiredFrom = '',
    this.purchasePrice,
    this.estimatedValue,
    this.notes = '',
    this.imagePaths = const [],
    this.condition = '',
    this.conditionNotes = '',
    this.provenance = '',
    this.appraisalSource = '',
    this.valuationDate = '',
    this.supportingDocumentPaths = const [],
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'year': year,
    'acquired_from': acquiredFrom,
    'purchase_price': purchasePrice,
    'estimated_value': estimatedValue,
    'notes': notes,
    'condition': condition,
    'condition_notes': conditionNotes,
    'provenance': provenance,
    'appraisal_source': appraisalSource,
    'valuation_date': valuationDate,
  };

  factory Valuable.fromMap(
    Map<String, Object?> map, {
    List<String> imagePaths = const [],
    List<String> supportingDocumentPaths = const [],
  }) {
    double? toDouble(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return Valuable(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      year: map['year'] as String? ?? '',
      acquiredFrom: map['acquired_from'] as String? ?? '',
      purchasePrice: toDouble(map['purchase_price']),
      estimatedValue: toDouble(map['estimated_value']),
      notes: map['notes'] as String? ?? '',
      imagePaths: imagePaths,
      condition: map['condition'] as String? ?? '',
      conditionNotes: map['condition_notes'] as String? ?? '',
      provenance: map['provenance'] as String? ?? '',
      appraisalSource: map['appraisal_source'] as String? ?? '',
      valuationDate: map['valuation_date'] as String? ?? '',
      supportingDocumentPaths: supportingDocumentPaths,
    );
  }
}
