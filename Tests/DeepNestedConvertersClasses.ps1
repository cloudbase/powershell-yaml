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
# Test classes for deep nesting with custom converters

using namespace PowerShellYaml
using namespace System
using namespace System.Collections.Generic

# Custom type: IP Address (renamed to avoid conflict with System.Net.IPAddress)
class CustomIPAddress {
    [byte]$Octet1 = 0
    [byte]$Octet2 = 0
    [byte]$Octet3 = 0
    [byte]$Octet4 = 0

    CustomIPAddress() {
        $this.Octet1 = 0
        $this.Octet2 = 0
        $this.Octet3 = 0
        $this.Octet4 = 0
    }

    [string] ToString() {
        return "$($this.Octet1).$($this.Octet2).$($this.Octet3).$($this.Octet4)"
    }
}

# Custom converter for IP Address
class IPAddressConverter : YamlConverter {
    [bool] CanHandle([string]$tag, [Type]$targetType) {
        return $targetType -eq [CustomIPAddress]
    }

    [object] ConvertFromYaml([object]$data, [string]$tag, [Type]$targetType) {
        $ip = [CustomIPAddress]@{}

        if ($data -is [string]) {
            # Parse string format: "192.168.1.1"
            $octets = $data -split '\.'
            if ($octets.Length -ne 4) {
                throw [FormatException]::new("Invalid IP address format: $data")
            }
            $ip.Octet1 = [byte]$octets[0]
            $ip.Octet2 = [byte]$octets[1]
            $ip.Octet3 = [byte]$octets[2]
            $ip.Octet4 = [byte]$octets[3]
        }
        elseif ($data -is [System.Collections.Generic.Dictionary[string, object]]) {
            # Parse dictionary format
            if ($data.ContainsKey('a')) { $ip.Octet1 = [byte]$data['a'] }
            if ($data.ContainsKey('b')) { $ip.Octet2 = [byte]$data['b'] }
            if ($data.ContainsKey('c')) { $ip.Octet3 = [byte]$data['c'] }
            if ($data.ContainsKey('d')) { $ip.Octet4 = [byte]$data['d'] }
        }

        return $ip
    }

    [object] ConvertToYaml([object]$value) {
        $ip = [CustomIPAddress]$value
        return @{
            Value = $ip.ToString()
            Tag = '!ipaddr'
        }
    }
}

# Custom type: Duration (simple time span)
class Duration {
    [int]$Hours = 0
    [int]$Minutes = 0
    [int]$Seconds = 0

    Duration() {
        $this.Hours = 0
        $this.Minutes = 0
        $this.Seconds = 0
    }

    [string] ToString() {
        return "$($this.Hours)h$($this.Minutes)m$($this.Seconds)s"
    }
}

# Custom converter for Duration
class DurationConverter : YamlConverter {
    [bool] CanHandle([string]$tag, [Type]$targetType) {
        return $targetType -eq [Duration]
    }

    [object] ConvertFromYaml([object]$data, [string]$tag, [Type]$targetType) {
        $duration = [Duration]::new()

        if ($data -is [string]) {
            # Parse string format: "2h30m15s"
            if ($data -match '^(\d+)h(\d+)m(\d+)s$') {
                $duration.Hours = [int]$Matches[1]
                $duration.Minutes = [int]$Matches[2]
                $duration.Seconds = [int]$Matches[3]
            }
            else {
                throw [FormatException]::new("Invalid duration format: $data")
            }
        }
        elseif ($data -is [System.Collections.Generic.Dictionary[string, object]]) {
            if ($data.ContainsKey('hours')) { $duration.Hours = [int]$data['hours'] }
            if ($data.ContainsKey('minutes')) { $duration.Minutes = [int]$data['minutes'] }
            if ($data.ContainsKey('seconds')) { $duration.Seconds = [int]$data['seconds'] }
        }

        return $duration
    }

    [object] ConvertToYaml([object]$value) {
        $duration = [Duration]$value
        return @{
            Value = $duration.ToString()
            Tag = '!duration'
        }
    }
}

# Level 3: Server configuration (deepest level with converters)
class ServerConfig : YamlBase {
    [string]$Hostname = ""

    [YamlConverter("IPAddressConverter")]
    [CustomIPAddress]$Address = $null

    [int]$Port = 0

    [YamlConverter("DurationConverter")]
    [Duration]$Timeout = $null
}

# Level 2: Database configuration (middle level with converters)
class DatabaseConfig : YamlBase {
    [string]$Name = ""

    [YamlConverter("IPAddressConverter")]
    [CustomIPAddress]$Host = $null

    [int]$Port = 0

    [ServerConfig]$PrimaryServer = $null
    [ServerConfig]$ReplicaServer = $null

    [YamlConverter("DurationConverter")]
    [Duration]$ConnectionTimeout = $null
}

# Level 1: Application configuration (top level)
class ApplicationConfig : YamlBase {
    [string]$AppName = ""
    [string]$Environment = ""

    [DatabaseConfig]$Database = $null

    [YamlConverter("IPAddressConverter")]
    [CustomIPAddress]$ApiGateway = $null

    [YamlConverter("DurationConverter")]
    [Duration]$RequestTimeout = $null
}
