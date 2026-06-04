const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

const geminiApiKey = defineSecret("GEMINI_API_KEY");

const DEFAULT_MODEL = "gemini-2.5-flash";
const GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta";

exports.screenPriceContribution = onCall(
  {
    region: "asia-southeast1",
    secrets: [geminiApiKey],
    timeoutSeconds: 45,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in before screening reports.");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      throw new HttpsError("failed-precondition", "Gemini API key is not configured.");
    }

    const report = sanitizeReport(request.data || {});
    const prompt = buildScreeningPrompt(report);
    const parts = [{ text: prompt }];

    const imagePart = await imagePartFromUrl(report.photoUrl);
    if (imagePart) {
      parts.push(imagePart);
    }

    const model = process.env.GEMINI_MODEL || DEFAULT_MODEL;
    const response = await fetch(
      `${GEMINI_ENDPOINT}/models/${model}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts }],
          generationConfig: {
            temperature: 0.1,
            responseMimeType: "application/json",
          },
        }),
      },
    );

    if (!response.ok) {
      const body = await response.text();
      logger.error("Gemini screening failed", {
        status: response.status,
        body: body.slice(0, 1000),
      });
      throw new HttpsError("unavailable", "Gemini screening failed.");
    }

    const json = await response.json();
    const rawText = json.candidates?.[0]?.content?.parts
      ?.map((part) => part.text || "")
      .join("\n")
      .trim();

    const parsed = parseGeminiJson(rawText);
    return applyPolicyCaps(parsed, report, model);
  },
);

function sanitizeReport(data) {
  return {
    stationName: stringField(data.stationName, "Fuel station"),
    brand: stringField(data.brand, ""),
    gasoline: numberOrNull(data.gasoline),
    diesel: numberOrNull(data.diesel),
    premium: numberOrNull(data.premium),
    distanceMeters: numberOrNull(data.distanceMeters),
    hasPhoto: data.hasPhoto === true,
    photoUploadFailed: data.photoUploadFailed === true,
    photoUrl: stringField(data.photoUrl, ""),
    contributorTrustScore: numberOrNull(data.contributorTrustScore),
    nearbyReferencePrices: Array.isArray(data.nearbyReferencePrices)
      ? data.nearbyReferencePrices.slice(0, 8)
      : [],
  };
}

function buildScreeningPrompt(report) {
  return [
    "You are PumpScout Davao's fuel price contribution validator.",
    "Classify the submitted fuel price report as usable, needs_review, or spam.",
    "Base your decision on proof/photo evidence, location accuracy, price plausibility, reference price consistency, contributor trust, and spam patterns.",
    "No photo should strongly reduce confidence. Do not mark a no-photo report high confidence unless every other signal is excellent.",
    "Return only valid JSON with this exact shape:",
    '{"label":"usable|needs_review|spam","confidence":0.0,"reasons":["short reason"],"breakdown":{"photoEvidence":0,"locationAccuracy":0,"priceConsistency":0,"contributorTrust":0,"spamSafety":0}}',
    "Breakdown values are points. Use photoEvidence max 30, locationAccuracy max 20, priceConsistency max 25, contributorTrust max 15, spamSafety max 10.",
    `Report JSON: ${JSON.stringify(report)}`,
  ].join("\n");
}

async function imagePartFromUrl(photoUrl) {
  if (!photoUrl) return null;

  try {
    const response = await fetch(photoUrl);
    if (!response.ok) return null;

    const contentType = response.headers.get("content-type") || "image/jpeg";
    if (!contentType.startsWith("image/")) return null;

    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > 5 * 1024 * 1024) return null;

    return {
      inlineData: {
        mimeType: contentType,
        data: bytes.toString("base64"),
      },
    };
  } catch (error) {
    logger.warn("Could not attach report photo to Gemini request", { error });
    return null;
  }
}

function parseGeminiJson(rawText) {
  if (!rawText) {
    throw new HttpsError("internal", "Gemini returned an empty response.");
  }

  try {
    return JSON.parse(rawText);
  } catch (_) {
    const match = rawText.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new HttpsError("internal", "Gemini returned invalid JSON.");
    }
    return JSON.parse(match[0]);
  }
}

function applyPolicyCaps(result, report, model) {
  const label = ["usable", "needs_review", "spam"].includes(result.label)
    ? result.label
    : "needs_review";

  const reasons = Array.isArray(result.reasons)
    ? result.reasons.map((reason) => String(reason)).filter(Boolean).slice(0, 6)
    : [];

  let confidence = clamp(Number(result.confidence), 0.35, 0.98);
  let finalLabel = label;

  if (!report.hasPhoto && finalLabel === "usable" && confidence > 0.65) {
    confidence = 0.65;
    finalLabel = "needs_review";
    reasons.unshift("No receipt or pump photo was attached, so confidence is capped.");
  }

  if (report.photoUploadFailed) {
    finalLabel = "needs_review";
    confidence = Math.min(confidence, 0.6);
    reasons.unshift("A photo was selected, but upload failed.");
  }

  if (report.distanceMeters == null || report.distanceMeters > 3000) {
    finalLabel = finalLabel === "spam" ? "spam" : "needs_review";
    confidence = Math.min(confidence, 0.68);
    reasons.unshift("Reporter location was not verified within 3 km.");
  }

  const hasReason = reasons.length > 0;
  return {
    label: finalLabel,
    confidence,
    reasons: hasReason ? reasons : ["Gemini completed the automatic screening."],
    breakdown: sanitizeBreakdown(result.breakdown),
    needsAdminAttention: finalLabel !== "usable",
    modelVersion: `gemini-${model}`,
  };
}

function sanitizeBreakdown(breakdown) {
  const value = breakdown && typeof breakdown === "object" ? breakdown : {};
  return {
    photoEvidence: clamp(Number(value.photoEvidence), 0, 30),
    locationAccuracy: clamp(Number(value.locationAccuracy), 0, 20),
    priceConsistency: clamp(Number(value.priceConsistency), 0, 25),
    contributorTrust: clamp(Number(value.contributorTrust), 0, 15),
    spamSafety: clamp(Number(value.spamSafety), 0, 10),
  };
}

function stringField(value, fallback) {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function clamp(value, min, max) {
  if (!Number.isFinite(value)) return min;
  return Math.min(Math.max(value, min), max);
}
