param(
    [string]$Namespace = "haproxy-demo",
    [string]$ServiceName = "haproxy-server",
    [int]$LocalPort = 8443,
    [int]$RemotePort = 8443
)

$ErrorActionPreference = "Stop"

Write-Host "Starting port-forward for service/$ServiceName in namespace $Namespace"
Write-Host "Forwarding localhost:$LocalPort -> service/$ServiceName:$RemotePort"
Write-Host "If you use the ingress host name locally, keep haproxy-server.local mapped to 127.0.0.1 for this test."

kubectl port-forward --namespace $Namespace service/$ServiceName "${LocalPort}:${RemotePort}"
