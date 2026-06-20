#!/usr/bin/env bash
# Hawckeye CI — core trigger client (engine-free).
#
# Triggered AFTER a deploy to a test/staging environment. Starts a Hawckeye scan
# (security / qa / friction) against an AUTHORIZED target and returns immediately.
# Results are delivered SERVER-SIDE on completion (dashboard always; Linear + email
# per the asset's config) — NOT back to this job or a PR. No scanning logic here.
#
# Required env:
#   HAWKEYE_TOKEN              Hawckeye API key
#   HAWKEYE_ASSET_ID           the verified, authorized asset to scan (REQUIRED) —
#                              the engine rejects anything outside it (403)
# Optional refinements (must fall WITHIN the asset; cannot pick a new target):
#   HAWKEYE_ENVIRONMENT_URL    specific deployed URL within the asset's verified hosts
#   HAWKEYE_APK                path to an APK build (must match the asset package/signature)
# Optional env:
#   HAWKEYE_SCANS         comma list of suites: security,qa,friction (default all)
#   HAWKEYE_API           API base url (default https://api.hawckeye.com)
#   HAWKEYE_REF           commit sha / build id for traceability
#   HAWKEYE_METADATA      JSON object of build context (branch, env, actor, deploy url)
#   HAWKEYE_WAIT          true|false (default false = fire-and-forget)
#   HAWKEYE_TIMEOUT       seconds to wait when WAIT=true (default 1800)
#   HAWKEYE_POLL_INTERVAL seconds between polls (default 15)
#   HAWKEYE_OUTPUT_DIR    where to write the scan id (default .)
#   Readiness gate (web only — waits until the deploy is live before scanning):
#   HAWKEYE_WAIT_FOR_URL  true|false (default false)
#   HAWKEYE_EXPECTED_REF  commit sha the env must report (via VERSION_PATH) before scanning
#   HAWKEYE_VERSION_PATH  path returning the deployed sha, e.g. /version (health-check only if unset)
#   HAWKEYE_READY_TIMEOUT seconds to wait for readiness (default 600)
#   HAWKEYE_READY_INTERVAL seconds between readiness polls (default 15)
set -euo pipefail

: "${HAWKEYE_API:=https://api.hawckeye.com}"
: "${HAWKEYE_SCANS:=security,qa,friction}"
: "${HAWKEYE_WAIT:=false}"
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
      -H "Content-Type: application/json" -d "$body"
  else
    curl -fsS -X "$method" "$HAWKEYE_API$path" \
      -H "Authorization: Bearer $HAWKEYE_TOKEN"
  fi
}

mkdir -p "$HAWKEYE_OUTPUT_DIR"

# --- Readiness gate: wait until the deploy is live (and serving the right build) ---
# Solves "deploy takes N minutes" without a magic timer — works on every platform.
if [ "${HAWKEYE_WAIT_FOR_URL:-false}" = "true" ]; then
  url="${HAWKEYE_ENVIRONMENT_URL:-}"
  [ -n "$url" ] || die "HAWKEYE_WAIT_FOR_URL=true requires HAWKEYE_ENVIRONMENT_URL"
  : "${HAWKEYE_READY_TIMEOUT:=600}"
  : "${HAWKEYE_READY_INTERVAL:=15}"
  want="${HAWKEYE_EXPECTED_REF:-}"
  vpath="${HAWKEYE_VERSION_PATH:-}"
  short="$(printf '%s' "$want" | cut -c1-7)"
  echo "hawkeye: waiting for $url to be ready${want:+ at ref ${short}}"
  rdeadline=$(( $(date +%s) + HAWKEYE_READY_TIMEOUT ))
  while :; do
    if [ -n "$want" ] && [ -n "$vpath" ]; then
      got="$(curl -fsS --max-time 10 "${url%/}${vpath}" 2>/dev/null || true)"
      case "$got" in
        *"$want"*|*"$short"*) echo "hawkeye: env is serving ${short}"; break ;;
      esac
      last="version='${got:-<no response>}'"
    else
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo 000)"
      case "$code" in 2??|3??) echo "hawkeye: env healthy (HTTP $code)"; break ;; esac
      last="HTTP $code"
    fi
    [ "$(date +%s)" -lt "$rdeadline" ] || die "env not ready after ${HAWKEYE_READY_TIMEOUT}s (last: ${last:-unknown})"
    echo "hawkeye: not ready (${last:-...}); retrying in ${HAWKEYE_READY_INTERVAL}s"
    sleep "$HAWKEYE_READY_INTERVAL"
  done
