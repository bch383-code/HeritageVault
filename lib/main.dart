import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enables SQLite for the Windows desktop app.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const HeritageVaultApp());
}

class HeritageVaultApp extends StatelessWidget {
  const HeritageVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heritage Vault',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5E4A32),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}