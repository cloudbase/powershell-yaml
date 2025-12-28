#!/usr/bin/env pwsh
# Tagged Scalars Tests: Demonstrates round-tripping YAML with explicit type tags

BeforeAll {
    # Import the main module (now includes typed cmdlets)
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

    # Load test class
    . "$PSScriptRoot/TaggedScalars.ps1"
}

Describe "Tagged Scalars: Round-trip with Explicit Type Tags" {
    It "Should round-trip YAML with explicit tags on scalars" {
        # Note: PowerShell class properties are case-insensitive, so we use
        # string-value and int-value instead of Test/test
        # Tags with quoted values should convert the value AND preserve the tag+quoting
        $yaml = @"
string-value: !!str "I am a string"
int-value: !!int "22"
"@

        # Deserialize
        $obj = $yaml | ConvertFrom-Yaml -As ([TaggedScalarsTest])

        # Verify values were parsed correctly - !!int "22" should become int 22
        $obj.StringValue | Should -Be "I am a string"
        $obj.IntValue | Should -Be 22
        $obj.StringValue | Should -BeOfType [string]
        $obj.IntValue | Should -BeOfType [int]

        # Verify tags were preserved
        $obj.GetPropertyTag('StringValue') | Should -Be "tag:yaml.org,2002:str"
        $obj.GetPropertyTag('IntValue') | Should -Be "tag:yaml.org,2002:int"

        # Serialize back
        $newYaml = $obj | ConvertTo-Yaml

        # Verify tags are in output
        $newYaml | Should -Match "string-value: !!str"
        $newYaml | Should -Match "int-value: !!int"

        # Verify values are preserved with quoting
        # The original had !!int "22" (quoted), so it should serialize back the same way
        $newYaml | Should -Match 'string-value: !!str "I am a string"'
        $newYaml | Should -Match 'int-value: !!int "22"'
    }

    It "Should handle untagged values and infer types" {
        # YAML without explicit tags
        $yaml = @"
string-value: normal string
int-value: 42
"@

        $obj = $yaml | ConvertFrom-Yaml -As ([TaggedScalarsTest])

        # Values should be converted to correct types
        $obj.StringValue | Should -Be "normal string"
        $obj.IntValue | Should -Be 42
        $obj.IntValue | Should -BeOfType [int]

        # No tags initially (parsed without tags)
        $obj.GetPropertyTag('IntValue') | Should -BeNullOrEmpty

        # Set tags explicitly
        $obj.SetPropertyTag('StringValue', 'tag:yaml.org,2002:str')
        $obj.SetPropertyTag('IntValue', 'tag:yaml.org,2002:int')

        # Now serialize with tags
        $newYaml = $obj | ConvertTo-Yaml
        $newYaml | Should -Match "string-value: !!str"
        $newYaml | Should -Match "int-value: !!int 42"
    }

    It "Should preserve tags when explicitly set" {
        $obj = [TaggedScalarsTest]::new()
        $obj.StringValue = "Hello World"
        $obj.IntValue = 100

        # Set explicit tags
        $obj.SetPropertyTag('StringValue', 'tag:yaml.org,2002:str')
        $obj.SetPropertyTag('IntValue', 'tag:yaml.org,2002:int')

        # Serialize
        $yaml = $obj | ConvertTo-Yaml

        # Should have both properties with correct tags
        $yaml | Should -Match "string-value: !!str"
        $yaml | Should -Match "int-value: !!int"

        # Deserialize back
        $obj2 = $yaml | ConvertFrom-Yaml -As ([TaggedScalarsTest])

        # Values should match
        $obj2.StringValue | Should -Be "Hello World"
        $obj2.IntValue | Should -Be 100

        # Tags should be preserved
        $obj2.GetPropertyTag('StringValue') | Should -Be "tag:yaml.org,2002:str"
        $obj2.GetPropertyTag('IntValue') | Should -Be "tag:yaml.org,2002:int"
    }
}
