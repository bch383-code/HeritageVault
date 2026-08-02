import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/coin.dart';

class CoinsScreen extends StatefulWidget {
  const CoinsScreen({super.key});

  @override
  State<CoinsScreen> createState() => _CoinsScreenState();
}

class _CoinsScreenState extends State<CoinsScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  List<Coin> _coins = [];
  String _searchText = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    try {
      final coins = await _databaseHelper.getCoins();

      if (!mounted) {
        return;
      }

      setState(() {
        _coins = coins;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load coins: $error'),
        ),
      );
    }
  }

  List<Coin> get _filteredCoins {
    final query = _searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return _coins;
    }

    return _coins.where((coin) {
      return coin.year.toLowerCase().contains(query) ||
          coin.name.toLowerCase().contains(query) ||
          coin.mintMark.toLowerCase().contains(query) ||
          coin.country.toLowerCase().contains(query) ||
          coin.notes.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showAddCoinDialog() async {
    final yearController = TextEditingController();
    final nameController = TextEditingController();
    final mintController = TextEditingController();
    final countryController = TextEditingController(
      text: 'United States',
    );
    final notesController = TextEditingController();

    final newCoin = await showDialog<Coin>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Coin'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: yearController,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Coin name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mintController,
                    decoration: const InputDecoration(
                      labelText: 'Mint mark',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: countryController,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final year = yearController.text.trim();
                final name = nameController.text.trim();
                final mintMark = mintController.text.trim();
                final country = countryController.text.trim();
                final notes = notesController.text.trim();

                if (year.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Year and coin name are required.',
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(
                  dialogContext,
                  Coin(
                    year: year,
                    name: name,
                    mintMark: mintMark,
                    country: country.isEmpty ? 'Unknown' : country,
                    notes: notes,
                  ),
                );
              },
              child: const Text('Save Coin'),
            ),
          ],
        );
      },
    );

    yearController.dispose();
    nameController.dispose();
    mintController.dispose();
    countryController.dispose();
    notesController.dispose();

    if (newCoin == null) {
      return;
    }

    try {
      await _databaseHelper.insertCoin(newCoin);
      await _loadCoins();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coin saved permanently.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save coin: $error'),
        ),
      );
    }
  }

  Future<void> _deleteCoin(Coin coin) async {
    if (coin.id == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Coin?'),
          content: Text(
            'Delete ${coin.year} ${coin.name} from Heritage Vault?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    await _databaseHelper.deleteCoin(coin.id!);
    await _loadCoins();
  }

  @override
  Widget build(BuildContext context) {
    final visibleCoins = _filteredCoins;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin Collection'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCoinDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Coin'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText:
                    'Search by year, name, mint mark, country, or notes',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                });
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _buildCoinList(visibleCoins),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinList(List<Coin> visibleCoins) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (visibleCoins.isEmpty) {
      return const Center(
        child: Text(
          'No coins have been added yet.\n'
          'Click Add Coin to create your first entry.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: visibleCoins.length,
      separatorBuilder: (context, index) {
        return const SizedBox(height: 8);
      },
      itemBuilder: (context, index) {
        final coin = visibleCoins[index];

        final mintText = coin.mintMark.isEmpty
            ? 'No mint mark'
            : 'Mint: ${coin.mintMark}';

        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.monetization_on_outlined),
            ),
            title: Text('${coin.year} ${coin.name}'),
            subtitle: Text('${coin.country} • $mintText'),
            trailing: IconButton(
              tooltip: 'Delete coin',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                _deleteCoin(coin);
              },
            ),
          ),
        );
      },
    );
  }
}