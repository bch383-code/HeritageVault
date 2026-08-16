import 'package:flutter/material.dart';

class CustomCollectionIcons {
  static const keys = <String>[
    'inventory','collections','sports','military','jewelry',
    'book','tools','art','star','archive',
  ];

  static IconData fromKey(String key) {
    switch (key) {
      case 'collections': return Icons.collections_bookmark_outlined;
      case 'sports': return Icons.sports_baseball_outlined;
      case 'military': return Icons.military_tech_outlined;
      case 'jewelry': return Icons.diamond_outlined;
      case 'book': return Icons.menu_book_outlined;
      case 'tools': return Icons.handyman_outlined;
      case 'art': return Icons.palette_outlined;
      case 'star': return Icons.star_outline;
      case 'archive': return Icons.archive_outlined;
      default: return Icons.inventory_2_outlined;
    }
  }

  static String label(String key) {
    switch (key) {
      case 'collections': return 'Collection';
      case 'sports': return 'Sports';
      case 'military': return 'Military';
      case 'jewelry': return 'Jewelry';
      case 'book': return 'Books';
      case 'tools': return 'Tools';
      case 'art': return 'Art';
      case 'star': return 'Favorites';
      case 'archive': return 'Archive';
      default: return 'General';
    }
  }
}
