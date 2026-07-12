import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class HeatmapImagePainter extends CustomPainter {
  final ui.Image image;
  final double imageWidth;
  final double imageHeight;

  HeatmapImagePainter(this.image, this.imageWidth, this.imageHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / imageWidth).clamp(0.0, size.height / imageHeight);
    final displayWidth = imageWidth * scale;
    final displayHeight = imageHeight * scale;

    final dx = (size.width - displayWidth) / 2;
    final dy = (size.height - displayHeight) / 2;

    // Draw Heatmap Image
    final paint = Paint();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(dx, dy, displayWidth, displayHeight),
      paint,
    );

    // Draw Color Bar (Legend)
    _drawColorBar(canvas, dy, displayHeight);
  }

  void _drawColorBar(Canvas canvas, double top, double height) {
    const left = 20.0;
    const width = 20.0;

    final rect = Rect.fromLTWH(left, top + 20, width, height - 60);

    final gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFFF0000), // High
        Color(0xFF800080),
        Color(0xFF0000FF), // Low
      ],
    );

    canvas.drawRect(
      rect,
      Paint()..shader = gradient.createShader(rect),
    );

    // Text "High"
    final tpHigh = TextPainter(
      text: const TextSpan(
        text: "High",
        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tpHigh.layout();
    tpHigh.paint(canvas, Offset(left + 30, top + 15));

    // Text "Low"
    final tpLow = TextPainter(
      text: const TextSpan(
        text: "Low",
        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tpLow.layout();
    tpLow.paint(canvas, Offset(left + 30, top + height - 45));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}