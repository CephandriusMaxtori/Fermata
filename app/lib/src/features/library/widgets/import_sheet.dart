import 'dart:async';

import 'package:fermata_core/fermata_core.dart';
import 'package:fermata_data/fermata_data.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../providers/library_providers.dart';

/// Runs the import flow and returns the created score, or null if cancelled.
///
/// Owns the whole flow in one modal: pick, review any duplicate warning, then
/// import. Returning the score lets the caller open it straight away, which is
/// the common case since a user who just imported something wants to look at
/// it.
Future<Score?> showImportSheet(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ImportCandidate.supportedExtensions
        .map((extension) => extension.substring(1))
        .toList(growable: false),
  );

  if (picked.isEmpty) return null;

  final candidates = [
    for (final file in picked)
      if (file.path != null)
        ImportCandidate(
          sourcePath: file.path!,
          title: _titleFromFileName(file.name),
        ),
  ];

  if (candidates.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Those files could not be read.')),
    );
    return null;
  }

  if (!context.mounted) return null;

  return showModalBottomSheet<Score>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ImportSheet(candidates: candidates),
  );
}

/// Strips a trailing numeric suffix so "scan_003.pdf" previews as "scan".
///
/// Import still stores the file under its original name; this only affects the
/// placeholder title the user can overwrite before importing.
String? _titleFromFileName(String fileName) {
  final stem = p.basenameWithoutExtension(fileName);
  final trimmed = stem.replaceFirst(RegExp(r'[\s_-]*\d+$'), '');
  return trimmed.isEmpty ? stem : trimmed;
}

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet({required this.candidates});

  final List<ImportCandidate> candidates;

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final _titleController = TextEditingController();
  final _composerController = TextEditingController();

  ImportPreview? _preview;
  bool _previewing = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.candidates.length == 1) {
      _titleController.text =
          _titleFromFileName(widget.candidates.first.fileName) ?? '';
    }
    unawaited(_loadPreview());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final service = await ref.read(importServiceProvider.future);
    final preview = await service.preview(widget.candidates);
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _previewing = false;
    });
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final service = await ref.read(importServiceProvider.future);
      final result = await service.importScore(
        widget.candidates,
        title: _titleController.text,
        composer: _composerController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result.score);
    } on ImportException catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final blocked = preview?.hasExactDuplicate ?? false;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Import scores', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.candidates.length} '
              '${widget.candidates.length == 1 ? 'file' : 'files'} selected',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            if (_previewing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (blocked)
              _DuplicateBlocked(
                existing: preview!.exactDuplicate!.blockingScore!,
                onClose: () => Navigator.of(context).pop(),
              )
            else ...[
              if (preview != null && preview.unsupportedFiles.isNotEmpty) ...[
                _Notice(
                  icon: Icons.info_outline_rounded,
                  tone: _NoticeTone.neutral,
                  message:
                      'Skipping ${preview.unsupportedFiles.length} '
                      'unsupported '
                      '${preview.unsupportedFiles.length == 1 ? 'file' : 'files'}.',
                ),
                const SizedBox(height: 12),
              ],
              if (preview != null && preview.hasMetadataSuggestion) ...[
                _Notice(
                  icon: Icons.merge_rounded,
                  tone: _NoticeTone.advisory,
                  message:
                      'You already have '
                      '${preview.metadataMatches.map((s) => '"${s.title}"').join(', ')}. '
                      'Import anyway if this is a different edition.',
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Defaults to the file name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _composerController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Composer'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _Notice(
                  icon: Icons.error_outline_rounded,
                  tone: _NoticeTone.error,
                  message: _error!,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _importing ? null : _import,
                child: _importing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Import'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _importing ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DuplicateBlocked extends StatelessWidget {
  const _DuplicateBlocked({required this.existing, required this.onClose});

  final Score existing;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Notice(
          icon: Icons.content_copy_rounded,
          tone: _NoticeTone.error,
          message:
              'This exact file is already in your library as '
              '"${existing.title}".',
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: onClose, child: const Text('Close')),
      ],
    );
  }
}

enum _NoticeTone { neutral, advisory, error }

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tone,
    required this.message,
  });

  final IconData icon;
  final _NoticeTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (tone) {
      _NoticeTone.error => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
      ),
      _NoticeTone.advisory => (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      ),
      _NoticeTone.neutral => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
