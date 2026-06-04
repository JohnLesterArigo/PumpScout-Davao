part of '../main.dart';

class FuelPriceBand {
  const FuelPriceBand({
    required this.min,
    required this.max,
    required this.median,
    required this.mean,
    required this.count,
  });

  final double min;
  final double max;
  final double median;
  final double mean;
  final int count;

  factory FuelPriceBand.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FuelPriceBand(
        min: 55,
        max: 95,
        median: 75,
        mean: 75,
        count: 0,
      );
    }

    return FuelPriceBand(
      min: _doubleField(json, 'min') ?? 55,
      max: _doubleField(json, 'max') ?? 95,
      median: _doubleField(json, 'median') ?? 75,
      mean: _doubleField(json, 'mean') ?? 75,
      count: (json['count'] is int) ? json['count'] as int : 0,
    );
  }

  bool contains(double value) => value >= min && value <= max;
}

class RegionalPriceStats {
  const RegionalPriceStats({
    required this.region,
    required this.source,
    required this.updatedAt,
    required this.modelVersion,
    required this.gasoline,
    required this.diesel,
    required this.premium,
  });

  final String region;
  final String source;
  final String updatedAt;
  final String modelVersion;
  final FuelPriceBand gasoline;
  final FuelPriceBand diesel;
  final FuelPriceBand premium;

  FuelPriceBand bandFor(String fuelType) {
    return switch (fuelType) {
      'diesel' => diesel,
      'premium' => premium,
      _ => gasoline,
    };
  }

  factory RegionalPriceStats.fromJson(Map<String, dynamic> json) {
    return RegionalPriceStats(
      region: _stringField(json, 'region', fallback: 'Davao City'),
      source: _stringField(json, 'source'),
      updatedAt: _stringField(json, 'updatedAt'),
      modelVersion: _stringField(json, 'modelVersion', fallback: 'regional-prior-v1'),
      gasoline: FuelPriceBand.fromJson(
        json['gasoline'] is Map<String, dynamic>
            ? json['gasoline'] as Map<String, dynamic>
            : null,
      ),
      diesel: FuelPriceBand.fromJson(
        json['diesel'] is Map<String, dynamic>
            ? json['diesel'] as Map<String, dynamic>
            : null,
      ),
      premium: FuelPriceBand.fromJson(
        json['premium'] is Map<String, dynamic>
            ? json['premium'] as Map<String, dynamic>
            : null,
      ),
    );
  }
}

class RegionalPriceModel {
  static RegionalPriceStats? _cache;

  static Future<RegionalPriceStats> load() async {
    if (_cache != null) return _cache!;

    try {
      final raw = await rootBundle.loadString(
        'assets/data/regional_price_stats.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cache = RegionalPriceStats.fromJson(decoded);
        return _cache!;
      }
    } catch (error) {
      debugPrint('Regional price stats load failed: $error');
    }

    _cache = const RegionalPriceStats(
      region: 'Davao City',
      source: 'fallback',
      updatedAt: 'unknown',
      modelVersion: 'regional-prior-fallback',
      gasoline: FuelPriceBand(min: 70, max: 90, median: 76, mean: 77, count: 0),
      diesel: FuelPriceBand(min: 68, max: 85, median: 74, mean: 76, count: 0),
      premium: FuelPriceBand(min: 72, max: 95, median: 78, mean: 80, count: 0),
    );
    return _cache!;
  }
}
