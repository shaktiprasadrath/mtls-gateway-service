from __future__ import annotations

import argparse
import datetime as dt
import ipaddress
from pathlib import Path
from urllib.parse import urlparse

import requests
import urllib3
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a client certificate signed by your CA and call the HAProxy mTLS endpoint."
    )
    parser.add_argument(
        "--server-url",
        default="https://localhost:8443/capital?country=India",
        help="Full HAProxy URL to call.",
    )
    parser.add_argument(
        "--ca-cert",
        default="certs/ca.crt",
        help="Path to the CA certificate PEM file.",
    )
    parser.add_argument(
        "--ca-key",
        default=None,
        help="Optional CA private key PEM file used only for demo-time client certificate minting.",
    )
    parser.add_argument(
        "--client-cert",
        default=None,
        help="Optional path to an already-issued client certificate PEM file.",
    )
    parser.add_argument(
        "--client-key",
        default=None,
        help="Optional path to an already-issued client private key PEM file.",
    )
    parser.add_argument(
        "--server-ca-cert",
        default=None,
        help="Optional CA certificate PEM file used only to verify the HAProxy server certificate.",
    )
    parser.add_argument(
        "--output-dir",
        default="generated",
        help="Directory where the generated client certificate and key will be written.",
    )
    parser.add_argument(
        "--client-common-name",
        default="haproxy-client",
        help="Common Name to place in the generated client certificate.",
    )
    parser.add_argument(
        "--connect-ip",
        default=None,
        help="Optional IP to connect to directly while preserving the URL hostname for TLS SNI and Host header.",
    )
    parser.add_argument(
        "--country",
        default=None,
        help="Optional country query value. If set, it replaces any existing country query parameter.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="HTTP request timeout in seconds.",
    )
    return parser.parse_args()


def load_ca_certificate(ca_cert_path: Path) -> x509.Certificate:
    return x509.load_pem_x509_certificate(ca_cert_path.read_bytes())


def load_ca_private_key(ca_key_path: Path):
    return serialization.load_pem_private_key(ca_key_path.read_bytes(), password=None)


def build_san_entries(hostname: str) -> list[x509.GeneralName]:
    san_entries: list[x509.GeneralName] = []
    try:
        san_entries.append(x509.IPAddress(ipaddress.ip_address(hostname)))
    except ValueError:
        san_entries.append(x509.DNSName(hostname))
    return san_entries


def write_client_material(
    ca_cert_path: Path,
    ca_key_path: Path,
    output_dir: Path,
    client_common_name: str,
    server_url: str,
) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)

    ca_cert = load_ca_certificate(ca_cert_path)
    ca_private_key = load_ca_private_key(ca_key_path)

    parsed_url = urlparse(server_url)
    hostname = parsed_url.hostname or "localhost"

    client_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Shakti"),
            x509.NameAttribute(NameOID.COMMON_NAME, client_common_name),
        ]
    )

    now = dt.datetime.now(dt.timezone.utc)
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(ca_cert.subject)
        .public_key(client_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - dt.timedelta(minutes=5))
        .not_valid_after(now + dt.timedelta(days=365))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=True,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH]),
            critical=False,
        )
        .add_extension(x509.SubjectAlternativeName(build_san_entries(hostname)), critical=False)
        .sign(private_key=ca_private_key, algorithm=hashes.SHA256())
    )

    client_key_path = output_dir / "client.key"
    client_cert_path = output_dir / "client.crt"

    client_key_path.write_bytes(
        client_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    client_cert_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))

    return client_cert_path, client_key_path


def build_request_url(server_url: str, country: str | None) -> str:
    if not country:
        return server_url

    parsed = urlparse(server_url)
    path = parsed.path or "/capital"
    return parsed._replace(path=path, query=f"country={country}").geturl()


