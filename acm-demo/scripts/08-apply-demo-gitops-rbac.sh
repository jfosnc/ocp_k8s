#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_context

log "Granting the OpenShift GitOps application controller admin access in $DEMO_NAMESPACE"
spoke apply -f "$DEMO_ROOT/spoke/03-demo-gitops-rbac.yaml"
spoke -n "$DEMO_NAMESPACE" get rolebinding openshift-gitops-application-controller-admin

