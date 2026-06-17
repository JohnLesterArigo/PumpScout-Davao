import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

from flask import Flask, jsonify, request
from flask_cors import CORS


DEFAULT_MODEL_PATH = (
    Path(__file__).resolve().parent.parent
    / "data"
    / "training"
    / "price_forecast_model.json"
)
MODEL_PATH = Path(os.environ.get("PRICE_FORECAST_MODEL_PATH", DEFAULT_MODEL_PATH))

app = Flask(__name__)
CORS(app)


def load_model():
    with MODEL_PATH.open(encoding="utf-8") as file:
        return json.load(file)


MODEL = load_model()


def normalize_fuel_type(value):
    fuel_type = clean_text(value).lower()
    if fuel_type in {"regular", "unleaded", "gas", "gasoline"}:
        return "gasoline"
    if fuel_type in {"premium", "premium gasoline"}:
        return "premium"
    if fuel_type == "diesel":
        return "diesel"
    return fuel_type


def normalize_product_type(value):
    product_type = clean_text(value).lower()
    product_type = product_type.replace("&", " and ")
    product_type = "_".join(
        word for word in product_type.replace("-", " ").split() if word
    )
    product_type = product_type.replace("v_power", "vpower")
    product_type = product_type.replace("fuel_save", "fuelsave")
    if product_type in {"regular", "unleaded", "gas", "gasoline"}:
        return "gasoline"
    if product_type in {"premium", "premium_gasoline"}:
        return "premium"
    return product_type


def clean_text(value):
    return " ".join(str(value or "").strip().split())


def number_field(data, name, fallback=None):
    value = data.get(name, fallback)
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def predict_next_price(model, payload):
    fuel_type = normalize_fuel_type(payload.get("fuelType", "gasoline"))
    product_type = normalize_product_type(payload.get("productType", fuel_type))
    brand = clean_text(payload.get("brand", "")).lower()

    history = payload.get("history")
    if not isinstance(history, list) or len(history) < 3:
        raise ValueError("history must contain at least 3 price points")

    prices = [float(point["price"]) for point in history]
    latest = prices[-1]
    previous = prices[-2]
    previous_two = prices[-3]

    latest_date = parse_date(history[-1].get("date"))
    first_date = parse_date(history[0].get("date"))
    week_index = (latest_date - first_date).days / 7

    numeric = {
        "current_price": latest,
        "price_1_week_ago": previous,
        "price_2_weeks_ago": previous_two,
        "rolling_avg_3": (latest + previous + previous_two) / 3,
        "change_1_week": latest - previous,
        "change_2_weeks": previous - previous_two,
        "week_index": week_index,
        "lat": number_field(payload, "lat", 0.0),
        "lng": number_field(payload, "lng", 0.0),
    }

    features = {"bias": 1.0}
    for name in model.get("numericFeatures", []):
        scale = model["scaler"][name]
        std = scale["std"] or 1
        features[name] = (numeric[name] - scale["mean"]) / std

    for option in model.get("fuelTypes", []):
        features[f"fuel_type={option}"] = 1.0 if fuel_type == option else 0.0

    for option in model.get("productTypes", []):
        features[f"product_type={option}"] = 1.0 if product_type == option else 0.0

    for option in model.get("brands", []):
        features[f"brand={option}"] = 1.0 if brand == option else 0.0

    weights = model["weights"]
    raw_prediction = sum(weights.get(name, 0.0) * value for name, value in features.items())
    predicted_price = clamp_price(
        raw_prediction,
        fuel_type,
        payload.get("minPrice"),
        payload.get("maxPrice"),
    )

    return {
        "fuelType": fuel_type,
        "productType": product_type,
        "brand": brand,
        "currentPrice": round(latest, 2),
        "predictedPrice": round(predicted_price, 2),
        "change": round(predicted_price - latest, 2),
        "predictedAt": (latest_date + timedelta(days=7)).isoformat(),
        "confidencePercent": confidence_percent(len(history), latest, predicted_price),
        "modelVersion": model.get("modelVersion", "unknown"),
        "method": "Linear regression model loaded from JSON",
    }


def parse_date(value):
    if not value:
        return datetime.now(timezone.utc).date()
    return datetime.fromisoformat(str(value).replace("Z", "+00:00")).date()


def clamp_price(price, fuel_type, min_price, max_price):
    default_bands = {
        "diesel": (45.0, 95.0),
        "gasoline": (50.0, 105.0),
        "premium": (55.0, 115.0),
    }
    fallback_min, fallback_max = default_bands.get(fuel_type, (45.0, 120.0))
    lower = float(min_price) if min_price is not None else fallback_min
    upper = float(max_price) if max_price is not None else fallback_max
    return max(lower, min(float(price), upper))


def confidence_percent(point_count, current_price, predicted_price):
    confidence = 0.5 + (min(point_count, 10) * 0.035)
    if abs(predicted_price - current_price) <= 3:
        confidence += 0.04
    confidence = max(0.35, min(confidence, 0.9))
    return round(confidence * 100)


@app.get("/")
def health_check():
    return jsonify(
        {
            "status": "ok",
            "service": "PumpScout Davao Forecast API",
            "modelVersion": MODEL.get("modelVersion"),
        }
    )


@app.post("/predict")
def predict():
    try:
        payload = request.get_json(force=True) or {}
        return jsonify(predict_next_price(MODEL, payload))
    except (KeyError, TypeError, ValueError) as error:
        return jsonify({"error": str(error)}), 400


if __name__ == "__main__":
    app.run(debug=True)
