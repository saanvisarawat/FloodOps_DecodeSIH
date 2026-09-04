import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../core/theme/app_colors.dart';

/// The ONLY risk gauge used in this app — an animated circular ring
/// (`percent_indicator`'s `CircularPercentIndicator`), never a plain
/// number or linear bar.
class CircularRiskGauge extends StatelessWidget {
  final double score; // 0-100
  final double radius;
  /// Overrides the default numeric-value center content (used by the
  /// Dashboard's ambient risk card, which shows a risk label instead of
  /// the raw score). Leave null for the default centered value + label.
  final Widget? center;

  const CircularRiskGauge({super.key, required this.score, this.radius = 80, this.center});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.riskColor(score);
    final label = AppColors.riskLabel(score);

    return CircularPercentIndicator(
      radius: radius,
      lineWidth: 11,
      animation: true,
      animationDuration: 900,
      curve: Curves.easeOutCubic,
      percent: (score / 100).clamp(0, 1),
      circularStrokeCap: CircularStrokeCap.round,
      backgroundColor: AppColors.surfaceRaised,
      progressColor: color,
      center: center ??
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.round().toString(),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
    );
  }
}
