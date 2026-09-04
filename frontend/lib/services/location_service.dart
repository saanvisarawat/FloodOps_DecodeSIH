import 'package:geolocator/geolocator.dart';

class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
}

/// Fine-grained reason a location fix isn't available, for screens (like
/// navigation) that need to show a specific inline state rather than a
/// single generic error — see [LocationService.checkAvailability].
enum LocationAvailability { available, servicesDisabled, permissionDenied, permissionDeniedForever }

class LocationService {
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationPermissionDenied();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Checks permission/service state without throwing, so a screen can
  /// render a tailored inline state ("Turn on Location Services" vs
  /// "Location permission required") instead of one generic error.
  Future<LocationAvailability> checkAvailability() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAvailability.servicesDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationAvailability.permissionDeniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationAvailability.permissionDenied;
    }
    return LocationAvailability.available;
  }

  /// Continuous position updates for the navigation map/active-navigation
  /// screens. A 5 m distance filter avoids the update-per-inch spam a raw
  /// GPS stream produces while still feeling live at walking/driving
  /// speed.
  Stream<Position> watchPosition({int distanceFilterMeters = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: distanceFilterMeters),
    );
  }
}
