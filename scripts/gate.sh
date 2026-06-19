#!/usr/bin/env bash
# Optional severity gate. Default fail-on=none keeps the build non-blocking.
# Runs AFTER the comment is posted so results always reach the PR/MR.
# Portable: avoids bash-4 associative arrays (macOS ships bash 3.2).
set -euo pipefail

fail_on="${HAWKEYE_FAIL_ON:-none}"
[ "$fail_on" = "none" ] && exit 0

count="${HAWKEYE_FINDINGS_COUNT:-0}"
max="${HAWKEYE_MAX_SEVERITY:-info}"

rank() {
  case "$1" in
    info) echo 0 ;; low) echo 1 ;; medium) echo 2 ;;
    high) echo 3 ;; critical) echo 4 ;; *) echo -1 ;;
  esac
}

if [ "$fail_on" = "any" ]; then
  [ "$count" -gt 0 ] && { echo "hawkeye: failing — $count finding(s)"; exit 1; }
  exit 0
fi

thr="$(rank "$fail_on")"
cur="$(rank "$max")"
[ "$thr" -lt 0 ] && { echo "hawkeye: unknown fail-on '$fail_on'; not gating"; exit 0; }

if [ "$count" -gt 0 ] && [ "$cur" -ge "$thr" ]; then
  echo "hawkeye: failing — max severity '$max' >= threshold '$fail_on'"
  exit 1
fi
echo "hawkeye: gate passed (max '$max' < '$fail_on')"
exit 0
