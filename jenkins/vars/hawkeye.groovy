// Hawkeye Autonomous Pentest — Jenkins shared library global step.
//
// Configure this repo as a Global Pipeline Library named 'hawkeye'
// (Manage Jenkins → System → Global Pipeline Libraries, point at this repo).
//
// Jenkinsfile:
//   @Library('hawkeye') _
//   hawkeye(
//     assetId: 'as_9f3c...',          // or apk: 'build/app-release.apk'
//     hawkeyeCredId: 'hawkeye-token', // Jenkins "Secret text" credential = Hawkeye API key
//     scmCredId: 'github-token',      // optional: posts a PR comment on multibranch PR builds
//     repo: 'your-org/your-repo',     // required for PR comments
//     failOn: 'none'                  // none|low|medium|high|critical|any
//   )
def call(Map cfg = [:]) {
  String apiUrl     = cfg.apiUrl     ?: 'https://api.hawkeye.io'
  String assetId    = cfg.assetId    ?: ''
  String apk        = cfg.apk        ?: ''
  String failOn     = cfg.failOn     ?: 'none'
  String clientRef  = cfg.clientRef  ?: 'v1'
  String clientBase = cfg.clientBase ?: 'https://raw.githubusercontent.com/your-org/hawkeye-ci'
  String hawkeyeCred = cfg.hawkeyeCredId ?: 'hawkeye-token'
  String scmCred    = cfg.scmCredId  ?: ''
  String repo       = cfg.repo       ?: ''
  String clientUrl  = "${clientBase}/${clientRef}/scripts"

  catchError(buildResult: 'SUCCESS', stageResult: (failOn == 'none' ? 'SUCCESS' : 'UNSTABLE')) {
    withCredentials([string(credentialsId: hawkeyeCred, variable: 'HAWKEYE_TOKEN')]) {
      withEnv([
        "HAWKEYE_API=${apiUrl}",
        "HAWKEYE_ASSET_ID=${assetId}",
        "HAWKEYE_APK=${apk}",
        "HAWKEYE_FAIL_ON=${failOn}",
        "HAWKEYE_REF=${env.GIT_COMMIT ?: ''}",
        "CLIENT_URL=${clientUrl}",
      ]) {
        sh '''
          set -euo pipefail
          mkdir -p .hawkeye
          curl -fsSL "$CLIENT_URL/hawkeye-core.sh" -o .hawkeye/core.sh
          curl -fsSL "$CLIENT_URL/gate.sh"         -o .hawkeye/gate.sh
          chmod +x .hawkeye/*.sh
          bash .hawkeye/core.sh
        '''
        archiveArtifacts artifacts: 'hawkeye-report.md,hawkeye-findings.json', allowEmptyArchive: true

        // Post a PR comment on multibranch PR builds (CHANGE_ID set by the SCM plugin).
        if (env.CHANGE_ID && scmCred && repo) {
          withCredentials([string(credentialsId: scmCred, variable: 'GITHUB_TOKEN')]) {
            withEnv(["HAWKEYE_PR=${env.CHANGE_ID}", "GITHUB_REPOSITORY=${repo}"]) {
              sh '''
                curl -fsSL "$CLIENT_URL/post-github.sh" -o .hawkeye/post-github.sh
                bash .hawkeye/post-github.sh hawkeye-report.md || true
              '''
            }
          }
        }

        // Severity gate (no-op when failOn=none).
        sh '''
          export HAWKEYE_FINDINGS_COUNT="$(jq '(.findings // []) | length' hawkeye-findings.json)"
          export HAWKEYE_MAX_SEVERITY="$(jq -r 'def r:{info:0,low:1,medium:2,high:3,critical:4}[(.|ascii_downcase)]//0; ((.findings//[])|map((.severity//"info")|r)|max//0) as $m|["info","low","medium","high","critical"][$m]' hawkeye-findings.json)"
          bash .hawkeye/gate.sh
        '''
      }
    }
  }
}
