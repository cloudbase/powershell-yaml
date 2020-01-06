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
        [YamlDotNet.RepresentationModel.YamlSequenceNode]$Node,
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

$stringQuotingEmitterSource = @"
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using YamlDotNet;
using YamlDotNet.Core;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.EventEmitters;


public static class YamlFormatter
{
    public static readonly NumberFormatInfo NumberFormat = new NumberFormatInfo
    {
        CurrencyDecimalSeparator = ".",
        CurrencyGroupSeparator = "_",
        CurrencyGroupSizes = new[] { 3 },
        CurrencySymbol = string.Empty,
        CurrencyDecimalDigits = 99,
        NumberDecimalSeparator = ".",
        NumberGroupSeparator = "_",
        NumberGroupSizes = new[] { 3 },
        NumberDecimalDigits = 99,
        NaNSymbol = ".nan",
        PositiveInfinitySymbol = ".inf",
        NegativeInfinitySymbol = "-.inf"
    };

    public static string FormatNumber(object number)
    {
        // NOTE (gsamfira): For some reason, this does not work
        // on powershell core. Even though [System.Convert] is available
        // in the powershell session itself, it cannot be referenced from
        // within the C# code embeded here.
        //return System.Convert.ToString(number, NumberFormat);
        return number.ToString();
    }

    public static string FormatNumber(double number)
    {
        return number.ToString("G17", NumberFormat);
    }

    public static string FormatNumber(float number)
    {
        return number.ToString("G17", NumberFormat);
    }

    public static string FormatBoolean(object boolean)
    {
        return boolean.Equals(true) ? "true" : "false";
    }

    public static string FormatDateTime(object dateTime)
    {
        return ((DateTime)dateTime).ToString("o", CultureInfo.InvariantCulture);
    }

    public static string FormatTimeSpan(object timeSpan)
    {
        return ((TimeSpan)timeSpan).ToString();
    }
}

