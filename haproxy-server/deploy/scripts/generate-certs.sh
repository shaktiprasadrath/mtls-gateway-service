#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CERT_DIR="${DEPLOY_DIR}/certs"
K8S_DIR="${DEPLOY_DIR}/k8s"

NAMESPACE="${NAMESPACE:-haproxy-demo}"
HOST_NAME="${HOST_NAME:-haproxy-server.local}"
VALIDITY_DAYS="${VALIDITY_DAYS:-825}"

mkdir -p "${CERT_DIR}" "${K8S_DIR}"

openssl genrsa -out "${CERT_DIR}/ca.key" 4096
openssl req -x509 -new -nodes \
  -key "${CERT_DIR}/ca.key" \
  -sha256 \
  -days 1825 \
  -subj "/CN=haproxy-demo-ca" \
  -out "${CERT_DIR}/ca.crt"

openssl genrsa -out "${CERT_DIR}/server.key" 2048
openssl req -new \
  -key "${CERT_DIR}/server.key" \
  -subj "/CN=${HOST_NAME}" \
  -out "${CERT_DIR}/server.csr"

cat > "${CERT_DIR}/server-ext.cnf" <<EOF
subjectAltName=DNS:${HOST_NAME}
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF

openssl x509 -req \
  -in "${CERT_DIR}/server.csr" \
  -CA "${CERT_DIR}/ca.crt" \
  -CAkey "${CERT_DIR}/ca.key" \
  -CAcreateserial \
  -out "${CERT_DIR}/server.crt" \
  -days "${VALIDITY_DAYS}" \
  -sha256 \
  -extfile "${CERT_DIR}/server-ext.cnf"

openssl genrsa -out "${CERT_DIR}/client.key" 2048
openssl req -new \
  -key "${CERT_DIR}/client.key" \
  -subj "/CN=haproxy-demo-client" \
  -out "${CERT_DIR}/client.csr"

cat > "${CERT_DIR}/client-ext.cnf" <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

openssl x509 -req \
  -in "${CERT_DIR}/client.csr" \
  -CA "${CERT_DIR}/ca.crt" \
  -CAkey "${CERT_DIR}/ca.key" \
  -CAcreateserial \
  -out "${CERT_DIR}/client.crt" \
  -days "${VALIDITY_DAYS}" \
  -sha256 \
  -extfile "${CERT_DIR}/client-ext.cnf"

cat "${CERT_DIR}/server.crt" "${CERT_DIR}/server.key" > "${CERT_DIR}/tls.pem"

TLS_PEM_INDENTED="$(sed 's/^/    /' "${CERT_DIR}/tls.pem")"
CA_CERT_INDENTED="$(sed 's/^/    /' "${CERT_DIR}/ca.crt")"

cat > "${K8S_DIR}/02-haproxy-tls-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: haproxy-sidecar-tls
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  tls.pem: |
${TLS_PEM_INDENTED}
  ca.crt: |
${CA_CERT_INDENTED}
EOF

rm -f \
  "${CERT_DIR}/server.csr" \
  "${CERT_DIR}/client.csr" \
  "${CERT_DIR}/server-ext.cnf" \
  "${CERT_DIR}/client-ext.cnf" \
  "${CERT_DIR}/ca.srl"

echo "Generated CA, server, and client certificates in ${CERT_DIR}"
echo "Updated Kubernetes secret manifest at ${K8S_DIR}/02-haproxy-tls-secret.yaml"
