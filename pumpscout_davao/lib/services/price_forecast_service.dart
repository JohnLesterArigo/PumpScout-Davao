part of '../main.dart';

class FuelPriceForecast {
  const FuelPriceForecast({
    required this.fuelType,
    required this.history,
    required this.currentPrice,
    required this.predictedPrice,
    required this.predictedAt,
    required this.slopePerDay,
  });

  final String fuelType;
  final List<double> history;
  final double currentPrice;
  final double predictedPrice;
  final DateTime predictedAt;
  final double slopePerDay;

  double get change => predictedPrice - currentPrice;

  String get direction {
    if (change.abs() < 0.25) return 'stay stable';
    return change > 0 ? 'increase' : 'decrease';
  }
}

FuelPriceForecast? forecastFuelPrice(
  List<PriceReport> reports,
  String fuelType,
) {
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

  final firstDate = points.first.date;
  final xs = points
      .map((point) => point.date.difference(firstDate).inHours / 24.0)
      .toList();
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
  final predictedX = predictedAt.difference(firstDate).inHours / 24.0;
  final predictedPrice = intercept + (slope * predictedX);

  return FuelPriceForecast(
    fuelType: fuelType,
    history: ys,
    currentPrice: ys.last,
    predictedPrice: predictedPrice.clamp(1, 300).toDouble(),
    predictedAt: predictedAt,
    slopePerDay: slope,
  );
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
