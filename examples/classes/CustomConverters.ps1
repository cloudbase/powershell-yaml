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
# Example custom type converters using PowerShell classes

using namespace PowerShellYaml
using namespace System
using namespace System.Collections.Generic

# Custom type: Semantic Version
class SemanticVersion {
    [int]$Major = 0
    [int]$Minor = 0
    [int]$Patch = 0
    [string]$PreRelease = ""

    [string] ToString() {
        $ver = "$($this.Major).$($this.Minor).$($this.Patch)"
        if ($this.PreRelease) {
            $ver += "-$($this.PreRelease)"
        }
        return $ver
    }
}

# Custom converter for SemanticVersion with !semver tag
class SemVerConverter : YamlConverter {
    [bool] CanHandle([string]$tag, [Type]$targetType) {
        # Handle !semver tag or when target type is SemanticVersion
        return $targetType -eq [SemanticVersion]
    }

    [object] ConvertFromYaml([object]$data, [string]$tag, [Type]$targetType) {
        $semver = [SemanticVersion]::new()

        if ($data -is [string]) {
            # Parse string format: "1.2.3" or "1.2.3-beta1"
            $parts = $data -split '-', 2
            $numbers = $parts[0] -split '\.'

            $semver.Major = [int]$numbers[0]
            if ($numbers.Length -gt 1) { $semver.Minor = [int]$numbers[1] }
            if ($numbers.Length -gt 2) { $semver.Patch = [int]$numbers[2] }
            if ($parts.Length -gt 1) { $semver.PreRelease = $parts[1] }
        }
        elseif ($data -is [System.Collections.Generic.Dictionary[string, object]]) {
            # Parse dictionary format: { major: 1, minor: 2, patch: 3, pre: "beta1" }
            if ($data.ContainsKey('major')) { $semver.Major = [int]$data['major'] }
            if ($data.ContainsKey('minor')) { $semver.Minor = [int]$data['minor'] }
            if ($data.ContainsKey('patch')) { $semver.Patch = [int]$data['patch'] }
            if ($data.ContainsKey('pre')) { $semver.PreRelease = [string]$data['pre'] }
        }

        return $semver
    }

    [object] ConvertToYaml([object]$value) {
        $semver = [SemanticVersion]$value
        # Return hashtable with Value and Tag
        return @{
            Value = $semver.ToString()
            Tag = '!semver'
        }
    }
}

# Custom DateTime converter that overrides standard timestamp handling
# Uses a specific format instead of ISO8601
class CustomDateTimeConverter : YamlConverter {
    [bool] CanHandle([string]$tag, [Type]$targetType) {
        # Handle our custom !datetime tag or when no tag and target is DateTime
        return $targetType -eq [DateTime]
    }

    [object] ConvertFromYaml([object]$data, [string]$tag, [Type]$targetType) {
        if ($data -is [string]) {
            # Parse custom format: "YYYY-MM-DD HH:mm:ss UTC"
            if ($data -match '^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) UTC$') {
                return [DateTime]::new(
                    [int]$Matches[1],  # Year
                    [int]$Matches[2],  # Month
                    [int]$Matches[3],  # Day
                    [int]$Matches[4],  # Hour
                    [int]$Matches[5],  # Minute
                    [int]$Matches[6],  # Second
                    [DateTimeKind]::Utc
                )
            }

            # Fallback to general parse
            return [DateTime]::Parse($data)
        }
        elseif ($data -is [System.Collections.Generic.Dictionary[string, object]]) {
            # Parse dictionary format
            $year = [int]$data['year']
            $month = [int]$data['month']
            $day = [int]$data['day']
            $hour = if ($data.ContainsKey('hour')) { [int]$data['hour'] } else { 0 }
            $minute = if ($data.ContainsKey('minute')) { [int]$data['minute'] } else { 0 }
            $second = if ($data.ContainsKey('second')) { [int]$data['second'] } else { 0 }

            return [DateTime]::new($year, $month, $day, $hour, $minute, $second, [DateTimeKind]::Utc)
        }

        throw [FormatException]::new("Invalid datetime format")
    }

    [object] ConvertToYaml([object]$value) {
        $dt = [DateTime]$value

        # Convert to UTC if not already
        if ($dt.Kind -ne [DateTimeKind]::Utc) {
            $dt = $dt.ToUniversalTime()
        }

        # Return hashtable with Value and Tag
        return @{
            Value = $dt.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
            Tag = '!datetime'
        }
    }
}

# Example config class using custom converters
class AppRelease : YamlBase {
    [string]$AppName = ""

    [YamlConverter("SemVerConverter")]
    [SemanticVersion]$Version = $null

    [YamlConverter("CustomDateTimeConverter")]
    [DateTime]$ReleaseDate = [DateTime]::MinValue

    [YamlConverter("CustomDateTimeConverter")]
    [DateTime]$BuildDate = [DateTime]::MinValue

    [string[]]$Features = @()
}
