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
$assemblies = Join-Path $here "Load-Assemblies.ps1"

if (Test-Path $assemblies) {
    . $here\Load-Assemblies.ps1
}

function Get-YamlDocuments {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Yaml,
        [switch]$UseMergingParser=$false
    )
    PROCESS {
        $stringReader = new-object System.IO.StringReader($Yaml)
        $parser = New-Object "YamlDotNet.Core.Parser" $stringReader
        if($UseMergingParser) {
            $parser = New-Object "YamlDotNet.Core.MergingParser" $parser
        }

        $yamlStream = New-Object "YamlDotNet.RepresentationModel.YamlStream"
        $yamlStream.Load([YamlDotNet.Core.IParser] $parser)

        $stringReader.Close()

        return $yamlStream
    }
}

function Convert-ValueToProperType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.Object]$Node
    )
    PROCESS {
        if (!($Node.Value -is [string])) {
            return $Node
        }
        
        if ($Node.Style -eq 'Plain')
        {
            $types = @([int], [long], [double], [boolean], [decimal])
            foreach($i in $types){
                $parsedValue = New-Object -TypeName $i.FullName
                if ($i.IsAssignableFrom([boolean])){
                    $result = $i::TryParse($Node,[ref]$parsedValue) 
                } else {
                    $result = $i::TryParse($Node, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)
                }
                if( $result ) {
                    return $parsedValue
                }
            }
        }
        # From the YAML spec: http://yaml.org/type/timestamp.html
        $regex = @'
[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] # (ymd)
|[0-9][0-9][0-9][0-9] # (year)
 -[0-9][0-9]? # (month)
 -[0-9][0-9]? # (day)
 ([Tt]|[ \t]+)[0-9][0-9]? # (hour)
 :[0-9][0-9] # (minute)
 :[0-9][0-9] # (second)
 (\.[0-9]*)? # (fraction)
 (([ \t]*)Z|[-+][0-9][0-9]?(:[0-9][0-9])?)? # (time zone)
'@
        if([Text.RegularExpressions.Regex]::IsMatch($Node.Value, $regex, [Text.RegularExpressions.RegexOptions]::IgnorePatternWhitespace) ) {
            [DateTime]$datetime = [DateTime]::MinValue
            if( ([DateTime]::TryParse($Node.Value,[ref]$datetime)) ) {
                return $datetime
            }
        }
            
        return $Node.Value
    }
}

function Convert-YamlMappingToHashtable {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [YamlDotNet.RepresentationModel.YamlMappingNode]$Node,
        [switch] $Ordered
    )
    PROCESS {
        if ($Ordered) { $ret = [ordered]@{} } else { $ret = @{} }
        foreach($i in $Node.Children.Keys) {
            $ret[$i.Value] = Convert-YamlDocumentToPSObject $Node.Children[$i] -Ordered:$Ordered
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
        return ,$ret
    }
}

