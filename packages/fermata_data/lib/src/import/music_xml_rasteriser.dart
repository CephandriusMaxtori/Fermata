/// One page of a MusicXML document, already rasterised to PNG.
///
/// The bytes travel rather than the file path on purpose: rendering needs
/// Flutter (the SMuFL font and its metadata are assets of the `crisp_notation`
/// package, which `crisp_notation_core` cannot load because it is pure Dart),
/// but writing them into the library is `FileStore`'s job. Handing back bytes
/// keeps storage in this layer and lets the whole import path stay testable
/// without Flutter.
class RenderedPage {
  const RenderedPage({required this.pngBytes, required this.widthPx, required this.heightPx});

  final List<int> pngBytes;

  /// Pixel dimensions of [pngBytes].
  ///
  /// Recorded for reporting and future re-render decisions; it is deliberately
  /// *not* written to `ScorePage.geometry`, because a bitmap page's geometry is
  /// measured from the decoded image at display time. Storing it would add a
  /// second source of truth that can disagree with the file.
  final double widthPx;
  final double heightPx;
}

/// The result of rendering a MusicXML document.
class MusicXmlRender {
  const MusicXmlRender({required this.pages, this.title, this.composer});

  final List<RenderedPage> pages;

  /// Title from the document's `<work>` / `<movement-title>`, if it had one.
  final String? title;

  final String? composer;
}

/// Renders a MusicXML document into page images.
///
/// Handles both plain `.musicxml` and the zipped `.mxl` container; see
/// `ImportCandidate.isMusicXml`.
///
/// An interface for the same reason [PdfPageCounter] is one: the real
/// implementation needs Flutter to load Bravura and rasterise, which cannot run
/// in a plain `dart test`. Declaring it here keeps the import rules — page
/// ordering, duplicate handling, storage, page rows — testable against a stub,
/// and keeps `crisp_notation` out of this package's dependency graph entirely.
abstract interface class MusicXmlPageRasteriser {
  /// Renders the MusicXML document at [absolutePath].
  ///
  /// Throws [MusicXmlRenderException] if the document cannot be read or
  /// paginated. Implementations must not return an empty page list: a document
  /// that yields no pages is an error, not an empty score.
  Future<MusicXmlRender> render(String absolutePath);
}

/// Raised when a MusicXML document cannot be rendered.
///
/// Deliberately **not** a `FormatException`: the reader in `crisp_notation_core`
/// throws that for a malformed document, and catching it separately is what lets
/// `ImportService` say *which* named file was at fault. Keeping the two distinct
/// means this type has to be raised deliberately by a rasteriser rather than
/// arriving by accident from the XML layer.
class MusicXmlRenderException implements Exception {
  MusicXmlRenderException(this.message);

  final String message;

  @override
  String toString() => 'MusicXmlRenderException: $message';
}

/// Used when no rasteriser is configured.
class NullMusicXmlPageRasteriser implements MusicXmlPageRasteriser {
  const NullMusicXmlPageRasteriser();

  @override
  Future<MusicXmlRender> render(String absolutePath) async =>
      throw MusicXmlRenderException(
        'No MusicXML rasteriser configured; the app must supply one backed by '
        'crisp_notation before importing MusicXML.',
      );
}