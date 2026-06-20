# Hawckeye — CI integration

Run [Hawckeye](https://hawckeye.com) — autonomous **security, QA & product-friction**
testing — against an **authorized URL or APK** after you deploy to a test/staging
environment. **Fire-and-forget:** the CI step triggers the scan and returns; results
are delivered to your **dashboard, Linear, and email** — not the PR.

This repository is the **engine-free trigger client**. It contains no scanning
logic — it only calls the hosted Hawckeye API, so it is safe to run on any runner.
The engine runs entirely on Hawckeye's infrastructure.

## How it works

```
deploy to test env ──▶ CI step ──POST /v1/scans {environment_url|apk, scans}──▶ Hawckeye
                                                                                   │
   dashboard (always) + Linear issues + email digest  ◀── engine runs the scan ───┘
```

Why post-deploy, not on the PR? The scans need a **running instance** of your product,
and they run **after merge/deploy** — so findings are tracked work items (Linear),
not PR comments. You can only scan targets pre-registered as **authorized assets**;
the API rejects anything not on your allowlist.

Three suites, pick any subset via `scans`: **security**, **qa**, **friction**.

## Setup (once)

1. Get a **Hawckeye API key** → store it as a CI secret named `HAWKEYE_TOKEN`.
2. Register your target + connect **Linear** / notification emails → you get an asset.
3. Add the snippet below **after your deploy step**.

## GitHub Actions

```yaml
# .github/workflows/hawckeye.yml — run after deploy
on:
  push: { branches: [main] }
jobs:
  hawckeye:
    runs-on: ubuntu-latest
    steps:
      # ...deploy to your test env, exposing its URL...
      - uses: hawckeye-official/hawckeye-ci@v1
        with:
          token: ${{ secrets.HAWKEYE_TOKEN }}
          environment-url: "https://staging.my-app.com"   # or asset-id / apk
          scans: security,qa,friction
```

| Input | Default | Notes |
|---|---|---|
| `token` | — | **required**, Hawckeye API key |
| `environment-url` / `asset-id` / `apk` | — | one is required |
| `scans` | `security,qa,friction` | comma list of suites |
| `api-url` | `https://api.hawckeye.com` | |
| `wait` | `false` | fire-and-forget; set `true` to make the job reflect status |
| `timeout` | `1800` | seconds (only when `wait=true`) |

See `examples/github-post-deploy.yml` for the full deploy→scan job.

## GitLab CI

```yaml
# .gitlab-ci.yml — set HAWKEYE_TOKEN (masked). Runs on the default branch.
include:
  - component: $CI_SERVER_FQDN/hawckeye-official/hawckeye-ci/scan@1
    inputs:
      environment-url: "https://staging.my-app.com"   # or asset-id / apk
```

## Azure DevOps

Steps template (Linux agent; secret var `HAWKEYE_TOKEN`):

```yaml
resources:
  repositories:
    - repository: hawckeye
      type: github
      name: hawckeye-official/hawckeye-ci
      endpoint: your-github-service-connection
      ref: refs/tags/v1
steps:
  - template: azure/hawkeye-steps.yml@hawckeye
    parameters:
      environmentUrl: "https://staging.my-app.com"   # or assetId / apk
```

A Marketplace **task extension** (`Hawckeye@1`) is scaffolded under
`azure-devops-extension/` — run `build.sh` (needs `tfx-cli`) to package it.

## Jenkins

Add this repo as a Global Pipeline Library named `hawckeye`, then:

```groovy
@Library('hawckeye') _
hawckeye(
  environmentUrl: 'https://staging.my-app.com', // or apk: 'build/app-release.apk'
  scans: 'security,qa,friction',
  hawkeyeCredId: 'hawckeye-token'               // Secret text = Hawckeye API key
)
```

## How the wrappers share one core

Every platform runs the same engine-free `scripts/hawkeye-core.sh` (trigger +
fire-and-forget). GitHub bundles it via the action; GitLab/Azure/Jenkins fetch it
from the pinned release tag. One codebase, four platforms.

## Publishing (maintainers)

- **GitHub Marketplace** — tag `vX.Y.Z`; the `release` workflow floats `v1`. Then
  edit the GitHub Release and tick *“Publish this Action to the GitHub Marketplace.”*
- **GitLab CI/CD Catalog** — enable *Settings → General → CI/CD Catalog resource*,
  then push a semver tag; `.gitlab-ci.yml` creates the catalog release.

## License

MIT
