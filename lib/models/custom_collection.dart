import 'dart:convert';

class CustomCollection {
  final int? id;
  final String name;
  final String iconKey;
  final List<String> enabledFields;
  final int createdAtMilliseconds;

  const CustomCollection({
    this.id,
    required this.name,
    required this.iconKey,
    required this.enabledFields,
    required this.createdAtMilliseconds,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
        'enabled_fields_json': jsonEncode(enabledFields),
        'created_at_milliseconds': createdAtMilliseconds,
      };

  factory CustomCollection.fromMap(Map<String, Object?> map) {
    List<String> decodeFields(Object? value) {
      try {
        final decoded = jsonDecode(value?.toString() ?? '[]');
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toList();
        }
      } catch (_) {}
      return const [];
    }

    return CustomCollection(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      iconKey: map['icon_key'] as String? ?? 'inventory',
      enabledFields: decodeFields(map['enabled_fields_json']),
      createdAtMilliseconds:
          (map['created_at_milliseconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class CustomCollectionField {
  static const title = 'title';
  static const photos = 'photos';
  static const description = 'description';
  static const documents = 'documents';
  static const date = 'date';
  static const value = 'value';
  static const location = 'location';
  static const quantity = 'quantity';
  static const status = 'status';
  static const notes = 'notes';

  static const defaults = <String>[
    title,
    photos,
    description,
    date,
    value,
    notes,
  ];

  static const all = <String>[
    title,
    photos,
    description,
    documents,
    date,
    value,
    location,
    quantity,
    status,
    notes,
  ];

  static String label(String field) {
    switch (field) {
      case title:
        return 'Title';
      case photos:
        return 'Photos';
      case description:
        return 'Description';
      case documents:
        return 'Documents / Attachments';
      case date:
        return 'Date / Year';
      case value:
        return 'Value';
      case location:
        return 'Location';
      case quantity:
        return 'Quantity';
      case status:
        return 'Status';
      case notes:
        return 'Notes';
      default:
        return field;
    }
  }
}
