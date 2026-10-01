import 'package:fermata_core/fermata_core.dart';
import 'package:flutter/material.dart';

/// A horizontal third of the page area, for tap-to-turn.
enum TapZone { previous, next, none }

/// The pen or highlighter currently selected.
class BrushSelection {
  const BrushSelection({required this.color, required this.width})
    : kind = AnnotationKind.pen;

  const BrushSelection.highlighter({required this.color, required this.width})
    : kind = AnnotationKind.highlighter;

  /// Packed ARGB.
  final int color;

  /// Stroke width as a fraction of page width.
  final double width;

  final AnnotationKind kind;

  BrushSelection copyWith({int? color, double? width}) => BrushSelection(
    color: color ?? this.color,
    width: width ?? this.width,
  );
}

const _penColors = <int>[
  0xFF1A1A1A,
  0xFFD32F2F,
  0xFF1976D2,
  0xFF388E3C,
  0xFFF9A825,
];

const _highlighterColors = <int>[
  0xFFFFEB3B,
  0xFF80CBC4,
  0xFF90CAF9,
  0xFFFFAB91,
];

/// Colour and width picker for the annotation tools.
class BrushToolbar extends StatelessWidget {
  const BrushToolbar({super.key, required this.selection, required this.onChanged});

  final BrushSelection selection;
  final ValueChanged<BrushSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = selection;
    final colors = current.kind == AnnotationKind.pen
        ? _penColors
        : _highlighterColors;

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
                onTap: () => onChanged(
                  BrushSelection(color: current.color, width: current.width),
                ),
              ),
              const SizedBox(width: 8),
              _ToolToggle(
                icon: Icons.brush_rounded,
                label: 'Highlight',
                selected: current.kind == AnnotationKind.highlighter,
                onTap: () => onChanged(
                  BrushSelection.highlighter(
                    color: current.color,
                    width: current.width,
                  ),
                ),
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
