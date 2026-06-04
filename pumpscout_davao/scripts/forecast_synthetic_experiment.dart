// ignore_for_file: avoid_print

import 'dart:math' as math;

void main() {
  final scenarios = [
    SyntheticScenario(
      name: 'Increasing trend',
      prices: [76.00, 76.40, 76.90, 77.30, 77.80],
      expectedDirection: 'increase',
    ),
    SyntheticScenario(
      name: 'Decreasing trend',
      prices: [82.00, 81.50, 81.10, 80.70, 80.30],
      expectedDirection: 'decrease',
    ),
    SyntheticScenario(
      name: 'Stable trend',
      prices: [78.00, 78.10, 78.00, 78.20, 78.10],
      expectedDirection: 'stable',
    ),
    SyntheticScenario(
      name: 'Noisy with outlier',
      prices: [77.40, 77.60, 95.00, 77.80, 78.00, 78.10],
      expectedDirection: 'stable/slight increase',
    ),
  ];

  print(
    '| Scenario | Input prices | Expected | Forecast | Change | Confidence |',
  );
  print('|---|---:|---|---:|---:|---:|');
  for (final scenario in scenarios) {
    final forecast = forecastSyntheticPrice(scenario.prices);
    if (forecast == null) {
      print(
        '| ${scenario.name} | ${scenario.prices.join(', ')} | ${scenario.expectedDirection} | no forecast | - | - |',
      );
      continue;
    }

    final changePrefix = forecast.change >= 0 ? '+' : '';
    print(
      '| ${scenario.name} | ${scenario.prices.map((p) => p.toStringAsFixed(2)).join(', ')} | '
      '${scenario.expectedDirection} | PHP ${forecast.predictedPrice.toStringAsFixed(2)} | '
      '$changePrefix${forecast.change.toStringAsFixed(2)} | ${forecast.confidencePercent}% |',
    );
  }
}

SyntheticForecast? forecastSyntheticPrice(List<double> prices) {
  final points = [
    for (var i = 0; i < prices.length; i++)
      ForecastPoint(i.toDouble(), prices[i]),
  ];
  if (points.length < 3) return null;

  final cleaned = removeOutliers(points);
  if (cleaned.length < 3) return null;

  final linear = linearForecast(cleaned);
  if (linear == null) return null;

  final ema = emaForecast(cleaned);
  const regionalMedian = 76.90;
  const regionalMin = 72.10;
  const regionalMax = 82.70;
  final n = cleaned.length;

  final linearWeight = (0.45 + (n * 0.04)).clamp(0.45, 0.7).toDouble();
  const emaWeight = 0.25;
  final priorWeight = 1 - linearWeight - emaWeight;

  final blended =
      (linear.predictedPrice * linearWeight) +
      (ema * emaWeight) +
      (regionalMedian * priorWeight);
  final predictedPrice = blended.clamp(regionalMin, regionalMax).toDouble();
  final history = cleaned.map((point) => point.price).toList();

  return SyntheticForecast(
    history: history,
    currentPrice: history.last,
    predictedPrice: predictedPrice,
    confidence: forecastConfidence(
      pointCount: n,
      prices: history,
      predictedPrice: predictedPrice,
    ),
  );
}

List<ForecastPoint> removeOutliers(List<ForecastPoint> points) {
  if (points.length < 4) return points;

  final prices = points.map((point) => point.price).toList();
  final mean = prices.reduce((a, b) => a + b) / prices.length;
  final variance =
      prices.map((price) => math.pow(price - mean, 2)).reduce((a, b) => a + b) /
      prices.length;
  final stdDev = math.sqrt(variance);
  final maxDeviation = stdDev < 0.5 ? 4.0 : stdDev * 2.2;

  return points.where((point) {
    return (point.price - mean).abs() <= maxDeviation;
  }).toList();
}

LinearResult? linearForecast(List<ForecastPoint> points) {
  final xs = points.map((point) => point.x).toList();
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
  final predictedX = xs.last + 7;
  return LinearResult(intercept + (slope * predictedX));
}

double emaForecast(List<ForecastPoint> points) {
  const alpha = 0.35;
  var ema = points.first.price;
  for (var i = 1; i < points.length; i++) {
    ema = alpha * points[i].price + (1 - alpha) * ema;
  }

  final recentSlope =
      (points.last.price - points[points.length - 2].price) * 0.65;
  return ema + recentSlope;
}

double forecastConfidence({
  required int pointCount,
  required List<double> prices,
  required double predictedPrice,
}) {
  var confidence = 0.35 + (pointCount.clamp(0, 8) * 0.06);

  if (pointCount >= 5) confidence += 0.08;
  if (pointCount >= 7) confidence += 0.05;

  final spread = prices.reduce(math.max) - prices.reduce(math.min);
  if (spread <= 4) confidence += 0.08;
  if (spread >= 12) confidence -= 0.12;

  const regionalMin = 72.10;
  const regionalMax = 82.70;
  if (predictedPrice >= regionalMin &&
      predictedPrice <= regionalMax &&
      prices.last >= regionalMin &&
      prices.last <= regionalMax) {
    confidence += 0.1;
  } else {
    confidence -= 0.15;
  }

  return confidence.clamp(0.25, 0.92).toDouble();
}

class SyntheticScenario {
  const SyntheticScenario({
    required this.name,
    required this.prices,
    required this.expectedDirection,
  });

  final String name;
  final List<double> prices;
  final String expectedDirection;
}

class ForecastPoint {
  const ForecastPoint(this.x, this.price);

  final double x;
  final double price;
}

class LinearResult {
  const LinearResult(this.predictedPrice);

  final double predictedPrice;
}

class SyntheticForecast {
  const SyntheticForecast({
    required this.history,
    required this.currentPrice,
    required this.predictedPrice,
    required this.confidence,
  });

  final List<double> history;
  final double currentPrice;
  final double predictedPrice;
  final double confidence;

  double get change => predictedPrice - currentPrice;

  int get confidencePercent => (confidence * 100).round().clamp(0, 100);
}
