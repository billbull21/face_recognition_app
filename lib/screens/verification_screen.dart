import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../modules/face_camera/face_camera_controller.dart';
import '../modules/face_camera/face_camera_preview.dart';
import '../modules/face_liveness/face_liveness_controller.dart';
import '../modules/face_embedder/face_embedder.dart';
import '../modules/face_store/face_store.dart';
import 'verification_result_screen.dart';

enum _VerificationStep { liveness, matching }

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late FaceCameraController _cameraController;
  late FaceLivenessController _livenessController;
  late FaceEmbedder _embedder;

  _VerificationStep _step = _VerificationStep.liveness;
  String? _errorMessage;

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
    if (_step != _VerificationStep.liveness) return;
    final faces = _cameraController.detectedFaces;
    _livenessController.processFace(faces.isNotEmpty ? faces.first : null);

    if (_livenessController.state == LivenessState.passed && mounted) {
      setState(() => _step = _VerificationStep.matching);
      _runMatch();
    } else if (_livenessController.state == LivenessState.failed && mounted) {
      setState(() => _errorMessage = 'Liveness failed. Restarting...');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
            _step = _VerificationStep.liveness;
          });
          _livenessController.start();
        }
      });
    }
  }

  Future<void> _runMatch() async {
    bool captured = false;
    _cameraController.cameraController?.stopImageStream();
    _cameraController.cameraController?.startImageStream((image) async {
      if (captured) return;
      final faces = _cameraController.detectedFaces;
      if (faces.isEmpty) return;
      captured = true;
      _cameraController.cameraController?.stopImageStream();

      final embedding = await _embedder.extractEmbedding(image, faces.first);
      if (!mounted) return;

      if (embedding == null) {
        setState(() {
          _errorMessage = 'Could not extract embedding. Try again.';
          _step = _VerificationStep.liveness;
        });
        _livenessController.start();
        _cameraController.restartImageStream();
        return;
      }

      final store = context.read<FaceStore>();
      final result = store.match(embedding);

      if (!mounted) return;
      // Navigate to full-screen result page.
      // Returns false = retry, true/null = go back to home.
      final goHome = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => VerificationResultScreen(result: result),
        ),
      );
      if (!mounted) return;
      if (goHome == true) {
        Navigator.of(context).pop();
      } else {
        _retry();
      }
    });
  }

  void _retry() {
    setState(() {
      _step = _VerificationStep.liveness;
      _errorMessage = null;
    });
    _livenessController.reset();
    _livenessController.start();
    _cameraController.restartImageStream();
  }

  @override
  void dispose() {
    _cameraController.removeListener(_onCameraUpdate);
    _cameraController.dispose();
    _livenessController.dispose();
    _embedder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Face'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          ListenableBuilder(
              listenable: _cameraController,
              builder: (_, w) =>
                  FaceCameraPreview(controller: _cameraController),
            ),
          SafeArea(
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
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    switch (_step) {
      case _VerificationStep.liveness:
        return _livenessPanel();
      case _VerificationStep.matching:
        return _matchingPanel();
    }
  }

  Widget _livenessPanel() {
    return ListenableBuilder(
      listenable: _livenessController,
      builder: (_, w) => _card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face_retouching_natural, size: 36, color: Colors.white70),
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

  Widget _matchingPanel() {
    return _card(
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text('Identifying...', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
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
