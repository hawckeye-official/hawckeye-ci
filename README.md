# Hawkeye Autonomous Pentest — CI integration

Trigger a [Hawkeye](https://hawkeye.io) autonomous pentest against an **authorized
URL or APK** from your CI, and get findings posted back to the PR/MR. Non-blocking
by default.

This repository is the **engine-free trigger client**. It contains no scanning
logic — it only calls the hosted Hawkeye API, so it is safe to run on any runner.
The pentest engine runs entirely on Hawkeye's infrastructure.

## How it works

```
Your CI ──POST /v1/scans {asset_id|apk}──▶ Hawkeye API ──▶ engine runs the pentest
   ▲                                                              │
   └──────────────── sticky PR/MR comment ◀── poll /findings ─────┘
```

You can only scan targets pre-registered as **authorized assets** during
onboarding. The API rejects anything not on your allowlist.

## Setup (once)

1. Get a **Hawkeye API key** → store it as a CI secret named `HAWKEYE_TOKEN`.
2. Register your target (URL or mobile app) → you receive an **`asset-id`**.
3. Add the snippet below.

## GitHub Actions

```yaml
# .github/workflows/hawkeye.yml
on: [pull_request]
permissions: { pull-requests: write, contents: read }
jobs:
  hawkeye:
    runs-on: ubuntu-latest
    steps:
      - uses: your-org/hawkeye-ci@v1
        with:
          token: ${{ secrets.HAWKEYE_TOKEN }}
          asset-id: "as_9f3c..."   # or  apk: app-release.apk
```

| Input | Default | Notes |
|---|---|---|
| `token` | — | **required**, Hawkeye API key |
| `asset-id` / `apk` | — | one is required |
| `api-url` | `https://api.hawkeye.io` | |
| `wait` | `true` | wait for the scan to finish |
| `timeout` | `1800` | seconds |
| `fail-on` | `none` | `none\|low\|medium\|high\|critical\|any` |
| `comment` | `true` | post sticky PR comment |

## GitLab CI

```yaml
# .gitlab-ci.yml — set HAWKEYE_TOKEN and GITLAB_TOKEN (api scope) as CI variables
include:
  - component: $CI_SERVER_FQDN/your-org/hawkeye-ci/scan@1
    inputs:
      asset-id: "as_9f3c..."   # or  apk: "build/app-release.apk"
```

> `GITLAB_TOKEN` needs `api` scope to post the MR note (the default
> `CI_JOB_TOKEN` cannot create notes).

## Azure DevOps

Quickest path — a steps template (Linux agent; set secret var `HAWKEYE_TOKEN`):

```yaml
resources:
  repositories:
    - repository: hawkeye
      type: github
      name: your-org/hawkeye-ci
      endpoint: your-github-service-connection
      ref: refs/tags/v1
steps:
  - template: azure/hawkeye-steps.yml@hawkeye
    parameters:
      assetId: "as_9f3c..."   # or apk: "build/app-release.apk"
```

A Marketplace **task extension** (`Hawkeye@1`) is scaffolded under
`azure-devops-extension/` — run `build.sh` (needs `tfx-cli`) to package it.
Enable *Allow scripts to access the OAuth token* so PR comments can post.

## Jenkins

Add this repo as a Global Pipeline Library named `hawkeye`, then:

```groovy
@Library('hawkeye') _
hawkeye(
  assetId: 'as_9f3c...',          // or apk: 'build/app-release.apk'
  hawkeyeCredId: 'hawkeye-token', // Secret text credential = Hawkeye API key
  scmCredId: 'github-token',      // optional: PR comments on multibranch builds
  repo: 'your-org/your-repo'
)
```

## How the wrappers share one core

Every platform runs the same engine-free scripts under `scripts/`
(`hawkeye-core.sh` → `post-<platform>.sh` → `gate.sh`). GitHub bundles them via
the action; GitLab/Azure/Jenkins fetch them from the pinned release tag. One
codebase, four platforms.

## Publishing (maintainers)

- **GitHub Marketplace** — tag `vX.Y.Z`; the `release` workflow floats `v1`. Then
  edit the GitHub Release and tick *“Publish this Action to the GitHub Marketplace.”*
  Requires `action.yml` with `branding` (present) and a public repo.
- **GitLab CI/CD Catalog** — enable *Settings → General → CI/CD Catalog resource*,
  then push a semver tag; `.gitlab-ci.yml` creates the catalog release.

## License

MIT
