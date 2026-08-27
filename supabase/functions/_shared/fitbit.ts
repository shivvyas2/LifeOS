// Pure Fitbit helpers, shared by fitbit-token and fitbit-sync.
//
// Everything here is a function of its arguments, so it is tested with
// `deno test` and no network. The functions that do talk to Fitbit are thin
// wrappers around these decisions.

export const FITBIT_TOKEN_URL = "https://api.fitbit.com/oauth2/token";
export const FITBIT_API_BASE = "https://api.fitbit.com";

/// Every scope the app reads, and no scope it does not.
///
/// Deliberately absent: location, social, settings, electrocardiogram,
/// irregular_rhythm_notifications, blood_glucose. None of them feed the daily
/// spine, and each one is a line on the consent screen asking a person for
/// something this app will never look at.
export const FITBIT_SCOPES = [
  "activity",
  "cardio_fitness",
  "heartrate",
  "nutrition",
  "oxygen_saturation",
  "profile",
  "respiratory_rate",
  "sleep",
  "temperature",
  "weight",
];

export type FitbitFailure =
  | "needs_reauth"
  | "rate_limited"
  | "forbidden_scope"
  | "upstream_failure";

/// Why a Fitbit request failed, in the only four kinds the app acts on
/// differently. Collapsing these leaves the app retrying forever against a
/// dead credential, or reporting an exhausted quota as a broken connection.
export function classifyFitbitFailure(status: number, body: string): FitbitFailure {
  if (status === 429) return "rate_limited";
  if (status === 401) return "needs_reauth";

  let errorType = "";
  try {
    const parsed = JSON.parse(body);
    errorType = parsed?.errors?.[0]?.errorType ?? "";
  } catch {
    // Fitbit is not obliged to send JSON when it is having a bad day.
    return "upstream_failure";
  }

  if (errorType === "invalid_grant" || errorType === "expired_token") return "needs_reauth";
  if (status === 403 || errorType === "insufficient_scope") return "forbidden_scope";
  return "upstream_failure";
}

/// How many requests remain in this hour, or null when Fitbit did not say.
/// Null is treated as "unknown, take the conservative path", never as zero and
/// never as unlimited.
export function quotaRemaining(headers: Headers): number | null {
  const raw = headers.get("Fitbit-Rate-Limit-Remaining");
  if (raw === null) return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

/// The token endpoint's body. An exchange and a refresh are the same endpoint
/// with different grant types, and getting that wrong fails opaquely.
export function tokenForm(body: {
  code?: string;
  verifier?: string;
  redirect_uri?: string;
  refresh_token?: string;
}): URLSearchParams {
  const form = new URLSearchParams();
  if (body.refresh_token) {
    form.set("grant_type", "refresh_token");
    form.set("refresh_token", body.refresh_token);
    return form;
  }
  form.set("grant_type", "authorization_code");
  if (body.code) form.set("code", body.code);
  if (body.redirect_uri) form.set("redirect_uri", body.redirect_uri);
  if (body.verifier) form.set("code_verifier", body.verifier);
  return form;
}

/// Where each range collection lives. Sleep is the only one on v1.2, and
/// Fitbit answers a wrong path with a 404 that names nothing.
export function rangePath(collection: string, start: string, end: string): string {
  switch (collection) {
    case "sleep":            return `/1.2/user/-/sleep/date/${start}/${end}.json`;
    case "hrv":              return `/1/user/-/hrv/date/${start}/${end}.json`;
    case "spo2":             return `/1/user/-/spo2/date/${start}/${end}.json`;
    case "breathing":        return `/1/user/-/br/date/${start}/${end}.json`;
    case "skinTemperature":  return `/1/user/-/temp/skin/date/${start}/${end}.json`;
    case "restingHeartRate": return `/1/user/-/activities/heart/date/${start}/${end}.json`;
    case "cardioFitness":    return `/1/user/-/cardioscore/date/${start}/${end}.json`;
    default: throw new Error(`unknown collection ${collection}`);
  }
}
