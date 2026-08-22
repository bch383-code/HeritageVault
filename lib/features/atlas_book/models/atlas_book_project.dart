import 'package:flutter/material.dart';

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
