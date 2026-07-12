import 'dart:io';
import 'package:image/image.dart' as img;

class SegmentationPreprocessor {
  static Future<List> preprocess(File imageFile) async {
    final bytes = await imageFile.readAsBytes();

    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception("Unable to decode image");
    }

    // Changed from 640 to 224
    image = img.copyResize(
      image,
      width: 224,
      height: 224,
    );

    final input = List.generate(
      1,
      (_) => List.generate(
        224,  // Changed from 640
        (y) => List.generate(
          224,  // Changed from 640
          (x) {
            final pixel = image!.getPixel(x, y);

            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );

    return input;
  }
}