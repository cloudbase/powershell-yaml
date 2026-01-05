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
    UseBlockStyle = 512
    UseSequenceBlockStyle = 1024
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$infinityRegex = [regex]::new('^[-+]?(\.inf|\.Inf|\.INF)$', 'Compiled, CultureInvariant');

function Invoke-LoadAssemblyWithDependencies {
    param(
        [Parameter(Mandatory)]
        [string]$MainAssemblyPath,

        [Parameter(Mandatory)]
        [hashtable]$Dependencies,

        [string]$ForceLoadTypeName
    )

    # Load the main assembly via LoadFile (creates anonymous ALC on PS 7+)
    $mainAssembly = [Reflection.Assembly]::LoadFile($MainAssemblyPath)

    if ($PSVersionTable['PSEdition'] -eq 'Core') {
        # On PowerShell Core, use AssemblyResolve to manually load dependencies
        # This is needed because LoadFile doesn't automatically resolve dependencies
        $resolver = {
            param ($snd, $e)

            # Only respond if we have the necessary paths (from outer scope)
            if (-not $MainAssemblyPath -or -not $Dependencies) {
                return $null
            }

            # Only respond to requests from our main assembly
            if ($e.RequestingAssembly.Location -eq $MainAssemblyPath) {
                # Check each dependency
                foreach ($dep in $Dependencies.GetEnumerator()) {
                    if ($e.Name -match "^$($dep.Key),") {
                        # Dependency can be either a path (string) or an Assembly object
                        if ($dep.Value -is [string]) {
                            return [System.Reflection.Assembly]::LoadFile($dep.Value)
                        } else {
                            return $dep.Value
                        }
                    }
                }
            }

            return $null
        }

        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($resolver)

        # Force dependency resolution by accessing a type
        if ($ForceLoadTypeName) {
            $mainAssembly.GetType($ForceLoadTypeName) | Out-Null
        } else {
            $mainAssembly.GetTypes() | Out-Null
        }

        [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($resolver)
    }

    return $mainAssembly
}

# ============================================================================
# Assembly Path Configuration
# ============================================================================

$libDir = Join-Path $here 'lib/netstandard2.0'

# YAML module assemblies
$yamlDotNetPath = Join-Path $libDir 'YamlDotNet.dll'

# Typed YAML module assemblies (now contains ALL serialization code)
$typedModulePath = Join-Path $libDir 'PowerShellYaml.Module.dll'
$typedYamlBasePath = Join-Path $libDir 'PowerShellYaml.dll'

# Load YamlDotNet first (isolated via LoadFile)
$yamlDotNetAssembly = [Reflection.Assembly]::LoadFile($yamlDotNetPath)

# Load PowerShellYaml.dll (must be in Default ALC for class inheritance)
$yamlBaseAsm = [System.Reflection.Assembly]::LoadFrom($typedYamlBasePath)

# Load PowerShellYaml.Module.dll early for BuilderUtils access
# Dependencies: YamlDotNet (isolated) and PowerShellYaml (from Default ALC)
$script:typedModuleAssembly = Invoke-LoadAssemblyWithDependencies `
    -MainAssemblyPath $typedModulePath `
    -Dependencies @{
        'YamlDotNet' = $yamlDotNetPath
        'PowerShellYaml' = $yamlBaseAsm
    }

# Store types for use throughout the module
$script:BuilderUtils = $script:typedModuleAssembly.GetType('PowerShellYaml.Module.BuilderUtils')
$script:TypedYamlConverter = $script:typedModuleAssembly.GetType('PowerShellYaml.Module.TypedYamlConverter')
$script:YamlDocumentParser = $script:typedModuleAssembly.GetType('PowerShellYaml.Module.YamlDocumentParser')
$script:PSObjectMetadataExtensions = $script:typedModuleAssembly.GetType('PowerShellYaml.Module.PSObjectMetadataExtensions')
$YamlMetadataStore = $script:typedModuleAssembly.GetType('PowerShellYaml.Module.YamlMetadataStore')
$MetadataAwareSerializer = $script:typedModuleAssembly.GetType('PowerShellYaml.Module.MetadataAwareSerializer')

# Create type accelerators for test scripts
$TypeAcceleratorsClass = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
$TypeAcceleratorsClass::Add('YamlDocumentParser', $script:YamlDocumentParser)
$TypeAcceleratorsClass::Add('PSObjectMetadataExtensions', $script:PSObjectMetadataExtensions)
$TypeAcceleratorsClass::Add('YamlMetadataStore', $YamlMetadataStore)
$TypeAcceleratorsClass::Add('MetadataAwareSerializer', $MetadataAwareSerializer)

function Get-YamlDocuments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Yaml,
        [switch]$UseMergingParser = $false
    )
    process {
        $stringReader = New-Object System.IO.StringReader($Yaml)
        $parserType = $yamlDotNetAssembly.GetType('YamlDotNet.Core.Parser')
        $parser = $parserType::new($stringReader)
        if ($UseMergingParser) {
            $parserType = $yamlDotNetAssembly.GetType('YamlDotNet.Core.MergingParser')
            $parser = $parserType::new($parser)
        }

        $yamlStream = $yamlDotNetAssembly.GetType('YamlDotNet.RepresentationModel.YamlStream')::new()
        $yamlStream.Load($parser)

        $stringReader.Close()

        return $yamlStream
    }
}

