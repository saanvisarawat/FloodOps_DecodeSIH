import 'dart:math';

import 'package:flutter/material.dart';

import '../api/models/risk_models.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

/// SHAP-driven "why this score" visual — a donut chart sized by each
/// factor's real SHAP contribution magnitude (`RiskFactor.weight`, now
/// populated from the backend's actual TreeExplainer output rather than a
/// synthetic descending weight), with a colored legend naming each slice.
/// No charting package needed — a handful of arcs via `CustomPainter`.
class RiskFactorPieChart extends StatelessWidget {
  final List<RiskFactor> factors;
  const RiskFactorPieChart({super.key, required this.factors});

  static const _palette = [
    AppColors.dangerStrong,
    AppColors.warning,
    AppColors.info,
    AppColors.accent,
    AppColors.textTertiary,
  ];

  static Color sliceColor(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    final total = factors.fold<double>(0, (sum, f) => sum + f.weight.abs());
    if (factors.isEmpty || total <= 0) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: CustomPaint(painter: _PieChartPainter(factors: factors, total: total)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < factors.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: sliceColor(i), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          factors[i].factor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body().copyWith(fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${((factors[i].weight.abs() / total) * 100).round()}%',
                        style: AppTypography.caption(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<RiskFactor> factors;
  final double total;
  _PieChartPainter({required this.factors, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var startAngle = -pi / 2;
    for (var i = 0; i < factors.length; i++) {
      final sweep = (factors[i].weight.abs() / total) * 2 * pi;
      final paint = Paint()
        ..color = RiskFactorPieChart.sliceColor(i)
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }
    // Donut hole — reads as a chart, not a solid disc of color.
    canvas.drawCircle(rect.center, size.width * 0.32, Paint()..color = AppColors.surface);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.factors != factors || oldDelegate.total != total;
}
