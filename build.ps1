$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = @"
using System;
using System.Text.RegularExpressions;
using YamlDotNet;
using YamlDotNet.Core;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.EventEmitters;
public class StringQuotingEmitter: ChainedEventEmitter {
    // Patterns from https://yaml.org/spec/1.2/spec.html#id2804356
    private static Regex quotedRegex = new Regex(@`"^(\~|null|true|false|on|off|yes|no|y|n|[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?|[-+]?(\.inf))?$`", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    public StringQuotingEmitter(IEventEmitter next): base(next) {}

    public override void Emit(ScalarEventInfo eventInfo, IEmitter emitter) {
        var typeCode = eventInfo.Source.Value != null
        ? Type.GetTypeCode(eventInfo.Source.Type)
        : TypeCode.Empty;

        switch (typeCode) {
            case TypeCode.Char:
                if (Char.IsDigit((char)eventInfo.Source.Value)) {
                    eventInfo.Style = ScalarStyle.DoubleQuoted;
                }
                break;
            case TypeCode.String:
                var val = eventInfo.Source.Value.ToString();
                if (quotedRegex.IsMatch(val))
                {
                    eventInfo.Style = ScalarStyle.DoubleQuoted;
                } else if (val.IndexOf('\n') > -1) {
                    eventInfo.Style = ScalarStyle.Literal;
                }
                break;
        }

        base.Emit(eventInfo, emitter);
    }

    public static SerializerBuilder Add(SerializerBuilder builder) {
        return builder.WithEventEmitter(next => new StringQuotingEmitter(next));
    }
}
"@


function Invoke-LoadInContext {
    param(
        [string]$assemblyPath,
        [string]$loadContextName
    )
    
    $loadContext = [System.Runtime.Loader.AssemblyLoadContext]::New($loadContextName, $true)
    $assemblies = $loadContext.LoadFromAssemblyPath($assemblyPath)

    return @{ "yaml"= $assemblies }
}

function Invoke-LoadInGlobalContext {
    param(
        [string]$assemblyPath
    )
    $assemblies = [Reflection.Assembly]::LoadFrom($assemblyPath)
    return @{ "yaml"= $assemblies }
}


function Invoke-LoadAssembly {
    $libDir = Join-Path $here "lib"
    $assemblies = @{
        "core" = Join-Path $libDir "netstandard2.1\YamlDotNet.dll";
        "net45" = Join-Path $libDir "net45\YamlDotNet.dll";
        "net35" = Join-Path $libDir "net35\YamlDotNet.dll";
    }

    if ($PSVersionTable.Keys -contains "PSEdition") {
        if ($PSVersionTable.PSEdition -eq "Core") {
            return (Invoke-LoadInContext -assemblyPath $assemblies["core"] -loadContextName "powershellyaml")
        } elseif ($PSVersionTable.PSVersion.Major -gt 5.1) {
            return (Invoke-LoadInContext -assemblyPath $assemblies["net45"] -loadContextName "powershellyaml")
        } elseif ($PSVersionTable.PSVersion.Major -ge 4) {
            return (Invoke-LoadInGlobalContext $assemblies["net45"])
        } else {
            return (Invoke-LoadInGlobalContext $assemblies["net35"])
        }
    } else { # Powershell 4.0 and lower do not know "PSEdition" yet
        return (Invoke-LoadInGlobalContext $assemblies["net35"])
    }
}

$assemblies = Invoke-LoadAssembly
$yamlDotNetAssembly = $assemblies["yaml"]


if (!([System.Management.Automation.PSTypeName]'StringQuotingEmitter').Type) {
    $referenceList = @($yamlDotNetAssembly.Location,[Text.RegularExpressions.Regex].Assembly.Location)
    if ($PSVersionTable.PSEdition -eq "Core") {
        $referenceList += [IO.Directory]::GetFiles([IO.Path]::Combine($PSHOME, 'ref'), 'netstandard.dll', [IO.SearchOption]::TopDirectoryOnly)
        $destinations = @("lib/netstandard2.1")
    } else {
        $referenceList += 'System.Runtime.dll'
        $destinations = @("lib/net45", "lib/net35")
    }
}

$destinations = @("lib/netstandard2.1", "lib/net45", "lib/net35")

foreach ($target in $destinations) {
    $targetPath = Join-Path $here $target
    $file = Join-Path $targetPath "StringQuotingEmitter.dll"
    if (!(Test-Path $file)) {
        if ($PSVersionTable.PSEdition -eq "Core") {
            Add-Type -TypeDefinition $source -ReferencedAssemblies $referenceList -Language CSharp -CompilerOptions "-nowarn:1701" -OutputAssembly $file
        } else {
            Add-Type -TypeDefinition $source -ReferencedAssemblies $referenceList -Language CSharp -OutputAssembly $file
        }
    }
}