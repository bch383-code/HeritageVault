class VaultPhoto {
  final int? id;
  final String filePath;
  final String fileName;
  final String extension;
  final int fileSize;
  final int modifiedMilliseconds;
  final String relativeFolder;

  const VaultPhoto({
    this.id,
    required this.filePath,
    required this.fileName,
    required this.extension,
    required this.fileSize,
    required this.modifiedMilliseconds,
    required this.relativeFolder,
  });

  factory VaultPhoto.fromMap(Map<String, Object?> map) {
    int toInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return VaultPhoto(
      id: map['id'] as int?,
      filePath: map['file_path'] as String? ?? '',
      fileName: map['file_name'] as String? ?? '',
      extension: map['extension'] as String? ?? '',
      fileSize: toInt(map['file_size']),
      modifiedMilliseconds: toInt(map['modified_milliseconds']),
      relativeFolder: map['relative_folder'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'file_path': filePath,
        'file_name': fileName,
        'extension': extension,
        'file_size': fileSize,
        'modified_milliseconds': modifiedMilliseconds,
        'relative_folder': relativeFolder,
      };
}
