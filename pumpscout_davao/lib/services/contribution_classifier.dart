part of '../main.dart';

class ContributionClassification {
  const ContributionClassification({
    required this.label,
    required this.confidence,
    required this.reasons,
  });

  final String label;
  final double confidence;
  final List<String> reasons;

  bool get needsAdminAttention => label != 'usable';

  Map<String, Object?> toFirestore() {
    return {
      'aiClassification': label,
      'aiConfidence': confidence,
      'aiReasons': reasons,
      'aiScreenedAt': Timestamp.now(),
      'aiModelVersion': 'rules-v1',
      'needsAdminAttention': needsAdminAttention,
    };
  }
}

ContributionClassification classifyPriceContribution({
  required StationMarkerDetails station,
  required double? gasoline,
  required double? diesel,
  required double? premium,
  required bool hasPhoto,
  required bool photoUploadFailed,
}) {
  final reasons = <String>[];
  var riskScore = 0;

  final prices = <double>[
    ?gasoline,
    ?diesel,
    ?premium,
  ];

  if (prices.isEmpty) {
    riskScore += 45;
    _addReason(reasons, 'No fuel price was provided.');
  }

  for (final price in prices) {
    if (price <= 0) {
      riskScore += 40;
      _addReason(reasons, 'A reported price is zero or negative.');
      continue;
    }
    if (price < 35 || price > 120) {
      riskScore += 28;
      _addReason(
        reasons,
        'A reported price is outside the normal fuel price range.',
      );
    }
  }

  if (prices.length >= 2) {
    final minPrice = prices.reduce(math.min);
    final maxPrice = prices.reduce(math.max);
    if (maxPrice - minPrice > 35) {
      riskScore += 18;
      _addReason(reasons, 'Reported fuel prices have a very large difference.');
    }
  }

  final name = station.name.trim();
  if (name.isEmpty || name.toLowerCase() == 'fuel station') {
    riskScore += 10;
    _addReason(reasons, 'Station name is generic or missing.');
  }

  if (_looksLikeSpamText('${station.name} ${station.brand}')) {
    riskScore += 45;
    _addReason(reasons, 'Station text contains suspicious spam-like content.');
  }

  final distance = station.distanceMeters;
  if (distance == null || distance > 3000) {
    riskScore += 20;
    _addReason(reasons, 'Reporter distance could not be verified within 3 km.');
  }

  if (photoUploadFailed) {
    riskScore += 14;
    _addReason(reasons, 'Photo was selected but upload failed.');
  } else if (!hasPhoto) {
    riskScore += 8;
    _addReason(reasons, 'No receipt or pump photo was attached.');
  }

  if (reasons.isEmpty) {
    _addReason(reasons, 'Contribution passed the automatic quality checks.');
  }

  if (riskScore >= 60) {
    return ContributionClassification(
      label: 'spam',
      confidence: _confidenceFromRisk(riskScore),
      reasons: reasons,
    );
  }

  if (riskScore >= 25) {
    return ContributionClassification(
      label: 'needs_review',
      confidence: _confidenceFromRisk(riskScore),
      reasons: reasons,
    );
  }

  return ContributionClassification(
    label: 'usable',
    confidence: 0.86,
    reasons: reasons,
  );
}

void _addReason(List<String> reasons, String reason) {
  if (!reasons.contains(reason)) {
    reasons.add(reason);
  }
}

bool _looksLikeSpamText(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return false;

  final suspiciousPatterns = [
    RegExp(r'https?://|www\.'),
    RegExp(r'(.)\1{5,}'),
    RegExp(r'\b(free money|casino|betting|loan|promo code|click here)\b'),
    RegExp(r'[^\w\s.,&/-]{4,}'),
  ];

  return suspiciousPatterns.any((pattern) => pattern.hasMatch(normalized));
}

double _confidenceFromRisk(int riskScore) {
  return (0.55 + (riskScore.clamp(0, 100) / 220)).clamp(0.55, 0.98);
}
