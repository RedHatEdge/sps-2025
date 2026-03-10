#!/bin/bash
set -euo pipefail

# Download oc-mirror if not present
if [ ! -x ./oc-mirror ]; then
	echo "Downloading oc-mirror..."
	curl -fsSL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.tar.gz -o /tmp/oc-mirror.tar.gz
	tar -xzvf /tmp/oc-mirror.tar.gz -C /tmp oc-mirror || true
	mv /tmp/oc-mirror ./oc-mirror
	chmod +x ./oc-mirror
fi

# Read environment variables (with sensible defaults)
IMAGESET_CONFIG_PATH="${IMAGESET_CONFIG_PATH:-/tmp/imagesetconfiguration.yaml}"
NAMESPACE="${NAMESPACE:-oc-mirror}"
REGISTRY="${REGISTRY:-registry.${NAMESPACE}.svc.cluster.local:5000}"
DEST_USE_HTTP="${DEST_USE_HTTP:-False}"
DEST_SKIP_TLS="${DEST_SKIP_TLS:-False}"

if [ ! -f "${IMAGESET_CONFIG_PATH}" ]; then
	echo "ERROR: imageset config not found at ${IMAGESET_CONFIG_PATH}"
	exit 2
fi

# Ensure registry has no leading scheme (we will add docker://)
REG_NO_SCHEME="${REGISTRY#docker://}"

# Build oc-mirror arguments
CMD=("./oc-mirror --v1" "--config=${IMAGESET_CONFIG_PATH}")
if [ "${DEST_USE_HTTP,,}" = "true" ] || [ "${DEST_USE_HTTP}" = "1" ]; then
	CMD+=("--use-http")
fi
if [ "${DEST_SKIP_TLS,,}" = "true" ] || [ "${DEST_SKIP_TLS}" = "1" ]; then
	CMD+=("--skip-tls")
fi

CMD+=("docker://${REG_NO_SCHEME}")

echo "Running: ${CMD[*]}"
exec "${CMD[@]}"