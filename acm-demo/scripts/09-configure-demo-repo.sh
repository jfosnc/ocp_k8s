#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--repo-url URL] [--revision REVISION] [--path-prefix PREFIX]

Without arguments, the script prints the current Application source settings.
With --repo-url, --revision, and/or --path-prefix, it updates both Argo CD
Application manifests.
EOF
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

show_sources() {
  grep -HnE 'repoURL:|targetRevision:|path:' \
    "$APPROVED_APPLICATION_MANIFEST" \
    "$VIOLATING_APPLICATION_MANIFEST"
}

set_path_value() {
  local manifest="$1"
  local suffix="$2"
  local prefix="$3"
  local path_value

  if [[ -n "$prefix" ]]; then
    path_value="$prefix/$suffix"
  else
    path_value="$suffix"
  fi

  sed -i -E "s|(^[[:space:]]*path: ).*|\\1$(escape_sed_replacement "$path_value")|" "$manifest"
}

repo_url=""
revision=""
path_prefix=""
path_prefix_set=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)
      [[ $# -ge 2 ]] || die "--repo-url requires a value"
      repo_url="$2"
      shift 2
      ;;
    --revision)
      [[ $# -ge 2 ]] || die "--revision requires a value"
      revision="$2"
      shift 2
      ;;
    --path-prefix)
      [[ $# -ge 2 ]] || die "--path-prefix requires a value"
      path_prefix="$2"
      path_prefix_set=1
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

if [[ -z "$repo_url" && -z "$revision" && "$path_prefix_set" -eq 0 ]]; then
  log "Current Application source settings"
  show_sources
  exit 0
fi

if [[ -n "$repo_url" ]]; then
  log "Updating repoURL in the demo Application manifests"
  escaped_repo_url="$(escape_sed_replacement "$repo_url")"
  sed -i -E "s|(^[[:space:]]*repoURL: ).*|\\1$escaped_repo_url|" \
    "$APPROVED_APPLICATION_MANIFEST" \
    "$VIOLATING_APPLICATION_MANIFEST"
fi

if [[ -n "$revision" ]]; then
  log "Updating targetRevision in the demo Application manifests"
  escaped_revision="$(escape_sed_replacement "$revision")"
  sed -i -E "s|(^[[:space:]]*targetRevision: ).*|\\1$escaped_revision|" \
    "$APPROVED_APPLICATION_MANIFEST" \
    "$VIOLATING_APPLICATION_MANIFEST"
fi

if [[ "$path_prefix_set" -eq 1 ]]; then
  log "Updating Application path prefix"
  set_path_value "$APPROVED_APPLICATION_MANIFEST" "workloads/compliant" "$path_prefix"
  set_path_value "$VIOLATING_APPLICATION_MANIFEST" "workloads/violating" "$path_prefix"
fi

show_sources
