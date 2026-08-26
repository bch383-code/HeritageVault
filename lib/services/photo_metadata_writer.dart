import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/photo_catalog_metadata.dart';

class PhotoMetadataWriteResult {
  final bool success;
  final String message;
  final String? backupPath;

  const PhotoMetadataWriteResult({
    required this.success,
    required this.message,
    this.backupPath,
  });
}

class PhotoMetadataWriter {
  static Future<PhotoMetadataWriteResult> write({
    required String filePath,
    required PhotoCatalogMetadata metadata,
  }) async {
    final source = File(filePath);
    if (!await source.exists()) {
      return const PhotoMetadataWriteResult(
        success: false,
        message: 'The original photo could not be found.',
      );
    }

    final extension = path.extension(filePath).toLowerCase();
    const supported = {'.jpg', '.jpeg', '.tif', '.tiff', '.png', '.webp'};

    if (!supported.contains(extension)) {
      return PhotoMetadataWriteResult(
        success: false,
        message: 'Metadata writing is not enabled for $extension files yet.',
      );
    }

    final executable = await _findExifTool();
    if (executable == null) {
      return const PhotoMetadataWriteResult(
        success: false,
        message:
            'ExifTool was not found. Install the 64-bit Windows ExifTool '
            'executable and make sure exiftool.exe is available in PATH.',
      );
    }

    final backupPath = await _createBackup(source);

    final keywordByKey = <String, String>{};

    void addKeyword(String value) {
      final clean = value.trim();
      if (clean.isEmpty) return;
      keywordByKey.putIfAbsent(clean.toLowerCase(), () => clean);
    }

    for (final tag in metadata.tags) {
      addKeyword(tag);
    }
    for (final person in metadata.people) {
      final clean = person.trim();
      if (clean.isNotEmpty) {
        addKeyword('Person: $clean');
      }
    }

    final keywords = keywordByKey.values.toList();

    final args = <String>[
      '-P',
      '-overwrite_original',
      '-charset',
      'filename=UTF8',
    ];

    if (metadata.description.trim().isNotEmpty) {
      args.add('-XMP-dc:Description=${metadata.description.trim()}');
    }

    // Clear and rewrite the keyword list so Heirloom Atlas and the
    // embedded metadata remain predictable.
    args.add('-XMP-dc:Subject=');
    for (final keyword in keywords) {
      args.add('-XMP-dc:Subject+=$keyword');
    }

    if (metadata.location.trim().isNotEmpty) {
      args.add('-XMP-iptcCore:Location=${metadata.location.trim()}');
    }

    // Approximate Date is intentionally NOT written to DateTimeOriginal.
    // That field may contain a real camera/original date and must not be
    // overwritten by an estimated archival date.
    args.add(filePath);

    try {
      final result = await Process.run(executable, args, runInShell: false);

      if (result.exitCode != 0) {
        return PhotoMetadataWriteResult(
          success: false,
          backupPath: backupPath,
          message: 'ExifTool could not update the photo.\n${result.stderr}',
        );
      }

      return PhotoMetadataWriteResult(
        success: true,
        backupPath: backupPath,
        message: 'Metadata written to the original photo.',
      );
    } catch (error) {
      return PhotoMetadataWriteResult(
        success: false,
        backupPath: backupPath,
        message: 'Could not run ExifTool: $error',
      );
    }
  }

  static Future<String> _createBackup(File source) async {
    final documents = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      path.join(documents.path, 'Heirloom Atlas', 'Photo Metadata Backups'),
    );

    if (!await backupDirectory.exists()) {
      await backupDirectory.create(recursive: true);
    }

    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');

    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}_'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final base = path.basenameWithoutExtension(source.path);
    final extension = path.extension(source.path);
    final destination = path.join(
      backupDirectory.path,
      '${base}_$stamp$extension',
    );

    await source.copy(destination);
    return destination;
  }

  static Future<String?> _findExifTool() async {
    const directWindowsPath = r'C:\ExifTool\exiftool.exe';

    final directFile = File(directWindowsPath);
    if (await directFile.exists()) {
      try {
        final result = await Process.run(directWindowsPath, [
          '-ver',
        ], runInShell: false);
        if (result.exitCode == 0) return directWindowsPath;
      } catch (_) {}
    }

    const candidates = ['exiftool.exe', 'exiftool'];

    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate, ['-ver'], runInShell: true);
        if (result.exitCode == 0) return candidate;
      } catch (_) {}
    }

    return null;
  }
}
