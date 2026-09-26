import '../geometry/page_geometry.dart';

/// Where a page's pixels come from.
enum PageSourceKind {
  /// A page of a PDF source file.
  pdf,

  /// A standalone image file, i.e. a scanned page.
  bitmap;

  static PageSourceKind fromName(String name) =>
      PageSourceKind.values.firstWhere(
        (kind) => kind.name == name,
        orElse: () => PageSourceKind.pdf,
      );
}

/// One page of a score, which may be backed by a PDF page or an image file.
///
/// A score is a list of these in [index] order. Import flattens whatever the
/// user picked into this shape, which is why a multi-page PDF and a folder of
/// phone photos can end up as the same kind of library entry.
class ScorePage {
  const ScorePage({
    required this.id,
    required this.scoreId,
    required this.index,
    required this.kind,
    required this.sourcePath,
    this.pdfPageNumber,
    this.geometry,
  });

  final String id;
  final String scoreId;

  /// Zero-based position within the score. Annotation rows reference this.
  final int index;

  final PageSourceKind kind;

  /// Path relative to the owning score's source directory. Never an absolute
  /// path, so a backup can be restored into a different location.
  final String sourcePath;

  /// One-based page number within [sourcePath] when [kind] is
  /// [PageSourceKind.pdf]; null for bitmaps.
  final int? pdfPageNumber;

  /// Intrinsic size in PDF points. Null until the page has been measured.
  final PageGeometry? geometry;

  ScorePage copyWith({int? index, PageGeometry? geometry}) => ScorePage(
    id: id,
    scoreId: scoreId,
    index: index ?? this.index,
    kind: kind,
    sourcePath: sourcePath,
    pdfPageNumber: pdfPageNumber,
    geometry: geometry ?? this.geometry,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'scoreId': scoreId,
    'index': index,
    'kind': kind.name,
    'sourcePath': sourcePath,
    'pdfPageNumber': pdfPageNumber,
    'geometry': geometry == null
        ? null
        : {'widthPt': geometry!.widthPt, 'heightPt': geometry!.heightPt},
  };

  factory ScorePage.fromJson(Map<String, dynamic> json) {
    final rawGeometry = json['geometry'] as Map<String, dynamic>?;
    return ScorePage(
      id: json['id'] as String,
      scoreId: json['scoreId'] as String,
      index: (json['index'] as num).toInt(),
      kind: PageSourceKind.fromName(json['kind'] as String),
      sourcePath: json['sourcePath'] as String,
      pdfPageNumber: (json['pdfPageNumber'] as num?)?.toInt(),
      geometry: rawGeometry == null
          ? null
          : PageGeometry(
              widthPt: (rawGeometry['widthPt'] as num).toDouble(),
              heightPt: (rawGeometry['heightPt'] as num).toDouble(),
            ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScorePage &&
      other.id == id &&
      other.scoreId == scoreId &&
      other.index == index &&
      other.kind == kind &&
      other.sourcePath == sourcePath &&
      other.pdfPageNumber == pdfPageNumber &&
      other.geometry == geometry;

  @override
  int get hashCode =>
      Object.hash(id, scoreId, index, kind, sourcePath, pdfPageNumber, geometry);
}
