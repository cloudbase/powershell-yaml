#!/usr/bin/env pwsh
# Typed YAML Tests: Typed Class Mode with ALC Isolation

BeforeAll {
    # Import the main module (now includes typed cmdlets)
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

    # Load test classes
    . "$PSScriptRoot/TypedYamlTestClasses.ps1"
}

Describe "Typed YAML: Module Loading and Type Availability" {
    It "Should load YamlBase type into Default ALC" {
        [PowerShellYaml.YamlBase] | Should -Not -BeNullOrEmpty
    }

    It "Should NOT export typed cmdlets (internal use only)" {
        Get-Command ConvertFrom-YamlTyped -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command ConvertTo-YamlTyped -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It "Should use unified API (ConvertFrom-Yaml with -As parameter)" {
        Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command ConvertTo-Yaml -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should allow PowerShell classes to inherit from YamlBase" {
        $obj = [SimpleConfig]::new()
        $obj -is [PowerShellYaml.YamlBase] | Should -BeTrue
    }
}

Describe "Typed YAML: Simple Deserialization" {
    It "Should deserialize simple YAML to typed object" {
        $yaml = @"
name: test-server
port: 9000
enabled: true
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config | Should -Not -BeNullOrEmpty
        $config.Name | Should -Be 'test-server'
        $config.Port | Should -Be 9000
        $config.Enabled | Should -BeTrue
    }

    It "Should preserve type information" {
        $yaml = "name: test`nport: 8080`nenabled: false"
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config -is [SimpleConfig] | Should -BeTrue
        $config -is [PowerShellYaml.YamlBase] | Should -BeTrue
    }

    It "Should use default values for missing properties" {
        $yaml = "name: minimal"
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Port | Should -Be 8080
        $config.Enabled | Should -BeTrue
    }

    It "Should handle boolean values correctly" {
        $yaml = @"
name: bool-test
port: 1000
enabled: false
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])
        $config.Enabled | Should -BeFalse
    }
}

Describe "Typed YAML: Simple Serialization" {
    It "Should serialize typed object to YAML" {
        $config = [SimpleConfig]::new()
        $config.Name = 'serialize-test'
        $config.Port = 3000
        $config.Enabled = $true

        $yaml = ConvertTo-Yaml $config

        $yaml | Should -Not -BeNullOrEmpty
        $yaml | Should -Match 'name: serialize-test'
        $yaml | Should -Match 'port: 3000'
        $yaml | Should -Match 'enabled: true'
    }
}

Describe "Typed YAML: Round-trip Testing" {
    It "Should preserve values through round-trip" {
        $yaml = @"
name: roundtrip-test
port: 7777
enabled: false
"@
        $config1 = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])
        $yaml2 = ConvertTo-Yaml $config1
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([SimpleConfig])

        $config2.Name | Should -Be 'roundtrip-test'
        $config2.Port | Should -Be 7777
        $config2.Enabled | Should -BeFalse
    }

    It "Should handle modifications in round-trip" {
        $yaml = "name: original`nport: 1000"
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Port = 2000
        $config.Enabled = $false

        $yaml2 = ConvertTo-Yaml $config
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([SimpleConfig])

        $config2.Port | Should -Be 2000
        $config2.Enabled | Should -BeFalse
    }
}

