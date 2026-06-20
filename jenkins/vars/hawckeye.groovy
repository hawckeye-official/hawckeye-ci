// Hawckeye — Jenkins shared library global step. Run AFTER a deploy to a test env.
// Results go to your dashboard, Linear, and email — not the PR.
//
// Configure this repo as a Global Pipeline Library named 'hawckeye', then:
//   @Library('hawckeye') _
//   hawckeye(
//     environmentUrl: 'https://staging.my-app.com',  // or assetId / apk
//     scans: 'security,qa,friction',
//     hawkeyeCredId: 'hawckeye-token'                 // Secret text = Hawckeye API key
//   )
def call(Map cfg = [:]) {
  String apiUrl     = cfg.apiUrl     ?: 'https://api.hawckeye.com'
  String envUrl     = cfg.environmentUrl ?: ''
  String assetId    = cfg.assetId    ?: ''
  String apk        = cfg.apk        ?: ''
  String scans      = cfg.scans      ?: 'security,qa,friction'
  String waitFor    = (cfg.wait ?: 'false').toString()
  String clientRef  = cfg.clientRef  ?: 'v1'
  String clientBase = cfg.clientBase ?: 'https://raw.githubusercontent.com/hawckeye-official/hawckeye-ci'
  String hawkeyeCred = cfg.hawkeyeCredId ?: 'hawckeye-token'
  String clientUrl  = "${clientBase}/${clientRef}/scripts"

  withCredentials([string(credentialsId: hawkeyeCred, variable: 'HAWKEYE_TOKEN')]) {
    withEnv([
      "HAWKEYE_API=${apiUrl}",
      "HAWKEYE_ENVIRONMENT_URL=${envUrl}",
      "HAWKEYE_ASSET_ID=${assetId}",
      "HAWKEYE_APK=${apk}",
      "HAWKEYE_SCANS=${scans}",
      "HAWKEYE_WAIT=${waitFor}",
      "HAWKEYE_REF=${env.GIT_COMMIT ?: ''}",
      "CLIENT_URL=${clientUrl}",
    ]) {
      sh '''
        set -euo pipefail
        mkdir -p .hawkeye
        curl -fsSL "$CLIENT_URL/hawkeye-core.sh" -o .hawkeye/core.sh
        chmod +x .hawkeye/core.sh
        bash .hawkeye/core.sh
      '''
      archiveArtifacts artifacts: 'hawkeye-scan-id.txt', allowEmptyArchive: true
    }
  }
}
