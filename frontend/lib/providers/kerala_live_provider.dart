import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/floodops_api.dart';
import 'api_provider.dart';

/// Live Kerala rainfall/river-discharge/ML-risk-per-district plus
/// dam/reservoir levels (module 10, GET /api/dashboard/live-kerala).
/// Backed by `MockFloodOpsApi` with plausible fake values today; swaps to
/// the real hourly-refreshed backend cache automatically once
/// `DioFloodOpsApi` is selected in `api_provider.dart`.
final keralaLiveDashboardProvider = FutureProvider.autoDispose<KeralaLiveDashboard>((ref) {
  final api = ref.watch(floodOpsApiProvider);
  return api.getKeralaLiveDashboard();
});