Describe "Typed YAML: Nested Object Support" {
    It "Should deserialize nested objects" {
        $yaml = @"
app-name: MyApp
database:
  host: db.example.com
  port: 5432
  database: mydb
  use-ssl: true
tags:
  - production
  - web
max-connections: 200
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        $config.AppName | Should -Be 'MyApp'
        $config.Database | Should -Not -BeNullOrEmpty
        $config.Database.Host | Should -Be 'db.example.com'
        $config.Database.Port | Should -Be 5432
        $config.Database.Database | Should -Be 'mydb'
        $config.Database.UseSsl | Should -BeTrue
        $config.Tags.Count | Should -Be 2
        $config.MaxConnections | Should -Be 200
    }

    It "Should verify nested object types" {
        $yaml = @"
app-name: TypeTest
database:
  host: localhost
  database: test
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        $config.Database -is [DatabaseConfig] | Should -BeTrue
        $config.Database -is [PowerShellYaml.YamlBase] | Should -BeTrue
    }

    It "Should serialize nested objects" {
        $config = [ComplexConfig]::new()
        $config.AppName = 'NestedTest'
        $config.Database = [DatabaseConfig]::new()
        $config.Database.Host = 'nested.example.com'
        $config.Database.Port = 3306
        $config.Database.Database = 'nested_db'

        $yaml = ConvertTo-Yaml $config

        $yaml | Should -Match 'app-name: NestedTest'
        $yaml | Should -Match 'database:'
        $yaml | Should -Match 'host: nested.example.com'
        $yaml | Should -Match 'port: 3306'
    }

    It "Should round-trip nested objects" {
        $yaml1 = @"
app-name: NestedRoundTrip
database:
  host: rt.example.com
  port: 5433
  database: rt_db
  use-ssl: false
"@
        $config1 = ConvertFrom-Yaml -Yaml $yaml1 -As ([ComplexConfig])
        $yaml2 = ConvertTo-Yaml $config1
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([ComplexConfig])

        $config2.Database.Host | Should -Be 'rt.example.com'
        $config2.Database.Port | Should -Be 5433
        $config2.Database.UseSsl | Should -BeFalse
    }
}

Describe "Typed YAML: Array/Collection Support" {
    It "Should deserialize string arrays" {
        $yaml = @"
app-name: ArrayTest
tags:
  - tag1
  - tag2
  - tag3
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        $config.Tags | Should -Not -BeNullOrEmpty
        $config.Tags.Count | Should -Be 3
        $config.Tags[0] | Should -Be 'tag1'
        $config.Tags[2] | Should -Be 'tag3'
    }

    It "Should serialize string arrays" {
        $config = [ComplexConfig]::new()
        $config.AppName = 'ArraySerialize'
        $config.Tags = @('alpha', 'beta', 'gamma')

        $yaml = ConvertTo-Yaml $config

        $yaml | Should -Match 'tags:'
        $yaml | Should -Match '- alpha'
        $yaml | Should -Match '- beta'
        $yaml | Should -Match '- gamma'
    }

    It "Should handle empty arrays" {
        $config = [ComplexConfig]::new()
        $config.AppName = 'EmptyArray'
        $config.Tags = @()

        $yaml = ConvertTo-Yaml $config
        $config2 = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Empty arrays may be deserialized as null or empty depending on YAML representation
        # Check that it's either null or an empty array
        if ($config2.Tags -eq $null) {
            # This is acceptable - empty array was serialized as empty/null
            $true | Should -BeTrue
        } else {
            $config2.Tags.Count | Should -Be 0
        }
    }
}

Describe "Typed YAML: Error Handling" {
    It "Should throw error for non-YamlBase type" {
        $yaml = "name: test"
        { ConvertFrom-Yaml -Yaml $yaml -As ([string]) } | Should -Throw
    }

    It "Should throw error for null type" {
        $yaml = "name: test"
        { ConvertFrom-Yaml -Yaml $yaml -As $null } | Should -Throw
    }

    It "Should handle invalid YAML gracefully" {
        $yaml = "invalid: yaml: structure: bad"
        { ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig]) } | Should -Throw
    }
}

Describe "Typed YAML: Type Conversion" {
    It "Should convert string to int" {
        $yaml = "name: test`nport: '9999'`nenabled: true"
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Port | Should -Be 9999
        $config.Port | Should -BeOfType [int]
    }

    It "Should convert string to bool" {
        $yaml = "name: test`nport: 1000`nenabled: 'true'"
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Enabled | Should -BeTrue
        $config.Enabled | Should -BeOfType [bool]
    }
}

