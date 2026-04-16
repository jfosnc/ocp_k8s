#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DEMO_ROOT/.." && pwd)"

HUB_KUBECONFIG="${HUB_KUBECONFIG:-$REPO_ROOT/cluster1/auth/kubeconfig}"
SPOKE_KUBECONFIG="${SPOKE_KUBECONFIG:-$REPO_ROOT/cluster2/auth/kubeconfig}"

HUB_CLUSTER_NAME="${HUB_CLUSTER_NAME:-sno1}"
SPOKE_CLUSTER_NAME="${SPOKE_CLUSTER_NAME:-sno2}"
POLICY_NAMESPACE="${POLICY_NAMESPACE:-acm-policies}"
DEMO_NAMESPACE="${DEMO_NAMESPACE:-demo-gitops}"
GITOPS_NAMESPACE="${GITOPS_NAMESPACE:-openshift-gitops}"
GITOPS_OPERATOR_NAMESPACE="${GITOPS_OPERATOR_NAMESPACE:-openshift-gitops-operator}"
APPROVED_APP_NAME="${APPROVED_APP_NAME:-approved-demo}"
VIOLATING_APP_NAME="${VIOLATING_APP_NAME:-violating-demo}"
DRIFT_APP_NAME="${DRIFT_APP_NAME:-drift-demo}"
POLICY_LABEL_KEY="${POLICY_LABEL_KEY:-demo-policy}"
POLICY_LABEL_VALUE="${POLICY_LABEL_VALUE:-enabled}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-5}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"

APPROVED_APPLICATION_MANIFEST="$DEMO_ROOT/repo/application-compliant.yaml"
VIOLATING_APPLICATION_MANIFEST="$DEMO_ROOT/repo/application-violating.yaml"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_file() {
  [[ -f "$1" ]] || die "Required file not found: $1"
}

hub() {
  oc --kubeconfig "$HUB_KUBECONFIG" "$@"
}

spoke() {
  oc --kubeconfig "$SPOKE_KUBECONFIG" "$@"
}

require_context() {
  require_cmd oc
  require_file "$HUB_KUBECONFIG"
  require_file "$SPOKE_KUBECONFIG"
}

wait_for() {
  local description="$1"
  local timeout="${2:-$WAIT_TIMEOUT_SECONDS}"
  shift 2

  local start_time now
  start_time=$(date +%s)

  while true; do
    if "$@"; then
      log "$description"
      return 0
    fi

    now=$(date +%s)
    if (( now - start_time >= timeout )); then
      die "Timed out waiting for $description"
    fi

    sleep "$WAIT_INTERVAL_SECONDS"
  done
}

managed_cluster_ready() {
  local joined available

  joined="$(hub get managedcluster "$SPOKE_CLUSTER_NAME" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterJoined")].status}' 2>/dev/null || true)"
  available="$(hub get managedcluster "$SPOKE_CLUSTER_NAME" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || true)"

  [[ "$joined" == *True* && "$available" == *True* ]]
}

cluster_labeled_for_demo() {
  local value

  value="$(hub get managedcluster "$SPOKE_CLUSTER_NAME" -o jsonpath="{.metadata.labels['$POLICY_LABEL_KEY']}" 2>/dev/null || true)"
  [[ "$value" == "$POLICY_LABEL_VALUE" ]]
}

policy_reports_compliant() {
  local policy_name="$1"
  local status

  status="$(hub -n "$POLICY_NAMESPACE" get policy "$policy_name" -o jsonpath="{.status.status[?(@.clustername=='$SPOKE_CLUSTER_NAME')].compliant}" 2>/dev/null || true)"
  [[ "$status" == "Compliant" ]]
}

admission_policy_present() {
  spoke get validatingadmissionpolicy require-approved-deployment-label >/dev/null 2>&1
}

admission_policy_binding_present() {
  spoke get validatingadmissionpolicybinding require-approved-deployment-label-binding >/dev/null 2>&1
}

drift_demo_present() {
  spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME" >/dev/null 2>&1
}

drift_demo_ready() {
  local replicas

  replicas="$(spoke -n "$DEMO_NAMESPACE" get deployment "$DRIFT_APP_NAME" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  [[ "$replicas" == "1" ]]
}

application_ready() {
  local app_name="$1"
  local state

  state="$(spoke -n "$GITOPS_NAMESPACE" get application "$app_name" -o jsonpath='{.status.health.status} {.status.sync.status}' 2>/dev/null || true)"
  [[ "$state" == "Healthy Synced" ]]
}

application_operation_finished() {
  local app_name="$1"
  local phase

  phase="$(spoke -n "$GITOPS_NAMESPACE" get application "$app_name" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
  [[ -n "$phase" && "$phase" != "Running" ]]
}

application_reports_expected_admission_denial() {
  local app_name="$1"
  local message

  message="$(spoke -n "$GITOPS_NAMESPACE" get application "$app_name" -o jsonpath='{.status.operationState.message} {.status.conditions[*].message}' 2>/dev/null || true)"

  [[ "$message" == *"ValidatingAdmissionPolicy"* && "$message" == *"policy.demo.openshift.io/approved=true"* ]]
}
