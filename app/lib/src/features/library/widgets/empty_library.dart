import 'package:flutter/material.dart';

/// Shown when the library has no scores yet.
///
/// Import is the only thing a new user can do, so the empty state offers it
/// directly rather than describing the feature and leaving the user to find it.
class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key, required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 132,
              width: 132,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.library_music_rounded,
                size: 60,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Your library is empty',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a PDF or a few photos of printed pages. '
              'Everything stays on this device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Import scores'),
            ),
          ],
        ),
      ),
    );
  }
}
