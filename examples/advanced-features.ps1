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
# Advanced Features Demo: YamlKey, Nested Objects, Metadata

Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

# Load advanced config class
. "$PSScriptRoot/classes/AdvancedConfig.ps1"

Write-Host "=== Advanced Features Demo ===" -ForegroundColor Cyan
Write-Host ""

# YAML with case-sensitive keys, comments, and tags
$yaml = @"
# Service configuration
service-name: ApiGateway
api-version: v2.1

# Primary server endpoint
primary-endpoint:
  HTTP: http://api.example.com
  HTTPS: https://api.example.com
  port: !!int 443

# Backup endpoints for failover
backup-endpoints:
  - HTTP: http://backup1.example.com
    HTTPS: https://backup1.example.com
    port: 443
  - HTTP: http://backup2.example.com
    HTTPS: https://backup2.example.com
    port: 443

max-retry-count: !!int "5"
"@

Write-Host "Step 1: Deserialize YAML with advanced features" -ForegroundColor Green
Write-Host "Source YAML:" -ForegroundColor Yellow
Write-Host $yaml
Write-Host ""

$config = $yaml | ConvertFrom-Yaml -As ([AdvancedConfig])

Write-Host "Step 2: Access deserialized data" -ForegroundColor Green
Write-Host "  ServiceName: $($config.ServiceName)" -ForegroundColor Cyan
Write-Host "  ApiVersion: $($config.ApiVersion)" -ForegroundColor Cyan
Write-Host "  PrimaryEndpoint.HTTP: $($config.PrimaryEndpoint.HttpUrl)" -ForegroundColor Cyan
Write-Host "  PrimaryEndpoint.HTTPS: $($config.PrimaryEndpoint.HttpsUrl)" -ForegroundColor Cyan
Write-Host "  PrimaryEndpoint.Port: $($config.PrimaryEndpoint.Port)" -ForegroundColor Cyan
Write-Host "  BackupEndpoints.Count: $($config.BackupEndpoints.Count)" -ForegroundColor Cyan
Write-Host "  MaxRetries: $($config.MaxRetries)" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 3: Verify metadata preservation" -ForegroundColor Green
Write-Host "  Comment on ServiceName: '$($config.GetPropertyComment('ServiceName'))'" -ForegroundColor Cyan
Write-Host "  Comment on PrimaryEndpoint: '$($config.GetPropertyComment('PrimaryEndpoint'))'" -ForegroundColor Cyan
Write-Host "  Tag on MaxRetries: '$($config.GetPropertyTag('MaxRetries'))'" -ForegroundColor Cyan
Write-Host "  Tag on PrimaryEndpoint.Port: '$($config.PrimaryEndpoint.GetPropertyTag('Port'))'" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 4: Modify and serialize back" -ForegroundColor Green
$config.ServiceName = "UpdatedGateway"
$config.MaxRetries = 10
$config.BackupEndpoints[0].HttpsUrl = "https://new-backup1.example.com"

$newYaml = $config | ConvertTo-Yaml
Write-Host "Modified YAML:" -ForegroundColor Yellow
Write-Host $newYaml
Write-Host ""

Write-Host "Step 5: Verify case-sensitive keys preserved" -ForegroundColor Green
if ($newYaml -match 'HTTP:' -and $newYaml -match 'HTTPS:') {
    Write-Host "  ✓ Case-sensitive keys (HTTP/HTTPS) correctly preserved" -ForegroundColor Green
}
if ($newYaml -match 'max-retry-count:') {
    Write-Host "  ✓ Custom YAML key (max-retry-count) correctly used" -ForegroundColor Green
}
if ($newYaml -match 'service-name:') {
    Write-Host "  ✓ Auto-converted key (service-name) correctly used" -ForegroundColor Green
}
