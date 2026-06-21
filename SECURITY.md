# Security

## Reporting a vulnerability

Email **mohab@hawckeye.com**. Please do not open public issues for security
reports. We aim to acknowledge within 2 business days.

## What runs in your pipeline

This repository contains only the trigger client (`scripts/`, `action.yml`,
`templates/scan.yml`). It is auditable in full and contains no scanning logic,
credentials, or obfuscated code. See [PRIVACY.md](./PRIVACY.md) for the exact
network calls it makes.

## Tokens & scopes

- `HAWKEYE_API_KEY` — your Hawckeye API key. Store it as a masked CI secret. It is
  scoped to **your** authorized assets only.
- `GITHUB_TOKEN` / `GITLAB_TOKEN` — used by the client to post the report
  comment. Minimum scopes: GitHub `pull-requests: write`; GitLab `api` (for the
  MR note). Hawckeye never receives these tokens.

## Authorization model

Scans only run against targets you pre-registered as authorized assets, tied to
your API key. Off-allowlist targets are rejected server-side (`403`). This is
the contractual + technical guardrail for autonomous testing.

## Pinning

Pin to a released major tag (`@v1`) so you only run reviewed code. Each release
is tagged; `v1` floats to the latest reviewed `v1.x.y`.
