import 'package:flutter/material.dart';

import '../api/models/kerala_live_models.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import 'app_bottom_sheet.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// Dam-status label per this app's reservoir vocabulary — distinct from
/// [DistrictAlertLevel.label]'s generic "Warning", since dams specifically
/// read as NORMAL / WATCH / CRITICAL.
String reservoirStatusLabel(DistrictAlertLevel level) => switch (level) {
      DistrictAlertLevel.critical => 'CRITICAL',
      DistrictAlertLevel.warning => 'WATCH',
      DistrictAlertLevel.normal => 'NORMAL',
    };

Color reservoirStatusColor(DistrictAlertLevel level) => switch (level) {
      DistrictAlertLevel.critical => AppColors.dangerStrong,
      DistrictAlertLevel.warning => AppColors.warning,
      DistrictAlertLevel.normal => AppColors.accent,
    };

IconData reservoirStatusIcon(DistrictAlertLevel level) => switch (level) {
      DistrictAlertLevel.critical => Icons.error_outline_rounded,
      DistrictAlertLevel.warning => Icons.visibility_outlined,
      DistrictAlertLevel.normal => Icons.check_circle_outline_rounded,
    };

/// Elegant water-level card for a single dam/reservoir — dam name, current
/// storage level as a dominant percentage, current level in meters, and a
/// NORMAL/WATCH/CRITICAL status badge. Tapping opens a bottom sheet with
/// the full reading (level, capacity, outflow). Used both standalone on
/// the Reservoirs screen and compactly embedded on Home.
class ReservoirCard extends StatelessWidget {
  final ReservoirStatus reservoir;
  final double width;
  final bool compact;

  const ReservoirCard({super.key, required this.reservoir, this.width = 168, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = reservoirStatusColor(reservoir.status);
    return SizedBox(
      width: width,
      child: AppCard(
        onTap: () => _showDetail(context),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_outlined, size: 16, color: AppColors.info),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reservoir.damName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.cardTitle().copyWith(fontSize: 13.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${reservoir.capacityPct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
                color: AppColors.textPrimary,
              ),
            ),
            Text('storage level', style: AppTypography.caption()),
            const SizedBox(height: 10),
            StatusBadge(
              label: reservoirStatusLabel(reservoir.status),
              color: color,
              icon: reservoirStatusIcon(reservoir.status),
              filled: reservoir.status == DistrictAlertLevel.critical,
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text('${reservoir.currentLevelM.toStringAsFixed(1)} m current level', style: AppTypography.caption()),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final color = reservoirStatusColor(reservoir.status);
    AppBottomSheet.show(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(Icons.water_outlined, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reservoir.damName, style: AppTypography.cardTitle().copyWith(fontSize: 17)),
                    const SizedBox(height: 3),
                    StatusBadge(
                      label: reservoirStatusLabel(reservoir.status),
                      color: color,
                      icon: reservoirStatusIcon(reservoir.status),
                      filled: reservoir.status == DistrictAlertLevel.critical,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DetailRow(label: 'Current Level', value: '${reservoir.currentLevelM.toStringAsFixed(1)} m'),
          const SizedBox(height: 10),
          _DetailRow(label: 'Storage Capacity', value: '${reservoir.capacityPct.toStringAsFixed(0)}%'),
          const SizedBox(height: 10),
          _DetailRow(label: 'Outflow', value: '${reservoir.outflowM3s.toStringAsFixed(0)} m³/s'),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.label()),
        Text(value, style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
      ],
    );
  }
}
