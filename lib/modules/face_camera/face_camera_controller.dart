import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Wraps the camera plugin and provides a stream of [CameraImage] frames
/// alongside detected [Face] objects from ML Kit.
class FaceCameraController extends ChangeNotifier {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;

  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isInitialized = false;
  bool _isProcessing = false;

  List<Face> detectedFaces = [];
  Size? previewSize;

  bool get isInitialized => _isInitialized;
  CameraController? get cameraController => _cameraController;

  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    // Prefer front camera
    _selectedCameraIndex = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_selectedCameraIndex < 0) _selectedCameraIndex = 0;

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // eye open probability
        enableLandmarks: true,
        enableContours: false,
        enableTracking: true,
        // accurate mode detects faces reliably on lower-quality cameras
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    await _startCamera(_selectedCameraIndex);
  }

  Future<void> _startCamera(int index) async {
    _isInitialized = false;
    notifyListeners();

    _cameraController?.dispose();
    _cameraController = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    previewSize = Size(
      _cameraController!.value.previewSize!.height,
      _cameraController!.value.previewSize!.width,
    );

    _cameraController!.startImageStream(_onCameraImage);
    _isInitialized = true;
    notifyListeners();
  }

  /// Restarts the image stream using the internal face-detection handler.
  /// Call this after manually stopping the stream (e.g. for a single-frame capture).
  void restartImageStream() {
    if (_cameraController == null || !_isInitialized) return;
    if (_cameraController!.value.isStreamingImages) return;
    _cameraController!.startImageStream(_onCameraImage);
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _startCamera(_selectedCameraIndex);
  }

  void _onCameraImage(CameraImage image) async {
    if (_isProcessing || _faceDetector == null) return;
    _isProcessing = true;
    try {
      final camera = _cameras[_selectedCameraIndex];
      final rotation = _rotationFromCamera(camera.sensorOrientation);
      final inputImage = _buildInputImage(image, rotation);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }
      final faces = await _faceDetector!.processImage(inputImage);
      detectedFaces = faces;
      notifyListeners();
    } catch (_) {
      // Silently ignore processing errors on individual frames
    } finally {
      _isProcessing = false;
    }
  }

  InputImageRotation _rotationFromCamera(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImage? _buildInputImage(CameraImage image, InputImageRotation rotation) {
    // iOS uses BGRA8888 (single plane)
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    // Android: NV21 is already in the correct format (single plane)
    if (image.format.group == ImageFormatGroup.nv21) {
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    // Android: YUV_420_888 (3 separate planes) — convert to NV21 properly.
    // Simply concatenating planes is wrong because each plane has its own
    // row stride/padding that must be stripped.
    if (image.format.group == ImageFormatGroup.yuv420) {
      final nv21 = _yuv420ToNv21(image);
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    return null;
  }

  /// Converts Android YUV_420_888 (3-plane) to NV21 (Y + interleaved VU),
  /// correctly stripping row padding from each plane.
  Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List((width * height * 1.5).round());

    // Copy Y plane, stripping row padding
    for (int row = 0; row < height; row++) {
      nv21.setRange(
        row * width,
        row * width + width,
        yPlane.bytes,
        row * yPlane.bytesPerRow,
      );
    }

    // Interleave V then U after Y (NV21 = Y + VU)
    int uvOffset = width * height;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final int srcIndex = row * uPlane.bytesPerRow + col * uvPixelStride;
        nv21[uvOffset++] =
            vPlane.bytes[row * vPlane.bytesPerRow + col * (vPlane.bytesPerPixel ?? 1)];
        nv21[uvOffset++] = uPlane.bytes[srcIndex];
      }
    }

    return nv21;
  }

  @override
  void dispose() {
    if (_cameraController?.value.isStreamingImages == true) {
      _cameraController?.stopImageStream();
    }
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }
}
