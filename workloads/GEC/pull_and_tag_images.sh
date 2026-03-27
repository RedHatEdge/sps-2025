#!/usr/bin/env bash
set -euo pipefail

# Pull images from a public mirror and tag them as listed on the left side
# Usage: run as root or allow passwordless sudo for the invoking user

MAPPINGS_FILE="$(dirname "$0")/mappings.txt"
PULL_REGISTRY="${PULL_REGISTRY:-registry-oc-mirror.apps.ipc4.sps2025.com}"
LOGFILE="/var/log/podman-pull-tag.log"

mkdir -p "$(dirname "$LOGFILE")"
exec >>"$LOGFILE" 2>&1

echo "=== podman-pull-tag run started: $(date) ==="

if [ ! -r "$MAPPINGS_FILE" ]; then
  echo "Mappings file not found or unreadable: $MAPPINGS_FILE"
  exit 1
fi

while IFS= read -r raw || [ -n "$raw" ]; do
  # strip comments and whitespace
  line="$(printf "%s" "$raw" | sed -e 's/#.*$//' -e 's/^\s*//' -e 's/\s*$//')"
  [ -z "$line" ] && continue

  left="${line%%=*}"
  right="${line#*=}"
  # ensure both sides exist
  if [ -z "$left" ] || [ -z "$right" ]; then
    echo "Skipping malformed line: $raw"
    continue
  fi

  # Determine whether left contains a digest (@sha256:...) or a tag.
  if [[ "$left" == *@* ]]; then
    digest_part="${left#*@}"
    # get repository path from right (strip registry host and port)
    repo_path="${right#*/}"
    # remove any :tag from repo_path to get only repo name/path
    repo_only="${repo_path%%:*}"
    pull_image="${PULL_REGISTRY}/${repo_only}@${digest_part}"
  else
    # left has no digest; use left's tag (or full left) and replace its registry with PULL_REGISTRY
    # extract path after the registry from left
    left_path="${left#*/}"
    pull_image="${PULL_REGISTRY}/${left_path}"
  fi

  echo "Pulling: $pull_image"
  if ! sudo podman pull --tls-verify=false "$pull_image"; then
    echo "Failed to pull $pull_image"
    continue
  fi

  # Determine tag target. If left contains a digest (e.g. @sha256:...), create
  # a deterministic tag using the repo from left and a `sha256-<digest>` tag
  # because registries do not accept creating tags that are manifest@sha256 references.
  if [[ "$left" == *@* ]]; then
    repo_only_from_left="${left%%@*}"
    digest_full="${left#*@}"
    digest_clean="${digest_full#sha256:}"
    target_tag="${repo_only_from_left}:sha256-${digest_clean}"
    echo "Tagging: $pull_image -> $target_tag (digest encoded)"
    if ! sudo podman tag "$pull_image" "$target_tag"; then
      echo "Failed to tag $pull_image -> $target_tag"
      continue
    fi
  else
    echo "Tagging: $pull_image -> $left"
    if ! sudo podman tag "$pull_image" "$left"; then
      echo "Failed to tag $pull_image -> $left"
      continue
    fi
  fi

done < "$MAPPINGS_FILE"

echo "=== podman-pull-tag run finished: $(date) ==="