function Convert-ValueToProperType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Object]$Node
    )
    process {
        if (!($Node.Value -is [string])) {
            return $Node
        }
        $intTypes = @([int], [long])
        if ([string]::IsNullOrEmpty($Node.Tag) -eq $false) {
            switch ($Node.Tag) {
                '!' {
                    return $Node.Value
                }
                'tag:yaml.org,2002:str' {
                    return $Node.Value
                }
                'tag:yaml.org,2002:null' {
                    return $null
                }
                'tag:yaml.org,2002:bool' {
                    $parsedValue = $false
                    if (![boolean]::TryParse($Node.Value, [ref]$parsedValue)) {
                        throw ('failed to parse scalar {0} as boolean' -f $Node)
                    }
                    return $parsedValue
                }
                'tag:yaml.org,2002:int' {
                    $parsedValue = 0
                    if ($node.Value.Length -gt 2) {
                        switch ($node.Value.Substring(0, 2)) {
                            '0o' {
                                $parsedValue = [Convert]::ToInt64($Node.Value.Substring(2), 8)
                            }
                            '0x' {
                                $parsedValue = [Convert]::ToInt64($Node.Value.Substring(2), 16)
                            }
                            default {
                                if (![System.Numerics.BigInteger]::TryParse($Node.Value, @([Globalization.NumberStyles]::Float, [Globalization.NumberStyles]::Integer), [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                                    throw ('failed to parse scalar {0} as long' -f $Node)
                                }
                            }
                        }
                    } else {
                        if (![System.Numerics.BigInteger]::TryParse($Node.Value, @([Globalization.NumberStyles]::Float, [Globalization.NumberStyles]::Integer), [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                            throw ('failed to parse scalar {0} as long' -f $Node)
                        }
                    }
                    foreach ($i in $intTypes) {
                        $asIntType = $parsedValue -as $i
                        if ($null -ne $asIntType) {
                            return $asIntType
                        }
                    }
                    return $parsedValue
                }
                'tag:yaml.org,2002:float' {
                    $parsedValue = 0.0
                    if ($infinityRegex.Matches($Node.Value).Count -gt 0) {
                        $prefix = $Node.Value.Substring(0, 1)
                        switch ($prefix) {
                            '-' {
                                return [double]::NegativeInfinity
                            }
                            default {
                                # Prefix is either missing or is a +
                                return [double]::PositiveInfinity
                            }
                        }
                    }
                    if (![decimal]::TryParse($Node.Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                        throw ('failed to parse scalar {0} as decimal' -f $Node)
                    }
                    return $parsedValue
                }
                'tag:yaml.org,2002:timestamp' {
                    # From the YAML spec: http://yaml.org/type/timestamp.html
                    [DateTime]$parsedValue = [DateTime]::MinValue
                    $ts = [DateTime]::SpecifyKind($Node.Value, [System.DateTimeKind]::Utc)
                    $tss = $ts.ToString('o')
                    if (![datetime]::TryParse($tss, $null, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref] $parsedValue)) {
                        throw ('failed to parse scalar {0} as DateTime' -f $Node)
                    }
                    return $parsedValue
                }
            }
        }

        if ($Node.Style -eq 'Plain') {
            $parsedValue = New-Object -TypeName ([Boolean].FullName)
            $result = [boolean]::TryParse($Node, [ref]$parsedValue)
            if ( $result ) {
                return $parsedValue
            }

            $parsedValue = New-Object -TypeName ([System.Numerics.BigInteger].FullName)
            $result = [System.Numerics.BigInteger]::TryParse($Node, @([Globalization.NumberStyles]::Float, [Globalization.NumberStyles]::Integer), [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)
            if ($result) {
                $types = @([int], [long])
                foreach ($i in $types) {
                    $asType = $parsedValue -as $i
                    if ($null -ne $asType) {
                        return $asType
                    }
                }
                return $parsedValue
            }
            $types = @([decimal], [double])
            foreach ($i in $types) {
                $parsedValue = New-Object -TypeName $i.FullName
                $result = $i::TryParse($Node, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)
                if ( $result ) {
                    return $parsedValue
                }
            }
        }

        if ($Node.Style -eq 'Plain' -and $Node.Value -in '', '~', 'null', 'Null', 'NULL') {
            return $null
        }

        return $Node.Value
    }
}

function Convert-YamlMappingToHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Node,
        [switch] $Ordered
    )
    process {
        if ($Ordered) { $ret = [ordered]@{} } else { $ret = @{} }
        foreach ($i in $Node.Children.Keys) {
            $ret[$i.Value] = Convert-YamlDocumentToPSObject $Node.Children[$i] -Ordered:$Ordered
        }
        return $ret
    }
}

function Convert-YamlSequenceToArray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Node,
        [switch]$Ordered
    )
    process {
        $ret = [System.Collections.Generic.List[object]](New-Object 'System.Collections.Generic.List[object]')
        foreach ($i in $Node.Children) {
            $ret.Add((Convert-YamlDocumentToPSObject $i -Ordered:$Ordered))
        }
        return , $ret
    }
}

