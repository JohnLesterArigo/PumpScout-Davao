part of '../main.dart';

Future<ContributionClassification?> screenContributionWithGemini({
  required StationMarkerDetails station,
  required double? gasoline,
  required double? diesel,
  required double? premium,
  required bool hasPhoto,
  required bool photoUploadFailed,
  required String? photoUrl,
  required User user,
}) async {
  try {
    final trustScore = await _loadContributorTrustScore(user.uid);
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).httpsCallable('screenPriceContribution');

    final result = await callable.call<Map<String, dynamic>>({
      'stationName': station.name,
      'brand': station.brand,
      'gasoline': gasoline,
      'diesel': diesel,
      'premium': premium,
      'distanceMeters': station.distanceMeters,
      'hasPhoto': hasPhoto,
      'photoUploadFailed': photoUploadFailed,
      'photoUrl': photoUrl,
      'contributorTrustScore': trustScore,
      'nearbyReferencePrices': _referencePricesFor(station),
    });

    return ContributionClassification.fromCallableResult(result.data);
  } catch (error) {
    debugPrint('Gemini screening unavailable, using rules fallback: $error');
    return null;
  }
}

Future<double?> _loadContributorTrustScore(String userId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    return _doubleField(doc.data() ?? const <String, dynamic>{}, 'trustScore');
  } catch (_) {
    return null;
  }
}

List<Map<String, Object?>> _referencePricesFor(StationMarkerDetails station) {
  final price = station.price;
  if (price == null) return const <Map<String, Object?>>[];

  return [
    {
      'stationName': price.name,
      'brand': price.brand,
      'gasoline': price.gasoline,
      'diesel': price.diesel,
      'premium': price.premium,
      'updatedAt': price.updatedAt?.toIso8601String(),
    },
  ];
}
