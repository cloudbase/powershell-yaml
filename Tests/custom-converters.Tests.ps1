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
# Tests for custom type converters

BeforeAll {
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

    # Define test classes
    . "$PSScriptRoot/../examples/classes/CustomConverters.ps1"
}

Describe "Custom Type Converters" {
    Context "Local tags (single !)" {
        It "Should deserialize !semver tag" {
            $yaml = @"
app-name: "LocalTagTest"
version: !semver "1.2.3"
release-date: !datetime "2024-01-15 10:30:00 UTC"
build-date: !datetime "2024-01-15 09:00:00 UTC"
features: ["feature1"]
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            $config.Version | Should -Not -BeNullOrEmpty
            $config.Version.Major | Should -Be 1
            $config.Version.Minor | Should -Be 2
            $config.Version.Patch | Should -Be 3
            $config.Version.PreRelease | Should -Be ""
        }

        It "Should deserialize !datetime tag" {
            $yaml = @"
app-name: "LocalTagTest"
version: !semver "1.0.0"
release-date: !datetime "2024-01-15 10:30:00 UTC"
build-date: !datetime "2024-01-15 09:00:00 UTC"
features: []
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            $config.ReleaseDate.Year | Should -Be 2024
            $config.ReleaseDate.Month | Should -Be 1
            $config.ReleaseDate.Day | Should -Be 15
            $config.ReleaseDate.Hour | Should -Be 10
            $config.ReleaseDate.Minute | Should -Be 30
        }
    }

    Context "Global tags (double !!)" {
        It "Should deserialize !!semver tag" {
            $yaml = @"
app-name: "GlobalTagTest"
version: !!semver "2.1.5-beta"
release-date: !!datetime "2024-02-20 14:45:30 UTC"
build-date: !!datetime "2024-02-20 12:00:00 UTC"
features: ["feature1", "feature2"]
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            $config.Version.Major | Should -Be 2
            $config.Version.Minor | Should -Be 1
            $config.Version.Patch | Should -Be 5
            $config.Version.PreRelease | Should -Be "beta"
        }
    }

    Context "Full URI tags" {
        It "Should deserialize full URI tags" {
            $yaml = @"
app-name: "URITagTest"
version: !<tag:example.com,2024:semver> "3.0.0"
release-date: !<tag:example.com,2024:datetime> "2024-03-25 16:20:45 UTC"
build-date: !<tag:example.com,2024:datetime> "2024-03-25 15:00:00 UTC"
features: ["advanced-feature"]
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            $config.Version.Major | Should -Be 3
            $config.Version.Minor | Should -Be 0
            $config.Version.Patch | Should -Be 0
        }
    }

    Context "Tag preservation in round-trip" {
        It "Should preserve !semver tag in serialization" {
            $yaml = @"
app-name: "RoundTripTest"
version: !semver "1.0.0"
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2023-12-31 20:00:00 UTC"
features: ["initial"]
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])
            $roundTripped = $config | ConvertTo-Yaml

            $roundTripped | Should -Match "!semver"
        }

        It "Should preserve !datetime tag in serialization" {
            $yaml = @"
app-name: "RoundTripTest"
version: !semver "1.0.0"
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2023-12-31 20:00:00 UTC"
features: []
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])
            $roundTripped = $config | ConvertTo-Yaml

            $roundTripped | Should -Match "!datetime"
        }
    }

    Context "Multiple input formats" {
        It "Should deserialize semver from string format" {
            $yaml = @"
app-name: "StringFormat"
version: !semver "2.1.5-beta3"
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2024-01-01 00:00:00 UTC"
features: []
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            $config.Version.ToString() | Should -Be "2.1.5-beta3"
        }

        It "Should deserialize semver from dictionary format" {
            $yaml = @"
app-name: "DictFormat"
version: !semver { major: 3, minor: 0, patch: 0, pre: "alpha1" }
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2024-01-01 00:00:00 UTC"
features: []
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            $config.Version.Major | Should -Be 3
            $config.Version.Minor | Should -Be 0
            $config.Version.Patch | Should -Be 0
            $config.Version.PreRelease | Should -Be "alpha1"
        }

        It "Should deserialize datetime from dictionary format" {
            $yaml = @"
app-name: "DictFormat"
version: !semver "1.0.0"
release-date: !datetime { year: 2025, month: 6, day: 1, hour: 12, minute: 0, second: 0 }
build-date: !datetime "2024-01-01 00:00:00 UTC"
features: []
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            $config.ReleaseDate.Year | Should -Be 2025
            $config.ReleaseDate.Month | Should -Be 6
            $config.ReleaseDate.Day | Should -Be 1
            $config.ReleaseDate.Hour | Should -Be 12
        }
    }

    Context "Error handling" {
        It "Should throw error for invalid semver format" {
            $yaml = @"
app-name: "ErrorTest"
version: !semver "not-a-valid-version"
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2024-01-01 00:00:00 UTC"
features: []
"@
            { $yaml | ConvertFrom-Yaml -As ([AppRelease]) } | Should -Throw
        }
    }

    Context "Converter registration with string type name" {
        It "Should find converter by string type name" {
            # This test verifies that [YamlConverter("SemVerConverter")] works
            # by resolving the type name to the actual type
            $yaml = @"
app-name: "StringTypeNameTest"
version: !semver "1.2.3"
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2024-01-01 00:00:00 UTC"
features: []
"@
            $config = $yaml | ConvertFrom-Yaml -As ([AppRelease])

            # If this succeeds, it means the string type name was resolved correctly
            $config.Version | Should -Not -BeNullOrEmpty
            $config.Version.Major | Should -Be 1
        }
    }
}
