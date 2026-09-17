import 'dart:io';
import 'dart:typed_data';

import 'package:heic_native/heic_native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Compatibility helper for HEIC/HEIF photos.
///
/// Heirloom Atlas keeps the user's original file untouched. When another part
/// of the app needs broadly decodable image pixels, this service can provide
/// PNG bytes or a cached PNG working copy.
class HeicCompatibilityService {
  const HeicCompatibilityService();

  static const Set<String> _heicExtensions = <String>{
    '.heic',
    '.heif',
  };

  bool isHeicPath(String filePath) {
    return _heicExtensions.contains(path.extension(filePath).toLowerCase());
  }

  /// Returns bytes suitable for image display/analysis.
  ///
  /// Non-HEIC files are returned unchanged. HEIC/HEIF files are decoded to
  /// PNG in memory. The source file is never modified.
  Future<Uint8List> readableBytes(
    String filePath, {
    int compressionLevel = 1,
    bool preserveMetadata = true,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Image file does not exist.', filePath);
    }

    if (!isHeicPath(filePath)) {
      return file.readAsBytes();
    }

    final bytes = await HeicNative.convertToBytes(
      filePath,
      compressionLevel: compressionLevel,
      preserveMetadata: preserveMetadata,
    );

    if (bytes.isEmpty) {
      throw StateError('HEIC/HEIF conversion returned no image data.');
    }

    return bytes;
  }

  /// Returns a normal image path that can be used by code that requires a
  /// file path rather than bytes.
  ///
  /// Non-HEIC paths are returned unchanged. HEIC/HEIF files get a PNG working
  /// copy under Heirloom Atlas/Cache/HEIC. The original remains untouched.
  Future<String> readableFilePath(
    String filePath, {
    int compressionLevel = 1,
    bool preserveMetadata = true,
  }) async {
    final source = File(filePath);
    if (!await source.exists()) {
      throw FileSystemException('Image file does not exist.', filePath);
    }

    if (!isHeicPath(filePath)) return filePath;

    final documents = await getApplicationDocumentsDirectory();
    final cacheDirectory = Directory(
      path.join(
        documents.path,
        'Heirloom Atlas',
        'Cache',
        'HEIC',
      ),
    );
    await cacheDirectory.create(recursive: true);

    final stat = await source.stat();
    final key = _stableKey(
      '${source.absolute.path}|${stat.size}|'
      '${stat.modified.millisecondsSinceEpoch}',
    );

    final outputPath = path.join(cacheDirectory.path, '$key.png');
    final output = File(outputPath);

    if (await output.exists() && await output.length() > 0) {
      return outputPath;
    }

    final success = await HeicNative.convert(
      filePath,
      outputPath,
      compressionLevel: compressionLevel,
      preserveMetadata: preserveMetadata,
    );

    if (!success || !await output.exists() || await output.length() == 0) {
      if (await output.exists()) {
        try {
          await output.delete();
        } catch (_) {}
      }
      throw StateError('Unable to create HEIC/HEIF compatibility image.');
    }

    return outputPath;
  }

  /// Removes generated HEIC working copies only. Original photos are never
  /// touched.
  Future<void> clearCache() async {
    final documents = await getApplicationDocumentsDirectory();
    final cacheDirectory = Directory(
      path.join(
        documents.path,
        'Heirloom Atlas',
        'Cache',
        'HEIC',
      ),
    );

    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  }

  String _stableKey(String value) {
    // FNV-1a 64-bit. This avoids another package dependency and gives stable,
    // filesystem-safe cache names.
    const int offsetBasis = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    const int mask64 = 0xffffffffffffffff;

    var hash = offsetBasis;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * prime) & mask64;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}
