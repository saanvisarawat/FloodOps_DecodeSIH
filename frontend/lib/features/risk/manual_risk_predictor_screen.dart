import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/auth_models.dart';
import '../../api/models/risk_models.dart';
import '../../core/constants/kerala_districts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/circular_risk_gauge.dart';
import '../../widgets/district_dropdown.dart';
import '../../widgets/risk_factor_pie_chart.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/app_toast.dart';
import '../profile/role_gate.dart';

/// Manual "what-if" risk scenario builder — moved here from the citizen-
/// facing Risk tab (now `RiskPredictorScreen`, which just shows the live
/// pipeline's real numbers instead). A citizen has no reason to fabricate
/// hypothetical rainfall/elevation/etc. for their own district; a
/// volunteer or official coordinating a response does, so this stays
/// role-gated the same way Agent Hub / Command Center are.
class ManualRiskPredictorScreen extends ConsumerWidget {
  const ManualRiskPredictorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scenario Risk Predictor')),
      body: RoleGate(
        allowed: const [UserRole.volunteer, UserRole.official],
        currentRole: auth.user?.role,
        featureName: 'the Scenario Risk Predictor',
        child: const _ManualRiskPredictorBody(),
      ),
    );
  }
}

class _ManualRiskPredictorBody extends ConsumerStatefulWidget {
  const _ManualRiskPredictorBody();

  @override
  ConsumerState<_ManualRiskPredictorBody> createState() => _ManualRiskPredictorBodyState();
}

class _ManualRiskPredictorBodyState extends ConsumerState<_ManualRiskPredictorBody> {
  String _district = KeralaDistricts.all.first.name;
  double _rainfall = 120;
  double _elevation = 60;
  double _slope = 4;
  double _saturation = 55;
  double _riverProximity = 2.0;
  double _reservoirLevel = 60;

  RiskPredictionResponse? _result;
  bool _loading = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _applyDistrictDefaults(_district);
  }

  void _applyDistrictDefaults(String name) {
    final profile = KeralaDistricts.byName(name);
    setState(() {
      _district = name;
      _elevation = profile.avgElevationM.clamp(0, 2500);
      _slope = profile.avgSlopeDeg.clamp(0, 35);
      _rainfall = (profile.avgAnnualRainfallMm / 12).clamp(20, 400);
      _saturation = (40 + profile.baseRiskScore * 0.4).clamp(0, 100);
      _riverProximity = profile.baseRiskScore > 60 ? 0.8 : 3.5;
      _reservoirLevel = (profile.baseRiskScore * 0.7).clamp(10, 95);
      _result = null;
    });
  }

  Future<void> _predict() async {
    setState(() => _loading = true);
    final api = ref.read(floodOpsApiProvider);
    RiskPredictionResponse? response;
    try {
      response = await api.predictRisk(RiskPredictionRequest(
        district: _district,
        rainfallMm3Day: _rainfall,
        elevationM: _elevation,
        slopeDeg: _slope,
        soilSaturationPct: _saturation,
        riverProximityKm: _riverProximity,
        reservoirLevelPct: _reservoirLevel,
      ));
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't get a risk score — check your connection and try again.",
            kind: AppToastKind.error);
      }
    }
    if (!mounted) return;
    setState(() {
      if (response != null) _result = response;
      _loading = false;
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      final profile = KeralaDistricts.nearest(pos.latitude, pos.longitude);
      _applyDistrictDefaults(profile.name);
      await _predict();
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not get GPS location. Check location permissions.',
            kind: AppToastKind.error);
      }
    }
    if (mounted) setState(() => _locating = false);
  }

  @override
  Widget build(BuildContext context) {
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
          child: Text(
            'or pick a district below',
            style: AppTypography.caption(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DistrictDropdown(value: _district, onChanged: _applyDistrictDefaults),
        if (_loading && _result == null) ...[
          const SizedBox(height: AppSpacing.section),
          const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
        ],
        if (_result != null) ...[
          const SizedBox(height: AppSpacing.section),
          _RiskBanner(result: _result!),
        ],
        const SizedBox(height: AppSpacing.section),
        AppCard(
          child: Column(
            children: [
              _SliderRow(
                label: '3-Day Rainfall',
                value: _rainfall,
                min: 0,
                max: 400,
                unit: 'mm',
                onChanged: (v) => setState(() => _rainfall = v),
              ),
              _SliderRow(
                label: 'Elevation',
                value: _elevation,
                min: 0,
                max: 2500,
                unit: 'm',
                onChanged: (v) => setState(() => _elevation = v),
              ),
              _SliderRow(
                label: 'Terrain Slope',
                value: _slope,
                min: 0,
                max: 35,
                unit: '°',
                onChanged: (v) => setState(() => _slope = v),
              ),
              _SliderRow(
                label: 'Soil Saturation',
                value: _saturation,
                min: 0,
                max: 100,
                unit: '%',
                onChanged: (v) => setState(() => _saturation = v),
              ),
              _SliderRow(
                label: 'River Proximity',
                value: _riverProximity,
                min: 0,
                max: 10,
                unit: 'km',
                onChanged: (v) => setState(() => _riverProximity = v),
              ),
              _SliderRow(
                label: 'Reservoir/Dam Level',
                value: _reservoirLevel,
                min: 0,
                max: 100,
                unit: '%',
                onChanged: (v) => setState(() => _reservoirLevel = v),
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.comfortable),
        AppButton.secondary(
          label: _loading ? 'Analyzing…' : 'Predict With These Values',
          icon: Icons.analytics_outlined,
          isLoading: _loading,
          onPressed: _predict,
        ),
        if (_result != null) ...[
          const SectionHeader(title: 'Conditions Snapshot'),
          StatGrid(
            cards: [
              StatCard(
                label: '3-Day Rainfall',
                value: '${_rainfall.toStringAsFixed(0)} mm',
                icon: Icons.water_drop_outlined,
              ),
              StatCard(
                label: 'Elevation',
                value: '${_elevation.toStringAsFixed(0)} m',
                icon: Icons.terrain_outlined,
              ),
              StatCard(
                label: 'Terrain Slope',
                value: '${_slope.toStringAsFixed(1)}°',
                icon: Icons.moving_outlined,
              ),
              StatCard(
                label: 'Soil Saturation',
                value: '${_saturation.toStringAsFixed(0)}%',
                icon: Icons.opacity_outlined,
              ),
              StatCard(
                label: 'River Proximity',
                value: '${_riverProximity.toStringAsFixed(1)} km',
                icon: Icons.water_outlined,
              ),
              StatCard(
                label: 'Reservoir Level',
                value: '${_reservoirLevel.toStringAsFixed(0)}%',
                icon: Icons.waves_outlined,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RiskBanner extends StatelessWidget {
  final RiskPredictionResponse result;
  const _RiskBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.riskColor(result.riskScore);
    final label = AppColors.riskLabel(result.riskScore).toUpperCase();
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      child: Column(
        children: [
          CircularRiskGauge(score: result.riskScore, radius: 78),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$label RISK',
            style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 4),
          Text(result.district, style: AppTypography.body(color: AppColors.textSecondary)),
          if (result.topFactors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.comfortable),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Why — SHAP contribution', style: AppTypography.label()),
            ),
            const SizedBox(height: 10),
            RiskFactorPieChart(factors: result.topFactors),
          ],
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;
  final bool last;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTypography.label(color: AppColors.textPrimary)),
              Text(
                '${value.toStringAsFixed(value < 10 ? 1 : 0)} $unit',
                style: AppTypography.accentValue(),
              ),
            ],
          ),
          AppSlider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }
}
