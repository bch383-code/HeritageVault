class Antique {
  final int? id;
  final String title;
  final String description;
  final String year;
  final String acquiredFrom;
  final double? purchasePrice;
  final double? estimatedValue;
  final String notes;
  final List<String> imagePaths;

  const Antique({
    this.id,
    this.title = '',
    this.description = '',
    this.year = '',
    this.acquiredFrom = '',
    this.purchasePrice,
    this.estimatedValue,
    this.notes = '',
    this.imagePaths = const [],
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'year': year,
      'acquired_from': acquiredFrom,
      'purchase_price': purchasePrice,
      'estimated_value': estimatedValue,
      'notes': notes,
    };
  }

  factory Antique.fromMap(
    Map<String, Object?> map, {
    List<String> imagePaths = const [],
  }) {
    double? toDouble(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return Antique(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      year: map['year'] as String? ?? '',
      acquiredFrom: map['acquired_from'] as String? ?? '',
      purchasePrice: toDouble(map['purchase_price']),
      estimatedValue: toDouble(map['estimated_value']),
      notes: map['notes'] as String? ?? '',
      imagePaths: imagePaths,
    );
  }
}
