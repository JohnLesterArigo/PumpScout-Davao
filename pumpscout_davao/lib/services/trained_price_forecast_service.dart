part of '../main.dart';

class TrainedPriceForecastModel {
  const TrainedPriceForecastModel({
    required this.modelVersion,
    required this.numericFeatures,
    required this.fuelTypes,
    required this.productTypes,
    required this.brands,
    required this.scaler,
    required this.weights,
  });

  final String modelVersion;
  final List<String> numericFeatures;
  final List<String> fuelTypes;
  final List<String> productTypes;
  final List<String> brands;
  final Map<String, FeatureScale> scaler;
  final Map<String, double> weights;

  factory TrainedPriceForecastModel.fromJson(Map<String, dynamic> json) {
    final rawScaler = json['scaler'];
    final scaler = <String, FeatureScale>{};
    if (rawScaler is Map<String, dynamic>) {
      for (final entry in rawScaler.entries) {
        if (entry.value is Map<String, dynamic>) {
          scaler[entry.key] = FeatureScale.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
    }

    final rawWeights = json['weights'];
    final weights = <String, double>{};
    if (rawWeights is Map<String, dynamic>) {
      for (final entry in rawWeights.entries) {
        final value = _jsonDouble(entry.value);
        if (value != null) weights[entry.key] = value;
      }
    }

    return TrainedPriceForecastModel(
      modelVersion: _stringField(
        json,
        'modelVersion',
        fallback: 'trained-forecast-v1',
      ),
      numericFeatures: _jsonStringList(json['numericFeatures']),
      fuelTypes: _jsonStringList(json['fuelTypes']),
      productTypes: _jsonStringList(json['productTypes']),
      brands: _jsonStringList(json['brands']),
      scaler: scaler,
      weights: weights,
    );
  }

  double predict({
    required String fuelType,
    required String productType,
    required String brand,
    required double currentPrice,
    required double priceOneWeekAgo,
    required double priceTwoWeeksAgo,
    required double weekIndex,
    required double lat,
    required double lng,
  }) {
    final normalizedFuelType = _trainedFuelType(fuelType);
    final normalizedProductType = _trainedProductType(productType);
    final normalizedBrand = brand.trim().toLowerCase();
    final numeric = <String, double>{
      'current_price': currentPrice,
      'price_1_week_ago': priceOneWeekAgo,
      'price_2_weeks_ago': priceTwoWeeksAgo,
      'rolling_avg_3': (currentPrice + priceOneWeekAgo + priceTwoWeeksAgo) / 3,
      'change_1_week': currentPrice - priceOneWeekAgo,
      'change_2_weeks': priceOneWeekAgo - priceTwoWeeksAgo,
      'week_index': weekIndex,
      'lat': lat,
      'lng': lng,
    };

    final features = <String, double>{'bias': 1};
    for (final name in numericFeatures) {
      final scale = scaler[name];
      if (scale == null) continue;
      features[name] = ((numeric[name] ?? 0) - scale.mean) / scale.std;
    }

    for (final option in fuelTypes) {
      features['fuel_type=$option'] = normalizedFuelType == option ? 1 : 0;
    }

    for (final option in productTypes) {
      features['product_type=$option'] = normalizedProductType == option
          ? 1
          : 0;
    }

    for (final option in brands) {
      features['brand=$option'] = normalizedBrand == option ? 1 : 0;
    }

    var result = 0.0;
    for (final entry in features.entries) {
      result += (weights[entry.key] ?? 0) * entry.value;
    }
    return result;
  }
}

class TrainedPriceForecastService {
  static TrainedPriceForecastModel? _cache;

  static Future<TrainedPriceForecastModel?> load() async {
    if (_cache != null) return _cache;

    try {
      final raw = await rootBundle.loadString(
        'assets/data/price_forecast_model.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cache = TrainedPriceForecastModel.fromJson(decoded);
        return _cache;
      }
    } catch (error) {
      debugPrint('Trained price forecast model load failed: $error');
    }

    return null;
  }

  static Future<FuelPriceForecast?> forecastFuelPrice({
    required List<PriceReport> reports,
    required StationMarkerDetails station,
    required String fuelType,
    required RegionalPriceStats regionalStats,
  }) async {
    final model = await load();
    if (model == null) return null;

    final points =
        reports
            .map((report) {
              final value = _reportFuelPrice(report, fuelType);
              if (value == null) return null;
              return _ForecastPoint(report.createdAt, value);
            })
            .whereType<_ForecastPoint>()
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (points.length < 3) return null;

    final latest = points[points.length - 1];
    final previous = points[points.length - 2];
    final previousTwo = points[points.length - 3];
    final weekIndex = latest.date.difference(points.first.date).inDays / 7;
    final predictedAt = latest.date.add(const Duration(days: 7));
    final band = regionalStats.bandFor(_forecastBandFuelType(fuelType));
    final rawPrediction = model.predict(
      fuelType: fuelType,
      productType: _productTypeForForecastFuel(station, fuelType),
      brand: station.brand,
      currentPrice: latest.price,
      priceOneWeekAgo: previous.price,
      priceTwoWeeksAgo: previousTwo.price,
      weekIndex: weekIndex,
      lat: station.lat,
      lng: station.lng,
    );
    final predictedPrice = rawPrediction.clamp(band.min, band.max).toDouble();
    final confidence = _trainedForecastConfidence(
      pointCount: points.length,
      band: band,
      currentPrice: latest.price,
      predictedPrice: predictedPrice,
    );

    return FuelPriceForecast(
      fuelType: fuelType,
      history: points.map((point) => point.price).toList(),
      currentPrice: latest.price,
      predictedPrice: predictedPrice,
      predictedAt: predictedAt,
      slopePerDay: (predictedPrice - latest.price) / 7,
      confidence: confidence,
      modelVersion: model.modelVersion,
      methodLabel:
          'Trained linear model using synthetic Davao fuel price history.',
    );
  }
}

class FeatureScale {
  const FeatureScale({required this.mean, required this.std});

  final double mean;
  final double std;

  factory FeatureScale.fromJson(Map<String, dynamic> json) {
    final std = _jsonDouble(json['std']) ?? 1;
    return FeatureScale(
      mean: _jsonDouble(json['mean']) ?? 0,
      std: std == 0 ? 1 : std,
    );
  }
}

double _trainedForecastConfidence({
  required int pointCount,
  required FuelPriceBand band,
  required double currentPrice,
  required double predictedPrice,
}) {
  var confidence = 0.5 + (pointCount.clamp(0, 10) * 0.035);
  if (band.contains(currentPrice) && band.contains(predictedPrice)) {
    confidence += 0.08;
  }
  if ((predictedPrice - currentPrice).abs() <= 3) {
    confidence += 0.04;
  }
  return confidence.clamp(0.35, 0.9);
}

String _trainedFuelType(String fuelType) {
  final category = _forecastBandFuelType(fuelType);
  return category == 'regular' ? 'gasoline' : category;
}

String _productTypeForForecastFuel(
  StationMarkerDetails station,
  String fuelType,
) {
  if (_isFuelProductKey(fuelType)) {
    return _trainedProductType(_fuelProductLabelFromKey(fuelType));
  }

  final brand = station.brand.trim().toLowerCase();
  if (brand.contains('shell')) {
    return switch (_trainedFuelType(fuelType)) {
      'diesel' => 'shell_fuelsave_diesel',
      'premium' => 'shell_vpower_gasoline',
      _ => 'shell_fuelsave_gasoline',
    };
  }
  return _trainedFuelType(fuelType);
}

String _trainedProductType(String value) {
  var productType = value.trim().toLowerCase();
  productType = productType.replaceAll('&', ' and ');
  productType = productType.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  productType = productType.replaceAll(RegExp(r'_+'), '_');
  productType = productType.replaceAll(RegExp(r'^_|_$'), '');
  productType = productType
      .replaceAll('v_power', 'vpower')
      .replaceAll('fuel_save', 'fuelsave');
  if (productType == 'regular' ||
      productType == 'unleaded' ||
      productType == 'gas') {
    return 'gasoline';
  }
  return productType;
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((entry) => '$entry')
      .where((entry) => entry.isNotEmpty)
      .toList();
}

double? _jsonDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
