import argparse
import json
from collections import defaultdict
from pathlib import Path

from train_price_forecast_model import (
    NUMERIC_FEATURES,
    load_rows,
    normalize_fuel_type,
    normalize_product_type,
)


DEFAULT_DATA = Path("data/training/PumpScout_Davao_Synthetic_fuel_prices.csv")
DEFAULT_MODEL = Path("data/training/price_forecast_model.json")


def main():
    parser = argparse.ArgumentParser(
        description="Test a trained PumpScout next-week price forecast model."
    )
    parser.add_argument("--station", help="Station id, for example synthetic_shell_001")
    parser.add_argument("--fuel", default="diesel", help="diesel, regular/gasoline, or premium")
    parser.add_argument(
        "--product",
        help="Optional product type, for example shell_vpower_diesel.",
    )
    parser.add_argument("--data", default=str(DEFAULT_DATA))
    parser.add_argument("--model", default=str(DEFAULT_MODEL))
    parser.add_argument(
        "--list-stations",
        action="store_true",
        help="Print the first 20 station ids from the CSV.",
    )
    args = parser.parse_args()

    rows = load_rows(Path(args.data))
    if args.list_stations:
        print_station_examples(rows)
        return

    if not args.station:
        raise SystemExit(
            "Choose a station id with --station, or run with --list-stations first."
        )

    model = json.loads(Path(args.model).read_text(encoding="utf-8"))
    fuel_type = normalize_fuel_type(args.fuel)
    product_type = normalize_product_type(args.product or args.fuel)
    history = station_product_history(rows, args.station, fuel_type, product_type)

    if len(history) < 3:
        raise SystemExit(
            f"Need at least 3 rows for station={args.station}, "
            f"fuel={fuel_type}, product={product_type}. "
            f"Found {len(history)}."
        )

    prediction = predict_next_price(model, history)
    latest = history[-1]
    previous = history[-2]

    print("Forecast test")
    print(f"Station: {latest['station_name']} ({latest['station_id']})")
    print(f"Brand: {latest['brand']}")
    print(f"Fuel: {fuel_type}")
    print(f"Product: {latest['product_type']}")
    print(f"Latest date: {latest['date']}")
    print(f"Previous price: PHP {previous['price']:.2f}")
    print(f"Latest price: PHP {latest['price']:.2f}")
    print(f"Predicted next week: PHP {prediction:.2f}")
    print(f"Change: PHP {prediction - latest['price']:+.2f}")


def station_product_history(rows, station_id, fuel_type, product_type):
    history = [
        row
        for row in rows
        if row["station_id"] == station_id
        and row["fuel_type"] == fuel_type
        and row["product_type"] == product_type
    ]
    history.sort(key=lambda row: row["date"])
    return history


def predict_next_price(model, history):
    previous_2 = history[-3]
    previous_1 = history[-2]
    current = history[-1]
    first_date = history[0]["date"]

    numeric = {
        "current_price": current["price"],
        "price_1_week_ago": previous_1["price"],
        "price_2_weeks_ago": previous_2["price"],
        "rolling_avg_3": (current["price"] + previous_1["price"] + previous_2["price"])
        / 3,
        "change_1_week": current["price"] - previous_1["price"],
        "change_2_weeks": previous_1["price"] - previous_2["price"],
        "week_index": (current["date"] - first_date).days / 7,
        "lat": current["lat"],
        "lng": current["lng"],
    }

    features = {"bias": 1.0}
    for name in NUMERIC_FEATURES:
        scaler = model["scaler"][name]
        features[name] = (numeric[name] - scaler["mean"]) / scaler["std"]

    for option in model["fuelTypes"]:
        features[f"fuel_type={option}"] = 1.0 if current["fuel_type"] == option else 0.0

    for option in model.get("productTypes", []):
        features[f"product_type={option}"] = (
            1.0 if current["product_type"] == option else 0.0
        )

    for option in model["brands"]:
        features[f"brand={option}"] = 1.0 if current["brand"] == option else 0.0

    weights = model["weights"]
    return sum(weights.get(name, 0.0) * value for name, value in features.items())


def print_station_examples(rows):
    grouped = defaultdict(set)
    for row in rows:
        grouped[row["station_id"]].add(row["product_type"])

    print("Example station ids:")
    for station_id in sorted(grouped)[:20]:
        products = ", ".join(sorted(grouped[station_id]))
        print(f"- {station_id}: {products}")


if __name__ == "__main__":
    main()
