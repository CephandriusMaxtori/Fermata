import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';

/// The viewer's navigation footer.
///
/// Exists as its own widget rather than inline in the viewer screen so the bar
/// mode logic can be widget-tested directly. Every decision it makes about
/// whether a control is enabled, or what number to print, comes from
/// [BarNavigator] in `fermata_core`, so those tests need no database, no
/// repository and no PDF.
///
/// [barMode] is tri-state on purpose:
///
///  * `null`  — detection has not run or is still running. Shows the "Find bars"
///    affordance and does not pretend to know a bar count.
///  * `false` — detection ran and found no staff. Page stepping, page numbers.
///  * `true`  — bars were found. Bar stepping, bar numbers.
class BarNavigationBar extends StatelessWidget {
  const BarNavigationBar({
    super.key,
    required this.currentPage,
    required this.pageCount,
    required this.barMode,
    required this.cursor,
    required this.layouts,
    required this.onStepPage,
    required this.onStepBar,
    required this.onJumpToPage,
    required this.onDetect,
    required this.onToggleMode,
  });

  /// Zero-based index of the page on screen.
  final int currentPage;
  final int pageCount;

  /// See the class doc for the three cases.
  final bool? barMode;

  final BarCursor cursor;
  final List<BarLayout> layouts;

  final ValueChanged<int> onStepPage;
  final ValueChanged<int> onStepBar;
  final ValueChanged<int> onJumpToPage;
  final VoidCallback onDetect;

  /// Swaps between page stepping and bar stepping.
  ///
  /// Separate from [onStepPage] on purpose: this is a mode change, not a step,
  /// and folding it into a step callback would mean passing a magic delta that
  /// means "step nowhere and switch" — the kind of overload that reads as a bug
  /// later.
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bars = barMode ?? false;
    final position = BarNavigator.positionIn(cursor, layouts);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: bars ? 'Previous bar' : 'Previous page',
                onPressed: bars
                    ? (BarNavigator.isFirst(cursor, layouts)
                        ? null
                        : () => onStepBar(-1))
                    : (currentPage > 0 ? () => onStepPage(-1) : null),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              TextButton(
                onPressed: () => _showPicker(context),
                // A score with no staff has no bar numbers, so this stays on
                // pages rather than inventing a count.
                child: Text(
                  bars && position != null
                      ? 'Bar ${position.current} / ${position.total}'
                      : '${currentPage + 1} / $pageCount',
                ),
              ),
              IconButton(
                tooltip: bars ? 'Next bar' : 'Next page',
                onPressed: bars
                    ? (BarNavigator.isLast(cursor, layouts)
                        ? null
                        : () => onStepBar(1))
                    : (currentPage < pageCount - 1 ? () => onStepPage(1) : null),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                barMode == null
                    ? 'Looking for bars...'
                    : 'Page ${currentPage + 1} of $pageCount',
                style: theme.textTheme.labelSmall,
              ),
              if (barMode == null)
                TextButton.icon(
                  onPressed: onDetect,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Find bars'),
                )
              else
                TextButton.icon(
                  onPressed: onToggleMode,
                  icon: Icon(
                    bars
                        ? Icons.horizontal_rule_rounded
                        : Icons.menu_book_outlined,
                    size: 18,
                  ),
                  label: Text(bars ? 'By page' : 'By bar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: pageCount,
          itemBuilder: (_, index) {
            final layout = index < layouts.length ? layouts[index] : null;
            return ListTile(
              title: Text('Page ${index + 1}'),
              // Saying "no bars" rather than omitting the line keeps the list
              // honest about why bar mode fell back to pages on this score.
              subtitle: Text(
                layout != null && layout.hasStaff
                    ? '${layout.barCount} bars'
                    : 'No bars detected',
              ),
              selected: index == currentPage,
              onTap: () {
                onJumpToPage(index);
                Navigator.of(sheetContext).pop();
              },
            );
          },
        ),
      ),
    );
  }
}