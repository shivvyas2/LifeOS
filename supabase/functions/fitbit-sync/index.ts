// Fitbit sync.
//
// Holds the credential and the quota, and nothing else. The payloads go back
// to the device raw and are interpreted there, so a derivation bug is fixable
// by re-deriving from the archive rather than by spending another 150-request
// hour asking Fitbit for the same data.

import { json, resolveUser, serviceClient } from "../_shared/supabase.ts";
import {
  classifyFitbitFailure,
  FITBIT_API_BASE,
  FITBIT_TOKEN_URL,
  quotaRemaining,
  rangePath,
  tokenForm,
} from "../_shared/fitbit.ts";

/// Every range collection, with Fitbit's own cap on how many days one request
/// may span. Exceeding a cap is a 400 that names nothing useful.
const COLLECTIONS: { key: string; maxDays: number }[] = [
  { key: "sleep", maxDays: 100 },
  { key: "hrv", maxDays: 30 },
  { key: "spo2", maxDays: 30 },
  { key: "breathing", maxDays: 30 },
  { key: "skinTemperature", maxDays: 30 },
  { key: "restingHeartRate", maxDays: 365 },
  { key: "cardioFitness", maxDays: 30 },
];

/// Stop while there is still headroom rather than at zero. A sync that spends
/// the user's last request leaves nothing for the retry, and Fitbit's quota
/// resets only at the top of the hour.
const QUOTA_FLOOR = 10;

/// The columns this function reads. Declared because the rpc helpers return an
/// untyped row, and an untyped credential is one rename away from a silent
/// undefined reaching the Authorization header.
interface FitbitConnection {
  access_token: string;
  refresh_token: string;
  access_expires_at: string;
  needs_reauth: boolean;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let body: { days?: number };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const days = Math.min(Math.max(body.days ?? 30, 1), 365);

  const db = serviceClient();
  const { data: connection } = await db
    .rpc("read_fitbit_connection", { p_user_id: userID })
    .maybeSingle<FitbitConnection>();

  if (!connection) return json({ error: "not_connected" }, 404);
  // A dead credential is not a retry. Nothing the server holds can be used
  // again, so the app is told to ask the user to sign in rather than being
  // left to spin against it.
  if (connection.needs_reauth) return json({ needs_reauth: true, payloads: {}, failures: {} }, 200);

  let accessToken: string = connection.access_token;

  if (new Date(connection.access_expires_at).getTime() <= Date.now() + 60_000) {
    const refreshed = await refresh(db, userID);
    if (refreshed === "needs_reauth") {
      return json({ needs_reauth: true, payloads: {}, failures: {} }, 200);
    }
    if (refreshed === "busy") {
      // Another device is mid-refresh and will rotate the token out from under
      // us. Reporting this as a rate limit is deliberate: it is a "come back
      // shortly", not a fault, and the app already knows how to show that.
      return json({ payloads: {}, failures: {}, needs_reauth: false, retry: true }, 200);
    }
    accessToken = refreshed;
  }

  const end = new Date();
  const payloads: Record<string, unknown> = {};
  const failures: Record<string, string> = {};
  let stoppedForQuota = false;

  // Sequential, not Promise.all: the quota headroom arrives in each response,
  // and it can only stop the loop if the loop is still running.
  for (const collection of COLLECTIONS) {
    if (stoppedForQuota) {
      failures[collection.key] = "rate_limited";
      continue;
    }

    const span = Math.min(days, collection.maxDays);
    const start = new Date(end.getTime() - span * 86_400_000);
    const path = rangePath(collection.key, isoDay(start), isoDay(end));

    try {
      const response = await fetch(`${FITBIT_API_BASE}${path}`, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });

      const remaining = quotaRemaining(response.headers);
      if (remaining !== null && remaining <= QUOTA_FLOOR) stoppedForQuota = true;

      if (!response.ok) {
        const text = await response.text();
        // One collection failing must never abort the others. A user who
        // declined a single scope still gets the six that were granted.
        failures[collection.key] = classifyFitbitFailure(response.status, text);
        console.error(`fitbit ${collection.key} failed: ${response.status} ${text.slice(0, 200)}`);
        continue;
      }

      payloads[collection.key] = await response.json();
    } catch (error) {
      failures[collection.key] = "upstream_failure";
      console.error(`fitbit ${collection.key} threw: ${error}`);
    }
  }

  return json({ payloads, failures, needs_reauth: false, retry: stoppedForQuota }, 200);
});

/// Rotates the token under a lease, so exactly one caller does it.
///
/// Returns the new access token, "busy" when another sync holds the lease, or
/// "needs_reauth" when Fitbit refused the refresh token outright.
async function refresh(
  // deno-lint-ignore no-explicit-any
  db: any,
  userID: string,
): Promise<string | "busy" | "needs_reauth"> {
  const { data } = await db
    .rpc("claim_fitbit_refresh", { p_user_id: userID, p_lease_seconds: 30 })
    .maybeSingle();
  const claimed = data as FitbitConnection | null;

  if (!claimed) return "busy";

  const clientID = Deno.env.get("FITBIT_CLIENT_ID");
  const clientSecret = Deno.env.get("FITBIT_CLIENT_SECRET");
  if (!clientID || !clientSecret) throw new Error("server_not_configured");

  const response = await fetch(FITBIT_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${btoa(`${clientID}:${clientSecret}`)}`,
    },
    body: tokenForm({ refresh_token: claimed.refresh_token }),
  });

  const text = await response.text();
  if (!response.ok) {
    const kind = classifyFitbitFailure(response.status, text);
    console.error(`fitbit refresh failed: ${response.status} ${text.slice(0, 200)}`);

    if (kind === "needs_reauth") {
      await db.from("fitbit_connections")
        .update({ needs_reauth: true, refresh_lease_until: null })
        .eq("user_id", userID);
      return "needs_reauth";
    }
    // Release the lease so a transient failure does not block the next sync
    // for the rest of the lease window.
    await db.from("fitbit_connections")
      .update({ refresh_lease_until: null }).eq("user_id", userID);
    throw new Error(kind);
  }

  const tokens = JSON.parse(text) as {
    access_token: string;
    refresh_token: string;
    expires_in: number;
  };

  // Both halves, together. Writing the access token without the rotated
  // refresh token would leave a credential that cannot be renewed again.
  await db.from("fitbit_connections").update({
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
    access_expires_at: new Date(Date.now() + (tokens.expires_in ?? 28_800) * 1000).toISOString(),
    refresh_lease_until: null,
    updated_at: new Date().toISOString(),
  }).eq("user_id", userID);

  return tokens.access_token;
}

function isoDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}
