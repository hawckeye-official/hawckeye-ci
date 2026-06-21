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
not PR comments.

**Scope is locked to a verified asset — via the API key.** Your `api-key` is scoped to
an asset you proved you own at onboarding (domain via DNS, or app via signing
certificate). CI can pass a specific `environment-url` or `apk`, but only ones **within**
that asset; the API returns `403` for anything else. CI can never point Hawckeye at an
arbitrary URL or app it isn't authorized to test.

Three suites, pick any subset via `scans`: **security**, **qa**, **friction**.

## Setup (once)

1. Onboard your target (**verify ownership**) + connect **Linear** / notification emails.
2. Get your **Hawckeye API key** (scoped to that asset) → store it as a CI secret named `HAWKEYE_API_KEY`.
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
          api-key: ${{ secrets.HAWKEYE_API_KEY }}
          environment-url: "https://staging.my-app.com"   # must be within the key's asset
          scans: security,qa,friction
```

| Input | Default | Notes |
|---|---|---|
| `api-key` | — | **required**, scoped to your verified asset |
| `environment-url` / `apk` | — | the deployed URL / APK to scan; must be **within** the key's asset |
| `asset-id` | — | optional; only for an account-level key spanning multiple assets |
| `scans` | `security,qa,friction` | comma list of suites |
| `api-url` | `https://api.hawckeye.com` | |
| `wait` | `false` | fire-and-forget; set `true` to make the job reflect status |
| `timeout` | `1800` | seconds (only when `wait=true`) |
| `wait-for-url` | `false` | poll `environment-url` until live before scanning |
| `expected-ref` | `${{ github.sha }}` | env must report this sha (via `version-path`) before scanning |
| `version-path` | — | path returning the deployed sha, e.g. `/version` (health-check only if unset) |
| `ready-timeout` | `600` | max seconds to wait for the env to become ready |

See `examples/github-post-deploy.yml` (readiness gate) and
`examples/github-deployment-status.yml` (native deploy-success trigger).

### Handling slow deploys

Deploys take time (often minutes) and finish asynchronously, so don't guess a timer.
Either:
- **GitHub only:** trigger `on: deployment_status` (state `success`) — fires the instant
  the env is live and hands you the URL. See the example above.
- **Any platform:** set `wait-for-url: true` (+ `version-path` + `expected-ref`). The
  client polls until the env is healthy **and serving the expected commit**, then scans.
  If it never becomes ready within `ready-timeout`, the step fails. This is the portable
  option — same behavior on GitHub, GitLab, Azure, and Jenkins.

## GitLab CI

```yaml
# .gitlab-ci.yml — set HAWKEYE_API_KEY (masked). Runs on the default branch.
include:
  - component: $CI_SERVER_FQDN/hawckeye-official/hawckeye-ci/scan@1
    inputs:
      environment-url: "https://staging.my-app.com"   # must be within it
```

## Azure DevOps

Steps template (Linux agent; secret var `HAWKEYE_API_KEY`):

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
      environmentUrl: "https://staging.my-app.com"   # must be within it
```

A Marketplace **task extension** (`Hawckeye@1`) is scaffolded under
`azure-devops-extension/` — run `build.sh` (needs `tfx-cli`) to package it.

## Jenkins

Add this repo as a Global Pipeline Library named `hawckeye`, then:

```groovy
@Library('hawckeye') _
hawckeye(
  environmentUrl: 'https://staging.my-app.com', // must be within it (or apk: '...')
  scans: 'security,qa,friction',
  hawkeyeCredId: 'hawckeye-api-key'               // Secret text = Hawckeye API key
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
