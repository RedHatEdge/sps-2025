#!/usr/bin/env bash
set -euo pipefail

echo "Searching for an unpartitioned secondary disk..."

# Detect the root disk device (e.g. /dev/sda)
ROOT_PART=$(df / | tail -1 | awk '{print $1}')
ROOT_DEV=$(lsblk -no pkname "$ROOT_PART" 2>/dev/null || true)
if [[ -z "$ROOT_DEV" ]]; then
    ROOT_DEV=$(basename "$ROOT_PART" | sed 's/[0-9]*$//')
fi
ROOT_DEV="/dev/${ROOT_DEV}"

# Find candidate disks:
# - only type "disk" (no partitions)
# - exclude loop, ram, dm, sr, zram, nvme boot drive, composefs, etc.
# - exclude the root device
CANDIDATE=$(
    lsblk -dn -o NAME,TYPE | \
    awk '$2=="disk"{print "/dev/"$1}' | \
    grep -Ev '/dev/(loop|.*ram|dm-|sr|zd|nvme.*n1p|composefs)' | \
    while read -r DEV; do
        [[ "$DEV" == "$ROOT_DEV" ]] && continue
        # Skip if it has partitions
        if ! lsblk -no NAME "$DEV" | grep -q "${DEV##*/}[0-9]"; then
            echo "$DEV"
            break
        fi
    done
)

if [[ -z "$CANDIDATE" ]]; then
    echo "No suitable unpartitioned disk found."
    exit 1
fi

echo "Found unpartitioned disk: $CANDIDATE"
echo "Initializing for LVM..."

sgdisk -Z "$CANDIDATE"
sleep 1
pvcreate "$CANDIDATE"
vgcreate microshift-storage "$CANDIDATE"

echo "Volume group 'microshift-storage' created successfully on $CANDIDATE."