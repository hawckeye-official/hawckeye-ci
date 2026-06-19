#!/usr/bin/env bash
# Posts/updates a single sticky PR thread on Azure DevOps with the Hawkeye report.
# Requires SYSTEM_ACCESSTOKEN (enable "Allow scripts to access the OAuth token"
# on the job, and grant the build service "Contribute to pull requests").
set -euo pipefail

report="${1:-hawkeye-report.md}"
[ -f "$report" ] || { echo "hawkeye: no report file ($report); skipping comment"; exit 0; }

tok="${SYSTEM_ACCESSTOKEN:-}"
[ -n "$tok" ] || { echo "hawkeye: no SYSTEM_ACCESSTOKEN; skipping comment"; exit 0; }
col="${SYSTEM_COLLECTIONURI:?SYSTEM_COLLECTIONURI required}"
proj="${SYSTEM_TEAMPROJECT:?SYSTEM_TEAMPROJECT required}"
repo="${BUILD_REPOSITORY_ID:?BUILD_REPOSITORY_ID required}"
pr="${SYSTEM_PULLREQUEST_PULLREQUESTID:-}"
[ -n "$pr" ] || { echo "hawkeye: not a PR build; skipping comment"; exit 0; }

base="${col%/}/$proj/_apis/git/repositories/$repo/pullRequests/$pr/threads"
ver="api-version=7.1"
marker="<!-- hawkeye-report -->"
auth=(-H "Authorization: Bearer $tok")

list="$(curl -fsS "${auth[@]}" "$base?$ver")"
thread="$(echo "$list" | jq -r --arg m "$marker" \
  '.value[] | select((.comments[0].content // "")|contains($m)) | .id' | head -n1)"
cmt="$(echo "$list" | jq -r --arg m "$marker" \
  '.value[] | select((.comments[0].content // "")|contains($m)) | .comments[0].id' | head -n1)"

if [ -n "$thread" ] && [ "$thread" != "null" ]; then
  jq -nc --rawfile c "$report" '{content:$c}' \
    | curl -fsS -X PATCH "${auth[@]}" -H "Content-Type: application/json" \
        "$base/$thread/comments/$cmt?$ver" -d @- >/dev/null
  echo "hawkeye: updated PR thread $thread"
else
  jq -nc --rawfile c "$report" '{comments:[{parentCommentId:0,content:$c,commentType:1}],status:1}' \
    | curl -fsS -X POST "${auth[@]}" -H "Content-Type: application/json" \
        "$base?$ver" -d @- >/dev/null
  echo "hawkeye: created PR thread"
fi
