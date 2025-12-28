#!/usr/bin/env pwsh
# Typed YAML Demo: Comprehensive Introduction
# This demo showcases PowerShell YAML typed class features
Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

Write-Host "=== PowerShell YAML - Typed Class Demo ===" -ForegroundColor Cyan
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
Write-Host ""

# Import the module
# Write-Host "Step 1: Import PowerShell YAML module" -ForegroundColor Green
# Import-Module ./powershell-yaml.psd1 -Force

# Verify YamlBase is available
Write-Host "  YamlBase type available: $([PowerShellYaml.YamlBase] -ne $null)" -ForegroundColor Cyan
Write-Host ""

# Load demo classes
Write-Host "Step 2: Load configuration classes" -ForegroundColor Green
. "$PSScriptRoot/classes/DemoClasses.ps1"
Write-Host "  Loaded: DatabaseConfig, AppConfig" -ForegroundColor Cyan
Write-Host ""

# Demonstrate deserialization
Write-Host "Step 3: Deserialize YAML to typed objects" -ForegroundColor Green
$yaml = @"
app-name: MyAwesomeApp
version: 2.0.0
environment: production
database:
  # host is the address for the DB
  host: db.example.com
  port: !!int 5432
  database: !!str myapp_prod
  username: app_user
  use-ssl: true
max-connections: 200
allowed-origins:
  - https://app.example.com
  - https://admin.example.com
"@

Write-Host "  Source YAML:" -ForegroundColor Yellow
Write-Host $yaml
Write-Host ""

$config = ConvertFrom-Yaml -Yaml $yaml -As ([AppConfig])

Write-Host "  Deserialized object:" -ForegroundColor Yellow
Write-Host "    AppName: $($config.AppName)" -ForegroundColor Cyan
Write-Host "    Version: $($config.Version)" -ForegroundColor Cyan
Write-Host "    Environment: $($config.Environment)" -ForegroundColor Cyan
Write-Host "    Database.Host: $($config.Database.Host)" -ForegroundColor Cyan
Write-Host "    Database.Port: $($config.Database.Port)" -ForegroundColor Cyan
Write-Host "    Database.UseSsl: $($config.Database.UseSsl)" -ForegroundColor Cyan
Write-Host "    MaxConnections: $($config.MaxConnections)" -ForegroundColor Cyan
Write-Host "    AllowedOrigins: $($config.AllowedOrigins -join ', ')" -ForegroundColor Cyan
Write-Host ""

# Verify type safety
Write-Host "Step 4: Verify type safety" -ForegroundColor Green
Write-Host "  config is [AppConfig]: $($config -is [AppConfig])" -ForegroundColor Cyan
Write-Host "  config is [YamlBase]: $($config -is [PowerShellYaml.YamlBase])" -ForegroundColor Cyan
Write-Host "  config.Database is [DatabaseConfig]: $($config.Database -is [DatabaseConfig])" -ForegroundColor Cyan
Write-Host ""

# Modify and serialize
Write-Host "Step 5: Modify configuration and serialize back to YAML" -ForegroundColor Green
$config.Environment = 'staging'
$config.MaxConnections = 150
$config.AllowedOrigins += 'https://staging.example.com'
$config.Database.Port = 5433

$outputYaml = ConvertTo-Yaml $config

Write-Host "  Modified YAML:" -ForegroundColor Yellow
Write-Host $outputYaml
Write-Host ""

# Round-trip test
Write-Host "Step 6: Round-trip verification" -ForegroundColor Green
$config2 = ConvertFrom-Yaml -Yaml $outputYaml -As ([AppConfig])

Write-Host "  Environment preserved: $($config2.Environment -eq 'staging')" -ForegroundColor Cyan
Write-Host "  MaxConnections preserved: $($config2.MaxConnections -eq 150)" -ForegroundColor Cyan
Write-Host "  Database.Port preserved: $($config2.Database.Port -eq 5433)" -ForegroundColor Cyan
Write-Host "  AllowedOrigins count: $($config2.AllowedOrigins.Count)" -ForegroundColor Cyan
Write-Host ""

# Demonstrate nested object serialization
Write-Host "Step 7: Create configuration from scratch" -ForegroundColor Green
$newConfig = [AppConfig]::new()
$newConfig.AppName = 'TestApp'
$newConfig.Version = '1.0.0'
$newConfig.Environment = 'development'
$newConfig.Database = [DatabaseConfig]::new()
$newConfig.Database.Host = 'localhost'
$newConfig.Database.Database = 'test_db'
$newConfig.Database.Username = 'test_user'
$newConfig.AllowedOrigins = @('http://localhost:3000', 'http://localhost:8080')

$newYaml = ConvertTo-Yaml $newConfig

Write-Host "  Generated YAML from new object:" -ForegroundColor Yellow
Write-Host $newYaml
Write-Host ""
