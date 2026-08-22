import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum AtlasBookScope {
  people,
  branch,
  generations,
}

extension AtlasBookScopeLabel on AtlasBookScope {
  String get label {
    switch (this) {
      case AtlasBookScope.people:
        return 'People';
      case AtlasBookScope.branch:
        return 'Family Branch';
      case AtlasBookScope.generations:
        return 'Generations';
    }
  }

  IconData get icon {
    switch (this) {
      case AtlasBookScope.people:
        return Icons.person_outline;
      case AtlasBookScope.branch:
        return Icons.account_tree_outlined;
      case AtlasBookScope.generations:
        return Icons.groups_outlined;
    }
  }
}

class AtlasBookProject {
  final int? id;
  final String title;
  final String subtitle;
  final AtlasBookScope scope;
  final String status;
  final DateTime createdAt;

  const AtlasBookProject({
    this.id,
    required this.title,
    required this.subtitle,
    required this.scope,
    required this.status,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'scope': scope.name,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AtlasBookProject.fromMap(Map<String, Object?> map) {
    final scopeName = map['scope'] as String;

    return AtlasBookProject(
      id: map['id'] as int,
      title: map['title'] as String,
      subtitle: (map['subtitle'] as String?) ?? '',
      scope: AtlasBookScope.values.firstWhere(
        (scope) => scope.name == scopeName,
        orElse: () => AtlasBookScope.people,
      ),
      status: (map['status'] as String?) ?? 'Planning',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class AtlasBookRepository {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final databasePath = await databaseFactory.getDatabasesPath();
    final path = '$databasePath${Platform.pathSeparator}atlas_books.db';

    _database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE atlas_books (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              subtitle TEXT,
              scope TEXT NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );

    return _database!;
  }

  Future<List<AtlasBookProject>> getBooks() async {
    final db = await database;

    final rows = await db.query(
      'atlas_books',
      orderBy: 'created_at DESC',
    );

    return rows.map(AtlasBookProject.fromMap).toList();
  }

  Future<AtlasBookProject> createBook(AtlasBookProject project) async {
    final db = await database;

    final map = project.toMap();
    map.remove('id');

    final id = await db.insert('atlas_books', map);

    return AtlasBookProject(
      id: id,
      title: project.title,
      subtitle: project.subtitle,
      scope: project.scope,
      status: project.status,
      createdAt: project.createdAt,
    );
  }
}

class AtlasBookScreen extends StatefulWidget {
  const AtlasBookScreen({super.key});

  @override
  State<AtlasBookScreen> createState() => _AtlasBookScreenState();
}

class _AtlasBookScreenState extends State<AtlasBookScreen> {
  final AtlasBookRepository _repository = AtlasBookRepository();

  List<AtlasBookProject> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final books = await _repository.getBooks();

    if (!mounted) return;

    setState(() {
      _books = books;
      _loading = false;
    });
  }

  Future<void> _createBook() async {
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();

    AtlasBookScope selectedScope = AtlasBookScope.people;

    final result = await showDialog<_NewBookData>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create New Atlas Book'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Book name',
                          hintText: 'The Hoffman Family Story',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: subtitleController,
                        decoration: const InputDecoration(
                          labelText: 'Subtitle (optional)',
                          hintText:
                              'Four generations of family, stories, and keepsakes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'What will this book follow?',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 12),
                      RadioGroup<AtlasBookScope>(
                        groupValue: selectedScope,
                        onChanged: (value) {
                          if (value == null) return;

                          setDialogState(() {
                            selectedScope = value;
                          });
                        },
                        child: Column(
                          children: AtlasBookScope.values.map(
                            (scope) {
                              return RadioListTile<AtlasBookScope>(
                                value: scope,
                                title: Text(scope.label),
                                secondary: Icon(scope.icon),
                              );
                            },
                          ).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: const Text('Create Book'),
                  onPressed: () {
                    final title = titleController.text.trim();

                    if (title.isEmpty) return;

                    Navigator.pop(
                      context,
                      _NewBookData(
                        title: title,
                        subtitle: subtitleController.text.trim(),
                        scope: selectedScope,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    subtitleController.dispose();

    if (result == null) return;

    final newBook = await _repository.createBook(
      AtlasBookProject(
        title: result.title,
        subtitle: result.subtitle,
        scope: result.scope,
        status: 'Planning',
        createdAt: DateTime.now(),
      ),
    );

    if (!mounted) return;

    await _loadBooks();

    if (!mounted) return;

    _openBook(newBook);
  }

  void _openBook(AtlasBookProject book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _AtlasBookWorkspace(book: book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Atlas Book',
                          style:
                              Theme.of(context).textTheme.headlineLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Build family books from the people, photos, stories, '
                          'documents, and heirlooms you preserve.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _createBook,
                    icon: const Icon(Icons.add),
                    label: const Text('Create New Book'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Your Atlas Books',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_books.isEmpty)
                _EmptyAtlasLibrary(onCreateBook: _createBook)
              else
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: _books.map((book) {
                    return _AtlasBookCard(
                      book: book,
                      onTap: () => _openBook(book),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AtlasBookCard extends StatelessWidget {
  final AtlasBookProject book;
  final VoidCallback onTap;

  const _AtlasBookCard({
    required this.book,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (book.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    book.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(book.scope.icon, size: 18),
                    const SizedBox(width: 8),
                    Text(book.scope.label),
                  ],
                ),
                const SizedBox(height: 10),
                Chip(label: Text(book.status)),
                const SizedBox(height: 8),
                Text(
                  'Created ${_formatDate(book.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _EmptyAtlasLibrary extends StatelessWidget {
  final VoidCallback onCreateBook;

  const _EmptyAtlasLibrary({
    required this.onCreateBook,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 68,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Your first family story starts here',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Create an Atlas Book and Heirloom Atlas will help you '
                'bring together the people, photos, documents, stories, '
                'and keepsakes that belong in it.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCreateBook,
                icon: const Icon(Icons.add),
                label: const Text('Create Your First Book'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AtlasBookWorkspace extends StatelessWidget {
  final AtlasBookProject book;

  const _AtlasBookWorkspace({
    required this.book,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (book.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    book.subtitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                const SizedBox(height: 12),
                Chip(
                  avatar: Icon(book.scope.icon, size: 18),
                  label: Text(book.scope.label),
                ),
                const SizedBox(height: 32),
                Text(
                  'Build Your Book',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 18),
                _WorkspaceStep(
                  number: '1',
                  title: _selectionTitle(book.scope),
                  description: _selectionDescription(book.scope),
                  icon: book.scope.icon,
                ),
                const SizedBox(height: 12),
                const _WorkspaceStep(
                  number: '2',
                  title: 'Gather connected material',
                  description:
                      'Find photos, stories, documents, heirlooms, and other '
                      'items connected to the people in this book.',
                  icon: Icons.collections_bookmark_outlined,
                ),
                const SizedBox(height: 12),
                const _WorkspaceStep(
                  number: '3',
                  title: 'Build the story',
                  description:
                      'Organize the selected material into chapters, pages, '
                      'timelines, and family stories.',
                  icon: Icons.menu_book_outlined,
                ),
                const SizedBox(height: 12),
                const _WorkspaceStep(
                  number: '4',
                  title: 'Preview your Atlas Book',
                  description:
                      'Review the finished book before exporting or publishing.',
                  icon: Icons.preview_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _selectionTitle(AtlasBookScope scope) {
    switch (scope) {
      case AtlasBookScope.people:
        return 'Choose people';
      case AtlasBookScope.branch:
        return 'Choose a family branch';
      case AtlasBookScope.generations:
        return 'Choose generations';
    }
  }

  static String _selectionDescription(AtlasBookScope scope) {
    switch (scope) {
      case AtlasBookScope.people:
        return 'Select one or more people from your family tree.';
      case AtlasBookScope.branch:
        return 'Choose the family branch this book will follow.';
      case AtlasBookScope.generations:
        return 'Choose which generations you want represented in the book.';
    }
  }
}

class _WorkspaceStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final IconData icon;

  const _WorkspaceStep({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            CircleAvatar(child: Text(number)),
            const SizedBox(width: 18),
            Icon(
              icon,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewBookData {
  final String title;
  final String subtitle;
  final AtlasBookScope scope;

  const _NewBookData({
    required this.title,
    required this.subtitle,
    required this.scope,
  });
}
