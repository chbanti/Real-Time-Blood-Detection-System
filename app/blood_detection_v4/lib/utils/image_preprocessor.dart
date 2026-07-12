import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../models/image_info.dart';
import 'constants.dart';

class ImagePreprocessor {
  static Future<ImageInfoData> preprocess(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception("Unable to decode image");
    }

    return _preprocessImage(image);
  }

  static Future<ImageInfoData> preprocessCameraImage(CameraImage cameraImage) async {
    img.Image? image = _convertCameraImageToRGB(cameraImage);

    if (image == null) {
      throw Exception("Failed to convert CameraImage");
    }

    return _preprocessImage(image);
  }

  static ImageInfoData _preprocessImage(img.Image image) {
    final int originalWidth = image.width;
    final int originalHeight = image.height;

    // LetterBox Resize to 224x224
    final double scale = (inputWidth / originalWidth).clamp(0.0, double.infinity);
    final double scale2 = (inputHeight / originalHeight).clamp(0.0, double.infinity);
    final double ratio = scale < scale2 ? scale : scale2;

    final int resizedWidth = (originalWidth * ratio).round();
    final int resizedHeight = (originalHeight * ratio).round();

    final resized = img.copyResize(image, width: resizedWidth, height: resizedHeight);

    // Letterbox canvas with gray padding
    final canvas = img.Image(width: inputWidth, height: inputHeight);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final int padX = ((inputWidth - resizedWidth) / 2).round();
    final int padY = ((inputHeight - resizedHeight) / 2).round();

    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    // Tensor [1, 224, 224, 3]
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

  static img.Image? _convertCameraImageToRGB(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;
      final img.Image rgbImage = img.Image(width: width, height: height);

      if (image.format.group == ImageFormatGroup.yuv420 && image.planes.isNotEmpty) {
        final Uint8List yPlane = image.planes[0].bytes;
        final int rowStride = image.planes[0].bytesPerRow;

        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final int index = y * rowStride + x;
            if (index < yPlane.length) {
              final int value = yPlane[index].clamp(0, 255);
              rgbImage.setPixelRgb(x, y, value, value, value);
            }
          }
        }
        return rgbImage;
      }

      return img.Image.fromBytes(
        width: width,
        height: height,
        bytes: image.planes[0].bytes.buffer,
        format: img.Format.uint8,
      );
    } catch (e) {
      print("Camera conversion error: $e");
      return null;
    }
  }
}