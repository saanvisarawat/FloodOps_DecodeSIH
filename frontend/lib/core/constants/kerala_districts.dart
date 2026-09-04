import 'package:latlong2/latlong.dart';

/// Terrain/flood-risk profile used only to make mock ML predictor and
/// dashboard data look believable per district. Not real survey data.
class DistrictProfile {
  final String name;
  final LatLng center;
  final double avgElevationM;
  final double avgSlopeDeg;
  final String terrainNote;
  final double baseRiskScore; // 0-100, used as a seed for mock risk output
  final double avgAnnualRainfallMm;

  const DistrictProfile({
    required this.name,
    required this.center,
    required this.avgElevationM,
    required this.avgSlopeDeg,
    required this.terrainNote,
    required this.baseRiskScore,
    required this.avgAnnualRainfallMm,
  });
}

/// Kerala's 14 districts — the only scope for this app. No pan-India data.
class KeralaDistricts {
  KeralaDistricts._();

  static const LatLng keralaMapCenter = LatLng(10.3, 76.35);
  static const double keralaMapDefaultZoom = 7.3;

  static const List<DistrictProfile> all = [
    DistrictProfile(
      name: 'Thiruvananthapuram',
      center: LatLng(8.5241, 76.9366),
      avgElevationM: 64,
      avgSlopeDeg: 4,
      terrainNote: 'Coastal lowland with midland hills',
      baseRiskScore: 38,
      avgAnnualRainfallMm: 1850,
    ),
    DistrictProfile(
      name: 'Kollam',
      center: LatLng(8.8932, 76.6141),
      avgElevationM: 45,
      avgSlopeDeg: 3,
      terrainNote: 'Coastal, Ashtamudi backwaters',
      baseRiskScore: 42,
      avgAnnualRainfallMm: 2100,
    ),
    DistrictProfile(
      name: 'Pathanamthitta',
      center: LatLng(9.2648, 76.7870),
      avgElevationM: 220,
      avgSlopeDeg: 9,
      terrainNote: 'Pamba river basin, highland-midland mix',
      baseRiskScore: 68,
      avgAnnualRainfallMm: 2650,
    ),
    DistrictProfile(
      name: 'Alappuzha',
      center: LatLng(9.4981, 76.3388),
      avgElevationM: 2,
      avgSlopeDeg: 1,
      terrainNote: 'Kuttanad — below sea level, flat backwater delta',
      baseRiskScore: 82,
      avgAnnualRainfallMm: 2350,
    ),
    DistrictProfile(
      name: 'Kottayam',
      center: LatLng(9.5916, 76.5222),
      avgElevationM: 15,
      avgSlopeDeg: 2,
      terrainNote: 'Low-lying Kuttanad fringe, backwater adjacent',
      baseRiskScore: 71,
      avgAnnualRainfallMm: 2450,
    ),
    DistrictProfile(
      name: 'Idukki',
      center: LatLng(9.8497, 76.9681),
      avgElevationM: 1500,
      avgSlopeDeg: 26,
      terrainNote: 'Western Ghats highlands, steep terrain, dam catchments',
      baseRiskScore: 58,
      avgAnnualRainfallMm: 3200,
    ),
    DistrictProfile(
      name: 'Ernakulam',
      center: LatLng(9.9816, 76.2999),
      avgElevationM: 8,
      avgSlopeDeg: 2,
      terrainNote: 'Coastal, Periyar river delta, dense urban low-lying',
      baseRiskScore: 65,
      avgAnnualRainfallMm: 3000,
    ),
    DistrictProfile(
      name: 'Thrissur',
      center: LatLng(10.5276, 76.2144),
      avgElevationM: 30,
      avgSlopeDeg: 3,
      terrainNote: 'Chalakudy river plains, Kole wetlands',
      baseRiskScore: 60,
      avgAnnualRainfallMm: 3100,
    ),
    DistrictProfile(
      name: 'Palakkad',
      center: LatLng(10.7867, 76.6548),
      avgElevationM: 110,
      avgSlopeDeg: 6,
      terrainNote: 'Palakkad Gap, semi-arid rain shadow plains',
      baseRiskScore: 34,
      avgAnnualRainfallMm: 2400,
    ),
    DistrictProfile(
      name: 'Malappuram',
      center: LatLng(11.0510, 76.0711),
      avgElevationM: 60,
      avgSlopeDeg: 5,
      terrainNote: 'Chaliyar and Kadalundi river basins',
      baseRiskScore: 55,
      avgAnnualRainfallMm: 3000,
    ),
    DistrictProfile(
      name: 'Kozhikode',
      center: LatLng(11.2588, 75.7804),
      avgElevationM: 40,
      avgSlopeDeg: 4,
      terrainNote: 'Coastal midland, Chaliyar/Korapuzha basins',
      baseRiskScore: 48,
      avgAnnualRainfallMm: 3050,
    ),
    DistrictProfile(
      name: 'Wayanad',
      center: LatLng(11.6854, 76.1320),
      avgElevationM: 950,
      avgSlopeDeg: 22,
      terrainNote: 'Western Ghats plateau, landslide-prone slopes',
      baseRiskScore: 56,
      avgAnnualRainfallMm: 2900,
    ),
    DistrictProfile(
      name: 'Kannur',
      center: LatLng(11.8745, 75.3704),
      avgElevationM: 35,
      avgSlopeDeg: 4,
      terrainNote: 'Coastal, Valapattanam river basin',
      baseRiskScore: 40,
      avgAnnualRainfallMm: 3400,
    ),
    DistrictProfile(
      name: 'Kasaragod',
      center: LatLng(12.4996, 74.9869),
      avgElevationM: 50,
      avgSlopeDeg: 5,
      terrainNote: 'Coastal, laterite midlands',
      baseRiskScore: 36,
      avgAnnualRainfallMm: 3700,
    ),
  ];

  static const List<String> names = [
    'Thiruvananthapuram',
    'Kollam',
    'Pathanamthitta',
    'Alappuzha',
    'Kottayam',
    'Idukki',
    'Ernakulam',
    'Thrissur',
    'Palakkad',
    'Malappuram',
    'Kozhikode',
    'Wayanad',
    'Kannur',
    'Kasaragod',
  ];

  static DistrictProfile byName(String name) =>
      all.firstWhere((d) => d.name == name, orElse: () => all.first);

  /// Nearest district to a GPS fix, by straight-line distance to each
  /// district's center point — used to turn a raw lat/lng into a district
  /// the risk model/UI already understands (mirrors the same haversine
  /// approach `dio_floodops_api.dart` uses privately for shelter/task
  /// district lookups).
  static DistrictProfile nearest(double lat, double lng) {
    const distance = Distance();
    final point = LatLng(lat, lng);
    var closest = all.first;
    var best = double.infinity;
    for (final d in all) {
      final km = distance.as(LengthUnit.Kilometer, point, d.center);
      if (km < best) {
        best = km;
        closest = d;
      }
    }
    return closest;
  }
}
