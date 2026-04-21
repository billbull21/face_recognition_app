import 'package:flutter/material.dart';
import '../modules/face_store/face_store.dart';

class VerificationResultScreen extends StatelessWidget {
  final MatchResult result;

  const VerificationResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final matched = result.matched;
    final color = matched ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);
    final icon = matched ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final iconColor = matched ? Colors.greenAccent : Colors.redAccent;
    final title = matched ? 'Identity Verified' : 'Verification Failed';
    final subtitle = matched
        ? 'Welcome, ${result.label}!'
        : 'No matching identity found in the database.';

    return Scaffold(
      backgroundColor: color,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Icon(icon, size: 120, color: iconColor),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Score card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    if (matched) ...[
                      _InfoRow(
                        label: 'Matched Identity',
                        value: result.label ?? 'Unknown',
                        icon: Icons.person,
                      ),
                      const Divider(color: Colors.white24, height: 24),
                    ],
                    _InfoRow(
                      label: 'Confidence',
                      value: '${(result.similarity * 100).toStringAsFixed(1)}%',
                      icon: Icons.bar_chart,
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    _InfoRow(
                      label: 'Status',
                      value: matched ? 'PASSED' : 'FAILED',
                      icon: matched ? Icons.verified : Icons.block,
                      valueColor: iconColor,
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Back to Home',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
