import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate app icon', () async {
    const size = 512.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Draw Material 3 dark surface background
    final paintBg = Paint()
      ..color = const Color(0xFF1E1E2C)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, size, size),
        const Radius.circular(112),
      ),
      paintBg,
    );

    // Draw decorative staff lines
    final paintLine = Paint()
      ..color = const Color(0xFF4A4A6A)
      ..strokeWidth = 4;
    for (var i = 1; i <= 5; i++) {
      final y = size * (i / 6);
      canvas.drawLine(Offset(size * 0.15, y), Offset(size * 0.85, y), paintLine);
    }

    // Draw Fermata symbol (dot under an arc)
    final paintSymbol = Paint()
      ..color = const Color(0xFFD0BCFF) // M3 Primary
      ..style = PaintingStyle.fill;

    // Dot
    canvas.drawCircle(Offset(size * 0.5, size * 0.58), 28, paintSymbol);

    // Arc / Semi-circle above dot
    final paintArc = Paint()
      ..color = const Color(0xFFD0BCFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(size * 0.5, size * 0.58), radius: 75),
      3.14159,
      3.14159,
      false,
      paintArc,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final assetDir = Directory('assets/icon');
    await assetDir.create(recursive: true);
    final file = File('assets/icon/app_icon.png');
    await file.writeAsBytes(bytes);

    expect(file.existsSync(), isTrue);
  });
}
