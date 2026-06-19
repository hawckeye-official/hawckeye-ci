#!/usr/bin/env node
// Azure DevOps task entry. Maps task inputs (INPUT_*) to HAWKEYE_* env and runs
// the bundled bash client. Requires a Linux agent with bash/curl/jq.
// build.sh copies ../../scripts/* into ./scripts before packaging with tfx.
'use strict';
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const inp = (n, d = '') => process.env['INPUT_' + n.toUpperCase()] || d;
const failOn = inp('failOn', 'none');

const env = Object.assign({}, process.env, {
  HAWKEYE_API: inp('apiUrl', 'https://api.hawckeye.io'),
  HAWKEYE_TOKEN: inp('token'),
  HAWKEYE_ASSET_ID: inp('assetId'),
  HAWKEYE_APK: inp('apk'),
  HAWKEYE_WAIT: inp('wait', 'true'),
  HAWKEYE_TIMEOUT: inp('timeout', '1800'),
  HAWKEYE_FAIL_ON: failOn,
  HAWKEYE_REF: process.env.BUILD_SOURCEVERSION || '',
});

const dir = path.join(__dirname, 'scripts');
const run = (script, args = []) => {
  const r = spawnSync('bash', [path.join(dir, script), ...args], { stdio: 'inherit', env });
  return r.status === null ? 1 : r.status;
};

let code = run('hawkeye-core.sh');
run('post-azure.sh', ['hawkeye-report.md']); // best-effort comment

if (failOn !== 'none') {
  let count = 0, maxsev = 'info';
  try {
    const f = (JSON.parse(fs.readFileSync('hawkeye-findings.json', 'utf8')).findings) || [];
    const rank = { info: 0, low: 1, medium: 2, high: 3, critical: 4 };
    count = f.length;
    const m = f.reduce((a, x) => Math.max(a, rank[(x.severity || 'info').toLowerCase()] || 0), 0);
    maxsev = ['info', 'low', 'medium', 'high', 'critical'][m];
  } catch (_) { /* no findings file */ }
  env.HAWKEYE_FINDINGS_COUNT = String(count);
  env.HAWKEYE_MAX_SEVERITY = maxsev;
  const g = run('gate.sh');
  if (g !== 0) code = g;
}

process.exit(code);
