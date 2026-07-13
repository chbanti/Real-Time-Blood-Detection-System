import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../models/image_info.dart';
import '../utils/yolo_decoder.dart';

class LiveCameraService {
  CameraController? _controller;
  bool _isStreaming = false;
  Interpreter? _interpreter;
  
  int _frameCounter = 0;
  int _skipFrames = 1;
  
  double _lastImageWidth = 640;
  double _lastImageHeight = 480;
  bool _isFrontCamera = false;
  
  // Confidence threshold for live camera
  double _confidenceThreshold = 0.1;
  
  Function(List<Detection> detections, ui.Image? frameImage)? onDetection;

  bool get isStreaming => _isStreaming;
  CameraController? get controller => _controller;
  double get lastImageWidth => _lastImageWidth;
  double get lastImageHeight => _lastImageHeight;
  bool get isFrontCamera => _isFrontCamera;
  
  double get confidenceThreshold => _confidenceThreshold;
  set confidenceThreshold(double value) {
    _confidenceThreshold = value.clamp(0.0, 1.0);
    print("🔧 Confidence threshold set to: $_confidenceThreshold");
  }

  Future<void> initializeCamera(Function(List<Detection>, ui.Image?) callback) async {
    onDetection = callback;
    
    if (_interpreter == null) {
      _interpreter = await Interpreter.fromAsset('assets/models/detector.tflite');
      print("✅ Live camera detector model loaded (640x640)");
      print("Input Shape: ${_interpreter!.getInputTensor(0).shape}");
    }
  }

  Future<void> startCamera(CameraDescription camera) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
    
    final previewSize = _controller!.value.previewSize;
    if (previewSize != null) {
      _lastImageWidth = previewSize.width;
      _lastImageHeight = previewSize.height;
    }
    
    await _controller!.startImageStream(_processCameraImage);
    _isStreaming = true;
    print("📹 Camera streaming started at ${_lastImageWidth}x${_lastImageHeight}");
    print("📹 Camera lens: ${_isFrontCamera ? 'Front' : 'Back'}");
    print("📹 Confidence threshold: $_confidenceThreshold");
  }

  void _processCameraImage(CameraImage cameraImage) {
    if (!_isStreaming || _interpreter == null) return;

    _frameCounter++;
    if (_frameCounter % _skipFrames != 0) return;

    try {
      final image = _convertCameraImageToImage(cameraImage);
      if (image == null) return;

      // Preprocess for detection (640x640)
      final imageInfo = _preprocessImageForDetection(image);
      
      final output = List.generate(
        1,
        (_) => List.generate(300, (_) => List.filled(6, 0.0)),
      );
      
      _interpreter!.run(imageInfo.inputTensor, output);
      
      final detections = YoloDecoder.decode(output, imageInfo);
      
      // Filter by confidence threshold
      final filteredDetections = detections
          .where((d) => d.confidence > _confidenceThreshold)
          .toList();
      
      final displayImage = _convertToUiImage(image);
      
      onDetection?.call(filteredDetections, displayImage);
      
    } catch (e) {
      // Silent error
    }
  }

  // Detection preprocessing - 640x640
  ImageInfoData _preprocessImageForDetection(img.Image image) {
    final int originalWidth = image.width;
    final int originalHeight = image.height;

    const int inputWidth = 640;   // Detection uses 640
    const int inputHeight = 640;  // Detection uses 640

    final double scale = (inputWidth / originalWidth).clamp(0.0, double.infinity);
    final double scale2 = (inputHeight / originalHeight).clamp(0.0, double.infinity);
    final double ratio = scale < scale2 ? scale : scale2;

    final int resizedWidth = (originalWidth * ratio).round();
    final int resizedHeight = (originalHeight * ratio).round();

    final resized = img.copyResize(image, width: resizedWidth, height: resizedHeight);

    final canvas = img.Image(width: inputWidth, height: inputHeight);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final int padX = ((inputWidth - resizedWidth) / 2).round();
    final int padY = ((inputHeight - resizedHeight) / 2).round();

    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    final input = List.generate(
      1,
      (_) => List.generate(
        inputHeight,
        (y) => List.generate(
          inputWidth,
          (x) {
            final pixel = canvas.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );

    return ImageInfoData(
      inputTensor: input,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
      scale: ratio,
      padX: padX.toDouble(),
      padY: padY.toDouble(),
    );
  }

  img.Image? _convertCameraImageToImage(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;
      
      final img.Image image = img.Image(width: width, height: height);

      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        final Uint8List yPlane = cameraImage.planes[0].bytes;
        final Uint8List uPlane = cameraImage.planes[1].bytes;
        final Uint8List vPlane = cameraImage.planes[2].bytes;
        
        final int yRowStride = cameraImage.planes[0].bytesPerRow;
        final int uvRowStride = cameraImage.planes[1].bytesPerRow;
        final int uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final int yIndex = y * yRowStride + x;
            final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
            
            if (yIndex < yPlane.length && uvIndex < uPlane.length && uvIndex < vPlane.length) {
              final int yValue = yPlane[yIndex] & 0xFF;
              final int uValue = uPlane[uvIndex] & 0xFF;
              final int vValue = vPlane[uvIndex] & 0xFF;
              
              int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
              int g = (yValue - 0.344 * (uValue - 128) - 0.714 * (vValue - 128)).round().clamp(0, 255);
              int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
              image.setPixelRgb(x, y, r, g, b);
            }
          }
        }
        return image;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  ui.Image? _convertToUiImage(img.Image image) {
    try {
      final displayImage = img.copyResize(image, width: 320, height: 240);
      final bytes = img.encodePng(displayImage);
      return decodeImageFromList(bytes) as ui.Image?;
    } catch (e) {
      return null;
    }
  }

  Future<void> stopCamera() async {
    _isStreaming = false;
    if (_controller != null) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }
    print("📹 Camera streaming stopped");
  }

  void dispose() {
    _isStreaming = false;
    _controller?.dispose();
    _interpreter?.close();
    _controller = null;
    _interpreter = null;
  }

  Future<void> switchCamera(CameraDescription camera) async {
    await stopCamera();
    await startCamera(camera);
  }
}