import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'face_camera_controller.dart';

/// Paints bounding boxes around all detected faces.
class FaceBoundingBoxPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final bool isFrontCamera;

  FaceBoundingBoxPainter({
    required this.faces,
    required this.imageSize,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final face in faces) {
      final rect = _scaleRect(face.boundingBox, size);
      canvas.drawRect(rect, paint);
    }
  }

  Rect _scaleRect(Rect rect, Size widgetSize) {
    final scaleX = widgetSize.width / imageSize.width;
    final scaleY = widgetSize.height / imageSize.height;

    double left = isFrontCamera
        ? widgetSize.width - rect.right * scaleX
        : rect.left * scaleX;
    double right = isFrontCamera
        ? widgetSize.width - rect.left * scaleX
        : rect.right * scaleX;

    return Rect.fromLTRB(
      left,
      rect.top * scaleY,
      right,
      rect.bottom * scaleY,
    );
  }

  @override
  bool shouldRepaint(FaceBoundingBoxPainter oldDelegate) =>
      oldDelegate.faces != faces;
}

/// Full-screen camera preview with bounding box overlay.
class FaceCameraPreview extends StatelessWidget {
  final FaceCameraController controller;

  const FaceCameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.isInitialized || controller.cameraController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final cameraController = controller.cameraController!;
    final isFront =
        cameraController.description.lensDirection ==
        CameraLensDirection.front;

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(cameraController),
        if (controller.previewSize != null)
          CustomPaint(
            painter: FaceBoundingBoxPainter(
              faces: controller.detectedFaces,
              imageSize: controller.previewSize!,
              isFrontCamera: isFront,
            ),
          ),
      ],
    );
  }
}
