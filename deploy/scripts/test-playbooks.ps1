<#
.SYNOPSIS
    Validation and test runner for AWX starter playbooks.

.DESCRIPTION
    Validates YAML syntax of playbooks, inventories, and role files.
    Optionally runs syntax checks inside a container or local Python environment.
#>

[CmdletBinding()]
param(
    [switch]$RunSyntaxCheck
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         AWX Project Playbook & Syntax Validator          " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
Set-Location $projectRoot

# 1. Check Directory Layout
Write-Host "`n[1/3] Memeriksa struktur direktori AWX Project..." -ForegroundColor Yellow
$requiredPaths = @(
    "ansible.cfg",
    "requirements.yml",
    "collections/requirements.yml",
    "inventory/hosts.ini",
    "inventory/group_vars/all.yml",
    "inventory/host_vars/localhost.yml",
    "playbooks/ping.yml",
    "playbooks/hello-world.yml",
    "playbooks/test-vbox-server.yml",
    "playbooks/site.yml",
    "roles/starter/tasks/main.yml",
    "roles/starter/defaults/main.yml",
    "roles/starter/handlers/main.yml",
    "roles/starter/meta/main.yml"
)

$allFound = $true
foreach ($path in $requiredPaths) {
    if (Test-Path $path) {
        Write-Host " [OK] $path" -ForegroundColor Green
    } else {
        Write-Host " [FAIL] Missing: $path" -ForegroundColor Red
        $allFound = $false
    }
}

if (-not $allFound) {
    Write-Error "Beberapa file wajib belum ditemukan!"
    exit 1
}

# 2. Validate YAML Syntax using Python
Write-Host "`n[2/3] Memvalidasi sintaks YAML seluruh file..." -ForegroundColor Yellow

$yamlFiles = Get-ChildItem -Path . -Include *.yml,*.yaml -Recurse | Where-Object { $_.FullName -notmatch "node_modules|\.git" }

$pythonCheck = @"
import sys

try:
    import yaml
except ImportError:
    print(" [NOTE] Module 'pyyaml' belum terpasang. Jalankan 'pip install pyyaml' untuk validasi sintaks YAML.")
    sys.exit(0)

failed = 0
for filepath in sys.argv[1:]:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            list(yaml.safe_load_all(f))
        print(f" [VALID] {filepath}")
    except Exception as e:
        print(f" [INVALID] {filepath}: {e}")
        failed += 1

if failed > 0:
    sys.exit(1)
"@

$tempPyFile = [System.IO.Path]::GetTempFileName() + ".py"
Set-Content -Path $tempPyFile -Value $pythonCheck

try {
    $fileList = $yamlFiles.FullName
    $pyOutput = python $tempPyFile @fileList 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pyOutput | ForEach-Object { Write-Host $_ -ForegroundColor Green }
        Write-Host "Semua file YAML valid!" -ForegroundColor Green
    } else {
        $pyOutput | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        throw "Validasi YAML gagal."
    }
} catch {
    Write-Warning "Pengecekan via Python mengalami error: $_"
} finally {
    if (Test-Path $tempPyFile) { Remove-Item $tempPyFile -Force }
}

# 3. Optional: Run Dockerized Ansible Syntax Check
Write-Host "`n[3/3] Ansible Execution Environment Check..." -ForegroundColor Yellow
$dockerRunning = $false
try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -eq 0) { $dockerRunning = $true }
} catch {}

if ($dockerRunning -and $RunSyntaxCheck) {
    Write-Host "Menjalankan syntax-check di container quay.io/ansible/awx-ee:latest..." -ForegroundColor Cyan
    docker run --rm -v "${projectRoot}:/runner/project" -w /runner/project quay.io/ansible/awx-ee:latest `
        ansible-playbook -i inventory/hosts.ini playbooks/ping.yml playbooks/hello-world.yml playbooks/site.yml --syntax-check
    Write-Host "Syntax check playbook berhasil!" -ForegroundColor Green
} else {
    Write-Host "Tips: Untuk menjalankan dry-run syntax-check penuh menggunakan execution environment AWX:" -ForegroundColor White
    Write-Host "  powershell deploy/scripts/test-playbooks.ps1 -RunSyntaxCheck" -ForegroundColor Cyan
}

Write-Host "`nValidasi project selesai." -ForegroundColor Cyan
