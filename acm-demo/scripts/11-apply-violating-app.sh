#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

application_exists() {
  spoke -n "$GITOPS_NAMESPACE" get application "$VIOLATING_APP_NAME" >/dev/null 2>&1
}

application_blocked_or_finished() {
  application_operation_finished "$VIOLATING_APP_NAME" || application_reports_expected_admission_denial "$VIOLATING_APP_NAME"
}

require_context
require_file "$VIOLATING_APPLICATION_MANIFEST"

log "Applying the violating Argo CD Application"
spoke apply -f "$VIOLATING_APPLICATION_MANIFEST"

wait_for "Application $VIOLATING_APP_NAME to exist" 120 application_exists
wait_for "Application $VIOLATING_APP_NAME to show the expected blocked outcome" 180 application_blocked_or_finished

phase="$(spoke -n "$GITOPS_NAMESPACE" get application "$VIOLATING_APP_NAME" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
health_and_sync="$(spoke -n "$GITOPS_NAMESPACE" get application "$VIOLATING_APP_NAME" -o jsonpath='{.status.health.status} {.status.sync.status}' 2>/dev/null || true)"

log "Violating application phase: ${phase:-unknown}"
log "Violating application health/sync: ${health_and_sync:-unknown}"
spoke -n "$GITOPS_NAMESPACE" describe application "$VIOLATING_APP_NAME"

if spoke -n "$DEMO_NAMESPACE" get deployment "$VIOLATING_APP_NAME" >/dev/null 2>&1; then
  warn "Deployment $VIOLATING_APP_NAME exists in $DEMO_NAMESPACE. The admission policy may not be active."
  spoke -n "$DEMO_NAMESPACE" get deployment "$VIOLATING_APP_NAME"
  exit 1
fi

if application_reports_expected_admission_denial "$VIOLATING_APP_NAME"; then
  log "Argo CD is reporting the expected admission-policy denial."
fi

log "No violating deployment was created. This is the expected blocked outcome."
