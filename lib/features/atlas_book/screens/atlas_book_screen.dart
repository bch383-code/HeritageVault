import 'package:flutter/material.dart';

import '../data/atlas_book_repository.dart';
import '../models/atlas_book_project.dart';
import 'atlas_book_workspace_screen.dart';

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

    if (!mounted) {
      return;
    }

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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 12),
                      RadioGroup<AtlasBookScope>(
                        groupValue: selectedScope,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

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

                    if (title.isEmpty) {
                      return;
                    }

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

    if (result == null) {
      return;
    }

    final newBook = await _repository.createBook(
      AtlasBookProject(
        title: result.title,
        subtitle: result.subtitle,
        scope: result.scope,
        status: 'Planning',
        createdAt: DateTime.now(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadBooks();

    if (!mounted) {
      return;
    }

    _openBook(newBook);
  }

  void _openBook(AtlasBookProject book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AtlasBookWorkspaceScreen(
          book: book,
        ),
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
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
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
