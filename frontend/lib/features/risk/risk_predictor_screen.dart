import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/kerala_live_models.dart';
import '../../core/constants/kerala_districts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/kerala_live_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/circular_risk_gauge.dart';
import '../../widgets/district_dropdown.dart';
import '../../widgets/stat_card.dart';

/// Citizen-facing risk view (no login). Shows the live, government-pipeline
/// computed risk for the citizen's own district — real current rainfall/
/// river-discharge data run through the same backend model the official
/// Command Center uses (`keralaLiveDashboardProvider` / GET
/// /api/dashboard/live-kerala) — not an editable what-if scenario. The
/// manual slider-based "what-if" tool that used to live here moved to
/// `ManualRiskPredictorScreen`, reachable only from the Volunteer Hub /
/// Official Command Center, since a citizen has no reason to fabricate
/// hypothetical conditions for their own district.
class RiskPredictorScreen extends ConsumerStatefulWidget {
  const RiskPredictorScreen({super.key});

  @override
  ConsumerState<RiskPredictorScreen> createState() => _RiskPredictorScreenState();
}

class _RiskPredictorScreenState extends ConsumerState<RiskPredictorScreen> {
  String _district = KeralaDistricts.all.first.name;
  bool _locating = false;

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      final profile = KeralaDistricts.nearest(pos.latitude, pos.longitude);
      setState(() => _district = profile.name);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not get GPS location. Check location permissions.',
            kind: AppToastKind.error);
      }
    }
    if (mounted) setState(() => _locating = false);
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final asyncDashboard = ref.watch(keralaLiveDashboardProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        110,
      ),
      children: [
        AppButton(
          label: _locating ? 'Locating…' : 'Use Current Location',
          icon: Icons.my_location_rounded,
          color: AppColors.info,
          isLoading: _locating,
          onPressed: _useCurrentLocation,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text('or pick a district below', style: AppTypography.caption()),
        ),
        const SizedBox(height: AppSpacing.sm),
        DistrictDropdown(value: _district, onChanged: (name) => setState(() => _district = name)),
        const SizedBox(height: AppSpacing.section),
        asyncDashboard.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
          ),
          error: (_, __) => _ErrorNote(message: "Couldn't load live conditions — check your connection and try again."),
          data: (dashboard) {
            if (dashboard.isWarmingUp) {
              return _ErrorNote(message: 'Live data is still initializing — try again in a few seconds.');
            }
            DistrictLiveRisk? live;
            for (final d in dashboard.districts) {
              if (d.district == _district) {
                live = d;
                break;
              }
            }
            if (live == null) {
              return _ErrorNote(message: 'No live data available for $_district yet.');
            }
            return Column(
              children: [
                _LiveRiskBanner(risk: live),
                const SizedBox(height: AppSpacing.section),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Live Conditions Snapshot', style: AppTypography.sectionTitle()),
                ),
                const SizedBox(height: AppSpacing.sm),
                StatGrid(
                  cards: [
                    StatCard(
                      label: 'Rainfall',
                      value: '${live.rainfallMm.toStringAsFixed(1)} mm',
                      icon: Icons.water_drop_outlined,
                    ),
                    StatCard(
                      label: 'River Discharge',
                      value: '${live.riverDischargeM3s.toStringAsFixed(1)} m³/s',
                      icon: Icons.waves_outlined,
                    ),
                    StatCard(
                      label: 'Alert Level',
                      value: live.alertLevel.label,
                      icon: Icons.campaign_outlined,
                    ),
                    if (dashboard.lastUpdated != null)
                      StatCard(
                        label: 'Last Updated',
                        value: _relativeTime(dashboard.lastUpdated!),
                        icon: Icons.update_outlined,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Live-data equivalent of the manual predictor's result banner — no SHAP
/// `topFactors` here (the live pipeline cache doesn't carry them), so this
/// is just the gauge + label, not the pie-chart breakdown.
class _LiveRiskBanner extends StatelessWidget {
  final DistrictLiveRisk risk;
  const _LiveRiskBanner({required this.risk});

  @override
  Widget build(BuildContext context) {
    final score = risk.riskScore.toDouble();
    final color = AppColors.riskColor(score);
    final label = AppColors.riskLabel(score).toUpperCase();
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      child: Column(
        children: [
          CircularRiskGauge(score: score, radius: 78),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$label RISK',
            style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 4),
          Text(risk.district, style: AppTypography.body(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String message;
  const _ErrorNote({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: AppSpacing.compact),
          Expanded(child: Text(message, style: AppTypography.label(color: AppColors.danger))),
        ],
      ),
    );
  }
}
