import 'package:flutter/material.dart';

import 'core/theme/heritage_theme.dart';
import 'features/shell/museum_shell.dart';

class HeirloomAtlasApp extends StatelessWidget {
  const HeirloomAtlasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heirloom Atlas',
      theme: HeritageTheme.light(),
      darkTheme: HeritageTheme.dark(),
      themeMode: ThemeMode.system,
      home: const MuseumShell(),
    );
  }
}