# mTLS Gateway Service

This project demonstrates a secure service-to-service access pattern using mutual TLS (mTLS) with HAProxy acting as the gateway in front of a Spring Boot application. The backend service exposes country-to-capital lookup APIs, while the Python client generates a demo client certificate, presents it during the TLS handshake, and calls the HAProxy endpoint over HTTPS.

The overall flow is:

`Python client -> HAProxy TLS gateway -> Spring Boot server`

## Why HAProxy

HAProxy is used here as the secure gateway layer because it is a strong fit for TLS termination, certificate validation, routing, observability, and policy enforcement. Instead of teaching every backend service how to perform certificate validation and handshake-level security checks, HAProxy centralizes that responsibility at the edge of the application.

In this setup, HAProxy:

- terminates the incoming TLS connection
- validates the client certificate against a trusted CA
- rejects clients that do not present a valid certificate
- forwards verified request metadata to the Spring Boot service through headers
- keeps the application focused on business logic instead of transport-layer security

That separation is useful in real systems because gateway-level security is easier to standardize, audit, and scale than re-implementing TLS enforcement inside every service.

## What Is mTLS and Why We Use It

Standard TLS verifies the server identity so that the client knows it is talking to the right endpoint. Mutual TLS extends that model by requiring both sides to authenticate each other with certificates.

That matters in internal platforms and zero-trust environments because:

- the client can prove its identity before any application request is processed
- the server can prove its identity to the client
- unauthorized clients are blocked during the handshake itself
- trust is based on issued certificates instead of only IP rules or shared secrets
- the system gets a stronger and more explicit machine-to-machine authentication model

In this demo, the client certificate is signed by the same trusted CA that HAProxy uses to validate callers. If the certificate is missing, untrusted, or invalid, HAProxy denies the request before it reaches the Spring Boot application.

## Repository Layout

```text
mtls-gateway-service/
|-- haproxy-client/
|   |-- app.py
|   |-- certs/
|   `-- requirements.txt
`-- haproxy-server/
    |-- src/
    |-- deploy/
    |   |-- certs/
    |   |-- k8s/
    |   `-- scripts/
    `-- Dockerfile
```

## Server-Side Changes

The server side is made of two cooperating parts: the Spring Boot application and the HAProxy gateway deployment.

### Spring Boot application

The backend service:

- exposes `GET /capital?country=...` and `GET /capital/{country}`
- stores country/capital data in an H2 in-memory database
- initializes schema and sample data from `schema.sql` and `data.sql`
- logs forwarded certificate verification details received from HAProxy

The application does not perform the TLS handshake itself. Instead, it trusts the gateway to validate the client certificate and forward the verified metadata through:

- `X-SSL-Client-Verify`
- `X-SSL-Client-CN`
- `X-SSL-Client-DN`

This is implemented through the request logging filter in `haproxy-server/src/main/java/.../security/ClientCertificateLoggingFilter.java`, which records whether HAProxy accepted the client certificate and which identity was presented.

### HAProxy gateway deployment

The Kubernetes deployment adds an `haproxy:2.9` sidecar in front of the Spring Boot container. HAProxy listens on `8443`, uses the configured server certificate, trusts the CA in `deploy/certs/ca.crt`, and enforces client-certificate validation with:

```text
verify required
```

The HAProxy config also:

- logs TLS version, cipher, SNI, and client verification details
- forwards HTTPS requests to the local Spring Boot app on `127.0.0.1:8080`
- performs a backend health check on `/capital/India`
- injects forwarded certificate identity headers for the application layer

This gives the service an mTLS-protected entry point without embedding certificate-handling code in the Java service.

## Client-Side Changes

The client is a Python script that automates certificate generation and secure invocation of the HAProxy endpoint.

The client:

- verifies the HAProxy server certificate with the trusted CA
- preferably uses an already-issued client certificate and private key
- can optionally mint a demo client certificate when you explicitly provide the CA private key
- connects to the HAProxy HTTPS endpoint using the generated certificate
- optionally preserves the original hostname while connecting to a chosen IP address

That makes the demo easy to run locally because the server setup can issue a sample client certificate for reuse, while the client still verifies the HAProxy server certificate so that trust works in both directions.

This is a demo-only shortcut. In a real system, the CA private key is never distributed to clients. Clients should receive pre-issued certificates from a controlled issuer workflow.

## Execution

### 1. Generate server and client certificates

The demo uses one local CA to issue:

- the HAProxy server certificate and key
- the sample client certificate and key
- the combined `tls.pem` file used by HAProxy
- the generated Kubernetes TLS Secret manifest

From `mtls-gateway-service/haproxy-server` on Windows:

```powershell
./deploy/scripts/generate-certs.ps1
```

