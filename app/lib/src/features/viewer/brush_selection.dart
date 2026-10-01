import 'package:fermata_core/fermata_core.dart';

/// The pen or highlighter currently selected, with its colour and width.
///
/// Lives apart from the toolbar because three things need it: the toolbar that
/// edits it, the painter that previews it, and the provider that holds it. A
/// value type that other files depend on should not be nested inside one of them.
///
/// Width is a fraction of page width, so a mark keeps its visual weight
/// relative to the staff however the page is rendered.
class BrushSelection {
  const BrushSelection({required this.color, required this.width})
    : kind = AnnotationKind.pen;

  const BrushSelection.highlighter({required this.color, required this.width})
    : kind = AnnotationKind.highlighter;

  /// Packed ARGB, matching how `Stroke` stores colour so the model layer stays
  /// free of Flutter's `Color`.
  final int color;

  /// Stroke width as a fraction of page width.
  final double width;

  final AnnotationKind kind;

  /// The colours offered for this tool.
  List<int> get palette =>
      kind == AnnotationKind.pen ? penColors : highlighterColors;

  /// Changes colour or width, keeping the tool.
  ///
  /// The tool is carried through deliberately. An earlier version called the pen
  /// constructor here, which meant choosing a colour or dragging the width slider
  /// while the highlighter was selected silently switched the tool back to the
  /// pen - the single most surprising bug in the annotation toolbar, because
  /// nothing on screen showed it happening until the mark was committed.
  BrushSelection copyWith({int? color, double? width}) => BrushSelection._(
    kind: kind,
    color: color ?? this.color,
    width: width ?? this.width,
  );

  /// Switches tool, keeping the colour where the new palette has one.
  ///
  /// The two palettes are disjoint, so carrying a colour across unchanged would
  /// leave the toolbar with no selected dot and the user drawing in a colour they
  /// could not pick again. Falling back to the new palette's first colour keeps
  /// the control and the ink in agreement.
  BrushSelection withKind(AnnotationKind next) {
    if (next == kind) return this;
    final nextPalette =
        next == AnnotationKind.pen ? penColors : highlighterColors;
    return BrushSelection._(
      kind: next,
      color: nextPalette.contains(color) ? color : nextPalette.first,
      width: width,
    );
  }

  const BrushSelection._({
    required this.kind,
    required this.color,
    required this.width,
  });

  @override
  bool operator ==(Object other) =>
      other is BrushSelection &&
      other.kind == kind &&
      other.color == color &&
      other.width == width;

  @override
  int get hashCode => Object.hash(kind, color, width);

  @override
  String toString() =>
      'BrushSelection(${kind.name}, 0x${color.toRadixString(16)}, $width)';
}

/// Pen colours. Exposed so the toolbar and [BrushSelection] cannot disagree.
const List<int> penColors = <int>[
  0xFF1A1A1A,
  0xFFD32F2F,
  0xFF1976D2,
  0xFF388E3C,
  0xFFF9A825,
];

/// Highlighter colours. Disjoint from [penColors] on purpose.
const List<int> highlighterColors = <int>[
  0xFFFFEB3B,
  0xFF80CBC4,
  0xFF90CAF9,
  0xFFFFAB91,
];