public sealed class CustomTypeAssigningEventEmitter : ChainedEventEmitter
{
    // Patterns from https://yaml.org/spec/1.2/spec.html#id2804356
    private static Regex quotedRegex = new Regex(@`"^(\~|null|true|false|-?(0|[0-9][0-9]*)(\.[0-9]*)?([eE][-+]?[0-9]+)?)?$`", RegexOptions.Compiled);

    public CustomTypeAssigningEventEmitter(IEventEmitter nextEmitter)
        : base(nextEmitter)
    {
    }

    public override void Emit(ScalarEventInfo eventInfo, IEmitter emitter)
    {
        var suggestedStyle = ScalarStyle.Plain;

        var value = eventInfo.Source.Value;
        if (value == null)
        {
            eventInfo.Tag = "tag:yaml.org,2002:null";
            eventInfo.RenderedValue = "";
        }
        else
        {
            var typeCode = Type.GetTypeCode(eventInfo.Source.Type);
            switch (typeCode)
            {
                case TypeCode.Boolean:
                    eventInfo.RenderedValue = YamlFormatter.FormatBoolean(value);
                    break;

                case TypeCode.Byte:
                case TypeCode.Int16:
                case TypeCode.Int32:
                case TypeCode.Int64:
                case TypeCode.SByte:
                case TypeCode.UInt16:
                case TypeCode.UInt32:
                case TypeCode.UInt64:
                    eventInfo.Tag = "tag:yaml.org,2002:int";
                    eventInfo.RenderedValue = YamlFormatter.FormatNumber(value);
                    break;
                case TypeCode.Single:
                case TypeCode.Double:
                case TypeCode.Decimal:
                    eventInfo.Tag = "tag:yaml.org,2002:float";
                    eventInfo.RenderedValue = YamlFormatter.FormatNumber(value);
                    break;

                case TypeCode.String:
                    eventInfo.Tag = "tag:yaml.org,2002:str";
                    var val = eventInfo.Source.Value.ToString();
                    if (quotedRegex.IsMatch(val))
                    {
                        eventInfo.Style = ScalarStyle.DoubleQuoted;
                    } else if (val.IndexOf('\n') > -1) {
                        eventInfo.Style = ScalarStyle.Literal;
                    }
                    eventInfo.RenderedValue = value.ToString();
                    suggestedStyle = ScalarStyle.Any;
                    break;
                case TypeCode.Char:
                    eventInfo.Tag = "tag:yaml.org,2002:str";
                    if (Char.IsDigit((char)eventInfo.Source.Value)) {
                        eventInfo.Style = ScalarStyle.DoubleQuoted;
                    }
                    eventInfo.RenderedValue = value.ToString();
                    suggestedStyle = ScalarStyle.Any;

                    break;

                case TypeCode.DateTime:
                    eventInfo.Tag = "tag:yaml.org,2002:timestamp";
                    eventInfo.RenderedValue = YamlFormatter.FormatDateTime(value);
                    break;

                case TypeCode.Empty:
                    eventInfo.Tag = "tag:yaml.org,2002:null";
                    eventInfo.RenderedValue = "";
                    break;

                default:
                    if (eventInfo.Source.Type == typeof(TimeSpan))
                    {
                        eventInfo.RenderedValue = YamlFormatter.FormatTimeSpan(value);
                        break;
                    }

                    throw new NotSupportedException("TypeCode.{typeCode} is not supported.");
            }
        }

        eventInfo.IsPlainImplicit = true;
        if (eventInfo.Style == ScalarStyle.Any)
        {
            eventInfo.Style = suggestedStyle;
        }

        base.Emit(eventInfo, emitter);
    }

    public override void Emit(MappingStartEventInfo eventInfo, IEmitter emitter)
    {
        base.Emit(eventInfo, emitter);
    }

    public override void Emit(SequenceStartEventInfo eventInfo, IEmitter emitter)
    {
        base.Emit(eventInfo, emitter);
    }

    public static SerializerBuilder ReplaceTypeAssigningEventEmitter(SerializerBuilder builder) {
        builder.WithEventEmitter(inner => new CustomTypeAssigningEventEmitter(inner), loc => loc.InsteadOf<TypeAssigningEventEmitter>());
        return builder;
    }
}
"@

$referenceList = @([YamlDotNet.Serialization.Serializer].Assembly.Location,[Text.RegularExpressions.Regex].Assembly.Location)
if ($PSVersionTable.PSEdition -eq "Core") {
    Add-Type -TypeDefinition $stringQuotingEmitterSource -ReferencedAssemblies $referenceList -Language CSharp -CompilerOptions "-nowarn:1701"
} else {
    Add-Type -TypeDefinition $stringQuotingEmitterSource -ReferencedAssemblies $referenceList -Language CSharp
}

function Get-Serializer {
    Param(
        [Parameter(Mandatory=$true)][YamlDotNet.Serialization.SerializationOptions]$Options
    )
    
    $builder = New-Object "YamlDotNet.Serialization.SerializerBuilder"
    if ( -not $Options.HasFlag([YamlDotNet.Serialization.SerializationOptions]::JsonCompatible)) {
        $builder = [CustomTypeAssigningEventEmitter]::ReplaceTypeAssigningEventEmitter($builder)
    }
    
    if ($Options.HasFlag([YamlDotNet.Serialization.SerializationOptions]::Roundtrip)) {
        $builder = $builder.EnsureRoundtrip()
    }
    if ($Options.HasFlag([YamlDotNet.Serialization.SerializationOptions]::DisableAliases)) {
        $builder = $builder.DisableAliases()
    }
    if ($Options.HasFlag([YamlDotNet.Serialization.SerializationOptions]::EmitDefaults)) {
        $builder = $builder.EmitDefaults()
    }
    if ($Options.HasFlag([YamlDotNet.Serialization.SerializationOptions]::JsonCompatible)) {
        $builder = $builder.JsonCompatible()
    }
    if ($Options.HasFlag([YamlDotNet.Serialization.SerializationOptions]::DefaultToStaticType)) {
        $builder = $builder.WithTypeResolver((New-Object "YamlDotNet.Serialization.TypeResolvers.StaticTypeResolver"))
    }
    return $builder.Build()
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
                $Options = [YamlDotNet.Serialization.SerializationOptions]::JsonCompatible
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

Export-ModuleMember -Function * -Alias *
