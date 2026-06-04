# PumpScout Davao 1-Week Fuel Price Forecast Experiment

## What To Present

This proof has two parts:

1. Show the app screen where a station displays a 1-week fuel price forecast.
2. Show synthetic regression experiment results proving the model reacts correctly to known price patterns.

## Forecast Feature In The App

The app displays the 1-week forecast in the station bottom sheet under **Price Forecast**.

Code location:

- Forecast UI: `lib/widgets/map_container.dart`
- Forecast model: `lib/services/price_forecast_service.dart`
- Graph painter: `lib/widgets/price_trend_painter.dart`
- Verified report loader: `lib/services/station_service.dart`

The forecast only runs when the selected fuel type has at least 3 verified price reports for the station.

## Model Used

The app uses a small statistical ensemble model, not a trained AI model.

The model combines:

1. Linear regression trend
   - Detects if the station price is generally increasing or decreasing.

2. Exponential moving average
   - Smooths recent reports so one report does not control the forecast too much.

3. Davao regional reference price
   - Keeps the prediction inside realistic regional price ranges.

Model label in the app:

`ensemble-v1+regional-prior-v1`

## Graph Logic

The graph is drawn from verified price reports.

- Green line: verified historical price reports.
- Green dots: each verified report.
- Orange dashed line: movement from latest verified price to forecast.
- Orange dot: predicted price for next week.

If the predicted price is lower than the latest verified report, the app says the price may decrease.
If the predicted price is higher, the app says the price may increase.
If the change is very small, the app says the price may stay stable.

## Confidence Logic

The confidence percentage is a data-quality score, not a guarantee.

The score increases when:

- There are more verified reports.
- There are at least 5 reports.
- There are at least 7 reports.
- The prices are stable and not too spread out.
- The predicted price is inside the Davao regional price range.

The score decreases when:

- Prices are very spread out.
- The prediction is outside the normal Davao price range.
- The latest price is outside the normal Davao price range.

Important explanation for presentation:

`91% confidence` means the app has high confidence in the available data quality. It does not mean the future price is guaranteed to be exactly correct.

## Synthetic Regression Experiment

The experiment uses synthetic price histories where the expected trend is already known.

Runnable script:

`scripts/forecast_synthetic_experiment.dart`

Run command:

```powershell
dart run scripts/forecast_synthetic_experiment.dart
```

## Experiment Results

| Scenario | Input prices | Expected | Forecast | Change | Confidence |
|---|---:|---|---:|---:|---:|
| Increasing trend | 76.00, 76.40, 76.90, 77.30, 77.80 | increase | PHP 79.65 | +1.85 | 91% |
| Decreasing trend | 82.00, 81.50, 81.10, 80.70, 80.30 | decrease | PHP 78.13 | -2.17 | 91% |
| Stable trend | 78.00, 78.10, 78.00, 78.20, 78.10 | stable | PHP 78.12 | +0.02 | 91% |
| Noisy with outlier | 77.40, 77.60, 95.00, 77.80, 78.00, 78.10 | stable/slight increase | PHP 78.57 | +0.47 | 91% |

## Interpretation

The experiment shows that the forecast behaves as expected:

- When synthetic prices increase, the forecast increases.
- When synthetic prices decrease, the forecast decreases.
- When synthetic prices are stable, the forecast stays almost the same.
- When one noisy outlier is added, the model still gives a reasonable forecast because of smoothing and regional reference pricing.

## Conclusion

The 1-week price forecast is suitable as a guidance feature for PumpScout users.
It should be presented as an estimate based on verified historical price data, not as a guaranteed future fuel price.