Describe "Typed YAML: Type Validation" {
    # NOTE: Current implementation does NOT validate YAML type tags against class properties.
    # Type tags are captured as metadata but deserialization uses property types, not tags.
    # This is intentional - we trust the class schema over YAML tags.

    It "Should convert YAML !!int tag to string when property expects string" {
        $yaml = @"
name: !!int "42"
port: 8080
enabled: true
"@
        # Current behavior: Type tag is stored as metadata, but value is converted to property type
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Name | Should -Be "42"
        $config.Name | Should -BeOfType [string]
        # Type tag should be captured as metadata
        $config.GetPropertyTag('Name') | Should -Be 'tag:yaml.org,2002:int'
    }

    It "Should convert YAML !!str tag to int when property expects int" {
        $yaml = @"
name: test
port: !!str "8080"
enabled: true
"@
        # Current behavior: Type tag is stored as metadata, but value is converted to property type
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Port | Should -Be 8080
        $config.Port | Should -BeOfType [int]
        # Type tag should be captured as metadata
        $config.GetPropertyTag('Port') | Should -Be 'tag:yaml.org,2002:str'
    }

    It "Should convert YAML !!bool tag to string when property expects string" {
        $yaml = @"
name: !!bool "false"
port: 8080
enabled: true
"@
        # Current behavior: Type tag is stored as metadata, but value is converted to property type
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Name | Should -Be "false"
        $config.Name | Should -BeOfType [string]
        # Type tag should be captured as metadata
        $config.GetPropertyTag('Name') | Should -Be 'tag:yaml.org,2002:bool'
    }

    It "Should succeed when YAML tag matches property type" {
        $yaml = @"
name: !!str "test-server"
port: !!int "8080"
enabled: !!bool "true"
"@
        # This should succeed because tags match property types
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Name | Should -Be "test-server"
        $config.Port | Should -Be 8080
        $config.Enabled | Should -BeTrue
    }

    It "Should succeed when no explicit tags are provided" {
        $yaml = @"
name: test-server
port: 8080
enabled: true
"@
        # This should succeed - YamlDotNet infers types automatically
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        $config.Name | Should -Be "test-server"
        $config.Port | Should -Be 8080
        $config.Enabled | Should -BeTrue
    }

    It "Should preserve YAML tags through round-trip" {
        $yaml = @"
name: !!str "test-server"
port: !!int "8080"
enabled: true
"@
        # Deserialize
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify tags are captured as metadata
        $config.GetPropertyTag('Name') | Should -Be 'tag:yaml.org,2002:str'
        $config.GetPropertyTag('Port') | Should -Be 'tag:yaml.org,2002:int'

        # Serialize back
        $yaml2 = ConvertTo-Yaml $config

        # Tags should be preserved in output (with quotes preserved from original)
        $yaml2 | Should -Match 'name: !!str "test-server"'
        $yaml2 | Should -Match 'port: !!int "8080"'

        # Round-trip again to verify
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([SimpleConfig])
        $config2.GetPropertyTag('Name') | Should -Be 'tag:yaml.org,2002:str'
        $config2.GetPropertyTag('Port') | Should -Be 'tag:yaml.org,2002:int'
    }

    It "Should preserve plain (unquoted) scalar style" {
        $yaml = @"
name: test-server
port: 8080
enabled: true
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify plain style is captured
        $config.GetPropertyScalarStyle('Name') | Should -Be 'Plain'

        # Serialize back
        $yaml2 = ConvertTo-Yaml $config

        # Should remain unquoted
        $yaml2 | Should -Match 'name: test-server'
        $yaml2 | Should -Not -Match 'name: "test-server"'
        $yaml2 | Should -Not -Match "name: 'test-server'"
    }

    It "Should preserve double-quoted scalar style" {
        $yaml = @"
name: "test-server"
port: 8080
enabled: true
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify double-quoted style is captured
        $config.GetPropertyScalarStyle('Name') | Should -Be 'DoubleQuoted'

        # Serialize back
        $yaml2 = ConvertTo-Yaml $config

        # Should preserve double quotes
        $yaml2 | Should -Match 'name: "test-server"'
    }

    It "Should preserve single-quoted scalar style" {
        $yaml = @"
name: 'test-server'
port: 8080
enabled: true
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify single-quoted style is captured
        $config.GetPropertyScalarStyle('Name') | Should -Be 'SingleQuoted'

        # Serialize back
        $yaml2 = ConvertTo-Yaml $config

        # Should preserve single quotes
        $yaml2 | Should -Match "name: 'test-server'"
    }

    It "Should preserve mixed quoting styles across properties" {
        $yaml = @"
name: plain-value
port: "8080"
enabled: 'true'
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify each style is captured
        $config.GetPropertyScalarStyle('Name') | Should -Be 'Plain'
        $config.GetPropertyScalarStyle('Port') | Should -Be 'DoubleQuoted'
        $config.GetPropertyScalarStyle('Enabled') | Should -Be 'SingleQuoted'

        # Serialize back
        $yaml2 = ConvertTo-Yaml $config

        # Each style should be preserved
        $yaml2 | Should -Match 'name: plain-value'
        $yaml2 | Should -Match 'port: "8080"'
        $yaml2 | Should -Match "enabled: 'true'"
    }

    It "Should round-trip quoting styles multiple times" {
        $yaml = @"
name: "double-quoted"
port: 8080
"@
        # First round-trip
        $config1 = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])
        $yaml2 = ConvertTo-Yaml $config1

        # Second round-trip
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([SimpleConfig])
        $yaml3 = ConvertTo-Yaml $config2

        # Third round-trip
        $config3 = ConvertFrom-Yaml -Yaml $yaml3 -As ([SimpleConfig])

        # Style should still be double-quoted
        $config3.GetPropertyScalarStyle('Name') | Should -Be 'DoubleQuoted'
        $yaml4 = ConvertTo-Yaml $config3
        $yaml4 | Should -Match 'name: "double-quoted"'
    }
}

