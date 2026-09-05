import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models/auth_models.dart';
import '../../api/models/dashboard_event_models.dart';
import '../../api/models/kerala_live_models.dart';
import '../../core/constants/kerala_districts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/kerala_live_provider.dart';
import '../../providers/stream_providers.dart';
import '../../widgets/map_pin_marker.dart';
import '../../widgets/status_badge.dart';
import '../profile/role_gate.dart';

class _LivePin {
  final String ticketId;
  final double lat;
  final double lng;
  final String description;
  bool verified;
  int confirmCount;

  _LivePin({
    required this.ticketId,
    required this.lat,
    required this.lng,
    required this.description,
    this.verified = false,
    this.confirmCount = 0,
  });
}

/// Real-time command center stream (module 9/10, Official view). Today
/// driven by `MockFloodOpsApi.dashboardEventStream` (a local Timer);
/// swaps automatically for a real `ws://.../ws/dashboard` listener once
/// `DioFloodOpsApi` is selected in `api_provider.dart` — this screen
/// never changes.
class LiveDashboardScreen extends ConsumerStatefulWidget {
  const LiveDashboardScreen({super.key});

  @override
  ConsumerState<LiveDashboardScreen> createState() => _LiveDashboardScreenState();
}

class _LiveDashboardScreenState extends ConsumerState<LiveDashboardScreen> {
  final Map<String, _LivePin> _pins = {};
  final List<DashboardEvent> _log = [];

