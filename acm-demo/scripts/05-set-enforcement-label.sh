#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

cluster_not_labeled_for_demo() {
  ! cluster_labeled_for_demo
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [enable|disable|status]

Defaults to enable.
EOF
}

require_context

action="${1:-enable}"

case "$action" in
  enable)
    if cluster_labeled_for_demo; then
      log "$SPOKE_CLUSTER_NAME already has label $POLICY_LABEL_KEY=$POLICY_LABEL_VALUE"
    else
      log "Labeling $SPOKE_CLUSTER_NAME with $POLICY_LABEL_KEY=$POLICY_LABEL_VALUE"
      hub label managedcluster "$SPOKE_CLUSTER_NAME" "$POLICY_LABEL_KEY=$POLICY_LABEL_VALUE" --overwrite
    fi
    wait_for "managed cluster $SPOKE_CLUSTER_NAME to have label $POLICY_LABEL_KEY=$POLICY_LABEL_VALUE" 120 cluster_labeled_for_demo
    ;;
  disable)
    if cluster_labeled_for_demo; then
      log "Removing label $POLICY_LABEL_KEY from $SPOKE_CLUSTER_NAME"
      hub label managedcluster "$SPOKE_CLUSTER_NAME" "$POLICY_LABEL_KEY"- || true
    else
      log "$SPOKE_CLUSTER_NAME does not currently have label $POLICY_LABEL_KEY"
    fi
    wait_for "managed cluster $SPOKE_CLUSTER_NAME to no longer have label $POLICY_LABEL_KEY" 120 cluster_not_labeled_for_demo
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

hub get managedcluster "$SPOKE_CLUSTER_NAME" --show-labels
