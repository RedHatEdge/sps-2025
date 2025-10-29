#!/bin/bash

TEMPDIR=$(mktemp --directory)

echo Unpack container image
mkdir -p "${TEMPDIR}/container"
skopeo copy "containers-storage:$1" "oci:${TEMPDIR}/container/"

echo "Custom kickstart detected, will use..."
cp $2 "${TEMPDIR}/local.ks"

echo Pack iso to "$4"
cd "${TEMPDIR}"
sudo mkksiso --ks local.ks --add container/ \
     --cmdline "console=tty0 console=ttyS0,115200n8" \
     --rm-args "quiet" \
    "$3" "$4"
rm -rf "${TEMPDIR}"
echo Done