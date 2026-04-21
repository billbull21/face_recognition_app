import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const double defaultMatchThreshold = 0.65;

class EnrolledIdentity {
  final String id;
  final String label;
  final Float32List embedding;

  const EnrolledIdentity({
    required this.id,
    required this.label,
    required this.embedding,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'embedding': embedding.toList(),
      };

  factory EnrolledIdentity.fromJson(Map<String, dynamic> json) {
    final rawList = (json['embedding'] as List).cast<num>();
    return EnrolledIdentity(
      id: json['id'] as String,
      label: json['label'] as String,
      embedding: Float32List.fromList(rawList.map((e) => e.toDouble()).toList()),
    );
  }
}

class MatchResult {
  final bool matched;
  final String? identityId;
  final String? label;
  final double similarity;

  const MatchResult({
    required this.matched,
    this.identityId,
    this.label,
    required this.similarity,
  });
}

/// Manages enrollment (save/delete/list) and matching (cosine similarity).
class FaceStore extends ChangeNotifier {
  static const _storageKey = 'enrolled_identities';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final double matchThreshold;
  List<EnrolledIdentity> _identities = [];

  FaceStore({this.matchThreshold = defaultMatchThreshold});

  List<EnrolledIdentity> get identities => List.unmodifiable(_identities);

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _identities = list.map(EnrolledIdentity.fromJson).toList();
    notifyListeners();
  }

  Future<void> enroll({
    required String label,
    required Float32List embedding,
  }) async {
    if (_identities.length >= 100) {
      throw StateError('Maximum of 100 identities reached.');
    }
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _identities.add(EnrolledIdentity(id: id, label: label, embedding: embedding));
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _identities.removeWhere((e) => e.id == id);
    await _persist();
    notifyListeners();
  }

  /// Returns the best [MatchResult] for [liveEmbedding] against all stored identities.
  MatchResult match(Float32List liveEmbedding) {
    if (_identities.isEmpty) {
      return const MatchResult(matched: false, similarity: 0.0);
    }

    double bestScore = -1.0;
    EnrolledIdentity? bestMatch;

    for (final identity in _identities) {
      final score = _cosineSimilarity(liveEmbedding, identity.embedding);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = identity;
      }
    }

    if (bestScore >= matchThreshold && bestMatch != null) {
      return MatchResult(
        matched: true,
        identityId: bestMatch.id,
        label: bestMatch.label,
        similarity: bestScore,
      );
    }
    return MatchResult(matched: false, similarity: bestScore);
  }

  double _cosineSimilarity(Float32List a, Float32List b) {
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    // Vectors are L2-normalised so dot product == cosine similarity
    return dot;
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_identities.map((e) => e.toJson()).toList());
    await _storage.write(key: _storageKey, value: encoded);
  }
}
