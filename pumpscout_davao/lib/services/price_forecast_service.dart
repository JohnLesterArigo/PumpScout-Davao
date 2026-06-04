part of '../main.dart';

class FuelPriceForecast {
  const FuelPriceForecast({
    required this.fuelType,
    required this.history,
    required this.currentPrice,
    required this.predictedPrice,
    required this.predictedAt,
    required this.slopePerDay,
    required this.confidence,
    required this.modelVersion,
    required this.methodLabel,
  });

  final String fuelType;
  final List<double> history;
  final double currentPrice;
  final double predictedPrice;
  final DateTime predictedAt;
  final double slopePerDay;
  final double confidence;
  final String modelVersion;
  final String methodLabel;

  double get change => predictedPrice - currentPrice;

  String get direction {
    if (change.abs() < 0.25) return 'stay stable';
    return change > 0 ? 'increase' : 'decrease';
  }

  int get confidencePercent => (confidence * 100).round().clamp(0, 100);
}

FuelPriceForecast? forecastFuelPrice(
  List<PriceReport> reports,
  String fuelType, {
  RegionalPriceStats? regionalStats,
}) {
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

  final band = regionalStats?.bandFor(fuelType);
  var cleaned = _removeOutliers(points, band);
  if (cleaned.length < 3 && band != null) {
    cleaned = _removeOutliers(points, null);
  }
  if (cleaned.length < 3) return null;

  final linear = _linearForecast(cleaned);
  if (linear == null) return null;

  final ema = _emaForecast(cleaned);
  final prior = band?.median ?? cleaned.last.price;
  final n = cleaned.length;

  final linearWeight = (0.45 + (n * 0.04)).clamp(0.45, 0.7);
  final emaWeight = 0.25;
  final priorWeight = 1 - linearWeight - emaWeight;

  final blended =
      (linear.predictedPrice * linearWeight) +
      (ema * emaWeight) +
      (prior * priorWeight);

  final predictedPrice = blended
      .clamp(band?.min ?? 50, band?.max ?? 120)
      .toDouble();

  final confidence = _forecastConfidence(
    pointCount: n,
    prices: cleaned.map((point) => point.price).toList(),
    band: band,
    predictedPrice: predictedPrice,
  );

  return FuelPriceForecast(
    fuelType: fuelType,
    history: cleaned.map((point) => point.price).toList(),
    currentPrice: cleaned.last.price,
    predictedPrice: predictedPrice,
    predictedAt: linear.predictedAt,
    slopePerDay: linear.slopePerDay,
    confidence: confidence,
    modelVersion: regionalStats == null
        ? 'ensemble-v1'
        : 'ensemble-v1+${regionalStats.modelVersion}',
    methodLabel:
        'Ensemble blends station history, trend smoothing, and Davao reference prices.',
  );
}

List<_ForecastPoint> _removeOutliers(
  List<_ForecastPoint> points,
  FuelPriceBand? band,
) {
  if (points.length < 4) return points;

  final prices = points.map((point) => point.price).toList();
  final mean = prices.reduce((a, b) => a + b) / prices.length;
  final variance =
      prices.map((price) => math.pow(price - mean, 2)).reduce((a, b) => a + b) /
      prices.length;
  final stdDev = math.sqrt(variance);
  final maxDeviation = stdDev < 0.5 ? 4.0 : stdDev * 2.2;

  return points.where((point) {
    if ((point.price - mean).abs() > maxDeviation) return false;
    if (band != null && band.count > 0 && !band.contains(point.price)) {
      return false;
    }
    return true;
  }).toList();
}

_LinearForecastResult? _linearForecast(List<_ForecastPoint> points) {
  final firstDate = points.first.date;
  final actualDaySpan =
      points.last.date.difference(firstDate).inMinutes /
      (Duration.hoursPerDay * Duration.minutesPerHour);
  final hasUsableTimeSpread = actualDaySpan >= 1;
  final xs = hasUsableTimeSpread
      ? points
            .map((point) => point.date.difference(firstDate).inHours / 24.0)
            .toList()
      : List<double>.generate(points.length, (index) => index.toDouble());
  final ys = points.map((point) => point.price).toList();

  final xMean = xs.reduce((a, b) => a + b) / xs.length;
  final yMean = ys.reduce((a, b) => a + b) / ys.length;

  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final xDiff = xs[i] - xMean;
    numerator += xDiff * (ys[i] - yMean);
    denominator += xDiff * xDiff;
  }

  if (denominator.abs() < 0.0001) return null;

  final slope = numerator / denominator;
  final intercept = yMean - (slope * xMean);
  final predictedAt = points.last.date.add(const Duration(days: 7));
  final predictedX = hasUsableTimeSpread
      ? predictedAt.difference(firstDate).inHours / 24.0
      : xs.last + 7;
  final predictedPrice = intercept + (slope * predictedX);

  return _LinearForecastResult(
    predictedPrice: predictedPrice,
    predictedAt: predictedAt,
    slopePerDay: slope,
  );
}

double _emaForecast(List<_ForecastPoint> points) {
  const alpha = 0.35;
  var ema = points.first.price;
  for (var i = 1; i < points.length; i++) {
    ema = alpha * points[i].price + (1 - alpha) * ema;
  }

  if (points.length < 2) return ema;

  final recentSlope =
      (points.last.price - points[points.length - 2].price) * 0.65;
  return ema + recentSlope;
}

double _forecastConfidence({
  required int pointCount,
  required List<double> prices,
  required FuelPriceBand? band,
  required double predictedPrice,
}) {
  var confidence = 0.35 + (pointCount.clamp(0, 8) * 0.06);

  if (pointCount >= 5) confidence += 0.08;
  if (pointCount >= 7) confidence += 0.05;

  if (prices.length >= 2) {
    final spread = prices.reduce(math.max) - prices.reduce(math.min);
    if (spread <= 4) confidence += 0.08;
    if (spread >= 12) confidence -= 0.12;
  }

  if (band != null && band.count > 0) {
    if (band.contains(predictedPrice) && band.contains(prices.last)) {
      confidence += 0.1;
    } else {
      confidence -= 0.15;
    }
  }

  return confidence.clamp(0.25, 0.92);
}

double? _reportFuelPrice(PriceReport report, String fuelType) {
  return switch (fuelType) {
    'diesel' => report.diesel,
    'premium' => report.premium,
    _ => report.gasoline,
  };
}

class _ForecastPoint {
  const _ForecastPoint(this.date, this.price);

  final DateTime date;
  final double price;
}

class _LinearForecastResult {
  const _LinearForecastResult({
    required this.predictedPrice,
    required this.predictedAt,
    required this.slopePerDay,
  });

  final double predictedPrice;
  final DateTime predictedAt;
  final double slopePerDay;
}
