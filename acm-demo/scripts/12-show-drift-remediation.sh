#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_context
wait_for "deployment $DRIFT_APP_NAME to exist on $SPOKE_CLUSTER_NAME" 900 drift_demo_present

log "Current drift-demo state"
spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME" -o custom-columns=NAME:.metadata.name,SPEC_REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas

log "Scaling $DRIFT_APP_NAME to replicas=3 to simulate drift"
spoke -n "$DEMO_NAMESPACE" scale deployment "$DRIFT_APP_NAME" --replicas=3
spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME" -o custom-columns=NAME:.metadata.name,SPEC_REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas

wait_for "ACM to reconcile $DRIFT_APP_NAME back to replicas=1" 600 drift_demo_ready
spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME" -o custom-columns=NAME:.metadata.name,SPEC_REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas
hub -n "$POLICY_NAMESPACE" describe policy enforce-drift-demo

