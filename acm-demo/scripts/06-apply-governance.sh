#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_context

cluster_labeled_for_demo || die "Managed cluster $SPOKE_CLUSTER_NAME is not labeled for the demo. Run 05-set-enforcement-label.sh first."

log "Applying ACM governance policies on the hub"
hub apply -f "$DEMO_ROOT/hub/00-namespace.yaml"
hub apply -f "$DEMO_ROOT/hub/01-policy.yaml"
hub apply -f "$DEMO_ROOT/hub/05-drift-policy.yaml"
hub apply -f "$DEMO_ROOT/hub/02-managedclustersetbinding.yaml"
hub apply -f "$DEMO_ROOT/hub/03-placement.yaml"
hub apply -f "$DEMO_ROOT/hub/04-placementbinding.yaml"

wait_for "policy deny-unapproved-deployments to report Compliant for $SPOKE_CLUSTER_NAME" 900 policy_reports_compliant deny-unapproved-deployments
wait_for "policy enforce-drift-demo to report Compliant for $SPOKE_CLUSTER_NAME" 900 policy_reports_compliant enforce-drift-demo

hub -n "$POLICY_NAMESPACE" get policy