function Convert-YamlDocumentToPSObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Object]$Node,
        [switch]$Ordered
    )
    process {
        switch ($Node.GetType().FullName) {
            'YamlDotNet.RepresentationModel.YamlMappingNode' {
                return Convert-YamlMappingToHashtable $Node -Ordered:$Ordered
            }
            'YamlDotNet.RepresentationModel.YamlSequenceNode' {
                return Convert-YamlSequenceToArray $Node -Ordered:$Ordered
            }
            'YamlDotNet.RepresentationModel.YamlScalarNode' {
                return (Convert-ValueToProperType $Node)
            }
        }
    }
}

function Convert-HashtableToDictionary {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Data
    )
    foreach ($i in $($data.PSBase.Keys)) {
        $Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
    }
    return $Data
}

function Convert-OrderedHashtableToDictionary {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Collections.Specialized.OrderedDictionary] $Data
    )
    foreach ($i in $($data.PSBase.Keys)) {
        $Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
    }
    return $Data
}

function Convert-GenericOrderedDictionaryToOrderedDictionary {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Object]$Data
    )
    # Convert System.Collections.Generic ordered dictionaries to System.Collections.Specialized.OrderedDictionary
    # to preserve key order when serializing with YamlDotNet
    $ordered = [System.Collections.Specialized.OrderedDictionary]::new()
    foreach ($key in $Data.Keys) {
        $ordered[$key] = Convert-PSObjectToGenericObject $Data[$key]
    }
    return $ordered
}

function Convert-ListToGenericList {
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [array]$Data = @()
    )
    $ret = [System.Collections.Generic.List[object]](New-Object 'System.Collections.Generic.List[object]')
    for ($i = 0; $i -lt $Data.Count; $i++) {
        $ret.Add((Convert-PSObjectToGenericObject $Data[$i]))
    }
    return , $ret
}

function Convert-PSObjectToGenericObject {
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [System.Object]$Data
    )

    if ($null -eq $data) {
        return $data
    }

    $dataType = $data.GetType()

    # Check for OrderedDictionary types first (before generic IDictionary check)
    if (([System.Collections.Specialized.OrderedDictionary].IsAssignableFrom($dataType))) {
        return Convert-OrderedHashtableToDictionary $data
    }

    # Check for System.Collections.Generic ordered dictionary types
    # These need to be converted to OrderedDictionary to preserve key order in YamlDotNet
    if ($dataType.IsGenericType) {
        $genericDef = $dataType.GetGenericTypeDefinition()
        $genericName = $genericDef.FullName

        # Handle System.Collections.Generic.OrderedDictionary<K,V>
        if ($genericName -eq 'System.Collections.Generic.OrderedDictionary`2') {
            return Convert-GenericOrderedDictionaryToOrderedDictionary $data
        }

        # Handle System.Collections.Generic.SortedDictionary<K,V>
        if ($genericName -eq 'System.Collections.Generic.SortedDictionary`2') {
            return Convert-GenericOrderedDictionaryToOrderedDictionary $data
        }
    }

    # Generic IDictionary handling (for Hashtable, Dictionary, etc.)
    if (([System.Collections.IDictionary].IsAssignableFrom($dataType))) {
        return Convert-HashtableToDictionary $data
    }

    if (([System.Collections.IList].IsAssignableFrom($dataType))) {
        return Convert-ListToGenericList $data
    }

    return $data
}

