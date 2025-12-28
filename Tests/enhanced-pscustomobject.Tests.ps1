BeforeAll {
    # Only import if not already loaded to avoid assembly reload issues
    if (-not (Get-Module -Name powershell-yaml)) {
        Import-Module $PSScriptRoot/../powershell-yaml.psd1
    }
}

Describe 'Enhanced PSCustomObject Mode Tests' {

    Context 'Basic Enhanced PSCustomObject Creation' {
        It 'Should create enhanced PSCustomObject with -As [PSCustomObject]' {
            $yaml = @"
name: John
age: 30
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj | Should -Not -BeNullOrEmpty
            $obj.name | Should -Be 'John'
            $obj.age | Should -Be 30
            Test-YamlMetadata $obj | Should -Be $true
        }

        It 'Should create nested enhanced PSCustomObjects' {
            $yaml = @"
person:
  name: John
  age: 30
  address:
    city: New York
    zip: 10001
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.person.name | Should -Be 'John'
            $obj.person.address.city | Should -Be 'New York'
            Test-YamlMetadata $obj | Should -Be $true
            Test-YamlMetadata $obj.person | Should -Be $true
            Test-YamlMetadata $obj.person.address | Should -Be $true
        }

        It 'Should handle arrays in enhanced PSCustomObject' {
            $yaml = @"
items:
  - name: item1
    value: 100
  - name: item2
    value: 200
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.items | Should -HaveCount 2
            $obj.items[0].name | Should -Be 'item1'
            $obj.items[1].value | Should -Be 200
        }

        It 'Should return regular hashtable when -As is not specified' {
            $yaml = @"
name: John
age: 30
"@
            $obj = ConvertFrom-Yaml $yaml
            $obj | Should -BeOfType [hashtable]
            Test-YamlMetadata $obj | Should -Be $false
        }
    }

    Context 'Property Comment Operations' {
        It 'Should set and get property comments' {
            $yaml = @"
name: John
age: 30
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj | Set-YamlPropertyComment -PropertyName 'name' -Comment 'User full name'

            $comment = Get-YamlPropertyComment -InputObject $obj -PropertyName 'name'
            $comment | Should -Be 'User full name'
        }

        It 'Should preserve inline comments from YAML' {
            $yaml = @"
name: John  # User's full name
age: 30     # Age in years
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Comments should be preserved from source YAML
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'name' | Should -Be "User's full name"
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'age' | Should -Be 'Age in years'
        }

        It 'Should preserve block comments from YAML' {
            $yaml = @"
# This is the user's name
name: John
# This is the user's age
age: 30
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Block comments should be preserved
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'name' | Should -Be "This is the user's name"
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'age' | Should -Be "This is the user's age"
        }

        It 'Should prefer inline comments over block comments' {
            $yaml = @"
# Block comment
name: John  # Inline comment
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Inline comment should take precedence
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'name' | Should -Be 'Inline comment'
        }

        It 'Should support programmatic comment addition' {
            $yaml = @"
name: John
age: 30
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Metadata store should exist even if no comments in source
            Test-YamlMetadata $obj | Should -Be $true

            # Add comments programmatically
            $obj | Set-YamlPropertyComment -PropertyName 'name' -Comment 'User full name'
            $obj | Set-YamlPropertyComment -PropertyName 'age' -Comment 'Age in years'

            # Verify comments are stored
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'name' | Should -Be 'User full name'
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'age' | Should -Be 'Age in years'
        }

        It 'Should return null for non-existent property comment' {
            $yaml = @"
name: John
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $comment = Get-YamlPropertyComment -InputObject $obj -PropertyName 'nonexistent'
            $comment | Should -BeNullOrEmpty
        }

        It 'Should warn when setting comment on non-enhanced object' {
            $obj = [PSCustomObject]@{ name = 'John' }
            $warnings = $obj | Set-YamlPropertyComment -PropertyName 'name' -Comment 'test' 3>&1
            $warnings | Should -Match 'does not have YAML metadata'
        }

        It 'Should allow comments on nested properties' {
            $yaml = @"
database:
  host: localhost
  port: 5432
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Set comment on nested property
            $obj.database | Set-YamlPropertyComment -PropertyName 'host' -Comment 'Database server'
            $obj.database | Set-YamlPropertyComment -PropertyName 'port' -Comment 'Database port'

            # Retrieve nested comments
            Get-YamlPropertyComment -InputObject $obj.database -PropertyName 'host' | Should -Be 'Database server'
            Get-YamlPropertyComment -InputObject $obj.database -PropertyName 'port' | Should -Be 'Database port'
        }
    }

    Context 'Scalar Style Operations' {
        It 'Should set scalar style for property' {
            $yaml = @"
description: Some text
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj | Set-YamlPropertyScalarStyle -PropertyName 'description' -Style Literal

            # Verify it doesn't throw
            $obj | Should -Not -BeNullOrEmpty
        }

        It 'Should accept valid scalar styles' {
            $yaml = "text: value"
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            { $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style Plain } | Should -Not -Throw
            { $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style SingleQuoted } | Should -Not -Throw
            { $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style DoubleQuoted } | Should -Not -Throw
            { $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style Literal } | Should -Not -Throw
            { $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style Folded } | Should -Not -Throw
        }
    }

    Context 'Test-YamlMetadata Function' {
        It 'Should return true for enhanced PSCustomObject' {
            $yaml = "name: John"
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            Test-YamlMetadata $obj | Should -Be $true
        }

        It 'Should return false for regular PSCustomObject' {
            $obj = [PSCustomObject]@{ name = 'John' }
            Test-YamlMetadata $obj | Should -Be $false
        }

        It 'Should return false for hashtable' {
            $yaml = "name: John"
            $obj = ConvertFrom-Yaml $yaml
            Test-YamlMetadata $obj | Should -Be $false
        }
    }

    Context 'Complex Nested Structures' {
        It 'Should handle deeply nested objects' {
            $yaml = @"
level1:
  level2:
    level3:
      value: deep
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.level1.level2.level3.value | Should -Be 'deep'
            Test-YamlMetadata $obj.level1.level2.level3 | Should -Be $true
        }

        It 'Should handle mixed arrays and objects' {
            $yaml = @"
users:
  - name: John
    roles:
      - admin
      - user
  - name: Jane
    roles:
      - user
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.users[0].name | Should -Be 'John'
            $obj.users[0].roles[0] | Should -Be 'admin'
            $obj.users[1].roles | Should -HaveCount 1
        }
    }

    Context 'Type Preservation' {
        It 'Should preserve boolean types' {
            $yaml = @"
enabled: true
disabled: false
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.enabled | Should -BeOfType [bool]
            $obj.enabled | Should -Be $true
            $obj.disabled | Should -Be $false
        }

        It 'Should preserve numeric types' {
            $yaml = @"
integer: 42
long: 9223372036854775807
decimal: 3.14159
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.integer | Should -BeOfType [int]
            $obj.integer | Should -Be 42
            $obj.decimal | Should -Be 3.14159
        }

        It 'Should handle null values' {
            $yaml = @"
name: John
middle: null
age: 30
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.name | Should -Be 'John'
            $obj.middle | Should -BeNullOrEmpty
            $obj.age | Should -Be 30
        }

        It 'Should preserve BigInteger types' {
            $yaml = @"
bignum: 9999999999999999999999999999999999999999999999999
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.bignum | Should -BeOfType [System.Numerics.BigInteger]
            $obj.bignum | Should -Be ([System.Numerics.BigInteger]::Parse("9999999999999999999999999999999999999999999999999"))
        }

        It 'Should round-trip BigInteger values correctly' {
            $yaml = @"
bignum: 9999999999999999999999999999999999999999999999999
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $newYaml = ConvertTo-Yaml $obj
            $obj2 = ConvertFrom-Yaml $newYaml -As ([PSCustomObject])

            $obj2.bignum | Should -BeOfType [System.Numerics.BigInteger]
            $obj2.bignum | Should -Be $obj.bignum
        }

        It 'Should preserve DateTime types' {
            $yaml = @"
timestamp: 2024-01-15T10:30:00Z
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.timestamp | Should -BeOfType [DateTime]
        }

        It 'Should round-trip DateTime values correctly' {
            $yaml = @"
timestamp: 2024-01-15T10:30:00.0000000Z
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $newYaml = ConvertTo-Yaml $obj
            $obj2 = ConvertFrom-Yaml $newYaml -As ([PSCustomObject])

            $obj2.timestamp | Should -BeOfType [DateTime]
            # Compare as strings because DateTime comparison can be tricky with timezones
            $obj2.timestamp.ToString("o") | Should -Be $obj.timestamp.ToString("o")
        }

        It 'Should handle BigInteger in arrays' {
            $yaml = @"
numbers:
  - 9999999999999999999999999999999999999999999999999
  - 8888888888888888888888888888888888888888888888888
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.numbers[0] | Should -BeOfType [System.Numerics.BigInteger]
            $obj.numbers[1] | Should -BeOfType [System.Numerics.BigInteger]
        }

        It 'Should round-trip BigInteger arrays correctly' {
            $yaml = @"
numbers:
  - 9999999999999999999999999999999999999999999999999
  - 8888888888888888888888888888888888888888888888888
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $newYaml = ConvertTo-Yaml $obj
            $obj2 = ConvertFrom-Yaml $newYaml -As ([PSCustomObject])

            $obj2.numbers[0] | Should -Be $obj.numbers[0]
            $obj2.numbers[1] | Should -Be $obj.numbers[1]
        }
    }

    Context 'Backward Compatibility' {
        It 'Should maintain original behavior without -As parameter' {
            $yaml = @"
name: John
age: 30
"@
            $obj = ConvertFrom-Yaml $yaml
            $obj | Should -BeOfType [hashtable]
            $obj['name'] | Should -Be 'John'
            $obj['age'] | Should -Be 30
        }

        It 'Should work with -Ordered parameter when not using -As' {
            $yaml = @"
z: last
a: first
"@
            $obj = ConvertFrom-Yaml $yaml -Ordered
            $obj | Should -Not -BeNullOrEmpty
            # Ordered hashtable functionality is preserved
        }
    }

    Context 'Metadata Persistence Through Properties' {
        It 'Should maintain metadata on nested objects' {
            $yaml = @"
database:
  host: localhost
  port: 5432
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Set comment on nested object
            $obj.database | Set-YamlPropertyComment -PropertyName 'host' -Comment 'Database server address'

            $comment = Get-YamlPropertyComment -InputObject $obj.database -PropertyName 'host'
            $comment | Should -Be 'Database server address'
        }

        It 'Should allow setting metadata on multiple properties' {
            $yaml = @"
name: John
age: 30
email: john@example.com
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj | Set-YamlPropertyComment -PropertyName 'name' -Comment 'Full name'
            $obj | Set-YamlPropertyComment -PropertyName 'age' -Comment 'Age in years'
            $obj | Set-YamlPropertyComment -PropertyName 'email' -Comment 'Contact email'

            Get-YamlPropertyComment -InputObject $obj -PropertyName 'name' | Should -Be 'Full name'
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'age' | Should -Be 'Age in years'
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'email' | Should -Be 'Contact email'
        }

        It 'Should handle updating existing comments' {
            $yaml = "name: John"
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj | Set-YamlPropertyComment -PropertyName 'name' -Comment 'First comment'
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'name' | Should -Be 'First comment'

            $obj | Set-YamlPropertyComment -PropertyName 'name' -Comment 'Updated comment'
            Get-YamlPropertyComment -InputObject $obj -PropertyName 'name' | Should -Be 'Updated comment'
        }
    }

    Context 'Scalar Style Metadata' {
        It 'Should set and preserve scalar styles for different properties' {
            $yaml = @"
title: Simple Title
description: |
  Multi-line
  description
code: >
  Folded
  code
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Set different styles
            $obj | Set-YamlPropertyScalarStyle -PropertyName 'title' -Style DoubleQuoted
            $obj | Set-YamlPropertyScalarStyle -PropertyName 'description' -Style Literal
            $obj | Set-YamlPropertyScalarStyle -PropertyName 'code' -Style Folded

            # Verify no errors occurred
            Test-YamlMetadata $obj | Should -Be $true
        }

        It 'Should allow changing scalar style after initial setting' {
            $yaml = "text: value"
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style Plain
            $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style DoubleQuoted
            $obj | Set-YamlPropertyScalarStyle -PropertyName 'text' -Style SingleQuoted

            Test-YamlMetadata $obj | Should -Be $true
        }
    }

    Context 'Edge Cases and Error Handling' {
        It 'Should handle empty YAML document' {
            $yaml = ""
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj | Should -BeNullOrEmpty
        }

        It 'Should handle YAML with only whitespace' {
            $yaml = "   `n  `n   "
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj | Should -BeNullOrEmpty
        }

        It 'Should handle arrays with null elements' {
            $yaml = @"
items:
  - value1
  - null
  - value3
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.items | Should -HaveCount 3
            $obj.items[0] | Should -Be 'value1'
            $obj.items[1] | Should -BeNullOrEmpty
            $obj.items[2] | Should -Be 'value3'
        }

        It 'Should handle special YAML values' {
            $yaml = @"
null_value: null
tilde_null: ~
true_value: true
false_value: false
yes_value: yes
no_value: no
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.null_value | Should -BeNullOrEmpty
            $obj.tilde_null | Should -BeNullOrEmpty
            $obj.true_value | Should -Be $true
            $obj.false_value | Should -Be $false
        }

        It 'Should handle quoted strings that look like other types' {
            $yaml = @"
string_number: "123"
string_bool: "true"
string_null: "null"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.string_number | Should -Be '123'
            $obj.string_bool | Should -Be 'true'
            $obj.string_null | Should -Be 'null'
        }
    }

    Context 'Integration with Existing Functions' {
        It 'Should work with pipeline operations' {
            $yaml = @"
users:
  - name: Alice
    age: 25
  - name: Bob
    age: 30
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Pipelineoperations should work
            $obj.users | ForEach-Object { $_.name } | Should -Contain 'Alice'
            $obj.users | Where-Object { $_.age -gt 25 } | Should -HaveCount 1
        }

        It 'Should allow property access like regular PSCustomObject' {
            $yaml = "name: John`nage: 30"
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Standard property access
            $obj.name | Should -Be 'John'
            $obj.PSObject.Properties['age'].Value | Should -Be 30

            # Property enumeration
            $properties = $obj.PSObject.Properties.Name
            $properties | Should -Contain 'name'
            $properties | Should -Contain 'age'
        }

        It 'Should support Get-Member on enhanced objects' {
            $yaml = "name: John`nage: 30"
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $members = $obj | Get-Member -MemberType NoteProperty
            $members | Should -Not -BeNullOrEmpty
            $members.Name | Should -Contain 'name'
            $members.Name | Should -Contain 'age'
        }
    }

    Context 'YAML Style Preservation' {
        It 'Should preserve flow mapping style' {
            $yaml = @"
flow_map: {key1: value1, key2: value2}
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '\{.*\}'
        }

        It 'Should preserve flow sequence style' {
            $yaml = @"
flow_seq: [item1, item2, item3]
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '\[.*\]'
        }

        It 'Should preserve literal string style (|)' {
            $yaml = @"
description: |
  This is a multi-line
  literal string.
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '\|'
        }

        It 'Should preserve folded string style (>)' {
            $yaml = @"
description: >
  This is a folded
  multi-line string.
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '>'
        }

        It 'Should preserve single-quoted strings' {
            $yaml = @"
text: 'hello world'
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match "'"
        }

        It 'Should preserve double-quoted strings' {
            $yaml = @"
text: "hello world"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '"'
        }

        It 'Should preserve mixed flow and block styles' {
            $yaml = @"
server:
  name: web-01
  ports: [80, 443]
  config: {debug: true, timeout: 30}
  items:
    - one
    - two
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '\[.*\]'
            $result | Should -Match '\{.*\}'
        }

        It 'Should preserve styles after value modification' {
            $yaml = @"
ports: [80, 443]
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.ports = @(8080, 8443)
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '\[.*\]'
        }
    }

    Context 'YAML Tag Preservation' {
        It 'Should preserve tags when values are unchanged' {
            $yaml = @"
number: !!int 42
text: !!str hello
flag: !!bool true
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '!!int'
            $result | Should -Match '!!str'
            $result | Should -Match '!!bool'
        }

        It 'Should preserve tags when value changes but type stays same' {
            $yaml = @"
number: !!int 42
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.number = 99
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '!!int 99'
        }

        It 'Should remove tags when type changes' {
            $yaml = @"
number: !!int 42
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.number = "not a number"
            $result = ConvertTo-Yaml $obj

            $result | Should -Not -Match '!!int'
        }

        It 'Should not emit tags when source YAML has no tags' {
            $yaml = @"
number: 42
text: hello
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Not -Match '!!'
        }

        It 'Should preserve timestamp tags' {
            $yaml = @"
created: !!timestamp 2023-01-15T10:30:00Z
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '!!timestamp'
        }

        It 'Should preserve float tags' {
            $yaml = @"
value: !!float 3.14
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '!!float'
        }

        It 'Should preserve tags in nested objects' {
            $yaml = @"
server:
  port: !!int 8080
  host: !!str localhost
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '!!int'
            $result | Should -Match '!!str'
        }

        It 'Should preserve non-specific tag (!) to prevent type inference' {
            $yaml = @"
number: ! 42
flag: ! true
version: ! 1.2.3
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Values should be treated as strings due to "!" tag
            $obj.number | Should -BeOfType [string]
            $obj.number | Should -Be "42"
            $obj.flag | Should -BeOfType [string]
            $obj.flag | Should -Be "true"
            $obj.version | Should -BeOfType [string]
            $obj.version | Should -Be "1.2.3"

            # Round-trip should preserve the "!" tag
            $result = ConvertTo-Yaml $obj
            $result | Should -Match 'number: ! 42'
            $result | Should -Match 'flag: ! true'
            $result | Should -Match 'version: ! 1\.2\.3'

            # Parse again to verify it still prevents type inference
            $obj2 = ConvertFrom-Yaml $result -As ([PSCustomObject])
            $obj2.number | Should -BeOfType [string]
            $obj2.flag | Should -BeOfType [string]
            $obj2.version | Should -BeOfType [string]
        }

        It 'Should preserve custom tags for round-trip' {
            $yaml = @"
id: !uuid 550e8400-e29b-41d4-a716-446655440000
config: !include config.yaml
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            # Values should be strings
            $obj.id | Should -BeOfType [string]
            $obj.config | Should -BeOfType [string]

            # Round-trip should preserve custom tags
            $result = ConvertTo-Yaml $obj
            $result | Should -Match '!uuid'
            $result | Should -Match '!include'
            $result | Should -Match '550e8400-e29b-41d4-a716-446655440000'
            $result | Should -Match 'config\.yaml'
        }
    }

    Context 'Quoted Scalar Type Rules' {
        It 'Bare scalars should be type-inferred' {
            $yaml = @"
number: 42
flag: true
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.number | Should -BeOfType [int]
            $obj.flag | Should -BeOfType [bool]
        }

        It 'Double-quoted scalars should be strings (no tag)' {
            $yaml = @"
number: "42"
flag: "true"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.number | Should -BeOfType [string]
            $obj.number | Should -Be "42"
            $obj.flag | Should -BeOfType [string]
            $obj.flag | Should -Be "true"
        }

        It 'Single-quoted scalars should be strings (no tag)' {
            $yaml = @"
number: '42'
flag: 'true'
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.number | Should -BeOfType [string]
            $obj.number | Should -Be "42"
            $obj.flag | Should -BeOfType [string]
            $obj.flag | Should -Be "true"
        }

        It 'Tagged quoted scalars should use tag type (tag overrides quotes)' {
            $yaml = @"
number: !!int "42"
flag: !!bool "false"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.number | Should -BeOfType [int]
            $obj.number | Should -Be 42
            $obj.flag | Should -BeOfType [bool]
            $obj.flag | Should -Be $false
        }

        It 'Scientific notation should be parsed as decimal' {
            $yaml = @"
value: 1.23e-4
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.value | Should -BeOfType [decimal]
        }

        It 'Quoted scientific notation should remain string' {
            $yaml = @"
value: "1.23e-4"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.value | Should -BeOfType [string]
            $obj.value | Should -Be "1.23e-4"
        }

        It 'Very large numbers should be BigInteger (not scientific notation)' {
            $yaml = @"
bignum: 999999999999999999999999999999999
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.bignum | Should -BeOfType [System.Numerics.BigInteger]
            $obj.bignum.ToString() | Should -Not -Match 'e|E'
        }

        It 'Literal block scalars should be strings' {
            $yaml = @"
text: |
  42
  true
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.text | Should -BeOfType [string]
            $obj.text | Should -Match "42"
        }

        It 'Folded block scalars should be strings' {
            $yaml = @"
text: >
  42
  true
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])

            $obj.text | Should -BeOfType [string]
        }
    }

    Context 'Tag and Quote Style Combined' {
        It 'Should preserve both tag and double quotes' {
            $yaml = @"
number: !!int "42"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '!!int "42"'
        }

        It 'Should preserve both tag and single quotes' {
            $yaml = @"
number: !!int '42'
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match "!!int '42'"
        }

        It 'Should preserve tag and quotes after value change' {
            $yaml = @"
number: !!int "42"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.number = 99
            $result = ConvertTo-Yaml $obj

            $result | Should -Match '!!int "99"'
        }

        It 'Should remove tag but keep quotes when type changes' {
            $yaml = @"
number: !!int "42"
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $obj.number = "not a number"
            $result = ConvertTo-Yaml $obj

            $result | Should -Not -Match '!!int'
            $result | Should -Match '"not a number"'
        }

        It 'Should handle mixed tag and quote styles' {
            $yaml = @"
a: !!int "42"
b: "hello"
c: !!str 99
d: 'world'
"@
            $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
            $result = ConvertTo-Yaml $obj

            $result | Should -Match 'a: !!int "42"'
            $result | Should -Match 'b: "hello"'
            $result | Should -Match 'c: !!str'
            $result | Should -Match "d: 'world'"
        }
    }
}
