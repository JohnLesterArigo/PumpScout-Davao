part of '../main.dart';

Future<List<DestinationPlace>> fetchPlaceSuggestions(String query) async {
  final trimmedQuery = query.trim();
  if (trimmedQuery.length < 3) return [];

  final knownPlaces = _knownDavaoPlaces(trimmedQuery);
  final searchQueries = <String>[
    trimmedQuery,
    '$trimmedQuery Davao City Philippines',
    '$trimmedQuery near Davao City Philippines',
    '$trimmedQuery Davao del Sur Philippines',
    '$trimmedQuery Mindanao Philippines',
  ];
  final places = <DestinationPlace>[...knownPlaces];
  final seenKeys = <String>{};
  for (final place in knownPlaces) {
    seenKeys.add(
      '${place.name.toLowerCase()}:${place.lat.toStringAsFixed(5)},${place.lng.toStringAsFixed(5)}',
    );
  }

  for (final searchQuery in searchQueries) {
    final url = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/$searchQuery.json',
      {
        'access_token': accessToken,
        'autocomplete': 'true',
        'country': 'ph',
        'language': 'en',
        'limit': '8',
        'proximity': '125.6128,7.0731',
        'types': 'poi,address,place,locality,neighborhood',
      },
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('Mapbox geocoding failed: HTTP ${response.statusCode}');
        continue;
      }

      final data = jsonDecode(response.body);
      final features = data['features'];
      if (features is! List) continue;

      for (final feature in features) {
        if (feature is! Map<String, dynamic>) continue;
        final center = feature['center'];
        if (center is! List || center.length < 2) continue;
        final lng = center[0];
        final lat = center[1];
        if (lng is! num || lat is! num) continue;
        if (!_isDavaoArea(lat.toDouble(), lng.toDouble())) continue;

        final text = feature['text'];
        final placeName = feature['place_name'];
        final place = DestinationPlace(
          name: text is String ? text : 'Destination',
          address: placeName is String ? placeName : '',
          lat: lat.toDouble(),
          lng: lng.toDouble(),
        );
        final key =
            '${place.name.toLowerCase()}:${place.lat.toStringAsFixed(5)},${place.lng.toStringAsFixed(5)}';

        if (seenKeys.add(key)) {
          places.add(place);
        }

        if (places.length >= 8) return places;
      }
    } catch (error) {
      debugPrint('Mapbox geocoding request failed: $error');
    }
  }

  if (places.length < 8) {
    final osmPlaces = await fetchOpenStreetMapPlaceSuggestions(trimmedQuery);
    for (final place in osmPlaces) {
      final key =
          '${place.name.toLowerCase()}:${place.lat.toStringAsFixed(5)},${place.lng.toStringAsFixed(5)}';
      if (seenKeys.add(key)) {
        places.add(place);
      }
      if (places.length >= 8) return places;
    }
  }

  return places;
}

Future<List<DestinationPlace>> fetchOpenStreetMapPlaceSuggestions(
  String query,
) async {
  final searchQueries = <String>[
    query,
    '$query Davao City Philippines',
    '$query near Davao City Philippines',
    '$query Davao del Sur Philippines',
  ];
  final places = <DestinationPlace>[];
  final seenKeys = <String>{};

  for (final searchQuery in searchQueries) {
    final url = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': searchQuery,
      'format': 'jsonv2',
      'addressdetails': '1',
      'countrycodes': 'ph',
      'limit': '6',
      'viewbox': '125.35,7.35,125.75,6.85',
      'bounded': '0',
    });

    try {
      final response = await http
          .get(url, headers: const {'User-Agent': 'PumpScoutDavao/1.0'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('OpenStreetMap search failed: HTTP ${response.statusCode}');
        continue;
      }

      final data = jsonDecode(response.body);
      if (data is! List) continue;

      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final lat = double.tryParse('${item['lat']}');
        final lng = double.tryParse('${item['lon']}');
        if (lat == null || lng == null) continue;
        if (!_isDavaoArea(lat, lng)) continue;

        final displayName = _stringField(item, 'display_name');
        final name = _stringField(
          item,
          'name',
          fallback: displayName.split(',').first.trim(),
        );
        if (name.isEmpty) continue;

        final place = DestinationPlace(
          name: name,
          address: displayName,
          lat: lat,
          lng: lng,
        );
        final key =
            '${place.name.toLowerCase()}:${place.lat.toStringAsFixed(5)},${place.lng.toStringAsFixed(5)}';
        if (seenKeys.add(key)) {
          places.add(place);
        }
        if (places.length >= 8) return places;
      }
    } catch (error) {
      debugPrint('OpenStreetMap search request failed: $error');
    }
  }

  return places;
}

bool _isDavaoArea(double lat, double lng) {
  return lat >= 6.80 && lat <= 7.40 && lng >= 125.25 && lng <= 125.85;
}

List<DestinationPlace> _knownDavaoPlaces(String query) {
  final normalized = query
      .toLowerCase()
      .replaceAll('mapúa', 'mapua')
      .replaceAll('mindao', 'mindanao');

  const knownPlaces = [
    (
      keywords: ['mapua', 'malayan', 'mcm', 'mindanao colleges'],
      place: DestinationPlace(
        name: 'Mapua Malayan Colleges Mindanao',
        address:
            'Gen. Douglas MacArthur Hwy, Matina, Davao City, Davao del Sur',
        lat: 7.06314965,
        lng: 125.595841561652,
      ),
    ),
    (
      keywords: ['sm ecoland', 'sm city davao', 'sm davao', 'ecoland'],
      place: DestinationPlace(
        name: 'SM City Davao',
        address: 'Quimpo Blvd corner Eco West Drive, Matina, Davao City',
        lat: 7.04917,
        lng: 125.58833,
      ),
    ),
    (
      keywords: ['abreeza', 'ayala mall davao'],
      place: DestinationPlace(
        name: 'Abreeza Mall',
        address: 'J.P. Laurel Avenue, Bajada, Davao City',
        lat: 7.091186,
        lng: 125.6113,
      ),
    ),
    (
      keywords: ['matina town square', 'mts'],
      place: DestinationPlace(
        name: 'Matina Town Square',
        address: 'MacArthur Highway, Matina, Davao City',
        lat: 7.0647,
        lng: 125.5987,
      ),
    ),
    (
      keywords: ['davao doctors', 'ddh'],
      place: DestinationPlace(
        name: 'Davao Doctors Hospital',
        address: '118 E. Quirino Avenue, Davao City',
        lat: 7.0703,
        lng: 125.6044,
      ),
    ),
  ];

  return knownPlaces
      .where((entry) {
        return entry.keywords.any(normalized.contains);
      })
      .map((entry) => entry.place)
      .toList();
}
