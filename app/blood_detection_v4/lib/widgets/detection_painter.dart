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

    // Calculate the display area
    final double displayWidth = size.width;
    final double displayHeight = size.height;
    
    // Calculate scale to fit the image in the canvas (maintaining aspect ratio)
    final double scaleX = displayWidth / imageWidth;
    final double scaleY = displayHeight / imageHeight;
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    // Calculate offsets to center the image
    final double offsetX = (displayWidth - (imageWidth * scale)) / 2;
    final double offsetY = (displayHeight - (imageHeight * scale)) / 2;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final d in detections) {
      // Map the box from image coordinates to display coordinates
      // The detection boxes are already in original image coordinates
      final rect = Rect.fromLTRB(
        offsetX + d.box.left * scale,
        offsetY + d.box.top * scale,
        offsetX + d.box.right * scale,
        offsetY + d.box.bottom * scale,
      );
      
      // Draw bounding box
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