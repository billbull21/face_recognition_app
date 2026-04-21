import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'face_camera_controller.dart';

/// Paints bounding boxes mapped to BoxFit.cover screen coordinates.
class FaceBoundingBoxPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final bool isFrontCamera;
  final double scale;
  final double offsetX;
  final double offsetY;

  const FaceBoundingBoxPainter({
    required this.faces,
    required this.imageSize,
    required this.isFrontCamera,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final face in faces) {
      canvas.drawRect(_scaleRect(face.boundingBox, size), paint);
    }
  }

  Rect _scaleRect(Rect rect, Size widgetSize) {
    // With BoxFit.cover, a uniform scale is applied and one axis may be cropped.
    // offsetX/offsetY are negative when the image extends beyond the widget edge.
    final double left = isFrontCamera
        ? widgetSize.width - (rect.right * scale + offsetX)
        : rect.left * scale + offsetX;
    final double right = isFrontCamera
        ? widgetSize.width - (rect.left * scale + offsetX)
        : rect.right * scale + offsetX;

    return Rect.fromLTRB(
      left,
      rect.top * scale + offsetY,
      right,
      rect.bottom * scale + offsetY,
    );
  }

  @override
  bool shouldRepaint(FaceBoundingBoxPainter oldDelegate) =>
      oldDelegate.faces != faces || oldDelegate.scale != scale;
}

/// Full-screen camera preview with bounding box overlay.
/// Uses BoxFit.cover so the preview fills the screen without stretching.
class FaceCameraPreview extends StatelessWidget {
  final FaceCameraController controller;

  const FaceCameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.isInitialized ||
        controller.cameraController == null ||
        controller.previewSize == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final cam = controller.cameraController!;
    final isFront = cam.description.lensDirection == CameraLensDirection.front;
    final previewSize = controller.previewSize!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = constraints.biggest;

        // Compute the uniform scale factor for BoxFit.cover
        final scaleX = screenSize.width / previewSize.width;
        final scaleY = screenSize.height / previewSize.height;
        final scale = scaleX > scaleY ? scaleX : scaleY;

        // Offset is negative on the cropped axis (image extends past widget edge)
        final offsetX = (screenSize.width - previewSize.width * scale) / 2;
        final offsetY = (screenSize.height - previewSize.height * scale) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            // FittedBox.cover fills the screen without distorting aspect ratio
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.width,
                height: previewSize.height,
                child: CameraPreview(cam),
              ),
            ),
            CustomPaint(
              painter: FaceBoundingBoxPainter(
                faces: controller.detectedFaces,
                imageSize: previewSize,
                isFrontCamera: isFront,
                scale: scale,
                offsetX: offsetX,
                offsetY: offsetY,
              ),
            ),
          ],
        );
      },
    );
  }
}