Describe "Typed YAML: ALC Isolation Verification" {
    It "Should load YamlDotNet in isolated ALC (not Default)" -Skip:(-not $IsCoreClr) {
        # Get all loaded assemblies
        $assemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()
        $yamlDotNetAsms = @($assemblies | Where-Object { $_.GetName().Name -eq 'YamlDotNet' })

        # YamlDotNet should be loaded (at least once)
        $yamlDotNetAsms.Count | Should -BeGreaterThan 0

        # Check that YamlDotNet is NOT in the Default ALC
        # With LoadFile approach, it's in an anonymous ALC (named after the file path)
        $inDefaultAlc = $false
        foreach ($asm in $yamlDotNetAsms) {
            $alc = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($asm)
            if ($alc.Name -eq 'Default') {
                $inDefaultAlc = $true
                break
            }
        }
        $inDefaultAlc | Should -BeFalse -Because "YamlDotNet should NOT be in Default ALC (should be isolated)"
    }

    It "Should load PowerShellYaml in Default ALC" {
        $assemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()
        $mainAsms = @($assemblies | Where-Object { $_.GetName().Name -eq 'PowerShellYaml' })

        $mainAsms.Count | Should -BeGreaterThan 0

        if ($IsCoreClr) {
            # Check that at least one PowerShellYaml assembly is in Default ALC
            $defaultAlcFound = $false
            foreach ($asm in $mainAsms) {
                $alc = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($asm)
                if ($alc.Name -eq 'Default') {
                    $defaultAlcFound = $true
                    break
                }
            }
            $defaultAlcFound | Should -BeTrue -Because "PowerShellYaml should be loaded in Default ALC"
        }
    }
}

