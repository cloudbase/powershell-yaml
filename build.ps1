#!/usr/bin/env pwsh
# Copyright 2016-2026 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$Clean,

    [switch]$SkipTests,

    [switch]$IncludeSymbols,

    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

if ($Verbose) {
    $VerbosePreference = 'Continue'
}

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  PowerShell-YAML Build Script         " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration: $Configuration" -ForegroundColor Yellow
Write-Host ""

$root = $PSScriptRoot
$srcDir = Join-Path $root "src"
$libDir = Join-Path $root "lib"

# =====
# Clean
# =====

if ($Clean) {
    Write-Host "=== Cleaning Build Artifacts ===" -ForegroundColor Cyan

    # Clean .NET build outputs
    $cleanPaths = @(
        "$srcDir/obj",
        "$srcDir/bin",
        "$srcDir/*/obj",
        "$srcDir/*/bin",
        "$srcDir/*/*/obj",
        "$srcDir/*/*/bin"
    )

    foreach ($pattern in $cleanPaths) {
        Get-Item $pattern -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    }

    # Clean output directory
    if (Test-Path "$libDir/netstandard2.0") {
        Remove-Item "$libDir/netstandard2.0" -Recurse -Force
    }

    Write-Host "Clean complete" -ForegroundColor Green
    Write-Host ""
}

# ==============================
# Main Module (PowerShell 5.1+)
# ==============================

Write-Host "=== Building Main Module (netstandard2.0) ===" -ForegroundColor Cyan
Write-Host ""

# Build PowerShellYaml.Module.dll (netstandard2.0) - contains all serialization code
Write-Host "Building PowerShellYaml.Module.dll..." -ForegroundColor Yellow
Push-Location $srcDir
try {
    # Use publish to get all dependencies including YamlDotNet.dll
    dotnet publish PowerShellYaml.Module/PowerShellYaml.Module.csproj -c $Configuration -f netstandard2.0
    if ($LASTEXITCODE -ne 0) {
        throw "PowerShellYaml.Module build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# Copy module assemblies to lib/netstandard2.0
Write-Host "Copying module assemblies to lib/netstandard2.0..." -ForegroundColor Yellow
$netstandard2Dir = Join-Path $libDir "netstandard2.0"
if (!(Test-Path $netstandard2Dir)) {
    New-Item -Path $netstandard2Dir -ItemType Directory | Out-Null
}
$moduleSource = Join-Path $srcDir "PowerShellYaml.Module/bin/$Configuration/netstandard2.0/publish"
$assembliesToCopy = @(
    'PowerShellYaml.dll',
    'PowerShellYaml.Module.dll',
    'YamlDotNet.dll'
)

if ($IncludeSymbols) {
    $assembliesToCopy += @(
        'PowerShellYaml.pdb',
        'PowerShellYaml.Module.pdb'
    )
}

foreach ($assemblyName in $assembliesToCopy) {
    $sourcePath = Join-Path $moduleSource $assemblyName
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $netstandard2Dir -Force
        Write-Host "  ✓ $assemblyName" -ForegroundColor Gray
    } else {
        Write-Warning "  ⚠ $assemblyName not found at $sourcePath"
    }
}

Write-Host ""
Write-Host "Module build complete" -ForegroundColor Green
Write-Host ""

# ========
# Summary
# ========

Write-Host "=== Build Summary ===" -ForegroundColor Cyan
Write-Host ""

# Check all module outputs in lib/netstandard2.0
Write-Host "Module Assemblies (lib/netstandard2.0):" -ForegroundColor Yellow
$allRequired = @(
    'PowerShellYaml.dll',
    'PowerShellYaml.Module.dll',
    'YamlDotNet.dll'
)
$buildSuccess = $true
foreach ($dll in $allRequired) {
    $path = Join-Path $netstandard2Dir $dll
    if (Test-Path $path) {
        $size = (Get-Item $path).Length / 1KB
        Write-Host "  ✓ $dll ($([math]::Round($size, 1)) KB)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $dll (missing)" -ForegroundColor Red
        $buildSuccess = $false
    }
}

Write-Host ""

if (!$buildSuccess) {
    Write-Host "Build completed with errors" -ForegroundColor Red
    exit 1
}

Write-Host "✓ All assemblies built successfully" -ForegroundColor Green
Write-Host ""

# ==========
# Run Tests
# ==========

if (!$SkipTests) {
    Write-Host "=== Running Tests ===" -ForegroundColor Cyan
    Write-Host ""

    # Run all tests
    $testResult = Invoke-Pester ./Tests/*.Tests.ps1 -Output Normal -PassThru

    Write-Host ""
    if ($testResult.FailedCount -eq 0) {
        Write-Host "✓ All $($testResult.PassedCount) tests passed" -ForegroundColor Green
    } else {
        Write-Host "✗ $($testResult.FailedCount) tests failed" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# ==============
# Final Summary
# ==============

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Build Complete!                      " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Module Location:" -ForegroundColor Yellow
Write-Host "  $root" -ForegroundColor Gray
Write-Host ""
Write-Host "To use:" -ForegroundColor Yellow
Write-Host "  Import-Module $root/powershell-yaml.psd1" -ForegroundColor Cyan
