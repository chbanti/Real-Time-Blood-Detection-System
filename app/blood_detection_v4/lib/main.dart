import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'models/detection.dart';
import 'services/detector_service.dart';
import 'services/image_picker_service.dart';
import 'services/segmentation_service.dart';
import 'services/video_frame_extractor.dart';
import 'services/live_camera_service.dart';
import 'widgets/detection_painter.dart';
import 'widgets/heatmap_image_painter.dart';
import 'widgets/live_camera_view.dart';
import 'utils/heatmap_generator.dart';

late List<CameraDescription> cameras;

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

enum AnalysisMode {
  detection,
  segmentation,
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ImagePickerService _picker = ImagePickerService();
  final DetectorService _detector = DetectorService();
  final SegmentationService _segmenter = SegmentationService();
  final ScrollController _scrollController = ScrollController();

  // Image
  File? selectedImage;
  List<Detection> detections = [];
  bool modelLoaded = false;
  bool isProcessing = false;
  bool showResult = false;
  bool isLoadingMedia = false;

  double imageWidth = 0;
  double imageHeight = 0;

  AnalysisMode mode = AnalysisMode.detection;
  List<List<double>> segmentationMask = [];
  ui.Image? heatmapImage;

  // Video
  File? selectedVideo;
  bool isVideo = false;
  VideoPlayerController? _videoController;
  
  Map<int, List<Detection>> frameDetections = {};
  List<Detection> currentDetections = [];
  int currentFrameIndex = 0;
  
  bool isVideoAnalyzed = false;
  bool isPlaying = false;
  Timer? _playbackTimer;
  List<File>? extractedFrames = [];
  int totalFramesAnalyzed = 0;
  int totalDetectionsFound = 0;
  double videoAnalysisProgress = 0.0;
  
  int videoFps = 40;
  int totalFramesInVideo = 0;
  double frameDurationMs = 25.0;
  
  Stopwatch? _analysisStopwatch;
  Timer? _progressTimer;
  Duration _elapsedTime = Duration.zero;
  Duration _estimatedRemaining = Duration.zero;
  int _totalFramesToAnalyze = 0;

  // Live Camera
  bool isLiveMode = false;
  LiveCameraService? _liveCameraService;
  List<Detection> liveDetections = [];
  ui.Image? liveFrameImage;
  double liveImageWidth = 0;
  double liveImageHeight = 0;

  DetectorService? _videoDetector;

  @override
  void initState() {
    super.initState();
    loadModels();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _videoController?.dispose();
    heatmapImage?.dispose();
    liveFrameImage?.dispose();
    _playbackTimer?.cancel();
    _progressTimer?.cancel();
    _analysisStopwatch?.stop();
    _cleanupAllFrames();
    _closeVideoModels();
    _liveCameraService?.dispose();
    _detector.close();
    _segmenter.close();
    super.dispose();
  }

  void _closeVideoModels() {
    _videoDetector?.close();
    _videoDetector = null;
  }