function ConvertFrom-Yaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
        [string]$Yaml,
        [switch]$AllDocuments = $false,
        [switch]$Ordered,
        [switch]$UseMergingParser = $false,
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if ($null -eq $_) {
                throw "The -As parameter cannot be null"
            }
            if ($_ -eq [PSCustomObject]) {
                return $true
            }
            if ($_.IsSubclassOf([PowerShellYaml.YamlBase])) {
                return $true
            }
            throw "The -As parameter must be either [PSCustomObject] or a type that inherits from [PowerShellYaml.YamlBase]. Got: $($_.FullName)"
        })]
        [type]$As
    )

    begin {
        $d = ''
    }
    process {
        $d += $Yaml + "`n"
    }

    end {
        if ($d -eq '') {
            return
        }

        # Route based on -As parameter (validation already done by ValidateScript)
        if ($PSBoundParameters.ContainsKey('As')) {
            if ($As.IsSubclassOf([PowerShellYaml.YamlBase])) {
                if ($script:TypedYamlConverter) {
                    return $script:TypedYamlConverter::FromYaml($d, $As)
                } else {
                    throw "Typed YAML module not loaded"
                }
            } else {
                # Use YamlDocumentParser to preserve metadata
                $result = $script:YamlDocumentParser::ParseWithMetadata($d)
                if ($null -eq $result.Item1) {
                    return $null
                }
                # Create enhanced PSCustomObject from parsed data and metadata
                return $script:PSObjectMetadataExtensions::CreateEnhancedPSCustomObject($result.Item1, $result.Item2)
            }
        }

        # Mode 1: Original hashtable mode (no -As parameter)
        $documents = Get-YamlDocuments -Yaml $d -UseMergingParser:$UseMergingParser
        if (!$documents.Count) {
            return
        }
        if (($documents.Count -eq 1) -or !$AllDocuments) {
            return Convert-YamlDocumentToPSObject $documents[0].RootNode -Ordered:$Ordered
        }
        $ret = @()
        foreach ($i in $documents) {
            $ret += Convert-YamlDocumentToPSObject $i.RootNode -Ordered:$Ordered
        }
        return $ret
    }
}

function Get-Serializer {
    param(
        [Parameter(Mandatory = $true)][SerializationOptions]$Options,
        [int]$MaxDepth = 100
    )

    $builder = $yamlDotNetAssembly.GetType('YamlDotNet.Serialization.SerializerBuilder')::new()
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
        $resolver = $yamlDotNetAssembly.GetType('YamlDotNet.Serialization.TypeResolvers.StaticTypeResolver')::new()
        $builder = $builder.WithTypeResolver($resolver)
    }
    if ($Options.HasFlag([SerializationOptions]::WithIndentedSequences)) {
        $builder = $builder.WithIndentedSequences()
    }

    # Set a high recursion limit - our custom visitors handle depth limiting and circular references
    $builder = $builder.WithMaximumRecursion(1000)

    $omitNull = $Options.HasFlag([SerializationOptions]::OmitNullValues)
    $useFlowStyle = $Options.HasFlag([SerializationOptions]::UseFlowStyle)
    $useSequenceFlowStyle = $Options.HasFlag([SerializationOptions]::UseSequenceFlowStyle)
    $useBlockStyle = $Options.HasFlag([SerializationOptions]::UseBlockStyle)
    $useSequenceBlockStyle = $Options.HasFlag([SerializationOptions]::UseSequenceBlockStyle)

    $builder = $script:BuilderUtils::BuildSerializer($builder, $omitNull, $useFlowStyle, $useSequenceFlowStyle, $useBlockStyle, $useSequenceBlockStyle, $JsonCompatible, $MaxDepth)

    return $builder.Build()
}

