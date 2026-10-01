import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';

import 'brush_selection.dart';

/// A horizontal third of the page area, for tap-to-turn.
enum TapZone { previous, next, none }

/// Colour and width picker for the annotation tools.
class BrushToolbar extends StatelessWidget {
  const BrushToolbar({super.key, required this.selection, required this.onChanged});

  final BrushSelection selection;
  final ValueChanged<BrushSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = selection;
    final colors = current.palette;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ToolToggle(
                icon: Icons.edit_rounded,
                label: 'Pen',
                selected: current.kind == AnnotationKind.pen,
                onTap: () =>
                    onChanged(current.withKind(AnnotationKind.pen)),
              ),
              const SizedBox(width: 8),
              _ToolToggle(
                icon: Icons.brush_rounded,
                label: 'Highlight',
                selected: current.kind == AnnotationKind.highlighter,
                onTap: () =>
                    onChanged(current.withKind(AnnotationKind.highlighter)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final color in colors)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ColorDot(
                      color: color,
                      selected: color == current.color,
                      onTap: () => onChanged(current.copyWith(color: color)),
                    ),
                  ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: Slider(
                    value: current.width.clamp(0.001, 0.03),
                    min: 0.001,
                    max: 0.03,
                    label: (current.width * 1000).toStringAsFixed(1),
                    onChanged: (value) =>
                        onChanged(current.copyWith(width: value)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolToggle extends StatelessWidget {
  const _ToolToggle({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: theme.colorScheme.secondaryContainer,
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        height: 34,
        width: 34,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
