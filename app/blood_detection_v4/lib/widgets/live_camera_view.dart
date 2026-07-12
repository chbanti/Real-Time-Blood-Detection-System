import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/detection.dart';

class LiveCameraView extends StatefulWidget {
  final CameraController? cameraController;
  final List<Detection> detections;
  final ui.Image? frameImage;
  final bool isStreaming;
  final double imageWidth;
  final double imageHeight;

  const LiveCameraView({
    super.key,
    this.cameraController,
    this.detections = const [],
    this.frameImage,
    this.isStreaming = false,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  @override
  State<LiveCameraView> createState() => _LiveCameraViewState();
}

class _LiveCameraViewState extends State<LiveCameraView> {
  @override
  Widget build(BuildContext context) {
    if (!widget.isStreaming || widget.cameraController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "Camera not started",
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              "Tap 'Start Live Camera' to begin",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Get the actual camera preview size
        final previewSize = widget.cameraController!.value.previewSize;
        final double previewAspectRatio = previewSize != null 
            ? previewSize.width / previewSize.height 
            : 4.0 / 3.0;
        
        // Calculate the display size maintaining aspect ratio - FITTED (contain)
        double displayWidth = constraints.maxWidth;
        double displayHeight = constraints.maxHeight;
        
        final double containerAspectRatio = constraints.maxWidth / constraints.maxHeight;
        
        // Use BoxFit.contain logic - show entire camera preview without stretching
        if (containerAspectRatio > previewAspectRatio) {
          // Container is wider than preview - match height
          displayWidth = constraints.maxHeight * previewAspectRatio;
          displayHeight = constraints.maxHeight;
        } else {
          // Container is taller than preview - match width
          displayWidth = constraints.maxWidth;
          displayHeight = constraints.maxWidth / previewAspectRatio;
        }
        
        // Calculate offsets to center the preview
        // final double offsetX = (constraints.maxWidth - displayWidth) / 2;
        // final double offsetY = (constraints.maxHeight - displayHeight) / 2;

        // Calculate scale factors for proper mapping
        final double scaleX = displayWidth / widget.imageWidth;
        final double scaleY = displayHeight / widget.imageHeight;
        final double scale = scaleX < scaleY ? scaleX : scaleY;

        // Image offsets after scaling
        final double imageOffsetX = (displayWidth - (widget.imageWidth * scale)) / 2;
        final double imageOffsetY = (displayHeight - (widget.imageHeight * scale)) / 2;

        return Container(
          color: Colors.black, // Background color for letterbox
          child: Center(
            child: Stack(
              fit: StackFit.loose,
              children: [
                // Camera preview with proper aspect ratio - NO STRETCHING
                Container(
                  width: displayWidth,
                  height: displayHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: CameraPreview(widget.cameraController!),
                  ),
                ),
                
                // Detection overlay with proper mapping
                if (widget.detections.isNotEmpty && widget.imageWidth > 0 && widget.imageHeight > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    width: displayWidth,
                    height: displayHeight,
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: CustomPaint(
                          painter: LiveDetectionPainter(
                            detections: widget.detections,
                            imageWidth: widget.imageWidth,
                            imageHeight: widget.imageHeight,
                            displayWidth: displayWidth,
                            displayHeight: displayHeight,
                            offsetX: imageOffsetX,
                            offsetY: imageOffsetY,
                            scale: scale,
                          ),
                          size: Size(displayWidth, displayHeight),
                        ),
                      ),
                    ),
                  ),
                
                // Info overlay - Detection count
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "Detections: ${widget.detections.length}",
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                
                // Live indicator
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          "LIVE",
                          style: TextStyle(
                            color: Colors.white, 
                            fontSize: 10, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Custom painter with proper coordinate mapping
class LiveDetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final double imageWidth;
  final double imageHeight;
  final double displayWidth;
  final double displayHeight;
  final double offsetX;
  final double offsetY;
  final double scale;

  LiveDetectionPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.displayWidth,
    required this.displayHeight,
    required this.offsetX,
    required this.offsetY,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final d in detections) {
      // Scale and position the box correctly
      final rect = Rect.fromLTRB(
        offsetX + d.box.left * scale,
        offsetY + d.box.top * scale,
        offsetX + d.box.right * scale,
        offsetY + d.box.bottom * scale,
      );
      
      // Draw bounding box
      canvas.drawRect(rect, paint);

      // Draw confidence text
      final tp = TextPainter(
        text: TextSpan(
          text: "${(d.confidence * 100).toStringAsFixed(1)}%",
          style: const TextStyle(
            color: Colors.red,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 4,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      tp.layout();
      tp.paint(
        canvas,
        Offset(rect.left, rect.top - 20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}