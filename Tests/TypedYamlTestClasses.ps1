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
using namespace System.Collections.Generic

class SimpleConfig : YamlBase {
    [string]$Name
    [int]$Port = 8080
    [bool]$Enabled = $true

    [Dictionary[string, object]] ToDictionary() {
        $dict = [Dictionary[string, object]]::new()
        $dict['name'] = $this.Name
        $dict['port'] = $this.Port
        $dict['enabled'] = $this.Enabled
        return $dict
    }

    [void] FromDictionary([Dictionary[string, object]]$data) {
        if ($data.ContainsKey('name')) { $this.Name = [string]$data['name'] }
        if ($data.ContainsKey('port')) { $this.Port = [int]$data['port'] }
        if ($data.ContainsKey('enabled')) {
            # Handle both bool and string representations
            $val = $data['enabled']
            if ($val -is [bool]) {
                $this.Enabled = $val
            } else {
                $this.Enabled = [System.Convert]::ToBoolean($val)
            }
        }
    }
}

class DatabaseConfig : YamlBase {
    [string]$Host = 'localhost'
    [int]$Port = 5432
    [string]$Database
    [bool]$UseSsl = $true

    [Dictionary[string, object]] ToDictionary() {
        $dict = [Dictionary[string, object]]::new()
        $dict['host'] = $this.Host
        $dict['port'] = $this.Port
        $dict['database'] = $this.Database
        $dict['use-ssl'] = $this.UseSsl
        return $dict
    }

    [void] FromDictionary([Dictionary[string, object]]$data) {
        if ($data.ContainsKey('host')) { $this.Host = [string]$data['host'] }
        if ($data.ContainsKey('port')) { $this.Port = [int]$data['port'] }
        if ($data.ContainsKey('database')) { $this.Database = [string]$data['database'] }
        if ($data.ContainsKey('use-ssl')) {
            # Handle both bool and string representations
            $val = $data['use-ssl']
            if ($val -is [bool]) {
                $this.UseSsl = $val
            } else {
                $this.UseSsl = [System.Convert]::ToBoolean($val)
            }
        }
    }
}

class ComplexConfig : YamlBase {
    [string]$AppName
    [DatabaseConfig]$Database
    [string[]]$Tags = @()
    [int]$MaxConnections = 100

    [Dictionary[string, object]] ToDictionary() {
        $dict = [Dictionary[string, object]]::new()
        $dict['app-name'] = $this.AppName
        if ($this.Database) {
            # Return the YamlBase object itself, not its dictionary
            # This preserves metadata during serialization
            $dict['database'] = $this.Database
        }
        $dict['tags'] = $this.Tags
        $dict['max-connections'] = $this.MaxConnections
        return $dict
    }

    [void] FromDictionary([Dictionary[string, object]]$data) {
        if ($data.ContainsKey('app-name')) { $this.AppName = [string]$data['app-name'] }
        if ($data.ContainsKey('database')) {
            $this.Database = [DatabaseConfig]::new()
            $this.Database.FromDictionary($data['database'])
        }
        if ($data.ContainsKey('tags')) {
            $val = $data['tags']
            if ($val -eq $null) {
                $this.Tags = @()
            } else {
                $this.Tags = @($val)
            }
        }
        if ($data.ContainsKey('max-connections')) { $this.MaxConnections = [int]$data['max-connections'] }
    }
}

class SimpleConfigWithArray : YamlBase {
    [string]$Name
    [int]$Port = 8080
    [string[]]$Tags = @()

    [Dictionary[string, object]] ToDictionary() {
        $dict = [Dictionary[string, object]]::new()
        $dict['name'] = $this.Name
        $dict['port'] = $this.Port
        $dict['tags'] = $this.Tags
        return $dict
    }

    [void] FromDictionary([Dictionary[string, object]]$data) {
        if ($data.ContainsKey('name')) { $this.Name = [string]$data['name'] }
        if ($data.ContainsKey('port')) { $this.Port = [int]$data['port'] }
        if ($data.ContainsKey('tags')) {
            $val = $data['tags']
            if ($val -eq $null) {
                $this.Tags = @()
            } else {
                $this.Tags = @($val)
            }
        }
    }
}

class ServerInfo : YamlBase {
    [string]$Name
    [int]$Port

    [Dictionary[string, object]] ToDictionary() {
        $dict = [Dictionary[string, object]]::new()
        $dict['name'] = $this.Name
        $dict['port'] = $this.Port
        return $dict
    }

    [void] FromDictionary([Dictionary[string, object]]$data) {
        if ($data.ContainsKey('name')) { $this.Name = [string]$data['name'] }
        if ($data.ContainsKey('port')) { $this.Port = [int]$data['port'] }
    }
}

class ConfigWithServers : YamlBase {
    [ServerInfo[]]$Servers = @()
    [DatabaseConfig]$Database

    [Dictionary[string, object]] ToDictionary() {
        $dict = [Dictionary[string, object]]::new()
        $dict['servers'] = $this.Servers
        if ($this.Database) {
            $dict['database'] = $this.Database
        }
        return $dict
    }

    [void] FromDictionary([Dictionary[string, object]]$data) {
        if ($data.ContainsKey('servers')) {
            $val = $data['servers']
            if ($val -is [System.Collections.IList]) {
                $this.Servers = @($val | ForEach-Object {
                    $server = [ServerInfo]::new()
                    $server.FromDictionary($_)
                    $server
                })
            }
        }
        if ($data.ContainsKey('database')) {
            $this.Database = [DatabaseConfig]::new()
            $this.Database.FromDictionary($data['database'])
        }
    }
}
