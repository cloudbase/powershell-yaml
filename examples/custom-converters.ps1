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
# Custom Type Converters Demo: Extending YAML with custom types

Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

# Load custom converters
. "$PSScriptRoot/classes/CustomConverters.ps1"

Write-Host "=== Custom Type Converters Demo ===" -ForegroundColor Cyan
Write-Host ""

# Example 1: Custom tag for semantic versioning
Write-Host "Example 1: Custom !semver tag" -ForegroundColor Yellow
Write-Host "--------------------------------------"
Write-Host ""

$yaml1 = @"
app-name: MyAwesomeApp
version: !semver "2.1.5-beta3"
release-date: !datetime "2024-12-15 14:30:00 UTC"
build-date: !datetime "2024-12-15 10:00:00 UTC"
features:
  - New user interface
  - Performance improvements
  - Bug fixes
"@

Write-Host "Input YAML with custom tags:"
Write-Host $yaml1 -ForegroundColor Gray
Write-Host ""

$release = $yaml1 | ConvertFrom-Yaml -As ([AppRelease])

Write-Host "Deserialized values:"
Write-Host "  App Name: $($release.AppName)"
Write-Host "  Version: $($release.Version) (Type: $($release.Version.GetType().Name))"
Write-Host "    - Major: $($release.Version.Major)"
Write-Host "    - Minor: $($release.Version.Minor)"
Write-Host "    - Patch: $($release.Version.Patch)"
Write-Host "    - PreRelease: $($release.Version.PreRelease)"
Write-Host "  Release Date: $($release.ReleaseDate) (Type: $($release.ReleaseDate.GetType().Name))"
Write-Host "  Build Date: $($release.BuildDate)"
Write-Host "  Features: $($release.Features.Count) items"
Write-Host ""

# Modify and serialize back
$release.Version.Patch = 6
$release.Version.PreRelease = "rc1"
$release.ReleaseDate = [DateTime]::new(2025, 1, 15, 9, 0, 0, [DateTimeKind]::Utc)

$newYaml = $release | ConvertTo-Yaml

Write-Host "Modified and serialized back:"
Write-Host $newYaml -ForegroundColor Green
Write-Host ""

# Example 2: Different input formats with same converter
Write-Host "Example 2: Flexible input formats" -ForegroundColor Yellow
Write-Host "--------------------------------------"
Write-Host ""

$yaml2 = @"
app-name: FlexibleApp
version: !semver { major: 3, minor: 0, patch: 0, pre: "alpha1" }
release-date: !datetime { year: 2025, month: 6, day: 1, hour: 12, minute: 0, second: 0 }
build-date: !datetime "2025-05-30 18:45:30 UTC"
features:
  - Advanced configuration
"@

Write-Host "Input YAML with dictionary format for version:"
Write-Host $yaml2 -ForegroundColor Gray
Write-Host ""

$release2 = $yaml2 | ConvertFrom-Yaml -As ([AppRelease])

Write-Host "Deserialized values:"
Write-Host "  Version: $($release2.Version)"
Write-Host "  Release Date: $($release2.ReleaseDate)"
Write-Host ""

# Example 3: Round-trip preservation
Write-Host "Example 3: Round-trip with tag preservation" -ForegroundColor Yellow
Write-Host "--------------------------------------"
Write-Host ""

$yaml3 = @"
app-name: RoundTripTest
version: !semver "1.0.0"
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2023-12-31 20:00:00 UTC"
features:
  - Initial release
"@

$release3 = $yaml3 | ConvertFrom-Yaml -As ([AppRelease])
$roundTripped = $release3 | ConvertTo-Yaml

Write-Host "Original YAML:"
Write-Host $yaml3 -ForegroundColor Gray
Write-Host ""

Write-Host "Round-tripped YAML:"
Write-Host $roundTripped -ForegroundColor Green
Write-Host ""

# Example 4: Error handling - invalid format
Write-Host "Example 4: Error handling" -ForegroundColor Yellow
Write-Host "--------------------------------------"
Write-Host ""

$invalidYaml = @"
app-name: ErrorTest
version: !semver "not-a-valid-version"
release-date: !datetime "2024-01-01 00:00:00 UTC"
build-date: !datetime "2024-01-01 00:00:00 UTC"
features: []
"@

Write-Host "Attempting to parse invalid version format:"
Write-Host $invalidYaml -ForegroundColor Gray
Write-Host ""

try {
    $invalidRelease = $invalidYaml | ConvertFrom-Yaml -As ([AppRelease])
    Write-Host "Parsed successfully (converter handled gracefully)" -ForegroundColor Green
    Write-Host "  Version: $($invalidRelease.Version)"
} catch {
    Write-Host "✓ Error caught as expected:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
}
