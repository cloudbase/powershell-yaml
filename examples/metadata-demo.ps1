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
# Metadata Preservation Demo: Comments, Tags, and Scalar Styles

Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

# Load demo classes
. "$PSScriptRoot/classes/DemoClasses.ps1"

Write-Host "=== Metadata Preservation Demo ===" -ForegroundColor Cyan
Write-Host ""

# YAML with rich metadata: comments, tags, and different scalar styles
$yaml = @"
# Application configuration
app-name: "MyApp"
version: '1.0.0'
environment: production

# Database connection settings
database:
  host: db.example.com
  port: !!int 5432
  database: myapp_db
  username: app_user
  use-ssl: true

max-connections: !!int "100"
allowed-origins:
  - https://app.example.com
  - https://api.example.com
"@

Write-Host "Step 1: Deserialize YAML with metadata" -ForegroundColor Green
Write-Host "Source YAML:" -ForegroundColor Yellow
Write-Host $yaml
Write-Host ""

$config = $yaml | ConvertFrom-Yaml -As ([AppConfig])

Write-Host "Step 2: Inspect preserved metadata" -ForegroundColor Green
Write-Host "  Comment on 'AppName': '$($config.GetPropertyComment('AppName'))'" -ForegroundColor Cyan
Write-Host "  Comment on 'Database': '$($config.GetPropertyComment('Database'))'" -ForegroundColor Cyan
Write-Host "  Tag on 'MaxConnections': '$($config.GetPropertyTag('MaxConnections'))'" -ForegroundColor Cyan
Write-Host "  Scalar style on 'AppName': '$($config.GetPropertyScalarStyle('AppName'))'" -ForegroundColor Cyan
Write-Host "  Scalar style on 'Version': '$($config.GetPropertyScalarStyle('Version'))'" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 3: Modify values while preserving metadata" -ForegroundColor Green
$config.Environment = 'staging'
$config.MaxConnections = 150
Write-Host "  Changed Environment to 'staging'" -ForegroundColor Cyan
Write-Host "  Changed MaxConnections to 150" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 4: Serialize back with metadata preservation" -ForegroundColor Green
$newYaml = $config | ConvertTo-Yaml
Write-Host "Output YAML:" -ForegroundColor Yellow
Write-Host $newYaml
Write-Host ""

Write-Host "Step 5: Add new metadata programmatically" -ForegroundColor Green
$config.SetPropertyComment('Environment', 'Deployment environment')
$config.SetPropertyTag('MaxConnections', 'tag:yaml.org,2002:int')
$config.Database.SetPropertyComment('Host', 'Primary database server')

$newYaml2 = $config | ConvertTo-Yaml
Write-Host "YAML with added metadata:" -ForegroundColor Yellow
Write-Host $newYaml2
