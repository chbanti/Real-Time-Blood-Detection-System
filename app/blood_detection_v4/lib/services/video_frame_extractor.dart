import 'dart:io';
import 'package:ffmpeg_kit_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoFrameExtractor {
  static Future<List<ExtractedFrame>> extractFramesWithFFmpeg(
    File videoFile, {
    int skipFrames = 2,
    int maxFrames = 80,
    Function(int, int)? onProgress,
  }) async {
    try {
      print("📹 Extracting frames using FFmpeg...");
      
      final tempDir = await getTemporaryDirectory();
      final outputPattern = '${tempDir.path}/frame_%d.jpg';
      
      // Calculate fps: For 40fps video, to skip 2 frames, we extract at 40/3 ≈ 13fps
      final int extractFps = (40 / (skipFrames + 1)).ceil();
      final int framesToExtract = maxFrames;
      
      print("📹 Extracting at $extractFps fps, max $framesToExtract frames");
      
      final command = '-i "${videoFile.path}" -vf "fps=$extractFps" -vframes $framesToExtract -q:v 2 "$outputPattern"';
      
      print("📹 Running FFmpeg command: $command");
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        print("✅ FFmpeg extraction successful");
        
        final List<ExtractedFrame> extractedFrames = [];
        final dir = Directory(tempDir.path);
        final files = dir.listSync();
        
        final List<File> frameFiles = [];
        for (final file in files) {
          if (file is File && file.path.endsWith('.jpg') && file.path.contains('frame_')) {
            frameFiles.add(file);
          }
        }
        
        // Sort by file name to get frame numbers
        frameFiles.sort((a, b) {
          final aNum = int.tryParse(a.path.split('_').last.split('.').first) ?? 0;
          final bNum = int.tryParse(b.path.split('_').last.split('.').first) ?? 0;
          return aNum.compareTo(bNum);
        });
        
        int count = 0;
        for (final file in frameFiles) {
          // Extract the frame number from filename
          final frameNum = int.tryParse(file.path.split('_').last.split('.').first) ?? 0;
          
          // Calculate actual video frame number
          // Since we're extracting at specific fps, the frame number from filename 
          // corresponds to the frame index in the extracted sequence
          // The actual video frame = frameNum * (skipFrames + 1)
          final int actualVideoFrame = frameNum * (skipFrames + 1);
          final int timestampMs = actualVideoFrame * 25; // 25ms per frame at 40fps
          
          count++;
          extractedFrames.add(ExtractedFrame(
            file: file,
            frameNumber: frameNum,
            actualVideoFrame: actualVideoFrame,
            timestampMs: timestampMs,
          ));
          
          print("✅ Frame $count: file frame_$frameNum.jpg → video frame $actualVideoFrame (${timestampMs}ms)");
          onProgress?.call(count, framesToExtract);
        }
        
        print("✅ Total frames extracted: ${extractedFrames.length}");
        return extractedFrames;
        
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
  
  static Future<void> cleanupFrames(List<ExtractedFrame>? frames) async {
    if (frames == null || frames.isEmpty) return;
    
    int deleted = 0;
    for (final frame in frames) {
      try {
        if (await frame.file.exists()) {
          await frame.file.delete();
          deleted++;
        }
      } catch (e) {
        print("⚠️ Error deleting frame: ${frame.file.path}");
      }
    }
    print("✅ Cleaned up $deleted frames");
  }
}

// New class to hold extracted frame with metadata
class ExtractedFrame {
  final File file;
  final int frameNumber;        // The number from filename (frame_0.jpg, frame_1.jpg, etc.)
  final int actualVideoFrame;   // The actual video frame number
  final int timestampMs;        // Timestamp in milliseconds

  ExtractedFrame({
    required this.file,
    required this.frameNumber,
    required this.actualVideoFrame,
    required this.timestampMs,
  });
}