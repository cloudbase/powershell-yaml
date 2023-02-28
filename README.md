# powershell-yaml

This powershell module is a thin wrapper on top of [YamlDotNet](https://github.com/aaubry/YamlDotNet "YamlDotNet") that serializes and un-serializes simple powershell objects to and from YAML. It was tested on powershell versions 4 and 5, supports [Nano Server](https://technet.microsoft.com/en-us/library/mt126167.aspx "Nano") and apparently works with powershell on Linux. I suspect it works on Mac as well, but I have not had a chance to test it.

The ```lib``` folder contains the YamlDotNet assemblies. They are not really required, just a fall-back in case your system does not already have them installed and loaded. Feel free to remove the ```lib``` folder if you prefer to add the required assemblies yourself.

## Installation

This module is available for installation via [Powershell Gallery](http://www.powershellgallery.com/). Simply run the following command:

```powershell
Install-Module powershell-yaml
```

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

## Merge keys support

```powershell

$mergingYaml = @"
---
default: &default
  value1: 1
  value2: 2

hoge:
  <<: *default
  value3: 3
"@

ConvertFrom-Yaml -Yaml $mergingYaml -UseMergingParser

Name                           Value
----                           -----
default                        {value1, value2}
hoge                           {value2, value3, value1}

```

Important note: For the time being, overwriting keys will throw a duplicate key exception.

```powershell
$mergingYamlWithDuplicates = @"
---
default: &default
  value1: 1
  value2: 2

hoge:
  <<: *default
  # this is a duplicate
  value1: 44
  value3: 3
"@
```

## Converting from YAML to JSON

The awesome YamlDotNet assembly allows us to serialize an object in a JSON compatible way. Unfortunately it does not support indentation. Here is a simple example:

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

PS C:\> ConvertTo-Yaml -JsonCompatible $obj
{"anArray": [1, 2, 3], "nested": {"array": ["this", "is", "an", "array"]}, "hello": "world"}

# Or you could do it in one line.
PS C:\> ConvertFrom-Yaml $yaml | ConvertTo-Yaml -JsonCompatible
{"anArray": [1, 2, 3], "nested": {"array": ["this", "is", "an", "array"]}, "hello": "world"}

```

## Using tags

Using tags is prefered as opposed to allowing ```powershell-yaml``` to infer the type. Whenever there is a risc of ambiguity, use tags to make sure your values are converted using the intended type. This module supports the [tags specified by the core schema](http://yaml.org/spec/1.2-old/spec.html#id2804923), and aditionally the ```!!timestamp``` tag.

```powershell
Import-Module powershell-yaml

PS C:\> $data = @"
aPhoneNumber: !!str +40123456789
aPhoneNrWithoutTags: +40123456789
"@
PS C:\> ConvertFrom-Yaml $data

Name                           Value
----                           -----
aPhoneNrWithoutTags            40123456789
aPhoneNumber                   +40123456789

PS C:\> $obj = ConvertFrom-Yaml $data
PS C:\> $obj.aPhoneNumber.GetType()

IsPublic IsSerial Name                                     BaseType
-------- -------- ----                                     --------
True     True     String                                   System.Object

PS C:\> $obj.aPhoneNrWithoutTags.GetType()

IsPublic IsSerial Name                                     BaseType
-------- -------- ----                                     --------
True     True     Int64                                    System.ValueType
```

As you can see, the phone number without tags was cast to ```Int64```. This is most likely not the desired result and a case where tags should be used.

## Running the tests

Before running the associated unit tests; please make sure you have
[Pester](https://github.com/pester/pester) installed, as it is the testing
framework of choice.

After Pester is up and running, the tests may be ran by simply entering the
tests directory and running `Invoke-Pester`:

```powershell
PS C:\> Install-Module Pester
PS C:\> Install-Module Assert
PS C:\> git clone https://github.com/cloudbase/powershell-yaml.git $HOME\powershell-yaml
PS C:\> cd $HOME\powershell-yaml
PS C:\Users\Guest\powershell-yaml> powershell.exe -NonInteractive -Command {Invoke-Pester}
```
