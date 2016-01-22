# powershell-yaml

This powershell module is a thin wrapper on top of [YamlDotNet](https://github.com/aaubry/YamlDotNet "YamlDotNet") that serializes and un-serializes simple powershell objects to and from YAML. It was tested on powershell versions 4 and 5 and supports [Nano Server](https://technet.microsoft.com/en-us/library/mt126167.aspx Nano).

The ```lib``` folder contains the YamlDotNet assemblies. They are not really required, just a fall-back in case your system does not already have them installed and loaded. Feel free to remove the ```lib``` folder if you prefer to add the required assemblies yourself.

## ConvertTo-Yaml

```powershell
Import-Module powershell-yaml

PS C:\> $yaml = ConvertTo-Yaml @{"hello"="world"; "anArray"=@(1,2,3); "nested"=@{"array"=@("this", "is", "an", "array")}}
PS C:\> $yaml
anArray:
- 1
- 2
- 3
nested:
  array:
  - this
  - is
  - an
  - array
hello: world
```

## ConvertFrom-Yaml

### Single YAML document

```powershell
Import-Module powershell-yaml

PS C:\> $yaml = @"
anArray:
- 1
- 2
- 3
nested:
  array:
  - this
  - is
  - an
  - array
hello: world
"@

PS C:\> $obj = ConvertFrom-Yaml $yaml
PS C:\> $obj

Name                           Value
----                           -----
anArray                        {1, 2, 3}
nested                         {array}
hello                          world

PS C:\> $obj.GetType()

IsPublic IsSerial Name                                     BaseType
-------- -------- ----                                     --------
True     True     Hashtable                                System.Object
```

### Multiple YAML documents

Unserializing multiple documents results in an array representing the contents of each document. The result of this does not translate back to the same documents if you pass it back through ConvertTo-Yaml.

```powershell
Import-Module powershell-yaml

PS C:\> $yaml = @"
---
anArray:
- 1
- 2
- 3
nested:
  array:
  - this
  - is
  - an
  - array
hello: world
---
second: document
goodbye: world
"@

PS C:\> $obj = ConvertFrom-Yaml $yaml -AllDocuments
PS C:\> $obj

Name                           Value
----                           -----
anArray                        {1, 2, 3}
nested                         {array}
hello                          world
goodbye                        world
second                         document

PS C:\> $obj.GetType()

IsPublic IsSerial Name                                     BaseType
-------- -------- ----                                     --------
True     True     Object[]                                 System.Array

PS C:\> $obj[0]

Name                           Value
----                           -----
anArray                        {1, 2, 3}
nested                         {array}
hello                          world

PS C:\> $obj[1]

Name                           Value
----                           -----
goodbye                        world
second                         document
```

## Running the tests.

Before running the associated unit tests; please make sure you have
[Pester](https://github.com/pester/pester) installed, as it is the testing
framework of choice.

After Pester is up and running, the tests may be ran by simply entering the
tests directory and running `Invoke-Pester`:

```
PS C:\> git clone https://github.com/cloudbase/powershell-yaml.git $HOME\powershell-yaml
PS C:\> cd $HOME\powershell-yaml
PS C:\Users\Guest\powershell-yaml> powershell.exe -NonInteractive -Command {Invoke-Pester}
```