From `mtls-gateway-service/haproxy-server` on WSL/Linux:

```bash
chmod +x ./deploy/scripts/generate-certs.sh
./deploy/scripts/generate-certs.sh
```

Generated server-side files:

- `deploy/certs/ca.crt`
- `deploy/certs/ca.key`
- `deploy/certs/server.crt`
- `deploy/certs/server.key`
- `deploy/certs/tls.pem`
- `deploy/k8s/02-haproxy-tls-secret.yaml`

Generated client-side files for reuse:

- `deploy/certs/client.crt`
- `deploy/certs/client.key`

### 2. Deploy and start the server application

From `mtls-gateway-service/haproxy-server`:

```powershell
./deploy/scripts/generate-certs.ps1
docker build -t haproxy-server:latest .
kubectl apply -k .\deploy\k8s
powershell -ExecutionPolicy Bypass -File .\deploy\scripts\port-forward.ps1
```

Notes:

- the deployment expects the TLS assets under `haproxy-server/deploy/certs/`
- `./deploy/scripts/generate-certs.ps1` creates local demo certs and the generated `deploy/k8s/02-haproxy-tls-secret.yaml`
- HAProxy listens on local port `8443` after port-forward starts
- the Kubernetes `NetworkPolicy` restricts pod ingress to the HAProxy port so the app is not reachable directly on `8080`
- if you want hostname-based validation, map `haproxy-server.local` to `127.0.0.1`

### 3. Run the client with the generated client certificate

From `mtls-gateway-service/haproxy-client`:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py --server-url "https://localhost:8443/capital?country=India" --ca-cert "..\haproxy-server\deploy\certs\ca.crt" --client-cert "..\haproxy-server\deploy\certs\client.crt" --client-key "..\haproxy-server\deploy\certs\client.key"
```

If you want to preserve the hostname used by the server certificate:

```powershell
python app.py --server-url "https://haproxy-server.local/capital?country=India" --connect-ip 127.0.0.1 --ca-cert "..\haproxy-server\deploy\certs\ca.crt" --client-cert "..\haproxy-server\deploy\certs\client.crt" --client-key "..\haproxy-server\deploy\certs\client.key"
```

### 4. Optional: mint a demo client certificate from the client script

This is only for local learning. It intentionally uses the CA private key and should not be treated as a production pattern.

```powershell
python app.py --server-url "https://localhost:8443/capital?country=India" --ca-cert "..\haproxy-server\deploy\certs\ca.crt" --ca-key "..\haproxy-server\deploy\certs\ca.key"
```

If you explicitly want the client to mint a demo certificate instead, pass `--ca-key` and omit `--client-cert` and `--client-key`.

## Validation

When the setup is working, validation should be visible on both the client side and server side.

### Example client-side handshake/result snippet

```text
Request URL: https://localhost:8443/capital?country=India
Client certificate: C:\...\mtls-gateway-service\haproxy-client\generated\client.crt
{"country":"India","capital":"New Delhi"}
```

### Example HAProxy / server-side handshake snippet

HAProxy log:

```text
127.0.0.1:53310 [21/Apr/2026:10:42:16.120] https_in haproxy-server/app_backend 0/0/1/4/5 200 43 ssl_version=TLSv1.3 ssl_cipher=TLS_AES_256_GCM_SHA384 sni="haproxy-server.local" client_verify=0 client_cn="haproxy-client" client_dn="CN=haproxy-client,O=Shakti,C=US" "GET /capital?country=India HTTP/1.1"
```

Spring Boot application log:

```text
HAProxy client certificate verification status=0, cn=haproxy-client, dn="CN=haproxy-client,O=Shakti,C=US", path=/capital
```

`client_verify=0` indicates successful certificate verification by HAProxy. If the client certificate is missing or invalid, the TLS handshake is rejected before the request reaches the application.

## Exposure Note

If you publish or share this demo, the main exposure risks are:

- committing `deploy/certs/*` or `deploy/k8s/02-haproxy-tls-secret.yaml`
- giving end users the CA private key instead of only an issued client certificate
- exposing the app port directly and bypassing HAProxy/mTLS
- keeping old container base images and dependencies with known CVEs
- logging certificate identity details in places where they do not need to be retained

To reduce that risk:

- never commit generated keys, cert bundles, or rendered Kubernetes Secrets
- rotate the CA and reissue all certs immediately if any private key is exposed
- distribute only `client.crt`, `client.key`, and the trust anchor `ca.crt` to demo users
- keep ingress pointed at HAProxy only and do not publish direct access to `8080`
- rebuild and re-scan images regularly with `docker scout cves`
- treat this repo as a learning environment, not a production PKI design
