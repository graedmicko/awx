<#
.SYNOPSIS
    Automated bootstrap script for local Ansible AWX deployment on Windows.

.DESCRIPTION
    Checks Docker and Kubernetes prerequisites, applies the AWX Operator manifests,
    waits for pod readiness, forwards the AWX web port to localhost:8080,
    and extracts the generated admin password.
#>

[CmdletBinding()]
param(
    [string]$Namespace = "awx",
    [string]$AwxName = "awx-demo",
    [int]$LocalPort = 8080
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       Ansible AWX Local Deployment Bootstrap            " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check Docker status
Write-Host "`n[1/5] Memeriksa status Docker..." -ForegroundColor Yellow
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker daemon belum berjalan."
    }
    Write-Host " -> Docker aktif dan terhubung." -ForegroundColor Green
} catch {
    Write-Warning "Docker Desktop belum aktif atau tidak dapat diakses!"
    Write-Host "Silakan jalankan aplikasi Docker Desktop terlebih dahulu, lalu jalankan ulang skrip ini." -ForegroundColor White
    exit 1
}

# 2. Check Kubernetes cluster connectivity
Write-Host "`n[2/5] Memeriksa koneksi Kubernetes..." -ForegroundColor Yellow
try {
    $nodes = kubectl get nodes --request-timeout='5s' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Cluster Kubernetes tidak merespon."
    }
    Write-Host " -> Kubernetes cluster terdeteksi aktif:" -ForegroundColor Green
    $nodes | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
} catch {
    Write-Warning "Kubernetes cluster tidak ditemukan atau belum aktif!"
    Write-Host "Panduan mengaktifkan Kubernetes di Docker Desktop:" -ForegroundColor White
    Write-Host " 1. Buka Docker Desktop Settings (ikon gerigi di kanan atas)" -ForegroundColor Cyan
    Write-Host " 2. Pilih menu 'Kubernetes'" -ForegroundColor Cyan
    Write-Host " 3. Centang 'Enable Kubernetes' lalu klik 'Apply & restart'" -ForegroundColor Cyan
    Write-Host " 4. Tunggu hingga status Kubernetes berwarna hijau di kiri bawah Docker Desktop" -ForegroundColor Cyan
    exit 1
}

# 3. Create namespace & apply AWX manifests
Write-Host "`n[3/5] Menerapkan manifest AWX Operator ke namespace '$Namespace'..." -ForegroundColor Yellow
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$k8sDir = (Resolve-Path (Join-Path $scriptDir "..\k8s")).Path

kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k $k8sDir -n $Namespace

Write-Host " -> Manifest berhasil diterapkan." -ForegroundColor Green

# 4. Wait for AWX Operator controller & AWX pods
Write-Host "`n[4/5] Menunggu controller & instance AWX siap..." -ForegroundColor Yellow
Write-Host " -> Menunggu AWX Operator Controller Manager (bisa memakan waktu 1-2 menit saat download image pertama kali)..." -ForegroundColor White

try {
    kubectl -n $Namespace rollout status deployment/awx-operator-controller-manager --timeout=300s
} catch {
    Write-Warning "AWX Operator controller sedang dalam proses pull image atau inisialisasi."
}

Write-Host " -> Operator aktif. Instance '$AwxName' sedang dibuat oleh operator." -ForegroundColor Green
Write-Host "    (Proses pembuatan database PostgreSQL, migrations, dan web pod membutuhkan waktu beberapa menit)" -ForegroundColor DarkGray

# 5. Retrieve Admin credentials & Setup Port Forward
Write-Host "`n[5/5] Informasi Akses AWX Web UI:" -ForegroundColor Yellow

$passwordSecret = "$AwxName-admin-password"
Write-Host "Untuk memeriksa status pod jalankan:" -ForegroundColor White
Write-Host "  kubectl -n $Namespace get pods -w" -ForegroundColor Cyan

Write-Host "`nSetelah pod '$AwxName-web' berstatus Running, jalankan port-forwarding:" -ForegroundColor White
Write-Host "  kubectl -n $Namespace port-forward svc/$AwxName-service $LocalPort:80" -ForegroundColor Cyan

Write-Host "`nUntuk mendapatkan password admin (setelah secret dibuat):" -ForegroundColor White
$psCmd = 'kubectl -n ' + $Namespace + ' get secret ' + $passwordSecret + ' -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }'
Write-Host "  $psCmd" -ForegroundColor Cyan

Write-Host "`nAkses Web UI di browser:" -ForegroundColor Green
Write-Host "  URL      : http://localhost:$LocalPort" -ForegroundColor Green
Write-Host "  Username : admin" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Deployment AWX selesai diinisialisasi!" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