fi

# --- Common fields: scan suites + ref + build metadata ---------------------
base="$(jq -nc \
  --arg scans "$HAWKEYE_SCANS" \
  --arg ref "${HAWKEYE_REF:-}" \
  --argjson meta "${HAWKEYE_METADATA:-null}" '
  {scans: ($scans | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0)))}
  + (if $ref  == ""   then {} else {ref: $ref}       end)
  + (if $meta == null then {} else {metadata: $meta} end)')"

# --- Target: asset_id is REQUIRED (the verified authorization boundary). ---
# environment_url / apk only refine WHICH instance within that asset is scanned;
# the engine rejects anything outside the asset with 403. CI cannot pick an
# arbitrary target.
[ -n "${HAWKEYE_ASSET_ID:-}" ] || die "HAWKEYE_ASSET_ID is required — the authorized, verified asset to scan. environment-url/apk only refine it."
scan_body="$(echo "$base" | jq -c --arg a "$HAWKEYE_ASSET_ID" '. + {asset_id:$a}')"

if [ -n "${HAWKEYE_APK:-}" ]; then
  [ -f "$HAWKEYE_APK" ] || die "APK not found: $HAWKEYE_APK"
  echo "hawkeye: requesting upload slot"
  up_json="$(api POST /v1/uploads '{"kind":"apk"}')"
  put_url="$(echo "$up_json" | jq -r '.put_url // empty')"
  upload_id="$(echo "$up_json" | jq -r '.id // empty')"
  [ -n "$put_url" ] || die "no upload URL returned: $up_json"
  echo "hawkeye: uploading $HAWKEYE_APK"
  curl -fsS --upload-file "$HAWKEYE_APK" "$put_url" >/dev/null
  scan_body="$(echo "$scan_body" | jq -c --arg u "$upload_id" '. + {upload_id:$u}')"
fi
if [ -n "${HAWKEYE_ENVIRONMENT_URL:-}" ]; then
  scan_body="$(echo "$scan_body" | jq -c --arg e "$HAWKEYE_ENVIRONMENT_URL" '. + {environment_url:$e}')"
fi

# --- Start the scan (fire-and-forget) --------------------------------------
echo "hawkeye: starting scan [$HAWKEYE_SCANS]"
start_json="$(api POST /v1/scans "$scan_body")"
scan_id="$(echo "$start_json" | jq -r '.id // empty')"
[ -n "$scan_id" ] || die "scan did not start: $start_json"
dash="$(echo "$start_json" | jq -r '.dashboard_url // empty')"
echo "hawkeye: scan_id=$scan_id"
[ -n "$dash" ] && echo "hawkeye: dashboard $dash"
echo "$scan_id" > "$HAWKEYE_OUTPUT_DIR/hawkeye-scan-id.txt"

# --- Optionally wait so the deploy pipeline reflects scan status -----------
status="queued"; cur=""
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
  [ -n "$cur" ] && echo "$cur" | jq -r '.summary // {} | to_entries | map("\(.key)=\(.value)") | join(" ")' \
    | sed -e 's/^/hawkeye: summary /' -e '/summary $/d' || true
fi

# --- Emit outputs (GitHub Actions reads $GITHUB_OUTPUT) --------------------
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "scan_id=$scan_id"
    echo "status=$status"
    [ -n "$dash" ] && echo "dashboard_url=$dash"
  } >> "$GITHUB_OUTPUT"
fi

echo "hawkeye: triggered — results will arrive in the dashboard, Linear, and email."
