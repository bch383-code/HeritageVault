import 'package:flutter/material.dart';

import 'core/theme/heritage_theme.dart';
import 'features/shell/museum_shell.dart';

class HeritageVaultApp extends StatelessWidget {
  const HeritageVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heritage Vault',
      theme: HeritageTheme.light(),
      darkTheme: HeritageTheme.dark(),
      themeMode: ThemeMode.system,
      home: const MuseumShell(),
    );
  }
}
