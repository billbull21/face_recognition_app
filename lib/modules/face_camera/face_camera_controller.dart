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
        performanceMode: FaceDetectorMode.fast,
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
    if (image.format.group != ImageFormatGroup.nv21 &&
        image.format.group != ImageFormatGroup.yuv420) {
      return null;
    }

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }
}
