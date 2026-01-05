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

# Advanced configuration class demonstrating:
# - YamlKey attribute for case-sensitive keys
# - Nested YamlBase objects
# - Arrays
# - Automatic property name conversion

class ServerEndpoint : YamlBase {
    # Case-sensitive YAML keys for different protocols
    [YamlKey("HTTP")]
    [string]$HttpUrl = ""

    [YamlKey("HTTPS")]
    [string]$HttpsUrl = ""

    # Normal property with auto-conversion (Port -> port)
    [int]$Port = 0
}

class AdvancedConfig : YamlBase {
    # Standard properties with auto-conversion
    [string]$ServiceName = ""
    [string]$ApiVersion = ""

    # Nested object
    [ServerEndpoint]$PrimaryEndpoint = $null

    # Array of nested objects
    [ServerEndpoint[]]$BackupEndpoints = @()

    # Property with custom YAML key
    [YamlKey("max-retry-count")]
    [int]$MaxRetries = 3
}
