import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/kerala_live_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/kerala_live_provider.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/reservoir_card.dart';
import '../../widgets/section_header.dart';

/// Standalone dam & reservoir monitoring view (module: Dam & Reservoir
/// Monitoring) — every dam from the same live Kerala cache the Official
/// Command Center already reads (GET /api/dashboard/live-kerala), surfaced
/// here for every citizen, not just officials. No new backend call.
class ReservoirScreen extends ConsumerWidget {
  const ReservoirScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(keralaLiveDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dams & Reservoirs')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(keralaLiveDashboardProvider),
        color: AppColors.accent,
        backgroundColor: AppColors.surfaceHigh,
        child: async.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppSkeleton(height: 96, borderRadius: BorderRadius.circular(20)),
                ),
            ],
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off_outlined, color: AppColors.textTertiary, size: 28),
                    const SizedBox(height: 10),
                    Text(
                      'Live dam feed unavailable right now.',
                      style: AppTypography.body(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (dashboard) {
            if (dashboard.isWarmingUp) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Text(
                      'Live pipeline warming up — try again shortly.',
                      style: AppTypography.body(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              );
            }
            final critical = dashboard.reservoirs.where((r) => r.status == DistrictAlertLevel.critical).length;
            final watch = dashboard.reservoirs.where((r) => r.status == DistrictAlertLevel.warning).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                AppSpacing.xxl,
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryTile(
                        label: 'Total Monitored',
                        value: '${dashboard.reservoirs.length}',
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryTile(label: 'On Watch', value: '$watch', color: AppColors.warning),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryTile(label: 'Critical', value: '$critical', color: AppColors.dangerStrong),
                    ),
                  ],
                ),
                const SectionHeader(title: 'All Dams'),
                for (final r in dashboard.reservoirs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ReservoirCard(reservoir: r, width: double.infinity),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: AppTypography.caption()),
        ],
      ),
    );
  }
}
