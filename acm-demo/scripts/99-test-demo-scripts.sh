#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESET_REQUIRED=0

log() {
  printf '[TEST] %s\n' "$*"
}

run_step() {
  local step="$1"
  shift

  log "Running $step"
  "$@"
}

cleanup() {
  if [[ "$RESET_REQUIRED" == "1" ]]; then
    log "Resetting the demo environment back to baseline"
    "$SCRIPT_DIR/90-reset-demo-state.sh"
  fi
}

trap cleanup EXIT

run_step "01-verify-cluster-access" "$SCRIPT_DIR/01-verify-cluster-access.sh"
run_step "02-import-sno2" "$SCRIPT_DIR/02-import-sno2.sh"
run_step "03-install-gitops" "$SCRIPT_DIR/03-install-gitops.sh"
run_step "04-confirm-sno2-managed" "$SCRIPT_DIR/04-confirm-sno2-managed.sh"
run_step "05-set-enforcement-label enable" "$SCRIPT_DIR/05-set-enforcement-label.sh" enable
run_step "06-apply-governance" "$SCRIPT_DIR/06-apply-governance.sh"
run_step "07-verify-governance" "$SCRIPT_DIR/07-verify-governance.sh"
run_step "08-apply-demo-gitops-rbac" "$SCRIPT_DIR/08-apply-demo-gitops-rbac.sh"
run_step "09-configure-demo-repo" "$SCRIPT_DIR/09-configure-demo-repo.sh"

RESET_REQUIRED=1

run_step "10-apply-compliant-app" "$SCRIPT_DIR/10-apply-compliant-app.sh"
run_step "11-apply-violating-app" "$SCRIPT_DIR/11-apply-violating-app.sh"
run_step "12-show-drift-remediation" "$SCRIPT_DIR/12-show-drift-remediation.sh"
run_step "13-toggle-policy-targeting cycle" "$SCRIPT_DIR/13-toggle-policy-targeting.sh" cycle

run_step "90-reset-demo-state" "$SCRIPT_DIR/90-reset-demo-state.sh"
RESET_REQUIRED=0

log "Demo scripting test run completed successfully"
