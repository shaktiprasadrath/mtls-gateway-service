# Deploy HAProxy Sidecar Demo

This folder deploys the `haproxy-server:latest` application image with an `haproxy:2.9` sidecar.

Traffic flow:

`client -> Ingress -> HAProxy sidecar mTLS termination -> Spring Boot app`

The DNS name used by both the server certificate SAN and the Ingress host is:

`haproxy-server.local`

## Files

- `certs/`: generated demo CA, server cert, server key, and combined `tls.pem`
- `k8s/`: namespace, ConfigMap, generated Secret manifest, Deployment, Service, Ingress, and `kustomization.yaml`
- `scripts/generate-certs.sh`: generates the certs and renders the TLS Secret manifest
- `scripts/port-forward.ps1`: port-forwards the HAProxy Service to your local machine
- `scripts/port-forward.sh`: port-forwards the HAProxy Service from WSL/Linux shells

`deploy/certs/` and `deploy/k8s/02-haproxy-tls-secret.yaml` are generated artifacts and should stay local. Do not commit them to a public repository.

## Generate certs

From `mtls-gateway-service/haproxy-server`:

On Windows:

```powershell
./deploy/scripts/generate-certs.ps1
```

On WSL/Linux:

```bash
chmod +x ./deploy/scripts/generate-certs.sh
./deploy/scripts/generate-certs.sh
```

The certificate generation step must be run locally before `kubectl apply -k ./deploy/k8s`, because it creates the TLS secret manifest consumed by kustomize.

Generated server files:

- `deploy/certs/ca.crt`
- `deploy/certs/ca.key`
- `deploy/certs/server.crt`
- `deploy/certs/server.key`
- `deploy/certs/tls.pem`

Generated client files:

- `deploy/certs/client.crt`
- `deploy/certs/client.key`

## Build your app image

From `mtls-gateway-service/haproxy-server`:

```powershell
docker build -t haproxy-server:latest .
```

If your Kubernetes cluster inside WSL does not share the same Docker daemon, load the image into the cluster runtime before applying the manifests.

## Apply manifests

```bash
kubectl apply -k ./deploy/k8s
```

## Port-forward

From `mtls-gateway-service/haproxy-server`:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\scripts\port-forward.ps1
```

From WSL/Linux:

```bash
chmod +x ./deploy/scripts/port-forward.sh
./deploy/scripts/port-forward.sh
```

## Ingress requirements

This Ingress expects the NGINX ingress controller with SSL passthrough enabled.

For example, the controller must be started with:

```text
--enable-ssl-passthrough
```

## Local name resolution

Map the Ingress IP to `haproxy-server.local` in your hosts file or WSL `/etc/hosts`, then trust `deploy/certs/ca.crt` on the client side.

## Example request

```bash
curl --cert ./deploy/certs/client.crt --key ./deploy/certs/client.key --cacert ./deploy/certs/ca.crt "https://haproxy-server.local/capital/India"
```

## Client certificate enforcement

HAProxy now requires a client certificate signed by `deploy/certs/ca.crt`.

- `ca-file /usr/local/etc/haproxy/certs/ca.crt` tells HAProxy which CA to trust for client certificates.
- `verify required` rejects requests that do not present a valid client certificate.
- HAProxy forwards certificate verification details to the app in these headers:
  - `X-SSL-Client-Verify`
  - `X-SSL-Client-CN`
  - `X-SSL-Client-DN`

The Spring Boot app logs those forwarded values so you can confirm what HAProxy validated, even though the app itself does not participate in the TLS handshake.

## Security note

This repo is a learning demo. The preferred client flow is to use the generated `client.crt` and `client.key`. The client script can also mint a client certificate from the demo CA when you explicitly supply the CA private key, but that is not a production pattern. In a real deployment, the CA private key stays in a tightly controlled issuer workflow and clients receive already-issued certificates instead of direct CA signing access.
