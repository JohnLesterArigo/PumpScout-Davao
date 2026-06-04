# PumpScout ML Roadmap

## Should everything be full machine learning?

Not yet for price forecasting.

- **Price forecast:** Most stations only have a few verified history points. Deep learning will overfit until you have long time series per station (months of weekly or daily prices).
- **Spam screening:** This is the better first ML target because you already have labeled spam examples and clear numeric/text features.

## What the app uses today

### Price forecast (`ensemble-v1`)

Runs on the phone using:

1. Verified `priceReports` for the station
2. Outlier removal
3. Linear trend
4. Exponential smoothing
5. Davao regional priors from `assets/data/regional_price_stats.json`

Rebuild regional priors after updating the real reference CSV:

```powershell
.\scripts\build_regional_price_stats.ps1
```

### Spam screening (`rules-v1`)

Rule-based checks in `lib/services/contribution_classifier.dart`.

Training files live in:

- `data/training/` (spam examples)
- `data/reference/` (real Davao pump prices)

## When to add true ML

Add a trained model when you have:

- **Forecasting:** 500+ verified reports across many stations with dates
- **Spam:** 100+ verified real reports and 100+ rejected reports with reasons

## Recommended next steps

1. Keep reviewing contributions in the admin dashboard (`verified` / `rejected` labels become training data).
2. Export reviewed reports with a script (to be added) into `data/training/`.
3. Train a small Python model (scikit-learn) offline.
4. Deploy scores through a Firebase Cloud Function or bundle model weights into the app.

## Full ML architecture (later)

```text
Flutter app
  -> Cloud Function `screenContribution`
  -> Python model (RandomForest / logistic regression for spam)
  -> optional time-series model for forecast when data is large enough
```

Until then, the ensemble forecaster plus rules screening is the most reliable setup.
