#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

demo_namespace_exists() {
  spoke get ns "$DEMO_NAMESPACE" >/dev/null 2>&1
}

require_context

wait_for "admission policy require-approved-deployment-label to appear on $SPOKE_CLUSTER_NAME" 900 admission_policy_present
wait_for "admission policy binding to appear on $SPOKE_CLUSTER_NAME" 900 admission_policy_binding_present
wait_for "namespace $DEMO_NAMESPACE to exist on $SPOKE_CLUSTER_NAME" 900 demo_namespace_exists
wait_for "deployment $DRIFT_APP_NAME to exist on $SPOKE_CLUSTER_NAME" 900 drift_demo_present
wait_for "deployment $DRIFT_APP_NAME to converge to replicas=1" 900 drift_demo_ready

spoke get validatingadmissionpolicy require-approved-deployment-label
spoke get validatingadmissionpolicybinding require-approved-deployment-label-binding
spoke get ns "$DEMO_NAMESPACE"
spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME"

