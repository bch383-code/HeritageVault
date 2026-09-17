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

    // Only an explicitly Exact catalog date is portable as a capture date.
    // Approximate/year-only/decade/unknown values remain catalog-only so we
    // never replace a real camera date with an estimate.
    final storedDate = metadata.approximateDate.trim();
    final exactDate = _exifDateFromExactCatalogValue(storedDate);
    if (exactDate != null) {
      args.add('-EXIF:DateTimeOriginal=$exactDate');
      args.add('-EXIF:CreateDate=$exactDate');
      args.add('-XMP-exif:DateTimeOriginal=$exactDate');
    }

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

  static String? _exifDateFromExactCatalogValue(String value) {
    final clean = value.trim();
    if (clean.isEmpty ||
        clean.toLowerCase() == 'unknown' ||
        clean.startsWith('c. ') ||
        RegExp(r'^\d{4}s$').hasMatch(clean) ||
        RegExp(r'^\d{4}$').hasMatch(clean)) {
      return null;
    }

    // Accept the unambiguous exact format used by the photo editor.
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(clean);
    if (match == null) return null;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;

    final hour = int.tryParse(match.group(4) ?? '00') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '00') ?? 0;
    final second = int.tryParse(match.group(6) ?? '00') ?? 0;

    try {
      final parsed = DateTime(year, month, day, hour, minute, second);
      if (parsed.year != year ||
          parsed.month != month ||
          parsed.day != day ||
          parsed.hour != hour ||
          parsed.minute != minute ||
          parsed.second != second) {
        return null;
      }
    } catch (_) {
      return null;
    }

    String two(int number) => number.toString().padLeft(2, '0');
    return '${year.toString().padLeft(4, '0')}:'
        '${two(month)}:${two(day)} '
        '${two(hour)}:${two(minute)}:${two(second)}';
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
    final candidates = <String>[];

    // Installed/release build: ExifTool is bundled beside the Heirloom Atlas
    // executable under tools\exiftool.
    if (Platform.isWindows) {
      final executableDirectory = File(Platform.resolvedExecutable).parent.path;
      candidates.add(
        path.join(executableDirectory, 'tools', 'exiftool', 'exiftool.exe'),
      );

      // Development fallback.
      candidates.add(r'C:\ExifTool\exiftool.exe');
    }

    // Final fallback: allow a system-installed ExifTool from PATH.
    candidates.addAll(['exiftool.exe', 'exiftool']);

    for (final candidate in candidates) {
      try {
        if (path.isAbsolute(candidate) && !await File(candidate).exists()) {
          continue;
        }

        final result = await Process.run(candidate, [
          '-ver',
        ], runInShell: !path.isAbsolute(candidate));
        if (result.exitCode == 0) return candidate;
      } catch (_) {}
    }

    return null;
  }
}
