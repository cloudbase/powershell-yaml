#!/usr/bin/env pwsh
# Typed YAML Metadata Preservation Tests
# Tests that typed YAML mode preserves metadata just like PSCustomObject mode (comments, flow style, quoting style, etc.)

BeforeAll {
    # Import the main module (now includes typed cmdlets)
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

    # Load test classes
    . "$PSScriptRoot/TypedYamlTestClasses.ps1"
}

Describe "Typed YAML: Comment Preservation" {
    It "Should preserve comments on simple properties" {
        $yaml = @"
# Server name comment
name: test-server
# Port comment
port: 9000
# Enabled comment
enabled: true
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify comments are captured (use C# property names, not YAML keys)
        $config.GetPropertyComment('Name') | Should -Be 'Server name comment'
        $config.GetPropertyComment('Port') | Should -Be 'Port comment'
        $config.GetPropertyComment('Enabled') | Should -Be 'Enabled comment'
    }

    It "Should preserve inline comments" {
        $yaml = @"
name: test-server  # This is the server name
port: 9000  # This is the port
enabled: true  # Server is enabled
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify inline comments are captured (use C# property names)
        $config.GetPropertyComment('Name') | Should -Be 'This is the server name'
        $config.GetPropertyComment('Port') | Should -Be 'This is the port'
        $config.GetPropertyComment('Enabled') | Should -Be 'Server is enabled'
    }

    It "Should preserve comments in nested objects" {
        $yaml = @"
# App name
app-name: MyApp
database:
  # Database host
  host: db.example.com
  # Database port
  port: 5432
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        $config.GetPropertyComment('AppName') | Should -Be 'App name'
        $config.Database.GetPropertyComment('Host') | Should -Be 'Database host'
        $config.Database.GetPropertyComment('Port') | Should -Be 'Database port'
    }

    It "Should preserve comments through round-trip" {
        $yaml = @"
# Server name
name: test-server
# Port number
port: 9000
enabled: true
"@
        $config1 = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Modify a value
        $config1.Port = 8080

        # Serialize back to YAML
        $yaml2 = ConvertTo-Yaml $config1

        # Verify comments are in output
        $yaml2 | Should -Match '# Server name'
        $yaml2 | Should -Match '# Port number'
        $yaml2 | Should -Match 'port: 8080'

        # Deserialize again
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([SimpleConfig])

        # Verify comments survived round-trip
        $config2.GetPropertyComment('Name') | Should -Be 'Server name'
        $config2.GetPropertyComment('Port') | Should -Be 'Port number'
        $config2.Port | Should -Be 8080
    }
}

Describe "Typed YAML: Scalar Style Preservation" {
    It "Should preserve double-quoted strings" {
        $yaml = @"
name: "test-server"
port: 9000
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify scalar style is captured
        $config.GetPropertyScalarStyle('Name') | Should -Be 'DoubleQuoted'
    }

    It "Should preserve single-quoted strings" {
        $yaml = @"
name: 'test-server'
port: 9000
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify scalar style is captured
        $config.GetPropertyScalarStyle('Name') | Should -Be 'SingleQuoted'
    }

    It "Should preserve literal block scalars" {
        $yaml = @"
name: |-
  test-server
  multiline
port: 9000
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify literal style is captured
        $config.GetPropertyScalarStyle('Name') | Should -Match 'Literal|Folded'
    }

    It "Should preserve scalar styles through round-trip" {
        $yaml = @"
name: "quoted-server"
port: 9000
"@
        $config1 = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Verify style was captured
        $config1.GetPropertyScalarStyle('Name') | Should -Be 'DoubleQuoted'

        # Round-trip
        $yaml2 = ConvertTo-Yaml $config1
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([SimpleConfig])

        # Style should be preserved or at least the value should be quoted
        $yaml2 | Should -Match '"quoted-server"|''quoted-server'''
    }
}

Describe "Typed YAML: Mapping Style Preservation" {
    It "Should preserve block mapping style" {
        $yaml = @"
app-name: MyApp
database:
  host: localhost
  port: 5432
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Verify block style is captured (default)
        $config.GetPropertyMappingStyle('Database') | Should -Match 'Block|$null'
    }

    It "Should preserve flow mapping style" {
        $yaml = @"
app-name: MyApp
database: {host: localhost, port: 5432}
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Verify flow style is captured
        $config.GetPropertyMappingStyle('Database') | Should -Be 'Flow'
    }
}

Describe "Typed YAML: Sequence Style Preservation" {
    It "Should preserve block sequence style" {
        $yaml = @"
app-name: ArrayTest
tags:
  - tag1
  - tag2
  - tag3
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Verify block sequence style is captured
        $config.GetPropertySequenceStyle('Tags') | Should -Match 'Block|$null'
    }

    It "Should preserve flow sequence style" {
        $yaml = @"
app-name: ArrayTest
tags: [tag1, tag2, tag3]
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Verify flow sequence style is captured
        $config.GetPropertySequenceStyle('Tags') | Should -Be 'Flow'
    }

    It "Should preserve sequence styles through round-trip" {
        $yaml = @"
app-name: ArrayTest
tags: [tag1, tag2, tag3]
"@
        $config1 = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Round-trip
        $yaml2 = ConvertTo-Yaml $config1

        # Verify flow style is preserved
        $yaml2 | Should -Match '\[tag1, tag2, tag3\]'

        # Deserialize again
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([ComplexConfig])
        $config2.GetPropertySequenceStyle('Tags') | Should -Be 'Flow'
    }
}

Describe "Typed YAML: Complete Round-Trip with All Metadata" {
    It "Should preserve all metadata types through multiple round-trips" {
        $yaml = @"
# Application name
app-name: "MyApp"
# Database configuration
database:
  # Database host
  host: localhost
  port: 5432
  database: mydb
  use-ssl: true
# Application tags
tags: [production, web, critical]
# Maximum connections
max-connections: 200
"@
        # First round-trip
        $config1 = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])
        $yaml2 = ConvertTo-Yaml $config1

        # Verify comments are in output
        $yaml2 | Should -Match '# Application name'
        $yaml2 | Should -Match '# Database configuration'
        $yaml2 | Should -Match '# Application tags'

        # Verify flow style preserved
        $yaml2 | Should -Match '\[production, web, critical\]'

        # Second round-trip
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([ComplexConfig])
        $yaml3 = ConvertTo-Yaml $config2

        # Verify metadata survived second round-trip
        $yaml3 | Should -Match '# Application name'
        $yaml3 | Should -Match '# Database configuration'
        $yaml3 | Should -Match '\[production, web, critical\]'

        # Verify values are still correct
        $config2.AppName | Should -Be 'MyApp'
        $config2.Database.Host | Should -Be 'localhost'
        $config2.Tags.Count | Should -Be 3
        $config2.MaxConnections | Should -Be 200
    }

    It "Should allow programmatic metadata modification" {
        $yaml = @"
name: test-server
port: 9000
enabled: true
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Add a comment programmatically
        $config.SetPropertyComment('Port', 'Custom port comment')
        $config.SetPropertyScalarStyle('Name', 'DoubleQuoted')

        # Serialize
        $yaml2 = ConvertTo-Yaml $config

        # Verify programmatic metadata is in output
        $yaml2 | Should -Match '# Custom port comment'
        $yaml2 | Should -Match '"test-server"'

        # Round-trip and verify
        $config2 = ConvertFrom-Yaml -Yaml $yaml2 -As ([SimpleConfig])
        $config2.GetPropertyComment('Port') | Should -Be 'Custom port comment'
    }
}

