import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class PickResult {
  final File file;
  final bool isVideo;
  PickResult({required this.file, required this.isVideo});
}

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  Future<PickResult?> pickMedia() async {
    final XFile? pickedFile = await _picker.pickMedia(
      imageQuality: 100,
    );

    if (pickedFile == null) return null;

    final bool isVideo = pickedFile.path.toLowerCase().endsWith('.mp4') ||
                        pickedFile.path.toLowerCase().endsWith('.mov');

    return PickResult(file: File(pickedFile.path), isVideo: isVideo);
  }

  Future<PickResult?> pickFromCamera({bool isVideoMode = false}) async {
    await Permission.camera.request();

    if (isVideoMode) {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
      if (video == null) return null;
      return PickResult(file: File(video.path), isVideo: true);
    } else {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (photo == null) return null;
      return PickResult(file: File(photo.path), isVideo: false);
    }
  }

  Future<File?> pickImageFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    return image != null ? File(image.path) : null;
  }

  Future<File?> takePhotoFromCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    return image != null ? File(image.path) : null;
  }
}