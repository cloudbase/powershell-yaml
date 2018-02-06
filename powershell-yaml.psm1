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
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[string]$Yaml
	)
	process {
		$stringReader = New-Object System.IO.StringReader ($Yaml)
		$yamlStream = New-Object "YamlDotNet.RepresentationModel.YamlStream"
		$yamlStream.Load([System.IO.TextReader]$stringReader)
		$stringReader.Close()
		return $yamlStream
	}
}

function Convert-ValueToProperType {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[System.Object]$Value
	)
	process {
		if (!($Value -is [string])) {
			return $Value
		}
		$types = @( [int],[long],[double],[boolean],[decimal])
		foreach ($i in $types) {
			$parsedValue = New-Object -TypeName $i.FullName
			if ($i.IsAssignableFrom([boolean])) {
				$result = $i::TryParse($Value,[ref]$parsedValue)
			} else {
				$result = $i::TryParse($Value,[Globalization.NumberStyles]::Any,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsedValue)
			}
			if ($result) {
				return $parsedValue
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
		if ([Text.RegularExpressions.Regex]::IsMatch($Value,$regex,[Text.RegularExpressions.RegexOptions]::IgnorePatternWhitespace)) {
			[datetime]$datetime = [datetime]::MinValue
			if (([datetime]::TryParse($Value,[ref]$datetime))) {
				return $datetime
			}
		}

		return $Value
	}
}

function Convert-YamlMappingToHashtable {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[YamlDotNet.RepresentationModel.YamlMappingNode]$Node,
		[switch]$Ordered
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
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[YamlDotNet.RepresentationModel.YamlSequenceNode]$Node
	)
	process {
		$ret = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
		foreach ($i in $Node.Children) {
			$ret.Add((Convert-YamlDocumentToPSObject $i))
		}
		return,$ret
	}
}

function Convert-YamlDocumentToPSObject {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[System.Object]$Node,
		[switch]$Ordered
	)
	process {
		switch ($Node.GetType().FullName) {
			"YamlDotNet.RepresentationModel.YamlMappingNode" {
				return Convert-YamlMappingToHashtable $Node -Ordered:$Ordered
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
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[hashtable]$Data
	)
	foreach ($i in $($data.Keys)) {
		$Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
	}
	return $Data
}

function Convert-OrderedHashtableToDictionary {
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[System.Collections.Specialized.OrderedDictionary]$Data
	)
	foreach ($i in $($data.Keys)) {
		$Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
	}
	return $Data
}

function Convert-ListToGenericList {
	param(
		[Parameter(Mandatory = $false,ValueFromPipeline = $true)]
		[array]$Data = @()
	)
	for ($i = 0; $i -lt $Data.Count; $i++) {
		$Data[$i] = Convert-PSObjectToGenericObject $Data[$i]
	}
	return,$Data
}

function Convert-PSCustomObjectToDictionary {
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[pscustomobject]$Data
	)
	$ret = [System.Collections.Generic.Dictionary[string,object]](New-Object 'System.Collections.Generic.Dictionary[string,object]')
	foreach ($i in $Data.psobject.properties) {
		$ret[$i.Name] = Convert-PSObjectToGenericObject $i.Value
	}
	return $ret
}

function Convert-PSObjectToGenericObject {
	param(
		[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
		[System.Object]$Data
	)
	$dataType = $data.GetType()
	if ($dataType.FullName -eq "System.Management.Automation.PSCustomObject") {
		return Convert-PSCustomObjectToDictionary $data
	} elseif (([System.Collections.Specialized.OrderedDictionary].IsAssignableFrom($dataType))) {
		return Convert-OrderedHashtableToDictionary $data
	} elseif (([System.Collections.IDictionary].IsAssignableFrom($dataType))) {
		return Convert-HashtableToDictionary $data
	} elseif (([System.Collections.IList].IsAssignableFrom($dataType))) {
		return Convert-ListToGenericList $data
	}
	return $data
}

function ConvertFrom-Yaml {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false,ValueFromPipeline = $true)]
		[string]$Yaml,
		[switch]$AllDocuments = $false,
		[switch]$Ordered
	)

	process {
		if (!$Yaml) {
			return
		}
		$documents = Get-YamlDocuments -Yaml $Yaml
		if (!$documents.Count) {
			return
		}
		if ($documents.Count -eq 1) {
			return Convert-YamlDocumentToPSObject $documents[0].RootNode -Ordered:$Ordered
		}
		if (!$AllDocuments) {
			return Convert-YamlDocumentToPSObject $documents[0].RootNode -Ordered:$Ordered
		}
		$ret = @()
		foreach ($i in $documents) {
			$ret += Convert-YamlDocumentToPSObject $i.RootNode -Ordered:$Ordered
		}
		return $ret
	}
}

function ConvertTo-Yaml {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false,ValueFromPipeline = $true)]
		[System.Object]$Data,
		[Parameter(Mandatory = $false)]
		[string]$OutFile,
		[switch]$JsonCompatible = $false,
		[switch]$Force = $false
	)
	begin {
		$d = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
	}
	process {
		if ($data -is [System.Object]) {
			$d.Add($data)
		}
	}
	end {
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
				throw "Parent folder for specified path does not exist"
			}
			if ((Test-Path $OutFile) -and !$Force) {
				throw "Target file already exists. Use -Force to overwrite."
			}
			$wrt = New-Object "System.IO.StreamWriter" $OutFile
		} else {
			$wrt = New-Object "System.IO.StringWriter"
		}

		$options = 0
		if ($JsonCompatible) {
			# No indent options :~(
			$options = [YamlDotNet.Serialization.SerializationOptions]::JsonCompatible
		}
		try {
			$serializer = New-Object "YamlDotNet.Serialization.Serializer" $options
			$serializer.Serialize($wrt,$norm)
		} finally {
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
