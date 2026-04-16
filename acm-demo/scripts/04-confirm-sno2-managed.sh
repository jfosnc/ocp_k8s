#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_context

wait_for "managed cluster $SPOKE_CLUSTER_NAME to be joined and available" 900 managed_cluster_ready
hub get managedcluster "$SPOKE_CLUSTER_NAME" --show-labels