def send_request(
    request_url: str,
    connect_ip: str | None,
    client_cert_path: Path,
    client_key_path: Path,
    server_ca_cert_path: Path,
    timeout: float,
):
    if not connect_ip:
        response = requests.get(
            request_url,
            cert=(str(client_cert_path), str(client_key_path)),
            verify=str(server_ca_cert_path),
            timeout=timeout,
        )
        response.raise_for_status()
        return response.text

    parsed_url = urlparse(request_url)
    original_host = parsed_url.hostname
    if not original_host:
        raise ValueError(f"Unable to determine hostname from URL: {request_url}")

    if parsed_url.scheme != "https":
        raise ValueError("--connect-ip is only supported for https URLs.")

    port = parsed_url.port or 443
    path_and_query = parsed_url.path or "/"
    if parsed_url.query:
        path_and_query = f"{path_and_query}?{parsed_url.query}"

    headers = {"Host": original_host}
    if parsed_url.port and parsed_url.port != 443:
        headers["Host"] = f"{original_host}:{parsed_url.port}"

    pool = urllib3.HTTPSConnectionPool(
        host=connect_ip,
        port=port,
        cert_file=str(client_cert_path),
        key_file=str(client_key_path),
        cert_reqs="CERT_REQUIRED",
        ca_certs=str(server_ca_cert_path),
        assert_hostname=original_host,
        server_hostname=original_host,
    )
    response = pool.request("GET", path_and_query, headers=headers, timeout=timeout)
    if response.status >= 400:
        raise RuntimeError(f"Request failed with status {response.status}: {response.data.decode('utf-8', errors='replace')}")
    return response.data.decode("utf-8")


def main() -> int:
    args = parse_args()

    script_dir = Path(__file__).resolve().parent
    ca_cert_path = (script_dir / args.ca_cert).resolve()
    server_ca_cert_path = (
        (script_dir / args.server_ca_cert).resolve() if args.server_ca_cert else ca_cert_path
    )
    output_dir = (script_dir / args.output_dir).resolve()
    client_cert_path = (script_dir / args.client_cert).resolve() if args.client_cert else None
    client_key_path = (script_dir / args.client_key).resolve() if args.client_key else None
    ca_key_path = (script_dir / args.ca_key).resolve() if args.ca_key else None

    if not ca_cert_path.exists():
        raise FileNotFoundError(f"CA certificate not found: {ca_cert_path}")
    if not server_ca_cert_path.exists():
        raise FileNotFoundError(f"Server CA certificate not found: {server_ca_cert_path}")
    if (client_cert_path is None) != (client_key_path is None):
        raise ValueError("Provide both --client-cert and --client-key, or neither.")

    if client_cert_path and client_key_path:
        if not client_cert_path.exists():
            raise FileNotFoundError(f"Client certificate not found: {client_cert_path}")
        if not client_key_path.exists():
            raise FileNotFoundError(f"Client private key not found: {client_key_path}")
    else:
        if ca_key_path is None:
            raise ValueError(
                "Provide --client-cert/--client-key, or supply --ca-key to mint a demo client certificate."
            )
        if not ca_key_path.exists():
            raise FileNotFoundError(f"CA private key not found: {ca_key_path}")

        print(
            "WARNING: Demo-only certificate flow. This client reads a CA private key to mint a client certificate. "
            "Do not use this pattern in production."
        )

        client_cert_path, client_key_path = write_client_material(
            ca_cert_path=ca_cert_path,
            ca_key_path=ca_key_path,
            output_dir=output_dir,
            client_common_name=args.client_common_name,
            server_url=args.server_url,
        )

    request_url = build_request_url(args.server_url, args.country)
    response_text = send_request(
        request_url=request_url,
        connect_ip=args.connect_ip,
        client_cert_path=client_cert_path,
        client_key_path=client_key_path,
        server_ca_cert_path=server_ca_cert_path,
        timeout=args.timeout,
    )

    print(f"Request URL: {request_url}")
    if args.connect_ip:
        print(f"Connected IP: {args.connect_ip}")
    print(f"Client certificate: {client_cert_path}")
    print(response_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
