import 'dart:io';

import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/coin_image_pack_service.dart';
import '../onboarding/onboarding_screen.dart';
import 'backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _version = 'Private Beta 0.1.4';
  String? _dataPath;
  String _helpLevel = 'Guided';
  String _changePolicy = 'Ask before changing originals';
  bool _backupBusy = false;
  bool _coinPackBusy = false;
  bool _coinPackInstalled = false;
  String? _lastBackupPath;
  String? _backupDestination;
  String? _lastBackupCreatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final directory = await getApplicationSupportDirectory();
    final backupStatus = await HeirloomBackupService.getBackupStatus();

    final help = switch (prefs.getString('onboarding_help_level')) {
      'simple' => 'Simple',
      'advanced' => 'Advanced',
      _ => 'Guided',
    };

    final policy =
        prefs.getString('onboarding_change_policy') == 'approved_automation'
        ? 'Approved automation allowed'
        : 'Ask before changing originals';

    if (!mounted) return;
    setState(() {
      _dataPath = directory.path;
      _helpLevel = help;
      _changePolicy = policy;
      _backupDestination = backupStatus.preferredParentDirectory;
      _lastBackupPath = backupStatus.lastBackupPath;
      _lastBackupCreatedAt = backupStatus.lastBackupCreatedAt;
      _coinPackInstalled = CoinImagePackService.isInstalled;
    });
  }

  Future<void> _runSetupAgain() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OnboardingScreen(onComplete: () => Navigator.of(context).pop()),
      ),
    );
    await _load();
  }

  Future<void> _resetOnboarding() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset onboarding?'),
        content: const Text(
          'This resets only the first-run setup choices. It does not delete '
          'your photos, collections, family tree, or other Heirloom Atlas data. '
          'The setup wizard will appear the next time the app starts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset onboarding'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Onboarding reset. The setup wizard will appear after you restart Heirloom Atlas.',
        ),
      ),
    );
  }

  Future<void> _chooseBackupLocation() async {
    final destination = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose the Heirloom Atlas backup location',
      initialDirectory: _backupDestination,
    );
    if (destination == null || destination.trim().isEmpty) return;

    await HeirloomBackupService.setPreferredBackupParent(destination);
    if (!mounted) return;
    setState(() => _backupDestination = destination);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Backup location saved: $destination',
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    var destination = _backupDestination;
    if (destination == null || destination.trim().isEmpty) {
      destination = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose where to save Heirloom Atlas backups',
      );
      if (destination == null || destination.trim().isEmpty) return;
      await HeirloomBackupService.setPreferredBackupParent(destination);
    }

    setState(() => _backupBusy = true);
    try {
      final result = await HeirloomBackupService.createBackup(destination);
      final status = await HeirloomBackupService.getBackupStatus();
      if (!mounted) return;
      setState(() {
        _backupDestination = status.preferredParentDirectory;
        _lastBackupPath = result.backupPath;
        _lastBackupCreatedAt = status.lastBackupCreatedAt;
      });

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Backup created'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Heirloom Atlas catalog and organization data has been backed up.',
                ),
                const SizedBox(height: 12),
                SelectableText(result.backupPath),
                const SizedBox(height: 16),
                Text(
                  result.includedAtlasBook
                      ? 'Atlas Book data included.'
                      : 'No Atlas Book database was found to include.',
                ),
                Text(
                  '${result.faceThumbnailCount} face '
                  '${result.faceThumbnailCount == 1 ? 'thumbnail' : 'thumbnails'} included.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Original photos, documents, and other source files are not '
                  'copied into this backup. They remain in their existing '
                  'locations.',
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a Heirloom Atlas backup folder',
    );
    if (selected == null || selected.trim().isEmpty) return;

    Map<String, Object?> manifest;
    try {
      manifest = await HeirloomBackupService.inspectBackup(selected);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not use this backup: $error')),
      );
      return;
    }

    if (!mounted) return;

    final createdAt = manifest['created_at']?.toString() ?? 'Unknown date';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore Heirloom Atlas backup?'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Backup created: $createdAt'),
              const SizedBox(height: 12),
              const Text(
                'The restore will replace the Heirloom Atlas catalog database '
                'and Atlas Book database (when included). A safety copy of the '
                'current databases will be kept before replacement.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Your original photos and source files will not be deleted, '
                'moved, or overwritten.',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text(
                'The restore will be applied the next time Heirloom Atlas starts.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore on Restart'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await HeirloomBackupService.scheduleRestore(selected);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore scheduled'),
        content: const Text(
          'Close Heirloom Atlas completely and open it again. The backup will '
          'be restored before the app opens its databases.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static const String _coinPackUrl =
      'https://download.heirloomatlas.app/packs/coin-reference-1.0.zip';

  Future<void> _downloadCoinImagePack() async {
    setState(() => _coinPackBusy = true);

    final targetDirectory = CoinImagePackService.coinPackDirectory;
    final parentDirectory = targetDirectory.parent;
    final temporaryDirectory = Directory(
      '${parentDirectory.path}${Platform.pathSeparator}series_installing',
    );
    final temporaryZip = File(
      '${parentDirectory.path}${Platform.pathSeparator}coin-reference-1.0-downloading.zip',
    );

    HttpClient? client;
    try {
      parentDirectory.createSync(recursive: true);
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
      if (temporaryZip.existsSync()) {
        temporaryZip.deleteSync();
      }

      client = HttpClient();
      final request = await client.getUrl(Uri.parse(_coinPackUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}.',
          uri: Uri.parse(_coinPackUrl),
        );
      }

      final sink = temporaryZip.openWrite();
      await response.pipe(sink);

      await _installCoinImagePackFromZip(temporaryZip.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not download Coin Image Pack: $error')),
      );
    } finally {
      client?.close(force: true);
      if (temporaryZip.existsSync()) {
        try {
          temporaryZip.deleteSync();
        } catch (_) {}
      }
      if (mounted) setState(() => _coinPackBusy = false);
    }
  }

  Future<void> _installCoinImagePack() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose the Heirloom Atlas Coin Image Pack',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
    );

    final selectedPath = picked.single.path;
    if (selectedPath == null || selectedPath.trim().isEmpty) return;

    setState(() => _coinPackBusy = true);
    try {
      await _installCoinImagePackFromZip(selectedPath);
    } finally {
      if (mounted) setState(() => _coinPackBusy = false);
    }
  }

  Future<void> _installCoinImagePackFromZip(String zipPath) async {
    final targetDirectory = CoinImagePackService.coinPackDirectory;
    final parentDirectory = targetDirectory.parent;
    final temporaryDirectory = Directory(
      '${parentDirectory.path}${Platform.pathSeparator}series_installing',
    );

    try {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
      temporaryDirectory.createSync(recursive: true);

      final zipBytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);

      var installedCount = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;

        final normalized = entry.name.replaceAll('\\', '/');
        final fileName = normalized.split('/').last.trim();
        if (fileName.isEmpty || !_isSupportedCoinImage(fileName)) continue;

        final outputFile = File(
          '${temporaryDirectory.path}${Platform.pathSeparator}$fileName',
        );
        await outputFile.writeAsBytes(entry.content as List<int>, flush: true);
        installedCount++;
      }

      if (installedCount == 0) {
        throw const FormatException(
          'This ZIP does not contain any supported coin reference images.',
        );
      }

      if (targetDirectory.existsSync()) {
        targetDirectory.deleteSync(recursive: true);
      }
      temporaryDirectory.renameSync(targetDirectory.path);

      if (!mounted) return;
      setState(() => _coinPackInstalled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Coin Reference Images installed ($installedCount images).',
          ),
        ),
      );
    } catch (error) {
      if (temporaryDirectory.existsSync()) {
        try {
          temporaryDirectory.deleteSync(recursive: true);
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not install Coin Image Pack: $error')),
      );
      rethrow;
    }
  }

  Future<void> _removeCoinImagePack() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Coin Reference Images?'),
        content: const Text(
          'This removes only the optional coin reference artwork. '
          'Your coin collection, notes, values, storage locations, and other '
          'Heirloom Atlas data will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove Package'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _coinPackBusy = true);
    try {
      final directory = CoinImagePackService.coinPackDirectory;
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }

      if (!mounted) return;
      setState(() => _coinPackInstalled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coin Reference Images removed.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove Coin Image Pack: $error')),
      );
    } finally {
      if (mounted) setState(() => _coinPackBusy = false);
    }
  }

  bool _isSupportedCoinImage(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  String get _backupStatusText {
    if (_lastBackupCreatedAt == null || _lastBackupCreatedAt!.trim().isEmpty) {
      return 'No successful backup recorded yet.';
    }
    final parsed = DateTime.tryParse(_lastBackupCreatedAt!);
    if (parsed == null) return 'Last backup: $_lastBackupCreatedAt';
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Last backup: ${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFF071A2B).withValues(alpha: 0.54),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Color(0xFFF3E9D1),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.science_outlined, size: 18),
                label: const Text(_version),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF071A2B).withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFC9A65A).withValues(alpha: 0.42),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.42,
                      child: Opacity(
                        opacity: 0.28,
                        child: Image.asset(
                          'assets/branding/heirloom_atlas_beta_heritage_atmosphere.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.centerRight,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xFC071A2B),
                          Color(0xF0071A2B),
                          Color(0xBC071A2B),
                          Color(0x64071A2B),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF103451,
                          ).withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFFC9A65A,
                            ).withValues(alpha: 0.30),
                          ),
                        ),
                        child: const Icon(
                          Icons.settings_outlined,
                          color: Color(0xFFC9A65A),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Settings & Safekeeping',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: const Color(0xFFF3E9D1),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Protect your archive. Keep control of your collection.',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: const Color(0xFFC9A65A),
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _section(
            title: 'Getting Started',
            subtitle: 'Review or change how Heirloom Atlas helps you.',
            children: [
              _settingTile(
                icon: Icons.auto_awesome_outlined,
                title: 'Run Setup Again',
                subtitle:
                    'Revisit the onboarding wizard without deleting any collection data.',
                trailing: const Icon(Icons.chevron_right),
                onTap: _runSetupAgain,
              ),
              _infoTile(Icons.tune, 'Current experience', _helpLevel),
              _infoTile(
                Icons.shield_outlined,
                'Original-file policy',
                _changePolicy,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _section(
            title: 'Data Backup & Safekeeping',
            subtitle:
                'Protect your Heirloom Atlas catalog separately from your original files.',
            children: [
              _infoTile(
                Icons.folder_outlined,
                'Application data location',
                _dataPath ?? 'Loading…',
              ),
              _settingTile(
                icon: Icons.cloud_done_outlined,
                title: 'Backup Location',
                subtitle: _backupDestination == null
                    ? 'Choose a folder. A OneDrive-synced folder is a good option for an off-device copy.'
                    : _backupDestination!,
                trailing: const Icon(Icons.chevron_right),
                onTap: _backupBusy ? null : _chooseBackupLocation,
              ),
              _infoTile(
                Icons.history_outlined,
                'Backup status',
                _backupStatusText,
              ),
              _settingTile(
                icon: Icons.backup_outlined,
                title: 'Back Up Now',
                subtitle: _lastBackupPath == null
                    ? 'Back up catalog data, settings, Atlas Book data, and face thumbnails.'
                    : 'Most recent backup: $_lastBackupPath',
                trailing: _backupBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _backupBusy ? null : _createBackup,
              ),
              _settingTile(
                icon: Icons.restore_outlined,
                title: 'Restore Backup',
                subtitle:
                    'Restore a Heirloom Atlas backup safely on the next app start. Current databases receive safety copies first.',
                trailing: const Icon(Icons.chevron_right),
                onTap: _backupBusy ? null : _restoreBackup,
              ),
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                leading: Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFFC9A65A),
                ),
                title: Text(
                  'Original files stay separate',
                  style: TextStyle(
                    color: Color(0xFFF3E9D1),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  'This backup protects Heirloom Atlas organization data. It does not duplicate your original photo, document, or other source libraries.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _section(
            title: 'Downloads & Packages',
            subtitle:
                'Add optional reference resources without making the main Heirloom Atlas installation larger.',
            children: [
              _settingTile(
                icon: Icons.monetization_on_outlined,
                title: 'Coin Reference Images',
                subtitle: _coinPackInstalled
                    ? 'Installed • Optional reference artwork for U.S. coin series.'
                    : 'Not installed • 67 reference images • approximately 211 MB.',
                trailing: _coinPackBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _coinPackInstalled
                        ? TextButton(
                            onPressed: _removeCoinImagePack,
                            child: const Text('Remove'),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _downloadCoinImagePack,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Download & Install'),
                              ),
                              OutlinedButton(
                                onPressed: _installCoinImagePack,
                                child: const Text('Install from Package'),
                              ),
                            ],
                          ),
                onTap: null,
              ),
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                leading: Icon(
                  Icons.shield_outlined,
                  color: Color(0xFFC9A65A),
                ),
                title: Text(
                  'Reference resources only',
                  style: TextStyle(
                    color: Color(0xFFF3E9D1),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  'Removing an optional package never removes your personal collection records or source files.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _section(
            title: 'Beta Tools',
            subtitle: 'Tools useful while testing Heirloom Atlas.',
            children: [
              _settingTile(
                icon: Icons.restart_alt,
                title: 'Reset onboarding only',
                subtitle:
                    'Show the first-run wizard on the next launch. Your collection data is not reset.',
                trailing: const Icon(Icons.chevron_right),
                onTap: _resetOnboarding,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _section(
            title: 'About',
            subtitle: 'Heirloom Atlas build information.',
            children: [
              _infoTile(Icons.inventory_2_outlined, 'Heirloom Atlas', _version),
              _infoTile(
                Icons.computer_outlined,
                'Platform',
                Platform.isWindows ? 'Windows' : Platform.operatingSystem,
              ),
              _infoTile(
                Icons.photo_library_outlined,
                'Original files',
                'Heirloom Atlas does not move or delete your originals unless you explicitly choose an action that does so.',
              ),
              _infoTile(
                Icons.storage_outlined,
                'Data & backups',
                'Your Heirloom Atlas catalog is stored on your computer. You choose where backups are saved.',
              ),
              _infoTile(
                Icons.lock_outline,
                'Collection ownership & portability',
                'Your collection is yours. Not ours. Your family history should never be locked into one app.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Card(
      color: const Color(0xFF0B2742).withValues(alpha: 0.52),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFF86BCE7).withValues(alpha: 0.20),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFFF3E9D1),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 14),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Icon(icon, color: const Color(0xFFC9A65A)),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFF3E9D1),
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _infoTile(IconData icon, String title, String value) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Icon(icon, color: const Color(0xFFC9A65A)),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFF3E9D1),
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: SelectableText(value),
    );
  }
}