function Convert-YamlDocumentToPSObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [System.Object]$Node, 
        [switch]$Ordered
    )
    PROCESS {
        switch($Node.GetType().FullName){
            "YamlDotNet.RepresentationModel.YamlMappingNode"{
                return Convert-YamlMappingToHashtable $Node -Ordered:$Ordered
            }
            "YamlDotNet.RepresentationModel.YamlSequenceNode" {
                return Convert-YamlSequenceToArray $Node
            }
            "YamlDotNet.RepresentationModel.YamlScalarNode" {
                return (Convert-ValueToProperType $Node)
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

function Convert-OrderedHashtableToDictionary {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.Collections.Specialized.OrderedDictionary] $Data
    )
    foreach ($i in $($data.Keys)) {
        $Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
    }
    return $Data
}

function Convert-ListToGenericList {
    Param(
        [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
        [array]$Data=@()
    )
    $ret = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
    for($i=0; $i -lt $Data.Count; $i++) {
        $ret.Add((Convert-PSObjectToGenericObject $Data[$i]))
    }
    return ,$ret
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
        [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
        [System.Object]$Data
    )
    if ($data -isnot [System.Object]) {
        return $data
    }
    $dataType = $data.GetType()
    if ($dataType.FullName -eq "System.Management.Automation.PSCustomObject") {
        return Convert-PSCustomObjectToDictionary $data
    } elseif (([System.Collections.Specialized.OrderedDictionary].IsAssignableFrom($dataType))){
        return Convert-OrderedHashtableToDictionary $data
    } elseif (([System.Collections.IDictionary].IsAssignableFrom($dataType))){
        return Convert-HashtableToDictionary $data
    } elseif (([System.Collections.IList].IsAssignableFrom($dataType))) {
        return Convert-ListToGenericList $data
    }
    return $data
}

function ConvertFrom-Yaml {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=0)]
        [string]$Yaml,
        [switch]$AllDocuments=$false,
        [switch]$Ordered,
        [switch]$UseMergingParser=$false
    )
    
    PROCESS {
        if(!$Yaml){
            return
        }
        $documents = Get-YamlDocuments -Yaml $Yaml -UseMergingParser:$UseMergingParser
        if (!$documents.Count) {
            return
        }
        if($documents.Count -eq 1){
            return Convert-YamlDocumentToPSObject $documents[0].RootNode -Ordered:$Ordered
        }
        if(!$AllDocuments) {
            return Convert-YamlDocumentToPSObject $documents[0].RootNode -Ordered:$Ordered
        }
        $ret = @()
        foreach($i in $documents) {
            $ret += Convert-YamlDocumentToPSObject $i.RootNode -Ordered:$Ordered
        }
        return $ret
    }
}


function ConvertTo-Yaml {
    [CmdletBinding(DefaultParameterSetName = 'NoOptions')]
    Param(
        [Parameter(ValueFromPipeline = $true, Position=0)]
        [System.Object]$Data,

        [string]$OutFile,

        [Parameter(ParameterSetName = 'Options')]
        [YamlDotNet.Serialization.SerializationOptions]$Options = [YamlDotNet.Serialization.SerializationOptions]::Roundtrip,

        [Parameter(ParameterSetName = 'NoOptions')]
        [switch]$JsonCompatible,

        [switch]$Force
    )
    BEGIN {
        $d = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
    }
    PROCESS {
        if($data -is [System.Object]) {
            $d.Add($data)
        }
    }
    END {
        if ($d -eq $null -or $d.Count -eq 0) {
            return
        }
        if ($d.Count -eq 1) {
            $d = $d[0]
        }
        $norm = Convert-PSObjectToGenericObject $d
        if ($OutFile) {
            $parent = Split-Path $OutFile
            if (!(Test-Path $parent)) {
                Throw "Parent folder for specified path does not exist"
            }
            if ((Test-Path $OutFile) -and !$Force) {
                Throw "Target file already exists. Use -Force to overwrite."
            }
            $wrt = New-Object "System.IO.StreamWriter" $OutFile
        } else {
            $wrt = New-Object "System.IO.StringWriter"
        }

        if ($PSCmdlet.ParameterSetName -eq 'NoOptions') {
            $Options = 0

            if ($JsonCompatible) {
                # No indent options :~(
                $options = [YamlDotNet.Serialization.SerializationOptions]::JsonCompatible
            }
        }

        try {
            $serializer = New-Object "YamlDotNet.Serialization.Serializer" $Options
            $serializer.Serialize($wrt, $norm)
        }
        catch{
            $_
        }
        finally {
            $wrt.Close()
        }
        if ($OutFile) {
            return
        } else {
            return $wrt.ToString()
        }
    }
}

New-Alias -Name cfy -Value ConvertFrom-Yaml
New-Alias -Name cty -Value ConvertTo-Yaml

Export-ModuleMember -Function * -Alias *
