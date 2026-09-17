import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/heritage_theme.dart';
import 'core/theme/heritage_backdrop.dart';
import 'features/mobile/mobile_capture_home.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/museum_shell.dart';

class HeritageVaultApp extends StatelessWidget {
  const HeritageVaultApp({super.key});

  bool get _useMobileCaptureShell => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heirloom Atlas',
      theme: HeritageTheme.light(),
      darkTheme: HeritageTheme.dark(),
      // Private Beta 1 ships with the Historic theme.
      // A selectable Modern theme is planned separately.
      themeMode: ThemeMode.dark,
      builder: (context, child) =>
          HeritageBackdrop(child: child ?? const SizedBox.shrink()),
      home: _useMobileCaptureShell
          ? const MobileCaptureHome()
          : const _DesktopStartupGate(),
    );
  }
}

class _DesktopStartupGate extends StatefulWidget {
  const _DesktopStartupGate();

  @override
  State<_DesktopStartupGate> createState() => _DesktopStartupGateState();
}

class _DesktopStartupGateState extends State<_DesktopStartupGate> {
  bool? _betaActivated;
  bool? _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final activated = prefs.getBool('private_beta_activated') ?? false;
    final complete = prefs.getBool('onboarding_completed') ?? false;
    if (!mounted) return;
    setState(() {
      _betaActivated = activated;
      _onboardingComplete = complete;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activated = _betaActivated;
    final complete = _onboardingComplete;
    if (activated == null || complete == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!activated) {
      return _PrivateBetaActivationScreen(
        onActivated: () {
          if (!mounted) return;
          setState(() => _betaActivated = true);
        },
      );
    }

    if (complete) return const MuseumShell();

    return OnboardingScreen(
      onComplete: () {
        if (!mounted) return;
        setState(() => _onboardingComplete = true);
      },
    );
  }
}


class _PrivateBetaActivationScreen extends StatefulWidget {
  const _PrivateBetaActivationScreen({required this.onActivated});
  final VoidCallback onActivated;

  @override
  State<_PrivateBetaActivationScreen> createState() => _PrivateBetaActivationScreenState();
}

class _PrivateBetaActivationScreenState extends State<_PrivateBetaActivationScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  static const _validCodes = <String>{
    'HA-BETA-0001', 'HA-BETA-0002', 'HA-BETA-0003', 'HA-BETA-0004', 'HA-BETA-0005',
    'HA-BETA-0006', 'HA-BETA-0007', 'HA-BETA-0008', 'HA-BETA-0009', 'HA-BETA-0010',
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final code = _controller.text.trim().toUpperCase();
    if (!_validCodes.contains(code)) {
      setState(() => _error = 'That invite code was not recognized.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('private_beta_activated', true);
    await prefs.setString('private_beta_invite_code', code);
    if (!mounted) return;
    widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Heirloom Atlas', textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text('Private Beta', textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 24),
                    const Text(
                      'Enter the invite code you received to activate this Private Beta copy of Heirloom Atlas.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Invite code',
                        hintText: 'HA-BETA-0001',
                        errorText: _error,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) { if (!_saving) _activate(); },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving ? null : _activate,
                      child: Text(_saving ? 'Activating…' : 'Activate Private Beta'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your collection remains on your computer. Your collection is yours. Not ours.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