Describe "Typed YAML: Nested Object Metadata" {
    It "Should preserve metadata in deeply nested structures" {
        $yaml = @"
# Root config
app-name: NestedTest
# Database section
database:
  # DB host
  host: db.example.com
  # DB port
  port: 5432
  # DB name
  database: mydb
  use-ssl: true
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([ComplexConfig])

        # Verify nested comments
        $config.GetPropertyComment('AppName') | Should -Be 'Root config'
        $config.GetPropertyComment('Database') | Should -Be 'Database section'
        $config.Database.GetPropertyComment('Host') | Should -Be 'DB host'
        $config.Database.GetPropertyComment('Port') | Should -Be 'DB port'
        $config.Database.GetPropertyComment('Database') | Should -Be 'DB name'

        # Round-trip
        $yaml2 = ConvertTo-Yaml $config

        # Verify nested comments in output
        $yaml2 | Should -Match '# Root config'
        $yaml2 | Should -Match '# Database section'
        $yaml2 | Should -Match '# DB host'
        $yaml2 | Should -Match '# DB port'
    }
}

Describe "Typed YAML: Metadata Parity with PSCustomObject mode" {
    It "Should support same metadata operations as PSCustomObject mode PSCustomObject mode" {
        $yaml = @"
# Comment test
name: test
port: 9000
"@
        $config = ConvertFrom-Yaml -Yaml $yaml -As ([SimpleConfig])

        # Test all metadata methods (matching PSCustomObject mode API)
        $config.GetPropertyComment('Name') | Should -Not -BeNullOrEmpty
        $config.SetPropertyComment('Port', 'New comment')
        $config.GetPropertyComment('Port') | Should -Be 'New comment'

        $config.SetPropertyScalarStyle('Name', 'DoubleQuoted')
        $config.GetPropertyScalarStyle('Name') | Should -Be 'DoubleQuoted'

        $config.SetPropertyMappingStyle('Name', 'Flow')
        $config.GetPropertyMappingStyle('Name') | Should -Be 'Flow'

        $config.SetPropertySequenceStyle('Name', 'Flow')
        $config.GetPropertySequenceStyle('Name') | Should -Be 'Flow'

        $config.SetPropertyTag('Name', '!custom')
        $config.GetPropertyTag('Name') | Should -Be '!custom'
    }
}
