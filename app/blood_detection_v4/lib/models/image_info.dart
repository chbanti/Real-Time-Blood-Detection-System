// models/image_info.dart
class ImageInfoData {
  final List<List<List<List<double>>>> inputTensor;

  final int originalWidth;
  final int originalHeight;

  final double scale;

  final double padX;
  final double padY;

  ImageInfoData({
    required this.inputTensor,
    required this.originalWidth,
    required this.originalHeight,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}