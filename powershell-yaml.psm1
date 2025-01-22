# Copyright 2016-2024 Cloudbase Solutions Srl
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

[Flags()]
enum SerializationOptions {
    None = 0
    Roundtrip = 1
    DisableAliases = 2
    EmitDefaults = 4
    JsonCompatible = 8
    DefaultToStaticType = 16
    WithIndentedSequences = 32
    OmitNullValues = 64
    UseFlowStyle = 128
    UseSequenceFlowStyle = 256
}
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$infinityRegex = [regex]::new('^[-+]?(\.inf|\.Inf|\.INF)$', "Compiled, CultureInvariant");

function Invoke-LoadFile {
    param(
        [string]$assemblyPath
    )

    $powershellYamlDotNetAssemblyPath = Join-Path $assemblyPath "YamlDotNet.dll"
    $serializerAssemblyPath = Join-Path $assemblyPath "PowerShellYamlSerializer.dll"
    $yamlAssembly = [Reflection.Assembly]::LoadFile($powershellYamlDotNetAssemblyPath)
    $serializerAssembly = [Reflection.Assembly]::LoadFile($serializerAssemblyPath)

    if ($PSVersionTable['PSEdition'] -eq 'Core') {
        # Register the AssemblyResolve event to load dependencies manually. This seems to be needed only on
        # PowerShell Core.
        $resolver = {
            param ($snd, $e)
            # This event only needs to run once when the Invoke-LoadFile function is called.
            # If it's called again, the variables defined in this functions will not be available,
            # so we can safely ignore the event.
            if (-not $serializerAssemblyPath -or -not $powershellYamlDotNetAssemblyPath) {
                return $null
            }
            # Load YamlDotNet if it's requested by PowerShellYamlSerializer. Ignore other requests as they might
            # originate from other assemblies that are not part of this module and which might have different
            # versions of the module that they need to load.
            if ($e.Name -match "^YamlDotNet,*" -and $e.RequestingAssembly.Location -eq  $serializerAssemblyPath) {
                return [System.Reflection.Assembly]::LoadFile($powershellYamlDotNetAssemblyPath)
            }

            return $null
        }
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($resolver)
        # Load the StringQuotingEmitter from PowerShellYamlSerializer to force the resolver handler to fire once.
        # This is an ugly hack I am not happy with.
        $serializerAssembly.GetType("StringQuotingEmitter") | Out-Null

        # Remove the resolver handler after it has been used.
        [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($resolver)
    }

    return @{ "yaml"= $yamlAssembly; "quoted" = $serializerAssembly }
}

function Invoke-LoadAssembly {
    $libDir = Join-Path $here "lib"
    $assemblies = @{
        "core" = Join-Path $libDir "netstandard2.1";
        "net47" = Join-Path $libDir "net47";
    }

    if ($PSVersionTable.Keys -contains "PSEdition") {
        if ($PSVersionTable.PSEdition -eq "Core") {
            return (Invoke-LoadFile -assemblyPath $assemblies["core"])
        }
        return (Invoke-LoadFile -assemblyPath $assemblies["net47"])
    } else {
        return (Invoke-LoadFile -assemblyPath $assemblies["net47"])
    }
}

$assemblies = Invoke-LoadAssembly

$yamlDotNetAssembly = $assemblies["yaml"]
$stringQuotedAssembly = $assemblies["quoted"]

function Get-YamlDocuments {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Yaml,
        [switch]$UseMergingParser=$false
    )
    PROCESS {
        $stringReader = new-object System.IO.StringReader($Yaml)
        $parserType = $yamlDotNetAssembly.GetType("YamlDotNet.Core.Parser")
        $parser = $parserType::new($stringReader)
        if($UseMergingParser) {
            $parserType = $yamlDotNetAssembly.GetType("YamlDotNet.Core.MergingParser")
            $parser = $parserType::new($parser)
        }

        $yamlStream = $yamlDotNetAssembly.GetType("YamlDotNet.RepresentationModel.YamlStream")::new()
        $yamlStream.Load($parser)

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
        $intTypes = @([int], [long])
        if ([string]::IsNullOrEmpty($Node.Tag) -eq $false) {
            switch($Node.Tag) {
                "tag:yaml.org,2002:str" {
                    return $Node.Value
                }
                "tag:yaml.org,2002:null" {
                    return $null
                }
                "tag:yaml.org,2002:bool" {
                    $parsedValue = $false
                    if (![boolean]::TryParse($Node.Value, [ref]$parsedValue)) {
                        Throw ("failed to parse scalar {0} as boolean" -f $Node)
                    }
                    return $parsedValue
                }
                "tag:yaml.org,2002:int" {
                    $parsedValue = 0
                    if ($node.Value.Length -gt 2) {
                        switch ($node.Value.Substring(0, 2)) {
                            "0o" {
                                $parsedValue = [Convert]::ToInt64($Node.Value.Substring(2), 8)
                            }
                            "0x" {
                                $parsedValue = [Convert]::ToInt64($Node.Value.Substring(2), 16)
                            }
                            default {
                                if (![System.Numerics.BigInteger]::TryParse($Node.Value, @([Globalization.NumberStyles]::Float, [Globalization.NumberStyles]::Integer), [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                                    Throw ("failed to parse scalar {0} as long" -f $Node)
                                }
                            }
                        }
                    } else {
                        if (![System.Numerics.BigInteger]::TryParse($Node.Value, @([Globalization.NumberStyles]::Float, [Globalization.NumberStyles]::Integer), [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                            Throw ("failed to parse scalar {0} as long" -f $Node)
                        }
                    }
                    foreach ($i in $intTypes) {
                        $asIntType = $parsedValue -as $i
                        if($null -ne $asIntType) {
                            return $asIntType
                        }
                    }
                    return $parsedValue
                }
                "tag:yaml.org,2002:float" {
                    $parsedValue = 0.0
                    if ($infinityRegex.Matches($Node.Value).Count -gt 0) {
                        $prefix = $Node.Value.Substring(0, 1)
                        switch ($prefix) {
                            "-" {
                                return [double]::NegativeInfinity
                            }
                            default {
                                # Prefix is either missing or is a +
                                return [double]::PositiveInfinity
                            }
                        }
                    }
                    if (![decimal]::TryParse($Node.Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                        Throw ("failed to parse scalar {0} as decimal" -f $Node)
                    }
                    return $parsedValue
                }
                "tag:yaml.org,2002:timestamp" {
                    # From the YAML spec: http://yaml.org/type/timestamp.html
                    [DateTime]$parsedValue = [DateTime]::MinValue
                    $ts = [DateTime]::SpecifyKind($Node.Value, [System.DateTimeKind]::Utc)
                    $tss = $ts.ToString("o")
                    if(![datetime]::TryParse($tss, $null, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref] $parsedValue)) {
                        Throw ("failed to parse scalar {0} as DateTime" -f $Node)
                    }
                    return $parsedValue
                }
            }
        }

        if ($Node.Style -eq 'Plain') {
            $parsedValue = New-Object -TypeName ([Boolean].FullName)
            $result = [boolean]::TryParse($Node,[ref]$parsedValue)
            if( $result ) {
                return $parsedValue
            }

            $parsedValue = New-Object -TypeName ([System.Numerics.BigInteger].FullName)
            $result = [System.Numerics.BigInteger]::TryParse($Node, @([Globalization.NumberStyles]::Float, [Globalization.NumberStyles]::Integer), [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)
            if($result) {
                $types = @([int], [long])
                foreach($i in $types){
                    $asType = $parsedValue -as $i
                    if($null -ne $asType) {
                        return $asType
                    }
                }
                return $parsedValue
            }
            $types = @([decimal], [double])
            foreach($i in $types){
                $parsedValue = New-Object -TypeName $i.FullName
                $result = $i::TryParse($Node, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)
                if( $result ) {
                    return $parsedValue
                }
            }
        }

        if ($Node.Style -eq 'Plain' -and $Node.Value -in '','~','null','Null','NULL') {
            return $null
        }

        return $Node.Value
    }
}

function Convert-YamlMappingToHashtable {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $Node,
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
        $Node,
        [switch]$Ordered
    )
    PROCESS {
        $ret = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
        foreach($i in $Node.Children){
            $ret.Add((Convert-YamlDocumentToPSObject $i -Ordered:$Ordered))
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
                return Convert-YamlSequenceToArray $Node -Ordered:$Ordered
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
    foreach($i in $($data.PSBase.Keys)) {
        $Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
    }
    return $Data
}

function Convert-OrderedHashtableToDictionary {
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.Collections.Specialized.OrderedDictionary] $Data
    )
    foreach ($i in $($data.PSBase.Keys)) {
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

function Convert-PSObjectToGenericObject {
    Param(
        [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
        [System.Object]$Data
    )

    if ($null -eq $data) {
        return $data
    }

    $dataType = $data.GetType()
    if (([System.Collections.Specialized.OrderedDictionary].IsAssignableFrom($dataType))){
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

    BEGIN {
        $d = ""
    }
    PROCESS {
        if($Yaml -is [string]) {
            $d += $Yaml + "`n"
        }
    }

    END {
        if($d -eq ""){
            return
        }
        $documents = Get-YamlDocuments -Yaml $d -UseMergingParser:$UseMergingParser
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

function Get-Serializer {
    Param(
        [Parameter(Mandatory=$true)][SerializationOptions]$Options
    )
    
    $builder = $yamlDotNetAssembly.GetType("YamlDotNet.Serialization.SerializerBuilder")::new()
    $JsonCompatible = $Options.HasFlag([SerializationOptions]::JsonCompatible)

    if ($Options.HasFlag([SerializationOptions]::Roundtrip)) {
        $builder = $builder.EnsureRoundtrip()
    }
    if ($Options.HasFlag([SerializationOptions]::DisableAliases)) {
        $builder = $builder.DisableAliases()
    }
    if ($Options.HasFlag([SerializationOptions]::EmitDefaults)) {
        $builder = $builder.EmitDefaults()
    }
    if ($JsonCompatible) {
        $builder = $builder.JsonCompatible()
    }
    if ($Options.HasFlag([SerializationOptions]::DefaultToStaticType)) {
        $resolver = $yamlDotNetAssembly.GetType("YamlDotNet.Serialization.TypeResolvers.StaticTypeResolver")::new()
        $builder = $builder.WithTypeResolver($resolver)
    }
    if ($Options.HasFlag([SerializationOptions]::WithIndentedSequences)) {
        $builder = $builder.WithIndentedSequences()
    }

    $omitNull = $Options.HasFlag([SerializationOptions]::OmitNullValues)
    $useFlowStyle = $Options.HasFlag([SerializationOptions]::UseFlowStyle)
    $useSequenceFlowStyle = $Options.HasFlag([SerializationOptions]::UseSequenceFlowStyle)

    $stringQuoted = $stringQuotedAssembly.GetType("BuilderUtils")
    $builder = $stringQuoted::BuildSerializer($builder, $omitNull, $useFlowStyle, $useSequenceFlowStyle, $JsonCompatible)

    return $builder.Build()
}

function ConvertTo-Yaml {
    [CmdletBinding(DefaultParameterSetName = 'NoOptions')]
    Param(
        [Parameter(ValueFromPipeline = $true, Position=0)]
        [System.Object]$Data,

        [string]$OutFile,

        [Parameter(ParameterSetName = 'Options')]
        [SerializationOptions]$Options = [SerializationOptions]::Roundtrip,

        [Parameter(ParameterSetName = 'NoOptions')]
        [switch]$JsonCompatible,
        [switch]$UseFlowStyle,
        
        [switch]$KeepArray,

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
        if ($d.Count -eq 1 -and !($KeepArray)) {
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
                $Options = [SerializationOptions]::JsonCompatible
            }
        }

        try {
            $serializer = Get-Serializer $Options
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

Export-ModuleMember -Function ConvertFrom-Yaml,ConvertTo-Yaml -Alias cfy,cty
