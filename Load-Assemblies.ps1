$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir = Join-Path $here "lib"

function Get-ServerLevelKey {
    <#
    .SYNOPSIS
    Returns the path to the registry location where information about the server levels is stored
    #>
    PROCESS {
        return "HKLM:Software\Microsoft\Windows NT\CurrentVersion\Server\ServerLevels"
    }
}

function Get-IsNanoServer {
    <#
    .SYNOPSIS
    Return a boolean value of $true if we are running on a Nano server version.
    #>
    PROCESS {
        $serverLevelKey = Get-ServerLevelKey
        if (!(Test-Path $serverLevelKey)){
            # We are most likely running on a workstation version
            return $false
        }
        $serverLevels = Get-ItemProperty $serverLevelKey
        return ($serverLevels.NanoServer -eq 1)
    }
}

function Initialize-Assemblies {
    $isNano = Get-IsNanoServer
    if($isNano){
        # Load the portable assembly
        $assemblyDir = Join-Path $libDir "net45"
    } else {
        $assemblyDir = Join-Path $libDir "net35"
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