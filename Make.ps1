[CmdletBinding()]
param(
	[switch]$NoFormat = $false,
	[switch]$NoTest = $false)

function Is-Loaded {
	[CmdletBinding()]
	param(
		[string]$Module,
		[version]$Version)

	$mod = Get-Module -Name $Module
	return $mod -ne $null -and $mod.version -eq $Version
}

function Is-Available {
	[CmdletBinding()]
	param(
		[string]$Module,
		[version]$Version)

	$mod = Get-Module -Name $Module -ListAvailable
	return $mod -ne $null -and $mod.version -eq $Version
}

function Ensure-Loaded {
	[CmdletBinding()]
	param(
		[string]$Module,
		[version]$Version)

	if (Is-Available $Module $Version) {
		Write-Verbose "$Module $Version is available"
		if (Is-Loaded $Module $Version) {
			Write-Verbose "$Module $Version is loaded"
		} else {
			Write-Verbose "$Module $Version is not loaded. Importing..."
			Import-Module $Module -RequiredVersion $Version
		}
	} else {
		Write-Verbose "$Module $Version is not available. Installing..."
		Install-Module $Module -RequiredVersion $Version
	}
}

function Format-Files {
	$files = Get-ChildItem -Path $PWD -Include *.ps1,*.psm1 -Recurse
	Write-Verbose "Formatting files:"
	$files | ForEach-Object { Write-Verbose "- $_" }
	$files | Edit-DTWBeautifyScript -IndentType Tabs -NewLine LF
}

if (-not $NoFormat) {
	Ensure-Loaded PowerShell-Beautifier 1.2.3
	Format-Files
}

if (-not $NoTest) {
	Ensure-Loaded Pester 4.1.1
	Invoke-Pester
}
