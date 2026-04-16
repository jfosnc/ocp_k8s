#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

application_exists() {
  spoke -n "$GITOPS_NAMESPACE" get application "$APPROVED_APP_NAME" >/dev/null 2>&1
}

require_context
require_file "$APPROVED_APPLICATION_MANIFEST"

log "Applying the compliant Argo CD Application"
spoke apply -f "$APPROVED_APPLICATION_MANIFEST"

wait_for "Application $APPROVED_APP_NAME to exist" 120 application_exists
wait_for "Application $APPROVED_APP_NAME to become Healthy and Synced" 600 application_ready "$APPROVED_APP_NAME"

spoke -n "$GITOPS_NAMESPACE" get application "$APPROVED_APP_NAME"
spoke -n "$DEMO_NAMESPACE" get deployment "$APPROVED_APP_NAME"

