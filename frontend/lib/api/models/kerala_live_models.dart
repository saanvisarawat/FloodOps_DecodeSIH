/// Mirrors GET /api/dashboard/live-kerala on the real backend — the
/// hourly-refreshed cache of live rainfall/river-discharge/ML-risk per
/// district plus live dam/reservoir levels (scraped from KSEB's SLDC site,
/// with a hardcoded Idukki/Mullaperiyar fallback on scrape failure). The
/// backend feeds this same live weather+dam data into its XGBoost model on
/// an hourly APScheduler job server-side — there is nothing the frontend
/// needs to do to keep the model fed; this type only covers the read side.
enum DistrictAlertLevel { normal, warning, critical }

extension DistrictAlertLevelX on DistrictAlertLevel {
  static DistrictAlertLevel fromWire(String value) => switch (value) {
        'WARNING' => DistrictAlertLevel.warning,
        'CRITICAL' => DistrictAlertLevel.critical,
        _ => DistrictAlertLevel.normal,
      };

  String get label => switch (this) {
        DistrictAlertLevel.normal => 'Normal',
        DistrictAlertLevel.warning => 'Warning',
        DistrictAlertLevel.critical => 'Critical',
      };
}

class DistrictLiveRisk {
  final String district;
  final double rainfallMm;
  final double riverDischargeM3s;
  final int riskScore; // 0-100
  final bool isHighRisk;
  final DistrictAlertLevel alertLevel;

  const DistrictLiveRisk({
    required this.district,
    required this.rainfallMm,
    required this.riverDischargeM3s,
    required this.riskScore,
    required this.isHighRisk,
    required this.alertLevel,
  });

  factory DistrictLiveRisk.fromJson(String district, Map<String, dynamic> json) => DistrictLiveRisk(
        district: district,
        rainfallMm: (json['rainfall_mm'] as num?)?.toDouble() ?? 0,
        riverDischargeM3s: (json['river_discharge_m3s'] as num?)?.toDouble() ?? 0,
        riskScore: (json['risk_score'] as num?)?.round() ?? 0,
        isHighRisk: json['is_high_risk'] as bool? ?? false,
        alertLevel: DistrictAlertLevelX.fromWire(json['alert_level'] as String? ?? 'NORMAL'),
      );
}

class ReservoirStatus {
  final String damName;
  final double currentLevelM;
  final double capacityPct;
  final DistrictAlertLevel status;
  final double outflowM3s;

  const ReservoirStatus({
    required this.damName,
    required this.currentLevelM,
    required this.capacityPct,
    required this.status,
    required this.outflowM3s,
  });

  factory ReservoirStatus.fromJson(Map<String, dynamic> json) => ReservoirStatus(
        damName: json['dam_name'] as String? ?? 'Unknown',
        currentLevelM: (json['current_level_m'] as num?)?.toDouble() ?? 0,
        capacityPct: (json['capacity_pct'] as num?)?.toDouble() ?? 0,
        status: DistrictAlertLevelX.fromWire(json['status'] as String? ?? 'NORMAL'),
        outflowM3s: (json['outflow_m3s'] as num?)?.toDouble() ?? 0,
      );
}

class KeralaLiveDashboard {
  final DateTime? lastUpdated;
  final List<DistrictLiveRisk> districts;
  final List<ReservoirStatus> reservoirs;

  const KeralaLiveDashboard({
    required this.lastUpdated,
    required this.districts,
    required this.reservoirs,
  });

  /// True while the backend's hourly pipeline hasn't populated the cache
  /// yet (its very first seconds after a cold start) — the endpoint
  /// returns `{"message": "..."}` with no `districts`/`reservoirs` keys
  /// in that window.
  bool get isWarmingUp => districts.isEmpty && reservoirs.isEmpty && lastUpdated == null;

  factory KeralaLiveDashboard.fromJson(Map<String, dynamic> json) {
    final districtsJson = json['districts'] as Map<String, dynamic>?;
    final reservoirsJson = json['reservoirs'] as List?;
    final updatedRaw = json['last_updated'] as String?;
    return KeralaLiveDashboard(
      lastUpdated: updatedRaw == null ? null : DateTime.tryParse(updatedRaw),
      districts: districtsJson == null
          ? []
          : districtsJson.entries
              .map((e) => DistrictLiveRisk.fromJson(e.key, e.value as Map<String, dynamic>))
              .toList(),
      reservoirs: reservoirsJson == null
          ? []
          : reservoirsJson.map((e) => ReservoirStatus.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
