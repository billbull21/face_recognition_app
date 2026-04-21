import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../modules/face_camera/face_camera_controller.dart';
import '../modules/face_camera/face_camera_preview.dart';
import '../modules/face_liveness/face_liveness_controller.dart';
import '../modules/face_embedder/face_embedder.dart';
import '../modules/face_store/face_store.dart';

enum _EnrollmentStep { liveness, capture, labelling, done }

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  late FaceCameraController _cameraController;
  late FaceLivenessController _livenessController;
  late FaceEmbedder _embedder;

  _EnrollmentStep _step = _EnrollmentStep.liveness;
  final _labelController = TextEditingController();
  bool _isCapturing = false;
  String? _errorMessage;
  List<double>? _capturedEmbedding;

  @override
  void initState() {
    super.initState();
    _cameraController = FaceCameraController();
    _livenessController = FaceLivenessController();
    _embedder = FaceEmbedder();
    _init();
  }

  Future<void> _init() async {
    await _cameraController.initialize();
    await _embedder.loadModel();
    _cameraController.addListener(_onCameraUpdate);
    if (mounted) setState(() {});
    _livenessController.start();
  }

  void _onCameraUpdate() {
    if (_step != _EnrollmentStep.liveness) return;
    final faces = _cameraController.detectedFaces;
    if (faces.isNotEmpty) {
      _livenessController.processFace(faces.first);
    } else {
      _livenessController.processFace(null);
    }

    if (_livenessController.state == LivenessState.passed && mounted) {
      setState(() => _step = _EnrollmentStep.capture);
    } else if (_livenessController.state == LivenessState.failed && mounted) {
      setState(() {
        _errorMessage = 'Liveness failed. Restarting...';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
            _step = _EnrollmentStep.liveness;
          });
          _livenessController.start();
        }
      });
    }
  }

  Future<void> _captureEmbedding() async {
    final faces = _cameraController.detectedFaces;
    if (faces.isEmpty) {
      setState(() => _errorMessage = 'No face detected. Please try again.');
      return;
    }

    setState(() => _isCapturing = true);

    // We need the raw CameraImage — trigger a single capture
    _cameraController.cameraController?.stopImageStream();
    await _cameraController.cameraController?.takePicture(); // just to flush

    // Re-start stream to grab the next frame for embedding
    bool captured = false;
    _cameraController.cameraController?.startImageStream((image) async {
      if (captured) return;
      captured = true;
      _cameraController.cameraController?.stopImageStream();

      final embedding = await _embedder.extractEmbedding(image, faces.first);
      if (mounted) {
        if (embedding != null) {
          setState(() {
            _capturedEmbedding = embedding.toList();
            _step = _EnrollmentStep.labelling;
            _isCapturing = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Failed to extract face embedding. Try again.';
            _isCapturing = false;
          });
          _cameraController.cameraController?.startImageStream((_) {});
        }
      }
    });
  }

  Future<void> _saveEnrollment() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _errorMessage = 'Please enter a name or ID.');
      return;
    }
    if (_capturedEmbedding == null) return;

    final store = context.read<FaceStore>();
    try {
      await store.enroll(
        label: label,
        embedding: Float32List.fromList(_capturedEmbedding!.map((v) => v.toDouble()).toList()),
      );
      if (mounted) setState(() => _step = _EnrollmentStep.done);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  @override
  void dispose() {
    _cameraController.removeListener(_onCameraUpdate);
    _cameraController.dispose();
    _livenessController.dispose();
    _embedder.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Face'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          if (_step == _EnrollmentStep.liveness ||
              _step == _EnrollmentStep.capture)
            ListenableBuilder(
              listenable: _cameraController,
              builder: (_, w) =>
                  FaceCameraPreview(controller: _cameraController),
            ),
          _buildOverlay(),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return SafeArea(
      child: Column(
        children: [
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              color: Colors.red.withAlpha(204),
              padding: const EdgeInsets.all(12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          const Spacer(),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    switch (_step) {
      case _EnrollmentStep.liveness:
        return _livenessPanel();
      case _EnrollmentStep.capture:
        return _capturePanel();
      case _EnrollmentStep.labelling:
        return _labellingPanel();
      case _EnrollmentStep.done:
        return _donePanel();
    }
  }

  Widget _livenessPanel() {
    return ListenableBuilder(
      listenable: _livenessController,
      builder: (_, w) => _bottomCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face, size: 36, color: Colors.white70),
            const SizedBox(height: 8),
            Text(
              _livenessController.instruction,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _capturePanel() {
    return _bottomCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Liveness check passed! Tap to capture your face.',
            style: TextStyle(color: Colors.white, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isCapturing ? null : _captureEmbedding,
            icon: _isCapturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt),
            label: const Text('Capture'),
          ),
        ],
      ),
    );
  }

  Widget _labellingPanel() {
    return _bottomCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Face captured! Enter a name or ID for this face.',
            style: TextStyle(color: Colors.white, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Name / ID',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white54),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saveEnrollment,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _donePanel() {
    return _bottomCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 40),
          const SizedBox(height: 8),
          Text(
            '${_labelController.text} enrolled successfully!',
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _bottomCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(178),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
