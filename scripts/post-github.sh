#!/usr/bin/env bash
# Posts/updates a single sticky PR comment with the Hawkeye report.
# Uses the caller's GITHUB_TOKEN — Hawkeye never needs inbound repo access.
set -euo pipefail

report="${1:-hawkeye-report.md}"
[ -f "$report" ] || { echo "hawkeye: no report file ($report); skipping comment"; exit 0; }
: "${GITHUB_TOKEN:?GITHUB_TOKEN required to comment}"

api="${GITHUB_API_URL:-https://api.github.com}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"

pr=""
if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
  pr="$(jq -r '.pull_request.number // .issue.number // empty' "$GITHUB_EVENT_PATH")"
fi
[ -n "$pr" ] || { echo "hawkeye: not a PR context; skipping comment"; exit 0; }

marker="<!-- hawkeye-report -->"
payload="$(jq -nc --rawfile b "$report" '{body:$b}')"

existing="$(curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" \
  "$api/repos/$repo/issues/$pr/comments?per_page=100" \
  | jq -r --arg m "$marker" 'map(select(.body|contains($m)))[0].id // empty')"

if [ -n "$existing" ]; then
  curl -fsS -X PATCH -H "Authorization: Bearer $GITHUB_TOKEN" \
    "$api/repos/$repo/issues/comments/$existing" -d "$payload" >/dev/null
  echo "hawkeye: updated PR comment $existing"
else
  curl -fsS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
    "$api/repos/$repo/issues/$pr/comments" -d "$payload" >/dev/null
  echo "hawkeye: created PR comment"
fi
