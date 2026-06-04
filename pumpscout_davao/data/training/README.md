# PumpScout Spam Screening Dataset

This folder is for building the training data behind PumpScout contribution
screening.

## Current State

`GasPrice_Spam_Dataset_300.csv` is a synthetic spam-only starter dataset. It is
useful for defining bad examples such as:

- negative prices
- extremely low prices
- extremely high or absurd prices
- typo-like prices with extra digits
- invalid fuel price relationships

It is not enough to train a reliable AI model yet because it does not include
real legitimate reports. A classifier needs both spam and not-spam examples.

## Best First Milestone

Keep the app's current rules-based classifier as the first AI screen. It already
flags each contribution with:

- `aiClassification`: `usable`, `needs_review`, or `spam`
- `aiConfidence`
- `aiReasons`
- `aiModelVersion`

Admins should still verify or reject every contribution. Those admin decisions
become the real labels for future training.

## Label Meaning

For training exports:

- `status = verified` means `is_spam = false`
- `status = rejected` means `is_spam = true`
- `status = pending` should not be used as a final training label

Use `spam_type` to describe why something was rejected when possible, for
example:

- `negative`
- `extremely_low`
- `extremely_high`
- `absurd`
- `invalid_relationship`
- `photo_mismatch`
- `unclear_photo`
- `wrong_station`
- `duplicate`
- `other`

## Practical Progress Plan

1. Use the existing admin dashboard to review every pending contribution.
2. Export reviewed reports with `scripts/export_reviewed_price_reports.ps1`.
3. Append verified rows to the dataset as not-spam examples.
4. Append rejected rows as spam examples with a rejection reason or spam type.
5. When there are at least 100-300 real verified rows and 100-300 real rejected
   rows, train a small model.
6. Keep the rules as a safety layer even after adding a trained model.

## Why Start With Rules

Fuel price spam is mostly numeric at first. Rules catch the obvious problems
well:

- price below realistic Davao ranges
- price above realistic ranges
- impossible negative values
- one fuel type wildly different from the others
- missing proof photo or failed upload
- suspicious station text

A trained model becomes more useful later when you have real user behavior,
photos, station history, repeat offenders, and admin decisions.
