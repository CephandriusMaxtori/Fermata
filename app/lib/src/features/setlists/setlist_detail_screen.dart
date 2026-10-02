import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';
import '../library/library_screen.dart';
import '../library/widgets/score_card.dart';

class SetlistDetailScreen extends ConsumerStatefulWidget {
  const SetlistDetailScreen({
    super.key,
    required this.setlist,
    required this.onOpenScore,
  });

  final Setlist setlist;
  final void Function(Score score) onOpenScore;

  @override
  ConsumerState<SetlistDetailScreen> createState() => _SetlistDetailScreenState();
}

class _SetlistDetailScreenState extends ConsumerState<SetlistDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(setlistEntriesProvider(widget.setlist.id));
    final scoresAsync = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.setlist.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              final repo = await ref.read(organizationRepositoryProvider.future);
              if (!context.mounted) return;
              if (value == 'rename') {
                await _renameSetlist(context, ref, widget.setlist);
              } else if (value == 'delete') {
                await repo.deleteSetlist(widget.setlist.id);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete setlist')),
            ],
          ),
        ],
      ),
      body: switch (entriesAsync) {
        AsyncError(:final error) => Center(child: Text('Error: $error')),
        AsyncData(:final value) => switch (scoresAsync) {
          AsyncError(:final error) => Center(child: Text('Error: $error')),
          AsyncData(value: final allScores) =>
            _buildContent(context, ref, widget.setlist.id, value, allScores, theme),
          _ => const Center(child: CircularProgressIndicator()),
        },
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddScoresSheet(context, ref, widget.setlist.id),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add scores'),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    String setlistId,
    List<SetlistEntry> entries,
    List<Score> allScores,
    ThemeData theme,
  ) {
    final scoreMap = {for (final s in allScores) s.id: s};
    final scoresInSetlist = entries
        .map((e) => scoreMap[e.scoreId])
        .whereType<Score>()
        .toList(growable: false);

    if (scoresInSetlist.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text('Setlist is empty', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Tap "Add scores" to add music from your library.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
      itemCount: scoresInSetlist.length,
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) async {
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        final scoreId = scoresInSetlist[oldIndex].id;
        final repo = await ref.read(organizationRepositoryProvider.future);
        await repo.moveSetlistEntry(setlistId, scoreId, newIndex);
      },
      itemBuilder: (context, index) {
        final score = scoresInSetlist[index];
        return Padding(
          key: ValueKey(score.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey('dismiss_${score.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onErrorContainer),
            ),
            onDismissed: (_) async {
              final repo = await ref.read(organizationRepositoryProvider.future);
              await repo.removeScoreFromSetlist(setlistId, score.id);
            },
            child: ScoreCard.list(
              score: score,
              onTap: () => widget.onOpenScore(score),
            ),
          ),
        );
      },
    );
  }

  Future<void> _renameSetlist(BuildContext context, WidgetRef ref, Setlist setlist) async {
    final controller = TextEditingController(text: setlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Setlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Setlist name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    final repo = await ref.read(organizationRepositoryProvider.future);
    await repo.renameSetlist(setlist, name);
  }

  Future<void> _showAddScoresSheet(BuildContext context, WidgetRef ref, String setlistId) async {
    final allScores = await ref.read(libraryProvider.future);
    final entries = await ref.read(setlistEntriesProvider(setlistId).future);
    if (!context.mounted) return;
    final existingIds = entries.map((e) => e.scoreId).toSet();
    final availableScores = allScores.where((Score s) => !existingIds.contains(s.id)).toList();

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Add Scores to Setlist',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: availableScores.isEmpty
                  ? const Center(child: Text('All library scores are already in this setlist.'))
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: availableScores.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final score = availableScores[index];
                        return ListTile(
                          title: Text(score.title),
                          subtitle: Text(score.composer),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            onPressed: () async {
                              final repo = await ref.read(organizationRepositoryProvider.future);
                              await repo.addScoreToSetlist(setlistId, score.id);
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                          onTap: () async {
                            final repo = await ref.read(organizationRepositoryProvider.future);
                            await repo.addScoreToSetlist(setlistId, score.id);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