  void _cleanupAllFrames() {
    VideoFrameExtractor.cleanupFrames(extractedFrames);
    extractedFrames = [];
    frameDetections.clear();
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _pauseVideoIfPlaying() {
    if (isVideo && isPlaying && _videoController != null) {
      _stopPlayback();
      _videoController!.pause();
    }
  }

  void _startProgressTimer() {
    _analysisStopwatch = Stopwatch()..start();
    _elapsedTime = Duration.zero;
    _estimatedRemaining = Duration.zero;
    
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _elapsedTime = _analysisStopwatch!.elapsed;
        
        if (videoAnalysisProgress > 0 && videoAnalysisProgress < 1) {
          final totalEstimated = Duration(milliseconds: (_elapsedTime.inMilliseconds / videoAnalysisProgress).round());
          _estimatedRemaining = totalEstimated - _elapsedTime;
        }
      });
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _analysisStopwatch?.stop();
    setState(() {
      _elapsedTime = Duration.zero;
      _estimatedRemaining = Duration.zero;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours == '00' 
        ? '$minutes:$seconds'
        : '$hours:$minutes:$seconds';
  }

  Future<void> loadModels() async {
    await _detector.loadModel();
    
    if (mode == AnalysisMode.segmentation) {
      await _segmenter.loadModel();
    }
    
    setState(() => modelLoaded = true);
  }

  void _clearMedia() {
    _pauseVideoIfPlaying();
    _stopProgressTimer();
    
    _playbackTimer?.cancel();
    isPlaying = false;
    isVideoAnalyzed = false;
    _cleanupAllFrames();
    _closeVideoModels();
    _videoController?.dispose();
    _videoController = null;
    
    setState(() {
      selectedImage = null;
      selectedVideo = null;
      isVideo = false;
      detections.clear();
      segmentationMask.clear();
      heatmapImage?.dispose();
      heatmapImage = null;
      showResult = false;
      currentDetections.clear();
      frameDetections.clear();
      totalFramesAnalyzed = 0;
      totalDetectionsFound = 0;
      videoAnalysisProgress = 0.0;
      currentFrameIndex = 0;
      mode = AnalysisMode.detection;
      isLoadingMedia = false;
      _elapsedTime = Duration.zero;
      _estimatedRemaining = Duration.zero;
      _totalFramesToAnalyze = 0;
    });
    
    _showSnackBar("Media cleared", backgroundColor: Colors.blue);
  }

  // ==================== LIVE CAMERA METHODS ====================
// In _startLiveCamera method, store the camera info:

Future<void> _startLiveCamera() async {
  if (_liveCameraService == null) {
    _liveCameraService = LiveCameraService();
    await _liveCameraService!.initializeCamera((detections, frameImage) {
      setState(() {
        liveDetections = detections;
        liveFrameImage = frameImage;
        liveImageWidth = _liveCameraService!.lastImageWidth;
        liveImageHeight = _liveCameraService!.lastImageHeight;
      });
    });
  }

  if (cameras.isEmpty) {
    _showSnackBar("No camera available", backgroundColor: Colors.red);
    return;
  }

  final camera = cameras.firstWhere(
    (c) => c.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
  );

  await _liveCameraService!.startCamera(camera);
  
  setState(() {
    isLiveMode = true;
  });
  
  _showSnackBar("Live camera started", backgroundColor: Colors.green);
}

  Future<void> _stopLiveCamera() async {
    await _liveCameraService?.stopCamera();
    setState(() {
      isLiveMode = false;
      liveDetections = [];
      liveFrameImage = null;
      liveImageWidth = 0;
      liveImageHeight = 0;
    });
    _showSnackBar("Live camera stopped", backgroundColor: Colors.orange);
  }

  void _toggleLiveMode() {
    if (isLiveMode) {
      _stopLiveCamera();
    } else {
      _startLiveCamera();
    }
  }

  // ==================== IMAGE METHODS ====================
  Future<void> _pickFromGallery() async {
    _pauseVideoIfPlaying();
    _stopProgressTimer();
    
    if (isLiveMode) {
      await _stopLiveCamera();
    }
    
    setState(() => isLoadingMedia = true);
    
    final img = await _picker.pickImageFromGallery();
    if (img == null) {
      setState(() => isLoadingMedia = false);
      return;
    }
    await _processSelectedImage(img);
    setState(() => isLoadingMedia = false);
  }

  Future<void> _takePhoto() async {
    _pauseVideoIfPlaying();
    _stopProgressTimer();
    
    if (isLiveMode) {
      await _stopLiveCamera();
    }
    
    setState(() => isLoadingMedia = true);
    
    final img = await _picker.takePhotoFromCamera();
    if (img == null) {
      setState(() => isLoadingMedia = false);
      return;
    }
    await _processSelectedImage(img);
    setState(() => isLoadingMedia = false);
  }

  Future<void> _processSelectedImage(File img) async {
    _playbackTimer?.cancel();
    isPlaying = false;
    isVideoAnalyzed = false;
    _cleanupAllFrames();
    _closeVideoModels();
    selectedVideo = null;
    isVideo = false;
    _videoController?.dispose();
    _videoController = null;

    final decoded = await decodeImageFromList(await img.readAsBytes());

    setState(() {
      selectedImage = img;
      imageWidth = decoded.width.toDouble();
      imageHeight = decoded.height.toDouble();
      detections.clear();
      segmentationMask.clear();
      heatmapImage?.dispose();
      heatmapImage = null;
      showResult = false;
      mode = AnalysisMode.detection;
      isLoadingMedia = false;
    });
  }

  // ==================== VIDEO METHODS ====================
  Future<void> _pickVideoFromGallery() async {
    _pauseVideoIfPlaying();
    _stopProgressTimer();
    
    if (isLiveMode) {
      await _stopLiveCamera();
    }
    
    setState(() => isLoadingMedia = true);
    
    final result = await _picker.pickMedia();
    if (result == null) {
      setState(() => isLoadingMedia = false);
      return;
    }
    await _processSelectedVideo(result.file);
    setState(() => isLoadingMedia = false);
  }

  Future<void> _recordVideo() async {
    _pauseVideoIfPlaying();
    _stopProgressTimer();
    
    if (isLiveMode) {
      await _stopLiveCamera();
    }
    
    setState(() => isLoadingMedia = true);
    
    final result = await _picker.pickFromCamera(isVideoMode: true);
    if (result == null) {
      setState(() => isLoadingMedia = false);
      return;
    }
    await _processSelectedVideo(result.file);
    setState(() => isLoadingMedia = false);
  }

  Future<void> _processSelectedVideo(File video) async {
    selectedImage = null;
    detections.clear();
    segmentationMask.clear();
    heatmapImage?.dispose();
    heatmapImage = null;
    showResult = false;

    _playbackTimer?.cancel();
    isPlaying = false;
    isVideoAnalyzed = false;
    _cleanupAllFrames();
    _closeVideoModels();

    setState(() {
      selectedVideo = video;
      isVideo = true;
      currentDetections.clear();
      frameDetections.clear();
      totalFramesAnalyzed = 0;
      totalDetectionsFound = 0;
      videoAnalysisProgress = 0.0;
      currentFrameIndex = 0;
      mode = AnalysisMode.detection;
      isLoadingMedia = false;
      _elapsedTime = Duration.zero;
      _estimatedRemaining = Duration.zero;
      _totalFramesToAnalyze = 0;
    });

    _videoController = VideoPlayerController.file(video);
    await _videoController!.initialize();
    imageWidth = _videoController!.value.size.width;
    imageHeight = _videoController!.value.size.height;
    
    final totalDuration = _videoController!.value.duration;
    final totalMilliseconds = totalDuration.inMilliseconds;
    totalFramesInVideo = (totalMilliseconds / frameDurationMs).ceil();

    _videoController!.addListener(() {
      if (_videoController!.value.isPlaying && isVideoAnalyzed) {
        final position = _videoController!.value.position;
        final frameIndex = (position.inMilliseconds / frameDurationMs).floor();
        _updateDetectionsForFrame(frameIndex);
      }
    });
  }

  void _updateDetectionsForFrame(int frameIndex) {
    if (frameDetections.isEmpty) return;

    int closestKey = 0;
    int minDiff = 999999;

    for (final key in frameDetections.keys) {
      final diff = (key - frameIndex).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestKey = key;
      }
    }

    if (frameDetections.containsKey(closestKey) && closestKey != currentFrameIndex && minDiff <= 5) {
      setState(() {
        currentDetections = frameDetections[closestKey] ?? [];
        currentFrameIndex = closestKey;
        detections = currentDetections;
      });
    }
  }

