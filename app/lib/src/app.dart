import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';

import 'features/library/library_screen.dart';
import 'features/viewer/score_viewer_screen.dart';
import 'theme/fermata_theme.dart';

class FermataApp extends StatelessWidget {
  const FermataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fermata',
      debugShowCheckedModeBanner: false,
      theme: FermataTheme.light(),
      darkTheme: FermataTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}

/// Root navigation.
///
/// Deliberately a plain [Navigator] with pushed routes rather than a routing
/// package: the app has a library, a viewer, and later a setlists and settings
/// tab, which is not enough surface to justify the dependency yet.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          LibraryScreen(onOpenScore: _openScore),
          const _PlaceholderTab(
            icon: Icons.queue_music_rounded,
            title: 'Setlists',
            message: 'Coming after the library.',
          ),
          const _PlaceholderTab(
            icon: Icons.settings_rounded,
            title: 'Settings',
            message:
                'Pedal mappings, text scaling and backup live here once the '
                'viewer is in place.',
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music_rounded),
            label: 'Setlists',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _openScore(Score score) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScoreViewerScreen(scoreId: score.id, title: score.title),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