function ConvertTo-Yaml {
    [CmdletBinding(DefaultParameterSetName = 'NoOptions')]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        [System.Object]$Data,

        [string]$OutFile,

        [Parameter(ParameterSetName = 'Options')]
        [SerializationOptions]$Options = [SerializationOptions]::Roundtrip,

        [Parameter(ParameterSetName = 'NoOptions')]
        [switch]$JsonCompatible,

        [switch]$KeepArray,

        [switch]$Force,

        # Typed YAML parameters (for YamlBase objects)
        [switch]$OmitNull,

        [switch]$EmitTags,

        # Maximum recursion depth (default: 50)
        [int]$Depth = 100
    )
    begin {
        $d = [System.Collections.Generic.List[object]](New-Object 'System.Collections.Generic.List[object]')
    }
    process {
        if ($data -is [System.Object]) {
            $d.Add($data)
        }
    }
    end {
        if ($null -eq $d -or $d.Count -eq 0) {
            return
        }
        if ($d.Count -eq 1 -and !($KeepArray)) {
            $d = $d[0]
        }

        # Mode 3: Typed class mode - call C# helper directly
        if ($d -is [PowerShellYaml.YamlBase]) {
            if ($script:TypedYamlConverter) {
                # Extract flow/block style options if using Options parameter
                $useFlowStyle = $false
                $useBlockStyle = $false
                $useSequenceFlowStyle = $false
                $useSequenceBlockStyle = $false
                $indentedSequences = $false
                if ($PSCmdlet.ParameterSetName -eq 'Options') {
                    $useFlowStyle = $Options.HasFlag([SerializationOptions]::UseFlowStyle)
                    $useBlockStyle = $Options.HasFlag([SerializationOptions]::UseBlockStyle)
                    $useSequenceFlowStyle = $Options.HasFlag([SerializationOptions]::UseSequenceFlowStyle)
                    $useSequenceBlockStyle = $Options.HasFlag([SerializationOptions]::UseSequenceBlockStyle)
                    $indentedSequences = $Options.HasFlag([SerializationOptions]::WithIndentedSequences)
                }
                $yaml = $script:TypedYamlConverter::ToYaml($d, $OmitNull.IsPresent, $EmitTags.IsPresent, $useFlowStyle, $useBlockStyle, $useSequenceFlowStyle, $useSequenceBlockStyle, $indentedSequences, $Depth)
            } else {
                throw "Typed YAML module not loaded"
            }
        } elseif ($script:PSObjectMetadataExtensions::IsEnhancedPSCustomObject($d)) {
            # Use metadata-aware serializer
            $MetadataAwareSerializer = $script:typedModuleAssembly.GetType('PowerShellYaml.Module.MetadataAwareSerializer')
            # Extract style options if using Options parameter
            $indentedSequences = $false
            $useFlowStyle = $false
            $useBlockStyle = $false
            if ($PSCmdlet.ParameterSetName -eq 'Options') {
                $indentedSequences = $Options.HasFlag([SerializationOptions]::WithIndentedSequences)
                $useFlowStyle = $Options.HasFlag([SerializationOptions]::UseFlowStyle)
                $useBlockStyle = $Options.HasFlag([SerializationOptions]::UseBlockStyle)
            }
            $yaml = $MetadataAwareSerializer::Serialize($d, $indentedSequences, $EmitTags.IsPresent, $Depth, $useFlowStyle, $useBlockStyle)
        } else {
            $wrt = New-Object 'System.IO.StringWriter'
            $norm = Convert-PSObjectToGenericObject $d
            if ($PSCmdlet.ParameterSetName -eq 'NoOptions') {
                $Options = 0
                if ($JsonCompatible) {
                    # No indent options :~(
                    $Options = [SerializationOptions]::JsonCompatible
                }
            }
            try {
                $serializer = Get-Serializer -Options $Options -MaxDepth $Depth
                $serializer.Serialize($wrt, $norm)
                $yaml = $wrt.ToString()
            } finally {
                if ($null -ne $wrt) {
                    $wrt.Dispose()
                }
            }
        }

       if ($OutFile) {
            $parent = Split-Path $OutFile
            if (!(Test-Path $parent)) {
                throw 'Parent folder for specified path does not exist'
            }
            if ((Test-Path $OutFile) -and !$Force) {
                throw 'Target file already exists. Use -Force to overwrite.'
            }
            [System.IO.File]::WriteAllText($OutFile, $yaml)
            return
        }
        return $yaml
    }
}

<#
.SYNOPSIS
    Sets a YAML comment for a property on an enhanced PSCustomObject.
.DESCRIPTION
    Adds or updates a comment that will be written above the property when
    converting back to YAML. The object must be created with ConvertFrom-Yaml -As [PSCustomObject].
