import argparse
import csv
import json
import math
import random
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path


DEFAULT_INPUT = Path("data/training/PumpScout_Davao_Synthetic_fuel_prices.csv")
DEFAULT_OUTPUT = Path("data/training/price_forecast_model.json")

NUMERIC_FEATURES = [                                        
    "current_price",
    "price_1_week_ago",
    "price_2_weeks_ago",
    "rolling_avg_3",
    "change_1_week",
    "change_2_weeks",
    "week_index",
    "lat",
    "lng",
]


def main():
    parser = argparse.ArgumentParser(
        description="Train a simple next-week fuel price forecast model."
    )
    parser.add_argument(
        "--input",
        default=str(DEFAULT_INPUT),
        help=f"CSV training data path. Default: {DEFAULT_INPUT}",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_OUTPUT),
        help=f"Model JSON output path. Default: {DEFAULT_OUTPUT}",
    )
    parser.add_argument("--epochs", type=int, default=180)
    parser.add_argument("--learning-rate", type=float, default=0.035)
    parser.add_argument("--l2", type=float, default=0.0008)
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    rows = load_rows(input_path)
    examples = build_examples(rows)
    if len(examples) < 100:
        raise SystemExit(
            f"Only {len(examples)} training examples were created. "
            "Add more weeks of price history first."
        )

    train_examples, test_examples = split_by_last_dates(examples, holdout_dates=8)
    metadata = build_metadata(examples)
    scaler = fit_scaler(train_examples)

    weights = train_linear_model(
        train_examples,
        metadata,
        scaler,
        epochs=args.epochs,
        learning_rate=args.learning_rate,
        l2=args.l2,
    )

    train_metrics = evaluate(train_examples, metadata, scaler, weights)
    test_metrics = evaluate(test_examples, metadata, scaler, weights)

    model = {
        "modelType": "linear_regression_next_week_price",
        "modelVersion": "synthetic-linear-v1",
        "trainedAt": datetime.now(UTC).isoformat(timespec="seconds"),
        "sourceCsv": str(input_path),
        "target": "next_week_price",
        "numericFeatures": NUMERIC_FEATURES,
        "fuelTypes": metadata["fuelTypes"],
        "productTypes": metadata["productTypes"],
        "brands": metadata["brands"],
        "scaler": scaler,
        "weights": weights,
        "metrics": {
            "train": train_metrics,
            "test": test_metrics,
            "trainingRows": len(train_examples),
            "testRows": len(test_examples),
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(model, indent=2), encoding="utf-8")

    print("Training complete")
    print(f"Input rows: {len(rows)}")
    print(f"Training examples: {len(train_examples)}")
    print(f"Test examples: {len(test_examples)}")
    print(
        "Train MAE: "
        f"{train_metrics['mae']:.2f} PHP | RMSE: {train_metrics['rmse']:.2f} PHP"
    )
    print(
        "Test MAE: "
        f"{test_metrics['mae']:.2f} PHP | RMSE: {test_metrics['rmse']:.2f} PHP"
    )
    print(f"Saved model: {output_path}")


def load_rows(path):
    if not path.exists():
        raise SystemExit(f"CSV not found: {path}")

    required = {
        "station_id",
        "station_name",
        "brand",
        "lat",
        "lng",
        "date",
        "fuel_type",
        "price",
    }

    with path.open(newline="", encoding="utf-8-sig") as file:
        reader = csv.DictReader(file)
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"CSV is missing columns: {', '.join(sorted(missing))}")

        rows = []
        for line_number, raw in enumerate(reader, start=2):
            try:
                rows.append(
                    {
                        "station_id": clean_text(raw["station_id"]),
                        "station_name": clean_text(raw["station_name"]),
                        "brand": clean_text(raw["brand"]).lower(),
                        "lat": float(raw["lat"]),
                        "lng": float(raw["lng"]),
                        "date": datetime.strptime(raw["date"], "%Y-%m-%d").date(),
                        "fuel_type": normalize_fuel_type(raw["fuel_type"]),
                        "product_type": normalize_product_type(
                            raw.get("product_type") or raw["fuel_type"]
                        ),
                        "price": float(raw["price"]),
                    }
                )
            except ValueError as error:
                raise SystemExit(f"Bad value on CSV line {line_number}: {error}")

    return rows


