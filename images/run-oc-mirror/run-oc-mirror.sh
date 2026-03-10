#!/bin/sh
set -euo pipefail

# Simple wrapper to run oc-mirror using mounted config/secret
# Expects:
# - /tmp/imagesetconfiguration.yaml (mounted as a ConfigMap)
# - ENV: REGISTRY (destination registry)
# - ENV: DEST_USE_HTTP ('True'|'False')
# - ENV: DEST_SKIP_TLS ('True'|'False')

echo "Starting run-oc-mirror"

if [ ! -f /tmp/imagesetconfiguration.yaml ]; then
  echo "ERROR: /tmp/imagesetconfiguration.yaml not found"
  exit 2
fi

: ${REGISTRY:?'REGISTRY environment variable is required'}

CMD_ARGS="--config /tmp/imagesetconfiguration.yaml"

if [ "${DEST_USE_HTTP:-False}" = "True" ]; then
  CMD_ARGS="${CMD_ARGS} --use-http"
fi
if [ "${DEST_SKIP_TLS:-False}" = "True" ]; then
  CMD_ARGS="${CMD_ARGS} --skip-tls"
fi

echo "Running: oc-mirror ${CMD_ARGS} --dest docker://${REGISTRY}"
exec oc-mirror --v1 ${CMD_ARGS} --dest docker://${REGISTRY}
