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

# Test class demonstrating YamlKey attribute for case-sensitive YAML keys
# PowerShell class properties are case-insensitive, so we need the attribute
# to distinguish between "Test" and "test" in the YAML
class CaseSensitiveTest : YamlBase {
    [YamlKey("Test")]
    [string]$CapitalizedTest = ""

    [YamlKey("test")]
    [int]$LowercaseTest = 0
}

# Test class with mixed attribute and auto-conversion
class MixedKeysTest : YamlBase {
    # Uses attribute
    [YamlKey("custom-key")]
    [string]$CustomProperty = ""

    # Uses automatic PascalCase -> hyphenated-case conversion
    [int]$AutoConvertedKey = 0
}

# Test class that will fail due to duplicate key without explicit mapping
class IWillFailDueToDuplicateKey : YamlBase {
    [string]$test = ""
}

# Test class that succeeds because all duplicate keys are explicitly mapped
class IWillSucceedBecauseIHaveAMappedKey : YamlBase {
    [YamlKey("test")]
    [string]$test = ""

    [YamlKey("Test")]
    [string]$alsoTestButUppercase = ""
}
