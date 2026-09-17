import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../database/database_helper.dart';
import '../../models/family_person.dart';
import '../../models/antique.dart';
import '../../models/document_record.dart';
import '../../services/document_page_service.dart';
import '../../services/local_network_sync_client.dart';

class MobileCaptureHome extends StatefulWidget {
  const MobileCaptureHome({super.key});

  @override
  State<MobileCaptureHome> createState() => _MobileCaptureHomeState();
}

class _MobileCaptureHomeState extends State<MobileCaptureHome> {
  @override
  void initState() {
    super.initState();
    LocalNetworkSyncClient.restoreStoredPairing();
  }

  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: _cream,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HEIRLOOM ATLAS',
                style: TextStyle(
                    color: _cream,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
            Text('CAPTURE COMPANION',
                style: TextStyle(
                    color: _gold,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _panel.withValues(alpha: .92),
                border: Border.all(color: _gold.withValues(alpha: .28)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preserve it while it is in front of you.',
                      style: TextStyle(
                          color: _cream,
                          fontSize: 23,
                          fontWeight: FontWeight.w900)),
                  SizedBox(height: 8),
                  Text(
                    'Capture the item, connect the person, and preserve the story. '
                    'Finish detailed organizing on the computer later.',
                    style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('CAPTURE',
                style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5)),
            const SizedBox(height: 12),
            _CaptureTile(
              icon: Icons.camera_alt_outlined,
              title: 'Photograph an Item',
              subtitle: 'Heirloom, antique, coin, card, or other family object',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _ItemCaptureFlow(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _CaptureTile(
              icon: Icons.document_scanner_outlined,
              title: 'Scan Photo / Document',
              subtitle: 'Capture one or many pages as a single document',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _DocumentCaptureFlow(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _CaptureTile(
              icon: Icons.mic_none_outlined,
              title: 'Record a Story',
              subtitle: 'Preserve someone telling the memory in their own voice',
              onTap: () => _comingNext(context, 'Voice story recording'),
            ),
            const SizedBox(height: 12),
            _CaptureTile(
              icon: Icons.person_search_outlined,
              title: 'Find a Person',
              subtitle: 'Search the Family Tree',
              onTap: () async {
                final person = await _chooseFamilyPerson(context);
                if (!context.mounted || person == null) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Selected ${person.displayName}')),
                );
              },
            ),
            const SizedBox(height: 28),
            const Text('SYNC',
                style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5)),
            const SizedBox(height: 12),
            _CaptureTile(
              icon: Icons.wifi_tethering_outlined,
              title: 'Connect to Windows',
              subtitle: 'Pair this mobile companion with your Heirloom Atlas computer',
              onTap: () => _showWindowsPairingDialog(context),
            ),
            const SizedBox(height: 12),
            _CaptureTile(
              icon: Icons.sync_outlined,
              title: 'Retry Pending Captures',
              subtitle: 'Send Antique captures that are still waiting for Windows',
              onTap: () => _retryPendingAntiques(context),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _panel.withValues(alpha: .55),
                border: Border.all(color: _gold.withValues(alpha: .18)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: _gold, size: 21),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Safe by default. This mobile companion will sync captures '
                      'to the Windows archive without moving or deleting originals.',
                      style:
                          TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showWindowsPairingDialog(BuildContext context) async {
    final hostController = TextEditingController(text: '10.0.2.2');
    final portController = TextEditingController(text: '47831');
    final tokenController = TextEditingController();
    final client = LocalNetworkSyncClient();
    var checking = false;
    String? resultMessage;
    bool? resultOk;

    await showDialog<void>(
      context: context,
      barrierDismissible: !checking,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> check() async {
            if (checking) return;
            final port = int.tryParse(portController.text.trim());
            if (port == null) {
              setDialogState(() {
                resultOk = false;
                resultMessage = 'Enter the receiver port shown on Windows.';
              });
              return;
            }

            setDialogState(() {
              checking = true;
              resultMessage = null;
              resultOk = null;
            });

            final result = await client.checkPairing(
              host: hostController.text,
              port: port,
              pairingToken: tokenController.text,
            );

            if (!dialogContext.mounted) return;
            setDialogState(() {
              checking = false;
              resultOk = result.ok;
              resultMessage = result.message;
            });
          }

          return AlertDialog(
            title: const Text('Connect to Windows'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Start the Mobile Local Sync receiver on Windows, then enter the pairing information shown there.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: hostController,
                    decoration: const InputDecoration(
                      labelText: 'Windows address',
                      helperText: 'Android emulator: 10.0.2.2',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tokenController,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Pairing token',
                      hintText: 'XXXX-XXXX-XXXX',
                    ),
                  ),
                  if (resultMessage != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          resultOk == true
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: resultOk == true ? Colors.green : Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(resultMessage!)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: checking ? null : () => Navigator.pop(dialogContext),
                child: const Text('CLOSE'),
              ),
              FilledButton.icon(
                onPressed: checking ? null : check,
                icon: checking
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(checking ? 'CONNECTING...' : 'TEST CONNECTION'),
              ),
            ],
          );
        },
      ),
    );

    // Let Flutter finish dismissing the dialog before disposing the
    // controllers used by its text fields. Disposing immediately after
    // showDialog returns can race the dialog route teardown in debug mode.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    hostController.dispose();
    portController.dispose();
    tokenController.dispose();
  }

  static Future<void> _retryPendingAntiques(BuildContext context) async {
    await LocalNetworkSyncClient.restoreStoredPairing();
    if (!context.mounted) return;
    if (!LocalNetworkSyncClient.hasActivePairing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pair with Windows first.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('Retrying pending mobile captures...')),
          ],
        ),
      ),
    );

    var sent = 0;
    var skipped = 0;
    String? lastError;

