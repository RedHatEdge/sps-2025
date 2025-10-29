#!/usr/bin/env bash
set -euo pipefail

sgdisk -Z STORAGE_DEVICE
sleep 1
pvcreate STORAGE_DEVICE
vgcreate microshift_storage STORAGE_DEVICE

echo "Storage setup complete."