  void _handleEvent(DashboardEvent event) {
    setState(() {
      _log.insert(0, event);
      if (_log.length > 30) _log.removeLast();
      switch (event) {
        case NewSosPendingEvent e:
          _pins[e.ticketId] = _LivePin(
            ticketId: e.ticketId,
            lat: e.latitude,
            lng: e.longitude,
            description: e.description,
          );
        case SosVerifiedEvent e:
          final pin = _pins[e.ticketId];
          if (pin != null) {
            pin.verified = e.confirmCount >= 3;
            pin.confirmCount = e.confirmCount;
          }
        case VolunteerAssignedEvent _:
          break;
        case HighRiskAlertEvent _:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isOnline = ref.watch(isOnlineProvider);

    ref.listen(dashboardEventStreamProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Command Center')),
      body: RoleGate(
        allowed: const [UserRole.official],
        currentRole: auth.user?.role,
        featureName: 'the Live Command Center',
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  StatusBadge(
                    label: isOnline ? 'Gemini AI Active' : 'Offline Fallback Mode',
                    color: isOnline ? AppColors.accent : AppColors.warning,
                    icon: isOnline ? Icons.bolt_rounded : Icons.cloud_off_rounded,
                    dot: true,
                  ),
                  const Spacer(),
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => context.push('/sos-dashboard'),
                            icon: const Icon(Icons.emergency_outlined, size: 18, color: AppColors.info),
                            label: Text('SOS Dashboard', style: AppTypography.label(color: AppColors.info)),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/pending-alerts'),
                            icon: const Icon(Icons.campaign_outlined, size: 18, color: AppColors.dangerStrong),
                            label: Text('Pending Alerts', style: AppTypography.label(color: AppColors.dangerStrong)),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/manual-risk-predictor'),
                            icon: const Icon(Icons.analytics_outlined, size: 18, color: AppColors.accent),
                            label: Text('Scenario Predictor', style: AppTypography.label(color: AppColors.accent)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                AppSpacing.sm,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: FlutterMap(
                    options: const MapOptions(
                      initialCenter: KeralaDistricts.keralaMapCenter,
                      initialZoom: KeralaDistricts.keralaMapDefaultZoom,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.floodops.floodops_frontend',
                      ),
                      MarkerLayer(
                        markers: [
                          for (final pin in _pins.values)
                            Marker(
                              point: LatLng(pin.lat, pin.lng),
                              width: 40,
                              height: 40,
                              child: MapPinMarker(
                                icon: pin.verified ? Icons.verified_rounded : Icons.warning_rounded,
                                color: pin.verified ? AppColors.accent : AppColors.dangerStrong,
                                size: 32,
                                pulsing: !pin.verified,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const _KeralaLivePanel(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
              child: Row(
                children: [
                  StatusBadge(
                    label: '${_pins.values.where((p) => !p.verified).length} Pending',
                    color: AppColors.dangerStrong,
                    icon: Icons.circle,
                    filled: true,
                  ),
                  const SizedBox(width: AppSpacing.compact),
                  StatusBadge(
                    label: '${_pins.values.where((p) => p.verified).length} Verified',
                    color: AppColors.accent,
                    icon: Icons.circle,
                    filled: true,
                  ),
                  const Spacer(),
                  const StatusBadge(label: 'Live', color: AppColors.accent, icon: Icons.circle, dot: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            Expanded(
              child: _log.isEmpty
                  ? Center(
                      child: Text('Waiting for live events…', style: AppTypography.body(color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.screenPadding),
                      itemCount: _log.length,
                      itemBuilder: (context, i) => _EventTile(event: _log[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live dam/reservoir levels + per-district rainfall/river-discharge/ML
/// risk (module 10, GET /api/dashboard/live-kerala) — the "dam and river"
/// data the backend's hourly pipeline already feeds into the XGBoost
/// model server-side; this panel only surfaces the read side of it.
class _KeralaLivePanel extends ConsumerWidget {
  const _KeralaLivePanel();

  Color _alertColor(DistrictAlertLevel level) => switch (level) {
        DistrictAlertLevel.critical => AppColors.dangerStrong,
        DistrictAlertLevel.warning => AppColors.warning,
        DistrictAlertLevel.normal => AppColors.accent,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(keralaLiveDashboardProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.sm,
      ),
      child: async.when(
        loading: () => const SizedBox(
          height: 40,
          child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
        error: (e, _) => Text(
          'Live Kerala dam/river feed unavailable.',
          style: AppTypography.caption(color: AppColors.textTertiary),
        ),
        data: (dashboard) {
          if (dashboard.isWarmingUp) {
            return Text(
              'Live dam/river pipeline warming up — try again shortly.',
              style: AppTypography.caption(color: AppColors.textTertiary),
            );
          }
          final topRisk = [...dashboard.districts]
            ..sort((a, b) => b.riskScore.compareTo(a.riskScore));
          return Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live Dam & River Levels', style: AppTypography.cardTitle().copyWith(fontSize: 14)),
                const SizedBox(height: AppSpacing.compact),
                for (final r in dashboard.reservoirs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: _alertColor(r.status), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${r.damName} — ${r.currentLevelM.toStringAsFixed(1)}m (${r.capacityPct.toStringAsFixed(0)}% capacity)',
                            style: AppTypography.body().copyWith(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (topRisk.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.compact),
                  Text('Highest District Risk', style: AppTypography.label(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  for (final d in topRisk.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: _alertColor(d.alertLevel), shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(d.district, style: AppTypography.body().copyWith(fontSize: 13))),
                          Text('${d.riskScore}', style: AppTypography.cardTitle().copyWith(fontSize: 13, color: _alertColor(d.alertLevel))),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final DashboardEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, subtitle) = switch (event) {
      NewSosPendingEvent(:final ticketId, :final description, :final assignedVolunteerId) => (
          Icons.add_alert_outlined,
          AppColors.dangerStrong,
          'New SOS pending — $ticketId',
          assignedVolunteerId != null
              ? '$description  ·  Volunteer #$assignedVolunteerId dispatched'
              : description,
        ),
      SosVerifiedEvent(:final ticketId, :final confirmCount) => (
          Icons.verified_outlined,
          AppColors.accent,
          'Verified — $ticketId ($confirmCount/3)',
          null,
        ),
      VolunteerAssignedEvent(:final ticketId, :final assignedVolunteerName) => (
          Icons.person_pin_circle_outlined,
          AppColors.info,
          'Volunteer dispatched — $ticketId',
          assignedVolunteerName != null ? 'Assigned to $assignedVolunteerName' : null,
        ),
      HighRiskAlertEvent(:final district, :final riskScore, :final alertLevel) => (
          Icons.warning_amber_rounded,
          AppColors.dangerStrong,
          'High risk — $district',
          '$alertLevel · risk score $riskScore%',
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.cardTitle().copyWith(fontSize: 14)),
                if (subtitle != null) Text(subtitle, style: AppTypography.label()),
                Text(DateFormat.Hms().format(event.timestamp), style: AppTypography.caption()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
