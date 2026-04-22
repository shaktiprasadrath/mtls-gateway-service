#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-haproxy-demo}"
SERVICE_NAME="${SERVICE_NAME:-haproxy-server}"
LOCAL_PORT="${LOCAL_PORT:-8443}"
REMOTE_PORT="${REMOTE_PORT:-8443}"

echo "Starting port-forward for service/${SERVICE_NAME} in namespace ${NAMESPACE}"
echo "Forwarding localhost:${LOCAL_PORT} -> service/${SERVICE_NAME}:${REMOTE_PORT}"
echo "If you use the ingress host name locally, keep haproxy-server.local mapped to 127.0.0.1 for this test."

kubectl port-forward --namespace "${NAMESPACE}" "service/${SERVICE_NAME}" "${LOCAL_PORT}:${REMOTE_PORT}"
