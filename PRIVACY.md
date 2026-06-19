# What this client sends

This GitHub Action / GitLab Component is an **engine-free trigger client**. It
performs no scanning. When it runs in your pipeline it makes only these calls:

| Destination | Data sent | Why |
|---|---|---|
| `POST {api-url}/v1/scans` | your `asset-id` (or an uploaded APK), the commit sha | start an authorized scan |
| `GET  {api-url}/v1/scans/{id}` | — | poll status |
| `GET  {api-url}/v1/scans/{id}/findings` | — | retrieve results |
| `POST {api-url}/v1/uploads` + presigned PUT | the APK file you point it at | APK targets only |
| Your SCM API (GitHub/GitLab) | the findings report text | post the PR/MR comment, using **your** CI token |

What it does **not** do:

- It does **not** send your source code, repository contents, or secrets to Hawkeye.
- It does **not** grant Hawkeye inbound access to your repo — comments are posted
  by the client using your own `GITHUB_TOKEN` / `GITLAB_TOKEN`.
- It targets **only** assets you pre-registered and authorized. The API rejects
  anything not on your allowlist.

You can read every line that runs: see `scripts/` in this repository.

Questions: security@hawkeye.io
