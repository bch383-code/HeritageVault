import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'features/settings/backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    // Android/iOS use sqflite's native mobile database factory.
    // This also initializes the global factory used by code that imports
    // sqflite_common_ffi helpers.
    databaseFactory = sqflite.databaseFactory;
  }

  await HeirloomBackupService.applyPendingRestoreIfNeeded();

  runApp(const HeritageVaultApp());
}
