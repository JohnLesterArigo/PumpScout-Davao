part of '../main.dart';

Future<List<dynamic>> fetchGasStations(
  double lat,
  double lng, {
  int radiusMeters = stationDemoRadiusMeters,
}) async {
  final query =
      """
  [out:json][timeout:12];
  (
    node
      ["amenity"="fuel"]
      (around:$radiusMeters,$lat,$lng);
    way
      ["amenity"="fuel"]
      (around:$radiusMeters,$lat,$lng);
    relation
      ["amenity"="fuel"]
      (around:$radiusMeters,$lat,$lng);
    node
      ["shop"="fuel"]
      (around:$radiusMeters,$lat,$lng);
    way
      ["shop"="fuel"]
      (around:$radiusMeters,$lat,$lng);
    relation
      ["shop"="fuel"]
      (around:$radiusMeters,$lat,$lng);
    node
      ["fuel"]
      (around:$radiusMeters,$lat,$lng);
    way
      ["fuel"]
      (around:$radiusMeters,$lat,$lng);
    relation
      ["fuel"]
      (around:$radiusMeters,$lat,$lng);
  );
  out center;
  """;

  final urls = [
    Uri.parse('https://overpass-api.de/api/interpreter'),
    Uri.parse('https://overpass.kumi.systems/api/interpreter'),
  ];

  for (final url in urls) {
    try {
      final response = await http
          .post(
            url,
            headers: const {'User-Agent': 'PumpScoutDavao/1.0'},
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 14));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'];
        return elements is List ? elements : [];
      }

      final previewLength = response.body.length < 200
          ? response.body.length
          : 200;
      debugPrint(
        'Overpass failed from $url: HTTP ${response.statusCode} ${response.body.substring(0, previewLength)}',
      );
    } catch (error) {
      debugPrint('Overpass request failed from $url: $error');
    }
  }

  return [];
}

Future<List<StationPrice>> fetchStationPrices() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('stations')
        .get();

    return snapshot.docs.map(StationPrice.fromFirestore).toList();
  } catch (error) {
    debugPrint('Firestore station price load failed: $error');
    return [];
  }
}

Future<List<PriceReport>> fetchPriceReports(
  StationMarkerDetails details,
) async {
  final stationId = details.price?.id;
  final stationKey = _reportKeyForStationDetails(details);
  final reportsById = <String, PriceReport>{};

  void addVerifiedReports(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      final data = doc.data();
      if (_stringField(data, 'status', fallback: 'pending') != 'verified') {
        continue;
      }
      final report = PriceReport.fromFirestore(doc);
      reportsById[doc.id] = report;
    }
  }

  try {
    if (stationId != null && stationId.isNotEmpty) {
      final snapshot = await FirebaseFirestore.instance
          .collection('priceReports')
          .where('stationId', isEqualTo: stationId)
          .where('status', isEqualTo: 'verified')
          .get();
      addVerifiedReports(snapshot.docs);
    }

    if (stationKey.isNotEmpty) {
      final keySnapshot = await FirebaseFirestore.instance
          .collection('priceReports')
          .where('stationKey', isEqualTo: stationKey)
          .where('status', isEqualTo: 'verified')
          .get();
      addVerifiedReports(keySnapshot.docs);
    }

    if (reportsById.isEmpty) {
      final nearbySnapshot = await FirebaseFirestore.instance
          .collection('priceReports')
          .where('status', isEqualTo: 'verified')
          .limit(200)
          .get();

      final nearbyDocs = nearbySnapshot.docs.where((doc) {
        final data = doc.data();
        final lat = _doubleField(data, 'lat');
        final lng = _doubleField(data, 'lng');
        if (lat == null || lng == null) return false;

        final distanceMeters = geo.Geolocator.distanceBetween(
          details.lat,
          details.lng,
          lat,
          lng,
        );
        return distanceMeters <= 80;
      });
      addVerifiedReports(nearbyDocs);
    }

    final reports = reportsById.values.toList();
    reports.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    debugPrint(
      'Loaded ${reports.length} verified price reports for ${details.name}.',
    );
    return reports.length > 12 ? reports.sublist(reports.length - 12) : reports;
  } catch (error) {
    debugPrint('Price history load failed: $error');
    return [];
  }
}

String _reportKeyForStationDetails(StationMarkerDetails details) {
  final priceId = details.price?.id;
  if (priceId != null && priceId.isNotEmpty) return 'station:$priceId';

  final normalizedName = details.name.trim().toLowerCase();
  if (normalizedName.isEmpty) return '';
  return 'live:$normalizedName:${details.lat.toStringAsFixed(5)},${details.lng.toStringAsFixed(5)}';
}