Describe "Typed YAML: Style Conversion" {
    Context "Block to Flow conversion" {
        It "Should convert block style YAML to flow style" {
            # Parse block style YAML
            $blockYaml = @"
app-name: TestApp
database:
  host: db.example.com
  port: 5432
  database: test_db
  use-ssl: true
tags:
  - development
  - testing
max-connections: 100
"@
            $config = ConvertFrom-Yaml -Yaml $blockYaml -As ([ComplexConfig])

            # Convert to flow style
            $flowYaml = ConvertTo-Yaml -Data $config -Options UseFlowStyle

            # Should be in flow style (single line with curly braces)
            $flowYaml | Should -Match "^\{.*app-name:.*TestApp.*\}"
            $flowYaml | Should -Match "database:.*\{.*host:.*db\.example\.com.*\}"

            # Parse back and verify data integrity
            $roundTrip = ConvertFrom-Yaml -Yaml $flowYaml -As ([ComplexConfig])
            $roundTrip.AppName | Should -Be "TestApp"
            $roundTrip.Database.Host | Should -Be "db.example.com"
            $roundTrip.Database.Port | Should -Be 5432
            $roundTrip.Database.Database | Should -Be "test_db"
            $roundTrip.Database.UseSsl | Should -Be $true
            $roundTrip.Tags.Count | Should -Be 2
            $roundTrip.MaxConnections | Should -Be 100
        }
    }

    Context "Flow to Block conversion" {
        It "Should convert flow style YAML to block style" {
            # Parse flow style YAML
            $flowYaml = "{app-name: TestApp, database: {host: db.example.com, port: 5432, database: test_db, use-ssl: true}, tags: [development, testing], max-connections: 100}"
            $config = ConvertFrom-Yaml -Yaml $flowYaml -As ([ComplexConfig])

            # Convert to block style (need both flags for mappings and sequences)
            $blockYaml = $config | ConvertTo-Yaml -Options (512 + 1024) # UseBlockStyle + UseSequenceBlockStyle

            # Should be in block style (multi-line with proper indentation)
            $blockYaml | Should -Match "app-name:.*TestApp"
            $blockYaml | Should -Match "database:\s*\n\s+host:"
            $blockYaml | Should -Match "tags:\s*\n\s*-"

            # Parse back and verify data integrity
            $roundTrip = ConvertFrom-Yaml -Yaml $blockYaml -As ([ComplexConfig])
            $roundTrip.AppName | Should -Be "TestApp"
            $roundTrip.Database.Host | Should -Be "db.example.com"
            $roundTrip.Database.Port | Should -Be 5432
            $roundTrip.Database.Database | Should -Be "test_db"
            $roundTrip.Database.UseSsl | Should -Be $true
            $roundTrip.Tags.Count | Should -Be 2
            $roundTrip.MaxConnections | Should -Be 100
        }
    }

    Context "Sequence style conversion" {
        It "Should convert block sequences to flow sequences" {
            # Create config with arrays
            $config = [ComplexConfig]::new()
            $config.AppName = "SequenceTest"
            $config.Tags = @("tag1", "tag2", "tag3", "tag4")
            $config.MaxConnections = 50

            $db = [DatabaseConfig]::new()
            $db.Host = "localhost"
            $db.Port = 5432
            $db.Database = "testdb"
            $config.Database = $db

            # Default serialization should use block style
            $blockYaml = ConvertTo-Yaml -Data $config
            $blockYaml | Should -Match "tags:\s*\n\s*-"

            # Convert to flow style for sequences only
            $flowSeqYaml = ConvertTo-Yaml -Data $config -Options UseSequenceFlowStyle
            $flowSeqYaml | Should -Match "tags: \[tag1, tag2, tag3, tag4\]"

            # Mappings should still be block style
            $flowSeqYaml | Should -Match "database:\s*\n\s+host:"

            # Parse back and verify
            $roundTrip = ConvertFrom-Yaml -Yaml $flowSeqYaml -As ([ComplexConfig])
            $roundTrip.Tags.Count | Should -Be 4
            $roundTrip.Tags[0] | Should -Be "tag1"
        }

        It "Should convert flow sequences to block sequences" {
            # Parse YAML with flow sequences
            $flowYaml = @"
app-name: SequenceTest
database:
  host: localhost
  port: 5432
  database: testdb
  use-ssl: false
tags: [tag1, tag2, tag3, tag4]
max-connections: 50
"@
            $config = ConvertFrom-Yaml -Yaml $flowYaml -As ([ComplexConfig])

            # Convert to block style for sequences
            $blockSeqYaml = ConvertTo-Yaml -Data $config -Options UseSequenceBlockStyle

            # Sequences should be in block style
            $blockSeqYaml | Should -Match "tags:\s*\n\s*- tag1"

            # Parse back and verify
            $roundTrip = ConvertFrom-Yaml -Yaml $blockSeqYaml -As ([ComplexConfig])
            $roundTrip.Tags.Count | Should -Be 4
            $roundTrip.Tags[0] | Should -Be "tag1"
        }
    }

    Context "Nested object style conversion" {
        It "Should handle nested objects with flow style override" {
            # Create nested structure
            $config = [ComplexConfig]::new()
            $config.AppName = "NestedTest"
            $config.MaxConnections = 75
            $config.Tags = @("production")

            $db = [DatabaseConfig]::new()
            $db.Host = "prod.db.example.com"
            $db.Port = 3306
            $db.Database = "prod_db"
            $db.UseSsl = $true
            $config.Database = $db

            # Serialize with flow style
            $flowYaml = ConvertTo-Yaml -Data $config -Options UseFlowStyle

            # Both root and nested objects should be flow style
            $flowYaml | Should -Match "^\{"
            $flowYaml | Should -Match "database:.*\{.*host:.*prod\.db\.example\.com.*\}"

            # Parse back
            $roundTrip = ConvertFrom-Yaml -Yaml $flowYaml -As ([ComplexConfig])
            $roundTrip.Database.Host | Should -Be "prod.db.example.com"
            $roundTrip.Database.UseSsl | Should -Be $true

            # Now convert the same object to block style
            $blockYaml = ConvertTo-Yaml -Data $roundTrip -Options UseBlockStyle

            # Should be in block style
            $blockYaml | Should -Match "database:\s*\n\s+host:"
            $blockYaml | Should -Not -Match "^\{"

            # Parse back again
            $roundTrip2 = ConvertFrom-Yaml -Yaml $blockYaml -As ([ComplexConfig])
            $roundTrip2.Database.Host | Should -Be "prod.db.example.com"
            $roundTrip2.Database.UseSsl | Should -Be $true
        }
    }
}

Describe "Typed YAML: Real-world Scenarios" {
    It "Should handle complete application configuration" {
        $yaml = @"
app-name: ProductionApp
database:
  host: prod-db-01.example.com
  port: 5432
  database: production
  use-ssl: true
tags:
  - production
  - critical
  - monitored
max-connections: 500
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Modify for staging
        $config.AppName = 'StagingApp'
        $config.Database.Host = 'staging-db-01.example.com'
        $config.Database.Database = 'staging'
        $config.Tags = @('staging', 'test')
        $config.MaxConnections = 100

        # Serialize and verify
        $stagingYaml = ConvertTo-Yaml $config
        $stagingConfig = ConvertFrom-Yaml -Yaml $stagingYaml -As ([ComplexConfig])

        $stagingConfig.AppName | Should -Be 'StagingApp'
        $stagingConfig.Database.Host | Should -Be 'staging-db-01.example.com'
        $stagingConfig.MaxConnections | Should -Be 100
        $stagingConfig.Tags.Count | Should -Be 2
    }
}
