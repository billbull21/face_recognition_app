import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge { blink, turnLeft, turnRight }

enum LivenessState { idle, inProgress, passed, failed }

/// Orchestrates the blink and head-turn liveness challenge flow.
///
/// Feed detected [Face] objects from ML Kit via [processFace].
class FaceLivenessController extends ChangeNotifier {
  static const int _timeoutSeconds = 10;
  static const double _eyeClosedThreshold = 0.3;
  static const double _headTurnThreshold = 20.0;

  LivenessState state = LivenessState.idle;
  List<LivenessChallenge> _challenges = [];
  int _currentIndex = 0;
  Timer? _timer;

  /// Returns the current challenge the user must complete.
  LivenessChallenge? get currentChallenge =>
      _currentIndex < _challenges.length ? _challenges[_currentIndex] : null;

  /// Human-readable instruction for the current challenge.
  String get instruction {
    switch (currentChallenge) {
      case LivenessChallenge.blink:
        return 'Please blink your eyes';
      case LivenessChallenge.turnLeft:
        return 'Turn your head left';
      case LivenessChallenge.turnRight:
        return 'Turn your head right';
      case null:
        if (state == LivenessState.passed) return 'Liveness check passed!';
        if (state == LivenessState.failed) return 'Liveness check failed. Try again.';
        return 'Position your face in the frame';
    }
  }

  /// Starts a new liveness check with randomised challenge order.
  void start() {
    _currentIndex = 0;
    state = LivenessState.inProgress;
    _challenges = _buildChallenges();
    _startTimer();
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _currentIndex = 0;
    state = LivenessState.idle;
    _challenges = [];
    notifyListeners();
  }

  /// Call this every time new [Face] data arrives from ML Kit.
  void processFace(Face? face) {
    if (state != LivenessState.inProgress || face == null) return;
    if (currentChallenge == null) return;

    bool challengeCompleted = false;

    switch (currentChallenge!) {
      case LivenessChallenge.blink:
        final leftEye = face.leftEyeOpenProbability ?? 1.0;
        final rightEye = face.rightEyeOpenProbability ?? 1.0;
        challengeCompleted =
            leftEye < _eyeClosedThreshold && rightEye < _eyeClosedThreshold;
        break;
      case LivenessChallenge.turnLeft:
        final eulerY = face.headEulerAngleY ?? 0.0;
        challengeCompleted = eulerY < -_headTurnThreshold;
        break;
      case LivenessChallenge.turnRight:
        final eulerY = face.headEulerAngleY ?? 0.0;
        challengeCompleted = eulerY > _headTurnThreshold;
        break;
    }

    if (challengeCompleted) {
      _currentIndex++;
      if (_currentIndex >= _challenges.length) {
        _pass();
      } else {
        notifyListeners();
      }
    }
  }

  void _pass() {
    _timer?.cancel();
    state = LivenessState.passed;
    notifyListeners();
  }

  void _fail() {
    state = LivenessState.failed;
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _timeoutSeconds), () {
      if (state == LivenessState.inProgress) _fail();
    });
  }

  List<LivenessChallenge> _buildChallenges() {
    // Randomise order per FR-11
    final challenges = [
      LivenessChallenge.blink,
      LivenessChallenge.turnLeft,
      LivenessChallenge.turnRight,
    ];
    challenges.shuffle();
    // Use first two challenges for a shorter flow
    return challenges.take(2).toList();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
