import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

enum MapLocationFailureReason {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class MapLocationException implements Exception {
  const MapLocationException(this.reason, [this.cause]);

  final MapLocationFailureReason reason;
  final Object? cause;

  @override
  String toString() => 'MapLocationException($reason, $cause)';
}

class MapPosition {
  const MapPosition({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

abstract interface class MapLocationService {
  Future<MapPosition> currentPosition();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorMapLocationService implements MapLocationService {
  const GeolocatorMapLocationService();

  @override
  Future<MapPosition> currentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const MapLocationException(
          MapLocationFailureReason.servicesDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const MapLocationException(
          MapLocationFailureReason.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const MapLocationException(
          MapLocationFailureReason.permissionDeniedForever,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return MapPosition(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on MapLocationException {
      rethrow;
    } catch (error) {
      throw MapLocationException(
        MapLocationFailureReason.unavailable,
        error,
      );
    }
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

final mapLocationServiceProvider = Provider<MapLocationService>((ref) {
  return const GeolocatorMapLocationService();
});
