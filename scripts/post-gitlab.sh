#!/usr/bin/env bash
# Posts/updates a single sticky MR note with the Hawckeye report.
# Prefers GITLAB_TOKEN (project/group access token with `api` scope).
# CI_JOB_TOKEN usually cannot create notes, so set GITLAB_TOKEN as a CI variable.
set -euo pipefail

report="${1:-hawkeye-report.md}"
[ -f "$report" ] || { echo "hawkeye: no report file ($report); skipping note"; exit 0; }

token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
[ -n "$token" ] || { echo "hawkeye: no GitLab token; skipping note"; exit 0; }

api="${CI_API_V4_URL:?CI_API_V4_URL required}"
proj="${CI_PROJECT_ID:?CI_PROJECT_ID required}"
mr="${CI_MERGE_REQUEST_IID:-}"
[ -n "$mr" ] || { echo "hawkeye: not an MR pipeline; skipping note"; exit 0; }

if [ -n "${GITLAB_TOKEN:-}" ]; then hdr=(-H "PRIVATE-TOKEN: $GITLAB_TOKEN")
else hdr=(-H "JOB-TOKEN: $token"); fi

marker="<!-- hawkeye-report -->"
notes_url="$api/projects/$proj/merge_requests/$mr/notes"

existing="$(curl -fsS "${hdr[@]}" "$notes_url?per_page=100" \
  | jq -r --arg m "$marker" 'map(select(.body|contains($m)))[0].id // empty')"

if [ -n "$existing" ]; then
  curl -fsS -X PUT "${hdr[@]}" --data-urlencode "body@$report" \
    "$notes_url/$existing" >/dev/null
  echo "hawkeye: updated MR note $existing"
else
  curl -fsS -X POST "${hdr[@]}" --data-urlencode "body@$report" \
    "$notes_url" >/dev/null
  echo "hawkeye: created MR note"
fi