def build_examples(rows):
    grouped = defaultdict(list)
    for row in rows:
        grouped[(row["station_id"], row["product_type"])].append(row)

    examples = []
    first_date = min(row["date"] for row in rows)

    for (_, product_type), history in grouped.items():
        history.sort(key=lambda item: item["date"])
        for index in range(2, len(history) - 1):
            previous_2 = history[index - 2]
            previous_1 = history[index - 1]
            current = history[index]
            target = history[index + 1]

            examples.append(
                {
                    "date": current["date"].isoformat(),
                    "station_id": current["station_id"],
                    "brand": current["brand"],
                    "fuel_type": current["fuel_type"],
                    "product_type": product_type,
                    "target": target["price"],
                    "numeric": {
                        "current_price": current["price"],
                        "price_1_week_ago": previous_1["price"],
                        "price_2_weeks_ago": previous_2["price"],
                        "rolling_avg_3": (
                            current["price"]
                            + previous_1["price"]
                            + previous_2["price"]
                        )
                        / 3,
                        "change_1_week": current["price"] - previous_1["price"],
                        "change_2_weeks": previous_1["price"] - previous_2["price"],
                        "week_index": (current["date"] - first_date).days / 7,
                        "lat": current["lat"],
                        "lng": current["lng"],
                    },
                }
            )

    return examples


def split_by_last_dates(examples, holdout_dates):
    dates = sorted({example["date"] for example in examples})
    test_dates = set(dates[-holdout_dates:])
    train_examples = [example for example in examples if example["date"] not in test_dates]
    test_examples = [example for example in examples if example["date"] in test_dates]
    return train_examples, test_examples


def build_metadata(examples):
    return {
        "fuelTypes": sorted({example["fuel_type"] for example in examples}),
        "productTypes": sorted({example["product_type"] for example in examples}),
        "brands": sorted({example["brand"] for example in examples}),
    }


def fit_scaler(examples):
    scaler = {}
    for name in NUMERIC_FEATURES:
        values = [example["numeric"][name] for example in examples]
        mean = sum(values) / len(values)
        variance = sum((value - mean) ** 2 for value in values) / len(values)
        std = math.sqrt(variance) or 1.0
        scaler[name] = {"mean": mean, "std": std}
    return scaler


def train_linear_model(examples, metadata, scaler, epochs, learning_rate, l2):
    random.seed(42)
    feature_names = expanded_feature_names(metadata)
    weights = {name: 0.0 for name in feature_names}

    for epoch in range(epochs):
        random.shuffle(examples)
        rate = learning_rate / (1.0 + epoch / 180.0)

        for example in examples:
            features = vectorize(example, metadata, scaler)
            prediction = dot(weights, features)
            error = prediction - example["target"]

            for name, value in features.items():
                penalty = l2 * weights[name] if name != "bias" else 0.0
                weights[name] -= rate * ((error * value) + penalty)

    return weights


def evaluate(examples, metadata, scaler, weights):
    errors = []
    absolute_percentage_errors = []

    for example in examples:
        prediction = dot(weights, vectorize(example, metadata, scaler))
        error = prediction - example["target"]
        errors.append(error)
        if example["target"] != 0:
            absolute_percentage_errors.append(abs(error / example["target"]) * 100)

    mae = sum(abs(error) for error in errors) / len(errors)
    rmse = math.sqrt(sum(error * error for error in errors) / len(errors))
    mape = sum(absolute_percentage_errors) / len(absolute_percentage_errors)

    return {
        "mae": round(mae, 4),
        "rmse": round(rmse, 4),
        "mape": round(mape, 4),
    }


def vectorize(example, metadata, scaler):
    features = {"bias": 1.0}

    for name in NUMERIC_FEATURES:
        value = example["numeric"][name]
        features[name] = (value - scaler[name]["mean"]) / scaler[name]["std"]

    for fuel_type in metadata["fuelTypes"]:
        features[f"fuel_type={fuel_type}"] = (
            1.0 if example["fuel_type"] == fuel_type else 0.0
        )

    for product_type in metadata["productTypes"]:
        features[f"product_type={product_type}"] = (
            1.0 if example["product_type"] == product_type else 0.0
        )

    for brand in metadata["brands"]:
        features[f"brand={brand}"] = 1.0 if example["brand"] == brand else 0.0

    return features


def expanded_feature_names(metadata):
    names = ["bias", *NUMERIC_FEATURES]
    names.extend(f"fuel_type={fuel_type}" for fuel_type in metadata["fuelTypes"])
    names.extend(
        f"product_type={product_type}" for product_type in metadata["productTypes"]
    )
    names.extend(f"brand={brand}" for brand in metadata["brands"])
    return names


def dot(weights, features):
    return sum(weights[name] * value for name, value in features.items())


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


if __name__ == "__main__":
    main()
