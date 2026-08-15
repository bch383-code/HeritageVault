import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/valuable.dart';
import 'valuable_edit_screen.dart';

class ValuablesScreen extends StatefulWidget {
  const ValuablesScreen({super.key});

  @override
  State<ValuablesScreen> createState() => _ValuablesScreenState();
}

class _ValuablesScreenState extends State<ValuablesScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isLoading = true;
  String? _errorMessage;
  List<Valuable> _valuables = const [];

  @override
  void initState() {
    super.initState();
    _loadValuables();
  }

  Future<void> _loadValuables() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final valuables = await _databaseHelper.getValuables();
      if (!mounted) return;

      setState(() {
        _valuables = valuables;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _addValuable() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const ValuableEditScreen(),
      ),
    );

    if (saved == true) await _loadValuables();
  }

  Future<void> _editValuable(Valuable valuable) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ValuableEditScreen(valuable: valuable),
      ),
    );

    if (saved == true) await _loadValuables();
  }

  String _titleFor(Valuable valuable) {
    if (valuable.title.trim().isNotEmpty) return valuable.title.trim();
    if (valuable.year.trim().isNotEmpty) {
      return 'Valuable • ${valuable.year.trim()}';
    }
    return 'Untitled Valuable';
  }

  String _money(double? value) {
    if (value == null) return '';
    return '\$${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Valuables'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadValuables,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addValuable,
        icon: const Icon(Icons.add),
        label: const Text('Add Valuable'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Could not load valuables.\n\n$_errorMessage',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_valuables.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond_outlined, size: 64),
                    const SizedBox(height: 18),
                    Text(
                      'Your valuables collection is empty',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add valuables with photos, acquisition details, purchase price, and estimated value.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _addValuable,
                      icon: const Icon(Icons.add),
                      label: const Text('Add First Valuable'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      itemCount: _valuables.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (context, index) {
        final valuable = _valuables[index];
        File? imageFile;

        if (valuable.imagePaths.isNotEmpty) {
          final candidate = File(valuable.imagePaths.first);
          if (candidate.existsSync()) imageFile = candidate;
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _editValuable(valuable),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: imageFile != null
                        ? Image.file(
                            imageFile,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                              child: Icon(Icons.broken_image_outlined, size: 52),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.diamond_outlined, size: 60),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleFor(valuable),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (valuable.year.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(valuable.year.trim()),
                      ],
                      if (valuable.estimatedValue != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Estimated value: ${_money(valuable.estimatedValue)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
