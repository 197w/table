import 'package:geolocator/geolocator.dart';

class GuestLocation {
  const GuestLocation({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

abstract final class LocationService {
  /// Zwraca null, gdy lokalizacja jest wyłączona albo gość nie wyraził zgody.
  /// Wtedy aplikacja pokazuje lokale w wybranym mieście.
  static Future<GuestLocation?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return GuestLocation(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return null;
    }
  }
}
