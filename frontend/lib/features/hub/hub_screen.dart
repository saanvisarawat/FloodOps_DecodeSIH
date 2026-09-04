import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/auth_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../widgets/app_card.dart';

/// Feature hub — every major module as a tappable icon tile, so the user
/// can jump straight to any module instead of digging through nav. A
/// destination in its own right in the bottom nav, separate from Home
/// (which stays the SOS-first live dashboard).
class HubScreen extends ConsumerWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isVolunteer = auth.user?.role == UserRole.volunteer;
    final isOfficial = auth.user?.role == UserRole.official;

    void goToTab(int index) => ref.read(shellTabIndexProvider.notifier).state = index;

    final tiles = <_HubTileData>[
      _HubTileData(
        icon: Icons.emergency_share_rounded,
        label: 'SOS / Emergency Report',
        subtitle: 'Send an emergency alert',
        onTap: () => goToTab(0),
      ),
      _HubTileData(
        icon: Icons.speed_outlined,
        label: 'Risk Predictor',
        subtitle: 'Check flood risk now',
        onTap: () => goToTab(3),
      ),
      _HubTileData(
        icon: Icons.map_outlined,
        label: 'Evacuation Map',
        subtitle: 'Shelters & routes',
        onTap: () => goToTab(2),
      ),
      _HubTileData(
        icon: Icons.navigation_outlined,
        label: 'Navigate',
        subtitle: 'Offline GPS & directions',
        onTap: () => context.push('/navigate'),
      ),
      _HubTileData(
        icon: Icons.fact_check_outlined,
        label: 'Verified Reports Feed',
        subtitle: 'Crowd-verified reports',
        onTap: () => goToTab(5),
      ),
      _HubTileData(
        icon: Icons.chat_bubble_outline,
        label: 'Survival Chatbot',
        subtitle: 'Ask Ragbot for help',
        onTap: () => goToTab(4),
      ),
      _HubTileData(
        icon: Icons.mic_none_rounded,
        label: 'Voice Agent',
        subtitle: 'Speak your emergency',
        onTap: () => context.push('/voice-agent'),
      ),
      _HubTileData(
        icon: Icons.water_outlined,
        label: 'Dams & Reservoirs',
        subtitle: 'Live water levels',
        onTap: () => context.push('/reservoirs'),
      ),
      _HubTileData(
        icon: Icons.volunteer_activism_outlined,
        label: 'Volunteer Hub',
        subtitle: isVolunteer ? 'Duty, tasks & masked calls' : 'Volunteer sign-in required',
        onTap: isVolunteer ? () => context.push('/volunteer-hub') : null,
      ),
      _HubTileData(
        icon: Icons.home_work_outlined,
        label: 'Shelters Near Me',
        subtitle: 'Distance-sorted shelter list',
        onTap: () => context.push('/shelters-near-me'),
      ),
      _HubTileData(
        icon: Icons.notifications_outlined,
        label: 'Alerts / Notifications',
        subtitle: 'Verified & dispatched alerts',
        onTap: () => context.push('/alerts'),
      ),
      if (isOfficial)
        _HubTileData(
          icon: Icons.satellite_alt_outlined,
          label: 'Command Center',
          subtitle: 'Live SOS stream',
          onTap: () => context.push('/live-dashboard'),
        ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            110,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.95,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, i) => _HubTile(data: tiles[i]),
        ),
      ),
    );
  }
}

class _HubTileData {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  const _HubTileData({required this.icon, required this.label, required this.subtitle, required this.onTap});

  bool get enabled => onTap != null;
}

/// AppCard already owns press-scale/splash/highlight, so this stays a
/// thin StatelessWidget rather than duplicating that animation state.
class _HubTile extends StatelessWidget {
  final _HubTileData data;
  const _HubTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: data.enabled ? 1 : 0.5,
      child: AppCard(
        onTap: data.onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
                child: Icon(data.icon, color: AppColors.accent, size: 23),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                data.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.cardTitle().copyWith(fontSize: 13.5),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                data.subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
