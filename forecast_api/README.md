# PumpScout Davao Forecast API

This Flask API exposes the PumpScout fuel price forecast model as an HTTP endpoint.
It does not train the model. It only loads the exported JSON model and runs prediction.

## Local Run

From the project root:

```bash
cd forecast_api
pip install -r requirements.txt
python app.py
```

Open:

```text
http://127.0.0.1:5000/
```

Test prediction:

```bash
curl -X POST http://127.0.0.1:5000/predict ^
  -H "Content-Type: application/json" ^
  -d "{\"brand\":\"shell\",\"fuelType\":\"diesel\",\"productType\":\"shell_fuelsave_diesel\",\"lat\":7.05,\"lng\":125.58,\"history\":[{\"date\":\"2026-06-01\",\"price\":80.0},{\"date\":\"2026-06-08\",\"price\":80.8},{\"date\":\"2026-06-15\",\"price\":81.2}]}"
```

## Render Deployment

1. Push this repository to GitHub.
2. Open Render and choose **New Web Service**.
3. Connect the GitHub repository.
4. Use these settings:

```text
Root Directory: forecast_api
Build Command: pip install -r requirements.txt
Start Command: gunicorn app:app
```

5. Deploy the service.
6. Render will provide a URL like:

```text
https://pumpscout-forecast-api.onrender.com
```

7. Test:

```text
https://pumpscout-forecast-api.onrender.com/
```

## Request Body

```json
{
  "brand": "shell",
  "fuelType": "diesel",
  "productType": "shell_fuelsave_diesel",
  "lat": 7.05,
  "lng": 125.58,
  "history": [
    {"date": "2026-06-01", "price": 80.0},
    {"date": "2026-06-08", "price": 80.8},
    {"date": "2026-06-15", "price": 81.2}
  ]
}
```

## Response

```json
{
  "brand": "shell",
  "change": 0.52,
  "confidencePercent": 64,
  "currentPrice": 81.2,
  "fuelType": "diesel",
  "method": "Linear regression model loaded from JSON",
  "modelVersion": "synthetic-linear-v1",
  "predictedAt": "2026-06-22",
  "predictedPrice": 81.72,
  "productType": "shell_fuelsave_diesel"
}
```

