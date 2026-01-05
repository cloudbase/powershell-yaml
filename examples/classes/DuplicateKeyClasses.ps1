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

# Example class without YamlKey attributes - will fail with duplicate keys
class ConfigWithoutMapping : YamlBase {
    [string]$test = ""
}

# Example class with explicit YamlKey attributes for duplicate keys
class ConfigWithMapping : YamlBase {
    [YamlKey("test")]
    [string]$LowercaseValue = ""

    [YamlKey("Test")]
    [string]$CapitalizedValue = ""
}

# Example class demonstrating three case variations
class ThreeVariations : YamlBase {
    [YamlKey("test")]
    [string]$Lower = ""

    [YamlKey("Test")]
    [string]$Capital = ""

    [YamlKey("TEST")]
    [string]$Upper = ""
}
