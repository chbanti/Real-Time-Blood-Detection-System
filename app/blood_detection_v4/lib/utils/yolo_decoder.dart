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

    if (data == null || data.length == 0) {
      return detections;
    }

    double maxConf = 0.0;
    int detectionsFound = 0;

    for (int i = 0; i < data.length; i++) {
      if (data[i] == null || data[i].length < 5) continue;
      
      final confidence = data[i][4].toDouble();
      if (confidence > maxConf) maxConf = confidence;

      if (confidence < confidenceThreshold) continue;

      detectionsFound++;

      // Get normalized coordinates [0-1] from model output
      double x1 = data[i][0].toDouble();
      double y1 = data[i][1].toDouble();
      double x2 = data[i][2].toDouble();
      double y2 = data[i][3].toDouble();

      // Clamp to valid range
      x1 = x1.clamp(0.0, 1.0);
      y1 = y1.clamp(0.0, 1.0);
      x2 = x2.clamp(0.0, 1.0);
      y2 = y2.clamp(0.0, 1.0);

      // Convert to original image coordinates
      // The model outputs are normalized to the input size (640x640)
      // We need to map them back to the original image size
      
      // First, get the coordinates in the 640x640 space
      double left640 = x1 * inputWidth;
      double top640 = y1 * inputHeight;
      double right640 = x2 * inputWidth;
      double bottom640 = y2 * inputHeight;

      // Remove padding (letterbox) to get coordinates in the resized image
      // The image was resized with padding, so we need to subtract the padding
      final double paddedLeft = left640 - imageInfo.padX;
      final double paddedTop = top640 - imageInfo.padY;
      final double paddedRight = right640 - imageInfo.padX;
      final double paddedBottom = bottom640 - imageInfo.padY;

      // Scale back to original image size
      // The ratio used was imageInfo.scale (which is the scaling factor)
      final double scale = imageInfo.scale;
      
      double left = (paddedLeft / scale).clamp(0.0, imageInfo.originalWidth.toDouble());
      double top = (paddedTop / scale).clamp(0.0, imageInfo.originalHeight.toDouble());
      double right = (paddedRight / scale).clamp(0.0, imageInfo.originalWidth.toDouble());
      double bottom = (paddedBottom / scale).clamp(0.0, imageInfo.originalHeight.toDouble());

      // Ensure minimum box size
      if (right > left + 5 && bottom > top + 5) {
        detections.add(Detection(
          confidence: confidence,
          box: Rect.fromLTRB(left, top, right, bottom),
        ));
      }
    }

    if (maxConf > 0 || detectionsFound > 0) {
      print("=== YOLO DEBUG ===");
      print("Max confidence: $maxConf");
      print("Detections above threshold: $detectionsFound");
      print("Final detections: ${detections.length}");
      print("==================");
    }

    return detections;
  }
}