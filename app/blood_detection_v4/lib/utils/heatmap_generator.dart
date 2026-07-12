import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class HeatmapGenerator {
  static Future<ui.Image?> generateHeatmap(
    List<List<double>> mask,
    double imageWidth,
    double imageHeight,
  ) async {
    if (mask.isEmpty) return null;

    // Changed from 640 to 224
    const int maskSize = 224;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..style = PaintingStyle.fill;

    // Adjust step for 224 size (smaller step for better quality)
    const step = 2;  // Changed from 4 to 2 for 224 size

    for (int y = 0; y < maskSize; y += step) {
      for (int x = 0; x < maskSize; x += step) {
        final double p = mask[y][x].clamp(0.0, 1.0);

        paint.color = Color.lerp(
          const Color(0xFF0000FF),
          const Color(0xFFFF0000),
          p,
        )!.withOpacity(0.55);

        canvas.drawRect(
          Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            step.toDouble(),
            step.toDouble(),
          ),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(maskSize, maskSize);
  }
}