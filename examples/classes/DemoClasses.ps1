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

using namespace PowerShellYaml

# Simple demo classes using the default YamlBase implementations
# No need to implement ToDictionary/FromDictionary - they're handled automatically!
# Property names are automatically converted: PascalCase -> hyphenated-case

class DatabaseConfig : YamlBase {
    [string]$Host = 'localhost'
    [int]$Port = 5432
    [string]$Database = ''
    [string]$Username = ''
    [bool]$UseSsl = $true
}

class AppConfig : YamlBase {
    [string]$AppName = ''
    [string]$Version = ''
    [string]$Environment = 'development'
    [DatabaseConfig]$Database = $null
    [int]$MaxConnections = 100
    [string[]]$AllowedOrigins = @()
}
