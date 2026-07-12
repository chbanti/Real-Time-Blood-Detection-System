import 'dart:ui';
import '../models/detection.dart';
import '../models/image_info.dart';
import '../utils/constants.dart';

class YoloDecoder {
  static List<Detection> decode(
    List output,
    ImageInfoData imageInfo,
  ) {
    final detections = <Detection>[];
    final data = output[0];

    // Check if data is valid
    if (data == null || data.length == 0) {
      print("⚠️ No output data from model");
      return detections;
    }

    double maxConf = 0.0;
    int detectionsFound = 0;
    int totalPredictions = data.length;

    for (int i = 0; i < totalPredictions; i++) {
      // Check if data[i] is valid
      if (data[i] == null || data[i].length < 5) continue;
      
      final confidence = data[i][4].toDouble();
      if (confidence > maxConf) maxConf = confidence;

      // Use a lower threshold for live camera
      if (confidence < confidenceThreshold) continue;

      detectionsFound++;

      double x1 = data[i][0].toDouble();
      double y1 = data[i][1].toDouble();
      double x2 = data[i][2].toDouble();
      double y2 = data[i][3].toDouble();

      double left = x1 * imageInfo.originalWidth;
      double top = y1 * imageInfo.originalHeight;
      double right = x2 * imageInfo.originalWidth;
      double bottom = y2 * imageInfo.originalHeight;

      left = left.clamp(0.0, imageInfo.originalWidth.toDouble());
      top = top.clamp(0.0, imageInfo.originalHeight.toDouble());
      right = right.clamp(0.0, imageInfo.originalWidth.toDouble());
      bottom = bottom.clamp(0.0, imageInfo.originalHeight.toDouble());

      if (right > left + 5 && bottom > top + 5) {
        detections.add(Detection(
          confidence: confidence,
          box: Rect.fromLTRB(left, top, right, bottom),
        ));
      }
    }

    // Print debug info (only if there are detections or max confidence > 0)
    if (maxConf > 0 || detectionsFound > 0) {
      print("=== YOLO DEBUG ===");
      print("Total predictions: $totalPredictions");
      print("Max confidence: $maxConf");
      print("Detections above threshold: $detectionsFound");
      print("Final detections: ${detections.length}");
      print("==================");
    }

    return detections;
  }
}