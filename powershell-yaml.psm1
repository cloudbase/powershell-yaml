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

function Get-YamlDocuments {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Yaml
    )
    PROCESS {
        $stringReader = new-object System.IO.StringReader($Yaml)
        $yamlStream = New-Object "YamlDotNet.RepresentationModel.YamlStream"
        $yamlStream.Load([System.IO.TextReader] $stringReader)
        $stringReader.Close()
        return $yamlStream
    }
}

function Convert-ValueToProperType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.Object]$Value
    )
    PROCESS {
        if (!($Value -is [string])) {
            return $Value
        }
        $types = @([int], [long], [double], [boolean], [datetime])
        foreach($i in $types){
            try {
                return $i::Parse($Value)
            } catch {
                continue
            }
        }
        return $Value
    }
}

function Convert-YamlMappingToHashtable {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [YamlDotNet.RepresentationModel.YamlMappingNode]$Node
    )
    PROCESS {
        $ret = @{}
        foreach($i in $Node.Children.Keys) {
            $ret[$i.Value] = Convert-YamlDocumentToPSObject $Node.Children[$i]
        }
        return $ret
    }
}

function Convert-YamlSequenceToArray {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [YamlDotNet.RepresentationModel.YamlSequenceNode]$Node
    )
    PROCESS {
        $ret = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
        foreach($i in $Node.Children){
            $ret.Add((Convert-YamlDocumentToPSObject $i))
        }
        return $ret
    }
}

function Convert-YamlDocumentToPSObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [System.Object]$Node
    )
    PROCESS {
        switch($Node.GetType().FullName){
            "YamlDotNet.RepresentationModel.YamlMappingNode"{
                return Convert-YamlMappingToHashtable $Node
            }
            "YamlDotNet.RepresentationModel.YamlSequenceNode" {
                return Convert-YamlSequenceToArray $Node
            }
            "YamlDotNet.RepresentationModel.YamlScalarNode" {
                return (Convert-ValueToProperType $Node.Value)
            }
        }
    }
}

function Convert-HashtableToDictionary {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [hashtable]$Data
    )
    foreach($i in $($data.Keys)) {
        $Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
    }
    return $Data
}

function Convert-ListToGenericList {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [array]$Data
    )
    for($i=0; $i -lt $Data.Count; $i++) {
        $Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
    }
    return $Data
}

function Convert-PSCustomObjectToDictionary {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [PSCustomObject]$Data
    )
    $ret = [System.Collections.Generic.Dictionary[string,object]](New-Object 'System.Collections.Generic.Dictionary[string,object]')
    foreach ($i in $Data.psobject.properties) {
        $ret[$i.Name] = Convert-PSObjectToGenericObject $i.Value
    }
    return $ret
}

function Convert-PSObjectToGenericObject {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.Object]$Data
    )
    # explicitly cast object to its type. Without this, it gets wrapped inside a powershell object
    # which causes YamlDotNet to fail
    $data = $data -as $data.GetType().FullName
    switch($data.GetType()) {
        ($_.FullName -eq "System.Management.Automation.PSCustomObject") {
            return Convert-PSCustomObjectToDictionary
        }
        default {
            if (([System.Collections.IDictionary].IsAssignableFrom($_))){
                return Convert-HashtableToDictionary $data
            } elseif (([System.Collections.IList].IsAssignableFrom($_))) {
                return Convert-ListToGenericList $data
            }
            return $data
        }
    }
}

function ConvertFrom-Yaml {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
        [string]$Yaml,
        [switch]$AllDocuments=$false
    )
    PROCESS {
        if(!$Yaml){
            return
        }
        $documents = Get-YamlDocuments -Yaml $Yaml
        if (!$documents.Count) {
            return
        }
        if($documents.Count -eq 1){
            return Convert-YamlDocumentToPSObject $documents[0].RootNode
        }
        if(!$AllDocuments) {
            return Convert-YamlDocumentToPSObject $documents[0].RootNode
        }
        $ret = @()
        foreach($i in $documents) {
            $ret += Convert-YamlDocumentToPSObject $i.RootNode
        }
        return $ret
    }
}

function ConvertTo-Yaml {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
        [System.Object]$Data,
        [Parameter(Mandatory=$false)]
        [string]$OutFile,
        [switch]$Force=$false
    )
    BEGIN {
        $d = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
    }
    PROCESS {
        $d.Add($data)
    }
    END {
        if(!$d){
            return
        }
        $norm = Convert-PSObjectToGenericObject $d
        if($OutFile) {
            $parent = Split-Path $OutFile
            if(!(Test-Path $parent)) {
                Throw "Parent folder for specified path does not exist"
            }
            if((Test-Path $OutFile) -and !$Force){
                Throw "Target file already exists. Use -Force to overwrite."
            }
            $wrt = New-Object "System.IO.StreamWriter" $OutFile
        } else {
            $wrt = New-Object "System.IO.StringWriter"
        }
        try {
            $serializer = New-Object "YamlDotNet.Serialization.Serializer" 0
            $serializer.Serialize($wrt, $norm)
        } finally {
            $wrt.Close()
        }
        if($OutFile){
            return
        }else {
            return $wrt.ToString()
        }
    }
}

Export-ModuleMember -Function * -Alias *
