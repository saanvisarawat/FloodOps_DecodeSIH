import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../api/floodops_api.dart';
import '../../core/constants/kerala_districts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/kerala_live_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/shell_nav_provider.dart';
import '../../providers/sos_provider.dart';
import '../../providers/stream_providers.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/reservoir_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shelter_card.dart';
import '../../widgets/report_card.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/app_toast.dart';
import 'widgets/sos_composer_sheet.dart';

/// The district the Dashboard's ambient risk card watches by default.
/// Ernakulam is Kerala's most central/populous district and is already
/// used as a sensible fallback elsewhere in this app (see
/// volunteer_hub_screen.dart) when no GPS fix is available.
const _dashboardWatchDistrict = 'Ernakulam';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<ShelterFeature>? _shelters;
  List<ReportSummary>? _reports;
  int _activeAlertsCount = 0;
  double? _nearestShelterKm;
  double? _rainfallTodayMm;
  bool _loadingLists = true;
  bool _autoSyncing = false;
  ReportSummary? _activeSos;
  Timer? _sosPollTimer;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _sosPollTimer?.cancel();
    super.dispose();
  }

  /// Polls the same GET /api/reports data the Verification feed already
  /// uses (no new backend call) to keep the post-submit status card's
  /// verification count live for a short window after sending an SOS.
  void _startSosStatusTracking(String ticketId, {String? assignedVolunteerId}) {
    _sosPollTimer?.cancel();
    setState(() {
      _activeSos = ReportSummary(
        ticketId: ticketId,
        description: '',
        latitude: 0,
        longitude: 0,
        distanceMeters: 0,
        confirmCount: 0,
        falseAlarmCount: 0,
        status: ReportStatus.pending,
        reportedAt: DateTime.now(),
        // Allocation runs synchronously as part of submitting the SOS, so
        // the create-report response already says whether a volunteer was
        // dispatched immediately — no need to wait for a poll to show it.
        assignedVolunteerId: assignedVolunteerId,
      );
    });
    var attempts = 0;
    _sosPollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      attempts++;
      if (!mounted || _activeSos == null) {
        timer.cancel();
        return;
      }
      try {
        final reports = await ref.read(floodOpsApiProvider).getReports();
        final match = reports.where((r) => r.ticketId == ticketId);
        if (match.isNotEmpty && mounted) {
          setState(() => _activeSos = match.first);
          if (match.first.status == ReportStatus.verified) timer.cancel();
        }
      } catch (_) {
        // Keep the last known status rather than clearing the card on a
        // transient fetch failure.
      }
      if (attempts >= 6) timer.cancel();
    });
  }

  void _dismissSosStatus() {
    _sosPollTimer?.cancel();
    setState(() => _activeSos = null);
  }

  /// Manual dispatch (the official SOS dashboard's "Dispatch a Volunteer"
  /// action, used when no volunteer was available at creation time) can
  /// happen well after the 30s poll window above has already given up —
  /// this catches that update live over the same /ws/dashboard socket the
  /// Command Center uses, for as long as this citizen still has their SOS
  /// status card open.
  void _handleDashboardEvent(DashboardEvent event) {
    if (event is! VolunteerAssignedEvent) return;
    if (_activeSos == null || event.ticketId != _activeSos!.ticketId) return;
    if (_activeSos!.assignedVolunteerId != null) return;
    setState(() {
      _activeSos = _activeSos!.copyWith(assignedVolunteerId: event.assignedVolunteerId);
    });
    _showSnack(
      event.assignedVolunteerName != null
          ? 'Volunteer ${event.assignedVolunteerName} has been assigned to your SOS.'
          : 'A volunteer has been assigned to your SOS.',
    );
  }

  Future<void> _loadLists() async {
    final api = ref.read(floodOpsApiProvider);
    final profile = KeralaDistricts.byName(_dashboardWatchDistrict);
    final rainfallMm3Day = (profile.avgAnnualRainfallMm / 12).clamp(20, 400).toDouble();

    // Fetched independently (not one bundled Future.wait) so that one
    // endpoint failing — a network blip, the backend being down — doesn't
    // leave shelters/reports stuck on their loading skeleton forever too.
    final sheltersFuture = api.getSheltersGeoJson().catchError((_) => const ShelterFeatureCollection([]));
    final reportsFuture = api.getReports().catchError((_) => <ReportSummary>[]);

    final results = await Future.wait([sheltersFuture, reportsFuture]);
    if (!mounted) return;

    final allShelters = (results[0] as ShelterFeatureCollection).features;
    final unverified =
        (results[1] as List<ReportSummary>).where((r) => r.status != ReportStatus.verified).toList();
    final distance = const Distance();

    setState(() {
      _shelters = allShelters.take(8).toList();
      _reports = unverified.take(3).toList();
      _activeAlertsCount = unverified.length;
      _nearestShelterKm = allShelters.isEmpty
          ? null
          : allShelters
              .map((s) => distance.as(LengthUnit.Kilometer, profile.center, LatLng(s.latitude, s.longitude)))
              .reduce((a, b) => a < b ? a : b);
      _rainfallTodayMm = rainfallMm3Day / 3;
      _loadingLists = false;
    });
  }

  Future<void> _handleSosTap() async {
    final description = await AppBottomSheet.show<String>(
      context,
      builder: (_) => const SosComposerSheet(),
    );
    if (description == null || !mounted) return;

    final locationService = ref.read(locationServiceProvider);
    Position position;
    try {
      position = await locationService.getCurrentPosition();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not get GPS location. Check location permissions.', isError: true);
      return;
    }

    final outcome = await ref.read(sosControllerProvider.notifier).submit(
          description: description,
          latitude: position.latitude,
          longitude: position.longitude,
        );

    if (!mounted) return;
    switch (outcome.kind) {
      case SosOutcomeKind.submitted:
        _showSnack('SOS sent — ticket ${outcome.ticketId}. Help is on the way.');
        _loadLists();
        if (outcome.ticketId != null) {
          _startSosStatusTracking(outcome.ticketId!, assignedVolunteerId: outcome.assignedVolunteerId);
        }
        break;
      case SosOutcomeKind.queuedOffline:
        _showSnack(
          'No connection — SOS saved on device and will auto-send once you\'re back online.',
        );
        _maybeOfferSms(description, position.latitude, position.longitude);
        break;
      case SosOutcomeKind.failed:
        _showSnack('Could not send SOS. Please try again.', isError: true);
        break;
    }
  }

  void _maybeOfferSms(String description, double lat, double lng) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sms_outlined, color: AppColors.accent, size: 26),
              const SizedBox(height: 14),
              Text('Also send via SMS?', style: AppTypography.sectionTitle()),
              const SizedBox(height: 8),
              Text(
                'If you have zero signal, sending an SMS can reach emergency responders '
                'even when data doesn\'t work.',
                style: AppTypography.body(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: AppButton.tertiary(
                      label: 'Not now',
                      expand: true,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: 'Open SMS',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await ref.read(smsFallbackServiceProvider).sendFallbackSms(
                              latitude: lat,
                              longitude: lng,
                              description: description,
                            );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    AppToast.show(context, message, kind: isError ? AppToastKind.error : AppToastKind.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final queueCountAsync = ref.watch(offlineQueueCountProvider);
    final isSubmitting = ref.watch(sosControllerProvider);
    final keralaLive = ref.watch(keralaLiveDashboardProvider);

    ref.listen(connectivityStreamProvider, (previous, next) async {
      final wasOffline = previous?.value?.every((r) => r == ConnectivityResult.none) ?? false;
      final nowOnline = next.value?.any((r) => r != ConnectivityResult.none) ?? false;
      if (wasOffline && nowOnline && !_autoSyncing) {
        _autoSyncing = true;
        final synced = await ref.read(sosControllerProvider.notifier).syncQueue();
        _autoSyncing = false;
        if (synced > 0 && mounted) {
          _showSnack('Back online — synced $synced queued SOS report${synced == 1 ? '' : 's'}.');
        }
      }
    });

    ref.listen(dashboardEventStreamProvider, (previous, next) {
      next.whenData(_handleDashboardEvent);
    });

    final queueCount = queueCountAsync.value ?? 0;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: _TopBar(
            greeting: auth.isLoggedIn ? 'Hi, ${auth.user!.fullName.split(' ').first}' : 'Stay safe',
            subtitle: !isOnline
                ? 'Offline — SOS still works'
                : queueCount > 0
                    ? '$queueCount report${queueCount == 1 ? '' : 's'} queued'
                    : 'Kerala flood watch · live',
            initials: auth.isLoggedIn && auth.user!.fullName.isNotEmpty
                ? auth.user!.fullName[0].toUpperCase()
                : null,
            onAvatarTap: () => context.push('/profile'),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadLists,
            color: AppColors.accent,
            backgroundColor: AppColors.surfaceHigh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                110,
              ),
              children: [
                if (!isOnline || queueCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      color: AppColors.surfaceRaised,
                      onTap: () => context.push('/offline-queue'),
                      child: Row(
                        children: [
                          Icon(
                            isOnline ? Icons.cloud_sync : Icons.cloud_off,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              !isOnline
                                  ? 'You\'re offline. SOS reports are saved on this device.'
                                  : '$queueCount SOS report${queueCount == 1 ? '' : 's'} queued on this device.',
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                if (_activeSos != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _SosStatusCard(sos: _activeSos!, onDismiss: _dismissSosStatus),
                  ),
                AppButton.secondary(
                  label: 'Check Flood Risk',
                  icon: Icons.analytics_outlined,
                  onPressed: () => ref.read(shellTabIndexProvider.notifier).state = 3,
                ),
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      SosButton(onPressed: _handleSosTap, isBusy: isSubmitting),
                      const SizedBox(height: 10),
                      Text('Hold to send emergency SOS', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      AppButton.secondary(
                        label: 'Speak to Voice Agent',
                        icon: Icons.mic_none_rounded,
                        color: AppColors.info,
                        expand: false,
                        onPressed: () => context.push('/voice-agent'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Rainfall Today',
                        value: _rainfallTodayMm == null ? '—' : '${_rainfallTodayMm!.round()} mm',
                        icon: Icons.water_drop_outlined,
                        valueColor: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Nearest Shelter',
                        value: _nearestShelterKm == null ? '—' : '${_nearestShelterKm!.toStringAsFixed(1)} km',
                        icon: Icons.home_work_outlined,
                        valueColor: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Active Alerts',
                        value: '$_activeAlertsCount',
                        icon: Icons.warning_amber_outlined,
                        valueColor: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                keralaLive.maybeWhen(
                  data: (dashboard) => dashboard.reservoirs.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionHeader(
                              title: 'Reservoir Status',
                              actionLabel: 'View all',
                              onAction: () => context.push('/reservoirs'),
                            ),
                            SizedBox(
                              height: 148,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: dashboard.reservoirs.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                itemBuilder: (context, i) =>
                                    ReservoirCard(reservoir: dashboard.reservoirs[i], compact: true),
                              ),
                            ),
                          ],
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(height: AppSpacing.comfortable),
                AppButton(
                  label: 'View Evacuation Map',
                  icon: Icons.map_outlined,
                  onPressed: () => ref.read(shellTabIndexProvider.notifier).state = 2,
                ),
                SectionHeader(
                  title: 'Nearby Shelters',
                  actionLabel: 'View map',
                  onAction: () => ref.read(shellTabIndexProvider.notifier).state = 2,
                ),
                if (_loadingLists)
                  SizedBox(
                    height: 168,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 3,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => AppSkeleton(
                        width: 150,
                        height: 168,
                        borderRadius: AppRadius.cardR,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 168,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _shelters?.length ?? 0,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => ShelterCard(shelter: _shelters![i]),
                    ),
                  ),
                const SectionHeader(title: 'Unverified Reports Near You'),
                if (_loadingLists)
                  Column(
                    children: [
                      for (var i = 0; i < 2; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppSkeleton(height: 96, borderRadius: AppRadius.cardR),
                        ),
                    ],
                  )
                else if ((_reports ?? []).isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.section),
                    child: Column(
                      children: [
                        const Icon(Icons.verified_outlined, color: AppColors.textTertiary, size: 26),
                        const SizedBox(height: 8),
                        Text('All clear nearby', style: AppTypography.body(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final r in _reports!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ReportCard(report: r, compact: true),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String greeting;
  final String subtitle;
  final String? initials;
  final VoidCallback onAvatarTap;

  const _TopBar({
    required this.greeting,
    required this.subtitle,
    required this.initials,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.compact,
        AppSpacing.screenPadding,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.screenTitle(),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: initials != null
                  ? Text(
                      initials!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    )
                  : const Icon(Icons.person_outline, color: AppColors.textSecondary, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

/// Persistent post-submit confirmation — SOS sent, location shared, live
/// verification tally, responders alerted — replacing what used to be a
/// single toast that disappeared in a few seconds.
class _SosStatusCard extends StatelessWidget {
  final ReportSummary sos;
  final VoidCallback onDismiss;
  const _SosStatusCard({required this.sos, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final verified = sos.status == ReportStatus.verified;
    final volunteerAssigned = sos.assignedVolunteerId != null;
    return AppCard(
      color: AppColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emergency_share_rounded, color: AppColors.dangerStrong, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('SOS Sent · ${sos.ticketId}', style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _StatusLine(
            icon: Icons.check_circle_rounded,
            color: AppColors.accent,
            label: 'Location shared with responders',
          ),
          const SizedBox(height: 6),
          _StatusLine(
            icon: verified ? Icons.verified_rounded : Icons.hourglass_bottom_rounded,
            color: verified ? AppColors.accent : AppColors.warning,
            label: verified ? 'Verified by ${sos.confirmCount} nearby users' : 'Verification ${sos.confirmCount}/3',
          ),
          const SizedBox(height: 6),
          _StatusLine(
            icon: volunteerAssigned ? Icons.groups_rounded : Icons.hourglass_bottom_rounded,
            color: volunteerAssigned ? AppColors.info : AppColors.warning,
            label: volunteerAssigned ? 'Volunteer assigned and on the way' : 'Searching for a nearby volunteer…',
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatusLine({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppTypography.body(color: AppColors.textSecondary))),
      ],
    );
  }
}

