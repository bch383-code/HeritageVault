import 'package:flutter/material.dart';

import '../services/coin_import_service.dart';
import 'coins_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CoinImportService _importService = CoinImportService();

  bool _isImporting = false;

  Future<void> _importSpreadsheet() async {
    setState(() {
      _isImporting = true;
    });

    try {
      final result = await _importService.chooseAndReadWorkbook();

      if (!mounted || result == null) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Spreadsheet Read Successfully'),
            content: Text(
              'File: ${result.fileName}\n\n'
              'Coin worksheets: ${result.sheetCount}\n'
              'Needed coins: ${result.neededCount}\n'
              'Owned coins: ${result.ownedCount}\n'
              'Total tracked: ${result.trackedCount}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not read spreadsheet: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = [
      ('Coins', Icons.monetization_on_outlined),
      ('Photos', Icons.photo_library_outlined),
      ('Documents', Icons.description_outlined),
      ('Family Tree', Icons.account_tree_outlined),
      ('Antiques', Icons.chair_outlined),
      ('Stories', Icons.menu_book_outlined),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Heritage Vault'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preserve your family history',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Organize collections, photographs, documents, and stories in one place.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                itemCount: collections.length,
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.4,
                ),
                itemBuilder: (context, index) {
                  final collection = collections[index];

                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (collection.$1 == 'Coins') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CoinsScreen(),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(collection.$2, size: 42),
                            const SizedBox(height: 12),
                            Text(
                              collection.$1,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _isImporting ? null : _importSpreadsheet,
                icon: _isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(
                  _isImporting
                      ? 'Reading Spreadsheet...'
                      : 'Import Coin Spreadsheet',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}