.PARAMETER InputObject
    The enhanced PSCustomObject with YAML metadata.
.PARAMETER PropertyName
    The name of the property to add a comment to.
.PARAMETER Comment
    The comment text (without # prefix).
.EXAMPLE
    $config = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
    $config | Set-YamlPropertyComment -PropertyName 'Server' -Comment 'Production server address'
#>
function Set-YamlPropertyComment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$InputObject,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        [Parameter(Mandatory)]
        [string]$Comment
    )

    process {
        $metadata = $script:PSObjectMetadataExtensions::GetMetadata($InputObject)
        if ($metadata) {
            $metadata.SetPropertyComment($PropertyName, $Comment)
        } else {
            Write-Warning "Object does not have YAML metadata. Use ConvertFrom-Yaml with -As [PSCustomObject]"
        }
    }
}

<#
.SYNOPSIS
    Gets a YAML comment for a property on an enhanced PSCustomObject.
.DESCRIPTION
    Retrieves the comment associated with a property that was preserved during
    YAML parsing or set with Set-YamlPropertyComment.
.PARAMETER InputObject
    The enhanced PSCustomObject with YAML metadata.
.PARAMETER PropertyName
    The name of the property to get the comment for.
.EXAMPLE
    $comment = Get-YamlPropertyComment -InputObject $config -PropertyName 'Server'
#>
function Get-YamlPropertyComment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$InputObject,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    process {
        $metadata = $script:PSObjectMetadataExtensions::GetMetadata($InputObject)
        if ($metadata) {
            return $metadata.GetPropertyComment($PropertyName)
        } else {
            Write-Warning "Object does not have YAML metadata. Use ConvertFrom-Yaml with -As [PSCustomObject]"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Sets the scalar style for a property on an enhanced PSCustomObject.
.DESCRIPTION
    Controls how a property value will be formatted when converting to YAML
    (e.g., plain, single-quoted, double-quoted, literal, folded).
.PARAMETER InputObject
    The enhanced PSCustomObject with YAML metadata.
.PARAMETER PropertyName
    The name of the property to set the style for.
.PARAMETER Style
    The scalar style to use (Plain, SingleQuoted, DoubleQuoted, Literal, Folded).
.EXAMPLE
    $config | Set-YamlPropertyScalarStyle -PropertyName 'Description' -Style Literal
#>
function Set-YamlPropertyScalarStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$InputObject,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        [Parameter(Mandatory)]
        [ValidateSet('Plain', 'SingleQuoted', 'DoubleQuoted', 'Literal', 'Folded')]
        [string]$Style
    )

    process {
        $metadata = $script:PSObjectMetadataExtensions::GetMetadata($InputObject)
        if ($metadata) {
            $scalarStyle = [YamlDotNet.Core.ScalarStyle]::$Style
            $metadata.SetPropertyScalarStyle($PropertyName, $scalarStyle)
        } else {
            Write-Warning "Object does not have YAML metadata. Use ConvertFrom-Yaml with -As [PSCustomObject]"
        }
    }
}

<#
.SYNOPSIS
    Tests if a PSCustomObject has YAML metadata attached.
.DESCRIPTION
    Returns $true if the object was created with ConvertFrom-Yaml -As [PSCustomObject]
    and has metadata support, $false otherwise.
.PARAMETER InputObject
    The PSCustomObject to test.
.EXAMPLE
    if (Test-YamlMetadata $config) {
        $config | Set-YamlPropertyComment -PropertyName 'Name' -Comment 'User name'
    }
#>
function Test-YamlMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$InputObject
    )

    process {
        return $script:PSObjectMetadataExtensions::IsEnhancedPSCustomObject($InputObject)
    }
}

# Typed YAML Module already loaded at module initialization (see lines 107-123)

New-Alias -Name cfy -Value ConvertFrom-Yaml
New-Alias -Name cty -Value ConvertTo-Yaml

# Export only the public API
# Typed cmdlets (ConvertFrom-YamlTyped, ConvertTo-YamlTyped) are loaded but not exported.
# The manifest (.psd1) controls the final export list.
Export-ModuleMember -Function @(
    'ConvertFrom-Yaml',
    'ConvertTo-Yaml',
    'Set-YamlPropertyComment',
    'Get-YamlPropertyComment',
    'Set-YamlPropertyScalarStyle',
    'Test-YamlMetadata'
) -Alias @('cfy', 'cty')