    try {
      final db = DatabaseHelper.instance;
      final pending = await db.getPendingSyncChanges(limit: 100);
      final database = await db.database;

      for (final change in pending) {
        final entityType = change['entity_type']?.toString() ?? '';
        final operation = change['operation']?.toString().toLowerCase() ?? '';
        if (operation != 'create' && operation != 'insert') continue;

        final changeUuid = change['change_uuid']?.toString().trim() ?? '';
        final localKey = change['local_key']?.toString().trim() ?? '';
        if (changeUuid.isEmpty || localKey.isEmpty) {
          skipped++;
          continue;
        }

        if (entityType == 'antique') {
          final antiqueId = int.tryParse(localKey);
          if (antiqueId == null) {
            skipped++;
            continue;
          }

          final antiqueRows = await database.query(
            'antiques',
            where: 'id = ?',
            whereArgs: [antiqueId],
            limit: 1,
          );
          if (antiqueRows.isEmpty) {
            skipped++;
            continue;
          }

          final imageRows = await database.query(
            'antique_images',
            columns: ['image_path'],
            where: 'antique_id = ?',
            whereArgs: [antiqueId],
            orderBy: 'sort_order ASC, id ASC',
            limit: 1,
          );
          if (imageRows.isEmpty) {
            skipped++;
            continue;
          }

          final antiqueRow = antiqueRows.first;
          final imagePath =
              imageRows.first['image_path']?.toString().trim() ?? '';
          if (imagePath.isEmpty) {
            skipped++;
            continue;
          }

          final syncRows = await database.query(
            'sync_records',
            columns: ['record_uuid'],
            where: 'entity_type = ? AND local_key = ?',
            whereArgs: ['antique', localKey],
            orderBy: 'id DESC',
            limit: 1,
          );
          final recordUuid = syncRows.isEmpty
              ? 'antique_retry_$changeUuid'
              : (syncRows.first['record_uuid']?.toString().trim() ??
                  'antique_retry_$changeUuid');

          final result = await LocalNetworkSyncClient().sendAntique(
            changeUuid: changeUuid,
            recordUuid: recordUuid,
            title: antiqueRow['title']?.toString() ?? '',
            description: antiqueRow['description']?.toString() ?? '',
            notes: antiqueRow['notes']?.toString() ?? '',
            imagePath: imagePath,
          );

          if (!result.ok) {
            lastError = result.message;
            break;
          }

          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'antique',
            localKey: localKey,
            localModifiedMilliseconds: DateTime.now().millisecondsSinceEpoch,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
          sent++;
          continue;
        }

        if (entityType == 'sports_card') {
          Map<String, dynamic> details = <String, dynamic>{};
          final detailsText = change['details_json']?.toString() ?? '';
          if (detailsText.isNotEmpty) {
            try {
              final decoded = jsonDecode(detailsText);
              if (decoded is Map) {
                details = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          }

          final frontImagePath =
              details['front_image_path']?.toString().trim() ?? '';
          if (frontImagePath.isEmpty || !await File(frontImagePath).exists()) {
            skipped++;
            continue;
          }

          final syncRows = await database.query(
            'sync_records',
            columns: ['record_uuid'],
            where: 'entity_type = ? AND local_key = ?',
            whereArgs: ['sports_card', localKey],
            orderBy: 'id DESC',
            limit: 1,
          );
          final recordUuid = syncRows.isEmpty
              ? localKey
              : (syncRows.first['record_uuid']?.toString().trim() ?? localKey);

          final result = await LocalNetworkSyncClient().sendSportsCard(
            changeUuid: changeUuid,
            recordUuid: recordUuid,
            player: details['player']?.toString() ?? '',
            year: details['year']?.toString() ?? '',
            brand: details['brand']?.toString() ?? '',
            setName: details['set_name']?.toString() ?? '',
            cardNumber: details['card_number']?.toString() ?? '',
            condition: details['condition']?.toString() ?? '',
            storageLocation: details['storage_location']?.toString() ?? '',
            notes: details['notes']?.toString() ?? '',
            frontImagePath: frontImagePath,
            backImagePath: details['back_image_path']?.toString() ?? '',
            sport: details['sport']?.toString() ?? 'Baseball',
            team: details['team']?.toString() ?? '',
          );

          if (!result.ok) {
            lastError = result.message;
            break;
          }

          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'sports_card',
            localKey: localKey,
            localModifiedMilliseconds: DateTime.now().millisecondsSinceEpoch,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
          sent++;
          continue;
        }

        if (entityType == 'document') {
          final documentId = int.tryParse(localKey);
          if (documentId == null) {
            skipped++;
            continue;
          }

          final documentRows = await database.query(
            'documents',
            where: 'id = ?',
            whereArgs: [documentId],
            limit: 1,
          );
          if (documentRows.isEmpty) {
            skipped++;
            continue;
          }

          final pageRows = await database.query(
            'document_pages',
            columns: ['file_path'],
            where: 'document_id = ?',
            whereArgs: [documentId],
            orderBy: 'page_index ASC, id ASC',
          );
          final pagePaths = pageRows
              .map((row) => row['file_path']?.toString().trim() ?? '')
              .where((value) => value.isNotEmpty)
              .toList();
          if (pagePaths.isEmpty) {
            skipped++;
            continue;
          }

          final syncRows = await database.query(
            'sync_records',
            columns: ['record_uuid'],
            where: 'entity_type = ? AND local_key = ?',
            whereArgs: ['document', localKey],
            orderBy: 'id DESC',
            limit: 1,
          );
          final recordUuid = syncRows.isEmpty
              ? 'document_retry_$changeUuid'
              : (syncRows.first['record_uuid']?.toString().trim() ??
                  'document_retry_$changeUuid');
          final documentRow = documentRows.first;

          final result = await LocalNetworkSyncClient().sendDocument(
            changeUuid: changeUuid,
            recordUuid: recordUuid,
            title: documentRow['title']?.toString() ?? '',
            documentDate: documentRow['document_date']?.toString() ?? '',
            documentType: documentRow['document_type']?.toString() ?? '',
            people: documentRow['people']?.toString() ?? '',
            description: documentRow['description']?.toString() ?? '',
            source: documentRow['source']?.toString() ?? '',
            pagePaths: pagePaths,
          );

          if (!result.ok) {
            lastError = result.message;
            break;
          }

          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'document',
            localKey: localKey,
            localModifiedMilliseconds: DateTime.now().millisecondsSinceEpoch,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
          sent++;
          continue;
        }

        if (entityType == 'coin') {
          Map<String, dynamic> details = <String, dynamic>{};
          final detailsText = change['details_json']?.toString() ?? '';
          if (detailsText.isNotEmpty) {
            try {
              final decoded = jsonDecode(detailsText);
              if (decoded is Map) {
                details = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          }

          final frontImagePath =
              details['front_image_path']?.toString().trim() ?? '';
          if (frontImagePath.isEmpty || !await File(frontImagePath).exists()) {
            skipped++;
            continue;
          }

          final syncRows = await database.query(
            'sync_records',
            columns: ['record_uuid'],
            where: 'entity_type = ? AND local_key = ?',
            whereArgs: ['coin', localKey],
            orderBy: 'id DESC',
            limit: 1,
          );
          final recordUuid = syncRows.isEmpty
              ? localKey
              : (syncRows.first['record_uuid']?.toString().trim() ?? localKey);

          final result = await LocalNetworkSyncClient().sendCoin(
            changeUuid: changeUuid,
            recordUuid: recordUuid,
            category: details['category']?.toString() ?? '',
            series: details['series']?.toString() ?? '',
            year: details['year']?.toString() ?? '',
            mint: details['mint']?.toString() ?? '',
            variety: details['variety']?.toString() ?? '',
            grade: details['grade']?.toString() ?? '',
            storageLocation: details['storage_location']?.toString() ?? '',
            notes: details['notes']?.toString() ?? '',
            frontImagePath: frontImagePath,
            backImagePath: details['back_image_path']?.toString() ?? '',
          );

          if (!result.ok) {
            lastError = result.message;
            break;
          }

          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'coin',
            localKey: localKey,
            localModifiedMilliseconds: DateTime.now().millisecondsSinceEpoch,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
          sent++;
        }
      }
    } catch (error) {
      lastError = 'Retry failed: $error';
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(lastError == null ? 'Retry complete' : 'Retry stopped'),
        content: Text(
          lastError == null
              ? sent == 0
                  ? 'No pending mobile captures were ready to send.'
                  : 'Sent $sent pending capture${sent == 1 ? '' : 's'} to Windows.${skipped > 0 ? '\n\nSkipped: $skipped' : ''}'
              : '$lastError\n\nSuccessfully sent before the error: $sent.${skipped > 0 ? '\nSkipped: $skipped' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _comingNext(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is the next mobile capture step.')),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel.withValues(alpha: .90),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: _gold.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: _gold.withValues(alpha: .40)),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(icon, color: _gold, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _cream,
                            fontSize: 17,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: _muted, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _gold),
            ],
          ),
        ),
      ),
    );
  }
}


