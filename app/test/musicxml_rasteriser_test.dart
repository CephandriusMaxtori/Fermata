import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:fermata/src/providers/crisp_musicxml_rasteriser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The smallest MusicXML that should engrave: one measure, four quarter notes.
///
/// Hand-written rather than a fixture so the expected content is obvious by
/// inspection — the point of these tests is that *something* real was laid out
/// and drawn, and a large opaque fixture would make a failure hard to read.
const String _minimalScore = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <work><work-title>Test Piece</work-title></work>
  <identification>
    <creator type="composer">A Composer</creator>
  </identification>
  <part-list>
    <score-part id="P1"><part-name>Music</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>0</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
    </measure>
    <measure number="2">
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>4</duration><type>whole</type></note>
    </measure>
  </part>
</score-partwise>
''';

Future<File> writeScore(String name, String xml) async {
  final dir = await Directory.systemTemp.createTemp('fermata_mxl_test_');
  addTearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsString(xml);
  return file;
}

/// The PNG signature, so "these bytes are a PNG" is checked rather than assumed.
bool isPng(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

/// Reads width and height out of the IHDR chunk, which immediately follows the
/// signature. This is the check that matters: a page of the right byte count but
/// the wrong dimensions is the failure a bare "is a PNG" assertion would miss.
({int width, int height}) pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
  );
}

void main() {
  // Rasterising goes through dart:ui, so a real Flutter binding is required. This
  // is the concrete reason the renderer lives in app/ and behind an interface:
  // none of this can run under `dart test` in fermata_data.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CrispMusicXmlRasteriser', () {
    test('renders a MusicXML document to a PNG page', () async {
      final file = await writeScore('piece.musicxml', _minimalScore);

      final render = await const CrispMusicXmlRasteriser().render(file.path);

      expect(render.pages, isNotEmpty);
      final bytes = Uint8List.fromList(render.pages.first.pngBytes);
      expect(isPng(bytes), isTrue, reason: 'output is not a PNG');
    });

    test('a two-measure score is one page, not one page per measure', () async {
      // The whole point of pagination: page count comes from the page box, not
      // from the measure count. A bug that split per measure would still pass
      // every other assertion here.
      final file = await writeScore('short.musicxml', _minimalScore);

      final render = await const CrispMusicXmlRasteriser().render(file.path);

      expect(render.pages, hasLength(1));
    });

    test('pages carry A4 proportions, so they are not squashed', () async {
      // A layout composed in the wrong coordinate space shows up here first:
      // the image would be the right bytes at the wrong aspect ratio, and the
      // annotation overlay would be pinned to a page that does not match.
      final file = await writeScore('shape.musicxml', _minimalScore);

      final render = await const CrispMusicXmlRasteriser().render(file.path);
      final size = pngSize(Uint8List.fromList(render.pages.first.pngBytes));

      // A4 is 210 x 297mm, so 1 : sqrt(2).
      expect(size.width / size.height, closeTo(210 / 297, 0.02));
    });

    test('the page contains drawn ink, not just a blank sheet', () async {
      // This is the assertion that guards the silent failure mode. A page
      // rendered before Bravura's SMuFL metadata resolves is still a perfectly
      // valid PNG of the right size — it is simply blank — so size and
      // signature checks both pass on it. Decoding and finding real ink is what
      // distinguishes an engraved page from an empty one.
      final file = await writeScore('ink.musicxml', _minimalScore);

      final render = await const CrispMusicXmlRasteriser().render(file.path);
      final bytes = Uint8List.fromList(render.pages.first.pngBytes);
      final codec = await ui.instantiateImageCodec(bytes);
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      final decoded = frame.image;

      expect(decoded.width, greaterThan(100));
      expect(decoded.height, greaterThan(100));

      // Count dark pixels across the whole page rather than in a fixed band.
      // `layoutPages` only justifies a page vertically when it holds two or more
      // systems, so a one-system page sits just under the top margin and a
      // hard-coded "staff band" samples blank paper — which is exactly what an
      // earlier version of this test did, and it failed for the right reason.
      var dark = 0;
      final data = await decoded.toByteData();
      for (var y = 0; y < decoded.height; y += 2) {
        for (var x = 0; x < decoded.width; x += 2) {
          final pixel = data!.getUint32((y * decoded.width + x) * 4);
          // Bytes are R,G,B,A; ink is any channel well below 0xFF.
          if ((pixel & 0x00FFFFFF) < 0x00808080) dark++;
        }
      }
      expect(dark, greaterThan(50), reason: 'the page is blank');
    });

    test('reads the title and composer out of the document', () async {
      final file = await writeScore('meta.musicxml', _minimalScore);

      final render = await const CrispMusicXmlRasteriser().render(file.path);

      expect(render.title, isNotNull);
      expect(render.composer, contains('Composer'));
    });

    test('a document that is not MusicXML fails rather than rendering blank', () async {
      final file = await writeScore('bad.musicxml', 'not xml at all <<<');

      // Whatever the failure looks like, it must be a failure. A silently empty
      // import would leave the user with a score of blank pages and no idea why.
      await expectLater(
        const CrispMusicXmlRasteriser().render(file.path),
        throwsA(anything),
      );
    });
  });
}