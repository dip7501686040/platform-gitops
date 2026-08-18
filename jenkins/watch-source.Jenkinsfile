// Polls ai-notification-system's main branch. When it moves, diffs the new
// HEAD against the last commit this job actually processed and triggers
// build-<service> only for the apps/<service>/ directories that changed —
// one at a time (wait: true in a plain loop, not `parallel`), and not at
// all for services nothing touched.
//
// Why a marker file instead of Jenkins' built-in GIT_PREVIOUS_SUCCESSFUL_
// COMMIT: that's only populated for a job's *primary* SCM checkout, and
// this job's primary SCM is platform-gitops (to fetch this Jenkinsfile) —
// the source repo is a secondary checkout, same as in jenkins/Jenkinsfile,
// so its commit history has to be tracked by hand.

def SOURCE_REPO_URL = 'https://github.com/dip7501686040/ai-notification-system.git'
def SOURCE_BRANCH = 'main'
def MARKER_FILE = '/var/lib/jenkins/watch-source-last-commit.txt'

def KNOWN_SERVICES = [
  'identity-service', 'tenant-service', 'event-service', 'rule-engine-service',
  'template-service', 'notification-service', 'channel-service', 'ai-service',
  'analytics-service', 'audit-service', 'api-gateway', 'web', 'prediction-service',
]

pipeline {
  agent any

  // Only takes effect after this Jenkinsfile has run once (a declarative
  // triggers{} block is parsed from the *previous* run, not the one about
  // to happen) — click "Build Now" once after this job is first seeded to
  // register the schedule; every run after that is self-scheduling.
  triggers {
    cron('H/2 * * * *')
  }

  parameters {
    choice(name: 'ENVIRONMENT', choices: ['local', 'prod'], description: 'Which environment build-<service> should deploy to')
  }

  stages {
    stage('Checkout source repo') {
      steps {
        dir('src') {
          git branch: SOURCE_BRANCH, url: SOURCE_REPO_URL
        }
      }
    }

    stage('Diff and build only what changed') {
      steps {
        script {
          def newSha = sh(script: 'git -C src rev-parse HEAD', returnStdout: true).trim()
          def lastSha = fileExists(MARKER_FILE) ? readFile(MARKER_FILE).trim() : ''

          if (lastSha == newSha) {
            echo "No new commits on ${SOURCE_BRANCH} (still at ${newSha}) — nothing to do."
            return
          }

          if (lastSha == '') {
            echo "First run — no baseline yet. Recording ${newSha} without building anything."
            writeFile file: MARKER_FILE, text: newSha
            return
          }

          def diffOutput = sh(script: "git -C src diff --name-only ${lastSha} ${newSha}", returnStdout: true).trim()
          def changed = diffOutput ? diffOutput.split('\n') as List : []

          def changedServices = KNOWN_SERVICES.findAll { svc ->
            changed.any { it.startsWith("apps/${svc}/") }
          }

          if (changedServices.isEmpty()) {
            echo "Commits ${lastSha}..${newSha} touched no apps/<service>/ directory — nothing to build."
          } else {
            echo "Changed services: ${changedServices.join(', ')} — building one at a time, not in parallel."
            for (svc in changedServices) {
              echo "Building ${svc}..."
              build job: "build-${svc}", wait: true, parameters: [
                string(name: 'ENVIRONMENT', value: params.ENVIRONMENT),
                string(name: 'SERVICES', value: svc),
              ]
            }
          }

          // Recorded even when changedServices is empty (e.g. a docs-only
          // commit) so the next poll diffs from here, not the same stale
          // baseline forever.
          writeFile file: MARKER_FILE, text: newSha
        }
      }
    }
  }
}
