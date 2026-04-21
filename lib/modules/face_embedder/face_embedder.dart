import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Loads a face embedding TFLite model and generates embedding vectors.
/// Input size and embedding size are read from the model at load time,
/// so any compatible TFLite model works without code changes.
class FaceEmbedder {
  static const String _modelPath = 'assets/models/mobilefacenet.tflite';

  Interpreter? _interpreter;
  bool _isLoaded = false;

  /// Derived from the model's input tensor shape: [1, H, W, 3] → H (== W).
  int _inputSize = 112;

  /// Derived from the model's output tensor shape: [1, N] → N.
  int _embeddingSize = 128;

  bool get isLoaded => _isLoaded;

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset(_modelPath);

    // Read actual input size from tensor shape [1, H, W, 3]
    final inputShape = _interpreter!.getInputTensor(0).shape;
    if (inputShape.length == 4) {
      _inputSize = inputShape[1]; // H (assumes H == W)
    }

    // Read actual embedding size from output tensor shape [1, N]
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    if (outputShape.length == 2) {
      _embeddingSize = outputShape[1];
    }

    _isLoaded = true;
  }

  /// Crops the face region from [cameraImage], resizes to 112x112,
  /// normalises pixel values to [-1, 1], runs the TFLite model,
  /// and returns the 128-dim embedding vector.
  ///
  /// Returns null if the face bounding box is invalid or the model is not loaded.
  Future<Float32List?> extractEmbedding(
    CameraImage cameraImage,
    Face face,
  ) async {
    if (!_isLoaded || _interpreter == null) return null;

    final faceImage = _cropAndResizeFace(cameraImage, face);
    if (faceImage == null) return null;

    final input = _imageToFloat32(faceImage);
    final output = List.filled(_embeddingSize, 0.0).reshape([1, _embeddingSize]);

    _interpreter!.run(input.reshape([1, _inputSize, _inputSize, 3]), output);

    final embedding = Float32List.fromList(
      (output[0] as List).cast<num>().map((v) => v.toDouble()).toList(),
    );
    return _l2Normalize(embedding);
  }

  img.Image? _cropAndResizeFace(CameraImage cameraImage, Face face) {
    // Convert YUV420 → RGB image
    final rgbImage = _yuv420ToRgb(cameraImage);
    if (rgbImage == null) return null;

    final boundingBox = face.boundingBox;
    final imgWidth = rgbImage.width;
    final imgHeight = rgbImage.height;

    // Add 20% padding
    final padX = (boundingBox.width * 0.20).round();
    final padY = (boundingBox.height * 0.20).round();

    final x = (boundingBox.left - padX).clamp(0, imgWidth - 1).toInt();
    final y = (boundingBox.top - padY).clamp(0, imgHeight - 1).toInt();
    final w = (boundingBox.width + padX * 2).clamp(1, imgWidth - x).toInt();
    final h = (boundingBox.height + padY * 2).clamp(1, imgHeight - y).toInt();

    final cropped = img.copyCrop(rgbImage, x: x, y: y, width: w, height: h);
    return img.copyResize(cropped, width: _inputSize, height: _inputSize);
  }

  img.Image? _yuv420ToRgb(CameraImage image) {
    try {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final int width = image.width;
      final int height = image.height;
      final rgbImage = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yPlane.bytesPerRow + x;
          final int uvIndex =
              (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uPlane.bytesPerPixel!;

          final int yVal = yPlane.bytes[yIndex] & 0xFF;
          final int uVal = uPlane.bytes[uvIndex] & 0xFF;
          final int vVal = vPlane.bytes[uvIndex] & 0xFF;

          final int r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
          final int g =
              (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
                  .round()
                  .clamp(0, 255);
          final int b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

          rgbImage.setPixelRgb(x, y, r, g, b);
        }
      }
      return rgbImage;
    } catch (_) {
      return null;
    }
  }

  /// Normalises pixel values to [-1, 1] and returns a flattened Float32List.
  Float32List _imageToFloat32(img.Image image) {
    final input = Float32List(_inputSize * _inputSize * 3);
    int idx = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        input[idx++] = (pixel.r / 127.5) - 1.0;
        input[idx++] = (pixel.g / 127.5) - 1.0;
        input[idx++] = (pixel.b / 127.5) - 1.0;
      }
    }
    return input;
  }

  Float32List _l2Normalize(Float32List v) {
    double norm = 0.0;
    for (final val in v) {
      norm += val * val;
    }
    norm = norm == 0.0 ? 1.0 : norm;
    final scale = 1.0 / norm;
    return Float32List.fromList(v.map((e) => e * scale).toList());
  }

  void dispose() {
    _interpreter?.close();
  }
}
