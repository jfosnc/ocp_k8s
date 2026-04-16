#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_context

log "Verifying hub access with $HUB_KUBECONFIG"
hub whoami

log "Verifying spoke access with $SPOKE_KUBECONFIG"
spoke whoami

log "Current ACM managed clusters"
hub get managedcluster

