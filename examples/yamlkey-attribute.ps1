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
# Example: Using YamlKey attribute for case-sensitive YAML keys

Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

# PowerShell class properties are case-insensitive, but YAML keys can be case-sensitive.
# Use the [YamlKey] attribute to map different YAML keys to different properties.

# Load the class definition
. "$PSScriptRoot/classes/ServerConfig.ps1"

# YAML with case-sensitive keys
$yaml = @"
Host: primary.example.com
host: backup.example.com
port: 8080
"@

Write-Host "Input YAML:"
Write-Host $yaml
Write-Host ""

# Deserialize
$config = $yaml | ConvertFrom-Yaml -As ([ServerConfig])

Write-Host "Deserialized values:"
Write-Host "  PrimaryHost (from 'Host'): $($config.PrimaryHost)"
Write-Host "  BackupHost (from 'host'): $($config.BackupHost)"
Write-Host "  Port: $($config.Port)"
Write-Host ""

# Modify and serialize back
$config.PrimaryHost = "new-primary.example.com"
$config.BackupHost = "new-backup.example.com"
$config.Port = 9090

$newYaml = $config | ConvertTo-Yaml

Write-Host "Serialized YAML:"
Write-Host $newYaml
