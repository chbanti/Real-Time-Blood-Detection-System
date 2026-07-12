import 'dart:math';

class SegmentationDecoder {
  static List<List<double>> decode(List output) {
    // Changed from 640 to 224
    final mask = List.generate(
      224,
      (_) => List.filled(224, 0.0),
    );

    double minValue = double.infinity;
    double maxValue = -double.infinity;

    for (int y = 0; y < 224; y++) {  // Changed from 640
      for (int x = 0; x < 224; x++) {  // Changed from 640
        final double logit = output[0][y][x][0];

        if (logit < minValue) minValue = logit;
        if (logit > maxValue) maxValue = logit;
      }
    }

    print("========== Segmentation ==========");
    print("Logit Min : $minValue");
    print("Logit Max : $maxValue");
    print("==================================");

    final range = max(maxValue - minValue, 1e-6);

    for (int y = 0; y < 224; y++) {  // Changed from 640
      for (int x = 0; x < 224; x++) {  // Changed from 640
        final double logit = output[0][y][x][0];
        mask[y][x] = (logit - minValue) / range;
      }
    }

    return mask;
  }
}