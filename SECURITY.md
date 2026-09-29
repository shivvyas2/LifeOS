# Security

Almanac handles health, financial, and personal data. If you find a vulnerability, please report it privately.

## Reporting

Use GitHub's private vulnerability reporting: open the **Security** tab of this repository and choose **Report a vulnerability**. Do not open a public issue for security problems.

Include what you found, how to reproduce it, and what data or accounts it could affect. You will get an acknowledgement within a few days and a fix or a plan within two weeks for anything that exposes user data.

## What counts

- Any way to read another user's rows through the Supabase REST API or an Edge Function. Row Level Security is the boundary; a policy gap is a vulnerability.
- Secrets in the repo, in build output, or in logs.
- OAuth redirect or token handling for Whoop, Fitbit, or Plaid that could leak a token.
- Keychain, App Group, or WatchConnectivity handling that exposes data to another app.

## What is out of scope

- Issues that require a jailbroken device or physical access to an unlocked phone.
- Rate limiting on your own self-hosted backend.
- Findings in third-party services (Supabase, Plaid, Apple) that are not caused by this code.

## Supported versions

Only the latest release on `main` receives security fixes.
