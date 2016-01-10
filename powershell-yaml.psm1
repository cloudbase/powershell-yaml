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
        $yamlStream = [YamlDotNet.RepresentationModel.YamlStream]::New("")
        $yamlStream.Load([System.IO.TextReader] $stringReader)
        $stringReader.Close()
        return $yamlStream
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
        $ret = @()
        foreach($i in $Node.Children){
            $ret += Convert-YamlDocumentToPSObject $i
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
                return $Node.Value
            }
        }
    }
}

function Convert-HashtableToDictionary {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [hashtable]$Data
    )
    $new = [System.Collections.Generic.Dictionary[string,object]]::New()
    foreach($i in $data.GetEnumerator()) {
        $new[$i.Name] = Convert-PSObjectToGenericObject $i.Value
    }
    return $new
}

function Convert-ListToGenericList {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [array]$Data
    )
    $new = [System.Collections.Generic.List[object]]::New()
    for($i=0; $i -lt $data.Count; $i++) {
        $obj = Convert-PSObjectToGenericObject $Data[$i]
        $new.Add($obj)
    }
    return $new
}

function Convert-PSCustomObjectToDictionary {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [PSCustomObject]$Data
    )
    $ret = [System.Collections.Generic.Dictionary[string,object]]::New()
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
    switch($data.GetType().FullName) {
        "System.Collections.Hashtable" {
            return Convert-HashtableToDictionary $data
        }
        "System.Collections.ArrayList" {
            return Convert-ListToGenericList $data
        }
        "System.Management.Automation.PSCustomObject" {
            return Convert-PSCustomObjectToDictionary
        }
        default {
            return $data
        }
    }
}

function ConvertFrom-Yaml {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Yaml,
        [switch]$AllDocuments=$false
    )
    PROCESS {
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.Object]$Data
    )
    PROCESS {
        $norm = Convert-PSObjectToGenericObject $Data
        $wrt = [System.IO.StringWriter]::new()
        $serializer = [YamlDotNet.Serialization.Serializer]::New()
        $serializer.Serialize($wrt, $norm)
        $wrt.Close()
        return $wrt.ToString()
    }
}