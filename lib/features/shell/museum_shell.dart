import 'package:flutter/material.dart';

import '../../screens/collections_screen.dart';
import '../../screens/home_screen.dart';

class MuseumShell extends StatefulWidget {
  const MuseumShell({super.key});

  @override
  State<MuseumShell> createState() => _MuseumShellState();
}

class _MuseumShellState extends State<MuseumShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenCollections: () => setState(() => _selectedIndex = 1)),
      const CollectionsScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              extended: MediaQuery.sizeOf(context).width >= 1050,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: _VaultMark(),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Overview'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  selectedIcon: Icon(Icons.collections_bookmark),
                  label: Text('Collections'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(_selectedIndex),
                  child: pages[_selectedIndex],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultMark extends StatelessWidget {
  const _VaultMark();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Heritage Vault',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.account_balance_outlined,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}
