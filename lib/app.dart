import 'dart:io';

import 'package:flutter/material.dart';

import 'core/theme/heritage_theme.dart';
import 'features/mobile/mobile_capture_home.dart';
import 'features/shell/museum_shell.dart';

class HeritageVaultApp extends StatelessWidget {
  const HeritageVaultApp({super.key});

  bool get _useMobileCaptureShell =>
      Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heirloom Atlas',
      theme: HeritageTheme.light(),
      darkTheme: HeritageTheme.dark(),
      themeMode: ThemeMode.system,
      home: _useMobileCaptureShell
          ? const MobileCaptureHome()
          : const MuseumShell(),
    );
  }
}
