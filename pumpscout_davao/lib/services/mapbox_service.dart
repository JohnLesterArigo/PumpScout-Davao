part of '../main.dart';

Future<Map<String, dynamic>?> fetchDrivingRoute({
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
}) async {
  return fetchDrivingRouteWithCoordinates([
    Position(originLng, originLat),
    Position(destinationLng, destinationLat),
  ]);
}

Future<Map<String, dynamic>?> fetchDrivingRouteWithCoordinates(
  List<Position> coordinates,
) async {
  if (coordinates.length < 2) return null;
  final coordinatePath = coordinates
      .map((position) => '${position.lng},${position.lat}')
      .join(';');
  final url = Uri.https(
    'api.mapbox.com',
    '/directions/v5/mapbox/driving-traffic/$coordinatePath',
    {
      'geometries': 'geojson',
      'overview': 'full',
      'steps': 'true',
      'annotations': 'distance,duration,speed,congestion,congestion_numeric',
      'alternatives': 'true',
      'access_token': accessToken,
    },
  );

  try {
    final response = await http.get(url).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      debugPrint('Mapbox route failed: HTTP ${response.statusCode}');
      return null;
    }

    final data = jsonDecode(response.body);
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;

    final route = routes.first;
    if (route is! Map<String, dynamic>) return null;

    final geometry = route['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    return _trafficRouteFeatureCollection(route, geometry);
  } catch (error) {
    debugPrint('Mapbox route request failed: $error');
    return null;
  }
}

Map<String, dynamic> _trafficRouteFeatureCollection(
  Map<String, dynamic> route,
  Map<String, dynamic> geometry,
) {
  final coordinates = geometry['coordinates'];
  final congestion = <String>[];
  final congestionNumeric = <double?>[];
  final segmentDistances = <double>[];
  final segmentDurations = <double>[];

  final legs = route['legs'];
  if (legs is List) {
    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;
      final annotation = leg['annotation'];
      if (annotation is! Map<String, dynamic>) continue;

      final legCongestion = annotation['congestion'];
      if (legCongestion is List) {
        congestion.addAll(
          legCongestion.map((value) => value is String ? value : 'unknown'),
        );
      }

      final legCongestionNumeric = annotation['congestion_numeric'];
      if (legCongestionNumeric is List) {
        congestionNumeric.addAll(
          legCongestionNumeric.map(
            (value) => value is num ? value.toDouble() : null,
          ),
        );
      }

      final legDistances = annotation['distance'];
      if (legDistances is List) {
        segmentDistances.addAll(
          legDistances.map((value) => value is num ? value.toDouble() : 0),
        );
      }

      final legDurations = annotation['duration'];
      if (legDurations is List) {
        segmentDurations.addAll(
          legDurations.map((value) => value is num ? value.toDouble() : 0),
        );
      }
    }
  }

  final routeDistance = _numToDouble(route['distance']);
  final routeDuration = _numToDouble(route['duration']);
  final typicalDuration = _numToDouble(route['duration_typical']);
  var heavyDistanceMeters = 0.0;
  var severeDistanceMeters = 0.0;

  final features = <Map<String, dynamic>>[];
  if (coordinates is List && coordinates.length >= 2 && congestion.isNotEmpty) {
    for (var index = 0; index < coordinates.length - 1; index++) {
      final start = coordinates[index];
      final end = coordinates[index + 1];
      if (start is! List || end is! List) continue;

      final segmentCongestion = index < congestion.length
          ? congestion[index]
          : 'unknown';
      final segmentDistance = index < segmentDistances.length
          ? segmentDistances[index]
          : 0.0;
      final numericCongestion = index < congestionNumeric.length
          ? congestionNumeric[index]
          : null;

      if (segmentCongestion == 'heavy') heavyDistanceMeters += segmentDistance;
      if (segmentCongestion == 'severe') {
        severeDistanceMeters += segmentDistance;
      }

      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': [start, end],
        },
        'properties': {
          'congestion': segmentCongestion,
          'congestionNumeric': numericCongestion,
          'distance': segmentDistance,
          'duration': index < segmentDurations.length
              ? segmentDurations[index]
              : null,
        },
      });
    }
  }

  if (features.isEmpty) {
    features.add({
      'type': 'Feature',
      'geometry': geometry,
      'properties': {'congestion': 'unknown'},
    });
  }

  return {
    'type': 'FeatureCollection',
    'features': features,
    'properties': {
      'distance': routeDistance,
      'duration': routeDuration,
      'durationTypical': typicalDuration,
      'trafficDelay': routeDuration == null || typicalDuration == null
          ? null
          : math.max(routeDuration - typicalDuration, 0),
      'heavyDistance': heavyDistanceMeters,
      'severeDistance': severeDistanceMeters,
      'hasTraffic': congestion.any(
        (value) => value == 'moderate' || value == 'heavy' || value == 'severe',
      ),
    },
  };
}

double? _numToDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return null;
}

double? _stationLatitude(dynamic station) {
  if (station is! Map<String, dynamic>) return null;
  final lat = station['lat'];
  if (lat is num) return lat.toDouble();

  final center = station['center'];
  if (center is Map<String, dynamic>) {
    final centerLat = center['lat'];
    if (centerLat is num) return centerLat.toDouble();
  }

  return null;
}

double? _stationLongitude(dynamic station) {
  if (station is! Map<String, dynamic>) return null;
  final lon = station['lon'];
  if (lon is num) return lon.toDouble();

  final center = station['center'];
  if (center is Map<String, dynamic>) {
    final centerLon = center['lon'];
    if (centerLon is num) return centerLon.toDouble();
  }

  return null;
}
