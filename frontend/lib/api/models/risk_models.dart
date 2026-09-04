class RiskPredictionRequest {
  final String district;
  final double rainfallMm3Day;
  final double elevationM;
  final double slopeDeg;
  final double soilSaturationPct;
  final double riverProximityKm;
  final double reservoirLevelPct;

  const RiskPredictionRequest({
    required this.district,
    required this.rainfallMm3Day,
    required this.elevationM,
    required this.slopeDeg,
    required this.soilSaturationPct,
    required this.riverProximityKm,
    required this.reservoirLevelPct,
  });

  Map<String, dynamic> toJson() => {
        'district': district,
        'rainfall_mm_3day': rainfallMm3Day,
        'elevation_m': elevationM,
        'slope_deg': slopeDeg,
        'soil_saturation_pct': soilSaturationPct,
        'river_proximity_km': riverProximityKm,
        'reservoir_level_pct': reservoirLevelPct,
      };
}

class RiskFactor {
  final String factor;
  final double weight;

  const RiskFactor({required this.factor, required this.weight});

  factory RiskFactor.fromJson(Map<String, dynamic> json) => RiskFactor(
        factor: json['factor'] as String,
        weight: (json['weight'] as num).toDouble(),
      );
}

class RiskPredictionResponse {
  final double riskScore;
  final List<RiskFactor> topFactors;
  final String district;

  const RiskPredictionResponse({
    required this.riskScore,
    required this.topFactors,
    required this.district,
  });

  factory RiskPredictionResponse.fromJson(Map<String, dynamic> json) => RiskPredictionResponse(
        riskScore: (json['risk_score'] as num).toDouble(),
        district: json['district'] as String,
        topFactors: (json['top_factors'] as List)
            .map((e) => RiskFactor.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
