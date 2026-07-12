import 'dart:io';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/segmentation_decoder.dart';
import '../utils/segmentation_preprocessor.dart';

class SegmentationService {
  Interpreter? _interpreter;

  bool get isLoaded => _interpreter != null;

  Future<void> loadModel() async {
    if (_interpreter != null) {
      print("✅ Segmentation model already loaded");
      return;
    }

    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/segmentation.tflite',
      );

      print("✅ Segmentation model loaded (224x224)");
      print("Input Shape : ${_interpreter!.getInputTensor(0).shape}");
      print("Output Shape: ${_interpreter!.getOutputTensor(0).shape}");
    } catch (e) {
      print("❌ Failed to load segmentation model: $e");
      rethrow;
    }
  }

  Future<List<List<double>>> segment(File imageFile) async {
    if (_interpreter == null) {
      throw Exception("Segmentation model is not loaded.");
    }

    try {
      final input = await SegmentationPreprocessor.preprocess(imageFile);

      // Output shape: [1, 224, 224, 1]
      final output = List.generate(
        1,
        (_) => List.generate(
          224,  // Changed from 640
          (_) => List.generate(
            224,  // Changed from 640
            (_) => List.filled(1, 0.0),
          ),
        ),
      );

      _interpreter!.run(input, output);

      print("✅ Segmentation Inference Completed");

      return SegmentationDecoder.decode(output);
    } catch (e) {
      print("❌ Error during segmentation: $e");
      rethrow;
    }
  }

  void close() {
    if (_interpreter != null) {
      try {
        _interpreter!.close();
        _interpreter = null;
        print("✅ Segmentation model unloaded");
      } catch (e) {
        print("❌ Error closing segmentation model: $e");
      }
    }
  }
}