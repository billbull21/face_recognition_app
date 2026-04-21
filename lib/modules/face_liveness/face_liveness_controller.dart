import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge { blink, turnLeft, turnRight }

enum LivenessState { idle, waitingForFace, inProgress, centering, passed, failed }

/// Orchestrates the blink and head-turn liveness challenge flow.
///
/// Feed detected [Face] objects from ML Kit via [processFace].
class FaceLivenessController extends ChangeNotifier {
  static const int _timeoutSeconds = 15;

  // Eye open probability below this value = eye closed
  static const double _eyeClosedThreshold = 0.4;
  // Eye open probability above this value = eye open (for state machine reset)
  static const double _eyeOpenThreshold = 0.6;

  // Head must exceed this angle (degrees) to count as a turn
  static const double _headTurnThreshold = 18.0;
  // Head must stay past threshold for this many frames to confirm the turn
  static const int _headTurnConfirmFrames = 4;

  // After all challenges, face must be frontal for this many frames before passing
  static const int _centerConfirmFrames = 5;
  static const double _centerAngleThreshold = 12.0;

  LivenessState state = LivenessState.idle;
  List<LivenessChallenge> _challenges = [];
  int _currentIndex = 0;
  Timer? _timer;

  // Blink state machine: track open → closed transition
  bool _eyesWereOpen = false;

  // Head turn state machine: count consecutive frames past threshold
  int _headTurnFrameCount = 0;

  // Centering state machine: count consecutive frontal frames after challenges
  int _centerFrameCount = 0;

  /// Returns the current challenge the user must complete.
  LivenessChallenge? get currentChallenge =>
      _currentIndex < _challenges.length ? _challenges[_currentIndex] : null;

  /// Human-readable instruction for the current challenge.
  String get instruction {
    switch (state) {
      case LivenessState.idle:
        return 'Position your face in the frame';
      case LivenessState.waitingForFace:
        return 'Hold still — detecting your face...';
      case LivenessState.passed:
        return 'Liveness check passed!';
      case LivenessState.centering:
        return 'Now look straight at the camera';
      case LivenessState.failed:
        return 'Liveness check failed. Try again.';
      case LivenessState.inProgress:
        switch (currentChallenge) {
          case LivenessChallenge.blink:
            return 'Please blink your eyes';
          case LivenessChallenge.turnLeft:
            return 'Turn your head to the LEFT';
          case LivenessChallenge.turnRight:
            return 'Turn your head to the RIGHT';
          case null:
            return 'Hold on...';
        }
    }
  }

  /// Starts a new liveness check. Waits for face detection before
  /// beginning the challenge timer.
  void start() {
    _currentIndex = 0;
    state = LivenessState.waitingForFace;
    _challenges = _buildChallenges();
    _eyesWereOpen = false;
    _headTurnFrameCount = 0;
    _centerFrameCount = 0;
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _currentIndex = 0;
    state = LivenessState.idle;
    _challenges = [];
    _eyesWereOpen = false;
    _headTurnFrameCount = 0;
    _centerFrameCount = 0;
    notifyListeners();
  }

  /// Call this every time new [Face] data arrives from ML Kit.
  void processFace(Face? face) {
    if (state == LivenessState.idle ||
        state == LivenessState.passed ||
        state == LivenessState.failed) {
      return;
    }

    if (face == null) {
      // Reset head turn and centering counts if face lost
      _headTurnFrameCount = 0;
      _centerFrameCount = 0;
      return;
    }

    // Centering phase: wait for face to be frontal before declaring passed
    if (state == LivenessState.centering) {
      final eulerY = (face.headEulerAngleY ?? 0.0).abs();
      final eulerX = (face.headEulerAngleX ?? 0.0).abs();
      if (eulerY < _centerAngleThreshold && eulerX < _centerAngleThreshold) {
        _centerFrameCount++;
        if (_centerFrameCount >= _centerConfirmFrames) {
          _pass();
        }
      } else {
        _centerFrameCount = 0;
      }
      return;
    }


    // Waiting for face — once detected, start the challenge timer
    if (state == LivenessState.waitingForFace) {
      state = LivenessState.inProgress;
      _startTimer();
      notifyListeners();
      return;
    }

    if (currentChallenge == null) return;

    bool challengeCompleted = false;

    switch (currentChallenge!) {
      case LivenessChallenge.blink:
        final leftEye = face.leftEyeOpenProbability ?? 1.0;
        final rightEye = face.rightEyeOpenProbability ?? 1.0;
        final avgEye = (leftEye + rightEye) / 2.0;

        // State machine: detect open → closed transition
        if (avgEye > _eyeOpenThreshold) {
          _eyesWereOpen = true;
        } else if (_eyesWereOpen && avgEye < _eyeClosedThreshold) {
          challengeCompleted = true;
          _eyesWereOpen = false; // reset for next blink challenge if any
        }
        break;

      case LivenessChallenge.turnLeft:
        // Front camera mirrors horizontally: user turning LEFT appears as
        // rightward motion in the image, so eulerY is positive.
        final eulerY = face.headEulerAngleY ?? 0.0;
        if (eulerY > _headTurnThreshold) {
          _headTurnFrameCount++;
          if (_headTurnFrameCount >= _headTurnConfirmFrames) {
            challengeCompleted = true;
            _headTurnFrameCount = 0;
          }
        } else {
          _headTurnFrameCount = 0;
        }
        break;

      case LivenessChallenge.turnRight:
        // Front camera mirrors horizontally: user turning RIGHT appears as
        // leftward motion in the image, so eulerY is negative.
        final eulerY = face.headEulerAngleY ?? 0.0;
        if (eulerY < -_headTurnThreshold) {
          _headTurnFrameCount++;
          if (_headTurnFrameCount >= _headTurnConfirmFrames) {
            challengeCompleted = true;
            _headTurnFrameCount = 0;
          }
        } else {
          _headTurnFrameCount = 0;
        }
        break;
    }

    if (challengeCompleted) {
      _currentIndex++;
      _eyesWereOpen = false;
      _headTurnFrameCount = 0;
      if (_currentIndex >= _challenges.length) {
        // All challenges done — require face to return to centre before passing
        state = LivenessState.centering;
        _centerFrameCount = 0;
        notifyListeners();
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
    final challenges = [
      LivenessChallenge.blink,
      LivenessChallenge.turnLeft,
      LivenessChallenge.turnRight,
    ];
    challenges.shuffle();
    return challenges.take(2).toList();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
