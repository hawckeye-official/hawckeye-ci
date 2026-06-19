#!/usr/bin/env bash
# Hawckeye CI — core trigger client (engine-free).
#
# Starts a pentest scan on the hosted Hawckeye API against an AUTHORIZED target
# (a registered URL asset, or an uploaded APK), waits for completion, and writes
# hawkeye-findings.json + hawkeye-report.md. Contains no scanning logic — it only
# calls the API, so it is safe to run on any untrusted CI runner and to open-source.
#
# Required env:
#   HAWKEYE_TOKEN        Hawckeye API key
#   HAWKEYE_ASSET_ID     registered authorized asset id (URL target)   ─┐ one of
#   HAWKEYE_APK          path to an APK artifact to scan               ─┘ these
# Optional env:
#   HAWKEYE_API          API base url        (default https://api.hawckeye.io)
#   HAWKEYE_WAIT         true|false          (default true)
#   HAWKEYE_TIMEOUT      seconds to wait     (default 1800)
#   HAWKEYE_POLL_INTERVAL seconds            (default 15)
#   HAWKEYE_REF          commit sha / build id for traceability
#   HAWKEYE_OUTPUT_DIR   where to write outputs (default .)
set -euo pipefail

: "${HAWKEYE_API:=https://api.hawckeye.io}"
: "${HAWKEYE_WAIT:=true}"
: "${HAWKEYE_TIMEOUT:=1800}"
: "${HAWKEYE_POLL_INTERVAL:=15}"
: "${HAWKEYE_OUTPUT_DIR:=.}"

die()  { echo "hawkeye: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

need curl
need jq
[ -n "${HAWKEYE_TOKEN:-}" ] || die "HAWKEYE_TOKEN is required"

# api METHOD PATH [json-body]
api() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -fsS -X "$method" "$HAWKEYE_API$path" \
      -H "Authorization: Bearer $HAWKEYE_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -fsS -X "$method" "$HAWKEYE_API$path" \
      -H "Authorization: Bearer $HAWKEYE_TOKEN"
  fi
}

mkdir -p "$HAWKEYE_OUTPUT_DIR"

# --- Resolve the scan target (URL asset or APK upload) ---------------------
scan_body=""
if [ -n "${HAWKEYE_APK:-}" ]; then
  [ -f "$HAWKEYE_APK" ] || die "APK not found: $HAWKEYE_APK"
  echo "hawkeye: requesting upload slot"
  up_json="$(api POST /v1/uploads '{"kind":"apk"}')"
  put_url="$(echo "$up_json" | jq -r '.put_url // empty')"
  upload_id="$(echo "$up_json" | jq -r '.id // empty')"
  [ -n "$put_url" ] || die "no upload URL returned: $up_json"
  echo "hawkeye: uploading $HAWKEYE_APK"
  curl -fsS --upload-file "$HAWKEYE_APK" "$put_url" >/dev/null
  scan_body="$(jq -nc --arg u "$upload_id" --arg r "${HAWKEYE_REF:-}" \
    '{upload_id:$u} + (if $r=="" then {} else {ref:$r} end)')"
elif [ -n "${HAWKEYE_ASSET_ID:-}" ]; then
  scan_body="$(jq -nc --arg a "$HAWKEYE_ASSET_ID" --arg r "${HAWKEYE_REF:-}" \
    '{asset_id:$a} + (if $r=="" then {} else {ref:$r} end)')"
else
  die "set HAWKEYE_ASSET_ID (registered URL asset) or HAWKEYE_APK (file path)"
fi

# --- Start the scan --------------------------------------------------------
echo "hawkeye: starting scan"
start_json="$(api POST /v1/scans "$scan_body")"
scan_id="$(echo "$start_json" | jq -r '.id // empty')"
[ -n "$scan_id" ] || die "scan did not start: $start_json"
echo "hawkeye: scan_id=$scan_id"
echo "$scan_id" > "$HAWKEYE_OUTPUT_DIR/hawkeye-scan-id.txt"

# --- Wait for completion (the build itself stays non-blocking) -------------
status="queued"
if [ "$HAWKEYE_WAIT" = "true" ]; then
  deadline=$(( $(date +%s) + HAWKEYE_TIMEOUT ))
  while :; do
    cur="$(api GET "/v1/scans/$scan_id" || true)"
    [ -n "$cur" ] && status="$(echo "$cur" | jq -r '.status // "unknown"')"
    echo "hawkeye: status=$status"
    case "$status" in completed|failed|error|cancelled) break ;; esac
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "hawkeye: wait timeout — scan continues server-side"; break
    fi
    sleep "$HAWKEYE_POLL_INTERVAL"
  done
fi

# --- Fetch findings & build the report -------------------------------------
findings="$(api GET "/v1/scans/$scan_id/findings" || echo '{"findings":[]}')"
echo "$findings" > "$HAWKEYE_OUTPUT_DIR/hawkeye-findings.json"

count="$(echo "$findings" | jq '(.findings // []) | length')"
maxsev="$(echo "$findings" | jq -r '
  def rank: {"info":0,"low":1,"medium":2,"high":3,"critical":4}[(.|ascii_downcase)] // 0;
  ((.findings // []) | map((.severity // "info") | rank) | max // 0) as $m |
  ["info","low","medium","high","critical"][$m]')"

report="$HAWKEYE_OUTPUT_DIR/hawkeye-report.md"
results_url="${HAWKEYE_API%/}/scans/$scan_id"
{
  echo "<!-- hawkeye-report -->"
  echo "## 🦅 Hawckeye Autonomous Pentest"
  echo
  echo "**Scan** \`$scan_id\` · **Status** \`$status\` · **Findings** $count"
  echo
  if [ "$status" != "completed" ]; then
    echo "_Scan is \`$status\`. This comment updates when it finishes._"
  elif [ "$count" = "0" ]; then
    echo "✅ No findings on the authorized target."
  else
    echo "$findings" | jq -r '
      "| Severity | Title | Location |\n|---|---|---|\n" +
      ((.findings // []) | map("| \(.severity//"?") | \(.title//"untitled") | \(.location//"-") |") | join("\n"))'
  fi
  echo
  echo "[View full report]($results_url)"
} > "$report"

# --- Emit outputs (GitHub Actions reads $GITHUB_OUTPUT) --------------------
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "scan_id=$scan_id"
    echo "status=$status"
    echo "findings_count=$count"
    echo "max_severity=$maxsev"
    echo "report_file=$report"
  } >> "$GITHUB_OUTPUT"
fi

echo "hawkeye: done — $count finding(s), max severity $maxsev"
