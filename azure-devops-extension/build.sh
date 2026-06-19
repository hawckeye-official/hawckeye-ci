#!/usr/bin/env bash
# Bundle the shared client scripts into the task folder and package the extension.
# Prereq: npm i -g tfx-cli
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/task/scripts"
cp "$here/../scripts/hawkeye-core.sh" \
   "$here/../scripts/post-azure.sh" \
   "$here/../scripts/gate.sh" \
   "$here/task/scripts/"
echo "bundled scripts -> task/scripts"
command -v tfx >/dev/null || { echo "install tfx-cli: npm i -g tfx-cli" >&2; exit 1; }
tfx extension create --manifest-globs "$here/vss-extension.json" --output-path "$here/dist"
echo "Set a real publisher id and a fresh task GUID before publishing."
