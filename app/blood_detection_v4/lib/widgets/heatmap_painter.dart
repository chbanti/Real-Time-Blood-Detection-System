import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:math';

class HeatmapPainter extends CustomPainter {
  final List<List<double>> mask;
  final double imageWidth;
  final double imageHeight;

  HeatmapPainter({
    required this.mask,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mask.isEmpty) return;

    final scale = min(size.width / imageWidth, size.height / imageHeight);
    final displayWidth = imageWidth * scale;
    final displayHeight = imageHeight * scale;

    final dx = (size.width - displayWidth) / 2;
    final dy = (size.height - displayHeight) / 2;

    // Draw heatmap with lower resolution (better performance)
    const step = 4; // Increase this for better performance (4 or 8)

    final paint = Paint()..style = PaintingStyle.fill;

    for (int y = 0; y < 640; y += step) {
      for (int x = 0; x < 640; x += step) {
        final double p = mask[y][x].clamp(0.0, 1.0);

        paint.color = Color.lerp(
          const Color(0xFF0000FF), // Blue
          const Color(0xFFFF0000), // Red
          p,
        )!.withOpacity(0.55);

        final rect = Rect.fromLTWH(
          dx + x * (displayWidth / 640),
          dy + y * (displayHeight / 640),
          (displayWidth / 640) * step,
          (displayHeight / 640) * step,
        );

        canvas.drawRect(rect, paint);
      }
    }

    _drawColorBar(canvas, dy, displayHeight);
  }

  void _drawColorBar(Canvas canvas, double top, double height) {
    const left = 10.0;
    const width = 18.0;

    final rect = Rect.fromLTWH(left, top, width, height);
    final gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF0000), Color(0xFF800080), Color(0xFF0000FF)],
    );

    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = const TextSpan(text: "High", style: TextStyle(color: Colors.white, fontSize: 12));
    tp.layout();
    tp.paint(canvas, Offset(left + 25, top));

    tp.text = const TextSpan(text: "Low", style: TextStyle(color: Colors.white, fontSize: 12));
    tp.layout();
    tp.paint(canvas, Offset(left + 25, top + height - 12));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}