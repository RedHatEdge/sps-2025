#!/usr/bin/env bash
set -euo pipefail

# export_and_load_images.sh
# Pull images (by digest when available), tag deterministically, save to a tar,
# copy to a disconnected host, and load there with sudo podman.
#
# Usage:
#   export_and_load_images.sh <remote-user> <remote-host> [remote-dest-dir]
# Example:
#   ./export_and_load_images.sh root 10.0.0.5 /tmp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAPPINGS_FILE="${SCRIPT_DIR}/mappings.txt"
PULL_REGISTRY="${PULL_REGISTRY:-registry-oc-mirror.apps.ipc4.sps2025.com}"
REMOTE_USER="${1:-}"
REMOTE_HOST="${2:-}"
REMOTE_DIR="${3:-/tmp}"

if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOST" ]; then
  echo "Usage: $0 <remote-user> <remote-host> [remote-dest-dir]"
  exit 2
fi

TMPDIR=$(mktemp -d /tmp/podman-export.XXXX)
TARPATH="$TMPDIR/pulled_images.tar"
IMAGES_LIST=()

echo "Mappings: $MAPPINGS_FILE"
echo "Pull registry: $PULL_REGISTRY"
echo "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR"

if [ ! -r "$MAPPINGS_FILE" ]; then
  echo "Mappings file missing: $MAPPINGS_FILE"
  exit 1
fi

while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(printf "%s" "$raw" | sed -e 's/#.*$//' -e 's/^\s*//' -e 's/\s*$//')"
  [ -z "$line" ] && continue

  left="${line%%=*}"
  right="${line#*=}"
  if [ -z "$left" ] || [ -z "$right" ]; then
    echo "Skipping malformed line: $raw"
    continue
  fi

  # Build pull image: prefer left digest when present
  if [[ "$left" == *@* ]]; then
    digest_part="${left#*@}"
    # use path from right (after first '/') and strip tag if present
    repo_path="${right#*/}"
    repo_only="${repo_path%%:*}"
    pull_image="${PULL_REGISTRY}/${repo_only}@${digest_part}"
    # create a deterministic tag for saving/loading
    repo_only_from_left="${left%%@*}"
    digest_full="${left#*@}"
    digest_clean="${digest_full#sha256:}"
    target_tag="${repo_only_from_left}:sha256-${digest_clean}"
  else
    # left has no digest; use left's registry-stripped path under PULL_REGISTRY
    left_path="${left#*/}"
    pull_image="${PULL_REGISTRY}/${left_path}"
    target_tag="$left"
  fi

  echo "Pulling $pull_image"
  if ! sudo podman pull --tls-verify=false "$pull_image"; then
    echo "WARNING: failed to pull $pull_image -- continuing"
    continue
  fi

  echo "Tagging pulled -> $target_tag"
  if ! sudo podman tag "$pull_image" "$target_tag"; then
    echo "WARNING: failed to tag $pull_image -> $target_tag -- continuing"
    continue
  fi

  IMAGES_LIST+=("$target_tag")
done < "$MAPPINGS_FILE"

if [ ${#IMAGES_LIST[@]} -eq 0 ]; then
  echo "No images were pulled; exiting"
  rm -rf "$TMPDIR"
  exit 0
fi

echo "Saving ${#IMAGES_LIST[@]} images to $TARPATH"
sudo podman save -o "$TARPATH" "${IMAGES_LIST[@]}"

echo "Copying tar to remote host"
scp "$TARPATH" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/" || {
  echo "scp failed"; rm -rf "$TMPDIR"; exit 1
}

REMOTE_TAR="$REMOTE_DIR/$(basename "$TARPATH")"
echo "Loading tar on remote host: $REMOTE_TAR"
ssh "$REMOTE_USER@$REMOTE_HOST" bash -s <<EOF
set -euo pipefail
sudo podman load -i "$REMOTE_TAR"
sudo rm -f "$REMOTE_TAR"
echo "Remote load complete"
EOF

echo "Cleaning local temporary files"
rm -rf "$TMPDIR"

echo "Done."
