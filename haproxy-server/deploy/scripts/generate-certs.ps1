param(
    [string]$Namespace = "haproxy-demo",
    [string]$HostName = "haproxy-server.local",
    [int]$ValidityDays = 825
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$certDir = Join-Path $repoRoot "deploy\certs"
$k8sDir = Join-Path $repoRoot "deploy\k8s"

New-Item -ItemType Directory -Force -Path $certDir | Out-Null
New-Item -ItemType Directory -Force -Path $k8sDir | Out-Null

function Convert-ToPem {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $base64 = [System.Convert]::ToBase64String($Bytes)
    $wrapped = ($base64 -split "(.{1,64})" | Where-Object { $_ }) -join "`n"
    return "-----BEGIN $Label-----`n$wrapped`n-----END $Label-----`n"
}

function Export-PrivateKeyBytes {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.RSA]$Key
    )

    $exportPkcs8 = $Key.GetType().GetMethod("ExportPkcs8PrivateKey", [System.Type[]]@())
    if ($null -ne $exportPkcs8) {
        return $exportPkcs8.Invoke($Key, @())
    }

    if ($Key -is [System.Security.Cryptography.RSACng]) {
        return $Key.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
    }

    throw "Unable to export private key with the current PowerShell/.NET runtime."
}

$caKey = [System.Security.Cryptography.RSA]::Create(4096)
$caDn = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=haproxy-demo-ca")
$caReq = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    $caDn,
    $caKey,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)
$caReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true)
) | Out-Null
$caReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign,
        $true
    )
) | Out-Null
$caReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($caReq.PublicKey, $false)
) | Out-Null
$caCert = $caReq.CreateSelfSigned(
    [datetimeoffset]::UtcNow.AddDays(-1),
    [datetimeoffset]::UtcNow.AddYears(5)
)

$serverKey = [System.Security.Cryptography.RSA]::Create(2048)
$serverDn = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=$HostName")
$serverReq = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    $serverDn,
    $serverKey,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)
$sanBuilder = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
$sanBuilder.AddDnsName($HostName)
$serverReq.CertificateExtensions.Add($sanBuilder.Build()) | Out-Null
$serverReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true)
) | Out-Null
$serverReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment,
        $true
    )
) | Out-Null
$serverEku = [System.Security.Cryptography.OidCollection]::new()
$serverEku.Add([System.Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.1", "Server Authentication")) | Out-Null
$serverReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
        $serverEku,
        $false
    )
) | Out-Null
$serverReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($serverReq.PublicKey, $false)
) | Out-Null

$serialNumber = New-Object byte[] 16
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($serialNumber)
$rng.Dispose()
$serverCert = $serverReq.Create(
    $caCert,
    [datetimeoffset]::UtcNow.AddDays(-1),
    [datetimeoffset]::UtcNow.AddDays($ValidityDays),
    $serialNumber
)

$clientKey = [System.Security.Cryptography.RSA]::Create(2048)
$clientDn = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=haproxy-demo-client")
$clientReq = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    $clientDn,
    $clientKey,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)
$clientReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true)
) | Out-Null
$clientReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment,
        $true
    )
) | Out-Null
$clientEku = [System.Security.Cryptography.OidCollection]::new()
$clientEku.Add([System.Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.2", "Client Authentication")) | Out-Null
$clientReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
        $clientEku,
        $false
    )
) | Out-Null
$clientReq.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($clientReq.PublicKey, $false)
) | Out-Null

$clientSerialNumber = New-Object byte[] 16
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($clientSerialNumber)
$rng.Dispose()
$clientCert = $clientReq.Create(
    $caCert,
    [datetimeoffset]::UtcNow.AddDays(-1),
    [datetimeoffset]::UtcNow.AddDays($ValidityDays),
    $clientSerialNumber
)

$caCertPem = Convert-ToPem -Bytes $caCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) -Label "CERTIFICATE"
$caKeyPem = Convert-ToPem -Bytes (Export-PrivateKeyBytes -Key $caKey) -Label "PRIVATE KEY"
$serverCertPem = Convert-ToPem -Bytes $serverCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) -Label "CERTIFICATE"
$serverKeyPem = Convert-ToPem -Bytes (Export-PrivateKeyBytes -Key $serverKey) -Label "PRIVATE KEY"
$clientCertPem = Convert-ToPem -Bytes $clientCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) -Label "CERTIFICATE"
$clientKeyPem = Convert-ToPem -Bytes (Export-PrivateKeyBytes -Key $clientKey) -Label "PRIVATE KEY"
$haproxyPem = "$serverCertPem`n$serverKeyPem"

[System.IO.File]::WriteAllText((Join-Path $certDir "ca.crt"), $caCertPem)
[System.IO.File]::WriteAllText((Join-Path $certDir "ca.key"), $caKeyPem)
[System.IO.File]::WriteAllText((Join-Path $certDir "server.crt"), $serverCertPem)
[System.IO.File]::WriteAllText((Join-Path $certDir "server.key"), $serverKeyPem)
[System.IO.File]::WriteAllText((Join-Path $certDir "client.crt"), $clientCertPem)
[System.IO.File]::WriteAllText((Join-Path $certDir "client.key"), $clientKeyPem)
[System.IO.File]::WriteAllText((Join-Path $certDir "tls.pem"), $haproxyPem)

$indentBlock = {
    param([string]$Value)
    (($Value.TrimEnd() -split "`r?`n") | ForEach-Object { "    $_" }) -join "`n"
}

$secretYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: haproxy-sidecar-tls
  namespace: $Namespace
type: Opaque
stringData:
  tls.pem: |
$(& $indentBlock $haproxyPem)
  ca.crt: |
$(& $indentBlock $caCertPem)
"@

[System.IO.File]::WriteAllText((Join-Path $k8sDir "02-haproxy-tls-secret.yaml"), $secretYaml)

Write-Host "Generated CA, server, and client certificates in $certDir"
Write-Host "Updated Kubernetes secret manifest at $(Join-Path $k8sDir '02-haproxy-tls-secret.yaml')"
