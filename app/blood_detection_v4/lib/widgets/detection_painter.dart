import 'dart:math';
import 'package:flutter/material.dart';
import '../models/detection.dart';

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final double imageWidth;
  final double imageHeight;

  DetectionPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Calculate scale to fit the image in the canvas
    final scale = min(
      size.width / imageWidth,
      size.height / imageHeight,
    );

    final displayedWidth = imageWidth * scale;
    final displayedHeight = imageHeight * scale;

    final dx = (size.width - displayedWidth) / 2;
    final dy = (size.height - displayedHeight) / 2;

    for (final d in detections) {
      // Scale box coordinates to fit the displayed image
      final rect = Rect.fromLTRB(
        dx + d.box.left * scale,
        dy + d.box.top * scale,
        dx + d.box.right * scale,
        dy + d.box.bottom * scale,
      );
      
      // Draw bounding box with green color
      canvas.drawRect(rect, paint);

      // Draw confidence text
      final tp = TextPainter(
        text: TextSpan(
          text: "${(d.confidence * 100).toStringAsFixed(1)}%",
          style: const TextStyle(
            color: Colors.red,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 4,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      tp.layout();
      tp.paint(
        canvas,
        Offset(rect.left, rect.top - 20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}