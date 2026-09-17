import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../database/database_helper.dart';
import '../services/microsoft_graph_auth_service.dart';
import '../services/local_network_sync_service.dart';
import '../services/sync_service.dart';

class SyncStorageScreen extends StatefulWidget {
  const SyncStorageScreen({super.key});

  @override
  State<SyncStorageScreen> createState() => _SyncStorageScreenState();
}

class _SyncStorageScreenState extends State<SyncStorageScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final SyncService _syncService = SyncService();
  final MicrosoftGraphAuthService _microsoftAuthService =
      MicrosoftGraphAuthService();
  final LocalNetworkSyncService _localNetworkSyncService =
      LocalNetworkSyncService();

  bool _loading = true;
  bool _backingUp = false;
  bool _choosingSyncFolder = false;
  bool _exportingMobileCaptures = false;
  bool _startingLocalReceiver = false;
  LocalNetworkReceiverStatus? _localReceiverStatus;
  String? _error;
  Map<String, Object?>? _currentDevice;
  Map<String, int> _summary = const {};
  List<Map<String, Object?>> _sources = const [];
  List<Map<String, Object?>> _pendingChanges = const [];
  OutboundSyncPlan? _syncPlan;
  OneDriveMappingResult? _oneDriveMapping;
  MicrosoftGraphAuthSession? _microsoftSession;
  bool _microsoftAuthorizing = false;
  bool _oneDriveMatching = false;
  bool _showAdvanced = false;
  OneDriveRemoteMatchResult? _oneDriveMatchResult;
  String? _microsoftAuthError;
  List<Map<String, Object?>> _conflicts = const [];

  static const Color _heritageGold = Color(0xFFC9A65A);
  static const Color _heritageCream = Color(0xFFF3E9D1);
  static const Color _panelNavy = Color(0xFF081E33);
  static const Color _cardNavy = Color(0xFF102A40);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final device = await _syncService.initializeDevice();
      await _registerExistingPhotoSources();
      final oneDriveMapping = await _syncService.mapWindowsOneDriveSources();
      await _syncService.registerExistingPhotoRecords();

      final summary = await _syncService.statusSummary();
      final sources = await _syncService.connectedSources();
      final pendingChanges = await _syncService.pendingChanges();
      final syncPlan = await _syncService.buildOutboundSyncPlan();
      final conflicts = await _syncService.openConflicts();

      if (!mounted) return;
      setState(() {
        _currentDevice = device;
        _summary = summary;
        _sources = sources;
        _pendingChanges = pendingChanges;
        _syncPlan = syncPlan;
        _oneDriveMapping = oneDriveMapping;
        _conflicts = conflicts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _backupNow() async {
    if (_backingUp) return;

    setState(() {
      _backingUp = true;
    });

    try {
      final backupPath = await _databaseHelper.createDatabaseBackup(
        reason: 'manual',
      );

      if (!mounted) return;

      if (backupPath == null || backupPath.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup could not be created.')),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Backup Created'),
          content: SelectableText(
            'A fresh backup of your Heirloom Atlas catalog database was created successfully. '
            'Your original photos and files were not copied.\n\n'
            'Backup location:\n$backupPath',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
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
      if (mounted) {
        setState(() {
          _backingUp = false;
        });
      }
    }
  }

  Future<void> _chooseSyncFolder() async {
    if (_choosingSyncFolder) return;
    setState(() => _choosingSyncFolder = true);
    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose Heirloom Atlas Sync Folder',
      );
      if (!mounted || selectedPath == null || selectedPath.trim().isEmpty) {
        return;
      }

      final path = selectedPath.trim();
      final encodedPath = base64Url
          .encode(utf8.encode(path.toLowerCase()))
          .replaceAll('=', '');
      final sourceId = 'sync_folder_$encodedPath';

      await _syncService.registerSource(
        sourceId: sourceId,
        provider: SyncProviderType.localFolder,
        displayName: 'Heirloom Atlas Sync Folder',
        rootIdentifier: sourceId,
        rootPath: path,
        connectionStatus: 'connected',
        capabilitiesJson: jsonEncode({
          'discover': true,
          'index': true,
          'upload': true,
          'move': false,
          'rename': false,
          'delete': false,
          'connection_mode': 'sync_folder',
        }),
      );

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync folder connected: $path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not choose sync folder: $error')),
      );
    } finally {
      if (mounted) setState(() => _choosingSyncFolder = false);
    }
  }

  Future<void> _exportPendingMobileCaptures(Map<String, Object?> source) async {
    if (_exportingMobileCaptures) return;

    final syncFolderPath = source['root_path']?.toString().trim() ?? '';
    if (syncFolderPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The connected sync folder path is missing.'),
        ),
      );
      return;
    }

    setState(() => _exportingMobileCaptures = true);

    try {
      final result = await _syncService.exportPendingAntiquePackages(
        syncFolderPath: syncFolderPath,
      );

      await _load();
      if (!mounted) return;

      final message = result.errors > 0
          ? 'Exported ${result.exported} Antique capture(s). '
                '${result.errors} error(s).'
          : result.exported > 0
          ? 'Exported ${result.exported} Antique capture(s) to the Sync Folder.'
          : 'No pending Antique captures were available to export.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      if (result.errors > 0 && result.lastError.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Mobile Capture Export'),
            content: SelectableText(
              '$message\n\nLast error:\n${result.lastError}',
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export mobile captures: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingMobileCaptures = false);
      }
    }
  }

  Future<void> _startLocalReceiver() async {
    if (_startingLocalReceiver || _localReceiverStatus?.running == true) return;
    setState(() => _startingLocalReceiver = true);
    try {
      final status = await _localNetworkSyncService.startReceiver();
      if (!mounted) return;
      setState(() => _localReceiverStatus = status);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start local receiver: $error')),
      );
    } finally {
      if (mounted) setState(() => _startingLocalReceiver = false);
    }
  }

  Future<void> _stopLocalReceiver() async {
    await _localNetworkSyncService.stopReceiver();
    if (!mounted) return;
    setState(() => _localReceiverStatus = null);
  }

  Widget _buildLocalReceiverPanel() {
    final status = _localReceiverStatus;
    final running = status?.running == true;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.wifi_tethering_outlined,
            title: 'MOBILE LOCAL SYNC',
            subtitle:
                'Private-beta receiver for transfers from the Heirloom Atlas mobile companion on your local network. A pairing token is required.',
          ),
          const SizedBox(height: 14),
          if (running && status != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cardNavy,
                border: Border.all(color: _heritageGold.withValues(alpha: .20)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RECEIVER RUNNING',
                    style: TextStyle(
                      color: _heritageGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: .7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Port: ${status.port}\nPairing token: ${status.pairingToken}',
                    style: const TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'For the Android emulator, Windows is reachable at 10.0.2.2:${status.port}.',
                    style: TextStyle(
                      color: _heritageCream.withValues(alpha: .60),
                      fontSize: 10.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            onPressed: _startingLocalReceiver
                ? null
                : running
                ? _stopLocalReceiver
                : _startLocalReceiver,
            icon: _startingLocalReceiver
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    running
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
            label: Text(
              _startingLocalReceiver
                  ? 'STARTING...'
                  : running
                  ? 'STOP RECEIVER'
                  : 'START LOCAL RECEIVER',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The receiver accepts only authenticated Heirloom Atlas requests. This first test only starts the secured listener; it does not send or import a capture yet.',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .48),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeSyncFolder(Map<String, Object?> source) async {
    final sourceId = source['source_id']?.toString().trim() ?? '';
    final path = source['root_path']?.toString().trim() ?? '';
    if (sourceId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Sync Folder?'),
        content: Text(
          'Remove this folder from Heirloom Atlas Sync?\n\n'
          '${path.isEmpty ? 'Selected sync folder' : path}\n\n'
          'This only removes the connection from Heirloom Atlas. '
          'No files or folders will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _databaseHelper.removeConnectedSource(sourceId);
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync folder removed. No files were deleted.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove sync folder: $error')),
      );
    }
  }

  Widget _buildSyncFolderPanel() {
    final syncFolders = _sources.where((source) {
      final provider = source['provider_type']?.toString().trim() ?? '';
      final capabilities = source['capabilities_json']?.toString() ?? '';
      return provider == 'local_folder' && capabilities.contains('sync_folder');
    }).toList();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.folder_copy_outlined,
            title: 'SYNC FOLDER',
            subtitle:
                'Choose the folder Heirloom Atlas will use for local sync data. '
                'Selecting or removing a folder here never moves or deletes your originals.',
          ),
          const SizedBox(height: 14),
          if (syncFolders.isNotEmpty) ...[
            ...syncFolders.map((source) {
              final path = source['root_path']?.toString().trim() ?? '';

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cardNavy,
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .20),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_outlined,
                      color: _heritageGold,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        path.isEmpty ? 'Sync folder' : path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _heritageCream,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'CONNECTED',
                      style: TextStyle(
                        color: _heritageGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                        letterSpacing: .7,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _exportingMobileCaptures
                          ? null
                          : () => _exportPendingMobileCaptures(source),
                      icon: _exportingMobileCaptures
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.phone_android_outlined, size: 17),
                      label: Text(
                        _exportingMobileCaptures
                            ? 'EXPORTING...'
                            : 'EXPORT MOBILE CAPTURES',
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Remove sync folder',
                      onPressed: () => _removeSyncFolder(source),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: _heritageGold,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
          FilledButton.icon(
            onPressed: _choosingSyncFolder ? null : _chooseSyncFolder,
            icon: _choosingSyncFolder
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.create_new_folder_outlined),
            label: Text(
              _choosingSyncFolder ? 'CHOOSING...' : 'CHOOSE SYNC FOLDER',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectMicrosoftAccount() async {
    if (_microsoftAuthorizing) return;

    if (!_microsoftAuthService.isConfigured) {
      setState(() {
        _microsoftAuthError =
            'Microsoft client ID is not configured yet. '
            'Set HEIRLOOM_ATLAS_MS_CLIENT_ID before launching the app.';
      });
      return;
    }

    setState(() {
      _microsoftAuthorizing = true;
      _microsoftAuthError = null;
    });

    try {
      final session = await _microsoftAuthService.authorizeReadOnly();
      if (!mounted) return;

      setState(() {
        _microsoftSession = session;
        _microsoftAuthError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _microsoftAuthError = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _microsoftAuthorizing = false;
        });
      }
    }
  }

  Future<void> _matchPendingOneDriveItems() async {
    final session = _microsoftSession;
    if (session == null || _oneDriveMatching) return;

    setState(() {
      _oneDriveMatching = true;
      _microsoftAuthError = null;
    });

    try {
      final result = await _syncService.matchPendingOneDrivePhotoItems(
        session: session,
        graphService: _microsoftAuthService,
        limit: 1,
      );

      final pendingChanges = await _syncService.pendingChanges();
      final syncPlan = await _syncService.buildOutboundSyncPlan();

      if (!mounted) return;
      setState(() {
        _oneDriveMatchResult = result;
        _pendingChanges = pendingChanges;
        _syncPlan = syncPlan;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _microsoftAuthError = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _oneDriveMatching = false;
        });
      }
    }
  }

  void _disconnectMicrosoftSession() {
    setState(() {
      _microsoftSession = null;
      _oneDriveMatchResult = null;
      _microsoftAuthError = null;
    });
  }

  Future<void> _registerExistingPhotoSources() async {
    final photoSources = await _databaseHelper.getPhotoSources();

    for (final source in photoSources) {
      final id = source['id'] as int? ?? 0;
      if (id <= 0) continue;

      final sourceType = (source['source_type'] as String? ?? 'local_folder')
          .trim();
      final displayName = (source['display_name'] as String? ?? 'Photo Source')
          .trim();
      final rootPath = (source['root_path'] as String? ?? '').trim();

      final provider = _providerForSourceType(sourceType);
      if (provider == null) continue;

      await _syncService.registerSource(
        sourceId: 'photo_source_$id',
        provider: provider,
        displayName: displayName.isEmpty ? 'Photo Source' : displayName,
        rootIdentifier: 'photo_source_$id',
        rootPath: rootPath,
        connectionStatus: 'indexed',
        capabilitiesJson: jsonEncode({
          'discover': true,
          'index': true,
          'upload': false,
          'move': false,
          'rename': false,
          'delete': false,
          'connection_mode': 'windows_folder',
        }),
      );
    }
  }

  SyncProviderType? _providerForSourceType(String sourceType) {
    switch (sourceType.trim().toLowerCase()) {
      case 'local_folder':
        return SyncProviderType.localFolder;
      case 'onedrive':
        return SyncProviderType.oneDrive;
      case 'google_drive':
        return SyncProviderType.googleDrive;
      case 'icloud':
        return SyncProviderType.iCloud;
      default:
        return null;
    }
  }

  String _providerLabel(String value) {
    switch (value) {
      case 'local_folder':
        return 'Local Folder / This Computer';
      case 'onedrive':
        return 'OneDrive';
      case 'google_drive':
        return 'Google Drive';
      case 'icloud':
        return 'iCloud';
      default:
        return value.isEmpty ? 'Unknown Source' : value;
    }
  }

  String _syncPlanProviderLabel(SyncPlanItem item) {
    if (item.sourceName.trim().isNotEmpty) {
      final provider = _providerLabel(item.providerType);
      return provider == item.sourceName
          ? provider
          : '${item.sourceName} • $provider';
    }
    if (item.providerType.trim().isNotEmpty) {
      return _providerLabel(item.providerType);
    }
    return 'Source not mapped';
  }

  IconData _providerIcon(String value) {
    switch (value) {
      case 'local_folder':
        return Icons.folder_outlined;
      case 'onedrive':
        return Icons.cloud_outlined;
      case 'google_drive':
        return Icons.add_to_drive_outlined;
      case 'icloud':
        return Icons.cloud_queue_outlined;
      default:
        return Icons.storage_outlined;
    }
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .95),
        border: Border.all(
          color: _heritageGold.withValues(alpha: .28),
          width: .8,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _heritageGold, size: 21),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _heritageCream,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .58),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusCard(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _cardNavy,
        border: Border.all(color: _heritageGold.withValues(alpha: .20)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Icon(icon, color: _heritageGold, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _heritageCream.withValues(alpha: .70),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              color: _heritageCream,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 17, 20, 17),
      decoration: BoxDecoration(
        color: _panelNavy,
        border: Border(
          bottom: BorderSide(color: _heritageGold.withValues(alpha: .28)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.folder_copy_outlined,
            color: _heritageGold,
            size: 26,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FILES & BACKUP',
                  style: TextStyle(
                    color: _heritageCream,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Choose where Heirloom Atlas finds your files and protect your catalog.',
                  style: TextStyle(color: Color(0xFFB8C6CF), fontSize: 11.5),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.sync_outlined, size: 17),
            label: const Text('CHECK FOR CHANGES'),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicePanel() {
    final device = _currentDevice;
    final name = device?['display_name']?.toString().trim() ?? '';
    final platform = device?['platform']?.toString().trim() ?? '';
    final deviceId = device?['device_id']?.toString().trim() ?? '';

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.devices_outlined,
            title: 'THIS DEVICE',
            subtitle:
                'Heirloom Atlas now has a stable local device identity for future multi-device sync.',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _cardNavy,
              border: Border.all(color: _heritageGold.withValues(alpha: .20)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.desktop_windows_outlined,
                  color: _heritageGold,
                  size: 27,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'This Computer' : name,
                        style: const TextStyle(
                          color: _heritageCream,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (platform.isNotEmpty) platform,
                          if (deviceId.isNotEmpty) deviceId,
                        ].join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _heritageCream.withValues(alpha: .55),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _heritageGold.withValues(alpha: .30),
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'CURRENT',
                    style: TextStyle(
                      color: _heritageGold,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicrosoftAuthorizationPanel() {
    final configured = _microsoftAuthService.isConfigured;
    final session = _microsoftSession;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.account_circle_outlined,
            title: 'MICROSOFT ACCOUNT',
            subtitle:
                'Read-only authorization for OneDrive identification and remote-item matching. No upload, rename, move, delete, or metadata write permission is requested.',
          ),
          const SizedBox(height: 14),
          if (session != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: _heritageGold,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.accountDisplayName.isEmpty
                            ? 'Microsoft account connected'
                            : session.accountDisplayName,
                        style: const TextStyle(
                          color: _heritageCream,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (session.accountEmail.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          session.accountEmail,
                          style: TextStyle(
                            color: _heritageCream.withValues(alpha: .58),
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Text(
                        'OneDrive: ${session.driveName.isEmpty ? 'Detected' : session.driveName}'
                        '${session.driveType.isEmpty ? '' : ' • ${session.driveType}'}',
                        style: TextStyle(
                          color: _heritageCream.withValues(alpha: .62),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (session.driveId.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Remote drive ID resolved',
                          style: TextStyle(
                            color: _heritageCream.withValues(alpha: .48),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _oneDriveMatching
                                ? null
                                : _matchPendingOneDriveItems,
                            icon: _oneDriveMatching
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.link_outlined),
                            label: Text(
                              _oneDriveMatching
                                  ? 'MATCHING...'
                                  : 'MATCH PENDING ONEDRIVE ITEMS',
                            ),
                          ),
                          Text(
                            'Read-only diagnostic • first pending photo only',
                            style: TextStyle(
                              color: _heritageCream.withValues(alpha: .42),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                      if (_oneDriveMatchResult != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Remote matching: '
                          '${_oneDriveMatchResult!.matched} matched • '
                          '${_oneDriveMatchResult!.alreadyMatched} already linked • '
                          '${_oneDriveMatchResult!.notFound} not found • '
                          '${_oneDriveMatchResult!.errors} errors',
                          style: TextStyle(
                            color: _heritageCream.withValues(alpha: .66),
                            fontSize: 10.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_oneDriveMatchResult!.lastError.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            _oneDriveMatchResult!.lastError,
                            style: const TextStyle(
                              color: Color(0xFFE4A1A1),
                              fontSize: 10.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _disconnectMicrosoftSession,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _heritageGold,
                    side: BorderSide(
                      color: _heritageGold.withValues(alpha: .38),
                    ),
                  ),
                  child: const Text('DISCONNECT'),
                ),
              ],
            ),
          ] else ...[
            Text(
              configured
                  ? 'Heirloom Atlas is ready to request read-only Microsoft authorization.'
                  : 'Microsoft app registration is required before sign-in can begin.',
              style: TextStyle(
                color: _heritageCream.withValues(alpha: .68),
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _microsoftAuthorizing
                  ? null
                  : _connectMicrosoftAccount,
              icon: _microsoftAuthorizing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(
                _microsoftAuthorizing
                    ? 'WAITING FOR MICROSOFT...'
                    : 'CONNECT MICROSOFT ACCOUNT',
              ),
            ),
            if (!configured) ...[
              const SizedBox(height: 8),
              Text(
                'Configuration key: HEIRLOOM_ATLAS_MS_CLIENT_ID',
                style: TextStyle(
                  color: _heritageCream.withValues(alpha: .42),
                  fontSize: 10.5,
                ),
              ),
            ],
          ],
          if (_microsoftAuthError != null) ...[
            const SizedBox(height: 12),
            Text(
              _microsoftAuthError!,
              style: const TextStyle(
                color: Color(0xFFE4A1A1),
                fontSize: 10.8,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'This first authorization is session-only. Tokens are not persisted to disk yet.',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .46),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOneDriveMappingPanel() {
    final mapping = _oneDriveMapping;
    if (mapping == null) return const SizedBox.shrink();

    final detected = mapping.oneDriveDetected;
    final mapped = mapping.mappedSources;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.cloud_queue_outlined,
            title: 'ONEDRIVE MAPPING',
            subtitle:
                'Heirloom Atlas can identify which indexed folders belong to the OneDrive tree on this computer. This does not authorize cloud writes.',
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                detected ? Icons.check_circle_outline : Icons.info_outline,
                color: _heritageGold,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detected
                          ? 'OneDrive detected on this computer'
                          : 'OneDrive folder not detected',
                      style: const TextStyle(
                        color: _heritageCream,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detected
                          ? '$mapped indexed source(s) mapped to OneDrive. '
                                'The next provider step will authorize the Microsoft account and resolve remote item IDs.'
                          : 'No Windows OneDrive root was found in the current environment. '
                                'Existing sources remain unchanged.',
                      style: TextStyle(
                        color: _heritageCream.withValues(alpha: .62),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    if (mapping.detectedRoots.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...mapping.detectedRoots.map(
                        (root) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            root,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _heritageCream.withValues(alpha: .48),
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .28),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  detected ? 'LOCAL MAP READY' : 'NOT DETECTED',
                  style: const TextStyle(
                    color: _heritageGold,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Safety: mapping is read-only. No file is uploaded, moved, renamed, deleted, or marked synced.',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .48),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFileLocationDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add File Location'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Where are the files you want Heirloom Atlas to catalog?',
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('OneDrive'),
                subtitle: const Text(
                  'Choose a OneDrive folder available on this computer.',
                ),
                onTap: () => Navigator.pop(dialogContext, 'onedrive'),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_queue_outlined),
                title: const Text('iCloud'),
                subtitle: const Text(
                  'Choose an iCloud folder available on this computer.',
                ),
                onTap: () => Navigator.pop(dialogContext, 'icloud'),
              ),
              ListTile(
                leading: const Icon(Icons.add_to_drive_outlined),
                title: const Text('Google Drive'),
                subtitle: const Text(
                  'Choose a Google Drive folder available on this computer.',
                ),
                onTap: () => Navigator.pop(dialogContext, 'google_drive'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('This Computer / External Drive'),
                subtitle: const Text(
                  'Choose a local, USB, external, or network folder.',
                ),
                onTap: () => Navigator.pop(dialogContext, 'local_folder'),
              ),
              ListTile(
                enabled: false,
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Google Photos'),
                subtitle: const Text(
                  'Cloud selection — coming in a future beta.',
                ),
                trailing: const Text('COMING SOON'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    await _addMediaSourceFolder(preferredSourceType: choice);
  }

  Future<void> _addMediaSourceFolder({String? preferredSourceType}) async {
    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose a photo or video source folder',
      );
      if (!mounted || selectedPath == null || selectedPath.trim().isEmpty) {
        return;
      }

      final selected = selectedPath.trim();
      final lower = selected.toLowerCase();
      final sourceType =
          preferredSourceType ??
          (lower.contains('onedrive')
              ? 'onedrive'
              : lower.contains('icloud')
              ? 'icloud'
              : lower.contains('google drive')
              ? 'google_drive'
              : 'local_folder');

      final displayName = sourceType == 'onedrive'
          ? 'OneDrive'
          : sourceType == 'icloud'
          ? 'iCloud'
          : sourceType == 'google_drive'
          ? 'Google Drive'
          : 'Local / External Folder';

      final existingPhotoSources = await _databaseHelper.getPhotoSources();
      final alreadyExists = existingPhotoSources.any((source) {
        final root = (source['root_path'] as String? ?? '').trim();
        return root.toLowerCase() == selected.toLowerCase();
      });

      if (!alreadyExists) {
        await _databaseHelper.addPhotoSource(
          sourceType: sourceType,
          displayName: displayName,
          rootPath: selected,
        );
      }

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Media source connected. Original files were not moved or changed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add media source: $error')),
      );
    }
  }

  Future<void> _removeConnectedSource(Map<String, Object?> source) async {
    final sourceId = source['source_id']?.toString().trim() ?? '';
    final displayName = source['display_name']?.toString().trim() ?? '';
    final rootPath = source['root_path']?.toString().trim() ?? '';

    if (sourceId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This source could not be removed because its ID is missing.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Source?'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName.isEmpty ? 'Connected source' : displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (rootPath.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(rootPath),
              ],
              const SizedBox(height: 14),
              const Text(
                'This removes the connection from Heirloom Atlas only. '
                'No original files or folders will be deleted, moved, or changed.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REMOVE SOURCE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      var photoSourceRemoved = false;

      final photoSourceMatch = RegExp(
        r'^photo_source_(\d+)$',
      ).firstMatch(sourceId);
      if (photoSourceMatch != null) {
        final photoSourceId = int.tryParse(photoSourceMatch.group(1) ?? '');
        if (photoSourceId != null && photoSourceId > 0) {
          await _databaseHelper.removePhotoSource(photoSourceId);
          photoSourceRemoved = true;
        }
      }

      // Cloud mapping can change the connected-source ID, so fall back to
      // matching the underlying photo source by its cataloged root path.
      if (!photoSourceRemoved && rootPath.isNotEmpty) {
        await _databaseHelper.removePhotoSourceByRootPath(rootPath);
      }

      await _databaseHelper.removeConnectedSource(sourceId);
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Source removed from Heirloom Atlas. No original files were deleted.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove source: $error')),
      );
    }
  }

  Widget _buildFoundationPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.schema_outlined,
            title: 'SYNC FOUNDATION',
            subtitle:
                'The local database now tracks sources, records, changes, devices, and conflicts independently of any one cloud provider.',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 650;
              final cards = [
                _statusCard(
                  'Devices',
                  _summary['devices'] ?? 0,
                  Icons.devices_outlined,
                ),
                _statusCard(
                  'Sources',
                  _summary['connected_sources'] ?? 0,
                  Icons.cloud_outlined,
                ),
                _statusCard(
                  'Sync Records',
                  _summary['sync_records'] ?? 0,
                  Icons.link_outlined,
                ),
                _statusCard(
                  'Pending Changes',
                  _summary['pending_changes'] ?? 0,
                  Icons.pending_actions_outlined,
                ),
                _statusCard(
                  'Open Conflicts',
                  _summary['open_conflicts'] ?? 0,
                  Icons.rule_folder_outlined,
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cards
                    .map(
                      (card) => SizedBox(
                        width: (constraints.maxWidth - 16) / 3,
                        child: card,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _fileNameFromPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  List<String> _changedFields(Map<String, Object?> change) {
    final raw = change['details_json']?.toString().trim() ?? '';
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      final fields = decoded is Map ? decoded['changed_fields'] : null;
      if (fields is! List) return const [];
      return fields
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Widget _pendingThumbnail({required String entity, required String localKey}) {
    if (entity == 'photo' && localKey.trim().isNotEmpty) {
      final file = File(localKey);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.file(
            file,
            width: 58,
            height: 58,
            fit: BoxFit.cover,
            cacheWidth: 160,
            errorBuilder: (context, error, stackTrace) =>
                _pendingFallbackIcon(entity),
          ),
        );
      }
    }

    return _pendingFallbackIcon(entity);
  }

  Widget _pendingFallbackIcon(String entity) {
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _panelNavy,
        border: Border.all(color: _heritageGold.withValues(alpha: .20)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Icon(
        entity == 'photo' ? Icons.photo_outlined : Icons.edit_note_outlined,
        color: _heritageGold,
        size: 24,
      ),
    );
  }

  IconData _syncPlanReadinessIcon(SyncPlanReadiness readiness) {
    switch (readiness) {
      case SyncPlanReadiness.readyForProvider:
        return Icons.check_circle_outline;
      case SyncPlanReadiness.needsSourceMapping:
        return Icons.link_off_outlined;
      case SyncPlanReadiness.needsProviderConnection:
        return Icons.cloud_off_outlined;
      case SyncPlanReadiness.blockedBySafety:
        return Icons.shield_outlined;
      case SyncPlanReadiness.unsupported:
        return Icons.help_outline;
    }
  }

  Widget _buildSyncPlanPanel() {
    final plan = _syncPlan;
    if (plan == null) return const SizedBox.shrink();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.route_outlined,
            title: 'SYNC PLAN',
            subtitle: plan.items.isEmpty
                ? 'No outbound work is currently planned.'
                : 'Preview only. Heirloom Atlas has classified what would need to happen next; nothing is sent from this plan.',
          ),
          const SizedBox(height: 14),
          if (plan.items.isEmpty)
            Text(
              'There are no pending changes to plan.',
              style: TextStyle(color: _heritageCream.withValues(alpha: .65)),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _statusCard(
                    'Planned',
                    plan.summary.items,
                    Icons.route_outlined,
                  ),
                  _statusCard(
                    'Provider Ready',
                    plan.summary.readyForProvider,
                    Icons.cloud_done_outlined,
                  ),
                  _statusCard(
                    'Needs Connection',
                    plan.summary.needsProviderConnection,
                    Icons.cloud_off_outlined,
                  ),
                  _statusCard(
                    'Needs Mapping',
                    plan.summary.needsSourceMapping,
                    Icons.link_off_outlined,
                  ),
                  _statusCard(
                    'Safety Blocked',
                    plan.summary.blockedBySafety,
                    Icons.shield_outlined,
                  ),
                ];

                if (constraints.maxWidth < 650) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: (constraints.maxWidth - 16) / 3,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 14),
            ...plan.items.take(12).map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _cardNavy,
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .18),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _syncPlanReadinessIcon(item.readiness),
                      color: _heritageGold,
                      size: 21,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.entityType == 'photo'
                                ? _fileNameFromPath(item.localKey)
                                : item.localKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _heritageCream,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.action.label,
                            style: const TextStyle(
                              color: _heritageGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _syncPlanProviderLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _heritageCream.withValues(alpha: .62),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.changedFields.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Fields: ${item.changedFields.join(', ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _heritageCream.withValues(alpha: .52),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            item.reason,
                            style: TextStyle(
                              color: _heritageCream.withValues(alpha: .48),
                              fontSize: 10.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _heritageGold.withValues(alpha: .25),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.readiness.label.toUpperCase(),
                        style: const TextStyle(
                          color: _heritageGold,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (plan.items.length > 12)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${plan.items.length - 12} more planned item(s) are waiting. '
                  'This preview intentionally shows the first 12.',
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .48),
                    fontSize: 10.5,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingChangesPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.pending_actions_outlined,
            title: 'PENDING CHANGES',
            subtitle: _pendingChanges.isEmpty
                ? 'No local edits are waiting in the sync queue.'
                : 'Local edits waiting to sync. Repeated edits to the same item are combined here.',
          ),
          const SizedBox(height: 14),
          if (_pendingChanges.isEmpty)
            Text(
              'Everything currently tracked is caught up locally.',
              style: TextStyle(color: _heritageCream.withValues(alpha: .65)),
            )
          else
            ..._pendingChanges.take(25).map((change) {
              final localKey = change['local_key']?.toString() ?? '';
              final entity = change['entity_type']?.toString() ?? '';
              final fields = _changedFields(change);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _cardNavy,
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .18),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  children: [
                    _pendingThumbnail(entity: entity, localKey: localKey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entity == 'photo'
                                ? _fileNameFromPath(localKey)
                                : localKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _heritageCream,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fields.isEmpty
                                ? 'Local change'
                                : 'Changed: ${fields.join(', ')}',
                            style: const TextStyle(
                              color: _heritageGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_outlined,
                                size: 13,
                                color: _heritageCream.withValues(alpha: .48),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Waiting to sync',
                                style: TextStyle(
                                  color: _heritageCream.withValues(alpha: .55),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildConflictPanel() {
    if (_conflicts.isEmpty) return const SizedBox.shrink();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.warning_amber_outlined,
            title: 'OPEN CONFLICTS',
            subtitle:
                'Conflicts are held for review instead of silently overwriting one copy with another.',
          ),
          const SizedBox(height: 12),
          ..._conflicts
              .take(10)
              .map(
                (conflict) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.rule_folder_outlined,
                    color: _heritageGold,
                  ),
                  title: Text(
                    conflict['entity_type']?.toString() ?? 'Record',
                    style: const TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    conflict['local_key']?.toString() ?? '',
                    style: TextStyle(
                      color: _heritageCream.withValues(alpha: .55),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildAdvancedToggle() {
    return _panel(
      child: InkWell(
        onTap: () => setState(() => _showAdvanced = !_showAdvanced),
        child: Row(
          children: [
            const Icon(Icons.tune_outlined, color: _heritageGold, size: 20),
            const SizedBox(width: 9),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ADVANCED',
                    style: TextStyle(
                      color: _heritageCream,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Sync folders, device setup, provider mapping, and diagnostics.',
                    style: TextStyle(color: Color(0xFF9EADB8), fontSize: 10.8),
                  ),
                ],
              ),
            ),
            Icon(
              _showAdvanced ? Icons.expand_less : Icons.expand_more,
              color: _heritageGold,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _localNetworkSyncService.stopReceiver();
    super.dispose();
  }

  bool _isSyncFolderSource(Map<String, Object?> source) {
    final provider =
        source['provider_type']?.toString().trim().toLowerCase() ?? '';
    final capabilities =
        source['capabilities_json']?.toString().toLowerCase() ?? '';
    final sourceId = source['source_id']?.toString().toLowerCase() ?? '';
    final displayName =
        source['display_name']?.toString().trim().toLowerCase() ?? '';
    final rootPath = source['root_path']?.toString().trim().toLowerCase() ?? '';

    return capabilities.contains('sync_folder') ||
        sourceId.startsWith('sync_folder_') ||
        displayName == 'heirloom atlas sync folder' ||
        rootPath.endsWith(r'\heirloom atlas sync') ||
        (provider == 'local_folder' &&
            rootPath.contains(r'\heirloom atlas sync\'));
  }

  Widget _buildFilesIntroPanel() {
    return _panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: _heritageGold, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR FILES STAY WHERE THEY ARE',
                  style: TextStyle(
                    color: _heritageCream,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Heirloom Atlas catalogs your existing files without moving the originals. '
                  'You choose where they live.',
                  style: TextStyle(
                    color: _heritageCream.withValues(alpha: .65),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Your collection is yours. Not ours.',
                  style: TextStyle(
                    color: _heritageGold,
                    fontSize: 10.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _simpleSourceTypeLabel(String provider, String rootPath) {
    switch (provider.trim().toLowerCase()) {
      case 'onedrive':
      case 'google_drive':
      case 'icloud':
        return 'Cloud storage';
      case 'local_folder':
        final lower = rootPath.toLowerCase();
        if (lower.startsWith(r'\\') ||
            RegExp(r'^[d-z]:\\', caseSensitive: false).hasMatch(rootPath)) {
          return 'External or network storage';
        }
        return 'This computer';
      default:
        return 'File location';
    }
  }

  Widget _buildSimpleSourcesPanel() {
    final visibleSources = _sources
        .where((source) => !_isSyncFolderSource(source))
        .toList();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.folder_outlined,
            title: 'YOUR FILES',
            subtitle:
                'These are the folders Heirloom Atlas catalogs. Changes to these folders are watched automatically while Heirloom Atlas is running.',
          ),
          const SizedBox(height: 14),
          if (visibleSources.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardNavy,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'No file locations have been added yet.',
                style: TextStyle(color: _heritageCream.withValues(alpha: .65)),
              ),
            )
          else
            ...visibleSources.map((source) {
              final provider = source['provider_type']?.toString().trim() ?? '';
              final displayName =
                  source['display_name']?.toString().trim() ?? '';
              final rootPath = source['root_path']?.toString().trim() ?? '';
              final localPath =
                  rootPath.isNotEmpty &&
                  (provider == 'local_folder' ||
                      provider == 'onedrive' ||
                      provider == 'google_drive' ||
                      provider == 'icloud');
              final available = !localPath || Directory(rootPath).existsSync();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _cardNavy,
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .18),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  children: [
                    Icon(
                      _providerIcon(provider),
                      color: _heritageGold,
                      size: 23,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName.isEmpty
                                ? _providerLabel(provider)
                                : displayName,
                            style: const TextStyle(
                              color: _heritageCream,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              _simpleSourceTypeLabel(provider, rootPath),
                              if (rootPath.isNotEmpty) rootPath,
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _heritageCream.withValues(alpha: .50),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      available
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_outlined,
                      color: available
                          ? _heritageGold
                          : const Color(0xFFE4A1A1),
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      available ? 'WATCHING FOR CHANGES' : 'SOURCE UNAVAILABLE',
                      style: TextStyle(
                        color: available
                            ? _heritageGold
                            : const Color(0xFFE4A1A1),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .45,
                      ),
                    ),
                    const SizedBox(width: 5),
                    IconButton(
                      tooltip: 'Remove this file location',
                      onPressed: () => _removeConnectedSource(source),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: _heritageGold,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 5),
          FilledButton.icon(
            onPressed: _showAddFileLocationDialog,
            icon: const Icon(Icons.add),
            label: const Text('ADD FILE LOCATION'),
          ),
          const SizedBox(height: 8),
          Text(
            'OneDrive, iCloud, Google Drive, local folders, external drives, and other folders available on this computer can be added here. '
            'Google Photos cloud selection is planned for a future beta.',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .48),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.backup_outlined,
            title: 'PROTECT YOUR HEIRLOOM ATLAS CATALOG',
            subtitle:
                'Create a safety copy of the information Heirloom Atlas stores about your collection.',
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _cardNavy,
              border: Border.all(color: _heritageGold.withValues(alpha: .18)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: _heritageGold,
                  size: 24,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Back up your catalog database',
                        style: TextStyle(
                          color: _heritageCream.withValues(alpha: .90),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This saves a copy of the Heirloom Atlas database — the catalog information used for your photos, people, collections, organization, metadata, and app records. '
                        'It does not copy or duplicate your original photos, videos, documents, or other source files.',
                        style: TextStyle(
                          color: _heritageCream.withValues(alpha: .68),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Useful before large imports, duplicate cleanup, bulk edits, or other major changes.',
                        style: TextStyle(
                          color: _heritageCream.withValues(alpha: .50),
                          fontSize: 10.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loading || _backingUp ? null : _backupNow,
                  icon: _backingUp
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined, size: 17),
                  label: Text(_backingUp ? 'BACKING UP...' : 'BACK UP NOW'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherDevicesPanel() {
    final syncFolders = _sources
        .where((source) => _isSyncFolderSource(source))
        .toList();
    final syncFolder = syncFolders.isEmpty ? null : syncFolders.first;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.phone_android_outlined,
            title: 'OTHER DEVICES',
            subtitle:
                'Mobile transfer and multi-device synchronization are being tested during the private beta.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (syncFolder != null)
                OutlinedButton.icon(
                  onPressed: _exportingMobileCaptures
                      ? null
                      : () => _exportPendingMobileCaptures(syncFolder),
                  icon: const Icon(Icons.phone_android_outlined, size: 17),
                  label: Text(
                    _exportingMobileCaptures
                        ? 'EXPORTING...'
                        : 'EXPORT MOBILE CAPTURES',
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: .28),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'PRIVATE BETA',
                  style: TextStyle(
                    color: _heritageGold,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Setup and diagnostic controls for sync folders, pairing, and the local receiver are available under Advanced.',
            style: TextStyle(
              color: _heritageCream.withValues(alpha: .48),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061725),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: _heritageGold,
                            size: 38,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Files & Backup could not load.\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _heritageCream),
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      _buildFilesIntroPanel(),
                      const SizedBox(height: 12),
                      _buildSimpleSourcesPanel(),
                      const SizedBox(height: 12),
                      _buildBackupPanel(),
                      const SizedBox(height: 12),
                      _buildOtherDevicesPanel(),
                      const SizedBox(height: 12),
                      _buildAdvancedToggle(),
                      if (_showAdvanced) ...[
                        const SizedBox(height: 12),
                        _buildSyncFolderPanel(),
                        const SizedBox(height: 12),
                        _buildLocalReceiverPanel(),
                        const SizedBox(height: 12),
                        _buildDevicePanel(),
                        const SizedBox(height: 12),
                        _buildMicrosoftAuthorizationPanel(),
                        const SizedBox(height: 12),
                        _buildOneDriveMappingPanel(),
                        const SizedBox(height: 12),
                        _buildFoundationPanel(),
                        const SizedBox(height: 12),
                        _buildSyncPlanPanel(),
                        const SizedBox(height: 12),
                        _buildPendingChangesPanel(),
                        const SizedBox(height: 12),
                        _buildConflictPanel(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
