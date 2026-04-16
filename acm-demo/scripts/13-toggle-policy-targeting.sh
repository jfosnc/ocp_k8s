#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

admission_policy_absent() {
  ! admission_policy_present
}

drift_demo_absent() {
  ! drift_demo_present
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [disable|enable|cycle|status]

Defaults to cycle.
EOF
}

disable_targeting() {
  if cluster_labeled_for_demo; then
    log "Removing label $POLICY_LABEL_KEY from $SPOKE_CLUSTER_NAME"
    hub label managedcluster "$SPOKE_CLUSTER_NAME" "$POLICY_LABEL_KEY"- || true
  else
    log "$SPOKE_CLUSTER_NAME is already not targeted by label $POLICY_LABEL_KEY"
  fi
  wait_for "admission policy to be removed from $SPOKE_CLUSTER_NAME" 900 admission_policy_absent
  wait_for "deployment $DRIFT_APP_NAME to be removed from $SPOKE_CLUSTER_NAME" 900 drift_demo_absent
}

enable_targeting() {
  if cluster_labeled_for_demo; then
    log "$SPOKE_CLUSTER_NAME already has label $POLICY_LABEL_KEY=$POLICY_LABEL_VALUE"
  else
    log "Re-applying label $POLICY_LABEL_KEY=$POLICY_LABEL_VALUE to $SPOKE_CLUSTER_NAME"
    hub label managedcluster "$SPOKE_CLUSTER_NAME" "$POLICY_LABEL_KEY=$POLICY_LABEL_VALUE" --overwrite
  fi
  wait_for "managed cluster $SPOKE_CLUSTER_NAME to have label $POLICY_LABEL_KEY=$POLICY_LABEL_VALUE" 120 cluster_labeled_for_demo
  wait_for "admission policy to be restored on $SPOKE_CLUSTER_NAME" 900 admission_policy_present
  wait_for "deployment $DRIFT_APP_NAME to be restored on $SPOKE_CLUSTER_NAME" 900 drift_demo_present
  wait_for "deployment $DRIFT_APP_NAME to reconcile to replicas=1" 900 drift_demo_ready
}

show_status() {
  hub get managedcluster "$SPOKE_CLUSTER_NAME" --show-labels
  if admission_policy_present; then
    spoke get validatingadmissionpolicy require-approved-deployment-label
  else
    warn "Admission policy is not currently present on the spoke cluster."
  fi
  if drift_demo_present; then
    spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME"
  else
    warn "Deployment $DRIFT_APP_NAME is not currently present on the spoke cluster."
  fi
}

require_context

action="${1:-cycle}"

case "$action" in
  disable)
    disable_targeting
    ;;
  enable)
    enable_targeting
    ;;
  cycle)
    disable_targeting
    enable_targeting
    ;;
  status)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage
    die "Unknown action: $action"
    ;;
esac

show_status
