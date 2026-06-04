part of '../main.dart';

Future<List<dynamic>> fetchGasStations(double lat, double lng) async {
  final query =
      """
  [out:json][timeout:12];
  (
    node
      ["amenity"="fuel"]
      (around:8000,$lat,$lng);
    way
      ["amenity"="fuel"]
      (around:8000,$lat,$lng);
    relation
      ["amenity"="fuel"]
      (around:8000,$lat,$lng);
    node
      ["shop"="fuel"]
      (around:8000,$lat,$lng);
    way
      ["shop"="fuel"]
      (around:8000,$lat,$lng);
    relation
      ["shop"="fuel"]
      (around:8000,$lat,$lng);
    node
      ["fuel"]
      (around:8000,$lat,$lng);
    way
      ["fuel"]
      (around:8000,$lat,$lng);
    relation
      ["fuel"]
      (around:8000,$lat,$lng);
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
  if (stationId == null) return [];

  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('stationId', isEqualTo: stationId)
        .get();
    final reports = <PriceReport>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (_stringField(data, 'status', fallback: 'pending') != 'verified') {
        continue;
      }
      reports.add(PriceReport.fromFirestore(doc));
    }
    reports.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return reports.length > 12 ? reports.sublist(reports.length - 12) : reports;
  } catch (error) {
    debugPrint('Price history load failed: $error');
    return [];
  }
}
