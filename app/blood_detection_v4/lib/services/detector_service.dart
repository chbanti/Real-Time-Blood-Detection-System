import 'dart:io';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../utils/image_preprocessor.dart';
import '../utils/yolo_decoder.dart';

class DetectorService {
  Interpreter? _interpreter;

  bool get isLoaded => _interpreter != null;

  Future<void> loadModel() async {
    if (_interpreter != null) return;

    try {
      _interpreter = await Interpreter.fromAsset('assets/models/detector.tflite');
      print("✅ Detector model loaded (224x224)");
      print("Input Shape : ${_interpreter!.getInputTensor(0).shape}");
      print("Output Shape: ${_interpreter!.getOutputTensor(0).shape}");
    } catch (e) {
      print("❌ Failed to load detector model: $e");
      rethrow;
    }
  }

  Future<List<Detection>> detect(File imageFile) async {
    if (_interpreter == null) throw Exception("Detector model is not loaded.");

    try {
      final imageInfo = await ImagePreprocessor.preprocess(imageFile);

      // Output shape for 224x224 model: [1, 300, 6] (same as before)
      final output = List.generate(
        1,
        (_) => List.generate(300, (_) => List.filled(6, 0.0)),
      );

      _interpreter!.run(imageInfo.inputTensor, output);

      final detections = YoloDecoder.decode(output, imageInfo);
      print("Total detections: ${detections.length}");

      return detections;
    } catch (e) {
      print("❌ Error during detection: $e");
      rethrow;
    }
  }

  Future<List<Detection>> detectFromCameraImage(CameraImage cameraImage) async {
    if (_interpreter == null) throw Exception("Detector model is not loaded.");

    try {
      final imageInfo = await ImagePreprocessor.preprocessCameraImage(cameraImage);

      final output = List.generate(
        1,
        (_) => List.generate(300, (_) => List.filled(6, 0.0)),
      );

      _interpreter!.run(imageInfo.inputTensor, output);

      final detections = YoloDecoder.decode(output, imageInfo);
      print("Live detections: ${detections.length}");

      return detections;
    } catch (e) {
      print("❌ Error during camera detection: $e");
      rethrow;
    }
  }

  void close() {
    if (_interpreter != null) {
      try {
        _interpreter!.close();
        _interpreter = null;
        print("✅ Detector model unloaded");
      } catch (e) {
        print("❌ Error closing detector: $e");
      }
    }
  }
}