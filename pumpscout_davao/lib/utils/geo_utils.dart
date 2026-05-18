part of '../main.dart';

double _bearingToDestination(
  double originLat,
  double originLng,
  double destinationLat,
  double destinationLng,
) {
  final lat1 = _degreesToRadians(originLat);
  final lat2 = _degreesToRadians(destinationLat);
  final deltaLng = _degreesToRadians(destinationLng - originLng);

  final y = math.sin(deltaLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);

  return (_radiansToDegrees(math.atan2(y, x)) + 360) % 360;
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;

double _radiansToDegrees(double radians) => radians * 180 / math.pi;
