import 'dart:io';

class CoinImagePackService {
  CoinImagePackService._();

  /// Folder where optional Heirloom Atlas packages are stored.
  static Directory get coinPackDirectory {
    final appData = Platform.environment['LOCALAPPDATA'];

    if (appData == null || appData.isEmpty) {
      return Directory(
        '${Directory.current.path}${Platform.pathSeparator}'
        'Heirloom Atlas${Platform.pathSeparator}'
        'Packages${Platform.pathSeparator}'
        'Coins${Platform.pathSeparator}'
        'series',
      );
    }

    return Directory(
      '$appData${Platform.pathSeparator}'
      'Heirloom Atlas${Platform.pathSeparator}'
      'Packages${Platform.pathSeparator}'
      'Coins${Platform.pathSeparator}'
      'series',
    );
  }

  /// Converts an existing Flutter asset path such as:
  ///
  /// assets/images/series/morgan_dollar_thumb.png
  ///
  /// into the corresponding optional Coin Pack file.
  static File? fileForAsset(String? assetPath) {
    if (assetPath == null) return null;

    final cleaned = assetPath.trim();
    if (cleaned.isEmpty) return null;

    final normalized = cleaned.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;

    if (fileName.isEmpty) return null;

    return File(
      '${coinPackDirectory.path}${Platform.pathSeparator}$fileName',
    );
  }

  /// Returns the image file only when it actually exists.
  static File? installedFileForAsset(String? assetPath) {
    final file = fileForAsset(assetPath);

    if (file == null || !file.existsSync()) {
      return null;
    }

    return file;
  }

  /// True when the Coin Image Pack appears to be installed.
  static bool get isInstalled {
    final directory = coinPackDirectory;

    if (!directory.existsSync()) {
      return false;
    }

    try {
      return directory
          .listSync()
          .whereType<File>()
          .any((file) => _isSupportedImage(file.path));
    } catch (_) {
      return false;
    }
  }

  static bool _isSupportedImage(String path) {
    final lower = path.toLowerCase();

    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }
}