  Future<FrameResult> _processSingleFrame(FrameData data) async {
    try {
      final bytes = await data.file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final originalWidth = decoded.width.toDouble();
      final originalHeight = decoded.height.toDouble();

      final detections = await _videoDetector!.detect(data.file);

      return FrameResult(
        frameIndex: data.frameIndex,
        detections: detections,
        mask: [],
        width: originalWidth,
        height: originalHeight,
        success: true,
      );
    } catch (e) {
      return FrameResult(
        frameIndex: data.frameIndex,
        detections: [],
        mask: [],
        width: 0,
        height: 0,
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<void> analyzeVideo() async {
    if (selectedVideo == null || isProcessing || !isVideo) return;

    _closeVideoModels();

    setState(() {
      isProcessing = true;
      showResult = false;
      detections = [];
      frameDetections.clear();
      videoAnalysisProgress = 0.0;
      totalFramesAnalyzed = 0;
      totalDetectionsFound = 0;
      _elapsedTime = Duration.zero;
      _estimatedRemaining = Duration.zero;
    });

    try {
      _showSnackBar("Loading detector model...", backgroundColor: Colors.orange);
      await _ensureVideoDetectorLoaded();

      _showSnackBar("Extracting frames from video...", backgroundColor: Colors.orange);

      const int skipFrames = 4;
      const int maxFrames = 40;
      
      final frames = await VideoFrameExtractor.extractFramesWithFFmpeg(
        selectedVideo!,
        skipFrames: skipFrames,
        maxFrames: maxFrames,
        onProgress: (current, total) {
          setState(() {
            videoAnalysisProgress = current / total;
          });
        },
      );

      if (frames.isEmpty) {
        _showSnackBar("No frames could be extracted", backgroundColor: Colors.red);
        setState(() => isProcessing = false);
        return;
      }

      extractedFrames = frames;
      final totalFrames = frames.length;
      _totalFramesToAnalyze = totalFrames;

      _showSnackBar("Analyzing $totalFrames frames in parallel...", backgroundColor: Colors.orange);
      
      _startProgressTimer();

      final List<FrameData> frameDataList = [];
      for (int i = 0; i < totalFrames; i++) {
        final int videoFrameIndex = i * (skipFrames + 1);
        frameDataList.add(FrameData(
          file: frames[i],
          frameIndex: videoFrameIndex,
        ));
      }

      const int coreCount = 3;
      final List<List<FrameData>> coreGroups = List.generate(coreCount, (_) => []);

      for (int i = 0; i < frameDataList.length; i++) {
        final coreIndex = i % coreCount;
        coreGroups[coreIndex].add(frameDataList[i]);
      }

      final List<Future<List<FrameResult>>> coreFutures = [];

      for (int coreIndex = 0; coreIndex < coreCount; coreIndex++) {
        final coreFrames = coreGroups[coreIndex];
        if (coreFrames.isEmpty) continue;
        final coreFuture = _processCoreFrames(coreFrames, coreIndex);
        coreFutures.add(coreFuture);
      }

      final List<List<FrameResult>> allCoreResults = await Future.wait(coreFutures);

      final List<FrameResult> allResults = [];
      for (final coreResults in allCoreResults) {
        allResults.addAll(coreResults);
      }

      allResults.sort((a, b) => a.frameIndex.compareTo(b.frameIndex));

      int processed = 0;
      for (final result in allResults) {
        processed++;
        if (result.success) {
          if (result.detections.isNotEmpty) {
            frameDetections[result.frameIndex] = result.detections;
            totalDetectionsFound += result.detections.length;
          }
        }

        setState(() {
          totalFramesAnalyzed = processed;
          videoAnalysisProgress = processed / totalFrames;
        });
      }

      _stopProgressTimer();

      isVideoAnalyzed = true;

      if (frameDetections.isNotEmpty) {
        final firstKey = frameDetections.keys.reduce((a, b) => a < b ? a : b);
        currentDetections = frameDetections[firstKey] ?? [];
        detections = currentDetections;
        currentFrameIndex = firstKey;

        setState(() {
          showResult = true;
          isPlaying = true;
        });

        await _videoController!.play();
        _startPlayback();

        _showSnackBar(
          "Analysis complete! Found $totalDetectionsFound detections",
          backgroundColor: Colors.green,
        );
      } else {
        _showSnackBar("No detections found in video", backgroundColor: Colors.orange);
        setState(() => showResult = true);
      }
    } catch (e) {
      print("❌ Error during video analysis: $e");
      _showSnackBar("Error: $e", backgroundColor: Colors.red);
      _stopProgressTimer();
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Future<List<FrameResult>> _processCoreFrames(
    List<FrameData> frames,
    int coreIndex,
  ) async {
    final List<FrameResult> results = [];

    for (int i = 0; i < frames.length; i++) {
      final result = await _processSingleFrame(frames[i]);
      results.add(result);
    }

    return results;
  }

  Future<void> _ensureVideoDetectorLoaded() async {
    if (_videoDetector == null || !_videoDetector!.isLoaded) {
      _videoDetector = DetectorService();
      await _videoDetector!.loadModel();
    }
  }

  void _startPlayback() {
    _playbackTimer?.cancel();
    isPlaying = true;
    setState(() {});

    _playbackTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_videoController == null || !_videoController!.value.isInitialized) {
        timer.cancel();
        return;
      }

      final position = _videoController!.value.position;
      final frameIndex = (position.inMilliseconds / frameDurationMs).floor();
      _updateDetectionsForFrame(frameIndex);

      if (_videoController!.value.position >= _videoController!.value.duration) {
        timer.cancel();
        isPlaying = false;
        setState(() {});
      }
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    isPlaying = false;
    setState(() {});
  }

  void _togglePlayback() {
    if (isPlaying) {
      _stopPlayback();
      _videoController?.pause();
    } else {
      _videoController?.play();
      _startPlayback();
    }
  }

  // ==================== RUN DETECTION ====================
  Future<void> runDetection() async {
    if (isProcessing) return;

    _pauseVideoIfPlaying();
    _stopProgressTimer();

    if (isVideo) {
      await analyzeVideo();
      return;
    }

    if (selectedImage == null) return;

    heatmapImage?.dispose();
    heatmapImage = null;
    segmentationMask = [];

    setState(() {
      isProcessing = true;
      showResult = false;
      detections = [];
    });

    try {
      final result = await computeAnalysis(selectedImage!, mode);

      setState(() {
        detections = result.detections;
        segmentationMask = result.mask;
        heatmapImage = result.heatmapImage;
        showResult = true;
      });
    } catch (e, stack) {
      print("=== CRITICAL ERROR ===");
      print(e);
      print(stack);
    } finally {
      setState(() => isProcessing = false);
    }
  }

  void _toggleMode(AnalysisMode newMode) {
    if (isVideo) return;
    
    _pauseVideoIfPlaying();
    _stopProgressTimer();
    
    setState(() {
      mode = newMode;
    });
    
    _reloadModelsForMode(newMode);
  }
  
  Future<void> _reloadModelsForMode(AnalysisMode newMode) async {
    if (!_detector.isLoaded) {
      await _detector.loadModel();
    }
    
    if (newMode == AnalysisMode.segmentation) {
      if (!_segmenter.isLoaded) {
        await _segmenter.loadModel();
      }
    } else {
      _segmenter.close();
    }
    
    setState(() => modelLoaded = true);
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 380;
    final isLargeScreen = screenSize.width > 600;
    
    final double horizontalPadding = isSmallScreen ? 8 : 16;
    final double mediaHeight = isSmallScreen ? 250 : (isLargeScreen ? 400 : 320);
    final double fontSize = isSmallScreen ? 12 : 16;
    final double titleFontSize = isSmallScreen ? 18 : 22;
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            isLiveMode ? "Live Detection" : (isVideo ? "Video Analysis (40fps)" : "Blood Detection AI"),
            style: TextStyle(fontSize: isSmallScreen ? 16 : 20),
          ),
          centerTitle: true,
          backgroundColor: isLiveMode ? Colors.red[700] : Colors.blue[800],
          foregroundColor: Colors.white,
        ),
        body: !modelLoaded
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ==================== ANALYSIS MODE ====================
                        Text(
                          "Analysis Mode",
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        ToggleButtons(
                          borderRadius: BorderRadius.circular(12),
                          constraints: BoxConstraints(
                            minHeight: isSmallScreen ? 40 : 50,
                            minWidth: isSmallScreen ? 120 : 150,
                          ),
                          isSelected: [mode == AnalysisMode.detection, mode == AnalysisMode.segmentation],
                          onPressed: (isVideo || isLiveMode)
                              ? null
                              : (index) {
                                  final newMode = index == 0 ? AnalysisMode.detection : AnalysisMode.segmentation;
                                  _toggleMode(newMode);
                                },
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 4 : 6),
                              child: Text(
                                "Detection Only",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 12 : fontSize,
                                  color: (isVideo || isLiveMode) && mode == AnalysisMode.detection ? Colors.blue : null,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 4 : 6),
                              child: Text(
                                "Detection\n+ Segmentation",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 12 : fontSize,
                                  color: (isVideo || isLiveMode) ? Colors.grey : null,
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (isVideo || isLiveMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              isVideo ? "⚠️ Segmentation disabled for video analysis" : "⚠️ Segmentation disabled for live camera",
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 12,
                                color: Colors.orange,
                              ),
                            ),
                          ),

                        const SizedBox(height: 30),

                        // ==================== INPUT MEDIA HEADER ====================
                        if (!isLiveMode)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Input Media",
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (selectedImage != null || selectedVideo != null)
                                IconButton(
                                  onPressed: _clearMedia,
                                  icon: const Icon(Icons.clear, color: Colors.red),
                                  tooltip: "Clear Media",
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.red.withOpacity(0.1),
                                    padding: isSmallScreen 
                                        ? const EdgeInsets.all(6) 
                                        : const EdgeInsets.all(8),
                                  ),
                                ),
                            ],
                          ),
                        if (!isLiveMode)
                          const SizedBox(height: 12),

