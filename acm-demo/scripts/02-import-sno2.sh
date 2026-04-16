#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--import-manifest /path/to/import.yaml]

If the ACM import manifest has already been downloaded from the hub console,
pass it with --import-manifest and this script will apply it on the spoke.
If the cluster is already imported, the script will just verify its state.
EOF
}

require_context

import_manifest=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --import-manifest)
      [[ $# -ge 2 ]] || die "--import-manifest requires a path"
      import_manifest="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -n "$import_manifest" ]]; then
  require_file "$import_manifest"
  log "Applying ACM import manifest on the spoke cluster"
  spoke apply -f "$import_manifest"
fi

if ! hub get managedcluster "$SPOKE_CLUSTER_NAME" >/dev/null 2>&1; then
  warn "Managed cluster $SPOKE_CLUSTER_NAME is not imported yet."
  cat <<EOF
Next step:
1. Open the ACM console on $HUB_CLUSTER_NAME.
2. Import an existing cluster named $SPOKE_CLUSTER_NAME.
3. Download the generated import manifest.
4. Re-run this script with:

   $(basename "$0") --import-manifest /path/to/${SPOKE_CLUSTER_NAME}-import.yaml
EOF
  exit 1
fi

wait_for "managed cluster $SPOKE_CLUSTER_NAME to be joined and available" 900 managed_cluster_ready
hub get managedcluster "$SPOKE_CLUSTER_NAME" --show-labels

