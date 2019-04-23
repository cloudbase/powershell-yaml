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

function Load-Assembly {
    $libDir = Join-Path $here "lib"
    $assemblies = @{
        "core" = Join-Path $libDir "netstandard1.3\YamlDotNet.dll";
        "net45" = Join-Path $libDir "net45\YamlDotNet.dll";
        "net35" = Join-Path $libDir "net35\YamlDotNet.dll";
    }

    if ($PSVersionTable.PSEdition -eq "Core") {
        return [Reflection.Assembly]::LoadFrom($assemblies["core"])
    } elseif ($PSVersionTable.PSVersion.Major -ge 4) {
        return [Reflection.Assembly]::LoadFrom($assemblies["net45"])
    } else {
        return [Reflection.Assembly]::LoadFrom($assemblies["net35"])
    }
}


function Initialize-Assemblies {
    $requiredTypes = @(
        "Parser", "MergingParser", "YamlStream",
        "YamlMappingNode", "YamlSequenceNode",
        "YamlScalarNode", "ChainedEventEmitter",
        "Serializer", "Deserializer", "SerializerBuilder",
        "StaticTypeResolver"
    )

    $yaml = [System.AppDomain]::CurrentDomain.GetAssemblies() | ? Location -Match "YamlDotNet.dll"
    if (!$yaml) {
        return Load-Assembly
    }

    foreach ($i in $requiredTypes){
        if ($i -notin $yaml.DefinedTypes.Name) {
            Throw "YamlDotNet is loaded but missing required types ($i). Older version installed on system?"
        }
    }
}

Initialize-Assemblies | Out-Null