                        // ==================== MEDIA DISPLAY / LIVE CAMERA ====================
                        if (isLiveMode)
                          // Live Camera View
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: Container(
                              height: mediaHeight,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                color: Colors.black12,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: LiveCameraView(
                                  cameraController: _liveCameraService?.controller,
                                  detections: liveDetections,
                                  frameImage: liveFrameImage,
                                  isStreaming: isLiveMode,
                                  imageWidth: liveImageWidth,
                                  imageHeight: liveImageHeight,
                                ),
                              ),
                            ),
                          )
                        else
                          // Media Display
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: Container(
                              height: mediaHeight,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                color: Colors.black12,
                              ),
                              child: isLoadingMedia
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text(
                                            "Loading media...",
                                            style: TextStyle(fontSize: 16, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    )
                                  : selectedImage == null && selectedVideo == null
                                      ? const Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.image, size: 60, color: Colors.grey),
                                              SizedBox(height: 12),
                                              Text(
                                                "No Media Selected",
                                                style: TextStyle(fontSize: 18, color: Colors.grey),
                                              ),
                                              Text(
                                                "Select an image or video from below",
                                                style: TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        )
                                      : isVideo
                                          ? (_videoController != null && _videoController!.value.isInitialized
                                              ? LayoutBuilder(
                                                  builder: (context, constraints) {
                                                    return Stack(
                                                      children: [
                                                        Center(
                                                          child: FittedBox(
                                                            fit: BoxFit.contain,
                                                            child: SizedBox(
                                                              width: _videoController!.value.size.width,
                                                              height: _videoController!.value.size.height,
                                                              child: ClipRRect(
                                                                borderRadius: BorderRadius.circular(15),
                                                                child: VideoPlayer(_videoController!),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        if (isVideoAnalyzed && detections.isNotEmpty)
                                                          Positioned.fill(
                                                            child: ClipRRect(
                                                              borderRadius: BorderRadius.circular(15),
                                                              child: CustomPaint(
                                                                painter: DetectionPainter(
                                                                  detections: detections,
                                                                  imageWidth: imageWidth,
                                                                  imageHeight: imageHeight,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        if (isVideoAnalyzed)
                                                          Positioned(
                                                            top: 8,
                                                            left: 8,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                              decoration: BoxDecoration(
                                                                color: Colors.black.withOpacity(0.7),
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              child: Text(
                                                                "Frame: $currentFrameIndex | Detections: ${detections.length}",
                                                                style: const TextStyle(color: Colors.white, fontSize: 11),
                                                              ),
                                                            ),
                                                          ),
                                                        Positioned(
                                                          bottom: 8,
                                                          left: 8,
                                                          child: IconButton(
                                                            icon: Icon(
                                                              isPlaying ? Icons.pause : Icons.play_arrow,
                                                              color: Colors.white,
                                                              size: 30,
                                                            ),
                                                            onPressed: _togglePlayback,
                                                            style: IconButton.styleFrom(
                                                              backgroundColor: Colors.black.withOpacity(0.5),
                                                            ),
                                                          ),
                                                        ),
                                                        if (isProcessing)
                                                          const Positioned(
                                                            top: 8,
                                                            right: 8,
                                                            child: Text(
                                                              "⚡ Processing",
                                                              style: TextStyle(color: Colors.white, fontSize: 12),
                                                            ),
                                                          ),
                                                        if (!isVideoAnalyzed && !isProcessing)
                                                          Positioned.fill(
                                                            child: Container(
                                                              color: Colors.black.withOpacity(0.3),
                                                              child: Center(
                                                                child: Text(
                                                                  "Press 'Start Analysis'",
                                                                  style: TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: isSmallScreen ? 14 : 18,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  }
                                                )
                                              : const Center(child: CircularProgressIndicator()))
                                          : ClipRRect(
                                              borderRadius: BorderRadius.circular(15),
                                              child: Image.file(
                                                selectedImage!,
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                                height: double.infinity,
                                              ),
                                            ),
                            ),
                          ),

                        const SizedBox(height: 20),

                        // ==================== BUTTONS ====================
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: (isProcessing || isLiveMode) ? null : _pickFromGallery,
                                    icon: Icon(Icons.photo_library, size: isSmallScreen ? 18 : 24),
                                    label: Text(
                                      "Gallery",
                                      style: TextStyle(fontSize: isSmallScreen ? 12 : fontSize),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        vertical: isSmallScreen ? 10 : 14,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: isSmallScreen ? 8 : 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: (isProcessing || isLiveMode) ? null : _takePhoto,
                                    icon: Icon(Icons.camera_alt, size: isSmallScreen ? 18 : 24),
                                    label: Text(
                                      "Camera",
                                      style: TextStyle(fontSize: isSmallScreen ? 12 : fontSize),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        vertical: isSmallScreen ? 10 : 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(height: isSmallScreen ? 8 : 12),

                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: (isProcessing || isLiveMode) ? null : _pickVideoFromGallery,
                                    icon: Icon(Icons.video_library, size: isSmallScreen ? 18 : 24),
                                    label: Text(
                                      "Video Gallery",
                                      style: TextStyle(fontSize: isSmallScreen ? 12 : fontSize),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        vertical: isSmallScreen ? 10 : 14,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: isSmallScreen ? 8 : 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: (isProcessing || isLiveMode) ? null : _recordVideo,
                                    icon: Icon(Icons.videocam, size: isSmallScreen ? 18 : 24),
                                    label: Text(
                                      "Record Video",
                                      style: TextStyle(fontSize: isSmallScreen ? 12 : fontSize),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        vertical: isSmallScreen ? 10 : 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        SizedBox(height: isSmallScreen ? 8 : 12),

                        // ==================== LIVE CAMERA BUTTON ====================
                        if (!isVideo && selectedImage == null && selectedVideo == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ElevatedButton.icon(
                              onPressed: isProcessing ? null : _toggleLiveMode,
                              icon: Icon(
                                isLiveMode ? Icons.stop : Icons.videocam,
                                size: isSmallScreen ? 18 : 24,
                              ),
                              label: Text(
                                isLiveMode ? "Stop Live Camera" : "Start Live Camera",
                                style: TextStyle(fontSize: isSmallScreen ? 14 : fontSize),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 12 : 14,
                                ),
                                backgroundColor: isLiveMode ? Colors.red : Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),

                        // ==================== START ANALYSIS BUTTON ====================
                        ElevatedButton.icon(
                          onPressed: ((selectedImage == null && selectedVideo == null && !isLiveMode) || isProcessing)
                              ? null
                              : runDetection,
                          icon: isProcessing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Icon(Icons.play_arrow, size: isSmallScreen ? 18 : 24),
                          label: Text(
                            isProcessing ? "Running Analysis..." : "Start Analysis",
                            style: TextStyle(fontSize: isSmallScreen ? 14 : fontSize),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: isSmallScreen ? 12 : 14,
                            ),
                            backgroundColor: isLiveMode ? Colors.green[700] : Colors.blue[700],
                            foregroundColor: Colors.white,
                          ),
                        ),

                        // ==================== VIDEO PROGRESS ====================
                        if (isProcessing && isVideo) ...[
                          const SizedBox(height: 16),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Processing frames...",
                                style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                              ),
                              Text(
                                "${(videoAnalysisProgress * 100).toInt()}%",
                                style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: videoAnalysisProgress),
                          
                          const SizedBox(height: 12),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "⏱️ Elapsed: ${_formatDuration(_elapsedTime)}",
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 11 : 13,
                                  color: Colors.grey,
                                ),
                              ),
                              if (_estimatedRemaining > Duration.zero)
                                Text(
                                  "⏳ Remaining: ${_formatDuration(_estimatedRemaining)}",
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 11 : 13,
                                    color: Colors.orange,
                                  ),
                                ),
                            ],
                          ),
                          
                          const SizedBox(height: 8),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "📊 Frames: $totalFramesAnalyzed / ${_totalFramesToAnalyze}",
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 10 : 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                "🎯 Detections: $totalDetectionsFound",
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 10 : 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                "⚡ 3 cores",
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 10 : 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // ==================== VIEW RESULT BUTTON ====================
                        if (showResult && !isVideo && !isLiveMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _scrollController.animateTo(
                                  _scrollController.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.easeInOut,
                                );
                              },
                              icon: const Icon(Icons.arrow_downward),
                              label: Text(
                                "View Result",
                                style: TextStyle(fontSize: isSmallScreen ? 14 : fontSize),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 12 : 14,
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 30),

                        // ==================== RESULTS ====================
                        if (showResult && !isVideo && !isLiveMode) ...[
                          const Divider(thickness: 2, height: 40),
                          Text(
                            "Analysis Result",
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 15),

                          Card(
                            elevation: 5,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: SizedBox(
                              height: mediaHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(15),
                                      child: Image.file(
                                        selectedImage!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  if (mode == AnalysisMode.segmentation && heatmapImage != null)
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(15),
                                        child: CustomPaint(
                                          painter: HeatmapImagePainter(heatmapImage!, imageWidth, imageHeight),
                                        ),
                                      ),
                                    ),
                                  if (detections.isNotEmpty)
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: DetectionPainter(
                                          detections: detections,
                                          imageWidth: imageWidth,
                                          imageHeight: imageHeight,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Mode"), Text(mode == AnalysisMode.detection ? "Detection" : "Detection + Segmentation")]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Detections"), Text(detections.length.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Image Size"), Text("${imageWidth.toInt()} × ${imageHeight.toInt()}")]),
                                  const Divider(),
                                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Status"), Text("Completed", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // ==================== VIDEO STATS ====================
                        if (showResult && isVideo) ...[
                          const Divider(thickness: 2, height: 40),
                          Text(
                            "Video Stats",
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 15),

                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Mode"), Text("Detection Only")]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("FPS"), Text("$videoFps")]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Frames Analyzed"), Text(totalFramesAnalyzed.toString())]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Frames with Detections"), Text(frameDetections.length.toString())]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total Detections"), Text(totalDetectionsFound.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Processing"), Text("⚡ Parallel (3 cores)")]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Time Elapsed"), Text(_formatDuration(_elapsedTime))]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Size"), Text("${imageWidth.toInt()} × ${imageHeight.toInt()}")]),
                                  const Divider(),
                                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Status"), Text("Completed", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // ==================== LIVE CAMERA STATS ====================
                        if (isLiveMode && liveDetections.isNotEmpty) ...[
                          const Divider(thickness: 2, height: 40),
                          Text(
                            "Live Detection Stats",
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 15),

                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Mode"), Text("Live Detection")]),
                                  const Divider(),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Current Detections"), Text(liveDetections.length.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                                  const Divider(),
                                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Status"), Text("🟢 Live", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (isProcessing) const AnalysisLoadingOverlay(),
                ],
              ),
      ),
    );
  }
}

// ====================== DATA CLASSES ======================
class FrameData {
  final File file;
  final int frameIndex;

  FrameData({
    required this.file,
    required this.frameIndex,
  });
}

class FrameResult {
  final int frameIndex;
  final List<Detection> detections;
  final List<List<double>> mask;
  final double width;
  final double height;
  final bool success;
  final String? error;

  FrameResult({
    required this.frameIndex,
    required this.detections,
    required this.mask,
    required this.width,
    required this.height,
    required this.success,
    this.error,
  });
}

// ====================== ANALYSIS ======================
class AnalysisResult {
  final List<Detection> detections;
  final List<List<double>> mask;
  final ui.Image? heatmapImage;

  AnalysisResult({required this.detections, required this.mask, this.heatmapImage});
}

Future<AnalysisResult> computeAnalysis(File imageFile, AnalysisMode mode) async {
  final detector = DetectorService();
  final segmenter = SegmentationService();

  try {
    await detector.loadModel();
    
    if (mode == AnalysisMode.segmentation) {
      await segmenter.loadModel();
    }

    final bytes = await imageFile.readAsBytes();
    final decoded = await decodeImageFromList(bytes);
    final originalWidth = decoded.width.toDouble();
    final originalHeight = decoded.height.toDouble();

    final detections = await detector.detect(imageFile);

    List<List<double>> mask = [];
    ui.Image? heatmapImage;

    if (mode == AnalysisMode.segmentation) {
      mask = await segmenter.segment(imageFile);
      if (mask.isNotEmpty) {
        heatmapImage = await HeatmapGenerator.generateHeatmap(mask, originalWidth, originalHeight);
      }
    }

    return AnalysisResult(detections: detections, mask: mask, heatmapImage: heatmapImage);
  } finally {
    detector.close();
    if (mode == AnalysisMode.segmentation) {
      segmenter.close();
    }
  }
}

// ====================== LOADING OVERLAY ======================
class AnalysisLoadingOverlay extends StatelessWidget {
  const AnalysisLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withOpacity(0.9),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 70, height: 70, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 7)),
              SizedBox(height: 30),
              Text("Analyzing", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text("Please wait...", style: TextStyle(color: Colors.white70, fontSize: 17)),
              SizedBox(height: 40),
              Text("Do not touch the screen", style: TextStyle(color: Colors.white54, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}