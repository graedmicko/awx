<#
.SYNOPSIS
    Verification script for VirtualBox target server (192.168.56.103).

.DESCRIPTION
    Tests network & SSH reachability to 192.168.56.103:22,
    validates the test playbook syntax, and displays quick setup parameters for AWX.
#>

[CmdletBinding()]
param(
    [string]$TargetIP = "192.168.56.103",
    [int]$Port = 22,
    [string]$Username = "okta"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     VirtualBox Server Connectivity & AWX Verification    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Test TCP Port 22
Write-Host "`n[1/3] Menguji konektivitas TCP Port $Port ke $TargetIP..." -ForegroundColor Yellow
$tcpTest = Test-NetConnection -ComputerName $TargetIP -Port $Port -WarningAction SilentlyContinue

if ($tcpTest.TcpTestSucceeded) {
    Write-Host " [OK] Port $Port ($TargetIP) terbuka dan merespon!" -ForegroundColor Green
    Write-Host "      Interface : $($tcpTest.InterfaceAlias)" -ForegroundColor DarkGray
    Write-Host "      Source IP : $($tcpTest.SourceAddress)" -ForegroundColor DarkGray
} else {
    Write-Host " [FAIL] Tidak dapat terhubung ke ${TargetIP}:${Port}." -ForegroundColor Red
    Write-Warning "Pastikan Virtual Machine di VirtualBox dalam kondisi Running dan adapter Host-Only aktif."
    exit 1
}

# 2. Validate test-vbox-server.yml playbook syntax
Write-Host "`n[2/3] Memvalidasi sintaks playbook 'playbooks/test-vbox-server.yml'..." -ForegroundColor Yellow
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$playbookPath = Join-Path $projectRoot "playbooks\test-vbox-server.yml"

if (Test-Path $playbookPath) {
    try {
        $checkPy = @"
import sys, yaml
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    list(yaml.safe_load_all(f))
print('Sintaks YAML valid!')
"@
        $tempPy = [System.IO.Path]::GetTempFileName() + ".py"
        Set-Content -Path $tempPy -Value $checkPy
        python $tempPy $playbookPath
        Remove-Item $tempPy -Force
        Write-Host " [OK] File playbooks/test-vbox-server.yml siap digunakan." -ForegroundColor Green
    } catch {
        Write-Warning "Validasi Python: $_"
    }
} else {
    Write-Host " [FAIL] File $playbookPath tidak ditemukan!" -ForegroundColor Red
    exit 1
}

# 3. AWX Configuration Summary & CLI Quick Test
Write-Host "`n[3/3] Parameter Konfigurasi AWX Web UI:" -ForegroundColor Yellow
Write-Host "  --------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  1. Kredensial AWX (Menu Credentials -> Add):" -ForegroundColor White
Write-Host "     - Credential Type : Machine" -ForegroundColor Cyan
Write-Host "     - Username        : $Username" -ForegroundColor Cyan
Write-Host "     - Password        : 123" -ForegroundColor Cyan
Write-Host "     - Privilege Escalation: sudo" -ForegroundColor Cyan
Write-Host "     - Escalation Password : 123" -ForegroundColor Cyan

Write-Host "`n  2. Target Host AWX (Menu Inventories -> Hosts -> Add):" -ForegroundColor White
Write-Host "     - Host Name       : $TargetIP" -ForegroundColor Cyan

Write-Host "`n  3. Job Template AWX (Menu Templates -> Add):" -ForegroundColor White
Write-Host "     - Playbook        : playbooks/test-vbox-server.yml" -ForegroundColor Cyan
Write-Host "     - Credentials     : (Pilih kredensial di atas)" -ForegroundColor Cyan
Write-Host "  --------------------------------------------------------" -ForegroundColor DarkGray

Write-Host "`nUntuk tes login SSH manual via terminal PowerShell:" -ForegroundColor White
Write-Host "  ssh $Username@$TargetIP" -ForegroundColor Yellow

Write-Host "`nSelesai." -ForegroundColor Cyan
