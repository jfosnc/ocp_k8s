#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

gitops_namespace_exists() {
  spoke get ns "$GITOPS_NAMESPACE" >/dev/null 2>&1
}

application_controller_pod_exists() {
  spoke -n "$GITOPS_NAMESPACE" get pod/openshift-gitops-application-controller-0 >/dev/null 2>&1
}

require_context

log "Installing OpenShift GitOps on the spoke cluster"
spoke apply -f "$DEMO_ROOT/spoke/gitops-operator/00-namespace.yaml"
spoke apply -f "$DEMO_ROOT/spoke/gitops-operator/01-operatorgroup.yaml"
spoke apply -f "$DEMO_ROOT/spoke/gitops-operator/02-subscription.yaml"

wait_for "OpenShift GitOps namespace $GITOPS_NAMESPACE to exist" 900 gitops_namespace_exists
wait_for "OpenShift GitOps application controller pod to exist" 900 application_controller_pod_exists
spoke -n "$GITOPS_NAMESPACE" wait --for=condition=Ready pod/openshift-gitops-application-controller-0 --timeout=10m

log "GitOps operator status"
spoke -n "$GITOPS_OPERATOR_NAMESPACE" get subscriptions.operators.coreos.com
spoke -n "$GITOPS_OPERATOR_NAMESPACE" get installplan,csv

log "GitOps workload status"
spoke get ns "$GITOPS_NAMESPACE"
spoke -n "$GITOPS_NAMESPACE" get pods

