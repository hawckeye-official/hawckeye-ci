#!/usr/bin/env node
// Azure DevOps task entry. Maps task inputs (INPUT_*) to HAWKEYE_* env and runs
// the bundled bash client (fire-and-forget). Requires a Linux agent with bash/curl/jq.
// build.sh copies ../../scripts/* into ./scripts before packaging with tfx.
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');

const inp = (n, d = '') => process.env['INPUT_' + n.toUpperCase()] || d;

const env = Object.assign({}, process.env, {
  HAWKEYE_API: inp('apiUrl', 'https://api.hawckeye.com'),
  HAWKEYE_TOKEN: inp('token'),
  HAWKEYE_ENVIRONMENT_URL: inp('environmentUrl'),
  HAWKEYE_ASSET_ID: inp('assetId'),
  HAWKEYE_APK: inp('apk'),
  HAWKEYE_SCANS: inp('scans', 'security,qa,friction'),
  HAWKEYE_WAIT: inp('wait', 'false'),
  HAWKEYE_WAIT_FOR_URL: inp('waitForUrl', 'false'),
  HAWKEYE_EXPECTED_REF: inp('expectedRef') || (process.env.BUILD_SOURCEVERSION || ''),
  HAWKEYE_VERSION_PATH: inp('versionPath'),
  HAWKEYE_REF: process.env.BUILD_SOURCEVERSION || '',
});

const r = spawnSync('bash', [path.join(__dirname, 'scripts', 'hawkeye-core.sh')], { stdio: 'inherit', env });
process.exit(r.status === null ? 1 : r.status);
