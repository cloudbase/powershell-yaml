# Copyright 2016 Cloudbase Solutions Srl
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

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir = Join-Path $here "lib"

function ServerLevelKey {
    <#
    .SYNOPSIS
    Returns the path to the registry location where information about the server levels is stored
    #>
    PROCESS {
        return "HKLM:Software\Microsoft\Windows NT\CurrentVersion\Server\ServerLevels"
    }
}

function IsNanoServer {
    <#
    .SYNOPSIS
    Return a boolean value of $true if we are running on a Nano server version.
    #>
    PROCESS {
        $serverLevelKey = ServerLevelKey
        if (!(Test-Path $serverLevelKey)){
            # We are most likely running on a workstation version
            return $false
        }
        $serverLevels = Get-ItemProperty $serverLevelKey
        return ($serverLevels.NanoServer -eq 1)
    }
}

function Initialize-Assemblies {
    $isNano = IsNanoServer
    $assemblyDir = Join-Path $libDir "net35"
    if($isNano){
        # Load the portable assembly
        $assemblyDir = Join-Path $libDir "net45"
    }
    $assemblyFile = Join-Path $assemblyDir "YamlDotNet.dll"
    try {
        [YamlDotNet.Serialization.Serializer] | Out-Null
    } catch [System.Management.Automation.RuntimeException] {
        if(!(Test-Path $assemblyFile)) {
            Throw "Could not find YamlDotNet assembly on the system"
        }
        if($isNano){
            return [Microsoft.PowerShell.CoreCLR.AssemblyExtensions]::LoadFrom($assemblyFile)
        }
        return [Reflection.Assembly]::LoadFrom($assemblyFile)
    }
}

Initialize-Assemblies | Out-Null
