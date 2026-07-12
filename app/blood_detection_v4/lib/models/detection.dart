import 'dart:ui';

class Detection {
  final Rect box;
  final double confidence;

  Detection({
    required this.box,
    required this.confidence,
  });

  @override
  String toString() {
    return "Detection(conf=$confidence, box=$box)";
  }
}