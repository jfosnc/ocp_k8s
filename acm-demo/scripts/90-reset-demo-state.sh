#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

application_absent() {
  local app_name="$1"
  ! spoke -n "$GITOPS_NAMESPACE" get application "$app_name" >/dev/null 2>&1
}

deployment_absent() {
  local deployment_name="$1"
  ! spoke -n "$DEMO_NAMESPACE" get deployment "$deployment_name" >/dev/null 2>&1
}

require_context

log "Resetting the ACM demo environment to a clean, re-entrant baseline"
"$SCRIPT_DIR/01-verify-cluster-access.sh"
"$SCRIPT_DIR/04-confirm-sno2-managed.sh"
"$SCRIPT_DIR/03-install-gitops.sh"
"$SCRIPT_DIR/05-set-enforcement-label.sh" enable
"$SCRIPT_DIR/06-apply-governance.sh"
"$SCRIPT_DIR/07-verify-governance.sh"
"$SCRIPT_DIR/08-apply-demo-gitops-rbac.sh"

log "Removing the demo Argo CD Applications"
spoke -n "$GITOPS_NAMESPACE" delete application "$APPROVED_APP_NAME" "$VIOLATING_APP_NAME" --ignore-not-found
wait_for "Application $APPROVED_APP_NAME to be absent" 300 application_absent "$APPROVED_APP_NAME"
wait_for "Application $VIOLATING_APP_NAME to be absent" 300 application_absent "$VIOLATING_APP_NAME"

log "Removing demo workloads that may have been left behind"
spoke -n "$DEMO_NAMESPACE" delete deployment "$APPROVED_APP_NAME" "$VIOLATING_APP_NAME" --ignore-not-found
wait_for "Deployment $APPROVED_APP_NAME to be absent" 300 deployment_absent "$APPROVED_APP_NAME"
wait_for "Deployment $VIOLATING_APP_NAME to be absent" 300 deployment_absent "$VIOLATING_APP_NAME"

wait_for "deployment $DRIFT_APP_NAME to exist on $SPOKE_CLUSTER_NAME" 900 drift_demo_present
wait_for "deployment $DRIFT_APP_NAME to reconcile to replicas=1" 900 drift_demo_ready

log "Baseline summary"
hub get managedcluster "$SPOKE_CLUSTER_NAME" --show-labels
hub -n "$POLICY_NAMESPACE" get policy
spoke get validatingadmissionpolicy require-approved-deployment-label
spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME"
spoke -n "$GITOPS_NAMESPACE" get application || true