class _DocumentCaptureFlow extends StatefulWidget {
  const _DocumentCaptureFlow();

  @override
  State<_DocumentCaptureFlow> createState() => _DocumentCaptureFlowState();
}

class _DocumentCaptureFlowState extends State<_DocumentCaptureFlow> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  final ImagePicker _imagePicker = ImagePicker();
  final List<XFile> _pages = [];
  bool _capturing = false;

  Future<void> _capturePage() async {
    if (_capturing) return;

    setState(() => _capturing = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (!mounted || image == null) return;

      setState(() => _pages.add(image));

      await _askForAnotherPage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture the page. $error')),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _askForAnotherPage() async {
    final pageNumber = _pages.length;

    final scanAnother = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Page $pageNumber captured'),
        content: const Text('Is there another page?'),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, false),
            icon: const Icon(Icons.check),
            label: const Text('Finish Document'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan Next Page'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (scanAnother == true) {
      await _capturePage();
    }
  }

  void _removePage(int index) {
    setState(() => _pages.removeAt(index));
  }

  void _finish() {
    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan at least one page first.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DocumentDetailsScreen(
          pagePaths: _pages.map((page) => page.path).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: _cream,
        title: const Text(
          'SCAN DOCUMENT',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _panel.withValues(alpha: .92),
                border: Border.all(color: _gold.withValues(alpha: .28)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'One document. As many pages as you need.',
                    style: TextStyle(
                      color: _cream,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Photograph each page in order. After every page, '
                    'Heirloom Atlas will ask whether there is another page.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _capturing ? null : _capturePage,
              icon: _capturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(
                _pages.isEmpty
                    ? 'Scan Page 1'
                    : 'Scan Page ${_pages.length + 1}',
              ),
            ),
            const SizedBox(height: 18),
            if (_pages.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _panel.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'No pages captured yet.',
                  style: TextStyle(color: _muted),
                ),
              )
            else ...[
              Text(
                '${_pages.length} PAGE${_pages.length == 1 ? '' : 'S'} CAPTURED',
                style: const TextStyle(
                  color: _gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < _pages.length; index++)
                Card(
                  color: _panel,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(_pages[index].path),
                        width: 54,
                        height: 70,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(
                      'Page ${index + 1}',
                      style: const TextStyle(
                        color: _cream,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Captured',
                      style: TextStyle(color: _muted),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove page',
                      onPressed: () => _removePage(index),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: _muted,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _finish,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Finish Document'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _DocumentDetailsScreen extends StatefulWidget {
  final List<String> pagePaths;

  const _DocumentDetailsScreen({required this.pagePaths});

  @override
  State<_DocumentDetailsScreen> createState() => _DocumentDetailsScreenState();
}

class _DocumentDetailsScreenState extends State<_DocumentDetailsScreen> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  final _titleController = TextEditingController();
  final _dateController = TextEditingController();
  final _typeController = TextEditingController();
  final _peopleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sourceController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _dateController.dispose();
    _typeController.dispose();
    _peopleController.dispose();
    _descriptionController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title for this document.')),
      );
      return;
    }
    if (_saving) return;

    setState(() => _saving = true);

    final copiedPages = <String>[];
    int? documentId;

    try {
      final appDocuments = await getApplicationDocumentsDirectory();
      final pageFolder = Directory(
        path.join(
          appDocuments.path,
          'Heirloom Atlas',
          'Documents',
          'Pages',
        ),
      );
      await pageFolder.create(recursive: true);

      final stamp = DateTime.now().microsecondsSinceEpoch;

      for (var index = 0; index < widget.pagePaths.length; index++) {
        final source = File(widget.pagePaths[index]);
        if (!await source.exists()) {
          throw StateError('Page ${index + 1} could not be found.');
        }

        var extension = path.extension(source.path);
        if (extension.isEmpty) extension = '.jpg';

        final destination = path.join(
          pageFolder.path,
          'document_${stamp}_page_${index + 1}$extension',
        );

        await source.copy(destination);
        copiedPages.add(destination);
      }

      if (copiedPages.isEmpty) {
        throw StateError('No document pages were available to save.');
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final document = DocumentRecord(
        title: title,
        documentDate: _dateController.text.trim(),
        documentType: _typeController.text.trim(),
        people: _peopleController.text.trim(),
        description: _descriptionController.text.trim(),
        source: _sourceController.text.trim(),
        // Keep Page 1 here for compatibility with the existing Windows
        // Documents screen. All pages are also stored in document_pages.
        filePath: copiedPages.first,
        createdAtMilliseconds: now,
        updatedAtMilliseconds: now,
      );

      documentId = await DatabaseHelper.instance.insertDocument(document);

      await DocumentPageService.instance.replacePages(
        documentId: documentId,
        filePaths: copiedPages,
      );

      final db = DatabaseHelper.instance;
      final localKey = documentId.toString();
      final device = await db.ensureCurrentSyncDevice(
        displayName: 'Heirloom Atlas Mobile',
      );
      final deviceId = device['device_id']?.toString() ?? '';
      final recordUuid = 'document_mobile_${stamp}_$documentId';
      final changeUuid = 'change_${recordUuid}_$now';

      await db.upsertSyncRecord(
        recordUuid: recordUuid,
        entityType: 'document',
        localKey: localKey,
        localModifiedMilliseconds: now,
        syncState: 'local_only',
      );
      await db.recordOrMergePendingSyncChange(
        changeUuid: changeUuid,
        deviceId: deviceId,
        entityType: 'document',
        localKey: localKey,
        operation: 'create',
        detailsJson: jsonEncode({
          'capture_source': 'mobile_companion',
          'title': title,
          'document_date': _dateController.text.trim(),
          'document_type': _typeController.text.trim(),
          'people': _peopleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'source': _sourceController.text.trim(),
          'page_paths': copiedPages,
        }),
        changedAtMilliseconds: now,
      );

      LocalNetworkTransferResult? transferResult;
      await LocalNetworkSyncClient.restoreStoredPairing();
      if (LocalNetworkSyncClient.hasActivePairing) {
        transferResult = await LocalNetworkSyncClient().sendDocument(
          changeUuid: changeUuid,
          recordUuid: recordUuid,
          title: title,
          documentDate: _dateController.text.trim(),
          documentType: _typeController.text.trim(),
          people: _peopleController.text.trim(),
          description: _descriptionController.text.trim(),
          source: _sourceController.text.trim(),
          pagePaths: copiedPages,
        );

        if (transferResult.ok) {
          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'document',
            localKey: localKey,
            localModifiedMilliseconds: now,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
        }
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Document saved'),
          content: Text(
            transferResult == null
                ? '"$title" was saved with ${copiedPages.length} '
                    'page${copiedPages.length == 1 ? '' : 's'} on this device '
                    'and queued for Windows sync.'
                : transferResult.ok
                    ? '"$title" was saved with ${copiedPages.length} '
                        'page${copiedPages.length == 1 ? '' : 's'} and synced to Windows.'
                    : '"$title" was saved with ${copiedPages.length} '
                        'page${copiedPages.length == 1 ? '' : 's'} on this device. '
                        'Windows sync is still pending: ${transferResult.message}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      // Return past both the details screen and the scan screen.
      Navigator.of(context).pop();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      // If the document row was created but page registration failed, remove
      // that incomplete row before deleting the copied page files.
      if (documentId != null) {
        try {
          await DocumentPageService.instance
              .deletePagesForDocument(documentId);
          await DatabaseHelper.instance.deleteDocument(documentId);
        } catch (_) {}
      }

      for (final copiedPath in copiedPages) {
        try {
          final file = File(copiedPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save this document: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    bool required = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: _cream),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        labelStyle: const TextStyle(color: _muted),
        hintStyle: TextStyle(color: _muted.withValues(alpha: .65)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _gold.withValues(alpha: .25)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _gold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: _cream,
        title: const Text(
          'DOCUMENT DETAILS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _panel.withValues(alpha: .92),
                border: Border.all(color: _gold.withValues(alpha: .28)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: _gold, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.pagePaths.length} page${widget.pagePaths.length == 1 ? '' : 's'} captured',
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _field(
              _titleController,
              'Title',
              required: true,
              hint: 'Example: Grandma Smith letter',
            ),
            const SizedBox(height: 12),
            _field(
              _dateController,
              'Date',
              hint: 'Example: June 14, 1944 or circa 1920',
            ),
            const SizedBox(height: 12),
            _field(
              _typeController,
              'Document Type',
              hint: 'Letter, certificate, military record, deed...',
            ),
            const SizedBox(height: 12),
            _field(
              _peopleController,
              'People',
              hint: 'People connected to or named in this document',
            ),
            const SizedBox(height: 12),
            _field(
              _descriptionController,
              'Description / Story',
              maxLines: 4,
              hint: 'What is this document and why does it matter?',
            ),
            const SizedBox(height: 12),
            _field(
              _sourceController,
              'Source',
              hint: 'Family collection, courthouse, archive...',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _continue,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Document'),
            ),
            const SizedBox(height: 10),
            const Text(
              '* Required',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCaptureFlow extends StatefulWidget {
  const _ItemCaptureFlow();

  @override
  State<_ItemCaptureFlow> createState() => _ItemCaptureFlowState();
}

class _ItemCaptureFlowState extends State<_ItemCaptureFlow> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  static const _types = [
    'Antique',
    'Coin',
    'Sports Card',
    'Photo',
    'Document',
    'Other',
  ];

  int _step = 0;
  String? _type;
  FamilyPerson? _person;
  final _storyController = TextEditingController();
  final _locationController = TextEditingController();
  final _imagePicker = ImagePicker();
  XFile? _capturedImage;
  bool _capturingImage = false;
  bool _saving = false;

  @override
  void dispose() {
    _storyController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_capturingImage) return;

    setState(() => _capturingImage = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (!mounted || image == null) return;

      setState(() => _capturedImage = image);
    } catch (error) {
      if (!mounted) return;
      _message('Could not open the camera. $error');
    } finally {
      if (mounted) {
        setState(() => _capturingImage = false);
      }
    }
  }

  Future<void> _next() async {
    if (_step == 0 && _capturedImage == null) {
      _message('Take a photo of the item first.');
      return;
    }

    if (_step == 1 && _type == null) {
      _message('Choose what kind of item this is.');
      return;
    }

    if (_step == 1 && _type == 'Sports Card') {
      final front = _capturedImage;
      if (front == null) {
        _message('Take a photo of the card front first.');
        return;
      }
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => _SportsCardCaptureFlow(frontImage: front),
        ),
      );
      if (saved == true && mounted) {
        Navigator.pop(context, true);
      }
      return;
    }

    if (_step == 1 && _type == 'Coin') {
      final front = _capturedImage;
      if (front == null) {
        _message('Take a photo of the coin front first.');
        return;
      }
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => _CoinCaptureFlow(frontImage: front),
        ),
      );
      if (saved == true && mounted) {
        Navigator.pop(context, true);
      }
      return;
    }

    if (_step < 4) {
      setState(() => _step++);
      return;
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review capture'),
        content: Text(
          'Photo: ${_capturedImage == null ? 'Not captured' : 'Captured'}\n'
          'Type: ${_type ?? 'Other'}\n'
          'Person: ${_person?.displayName ?? 'Not linked yet'}\n'
          'Story: ${_storyController.text.trim().isEmpty ? 'None yet' : _storyController.text.trim()}\n'
          'Location: ${_locationController.text.trim().isEmpty ? 'Not entered' : _locationController.text.trim()}\n\n'
          'Save this capture to Heirloom Atlas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true || !mounted) return;
    await _saveCapture();
  }

  Future<void> _saveCapture() async {
    if (_saving) return;
    final captured = _capturedImage;
    final type = _type;
    if (captured == null || type == null) return;

    if (type != 'Antique') {
      _message('$type saving is not connected yet. Choose Antique for this test.');
      return;
    }

    setState(() => _saving = true);
    String? permanentImagePath;

    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final imageDirectory = Directory(path.join(
        documentsDirectory.path,
        'Heirloom Atlas',
        'Antiques',
        'Images',
      ));
      if (!await imageDirectory.exists()) {
        await imageDirectory.create(recursive: true);
      }

      final source = File(captured.path);
      if (!await source.exists()) {
        throw StateError('The captured photo could not be found.');
      }

      var extension = path.extension(captured.path);
      if (extension.isEmpty) extension = '.jpg';
      final stamp = DateTime.now().microsecondsSinceEpoch;
      permanentImagePath = path.join(
        imageDirectory.path,
        'antique_mobile_$stamp$extension',
      );
      await source.copy(permanentImagePath);

      final story = _storyController.text.trim();
      final location = _locationController.text.trim();
      final noteParts = <String>[
        if (location.isNotEmpty) 'Physical location: $location',
        'Captured with Heirloom Atlas mobile companion.',
      ];

      final antique = Antique(
        title: 'Mobile antique capture',
        description: story,
        notes: noteParts.join('\n'),
        imagePaths: [permanentImagePath],
      );

      final db = DatabaseHelper.instance;
      final antiqueId = await db.insertAntique(antique);
      final localKey = antiqueId.toString();

      final personId = _person?.id;
      if (personId != null) {
        await db.linkFamilyPersonToItem(
          personId: personId,
          itemType: 'antique',
          itemKey: localKey,
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final device = await db.ensureCurrentSyncDevice(
        displayName: 'Heirloom Atlas Mobile',
      );
      final deviceId = device['device_id']?.toString() ?? '';
      final recordUuid = 'antique_mobile_${stamp}_$antiqueId';

      await db.upsertSyncRecord(
        recordUuid: recordUuid,
        entityType: 'antique',
        localKey: localKey,
        localModifiedMilliseconds: now,
        syncState: 'local_only',
      );

      final changeUuid = 'change_${recordUuid}_$now';
      await db.recordOrMergePendingSyncChange(
        changeUuid: changeUuid,
        deviceId: deviceId,
        entityType: 'antique',
        localKey: localKey,
        operation: 'create',
        detailsJson: jsonEncode({
          'changed_fields': [
            'title',
            'description',
            'notes',
            'image_paths',
            if (personId != null) 'family_person_links',
          ],
          'capture_source': 'mobile_companion',
        }),
        changedAtMilliseconds: now,
      );

      LocalNetworkTransferResult? transferResult;
      if (LocalNetworkSyncClient.hasActivePairing) {
        transferResult = await LocalNetworkSyncClient().sendAntique(
          changeUuid: changeUuid,
          recordUuid: recordUuid,
          title: antique.title,
          description: antique.description,
          notes: antique.notes,
          imagePath: permanentImagePath,
        );

        if (transferResult.ok) {
          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'antique',
            localKey: localKey,
            localModifiedMilliseconds: now,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
        }
      }

      if (!mounted) return;
      final completedTransfer = transferResult;
      if (completedTransfer != null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              completedTransfer.ok ? 'Synced to Windows' : 'Saved on this phone',
            ),
            content: Text(
              completedTransfer.ok
                  ? completedTransfer.message
                  : '${completedTransfer.message}\n\nThe Antique is still saved on this device and remains queued for sync.',
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

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (permanentImagePath != null) {
        try {
          final copied = File(permanentImagePath);
          if (await copied.exists()) await copied.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      _message('Could not save the antique: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Capture',
      'What is this?',
      'Who is it connected to?',
      'What is its story?',
      'Where is it now?',
    ];

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: _cream,
        title: Text('STEP ${_step + 1} OF 5',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 5,
              backgroundColor: _panel,
              color: _gold,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(labels[_step],
                      style: const TextStyle(
                          color: _cream,
                          fontSize: 25,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(_subtitle(),
                      style: const TextStyle(
                          color: _muted, fontSize: 14, height: 1.4)),
                  const SizedBox(height: 24),
                  _buildStep(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: _gold.withValues(alpha: .18))),
              ),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saving ? null : _next,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_step == 4 ? Icons.check : Icons.arrow_forward),
                    label: Text(_saving
                        ? 'Saving...'
                        : (_step == 4 ? 'Review' : 'Continue')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    switch (_step) {
      case 0:
        return 'Start with a picture of the object.';
      case 1:
        return 'Choose the best home for this item. You can change it later.';
      case 2:
        return 'Connect the object to the person whose story it carries.';
      case 3:
        return 'Add the memory now while someone who knows it is nearby.';
      case 4:
        return 'Record where the object physically lives.';
      default:
        return '';
    }
  }

  Widget _buildStep() {
    if (_step == 0) {
      return _panelCard(
        child: Column(
          children: [
            if (_capturedImage == null) ...[
              const Icon(Icons.camera_alt_outlined, color: _gold, size: 72),
              const SizedBox(height: 18),
              const Text(
                'Photograph the item',
                style: TextStyle(
                  color: _cream,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use the phone camera to capture the object. You can retake it before continuing.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, height: 1.4),
              ),
            ] else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(_capturedImage!.path),
                  width: double.infinity,
                  height: 280,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Photo captured',
                style: TextStyle(
                  color: _cream,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _capturingImage ? null : _capturePhoto,
              icon: _capturingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(
                _capturingImage
                    ? 'Opening Camera...'
                    : _capturedImage == null
                        ? 'Open Camera'
                        : 'Retake Photo',
              ),
            ),
          ],
        ),
      );
    }

    if (_step == 1) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _types
            .map((type) => ChoiceChip(
                  selected: _type == type,
                  label: Text(type),
                  onSelected: (_) => setState(() => _type = type),
                ))
            .toList(),
      );
    }

    if (_step == 2) {
      return _panelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_person != null) ...[
              Text(_person!.displayName,
                  style: const TextStyle(
                      color: _cream,
                      fontSize: 19,
                      fontWeight: FontWeight.w900)),
              if (_person!.lifeSpan.isNotEmpty)
                Text(_person!.lifeSpan,
                    style: const TextStyle(color: _muted)),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              onPressed: () async {
                final person = await _chooseFamilyPerson(context);
                if (!mounted || person == null) return;
                setState(() => _person = person);
              },
              icon: const Icon(Icons.person_search_outlined),
              label: Text(_person == null
                  ? 'Search Family Tree'
                  : 'Choose Different Person'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _person = null;
                  _step = 3;
                });
              },
              child: const Text('Skip for now'),
            ),
          ],
        ),
      );
    }

    if (_step == 3) {
      return _panelCard(
        child: TextField(
          controller: _storyController,
          minLines: 6,
          maxLines: 10,
          style: const TextStyle(color: _cream),
          decoration: const InputDecoration(
            labelText: 'Tell the story',
            hintText:
                'Example: Grandpa carried this watch during his years on the railroad...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      );
    }

    return _panelCard(
      child: TextField(
        controller: _locationController,
        style: const TextStyle(color: _cream),
        decoration: const InputDecoration(
          labelText: 'Physical location',
          hintText: 'Display cabinet, Album 3, Box 4, Safe...',
          prefixIcon: Icon(Icons.location_on_outlined),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _panelCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: .90),
        border: Border.all(color: _gold.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}


class _SportsCardCaptureFlow extends StatefulWidget {
  const _SportsCardCaptureFlow({required this.frontImage});

  final XFile frontImage;

  @override
  State<_SportsCardCaptureFlow> createState() => _SportsCardCaptureFlowState();
}

class _SportsCardCaptureFlowState extends State<_SportsCardCaptureFlow> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  final _playerController = TextEditingController();
  final _yearController = TextEditingController();
  final _brandController = TextEditingController();
  final _setController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _conditionController = TextEditingController();
  final _teamController = TextEditingController();
  final _storageController = TextEditingController();
  final _notesController = TextEditingController();
  final _picker = ImagePicker();

  XFile? _backImage;
  bool _capturingBack = false;
  bool _saving = false;

  @override
  void dispose() {
    _playerController.dispose();
    _yearController.dispose();
    _brandController.dispose();
    _setController.dispose();
    _cardNumberController.dispose();
    _conditionController.dispose();
    _teamController.dispose();
    _storageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _captureBack() async {
    if (_capturingBack) return;
    setState(() => _capturingBack = true);
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (!mounted || image == null) return;
      setState(() => _backImage = image);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture the card back: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturingBack = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final year = _yearController.text.trim();
    final brand = _brandController.text.trim();
    final cardNumber = _cardNumberController.text.trim();
    if (year.isEmpty || brand.isEmpty || cardNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the year, brand, and card number before saving.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    String? frontPath;
    String backPath = '';
    var queued = false;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(
        path.join(
          docs.path,
          'Heirloom Atlas',
          'Mobile Captures',
          'Sports Cards',
        ),
      );
      await folder.create(recursive: true);

      final stamp = DateTime.now().microsecondsSinceEpoch;

      Future<String> copyImage(XFile sourceImage, String side) async {
        final source = File(sourceImage.path);
        if (!await source.exists()) {
          throw StateError('The $side image could not be found.');
        }
        var ext = path.extension(sourceImage.path);
        if (ext.isEmpty || ext.length > 8) ext = '.jpg';
        final destination =
            path.join(folder.path, 'sports_card_mobile_${stamp}_$side$ext');
        await source.copy(destination);
        return destination;
      }

      frontPath = await copyImage(widget.frontImage, 'front');
      if (_backImage != null) {
        backPath = await copyImage(_backImage!, 'back');
      }

      final db = DatabaseHelper.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final device = await db.ensureCurrentSyncDevice(
        displayName: 'Heirloom Atlas Mobile',
      );
      final deviceId = device['device_id']?.toString() ?? '';
      final recordUuid = 'sports_card_mobile_$stamp';
      final localKey = recordUuid;
      final changeUuid = 'change_${recordUuid}_$now';

      final details = <String, Object?>{
        'capture_source': 'mobile_companion',
        'sport': 'Baseball',
        'player': _playerController.text.trim(),
        'year': year,
        'brand': brand,
        'set_name': _setController.text.trim(),
        'card_number': cardNumber,
        'condition': _conditionController.text.trim(),
        'team': _teamController.text.trim(),
        'storage_location': _storageController.text.trim(),
        'notes': _notesController.text.trim(),
        'front_image_path': frontPath,
        'back_image_path': backPath,
      };

      await db.upsertSyncRecord(
        recordUuid: recordUuid,
        entityType: 'sports_card',
        localKey: localKey,
        localModifiedMilliseconds: now,
        syncState: 'local_only',
      );

      await db.recordOrMergePendingSyncChange(
        changeUuid: changeUuid,
        deviceId: deviceId,
        entityType: 'sports_card',
        localKey: localKey,
        operation: 'create',
        detailsJson: jsonEncode(details),
        changedAtMilliseconds: now,
      );
      queued = true;

      await LocalNetworkSyncClient.restoreStoredPairing();
      LocalNetworkTransferResult? transferResult;
      if (LocalNetworkSyncClient.hasActivePairing) {
        transferResult = await LocalNetworkSyncClient().sendSportsCard(
          changeUuid: changeUuid,
          recordUuid: recordUuid,
          player: _playerController.text.trim(),
          year: year,
          brand: brand,
          setName: _setController.text.trim(),
          cardNumber: cardNumber,
          condition: _conditionController.text.trim(),
          storageLocation: _storageController.text.trim(),
          notes: _notesController.text.trim(),
          frontImagePath: frontPath,
          backImagePath: backPath,
          sport: 'Baseball',
          team: _teamController.text.trim(),
        );

        if (transferResult.ok) {
          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'sports_card',
            localKey: localKey,
            localModifiedMilliseconds: now,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
        }
      }

      if (!mounted) return;

      final result = transferResult;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            result == null
                ? 'Saved on this phone'
                : result.ok
                    ? 'Synced to Windows'
                    : 'Saved on this phone',
          ),
          content: Text(
            result == null
                ? 'The Sports Card capture is saved and queued for Windows sync.'
                : result.ok
                    ? result.message
                    : '${result.message}\n\nThe Sports Card is still saved on this device and remains queued for sync.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!queued) {
        if (frontPath != null) {
          try {
            final file = File(frontPath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        if (backPath.isNotEmpty) {
          try {
            final file = File(backPath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the Sports Card: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String hint = '',
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: const TextStyle(color: _cream),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isEmpty ? null : hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: _cream,
        title: const Text(
          'SPORTS CARD CAPTURE',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Card photos',
              style: TextStyle(
                color: _cream,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The front is ready. Add the back if you want it preserved with the card.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _panel,
                border: Border.all(color: _gold.withValues(alpha: .25)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(widget.frontImage.path),
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_backImage != null) ...[
                    const Text(
                      'Back captured',
                      style: TextStyle(
                        color: _cream,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(_backImage!.path),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _capturingBack || _saving ? null : _captureBack,
                    icon: const Icon(Icons.flip_to_back_outlined),
                    label: Text(
                      _backImage == null ? 'Photograph Back' : 'Retake Back',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Card details',
              style: TextStyle(
                color: _gold,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _field(_playerController, 'Player'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_yearController, 'Year *')),
                const SizedBox(width: 12),
                Expanded(child: _field(_cardNumberController, 'Card # *')),
              ],
            ),
            const SizedBox(height: 12),
            _field(_brandController, 'Brand *', hint: 'Topps, Upper Deck...'),
            const SizedBox(height: 12),
            _field(_setController, 'Set', hint: 'Base, Chrome, Series 1...'),
            const SizedBox(height: 12),
            _field(_teamController, 'Team'),
            const SizedBox(height: 12),
            _field(_conditionController, 'Condition / Grade'),
            const SizedBox(height: 12),
            _field(
              _storageController,
              'Storage location',
              hint: 'Binder 2, Box 4, Display case...',
            ),
            const SizedBox(height: 12),
            _field(
              _notesController,
              'Notes',
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Sports Card'),
            ),
          ],
        ),
      ),
    );
  }
}


class _CoinCaptureFlow extends StatefulWidget {
  const _CoinCaptureFlow({required this.frontImage});

  final XFile frontImage;

  @override
  State<_CoinCaptureFlow> createState() => _CoinCaptureFlowState();
}

class _CoinCaptureFlowState extends State<_CoinCaptureFlow> {
  static const _navy = Color(0xFF071A2B);
  static const _panel = Color(0xFF0B2742);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFFAAB8C2);

  final _categoryController = TextEditingController(text: 'Coins');
  final _seriesController = TextEditingController();
  final _yearController = TextEditingController();
  final _mintController = TextEditingController();
  final _varietyController = TextEditingController();
  final _gradeController = TextEditingController();
  final _storageController = TextEditingController();
  final _notesController = TextEditingController();
  final _picker = ImagePicker();

  XFile? _backImage;
  bool _capturingBack = false;
  bool _saving = false;

  @override
  void dispose() {
    _categoryController.dispose();
    _seriesController.dispose();
    _yearController.dispose();
    _mintController.dispose();
    _varietyController.dispose();
    _gradeController.dispose();
    _storageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _captureBack() async {
    if (_capturingBack) return;
    setState(() => _capturingBack = true);
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (!mounted || image == null) return;
      setState(() => _backImage = image);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture the coin back: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturingBack = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final series = _seriesController.text.trim();
    final year = _yearController.text.trim();
    if (series.isEmpty || year.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the coin series and year before saving.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    String? frontPath;
    String backPath = '';
    var queued = false;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(
        path.join(
          docs.path,
          'Heirloom Atlas',
          'Mobile Captures',
          'Coins',
        ),
      );
      await folder.create(recursive: true);

      final stamp = DateTime.now().microsecondsSinceEpoch;

      Future<String> copyImage(XFile sourceImage, String side) async {
        final source = File(sourceImage.path);
        if (!await source.exists()) {
          throw StateError('The $side image could not be found.');
        }
        var ext = path.extension(sourceImage.path);
        if (ext.isEmpty || ext.length > 8) ext = '.jpg';
        final destination =
            path.join(folder.path, 'coin_mobile_${stamp}_$side$ext');
        await source.copy(destination);
        return destination;
      }

      frontPath = await copyImage(widget.frontImage, 'front');
      if (_backImage != null) {
        backPath = await copyImage(_backImage!, 'back');
      }

      final db = DatabaseHelper.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final device = await db.ensureCurrentSyncDevice(
        displayName: 'Heirloom Atlas Mobile',
      );
      final deviceId = device['device_id']?.toString() ?? '';
      final recordUuid = 'coin_mobile_$stamp';
      final localKey = recordUuid;
      final changeUuid = 'change_${recordUuid}_$now';

      final details = <String, Object?>{
        'capture_source': 'mobile_companion',
        'category': _categoryController.text.trim(),
        'series': series,
        'year': year,
        'mint': _mintController.text.trim(),
        'variety': _varietyController.text.trim(),
        'grade': _gradeController.text.trim(),
        'storage_location': _storageController.text.trim(),
        'notes': _notesController.text.trim(),
        'front_image_path': frontPath,
        'back_image_path': backPath,
      };

      await db.upsertSyncRecord(
        recordUuid: recordUuid,
        entityType: 'coin',
        localKey: localKey,
        localModifiedMilliseconds: now,
        syncState: 'local_only',
      );

      await db.recordOrMergePendingSyncChange(
        changeUuid: changeUuid,
        deviceId: deviceId,
        entityType: 'coin',
        localKey: localKey,
        operation: 'create',
        detailsJson: jsonEncode(details),
        changedAtMilliseconds: now,
      );
      queued = true;

      await LocalNetworkSyncClient.restoreStoredPairing();
      LocalNetworkTransferResult? transferResult;
      if (LocalNetworkSyncClient.hasActivePairing) {
        transferResult = await LocalNetworkSyncClient().sendCoin(
          changeUuid: changeUuid,
          recordUuid: recordUuid,
          category: _categoryController.text.trim(),
          series: series,
          year: year,
          mint: _mintController.text.trim(),
          variety: _varietyController.text.trim(),
          grade: _gradeController.text.trim(),
          storageLocation: _storageController.text.trim(),
          notes: _notesController.text.trim(),
          frontImagePath: frontPath,
          backImagePath: backPath,
        );

        if (transferResult.ok) {
          await db.markSyncChangeProcessed(changeUuid);
          await db.upsertSyncRecord(
            recordUuid: recordUuid,
            entityType: 'coin',
            localKey: localKey,
            localModifiedMilliseconds: now,
            lastSyncedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            syncState: 'synced',
          );
        }
      }

      if (!mounted) return;

      final result = transferResult;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            result == null
                ? 'Saved on this phone'
                : result.ok
                    ? 'Synced to Windows'
                    : 'Saved on this phone',
          ),
          content: Text(
            result == null
                ? 'The Coin capture is saved and queued for Windows sync.'
                : result.ok
                    ? result.message
                    : '${result.message}\n\nThe Coin is still saved on this device and remains queued for sync.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!queued) {
        if (frontPath != null) {
          try {
            final file = File(frontPath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        if (backPath.isNotEmpty) {
          try {
            final file = File(backPath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the Coin: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String hint = '',
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: const TextStyle(color: _cream),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isEmpty ? null : hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: _cream,
        title: const Text(
          'COIN CAPTURE',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Coin photos',
              style: TextStyle(
                color: _cream,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The front is ready. Add the reverse so both sides stay with the coin.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _panel,
                border: Border.all(color: _gold.withValues(alpha: .25)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(widget.frontImage.path),
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_backImage != null) ...[
                    const Text(
                      'Reverse captured',
                      style: TextStyle(
                        color: _cream,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(_backImage!.path),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _capturingBack || _saving ? null : _captureBack,
                    icon: const Icon(Icons.flip_to_back_outlined),
                    label: Text(
                      _backImage == null ? 'Photograph Reverse' : 'Retake Reverse',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Coin details',
              style: TextStyle(
                color: _gold,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _field(
              _categoryController,
              'Category',
              hint: 'U.S. Coins, World Coins...',
            ),
            const SizedBox(height: 12),
            _field(
              _seriesController,
              'Series *',
              hint: 'Morgan Dollar, Lincoln Cent...',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_yearController, 'Year *')),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _mintController,
                    'Mint',
                    hint: 'P, D, S...',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              _varietyController,
              'Variety',
              hint: 'Proof, VDB, Type 2...',
            ),
            const SizedBox(height: 12),
            _field(
              _gradeController,
              'Grade / Condition',
              hint: 'Raw, VF, MS-63...',
            ),
            const SizedBox(height: 12),
            _field(
              _storageController,
              'Storage location',
              hint: 'Binder 1, Tray 3, Safe...',
            ),
            const SizedBox(height: 12),
            _field(
              _notesController,
              'Notes',
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Coin'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<FamilyPerson?> _chooseFamilyPerson(BuildContext context) async {
  return showDialog<FamilyPerson>(
    context: context,
    builder: (dialogContext) => const _FamilyPersonPickerDialog(),
  );
}

class _FamilyPersonPickerDialog extends StatefulWidget {
  const _FamilyPersonPickerDialog();

  @override
  State<_FamilyPersonPickerDialog> createState() =>
      _FamilyPersonPickerDialogState();
}

class _FamilyPersonPickerDialogState extends State<_FamilyPersonPickerDialog> {
  final _controller = TextEditingController();
  List<FamilyPerson> _results = const [];
  bool _loadingTree = true;
  bool _searching = false;
  bool _hasPeople = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkTree();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkTree() async {
    try {
      final people = await DatabaseHelper.instance.getFamilyPeople();
      if (!mounted) return;
      setState(() {
        _hasPeople = people.isNotEmpty;
        _loadingTree = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingTree = false;
        _error = 'Could not read the Family Tree. $error';
      });
    }
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final matches =
          await DatabaseHelper.instance.getFamilyPeople(searchText: query);
      if (!mounted) return;
      setState(() {
        _results = matches.take(50).toList();
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Could not search the Family Tree. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_loadingTree) {
      content = const SizedBox(
        width: 420,
        height: 160,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Checking Family Tree...'),
            ],
          ),
        ),
      );
    } else if (_error != null) {
      content = SizedBox(
        width: 420,
        child: Text(_error!),
      );
    } else if (!_hasPeople) {
      content = const SizedBox(
        width: 420,
        child: Text(
          'There are no people in the Family Tree yet. '
          'You can skip this step now and connect the item later.',
        ),
      );
    } else {
      content = SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search Family Tree',
                hintText: 'Type at least 2 letters',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(
                          child: Text(
                            'Type at least 2 letters to search for a person.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final person = _results[index];
                            return ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(person.displayName),
                              subtitle: person.lifeSpan.isEmpty
                                  ? null
                                  : Text(person.lifeSpan),
                              onTap: () => Navigator.pop(context, person),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text(!_loadingTree && !_hasPeople && _error == null
          ? 'No Family Tree people yet'
          : 'Connect a Family Person'),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(!_loadingTree && !_hasPeople && _error == null
              ? 'OK'
              : 'Cancel'),
        ),
      ],
    );
  }
}
