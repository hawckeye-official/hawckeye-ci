# API contract

This client targets the **Hawckeye Scan API v1** (data plane). The authoritative
spec lives in the private `hawckeye-api-contract` repo and is the source of truth
the engine implements.

Data-plane endpoints this client depends on:

- `POST /v1/scans` — start a scan `{asset_id|upload_id, ref}` → `{id, status}`
- `GET  /v1/scans/{id}` — status → `{status}` (`queued|running|completed|failed|error|cancelled`)
- `GET  /v1/scans/{id}/findings` — `{findings:[{severity,title,location}]}`
- `POST /v1/uploads` — `{kind:"apk"}` → `{id, put_url}` (APK targets)

Breaking changes are gated behind a new major version + a coordinated client
release. Maintainers: run `contract-check.sh` from `hawckeye-api-contract`
against this repo in CI to detect drift.
