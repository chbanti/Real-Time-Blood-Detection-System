import 'dart:io';
import 'package:ffmpeg_kit_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoFrameExtractor {
  static Future<List<File>> extractFramesWithFFmpeg(
    File videoFile, {
    int skipFrames = 4,
    int maxFrames = 60,
    Function(int, int)? onProgress,
  }) async {
    try {
      print("📹 Extracting frames using FFmpeg...");
      
      final tempDir = await getTemporaryDirectory();
      final outputPattern = '${tempDir.path}/frame_%d.jpg';
      
      // Calculate fps: For 30fps video, to skip 4 frames, we extract at 30/5 = 6fps
      final int extractFps = (30 / (skipFrames + 1)).ceil();
      final int framesToExtract = maxFrames;
      
      print("📹 Extracting at $extractFps fps, max $framesToExtract frames");
      
      // FFmpeg command: extract frames at specific fps
      final command = '-i "${videoFile.path}" -vf "fps=$extractFps" -vframes $framesToExtract -q:v 2 "$outputPattern"';
      
      print("📹 Running FFmpeg command: $command");
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        print("✅ FFmpeg extraction successful");
        
        // Collect all extracted frames
        final List<File> extractedFiles = [];
        final dir = Directory(tempDir.path);
        final files = dir.listSync();
        
        // Filter and sort files by creation time or name
        final List<File> frameFiles = [];
        for (final file in files) {
          if (file is File && file.path.endsWith('.jpg') && file.path.contains('frame_')) {
            frameFiles.add(file);
          }
        }
        
        // Sort by last modified time (which should be the order they were created)
        frameFiles.sort((a, b) {
          return a.lastModifiedSync().compareTo(b.lastModifiedSync());
        });
        
        int count = 0;
        for (final file in frameFiles) {
          extractedFiles.add(file);
          count++;
          onProgress?.call(count, framesToExtract);
          print("✅ Frame $count extracted: ${file.path.split('/').last}");
        }
        
        print("✅ Total frames extracted: ${extractedFiles.length}");
        return extractedFiles;
        
      } else {
        print("❌ FFmpeg failed with return code: $returnCode");
        final output = await session.getOutput();
        print("FFmpeg output: $output");
        return [];
      }
      
    } catch (e) {
      print("❌ Error extracting frames: $e");
      return [];
    }
  }
  
  static Future<void> cleanupFrames(List<File>? frames) async {
    if (frames == null || frames.isEmpty) return;
    
    int deleted = 0;
    for (final file in frames) {
      try {
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      } catch (e) {
        print("⚠️ Error deleting frame: $e");
      }
    }
    print("✅ Cleaned up $deleted frames");
  }
}